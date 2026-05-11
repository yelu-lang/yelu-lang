(* Phase 1 of retirement: lower Yelu1 IR to Lang_cmake.exp (the cmake
   syntax AST), then let the existing [lang_cmake_pp] render to text.
   See [doc/yelu_tiny/retirement_plan.md] for context.

   This module exists alongside [yelu_tiny_cmake_emit.ml] (the direct-
   text emit). Phase 1 closes coverage here until parity is reached;
   then the direct-text emit is demoted to a diagnostic / diff aid. *)

open Base
open Yelu_tiny
open Yelu_surface_cmake_store
open Yelu_theory_bool
open Yelu_theory_int
open Yelu_theory_list
open Yelu_surface_cmake_list
open Yelu_surface_cmake_file
open Yelu_surface_cmake_string
open Yelu_surface_cmake_target
open Yelu_surface_cmake_if
open Yelu_surface_cmake_cmake_op
open Yelu_surface_cmake_dir
open Yelu_surface_cmake_test
open Yelu_theory_target

(* Many other surface modules are opened transitively via [expr] match
   arms as Phase 1.3 expands coverage; keep [open]s narrow for now to
   avoid unused-open warnings. *)

module C = Lang_cmake

(* ========================================================================
   Erasure helpers — Yelu1 expr → cmake AST positional shapes.

   Four distinct erasures are needed; each gets its own helper:

   1. expr → C.arg              for command-arg positions (Bare/Quoted/Bracket)
   2. expr → string             for target / cvar / file-name positions
   3. bool expr → C.cond        for if-conditions (flat token list)
   4. ELet substitution         threaded through 1/2/3 via [subst]
   ======================================================================== *)

type subst = expr Map.M(String).t

let empty_subst : subst = Map.empty (module String)

(* Mirror [lang_yelu_compile.erase_arg]'s quoting policy: quote when cmake
   would otherwise mis-tokenize (empty / whitespace / genex / backslash);
   keep bare otherwise. EVar resolves through subst lazily; unresolved
   EVar renders as ${name} (cmake deref). *)
let rec arg ?(env = empty_subst) (e : expr) : C.arg =
  match e with
  | EVar name ->
    (match Map.find env name with
     | Some replacement -> arg ~env replacement
     | None -> C.Bare ("${" ^ name ^ "}"))
  | EString s ->
    (* Quoting policy mirrors legacy [lang_yelu_compile.erase_arg]: quote
       when cmake would otherwise mis-tokenize. The ${...} substring rule
       matches the legacy [Ycs_eval] case (configure-time deref forms are
       always quoted in arg position; cond position is different and
       handled by [cond_text]). *)
    if String.is_empty s
    || String.exists s ~f:Char.is_whitespace
    || String.is_substring s ~substring:"$<"
    || String.is_substring s ~substring:"${"
    || String.exists s ~f:(Char.equal '\\')
    then C.Quoted s
    else C.Bare s
  | EInt n -> C.Bare (Int.to_string n)
  | EBool true -> C.Bare "ON"
  | EBool false -> C.Bare "OFF"
  | ETarget name -> C.Bare name
  | _ -> fail "emit_ast: cannot erase expression to cmake arg"

(* Target / cvar / file-name positions: cmake convention is unquoted
   identifier. Resolve via subst; unresolved EVar renders as ${name}. *)
let rec target_arg ?(env = empty_subst) (e : expr) : string =
  match e with
  | EVar name ->
    (match Map.find env name with
     | Some replacement -> target_arg ~env replacement
     | None -> "${" ^ name ^ "}")
  | EString s -> s
  | ETarget name -> name
  | _ -> fail "emit_ast: cannot erase expression to target name"

