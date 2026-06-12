(* [tool-interface]
   node:     yc
   op:       parse ← cmake AST
   strategy: code
   exports:  from_emit_top : Lang_cmake.exp → Yelu_cmake.expr
   imports:  Lang_cmake (typed cmd AST), Yelu_cmake,
             Cmake_text_parse (per-command parsers)
   ─────────

   Reverse pass: Lang_cmake.exp -> yelu_cmake.expr.

   This is the inverse of yelu_cmake_emit.ml. yelu_cmake_emit
   goes yc -> Lang_cmake.exp (the cmake-syntax AST); from_emit
   goes Lang_cmake.exp -> yc. Together they form an "almost"
   roundtrip: from_emit ∘ to_emit ≡ id modulo lossy-emit cases.

   PURPOSE. Lets yc-eval ingest cmake text from real projects:
     cmake text → parse.py → Stage-1 JSON
       → print2's parse_cmd → Lang_cmake.exp
         → from_emit          → yelu_cmake.expr   [this module]
           → eval_yelu_cmake_expr → predicted env

   The bridge enables a "real cmake vs yc-eval" diff on actual
   projects (fmt is the first target) without hand-translating
   each program.

   SCOPE (updated 2026-06-03 — fmt-matrix complete).
     Modeled:
       Store     : Set / Set_cache / Unset / Set_env / Unset_env
                 / Cmake_option / Set_parent_scope
       Cond      : full recursive-descent — NOT / AND / OR / DEFINED
                 / TARGET / STREQUAL / EQUAL / LESS / GREATER
                 / LESS_EQUAL / GREATER_EQUAL / VERSION_LESS / GREATER
                 / EQUAL / LESS_EQUAL / GREATER_EQUAL
                 / MATCHES / IN_LIST / EXISTS / COMMAND / IS_ABSOLUTE
       Control   : If / Return / Function / Macro / Apply (Apply is
                   the lenient fallback for unmodeled cmds + user-defined
                   dispatch via env.functions)
       I/O       : Include (via include_loader) / Add_subdirectory
                   (via subdir_loader)
       Find/Try  : Find_program / Find_path / Find_library / Find_file
                   (stub: <OUT>-NOTFOUND to var + cache);
                   Find_package (stub: bookkeeping + whitelist;
                   see assumed_found_packages in yelu_cmake_find.ml);
                   Try_compile (stub: result=FALSE to var + cache)
       Misc      : Cmake_minimum_required / Project / Message

   DEFERRED. Each maps to EUnit (no-op for eval); diff against
   real cmake captures the gap.
     - Foreach, While, Break, Continue, Block
     - Add_executable / Add_library / Target_* family
     - Install rules (Install_targets, Install_files, etc.)
     - Set_target_properties / Set_property / Get_property
     - File commands (file(READ/WRITE/STRINGS/GLOB/...))
     - Configure_file
     - Execute_process (partial — result_variable set to "0")
     - Try_run
     - Custom commands / Custom targets
     - $<…> generator expressions (resolved at cmake's generate
       phase, after our prediction window)

   IMPLEMENTATION NOTE.
     The extensible-variant ctors of [yelu_cmake.expr] need
     fully-qualified module paths at construction sites
     (OCaml inference can't disambiguate which extension
     contributes a ctor at use). Helpers wrap each ctor
     with a fully-qualified path; same convention as
     [yelu_cmake_utils.ml]. *)

open Base
module C = Lang_cmake

(* ============================================================
   Helpers — fully-qualified extensible-variant ctors. *)

let e_bool b : Yelu_cmake.expr = Yelu_cmake.EBool b
let e_int i  : Yelu_cmake.expr = Yelu_cmake.EInt i
let e_str s  : Yelu_cmake.expr = Yelu_cmake.EString s
let e_var v  : Yelu_cmake.expr = Yelu_cmake.EVar v
let e_varlookup name : Yelu_cmake.expr =
  Yelu_cmake.EVarLookup (Yelu_cmake.EString name)
