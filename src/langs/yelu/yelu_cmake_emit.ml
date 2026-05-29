(* Production emit: lower yelu_cmake.expr to Lang_cmake.exp (the
   cmake syntax AST), then let the existing [lang_cmake_pp] render
   to text. This is the production path for every step binary and
   every test that needs cmake text output.

   This module exists alongside [yelu_cmake_emit_debug.ml] (the
   direct-text emit, retained as a diagnostic / diff aid; not on
   the production path). See [doc/yelu_cmake/retirement_plan.md]
   for the full retirement story. *)

open Base
open Yelu_cmake
open Yelu_cmake_store
open Yelu_cmake_normal_bool
open Yelu_cmake_normal_int
open Yelu_cmake_normal_list
open Yelu_cmake_list
open Yelu_cmake_file
open Yelu_cmake_string
open Yelu_cmake_target
open Yelu_cmake_if
open Yelu_cmake_cmake_op
open Yelu_cmake_dir
open Yelu_cmake_test
open Yelu_cmake_normal_target

(* Many other surface modules are opened transitively via [expr] match
   arms as Phase 1.3 expands coverage; keep [open]s narrow for now to
   avoid unused-open warnings. *)

module C = Lang_cmake

(* ========================================================================
   Erasure helpers — yelu_cmake expr → cmake AST positional shapes.

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
  | ECmakeGenex s ->
    (* Render genex source verbatim, Quoted. Matches legacy compile's
       erase_arg for Ycs_eval — preserves byte-equality oracle. *)
    C.Quoted s
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
  | ECmakeIsAbsolute p -> [ "IS_ABSOLUTE"; cond_token ~env p ]
  | ECmakePolicyCheck p -> [ "POLICY"; p ]
  | _ -> [ cond_token ~env e ]

(* [cond_atom] kept as an alias for compatibility; AND/OR now self-wraps
   in [cond_tokens] so all callers get explicit parens. *)
and cond_atom ?(env = empty_subst) (e : expr) : string list =
  cond_tokens ~env e

(* ========================================================================
   Top-level emit: yelu_cmake expr → cmake AST [exp].

   ESeq → Exp_list, ELet extends [subst] before recursing into body,
   matched ECmake* constructors map to their cmake AST counterparts.

   Phase 1.1 scope: skeleton + a small set of commands. Subsequent
   commits expand coverage until parity with [yelu_cmake_emit_debug].
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

(* Inverse of bridge's [Lang_cmake_strings.of_cmake_path_get_field]. Tiny stores
   the field as a keyword string ("ROOT_NAME", "EXTENSION LAST_ONLY", …);
   here we map back to the typed [Lang_cmake.cmake_path_get_field]. *)
let cmake_path_get_field_of_string s : C.cmake_path_get_field =
  match s with
  | "ROOT_NAME" -> C.Cpf_root_name
  | "ROOT_DIRECTORY" -> C.Cpf_root_directory
  | "ROOT_PATH" -> C.Cpf_root_path
  | "FILENAME" -> C.Cpf_filename
  | "EXTENSION" -> C.Cpf_extension false
  | "EXTENSION LAST_ONLY" -> C.Cpf_extension true
  | "STEM" -> C.Cpf_stem false
  | "STEM LAST_ONLY" -> C.Cpf_stem true
  | "RELATIVE_PART" -> C.Cpf_relative_part
  | "PARENT_PATH" -> C.Cpf_parent_path
  | _ -> fail "emit_ast: unknown cmake_path GET field %S" s

let cmake_path_has_field_of_string s : C.cmake_path_has_field =
  match s with
  | "HAS_ROOT_NAME" -> C.Cph_root_name
  | "HAS_ROOT_DIRECTORY" -> C.Cph_root_directory
  | "HAS_ROOT_PATH" -> C.Cph_root_path
  | "HAS_FILENAME" -> C.Cph_filename
  | "HAS_EXTENSION" -> C.Cph_extension
  | "HAS_STEM" -> C.Cph_stem
  | "HAS_RELATIVE_PART" -> C.Cph_relative_part
  | "HAS_PARENT_PATH" -> C.Cph_parent_path
  | _ -> fail "emit_ast: unknown cmake_path HAS field %S" s

let cmake_path_compare_op_of_string s : C.cmake_path_compare_op =
  match s with
  | "EQUAL" -> C.Cpco_equal
  | "NOT_EQUAL" -> C.Cpco_not_equal
  | _ -> fail "emit_ast: unknown cmake_path COMPARE op %S" s

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
  | ECmakeSetCache { name; values; cache_type; docstring; force } ->
    let ct = match cache_type with
      | "BOOL" -> C.Ct_bool | "FILEPATH" -> C.Ct_filepath
      | "PATH" -> C.Ct_path | "STRING" -> C.Ct_string
      | "INTERNAL" -> C.Ct_internal
      | _ -> fail "emit_ast: unknown set(CACHE) type %S" cache_type
    in
    C.Set_cache
      { var = name;
        values = List.map values ~f:(arg ~env);
        cache_type = ct;
        docstring;
        force }

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
        no_policy_scope = false }
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
  | ECmakeForeachInList { loop_var; lists; items; body } ->
    C.Foreach_in
      { loop_var; lists;
        items = List.map items ~f:(arg ~env);
        commands = emit_exp ~env body }
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
  | ECmakeTargetIncludeDirectories { target; visibility; before; system; dirs } ->
    C.Project_cmd
      (C.Target_include_directories
         { target = target_arg ~env target;
           system = (if system then Some true else None);
           before_or_after = (if before then Some C.Before else None);
           items = items_with_kind ~env ~visibility dirs })
  | ECmakeTargetCompileDefinitions { target; visibility; definitions } ->
    C.Project_cmd
      (C.Target_compile_definitions
         { target = target_arg ~env target;
           items = items_with_kind ~env ~visibility definitions })
  | ECmakeTargetCompileOptions { target; visibility; before; options_ } ->
    C.Project_cmd
      (C.Target_compile_options
         { target = target_arg ~env target;
           before;
           items = items_with_kind ~env ~visibility options_ })
  | ECmakeTargetLinkOptions { target; visibility; before; options_ } ->
    C.Project_cmd
      (C.Target_link_options
         { target = target_arg ~env target;
           before;
           items = items_with_kind ~env ~visibility options_ })
  | ECmakeTargetLinkDirectories { target; visibility; before; dirs } ->
    C.Project_cmd
      (C.Target_link_directories
         { target = target_arg ~env target;
           before;
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

  (* Target aliases & imported *)
  | ECmakeAddLibraryAlias { name; target } ->
    C.Project_cmd (C.Add_library_alias { name; target })
  | ECmakeAddExecutableAlias { name; target } ->
    C.Project_cmd (C.Add_executable_alias { name; target })
  | ECmakeAddLibraryImported { name; lib_type; global } ->
    C.Project_cmd
      (C.Add_library_imported
         { name = target_arg ~env name; lib_type; global })

  (* Directory *)
  | ECmakeAddSubdirectory path ->
    C.Project_cmd
      (C.Add_subdirectory
         { source_dir = target_arg ~env path;
           binary_dir = None;
           exclude_from_all = false;
           system = false })

  (* Dir-level compile / link / include commands.
     These map to cmake AST shapes that carry one [dir]/[dirs] split
     (Include_directories, Link_directories) — we put the whole list
     in [dirs] and leave the head [dir] empty. Add_definitions /
     Add_compile_definitions use [definition] = Def_var of var; for the
     simple bridge case we synthesize Def_var from the arg's text. *)
  | ECmakeIncludeDirectories { dirs; before; system } ->
    C.Project_cmd
      (C.Include_directories
         { before_or_after = (if before then C.Before else C.Default_order);
           system;
           dir = "";
           dirs = List.map dirs ~f:(target_arg ~env) })
  | ECmakeLinkDirectories { dirs; before } ->
    C.Project_cmd
      (C.Link_directories
         { before_or_after = (if before then C.Before else C.Default_order);
           directory = "";
           directories = List.map dirs ~f:(target_arg ~env) })
  | ECmakeAddCompileOptions opts ->
    C.Project_cmd
      (C.Add_compile_options { options_ = List.map opts ~f:(target_arg ~env) })
  | ECmakeAddLinkOptions opts ->
    C.Project_cmd
      (C.Add_link_options { options = List.map opts ~f:(target_arg ~env) })
  | ECmakeAddCompileDefinitions defs ->
    C.Project_cmd
      (C.Add_compile_definitions
         { defs = List.map defs ~f:(fun d -> C.Def_var (target_arg ~env d)) })
  | ECmakeAddDefinitions defs ->
    C.Project_cmd
      (C.Add_definitions
         { defs = List.map defs ~f:(fun d -> C.Def_var (target_arg ~env d)) })

  (* Find — non-package variants share [find_var_args]. *)
  | Yelu_cmake_find.ECmakeFindLibrary { out; names; paths; hints; required } ->
    let fa : C.find_var_args =
      { var = out;
        names = List.map names ~f:(arg ~env);
        hints = List.map hints ~f:(arg ~env);
        paths = List.map paths ~f:(arg ~env);
        path_suffixes = []; doc = None; required;
        no_cache = false; no_default_path = false;
        no_package_root_path = false; no_cmake_path = false;
        no_cmake_environment_path = false; no_system_environment_path = false;
        no_cmake_system_path = false; no_cmake_install_prefix = false }
    in
    C.Find_library fa
  | Yelu_cmake_find.ECmakeFindPath { out; names; paths; hints; required } ->
    let fa : C.find_var_args =
      { var = out;
        names = List.map names ~f:(arg ~env);
        hints = List.map hints ~f:(arg ~env);
        paths = List.map paths ~f:(arg ~env);
        path_suffixes = []; doc = None; required;
        no_cache = false; no_default_path = false;
        no_package_root_path = false; no_cmake_path = false;
        no_cmake_environment_path = false; no_system_environment_path = false;
        no_cmake_system_path = false; no_cmake_install_prefix = false }
    in
    C.Find_path fa
  | Yelu_cmake_find.ECmakeFindProgram { out; names; paths; hints; required } ->
    let fa : C.find_var_args =
      { var = out;
        names = List.map names ~f:(arg ~env);
        hints = List.map hints ~f:(arg ~env);
        paths = List.map paths ~f:(arg ~env);
        path_suffixes = []; doc = None; required;
        no_cache = false; no_default_path = false;
        no_package_root_path = false; no_cmake_path = false;
        no_cmake_environment_path = false; no_system_environment_path = false;
        no_cmake_system_path = false; no_cmake_install_prefix = false }
    in
    C.Find_program fa
  | Yelu_cmake_find.ECmakeFindFile { out; names; paths; hints; required } ->
    let fa : C.find_var_args =
      { var = out;
        names = List.map names ~f:(arg ~env);
        hints = List.map hints ~f:(arg ~env);
        paths = List.map paths ~f:(arg ~env);
        path_suffixes = []; doc = None; required;
        no_cache = false; no_default_path = false;
        no_package_root_path = false; no_cmake_path = false;
        no_cmake_environment_path = false; no_system_environment_path = false;
        no_cmake_system_path = false; no_cmake_install_prefix = false }
    in
    C.Find_file fa

  (* Install / Export / Package config *)
  | Yelu_cmake_install.ECmakeInstallExport { export; destination; file; namespace } ->
    C.Project_cmd
      (C.Install_export
         { file = Option.map file ~f:(arg ~env);
           export = arg ~env export;
           destination = arg ~env destination;
           namespace;
           component = None;
           rename = None;
           permissions = [] })
  | Yelu_cmake_install.ECmakeExportExport { name; file } ->
    C.Project_cmd
      (C.Export_export
         { name = target_arg ~env name;
           file = Option.map file ~f:(arg ~env) })
  | Yelu_cmake_install.ECmakeConfigurePackageConfigFile
      { install_dest; input; output;
        no_set_and_check_macro; no_check_required_components_macro } ->
    C.Module_cmd
      (C.Configure_package_config_file
         { input = arg ~env input;
           output = arg ~env output;
           install_dest = arg ~env install_dest;
           path_vars = [];
           no_set_and_check_macro;
           no_check_required_components_macro })
  | Yelu_cmake_install.ECmakeWriteBasicPackageVersionFile
      { file; version; compatibility; arch_independent } ->
    C.Module_cmd
      (C.Write_basic_package_version_file
         { file = arg ~env file;
           version = Option.map version ~f:(arg ~env);
           compatibility;
           arch_independent })

  (* Property scopes beyond target *)
  | Yelu_cmake_property.ECmakeSetProperty { targets; append; properties } ->
    C.Set_property
      { global = false;
        directory = [];
        targets = List.map targets ~f:(target_arg ~env);
        sources = [];
        source_directories = [];
        source_target_directories = [];
        installs = [];
        tests = [];
        test_directories = [];
        caches = [];
        append; append_string = false;
        properties = List.map properties ~f:(fun (prop, value) ->
          ({ prop; value = arg ~env value } : C.property)) }
  | Yelu_cmake_property.ECmakeSetGlobalProperty { properties } ->
    C.Set_property
      { global = true;
        directory = [];
        targets = [];
        sources = [];
        source_directories = [];
        source_target_directories = [];
        installs = [];
        tests = [];
        test_directories = [];
        caches = [];
        append = false; append_string = false;
        properties = List.map properties ~f:(fun (prop, value) ->
          ({ prop; value = arg ~env value } : C.property)) }
  | Yelu_cmake_property.ECmakeGetProperty { var; target; property; set_form } ->
    C.Get_property
      { var; global = false;
        directory = ""; source = ""; source_directory = "";
        source_target_directory = target_arg ~env target;
        install = ""; test = ""; test_directory = "";
        variable = false;
        property_name = property;
        set = set_form }
  | Yelu_cmake_property.ECmakeGetDirectoryProperty { var; property } ->
    C.Get_directory_property { var; directory = ""; property }
  | Yelu_cmake_property.ECmakeSetSourceProperty { file; property; values } ->
    C.Set_source_property
      { file = target_arg ~env file; property;
        values = List.map values ~f:(arg ~env) }

  (* cmake_op tail *)
  | ECmakeEnableLanguage { langs; optional } ->
    C.Project_cmd (C.Enable_language { langs; optional })
  | ECmakePolicySet { id; new_ } ->
    C.Cmake_cmd (C.Cmake_policy_set { id; new_ })

  (* String JSON — dispatch on op_name to construct json_op *)
  | ECmakeStringJson { out; error_var; op_name; args = json_args } ->
    let argv n =
      try List.nth_exn json_args n |> arg ~env
      with _ -> C.Bare ""
    in
    let path_from n = List.drop json_args n |> List.map ~f:(arg ~env) in
    let op : C.json_op = match op_name with
      | "GET" -> C.Jop_get { json = argv 0; path = path_from 1 }
      | "GET_RAW" -> C.Jop_get_raw { json = argv 0; path = path_from 1 }
      | "TYPE" -> C.Jop_type { json = argv 0; path = path_from 1 }
      | "LENGTH" -> C.Jop_length { json = argv 0; path = path_from 1 }
      | "MEMBER" -> C.Jop_member { json = argv 0; path = path_from 1 }
      | "REMOVE" -> C.Jop_remove { json = argv 0; path = path_from 1 }
      | "SET" ->
        let n = List.length json_args in
        C.Jop_set
          { json = argv 0;
            path = List.drop json_args 1 |> List.take_while ~f:(fun _ -> true)
                   |> (fun xs -> List.take xs (n - 2))
                   |> List.map ~f:(arg ~env);
            value = (try List.nth_exn json_args (n - 1) |> arg ~env
                     with _ -> C.Bare "") }
      | "EQUAL" -> C.Jop_equal { json1 = argv 0; json2 = argv 1 }
      | "STRINGIFY" ->
        C.Jop_string_encode { value = argv 0 }
      (* The bridge currently stores [op_name = "JSON_op"] for all
         string(JSON ...) calls — see [yelu_cmake_to_yelu1.ml]
         [Ystr_json] case: op shape is bridged opaque, args dropped.
         Synthesize a placeholder Jop_get so emit doesn't crash; the
         resulting cmake text is not semantically faithful to the
         original. Tracked as a bridge gap in
         [doc/yelu_cmake/status.md]. *)
      | "JSON_op" -> C.Jop_get { json = C.Bare ""; path = [] }
      | _ -> fail "emit_ast: unknown string(JSON ...) op %S" op_name
    in
    C.String_cmd (C.Sc_json { out; error_var; op })

  (* List transform — typed action / selector with payloads dropped by
     the bridge; we synthesize default payloads for emit. *)
  | ECmakeListTransform { list; action; selector; output } ->
    let action : C.list_transform_action = match action with
      | "APPEND" -> C.Lta_append (C.Bare "")
      | "PREPEND" -> C.Lta_prepend (C.Bare "")
      | "TOUPPER" -> C.Lta_toupper
      | "TOLOWER" -> C.Lta_tolower
      | "STRIP" -> C.Lta_strip
      | "GENEX_STRIP" -> C.Lta_genex_strip
      | "REPLACE" -> C.Lta_replace { match_regex = ""; replace = "" }
      | _ -> fail "emit_ast: unknown list(TRANSFORM ...) action %S" action
    in
    let selector = Option.map selector ~f:(fun s -> match s with
      | "AT" -> C.Lts_at []
      | "FOR" -> C.Lts_for { start = 0; stop = 0; step = None }
      | "REGEX" -> C.Lts_regex ""
      | _ -> fail "emit_ast: unknown list(TRANSFORM ...) selector %S" s)
    in
    C.List_cmd
      (C.Lc_transform { var = list; action; selector; output })

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
  | ECmakeListGet { list; indices; out } ->
    C.List_cmd (C.Lc_get { var = list; indices; out })
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
  | ECmakeFileReadFull { path; out; offset; limit; hex } ->
    C.File_read
      { var = out; file = arg ~env path; offset; limit; hex }
  | ECmakeFileStrings { out; path; regex; encoding; limit_count } ->
    C.File_strings
      { var = out; file = arg ~env path; regex; encoding; limit_count }
  | ECmakeFileTouch { files; nocreate } ->
    C.File_touch
      { files = List.map files ~f:(arg ~env); nocreate }
  | ECmakeFileMakeDirectory { dirs } ->
    C.File_make_directory { dirs = List.map dirs ~f:(arg ~env) }
  | ECmakeFileRename { old_; new_; result; no_replace } ->
    C.File_rename
      { old_ = arg ~env old_; new_ = arg ~env new_; result; no_replace }
  | ECmakeFileRemove { files; recurse } ->
    C.File_remove
      { files = List.map files ~f:(arg ~env); recurse }
  | ECmakeFileCopy { input; output; result; only_if_different } ->
    C.File_copy_file
      { input = arg ~env input; output = arg ~env output;
        result; only_if_different }
  | ECmakeFileRealPath { out; path; base_dir; expand_tilde } ->
    C.File_real_path
      { var = out; path = arg ~env path;
        base_dir = Option.map base_dir ~f:(arg ~env);
        expand_tilde }
  | ECmakeFileSize { out; path } ->
    C.File_size { var = out; file = arg ~env path }
  | ECmakeFileReadSymlink { out; link } ->
    C.File_read_symlink { var = out; link = arg ~env link }
  | ECmakeFileTimestamp { out; path; format; utc } ->
    C.File_timestamp
      { var = out; file = arg ~env path; format; utc }

  (* Install *)
  | Yelu_cmake_install.ECmakeInstallTargets { targets; destination; export } ->
    C.Project_cmd
      (C.Install_targets
         { targets = List.map targets ~f:(target_arg ~env);
           destination = arg ~env destination;
           component = None;
           rename = None;
           export = Option.map export ~f:(target_arg ~env);
           permissions = [] })
  | Yelu_cmake_install.ECmakeInstallFiles { files; destination } ->
    C.Project_cmd
      (C.Install_files
         { files = List.map files ~f:(arg ~env);
           destination = arg ~env destination;
           component = None;
           rename = None;
           permissions = [] })

  (* Property — target subset *)
  | Yelu_cmake_property.ECmakeSetTargetProperty { target; property; value } ->
    C.Project_cmd
      (C.Set_target_properties
         { targets = [ target_arg ~env target ];
           properties = [ { prop = property; value = arg ~env value } ] })
  | Yelu_cmake_property.ECmakeGetTargetProperty { var; target; property } ->
    C.Project_cmd
      (C.Get_target_property
         { var; target = target_arg ~env target;
           property = { prop = property; value = C.Bare "" } })

  (* Find *)
  | Yelu_cmake_find.ECmakeFindPackage
      { package_name; version; exact; quiet; config_mode;
        required; components; optional_components } ->
    C.Find_package
      { name = package_name; required;
        version; exact; quiet; config_mode;
        components; optional_components }

  (* Property — non-target scopes *)
  | Yelu_cmake_property.ECmakeDefineProperty
      { mode; property_name; inherited; brief_docs; full_docs; initialize_from } ->
    let dpm = match mode with
      | "TARGET" -> C.Dp_target | "SOURCE" -> C.Dp_source
      | "TEST" -> C.Dp_test | "VARIABLE" -> C.Dp_variable
      | "CACHED_VARIABLE" -> C.Dp_cached_variable
      | "GLOBAL" -> C.Dp_global | "DIRECTORY" -> C.Dp_directory
      | _ -> fail "emit_ast: unknown define_property mode %S" mode
    in
    C.Project_cmd
      (C.Define_property
         { mode = dpm; property_name; inherited; brief_docs; full_docs;
           initialize_from = Option.value initialize_from ~default:"" })

  (* Path — full family. cmake_path(...) wraps in Cmake_cmd / Cmake_path;
     get_filename_component is its own top-level ctor. *)
  | Yelu_cmake_path.ECmakePathSet { path; input; normalize } ->
    C.Cmake_cmd
      (C.Cmake_path
         (C.Cpp_set { path_var = path; input = arg ~env input; normalize }))
  | Yelu_cmake_path.ECmakePathNormalPath { path; out } ->
    C.Cmake_cmd
      (C.Cmake_path (C.Cpp_normal_path { path_var = path; out_var = out }))
  | Yelu_cmake_path.ECmakePathGetFilename { path; out } ->
    C.Cmake_cmd
      (C.Cmake_path
         (C.Cpp_get
            { path_var = path; field = C.Cpf_filename; out_var = out }))
  | Yelu_cmake_path.ECmakePathGet { path; field; out } ->
    C.Cmake_cmd
      (C.Cmake_path
         (C.Cpp_get
            { path_var = path;
              field = cmake_path_get_field_of_string field;
              out_var = out }))
  | Yelu_cmake_path.ECmakePathHas { path; field; out } ->
    C.Cmake_cmd
      (C.Cmake_path
         (C.Cpp_has
            { path_var = path;
              field = cmake_path_has_field_of_string field;
              out_var = out }))
  | Yelu_cmake_path.ECmakePathIsAbsolute { path; out } ->
    C.Cmake_cmd (C.Cmake_path (C.Cpp_is_absolute { path_var = path; out_var = out }))
  | Yelu_cmake_path.ECmakePathIsRelative { path; out } ->
    C.Cmake_cmd (C.Cmake_path (C.Cpp_is_relative { path_var = path; out_var = out }))
  | Yelu_cmake_path.ECmakePathIsPrefix { path; input; normalize; out } ->
    C.Cmake_cmd
      (C.Cmake_path
         (C.Cpp_is_prefix
            { path_var = path; input = arg ~env input; normalize;
              out_var = out }))
  | Yelu_cmake_path.ECmakePathCompare { input1; op; input2; out } ->
    C.Cmake_cmd
      (C.Cmake_path
         (C.Cpp_compare
            { input1 = arg ~env input1;
              op = cmake_path_compare_op_of_string op;
              input2 = arg ~env input2;
              out_var = out }))
  | Yelu_cmake_path.ECmakePathAppend { path; inputs; out } ->
    C.Cmake_cmd
      (C.Cmake_path
         (C.Cpp_append
            { path_var = path;
              inputs = List.map inputs ~f:(arg ~env);
              out_var = out }))
  | Yelu_cmake_path.ECmakePathAppendString { path; inputs; out } ->
    C.Cmake_cmd
      (C.Cmake_path
         (C.Cpp_append_string
            { path_var = path;
              inputs = List.map inputs ~f:(arg ~env);
              out_var = out }))
  | Yelu_cmake_path.ECmakePathRemoveFilename { path; out } ->
    C.Cmake_cmd
      (C.Cmake_path (C.Cpp_remove_filename { path_var = path; out_var = out }))
  | Yelu_cmake_path.ECmakePathReplaceFilename { path; input; out } ->
    C.Cmake_cmd
      (C.Cmake_path
         (C.Cpp_replace_filename
            { path_var = path; input = arg ~env input; out_var = out }))
  | Yelu_cmake_path.ECmakePathRemoveExtension { path; last_only; out } ->
    C.Cmake_cmd
      (C.Cmake_path
         (C.Cpp_remove_extension { path_var = path; last_only; out_var = out }))
  | Yelu_cmake_path.ECmakePathReplaceExtension { path; last_only; input; out } ->
    C.Cmake_cmd
      (C.Cmake_path
         (C.Cpp_replace_extension
            { path_var = path; last_only;
              input = arg ~env input; out_var = out }))
  | Yelu_cmake_path.ECmakePathRelativePath { path; base_dir; out } ->
    C.Cmake_cmd
      (C.Cmake_path
         (C.Cpp_relative_path
            { path_var = path;
              base_dir = Option.map base_dir ~f:(arg ~env);
              out_var = out }))
  | Yelu_cmake_path.ECmakePathAbsolutePath { path; base_dir; normalize; out } ->
    C.Cmake_cmd
      (C.Cmake_path
         (C.Cpp_absolute_path
            { path_var = path;
              base_dir = Option.map base_dir ~f:(arg ~env);
              normalize;
              out_var = out }))
  | Yelu_cmake_path.ECmakePathNativePath { path; normalize; out } ->
    C.Cmake_cmd
      (C.Cmake_path
         (C.Cpp_native_path { path_var = path; normalize; out_var = out }))
  | Yelu_cmake_path.ECmakePathConvertToCmake { input; normalize; out } ->
    C.Cmake_cmd
      (C.Cmake_path
         (C.Cpp_convert_to_cmake
            { input = arg ~env input; normalize; out_var = out }))
  | Yelu_cmake_path.ECmakePathConvertToNative { input; normalize; out } ->
    C.Cmake_cmd
      (C.Cmake_path
         (C.Cpp_convert_to_native
            { input = arg ~env input; normalize; out_var = out }))
  | Yelu_cmake_path.ECmakePathHash { path; out } ->
    C.Cmake_cmd
      (C.Cmake_path (C.Cpp_hash { path_var = path; out_var = out }))
  | Yelu_cmake_path.ECmakeGetFilenameComponent { var; filename; mode } ->
    C.Get_filename_component
      { var; filename = target_arg ~env filename; mode; cache = false }

  (* Variable watch *)
  | ECmakeVariableWatch { var; command } ->
    C.Variable_watch
      { var; command; access = C.Vw_read_access;
        value = None; current_list_file = None; stack = [] }

  (* Execute process *)
  | ECmakeExecuteProcess r ->
    C.Execute_process
      { commands = List.map r.commands ~f:(List.map ~f:(arg ~env));
        working_directory = Option.map r.working_directory ~f:(arg ~env);
        timeout = r.timeout;
        result_variable = r.result_variable;
        output_variable = r.output_variable;
        error_variable = r.error_variable;
        input_file = Option.map r.input_file ~f:(arg ~env);
        output_file = Option.map r.output_file ~f:(arg ~env);
        error_file = Option.map r.error_file ~f:(arg ~env);
        output_quiet = r.output_quiet;
        error_quiet = r.error_quiet;
        output_strip_trailing_whitespace = r.output_strip_trailing_whitespace;
        error_strip_trailing_whitespace = r.error_strip_trailing_whitespace;
        command_error_is_fatal = r.command_error_is_fatal }

  (* File glob *)
  | ECmakeFileGlob { out; recurse; relative; configure_depends; patterns } ->
    C.File_glob
      { var = out; recurse;
        relative = Option.map relative ~f:(target_arg ~env);
        configure_depends;
        patterns = List.map patterns ~f:(arg ~env) }

  (* Target precompile headers *)
  | ECmakeTargetPrecompileHeaders { target; visibility; headers } ->
    C.Project_cmd
      (C.Target_precompile_headers
         { target = target_arg ~env target;
           items = items_with_kind ~env ~visibility headers })

  (* Custom target / command *)
  | ECmakeAddCustomCommand { outputs; commands; depends; comment; verbatim } ->
    let cc_list =
      List.map commands ~f:(fun (bc : build_command) ->
        ({ command = bc.command; args = bc.args } : C.custom_command))
    in
    let outputs = List.map outputs ~f:(target_arg ~env) in
    let depends = List.map depends ~f:(target_arg ~env) in
    C.Project_cmd
      (C.Add_custom_command
         { outputs; commands = cc_list; depends; comment;
           main_dependency = None; byproducts = []; implicit_depends = [];
           working_directory = None; depfile = None; job_pool = None;
           job_server_aware = false; verbatim; append = false;
           uses_terminal = false; codegen = false;
           command_expand_list = []; depends_explicit_only = false })
  | ECmakeAddCustomTarget { name; all; commands; depends; comment } ->
    let cc_list =
      List.map commands ~f:(fun (bc : build_command) ->
        ({ command = bc.command; args = bc.args } : C.custom_command))
    in
    C.Project_cmd
      (C.Add_custom_target
         { name = target_arg ~env name;
           all;
           commands = cc_list;
           depends = List.map depends ~f:(target_arg ~env);
           byproducts = [];
           working_directory = None;
           comment;
           job_pool = [];
           job_server_aware = false;
           verbatim = false;
           uses_terminal = false;
           command_expand_list = [];
           sources = [] })

  (* Add dependencies *)
  | ECmakeAddDependencies { target; deps } ->
    C.Project_cmd (C.Add_dependencies { target; deps })

  (* Try *)
  | Yelu_cmake_try.ECmakeTryCompile { result_var; sources } ->
    C.Project_cmd
      (C.Try_compile
         { tc_result_var = result_var;
           tc_sources = List.map sources ~f:(arg ~env);
           tc_compile_definitions = []; tc_link_libraries = [];
           tc_link_options = []; tc_cmake_flags = [];
           tc_output_variable = None; tc_copy_file = None;
           tc_no_cache = false;
           tc_c_standard = None; tc_cxx_standard = None })
  | Yelu_cmake_try.ECmakeTryCompileEx r ->
    C.Project_cmd
      (C.Try_compile
         { tc_result_var = r.result_var;
           tc_sources = List.map r.sources ~f:(arg ~env);
           tc_compile_definitions = List.map r.compile_definitions ~f:(arg ~env);
           tc_link_libraries = List.map r.link_libraries ~f:(arg ~env);
           tc_link_options = List.map r.link_options ~f:(arg ~env);
           tc_cmake_flags = [];
           tc_output_variable = r.output_variable;
           tc_copy_file = None;
           tc_no_cache = r.no_cache;
           tc_c_standard = r.c_standard;
           tc_cxx_standard = r.cxx_standard })
  | Yelu_cmake_try.ECmakeTryRun r ->
    C.Project_cmd
      (C.Try_run
         { tr_run_result_var = r.run_result_var;
           tr_compile_result_var = r.compile_result_var;
           tr_sources = List.map r.sources ~f:(arg ~env);
           tr_compile_definitions = List.map r.compile_definitions ~f:(arg ~env);
           tr_link_libraries = List.map r.link_libraries ~f:(arg ~env);
           tr_compile_output_variable = r.compile_output_variable;
           tr_run_output_variable = r.run_output_variable;
           tr_args = List.map r.args ~f:(arg ~env) })

  (* cmake_op long tail *)
  | ECmakeIncludeGuard { scope } ->
    let s = match scope with
      | "DIRECTORY" -> C.Ig_directory
      | "GLOBAL" -> C.Ig_global
      | _ -> fail "emit_ast: unknown include_guard scope %S" scope
    in
    C.Include_guard { scope = s }
  | ECmakeLanguageCall { cmd; args = call_args } ->
    (* Legacy compile maps cmake_language(CALL cmd args...) to a flat
       [Meta_call { cmd = Var_exp cmd; arg = [exp...] }] where each arg
       becomes a Var_exp / Quote exp directly. EVar in this position
       renders as the bare name (cmake_language CALL passes the var by
       name; the cmake-side dereferences). *)
    let arg_to_exp e : C.exp =
      match e with
      | EVar name -> C.Var_exp (target_arg ~env e |> fun _ -> name)
      | _ ->
        match arg ~env e with
        | C.Bare s -> C.Var_exp s
        | C.Quoted s -> C.Quote (Fmt.str "\"%s\"" s)
        | C.Bracket (level, s) ->
          let eqs = String.make level '=' in
          C.Var_exp (Fmt.str "[%s[%s]%s]" eqs s eqs)
    in
    C.Cmake_cmd
      (C.Cmake_meta_lang
         (C.Meta_call
            { cmd = C.Var_exp cmd;
              arg = List.map call_args ~f:arg_to_exp }))
  | ECmakeLanguageEval { code } ->
    C.Cmake_cmd (C.Cmake_meta_lang (C.Meta_eval { code }))
  | ECmakeLanguageGetLogLevel { out } ->
    C.Cmake_cmd (C.Cmake_meta_lang (C.Meta_get_msg_log_level { var = out }))
  | ECmakeSeparateArguments { var; mode; input } ->
    let m = match mode with
      | "PLAIN" -> C.Sa_plain
      | "UNIX_COMMAND" -> C.Sa_unix_command
      | "WINDOWS_COMMAND" -> C.Sa_windows_command
      | "NATIVE_COMMAND" -> C.Sa_native_command
      | _ -> fail "emit_ast: unknown separate_arguments mode %S" mode
    in
    C.Separete_arguments
      { var; mode = m; input = Option.map input ~f:(arg ~env) }

  (* String long tail *)
  | ECmakeStringPrepend { cvar; inputs } ->
    (* Legacy compile splits the first input into [prefix] and rest into
       [inputs] — pp emits "string(PREPEND var prefix inputs...)". *)
    let prefix, rest = match inputs with
      | [] -> C.Bare "", []
      | hd :: tl -> arg ~env hd, List.map tl ~f:(arg ~env)
    in
    C.String_cmd (C.Sc_prepend { var = cvar; prefix; inputs = rest })
  | ECmakeStringRegexQuote { out; inputs } ->
    C.String_cmd
      (C.Sc_regex
         (C.Sr_quote { out; inputs = List.map inputs ~f:(arg ~env) }))
  | ECmakeStringTimestamp { out; format; utc } ->
    C.String_cmd (C.Sc_timestamp { out; format; utc })
  | ECmakeStringGenexStrip { input; out } ->
    C.String_cmd (C.Sc_genex_strip { string = arg ~env input; out })
  | ECmakeStringMakeCIdentifier { input; out } ->
    C.String_cmd
      (C.Sc_make_c_identifier { string = arg ~env input; out })
  | ECmakeStringHex { input; out } ->
    C.String_cmd (C.Sc_hex { string = arg ~env input; out })
  | ECmakeStringUuid { out; namespace; name; type_; upper } ->
    let t = match type_ with
      | "MD5" -> `Md5 | "SHA1" -> `Sha1
      | _ -> fail "emit_ast: unknown uuid type %S" type_
    in
    C.String_cmd (C.Sc_uuid { out; namespace; name; type_ = t; upper })
  | ECmakeStringCompare { op; string1; string2; out } ->
    let cop = match op with
      | "LESS" -> C.Sco_less | "GREATER" -> C.Sco_greater
      | "EQUAL" -> C.Sco_equal | "NOTEQUAL" -> C.Sco_notequal
      | "LESS_EQUAL" -> C.Sco_less_equal
      | "GREATER_EQUAL" -> C.Sco_greater_equal
      | _ -> fail "emit_ast: unknown string compare op %S" op
    in
    C.String_cmd
      (C.Sc_compare
         { op = cop;
           string1 = arg ~env string1;
           string2 = arg ~env string2;
           out })

  (* List long tail *)
  | ECmakeListSublist { list; begin_; length; out } ->
    C.List_cmd (C.Lc_sublist { var = list; begin_; length; out })
  | ECmakeListFilter { list; mode; regex } ->
    let m = match mode with
      | "INCLUDE" -> C.Lf_include | "EXCLUDE" -> C.Lf_exclude
      | _ -> fail "emit_ast: unknown list filter mode %S" mode
    in
    C.List_cmd (C.Lc_filter { var = list; mode = m; regex })
  | ECmakeListPopFront { list; out_vars } ->
    C.List_cmd (C.Lc_pop_front { var = list; out_vars })
  | ECmakeListPopBack { list; out_vars } ->
    C.List_cmd (C.Lc_pop_back { var = list; out_vars })
  | ECmakeListSort { list; order; compare; case } ->
    let order = Option.map order ~f:(function
      | "ASCENDING" -> C.Ls_ascending | "DESCENDING" -> C.Ls_descending
      | _ -> fail "emit_ast: unknown list sort order")
    in
    let compare = Option.map compare ~f:(function
      | "STRING" -> C.Ls_string | "FILE_BASENAME" -> C.Ls_file_basename
      | "NATURAL" -> C.Ls_natural
      | _ -> fail "emit_ast: unknown list sort compare")
    in
    let case = Option.map case ~f:(function
      | "SENSITIVE" -> C.Ls_sensitive | "INSENSITIVE" -> C.Ls_insensitive
      | _ -> fail "emit_ast: unknown list sort case")
    in
    C.List_cmd (C.Lc_sort { var = list; order; compare; case })

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
     [yelu_cmake_emit_debug]: a bare value at statement position renders
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

  | _ ->
    (* Phase 1 coverage gap. The first-field-of-extension trick gets the
       ctor name as a string so the test oracle can group uncovered
       programs by their root constructor. *)
    let r = Stdlib.Obj.repr e in
    let name =
      if Stdlib.Obj.is_block r then
        let head = Stdlib.Obj.field r 0 in
        if Stdlib.Obj.tag head = Stdlib.Obj.object_tag
        then (Stdlib.Obj.magic (Stdlib.Obj.field head 0) : string)
        else "?"
      else "?"
    in
    fail "emit_ast gap: %s" name

(* Public API. *)

let emit_ast ?(env = empty_subst) (e : expr) : C.exp = emit_exp ~env e

let emit_script (e : expr) : string =
  let ast = emit_ast e in
  Fmt.str "%a" Lang_cmake_pp.pp ast