(* Tokens for cond-position rendering. cmake [cond = string list] composes
   into the parenthesized argument list of [if(...)]. Token rendering
   mirrors the legacy [lang_yelu_compile.cmake_quote_cond] policy: emit
   bare names (cmake's if() auto-derefs unquoted identifiers), quote only
   when the value has whitespace / parens / ${} / etc. *)
let quote_cond_text s : string =
  if String.is_empty s
  || String.exists s ~f:(Char.equal ';')
  || String.exists s ~f:Char.is_whitespace
  || String.is_substring s ~substring:"${"
  || String.exists s ~f:(Char.equal '(')
  || String.exists s ~f:(Char.equal ')')
  then Fmt.str "\"%s\"" s
  else s

(* Cond position: render expression to a raw string (no ${...} wrap for
   unresolved EVar — cmake's if() auto-dereferences identifiers). Then
   apply quote_cond_text. *)
let rec cond_text ?(env = empty_subst) (e : expr) : string =
  match e with
  | EVar name ->
    (match Map.find env name with
     | Some replacement -> cond_text ~env replacement
     | None -> name)
  | EString s -> s
  | EInt n -> Int.to_string n
  | EBool true -> "ON"
  | EBool false -> "OFF"
  | ETarget name -> name
  | _ -> fail "emit_ast: cannot erase expression for cond position"

let cond_token ?(env = empty_subst) e : string =
  quote_cond_text (cond_text ~env e)

let rec cond_tokens ?(env = empty_subst) (e : expr) : string list =
  match e with
  | EBool true -> [ "TRUE" ]
  | EBool false -> [ "FALSE" ]
  | ENot e -> "NOT" :: cond_tokens ~env e
  (* AND/OR always wraps in [(...)] — mirrors legacy [erase_bool] policy
     and makes operator precedence explicit. *)
  | EAnd (l, r) ->
    [ "(" ] @ cond_tokens ~env l @ [ "AND" ] @ cond_tokens ~env r @ [ ")" ]
  | EOr (l, r) ->
    [ "(" ] @ cond_tokens ~env l @ [ "OR" ] @ cond_tokens ~env r @ [ ")" ]
  | EIntLess (l, r) -> [ cond_token ~env l; "LESS"; cond_token ~env r ]
  | EIntEqual (l, r) -> [ cond_token ~env l; "EQUAL"; cond_token ~env r ]
  | EIntGreater (l, r) -> [ cond_token ~env l; "GREATER"; cond_token ~env r ]
  | EIntLessEqual (l, r) -> [ cond_token ~env l; "LESS_EQUAL"; cond_token ~env r ]
  | EIntGreaterEqual (l, r) -> [ cond_token ~env l; "GREATER_EQUAL"; cond_token ~env r ]
  | ECmakeStringEqual (l, r) -> [ cond_token ~env l; "STREQUAL"; cond_token ~env r ]
  | ECmakeVersionLess (a, b) -> [ cond_token ~env a; "VERSION_LESS"; cond_token ~env b ]
  | ECmakeVersionGreater (a, b) -> [ cond_token ~env a; "VERSION_GREATER"; cond_token ~env b ]
  | ECmakeVersionEqual (a, b) -> [ cond_token ~env a; "VERSION_EQUAL"; cond_token ~env b ]
  | ECmakeVersionLessEqual (a, b) -> [ cond_token ~env a; "VERSION_LESS_EQUAL"; cond_token ~env b ]
  | ECmakeVersionGreaterEqual (a, b) -> [ cond_token ~env a; "VERSION_GREATER_EQUAL"; cond_token ~env b ]
  | ECmakeVarDefined name -> [ "DEFINED"; name ]
  | ECmakeTargetExists t -> [ "TARGET"; target_arg ~env t ]
  | ECmakeFileExists p -> [ "EXISTS"; cond_token ~env p ]
  | ECmakeMatches { expr_; regex } -> [ cond_token ~env expr_; "MATCHES"; "\"" ^ regex ^ "\"" ]
  | ECmakeInList { item; list_ } -> [ cond_token ~env item; "IN_LIST"; cond_token ~env list_ ]
  | ECmakeIsDirectory p -> [ "IS_DIRECTORY"; cond_token ~env p ]
  | ECmakePolicyCheck p -> [ "POLICY"; p ]
  | _ -> [ cond_token ~env e ]

(* [cond_atom] kept as an alias for compatibility; AND/OR now self-wraps
   in [cond_tokens] so all callers get explicit parens. *)
and cond_atom ?(env = empty_subst) (e : expr) : string list =
  cond_tokens ~env e

(* ========================================================================
   Top-level emit: Yelu1 expr → cmake AST [exp].

   ESeq → Exp_list, ELet extends [subst] before recursing into body,
   matched ECmake* constructors map to their cmake AST counterparts.

   Phase 1.1 scope: skeleton + a small set of commands. Subsequent
   commits expand coverage until parity with [yelu_tiny_cmake_emit].
   ======================================================================== *)

let message_mode_of_string = function
  | "" | "NONE" -> C.Mm_none
  | "STATUS" -> C.Mm_status
  | "NOTICE" -> C.Mm_notice
  | "VERBOSE" -> C.Mm_verbose
  | "DEBUG" -> C.Mm_debug
  | "TRACE" -> C.Mm_trace
  | "WARNING" -> C.Mm_warning
  | "AUTHOR_WARNING" -> C.Mm_author_warning
  | "CHECK_START" -> C.Mm_check_start
  | "CHECK_PASS" -> C.Mm_check_pass
  | "CHECK_FAIL" -> C.Mm_check_fail
  | "SEND_ERROR" -> C.Mm_send_error
  | "FATAL_ERROR" -> C.Mm_fatal_error
  | "DEPRECATION" -> C.Mm_deprecation
  | other -> fail "emit_ast: unknown message mode %S" other

let version_of_string s : C.version =
  match String.split s ~on:'.' with
  | [ maj; min ] ->
    { major = Int.of_string maj; minor = Int.of_string min; patch = "" }
  | [ maj; min; patch ] ->
    { major = Int.of_string maj; minor = Int.of_string min; patch }
  | _ -> { major = 3; minor = 20; patch = "" }

(* Wrap a tiny [visibility : string] + [expr list] into the cmake AST's
   [items_with_kind list] shape. cmake's PUBLIC/PRIVATE/INTERFACE keyword
   separates groups; the bridge always collapses to a single group. *)
let items_with_kind ~env ~visibility (items : expr list) : C.items_with_kind list =
  [ { kind = visibility; items = List.map items ~f:(arg ~env) } ]

let target_feature_of_expr ~env (feature : expr) : C.target_feature =
  (* tiny stores features as plain strings; assume PRIVATE kind by default. *)
  { kind = "PRIVATE"; feature = target_arg ~env feature }

let rec emit_exp ~env (e : expr) : C.exp =
  match e with
  | EUnit -> C.Exp_list []
  | ESeq exprs ->
    C.Exp_list (List.map exprs ~f:(emit_exp ~env))
  | ELet { var; value; body } ->
    let env = Map.set env ~key:var ~data:value in
    emit_exp ~env body

  (* Store theory *)
  | ESetVar (name, EList exprs) ->
    C.Set { var = name; values = List.map exprs ~f:(arg ~env); parent_scope = false }
  | ESetVar (name, value) ->
    C.Set { var = name; values = [ arg ~env value ]; parent_scope = false }
  | ECmakeUnsetVar name ->
    C.Unset { var = name; cache = false; parent_scope = false }
  | ECmakeUnsetVarCache name ->
    C.Unset { var = name; cache = true; parent_scope = false }
  | ECmakeSetParentScope { name; value = EList exprs } ->
    C.Set { var = name; values = List.map exprs ~f:(arg ~env); parent_scope = true }
  | ECmakeSetParentScope { name; value } ->
    C.Set { var = name; values = [ arg ~env value ]; parent_scope = true }
  | ECmakeSetEnvVar { name; value } ->
    C.Set_env { var = name; value = arg ~env value }
  | ECmakeUnsetEnvVar name ->
    C.Unset_env { var = name }
  | ECmakeOption { name; message; value } ->
    C.Cmake_option { var = name; msg = message; value = arg ~env value }

  (* cmake_op: project metadata *)
  | ECmakeMinimumRequired version_s ->
    C.Cmake_cmd
      (C.Cmake_minimum_required { min = version_of_string version_s; max = None })
  | ECmakeMessage { mode; texts } ->
    C.Message
      { mode = message_mode_of_string mode;
        texts = List.map texts ~f:(target_arg ~env) }
  | ECmakeProject { name; languages; version } ->
    C.Project_cmd
      (C.Project
         { name;
           version = Option.map version ~f:version_of_string;
           description = None;
           homepage_url = None;
           languages })
  | ECmakeInclude { file; optional } ->
    C.Include
      { file = arg ~env file;
        optional;
        result_var = None;
        no_policy_scope = None }
  | ECmakeAtVar key ->
    (* @key@ literal: no first-class cmake AST ctor — render via Quote
       so it lands as a bare top-level line. *)
    C.Quote ("@" ^ key ^ "@")
  | ECmakeMath { exp; out } ->
    C.Math_lib
      { var = out;
        exp = C.Quote (Fmt.str "\"%s\"" exp);
        output_format = C.Decical }

  (* Control flow *)
  | ECmakeIfStmt { cond; then_; else_ } ->
    C.If
      { cond = cond_tokens ~env cond;
        then_ = emit_exp ~env then_;
        else_ = Option.map else_ ~f:(emit_exp ~env) }
  | ECmakeWhile { cond; body } ->
    C.While { cond = cond_tokens ~env cond; commands = emit_exp ~env body }
  | ECmakeBreak -> C.Break
  | ECmakeContinue -> C.Continue
  | ECmakeReturn { propagate_vars } ->
    C.Return { propogate_vars = propagate_vars }
  | ECmakeBlock { scope_vars; propagate; body } ->
    C.Block
      { scope_policy = [];
        scope_var = scope_vars;
        propagate;
        body = [ emit_exp ~env body ] }
  | ECmakeForeach { loop_var; items; body } ->
    C.Foreach
      { loop_var;
        items = List.map items ~f:(arg ~env);
        commands = emit_exp ~env body }
  | ECmakeForeachRange { loop_var; start; stop; step; body } ->
    C.Foreach_range
      { loop_var;
        start = Option.map start ~f:Int.to_string;
        stop = Int.to_string stop;
        step = Option.map step ~f:Int.to_string;
        commands = emit_exp ~env body }
  | ECmakeForeachZip { loop_vars; lists; body } ->
    C.Foreach_zip
      { loop_vars; lists; commands = emit_exp ~env body }
  | ECmakeFunction { name; params; body } ->
    (* cmake_pp's Function expects [cmds : cmd list] where [cmd = exp].
       Wrap our single [exp] as a one-element command list. *)
    C.Function
      { name = target_arg ~env name;
        args = params;
        cmds = [ emit_exp ~env body ] }
  | ECmakeMacro { name; params; body } ->
    C.Macro
      { name = target_arg ~env name;
        args = params;
        commands = emit_exp ~env body }
  | ECmakeApply { name; args = call_args } ->
    C.Apply
      { name = target_arg ~env name;
        args = List.map call_args ~f:(arg ~env) }

  (* Target / build graph *)
  | ECmakeAddExecutable { name; sources } ->
    C.Project_cmd
      (C.Add_executable
         { name = target_arg ~env name;
           options = [];
           sources = List.map sources ~f:(target_arg ~env) })
  | ECmakeAddLibrary { name; type_; sources } ->
    C.Project_cmd
      (C.Add_library
         { name = target_arg ~env name;
           exclude_from_all = false;
           type_;
           sources = List.map sources ~f:(target_arg ~env) })
  | ECmakeTargetLinkLibraries { target; visibility; items } ->
    C.Project_cmd
      (C.Target_link_libraries
         { targets = [ target_arg ~env target ];
           items = items_with_kind ~env ~visibility items })
  | ECmakeTargetIncludeDirectories { target; visibility; dirs } ->
    C.Project_cmd
      (C.Target_include_directories
         { target = target_arg ~env target;
           system = None;
           before_or_after = None;
           items = items_with_kind ~env ~visibility dirs })
  | ECmakeTargetCompileDefinitions { target; visibility; definitions } ->
    C.Project_cmd
      (C.Target_compile_definitions
         { target = target_arg ~env target;
           items = items_with_kind ~env ~visibility definitions })
  | ECmakeTargetCompileOptions { target; visibility; options_ } ->
    C.Project_cmd
      (C.Target_compile_options
         { target = target_arg ~env target;
           before = false;
           items = items_with_kind ~env ~visibility options_ })
  | ECmakeTargetLinkOptions { target; visibility; options_ } ->
    C.Project_cmd
      (C.Target_link_options
         { target = target_arg ~env target;
           before = false;
           items = items_with_kind ~env ~visibility options_ })
  | ECmakeTargetLinkDirectories { target; visibility; dirs } ->
    C.Project_cmd
      (C.Target_link_directories
         { target = target_arg ~env target;
           before = false;
           items = items_with_kind ~env ~visibility dirs })
  | ECmakeTargetCompileFeatures { target; visibility = _; features } ->
    C.Project_cmd
      (C.Target_compile_features
         { target = target_arg ~env target;
           features = List.map features ~f:(target_feature_of_expr ~env) })
  | ECmakeTargetSources { target; visibility; sources } ->
    C.Project_cmd
      (C.Target_sources
         { target = target_arg ~env target;
           items = items_with_kind ~env ~visibility sources })

  (* Directory *)
  | ECmakeAddSubdirectory path ->
    C.Project_cmd
      (C.Add_subdirectory
         { source_dir = target_arg ~env path;
           binary_dir = None;
           exclude_from_all = false;
           system = false })

  (* String *)
  | ECmakeStringConcat { inputs; out } ->
    C.String_cmd (C.Sc_concat { out; inputs = List.map inputs ~f:(arg ~env) })
  | ECmakeStringToupper { input; out } ->
    C.String_cmd (C.Sc_toupper { string = arg ~env input; out })
  | ECmakeStringTolower { input; out } ->
    C.String_cmd (C.Sc_tolower { string = arg ~env input; out })
  | ECmakeStringLength { input; out } ->
    C.String_cmd (C.Sc_length { string = arg ~env input; out })
  | ECmakeStringStrip { input; out } ->
    C.String_cmd (C.Sc_strip { string = arg ~env input; out })
  | ECmakeStringReplace { match_; replace; input; out } ->
    C.String_cmd
      (C.Sc_replace
         { match_string = arg ~env match_;
           replace_string = arg ~env replace;
           out;
           inputs = [ arg ~env input ] })
  | ECmakeStringRegexReplace { regex; replace; out; inputs } ->
    C.String_cmd
      (C.Sc_regex
         (C.Sr_replace
            { regex; replace = arg ~env replace; out;
              inputs = List.map inputs ~f:(arg ~env) }))
  | ECmakeStringRegexMatch { regex; out; inputs } ->
    C.String_cmd
      (C.Sc_regex
         (C.Sr_match { regex; out; inputs = List.map inputs ~f:(arg ~env) }))
  | ECmakeStringRegexMatchAll { regex; out; inputs } ->
    C.String_cmd
      (C.Sc_regex
         (C.Sr_matchall { regex; out; inputs = List.map inputs ~f:(arg ~env) }))
  | ECmakeStringJoin { glue; out; inputs } ->
    C.String_cmd
      (C.Sc_join
         { glue = arg ~env glue; out; inputs = List.map inputs ~f:(arg ~env) })
  | ECmakeStringAppend { cvar; inputs } ->
    C.String_cmd (C.Sc_append { var = cvar; inputs = List.map inputs ~f:(arg ~env) })
  | ECmakeStringSubstring { string; begin_; length; out } ->
    C.String_cmd
      (C.Sc_substring { string = arg ~env string; begin_; length; out })
  | ECmakeStringRepeat { string; count; out } ->
    C.String_cmd (C.Sc_repeat { string = arg ~env string; count; out })
  | ECmakeStringFind { string; substring; out; reverse } ->
    C.String_cmd
      (C.Sc_find
         { string = arg ~env string;
           substring = arg ~env substring;
           out; reverse })

  (* List *)
  | ECmakeListAppend { list; items } ->
    C.List_cmd (C.Lc_append { var = list; values = List.map items ~f:(arg ~env) })
  | ECmakeListPrepend { list; items } ->
    C.List_cmd (C.Lc_prepend { var = list; values = List.map items ~f:(arg ~env) })
  | ECmakeListInsert { list; index; items } ->
    C.List_cmd
      (C.Lc_insert { var = list; index; values = List.map items ~f:(arg ~env) })
  | ECmakeListLength { list; out } ->
    C.List_cmd (C.Lc_length { var = list; out })
  | ECmakeListGet { list; index; out } ->
    let i = match index with
      | EInt n -> n
      | _ -> fail "emit_ast: list(GET) index must be a literal integer"
    in
    C.List_cmd (C.Lc_get { var = list; indices = [ i ]; out })
  | ECmakeListJoin { list; glue; out } ->
    C.List_cmd (C.Lc_join { var = list; glue = arg ~env glue; out })
  | ECmakeListRemoveItem { list; items } ->
    C.List_cmd
      (C.Lc_remove_item { var = list; values = List.map items ~f:(arg ~env) })
  | ECmakeListRemoveAt { list; indices } ->
    C.List_cmd (C.Lc_remove_at { var = list; indices })
  | ECmakeListRemoveDuplicates { list } ->
    C.List_cmd (C.Lc_remove_duplicates { var = list })
  | ECmakeListReverse { list } ->
    C.List_cmd (C.Lc_reverse { var = list })
  | ECmakeListFind { list; value; out } ->
    C.List_cmd (C.Lc_find { var = list; value = arg ~env value; out })

  (* File I/O — small first slice *)
  | ECmakeFileWrite { path; content } ->
    C.File_write
      { file = arg ~env path;
        append = false;
        content = List.map content ~f:(arg ~env) }
  | ECmakeFileWriteAppend { path; content } ->
    C.File_write
      { file = arg ~env path;
        append = true;
        content = List.map content ~f:(arg ~env) }
  | ECmakeFileRead { path; out } ->
    C.File_read
      { var = out; file = arg ~env path;
        offset = None; limit = None; hex = false }
  | ECmakeConfigureFile { input; output } ->
    C.Cmake_cmd
      (C.Configure_file
         { input = target_arg ~env input;
           output = target_arg ~env output;
           permission_level = None;
           permissions = [];
           copy_only = None;
           escape_quotes = None;
           only = None;
           newline_style = None })
  | ECmakeFileRelativePath { var; base; file } ->
    C.File_relative_path
      { var; base = target_arg ~env base; file = target_arg ~env file }

  (* Install *)
  | Yelu_surface_cmake_install.ECmakeInstallTargets { targets; destination; export } ->
    C.Project_cmd
      (C.Install_targets
         { targets = List.map targets ~f:(target_arg ~env);
           destination = arg ~env destination;
           component = None;
           rename = None;
           export = Option.map export ~f:(target_arg ~env);
           permissions = [] })
  | Yelu_surface_cmake_install.ECmakeInstallFiles { files; destination } ->
    C.Project_cmd
      (C.Install_files
         { files = List.map files ~f:(arg ~env);
           destination = arg ~env destination;
           component = None;
           rename = None;
           permissions = [] })

  (* Property — target subset *)
  | Yelu_surface_cmake_property.ECmakeSetTargetProperty { target; property; value } ->
    C.Project_cmd
      (C.Set_target_properties
         { target = target_arg ~env target;
           properties = [ { prop = property; value = arg ~env value } ] })
  | Yelu_surface_cmake_property.ECmakeGetTargetProperty { var; target; property } ->
    C.Project_cmd
      (C.Get_target_property
         { var; target = target_arg ~env target;
           property = { prop = property; value = C.Bare "" } })

  (* Find *)
  | Yelu_surface_cmake_find.ECmakeFindPackage { package_name; required } ->
    C.Find_package
      { name = package_name; required;
        version = None; exact = false; quiet = false;
        config_mode = false;
        components = []; optional_components = [] }

  (* Tests *)
  | ECmakeEnableTesting ->
    C.Project_cmd C.Enable_testing
  | ECmakeAddTest { name; command; args = call_args } ->
    C.Project_cmd
      (C.Add_test
         { name = target_arg ~env name;
           command = target_arg ~env command;
           args = List.map call_args ~f:(target_arg ~env);
           dir = None })

  (* Diagnostic / result-message fallthroughs (kept compatible with
     [yelu_tiny_cmake_emit]: a bare value at statement position renders
     as a [message] for round-trip-observability). *)
  | EVar name when Map.mem env name ->
    emit_exp ~env (Map.find_exn env name)
  | EVar name ->
    C.Message { mode = C.Mm_none; texts = [ "RESULT=${" ^ name ^ "}" ] }
  | EString s ->
    C.Message { mode = C.Mm_none; texts = [ "RESULT=" ^ s ] }
  | EInt n ->
    C.Message { mode = C.Mm_none; texts = [ "RESULT=" ^ Int.to_string n ] }
  | EBool b ->
    C.Message { mode = C.Mm_none; texts = [ "RESULT=" ^ (if b then "ON" else "OFF") ] }
  | ETarget _ -> C.Exp_list []

  | _ -> fail "emit_ast: unsupported Yelu1 expression (phase 1 coverage gap)"

(* Public API. *)

let emit_ast ?(env = empty_subst) (e : expr) : C.exp = emit_exp ~env e

let emit_script (e : expr) : string =
  let ast = emit_ast e in
  Fmt.str "%a" Lang_cmake_pp.pp ast