let e_unit   : Yelu_cmake.expr = Yelu_cmake.EUnit
let e_seq xs : Yelu_cmake.expr = Yelu_cmake.ESeq xs
let e_set_var v body : Yelu_cmake.expr = Yelu_cmake.ESetVar (v, body)
let e_list xs : Yelu_cmake.expr = Yelu_cmake_normal_list.EList xs

let e_not a    : Yelu_cmake.expr = Yelu_cmake_normal_bool.ENot a
let e_and a b  : Yelu_cmake.expr = Yelu_cmake_normal_bool.EAnd (a, b)
let e_or a b   : Yelu_cmake.expr = Yelu_cmake_normal_bool.EOr  (a, b)

let e_streq a b : Yelu_cmake.expr =
  Yelu_cmake_string.ECmakeStringEqual (a, b)
let e_int_eq a b : Yelu_cmake.expr =
  Yelu_cmake_normal_int.EIntEqual (a, b)
let e_int_less a b : Yelu_cmake.expr =
  Yelu_cmake_normal_int.EIntLess (a, b)
let e_int_gt a b : Yelu_cmake.expr =
  Yelu_cmake_normal_int.EIntGreater (a, b)
let e_int_leq a b : Yelu_cmake.expr =
  Yelu_cmake_normal_int.EIntLessEqual (a, b)
let e_int_geq a b : Yelu_cmake.expr =
  Yelu_cmake_normal_int.EIntGreaterEqual (a, b)

let e_ver_less a b : Yelu_cmake.expr =
  Yelu_cmake_string.ECmakeVersionLess (a, b)
let e_ver_gt a b : Yelu_cmake.expr =
  Yelu_cmake_string.ECmakeVersionGreater (a, b)
let e_ver_eq a b : Yelu_cmake.expr =
  Yelu_cmake_string.ECmakeVersionEqual (a, b)
let e_ver_leq a b : Yelu_cmake.expr =
  Yelu_cmake_string.ECmakeVersionLessEqual (a, b)
let e_ver_geq a b : Yelu_cmake.expr =
  Yelu_cmake_string.ECmakeVersionGreaterEqual (a, b)

let e_matches expr_ regex : Yelu_cmake.expr =
  Yelu_cmake_string.ECmakeMatches { expr_; regex }
let e_in_list item list_ : Yelu_cmake.expr =
  Yelu_cmake_string.ECmakeInList { item; list_ }

let e_var_defined s : Yelu_cmake.expr =
  Yelu_cmake_store.ECmakeVarDefined s
let e_target_exists e : Yelu_cmake.expr =
  Yelu_cmake_target.ECmakeTargetExists e
let e_file_exists e : Yelu_cmake.expr =
  Yelu_cmake_file.ECmakeFileExists e
let e_is_absolute e : Yelu_cmake.expr =
  Yelu_cmake_string.ECmakeIsAbsolute e
let e_command_defined e : Yelu_cmake.expr =
  Yelu_cmake_cmake_op.ECmakeCommandDefined e

let e_unset_var s : Yelu_cmake.expr = Yelu_cmake_store.ECmakeUnsetVar s
let e_unset_var_cache s : Yelu_cmake.expr =
  Yelu_cmake_store.ECmakeUnsetVarCache s
let e_set_env name value : Yelu_cmake.expr =
  Yelu_cmake_store.ECmakeSetEnvVar { name; value }
let e_unset_env name : Yelu_cmake.expr =
  Yelu_cmake_store.ECmakeUnsetEnvVar name
let e_set_parent_scope name value : Yelu_cmake.expr =
  Yelu_cmake_store.ECmakeSetParentScope { name; value }
let e_option name message value : Yelu_cmake.expr =
  Yelu_cmake_store.ECmakeOption { name; message; value }
let e_set_cache name values cache_type docstring force : Yelu_cmake.expr =
  Yelu_cmake_store.ECmakeSetCache { name; values; cache_type; docstring; force }

let e_minimum_required s : Yelu_cmake.expr =
  Yelu_cmake_cmake_op.ECmakeMinimumRequired s
let e_project name languages version : Yelu_cmake.expr =
  Yelu_cmake_cmake_op.ECmakeProject { name; languages; version }
let e_message mode texts : Yelu_cmake.expr =
  Yelu_cmake_cmake_op.ECmakeMessage { mode; texts }
