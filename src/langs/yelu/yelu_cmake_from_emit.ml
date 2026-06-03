(* Reverse pass: Lang_cmake.exp -> yelu_cmake.expr.

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

   SCOPE (Day 1, minimal first cut).
     Modeled: Set, Set_cache, Unset, Set_env, Unset_env,
     Cmake_option, Cmake_minimum_required, Project, Message,
     Include, Apply (no-op).

     If: minimal support — single-token / NOT / STREQUAL /
     DEFINED / TARGET. Complex multi-clause conds bail to
     "always true" (then-branch evaluates).

   DEFERRED.
     Foreach, add_library, add_executable, target_* family,
     install, set_target_properties, set_property,
     configure_file, find_program, file commands. Each maps to
     EUnit (no-op for eval). yc-eval will run but its
     predicted cache will be missing entries these commands
     would have populated; the diff against real cmake
     captures the gap.

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

let e_var_defined s : Yelu_cmake.expr =
  Yelu_cmake_store.ECmakeVarDefined s
let e_target_exists e : Yelu_cmake.expr =
  Yelu_cmake_target.ECmakeTargetExists e

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
let unwrap_var_ref s : string option =
  let n = String.length s in
  if n >= 4
     && Char.equal s.[0] '$' && Char.equal s.[1] '{'
     && Char.equal s.[n - 1] '}'
     (* No nested ${ inside — corner case deferred *)
     && not (String.is_substring
              (String.sub s ~pos:2 ~len:(n - 3))
              ~substring:"${")
  then Some (String.sub s ~pos:2 ~len:(n - 3))
  else None

let arg_to_expr (a : C.arg) : Yelu_cmake.expr =
  match a with
  | C.Bare s | C.Quoted s | C.Bracket (_, s) ->
    (match unwrap_var_ref s with
     | Some name -> e_var name
     | None -> e_str s)

let args_to_exprs args = List.map args ~f:arg_to_expr

(* ============================================================
   cond-token -> expr.
   Bare identifier "FOO" treated as ${FOO} (EVar lookup).
   Quoted "literal" -> EString.
   TRUE/ON/YES/1 -> EBool true; FALSE/OFF/NO/0/N/IGNORE/NOTFOUND -> EBool false.
   Numeric -> EInt. *)
let cond_token_to_expr (s : string) : Yelu_cmake.expr =
  let n = String.length s in
  if n >= 2 && Char.equal s.[0] '"' && Char.equal s.[n - 1] '"' then
    e_str (String.sub s ~pos:1 ~len:(n - 2))
  else begin
    match s with
    | "TRUE" | "ON" | "YES" | "Y" | "1" -> e_bool true
    | "FALSE" | "OFF" | "NO" | "N" | "0" | "IGNORE" | "NOTFOUND" ->
      e_bool false
    | _ ->
      (match Int.of_string_opt s with
       | Some i -> e_int i
       | None -> e_var s)
  end

(* ============================================================
   Cond parser: token list -> yc cond expr.
   Recursive descent. Handles:
     <atom> | NOT <expr> | DEFINED name | TARGET name |
     <l> STREQUAL <r> | <l> EQUAL/LESS/GREATER <r> |
     paren-balanced AND/OR.
   Unrecognized shapes -> EBool true (safe direction; yc-eval
   will execute the then-branch, over-populating the predicted
   cache rather than under-populating). *)
let bridge_warn what =
  Stdlib.Printf.eprintf "yelu_cmake_from_emit: bridging %s -> default\n" what

let rec parse_cond_tokens (toks : string list) : Yelu_cmake.expr =
  let toks =
    match toks with
    | "(" :: rest ->
      (match List.rev rest with
       | ")" :: rev_rest -> List.rev rev_rest
       | _ -> toks)
    | _ -> toks
  in
  let split_top_kw toks kw =
    let rec loop depth acc = function
      | [] -> None
      | "(" :: rest -> loop (depth + 1) ("(" :: acc) rest
      | ")" :: rest -> loop (depth - 1) (")" :: acc) rest
      | tok :: rest when depth = 0 && String.equal tok kw ->
        Some (List.rev acc, rest)
      | tok :: rest -> loop depth (tok :: acc) rest
    in
    loop 0 [] toks
  in
  match split_top_kw toks "AND" with
  | Some (l, r) -> e_and (parse_cond_tokens l) (parse_cond_tokens r)
  | None ->
    begin match split_top_kw toks "OR" with
    | Some (l, r) -> e_or (parse_cond_tokens l) (parse_cond_tokens r)
    | None ->
      begin match toks with
      | [] -> e_bool true
      | [ x ] -> cond_token_to_expr x
      | [ "NOT"; x ] -> e_not (cond_token_to_expr x)
      | "NOT" :: rest -> e_not (parse_cond_tokens rest)
      | [ "DEFINED"; name ] -> e_var_defined name
      | [ "TARGET"; name ] -> e_target_exists (cond_token_to_expr name)
      | [ l; "STREQUAL"; r ] ->
        e_streq (cond_token_to_expr l) (cond_token_to_expr r)
      | [ l; "EQUAL"; r ] ->
        e_int_eq (cond_token_to_expr l) (cond_token_to_expr r)
      | [ l; "LESS"; r ] ->
        e_int_less (cond_token_to_expr l) (cond_token_to_expr r)
      | [ l; "GREATER"; r ] ->
        e_int_gt (cond_token_to_expr l) (cond_token_to_expr r)
      | _ ->
        bridge_warn
          (Printf.sprintf "cond[%s]" (String.concat ~sep:" " toks));
        e_bool true
      end
    end

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
       - "${X}" wrapping → variable lookup (e_var "X")
       - bare cmake bool literal (ON/OFF/TRUE/...) → e_bool
       - anything else → e_var (treats as variable name; if
         unbound at eval time, EVar returns VString "" per
         the cmake-compatible rule). *)
    let n = String.length s in
    if n >= 3
       && Char.equal s.[0] '$' && Char.equal s.[1] '{'
       && Char.equal s.[n - 1] '}'
    then e_var (String.sub s ~pos:2 ~len:(n - 3))
    else begin match s with
      | "ON" | "TRUE" | "YES" | "Y" | "1" -> e_bool true
      | "OFF" | "FALSE" | "NO" | "N" | "0" | "IGNORE" | "NOTFOUND" ->
        e_bool false
      | _ -> e_var s
    end
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

  (* Generic fallback: Apply (unmodeled command call) becomes a
     no-op for eval. Real cmake's behavior is missing from the
     predicted cache; the diff captures the gap. *)
  | C.Apply { name; args = _ } ->
    bridge_warn (Printf.sprintf "Apply(%s)" name);
    e_unit

  | _ ->
    (* Deferred (foreach / add_library / target_* / install /
       configure_file / find_program / file / set_target_properties /
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