let e_include file optional : Yelu_cmake.expr =
  Yelu_cmake_cmake_op.ECmakeInclude { file; optional }
let e_if cond then_ else_ : Yelu_cmake.expr =
  Yelu_cmake_if.ECmakeIfStmt { cond; then_; else_ }

(* ============================================================
   Argument helpers: C.arg -> expr. *)

(* Detect a whole-string [${IDENT}] wrapping; return the inner
   name. Matches the cond-token unwrapping below — same helper
   could be shared.

   QUICK CASE: this handles the common pattern where an arg or
   value is exactly [${X}] — converted to e_var "X" so eval-time
   variable lookup happens. DEFERRED CORNERS (treated as literal
   string, may diverge from cmake at the diff layer):
   - nested [${${prefix}_X}]
   - mid-string [prefix${X}suffix]
   - list expansion (cmake expands ${LIST} to multiple args)
   - escapes [\${X}]
   - [@VAR@] (configure_file substitution)
   - generator expressions [$<...>] (generate-time, separate phase)
   Each surfaces as a diff entry in the matrix smoke when it
   bites; close in its own commit when it does. *)
let arg_to_expr (a : C.arg) : Yelu_cmake.expr =
  match a with
  (* The cmake quote bit IS the quoted/unquoted distinction: an *unquoted*
     `${X}` is a first-class expansion (EVarLookup, splits); a *quoted*
     `"${X}"` is a string value (EString, no split). This is where the bit
     comes *from* cmake. A bare non-`${...}` token (PUBLIC, a literal) is a
     string. Mixed/nested `${...}` falls through parse_var_lookup → EString
     (the deferred corner). *)
  | C.Bare s ->
    (match Yelu_cmake.parse_var_lookup s with Some e -> e | None -> e_str s)
  | C.Quoted s | C.Bracket (_, s) -> e_str s

let args_to_exprs args = List.map args ~f:arg_to_expr

(* ============================================================
   cmake bool-literal recognition — ONE place, two callers.

   Background. cmake's actual semantic model is "everything is a
   string; bool coercion is a viewing rule applied at consume
   sites" (see yelu_cmake.ml's expect_bool). So `set(X On)` stores
   the literal "On" and `if(X)` later coerces that string. We
   *could* model this purely on the eval side and never produce
   EBool at parse time.

   We don't, because two parse-time positions are unambiguously
   constants in cmake's grammar:
     1. inside if() conditions — bare ON/OFF/etc. are bool atoms,
        not variable references (cmake doc, "Constants").
     2. cmake's parse_cmd-known-bool slots that surface here as
        C.Var_exp (option() defaults, etc.)

   Case-insensitive (cmake source freely uses On/On/yes/etc).
   Predicate-style API (returns None on non-bool) so the caller
   decides the fallback for non-bool tokens.

   FUTURE (Y17 typing redesign): collapse this into eval-side
   expect_bool only. See doc/yelu_cmake/io_architecture.md §
   "Bool literals — parse-time vs eval-time" for the migration
   path. Until then, this is the single source of truth for
   parse-time cmake bool literals. *)
(* ============================================================
   cond-token -> expr.
   Bare identifier "FOO" treated as ${FOO} (EVar lookup).
   Quoted "literal" -> EString.
   Bool literal (case-insensitive) -> EBool via [Yelu_cmake.bool_literal_of_string].
   Numeric -> EInt. *)
let cond_token_to_expr (s : string) : Yelu_cmake.expr =
  let n = String.length s in
  if n >= 2 && Char.equal s.[0] '"' && Char.equal s.[n - 1] '"' then
    e_str (String.sub s ~pos:1 ~len:(n - 2))
  else
    match Yelu_cmake.bool_literal_of_string s with
    | Some e -> e
    | None ->
      (match Int.of_string_opt s with
       | Some i -> e_int i
       | None -> e_var s)

(* ============================================================
   Cond parser: token list -> yc cond expr.

   Proper recursive descent. Grammar (cmake precedence —
   OR loosest, AND next, NOT, then comparison binaries, then atoms):

     or    := and  ("OR"  and)*
     and   := not  ("AND" not)*
     not   := "NOT" not | atom
     atom  := "(" or ")" | unary | binary | <token>
     unary := "DEFINED" <token> | "TARGET" <token>
            | "EXISTS" <token> | "COMMAND" <token>
            | "IS_ABSOLUTE" <token>
     binary:= <token> OP <token>
               where OP ∈ STREQUAL | EQUAL | LESS | GREATER
                        | LESS_EQUAL | GREATER_EQUAL
                        | VERSION_LESS | VERSION_GREATER | VERSION_EQUAL
                        | VERSION_LESS_EQUAL | VERSION_GREATER_EQUAL
                        | MATCHES | IN_LIST

   Parens consumed naturally in `atom` — no preprocessing.
   Anything we can't parse falls back to EBool true (safe direction;
   yc-eval will execute the then-branch, over-populating the
   predicted cache rather than under-populating). *)
let bridge_warn what =
  Stdlib.Printf.eprintf "yelu_cmake_from_emit: bridging %s -> default\n" what

let is_binary_op = function
  | "STREQUAL" | "EQUAL" | "LESS" | "GREATER"
  | "LESS_EQUAL" | "GREATER_EQUAL"
  | "VERSION_LESS" | "VERSION_GREATER" | "VERSION_EQUAL"
  | "VERSION_LESS_EQUAL" | "VERSION_GREATER_EQUAL"
  | "MATCHES" | "IN_LIST" -> true
  | _ -> false

let build_binary op l r : Yelu_cmake.expr =
  let le = cond_token_to_expr l in
  let re = cond_token_to_expr r in
  match op with
  | "STREQUAL" -> e_streq le re
  | "EQUAL" -> e_int_eq le re
  | "LESS" -> e_int_less le re
  | "GREATER" -> e_int_gt le re
  | "LESS_EQUAL" -> e_int_leq le re
  | "GREATER_EQUAL" -> e_int_geq le re
  | "VERSION_LESS" -> e_ver_less le re
  | "VERSION_GREATER" -> e_ver_gt le re
  | "VERSION_EQUAL" -> e_ver_eq le re
  | "VERSION_LESS_EQUAL" -> e_ver_leq le re
  | "VERSION_GREATER_EQUAL" -> e_ver_geq le re
  | "MATCHES" -> e_matches le r  (* regex is raw string, not expr *)
  | "IN_LIST" -> e_in_list le re
  | _ -> assert false

let parse_cond_tokens (toks : string list) : Yelu_cmake.expr =
  let cur = ref toks in
  let peek () = match !cur with [] -> None | h :: _ -> Some h in
  let advance () = match !cur with [] -> () | _ :: t -> cur := t in
  let rec parse_or () =
    let left = parse_and () in
    match peek () with
    | Some "OR" -> advance (); let right = parse_or () in e_or left right
    | _ -> left
  and parse_and () =
    let left = parse_not () in
    match peek () with
    | Some "AND" -> advance (); let right = parse_and () in e_and left right
    | _ -> left
  and parse_not () =
    match peek () with
    | Some "NOT" -> advance (); e_not (parse_not ())
    | _ -> parse_atom ()
  and parse_atom () =
    match !cur with
    | "(" :: rest ->
      cur := rest;
      let inner = parse_or () in
      (match peek () with
       | Some ")" -> advance (); inner
       | _ -> inner  (* unbalanced — keep what we have *))
    | "DEFINED" :: name :: rest -> cur := rest; e_var_defined name
    | "TARGET" :: name :: rest ->
      cur := rest; e_target_exists (cond_token_to_expr name)
    | "EXISTS" :: path :: rest ->
      cur := rest; e_file_exists (cond_token_to_expr path)
    | "COMMAND" :: name :: rest ->
      cur := rest; e_command_defined (cond_token_to_expr name)
    | "IS_ABSOLUTE" :: path :: rest ->
      cur := rest; e_is_absolute (cond_token_to_expr path)
    | l :: op :: r :: rest when is_binary_op op ->
      cur := rest; build_binary op l r
    | x :: rest -> cur := rest; cond_token_to_expr x
    | [] -> e_bool true
  in
  let result = parse_or () in
  (match !cur with
   | [] -> ()
   | leftover ->
     bridge_warn
       (Printf.sprintf "cond[%s] (leftover: %s)"
          (String.concat ~sep:" " toks)
          (String.concat ~sep:" " leftover)));
  result

(* ============================================================
   Cmake version / mode / cache_type -> string. *)

let version_to_string (v : C.version) =
  Printf.sprintf "%d.%d" v.major v.minor
  ^ (if String.is_empty v.patch then "" else "." ^ v.patch)

let message_mode_to_string : C.message_mode -> string = function
  | C.Mm_fatal_error -> "FATAL_ERROR"
  | C.Mm_send_error -> "SEND_ERROR"
  | C.Mm_warning -> "WARNING"
  | C.Mm_author_warning -> "AUTHOR_WARNING"
  | C.Mm_deprecation -> "DEPRECATION"
  | C.Mm_notice -> "NOTICE"
  | C.Mm_status -> "STATUS"
  | C.Mm_verbose -> "VERBOSE"
  | C.Mm_debug -> "DEBUG"
  | C.Mm_trace -> "TRACE"
  | C.Mm_check_start -> "CHECK_START"
  | C.Mm_check_pass -> "CHECK_PASS"
  | C.Mm_check_fail -> "CHECK_FAIL"
  | C.Mm_none -> "STATUS"

(* cache_type used to be an enum (C.cache_type). As of 2026-06-03
   it's a raw string carried verbatim through parse → IR → emit.
   The cache_type_to_string conversion is now identity; removed. *)

(* ============================================================
   Main bridge. *)

let rec from_emit (e : C.exp) : Yelu_cmake.expr =
  match e with
  (* Literal-shaped exps: these come from parse_cmd's per-command
     parsers when the cmake source uses a bare value as a slot
     position (option() default, version arg, etc.). *)
  | C.Bool b -> e_bool b
  | C.Var_exp s ->
    (* Var_exp captures a "${VAR}"-shaped arg OR a bare cmake
       identifier slot — parse_cmd doesn't distinguish them at
       parse time. We recover the intent here:
       - "${X}" (pure, incl. nested) → first-class expansion (EVarLookup)
       - bare cmake bool literal (ON/OFF/TRUE/...) → e_bool
       - anything else → e_var (a variable *name* slot; if unbound at
         eval time, EVar returns VString "" per the cmake-compatible rule). *)
    (match Yelu_cmake.parse_var_lookup s with
     | Some e -> e
     | None ->
      (match Yelu_cmake.bool_literal_of_string s with
       | Some e -> e
       | None -> e_var s))
  | C.Quote s -> e_str s

  (* Store *)
  | C.Set { var; values; parent_scope } ->
    let value =
      match values with
      | []  -> e_str ""
      | [v] -> arg_to_expr v
      | vs  -> e_list (args_to_exprs vs)
    in
    if parent_scope then e_set_parent_scope var value
    else e_set_var var value
  | C.Unset { var; cache; parent_scope = _ } ->
    if cache then e_unset_var_cache var else e_unset_var var
  | C.Set_env { var; value } -> e_set_env var (arg_to_expr value)
  | C.Unset_env { var } -> e_unset_env var
  | C.Cmake_option { var; msg; value } ->
    e_option var msg (arg_to_expr value)
  (* parse_cmd's parse_option produces C.Option (a SEPARATE ctor from
     C.Cmake_option). They differ in value type: Option's value is an
     exp (could be Bool, Var_exp, Quote, etc.); Cmake_option's is an
     arg. We bridge both. Value is recursively from_emit'd so
     ${FMT_MASTER_PROJECT} → EVar "FMT_MASTER_PROJECT" works at
     eval time (looks up the var, picks up its actual bool). *)
  | C.Option { var; help_text; value } ->
    e_option var (String.concat ~sep:" " help_text) (from_emit value)
  | C.Set_cache { var; values; cache_type; docstring; force } ->
    (* cache_type now a raw string (no enum conversion). *)
    e_set_cache var (args_to_exprs values) cache_type docstring force

  (* Control flow *)
  | C.If { cond; then_; else_ } ->
    e_if (parse_cond_tokens cond)
      (from_emit then_)
      (Option.map else_ ~f:from_emit)

  (* cmake_op *)
  | C.Cmake_cmd (C.Cmake_minimum_required { min; _ }) ->
    e_minimum_required (version_to_string min)
  | C.Project_cmd (C.Project { name; languages; version; _ }) ->
    e_project name languages
      (Option.map version ~f:version_to_string)
  | C.Message { mode; texts } ->
    e_message (message_mode_to_string mode)
      (List.map texts ~f:e_str)
  | C.Include { file; optional; _ } ->
    e_include (arg_to_expr file) optional
  | C.Project_cmd (C.Add_subdirectory { source_dir; _ }) ->
    Yelu_cmake_normal_dir.EAddSubdirectory (e_str source_dir)

  (* find_program / find_path / find_library / find_file — all the
     same shape (find_var_args). out=var, names/paths/hints all carry
     args. Eval stub assumes NOTFOUND and writes both var and cache. *)
  | C.Find_program { var; names; paths; hints; required; _ } ->
    Yelu_cmake_find.ECmakeFindProgram
      { out = var;
        names = args_to_exprs names;
        paths = args_to_exprs paths;
        hints = args_to_exprs hints;
        required }
  | C.Find_path { var; names; paths; hints; required; _ } ->
    Yelu_cmake_find.ECmakeFindPath
      { out = var;
        names = args_to_exprs names;
        paths = args_to_exprs paths;
        hints = args_to_exprs hints;
        required }
  | C.Find_library { var; names; paths; hints; required; _ } ->
    Yelu_cmake_find.ECmakeFindLibrary
      { out = var;
        names = args_to_exprs names;
        paths = args_to_exprs paths;
        hints = args_to_exprs hints;
        required }
  | C.Find_file { var; names; paths; hints; required; _ } ->
    Yelu_cmake_find.ECmakeFindFile
      { out = var;
        names = args_to_exprs names;
        paths = args_to_exprs paths;
        hints = args_to_exprs hints;
        required }
  | C.Find_package
      { name; version; exact; quiet; config_mode; required;
        components; optional_components } ->
    Yelu_cmake_find.ECmakeFindPackage
      { package_name = name; version; exact; quiet; config_mode;
        required; components; optional_components }
  | C.Return { propogate_vars } ->
    Yelu_cmake_cmake_op.ECmakeReturn { propagate_vars = propogate_vars }
  | C.Project_cmd (C.Try_compile tc) ->
    Yelu_cmake_try.ECmakeTryCompileEx
      { result_var = tc.tc_result_var;
        sources = args_to_exprs tc.tc_sources;
        compile_definitions = args_to_exprs tc.tc_compile_definitions;
        link_libraries = args_to_exprs tc.tc_link_libraries;
        link_options = args_to_exprs tc.tc_link_options;
        output_variable = tc.tc_output_variable;
        no_cache = tc.tc_no_cache;
        c_standard = tc.tc_c_standard;
        cxx_standard = tc.tc_cxx_standard }

  (* Generic fallback: Apply (unmodeled command call) becomes a
     no-op for eval. Real cmake's behavior is missing from the
     predicted cache; the diff captures the gap. *)
  | C.Apply { name; args = _ } ->
    bridge_warn (Printf.sprintf "Apply(%s)" name);
    e_unit

  | _ ->
    (* Deferred — see the SCOPE.DEFERRED list at the top of this
       file. Foreach / add_library / target_* / install / configure_file
       / file / set_target_properties /
       set_property / etc.). Same no-op as Apply. *)
    e_unit

and from_emit_exp_list (es : C.exp list) : Yelu_cmake.expr =
  match es with
  | []  -> e_unit
  | [e] -> from_emit e
  | _   -> e_seq (List.map es ~f:from_emit)

(* Ingest a list of top-level cmake stmts (the shape parse.py +
   print2 produce). Wraps in ESeq for sequential eval. *)
let from_emit_top (stmts : C.exp list) : Yelu_cmake.expr =
  e_seq (List.map stmts ~f:from_emit)
