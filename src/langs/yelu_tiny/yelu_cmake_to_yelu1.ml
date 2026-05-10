open Base
open Yelu_tiny
open Yelu_surface_cmake_store
open Yelu_theory_bool
open Yelu_theory_target
open Yelu_surface_cmake_install
open Yelu_theory_list
open Yelu_surface_cmake_list
open Yelu_surface_cmake_path
open Yelu_surface_cmake_file
open Yelu_surface_cmake_string
open Yelu_surface_cmake_target
open Yelu_surface_cmake_cmake_op
open Yelu_surface_cmake_dir
open Yelu_surface_cmake_test
open Yelu_surface_cmake_property
open Yelu_surface_cmake_find
open Yelu_surface_cmake_try

module Old = Lang_yelu_cmake

exception Bridge_error of string

let fail fmt = Fmt.kstr (fun msg -> raise (Bridge_error msg)) fmt

let cvar_name ({ name; _ } : Old.tc_name) = name

let rec expr : Old.yelu_expr -> Yelu_tiny.expr = function
  | Yexpr_string (Ycs_path s | Ycs_keyword s | Ycs_string s | Ycs_eval s) ->
    EString s
  | Yexpr_bool b -> EBool b
  | Yexpr_var (Yvar name) -> EVar name
  | Yexpr_name { ns = Ns_var; name } -> EVar name
  | Yexpr_name { ns = Ns_target; name } -> ETarget name
  | Yexpr_name { name; _ } -> EString name
  | Yexpr_not cond -> ENot (expr cond)
  | Yexpr_and (left, right) -> EAnd (expr left, expr right)
  | Yexpr_or (left, right) -> EOr (expr left, expr right)
  | Yexpr_str_equal (left, right) -> ECmakeStringEqual (expr left, expr right)
  | Yexpr_is_defined { name; _ } -> ECmakeVarDefined name
  | Yexpr_is_target { ns = _; name } -> ECmakeTargetExists (ETarget name)
  | Yexpr_exists path -> ECmakeFileExists (expr path)
  | _ -> fail "unsupported yelu_cmake expression for Yelu1 bridge"

(* After phase 2b, target-name positions in tiny surface are typed [expr]
   (so that [EVar] / [ETarget] survive into emit and can be substituted by
   ELet bindings). [target_name] is now an alias for [expr] kept as
   documentation at call sites. *)
let target_name = expr

let command_name : Old.yelu_expr -> Yelu_tiny.expr = function
  | Yexpr_var (Yvar name) -> EString name
  | Yexpr_name { name; _ } -> EString name
  | e -> expr e

let one_input ~op = function
  | [ input ] -> expr input
  | inputs ->
    fail "%s bridge currently requires exactly one input, got %d"
      op (List.length inputs)

let string_statement : Old.yelu_string_stmt -> Yelu_tiny.expr = function
  | Ystr_concat { out; inputs } ->
    ECmakeStringConcat { out = cvar_name out; inputs = List.map inputs ~f:expr }
  | Ystr_toupper { string; out } ->
    ECmakeStringToupper { input = expr string; out = cvar_name out }
  | Ystr_replace { match_string; replace_string; out; inputs } ->
    ECmakeStringReplace
      {
        match_ = expr match_string;
        replace = expr replace_string;
        input = one_input ~op:"string(REPLACE)" inputs;
        out = cvar_name out;
      }
  | Ystr_length { string; out } ->
    ECmakeStringLength { input = expr string; out = cvar_name out }
  | Ystr_compare { op = Sco_equal; string1; string2; out } ->
    ESetVar (cvar_name out, ECmakeStringEqual (expr string1, expr string2))
  | _ -> fail "unsupported yelu_cmake string statement for Yelu1 bridge"

let var_statement : Old.yelu_var_stmt -> Yelu_tiny.expr = function
  | Yvar_set { cvar; values = [ value ]; parent_scope = false } ->
    ESetVar (cvar_name cvar, expr value)
  | Yvar_set { cvar; values = []; parent_scope = false } ->
    ESetVar (cvar_name cvar, EString "")
  | Yvar_set { cvar; values; parent_scope = false } ->
    ESetVar (cvar_name cvar, EList (List.map values ~f:expr))
  | Yvar_set { parent_scope = true; _ } ->
    fail "set(PARENT_SCOPE) is outside the first Yelu1 bridge slice"
  | Yvar_option { cvar; msg; value } ->
    ECmakeOption { name = cvar_name cvar; message = msg; value = expr value }
  | _ -> fail "unsupported yelu_cmake variable statement for Yelu1 bridge"

let list_index ~indices =
  match indices with
  | [ index ] -> EInt index
  | [] -> fail "list(GET) bridge requires one index; parser does not expose one yet"
  | _ -> fail "list(GET) bridge currently supports exactly one index"

let list_statement : Old.yelu_list_stmt -> Yelu_tiny.expr = function
  | Ylist_append { cvar; values } ->
    ECmakeListAppend { list = cvar_name cvar; items = List.map values ~f:expr }
  | Ylist_get { cvar; indices; out } ->
    ECmakeListGet
      { list = cvar_name cvar; index = list_index ~indices; out = cvar_name out }
  | Ylist_length { cvar; out } ->
    ECmakeListLength { list = cvar_name cvar; out = cvar_name out }
  | Ylist_join { cvar; glue; out } ->
    ECmakeListJoin { list = cvar_name cvar; glue = expr glue; out = cvar_name out }
  | _ -> fail "unsupported yelu_cmake list statement for Yelu1 bridge"

let path_statement : Old.yelu_path_stmt -> Yelu_tiny.expr = function
  | Ypath_set { path_var; input; normalize } ->
    ECmakePathSet { path = cvar_name path_var; input = expr input; normalize }
  | Ypath_get { path_var; field = Cpf_filename; out } ->
    ECmakePathGetFilename { path = cvar_name path_var; out = cvar_name out }
  | Ypath_normal_path { path_var; out } ->
    ECmakePathNormalPath
      { path = cvar_name path_var; out = Option.map out ~f:cvar_name }
  | _ -> fail "unsupported yelu_cmake path statement for Yelu1 bridge"

let file_statement : Old.yelu_file_io_stmt -> Yelu_tiny.expr = function
  | Yfile_write { file; append = false; content } ->
    ECmakeFileWrite { path = expr file; content = List.map content ~f:expr }
  | Yfile_write { append = true; _ } ->
    fail "file(APPEND) is outside the current Yelu1 bridge slice"
  | Yfile_read { out; file; offset = None; limit = None; hex = false } ->
    ECmakeFileRead { path = expr file; out = cvar_name out }
  | Yfile_read { offset = Some _; _ } ->
    fail "file(READ OFFSET) is outside the current Yelu1 bridge slice"
  | Yfile_read { limit = Some _; _ } ->
    fail "file(READ LIMIT) is outside the current Yelu1 bridge slice"
  | Yfile_read { hex = true; _ } ->
    fail "file(READ HEX) is outside the current Yelu1 bridge slice"
  | Yfile_configure { input; output } ->
    ECmakeConfigureFile { input = expr input; output = expr output }
  | _ -> fail "unsupported yelu_cmake file statement for Yelu1 bridge"

let string_of_version (v : Lang_cmake.version) =
  let patch = if String.length v.patch = 0 then "" else "." ^ v.patch in
  Fmt.str "%d.%d%s" v.major v.minor patch

let string_of_supported_lang : Lang_cmake.supported_lang -> string = function
  | Lang_none -> "NONE"
  | Lang_c -> "C"
  | Lang_cxx -> "CXX"
  | Lang_csharp -> "CSharp"
  | Lang_cuda -> "CUDA"
  | Lang_objc -> "OBJC"
  | Lang_objcxx -> "OBJCXX"
  | Lang_fortran -> "Fortran"
  | Lang_hipy -> "HIP"
  | Lang_ispc -> "ISPC"
  | Lang_swift -> "Swift"
  | Lang_asm -> "ASM"
  | Lang_asm_nasm -> "ASM_NASM"
  | Lang_asm_marmasm -> "ASM_MARMASM"
  | Lang_asm_masm -> "ASM_MASM"
  | Lang_asm_att -> "ASM_ATT"

let string_of_message_mode : Lang_cmake.message_mode -> string = function
  | Mm_none -> ""
  | Mm_status -> "STATUS"
  | Mm_notice -> "NOTICE"
  | Mm_verbose -> "VERBOSE"
  | Mm_debug -> "DEBUG"
  | Mm_trace -> "TRACE"
  | Mm_warning -> "WARNING"
  | Mm_author_warning -> "AUTHOR_WARNING"
  | Mm_check_start -> "CHECK_START"
  | Mm_check_pass -> "CHECK_PASS"
  | Mm_check_fail -> "CHECK_FAIL"
  | Mm_send_error -> "SEND_ERROR"
  | Mm_fatal_error -> "FATAL_ERROR"
  | Mm_deprecation -> "DEPRECATION"

let cmake_op_statement : Old.yelu_cmake_stmt -> Yelu_tiny.expr = function
  | Ycmake_minimum_required { min; max = _ } ->
    (* The optional max is currently dropped; the tiny env only tracks min. *)
    ECmakeMinimumRequired (string_of_version min)
  | Ycmake_project { name; version; languages } ->
    ECmakeProject
      {
        name;
        languages = List.map languages ~f:string_of_supported_lang;
        version = Option.map version ~f:string_of_version;
      }
  | Ycmake_message { mode; texts } ->
    ECmakeMessage
      {
        mode = string_of_message_mode mode;
        texts = List.map texts ~f:(fun s -> EString s);
      }
  | _ -> fail "unsupported yelu_cmake cmake_op statement for Yelu1 bridge"

let dir_statement : Old.yelu_dir_stmt -> Yelu_tiny.expr = function
  | Ydir_add_subdirectory { source_dir } ->
    ECmakeAddSubdirectory (expr source_dir)
  | _ -> fail "unsupported yelu_cmake dir statement for Yelu1 bridge"

let test_statement : Old.yelu_test_stmt -> Yelu_tiny.expr = function
  | Ytest_enable_testing -> ECmakeEnableTesting
  | Ytest_add_test { name; command; args } ->
    ECmakeAddTest
      { name = expr name; command = expr command; args = List.map args ~f:expr }

let property_statement : Old.yelu_property_stmt -> Yelu_tiny.expr = function
  | Yprop_set_tests { tests; properties } ->
    ECmakeSetTestsProperties
      {
        tests = List.map tests ~f:expr;
        properties = List.map properties ~f:(fun (property, value) -> property, expr value);
      }
  | Yprop_set_target { target; properties } ->
    properties
    |> List.map ~f:(fun (property, value) ->
      ECmakeSetTargetProperty
        { target = target_name target; property; value = expr value })
    |> ESeq
  | Yprop_get_target { var; target; property } ->
    ECmakeGetTargetProperty
      { var = cvar_name var; target = ETarget target; property }
  | _ -> fail "unsupported yelu_cmake property statement for Yelu1 bridge"

let find_statement : Old.yelu_find_stmt -> Yelu_tiny.expr = function
  | Yfind_package { name; version = None; exact = false; quiet = false;
                    config_mode = false; required;
                    components = []; optional_components = [] } ->
    ECmakeFindPackage { package_name = name; required }
  | Yfind_package _ ->
    fail "find_package(VERSION/EXACT/COMPONENTS/CONFIG) is outside the current Yelu1 bridge slice"
  | _ -> fail "unsupported yelu_cmake find statement for Yelu1 bridge"

let try_statement : Old.yelu_try_stmt -> Yelu_tiny.expr = function
  | Ytry_compile { result_var; sources;
                   compile_definitions = [];
                   link_libraries = [];
                   link_options = [];
                   output_variable = None;
                   no_cache = false;
                   c_standard = None;
                   cxx_standard = None } ->
    ECmakeTryCompile
      { result_var = cvar_name result_var;
        sources = List.map sources ~f:expr }
  | Ytry_compile _ ->
    fail "try_compile(extras) is outside the current Yelu1 bridge slice"
  | _ -> fail "unsupported yelu_cmake try statement for Yelu1 bridge"

let visibility_of_kind = function
  | Old.Public -> "PUBLIC"
  | Old.Private -> "PRIVATE"
  | Old.Interface -> "INTERFACE"
  | Old.Plain -> "PRIVATE"

let build_command ({ command; args } : Lang_cmake.custom_command) =
  { command; args }

let library_type_name = function
  | Lang_cmake.Lib_static -> "STATIC"
  | Lang_cmake.Lib_shared -> "SHARED"
  | Lang_cmake.Lib_module -> "MODULE"
  | Lang_cmake.Lib_unknown -> "UNKNOWN"
  | Lang_cmake.Lib_object -> "OBJECT"
  | Lang_cmake.Lib_interface -> "INTERFACE"
  | Lang_cmake.Lib_global -> "GLOBAL"

let target_statement : Old.yelu_target_stmt -> Yelu_tiny.expr = function
  | Ytgt_add_executable { name; sources; exclude_from_all = false } ->
    ECmakeAddExecutable { name = target_name name; sources = List.map sources ~f:expr }
  | Ytgt_add_executable { exclude_from_all = true; _ } ->
    fail "add_executable(EXCLUDE_FROM_ALL) is outside the first Yelu1 bridge slice"
  | Ytgt_add_library { name; type_; sources; exclude_from_all = false } ->
    ECmakeAddLibrary
      {
        name = target_name name;
        type_ = Option.map type_ ~f:library_type_name;
        sources = List.map sources ~f:expr;
      }
  | Ytgt_add_library { exclude_from_all = true; _ } ->
    fail "add_library(EXCLUDE_FROM_ALL) is outside the current Yelu1 bridge slice"
  | Ytgt_sources { target; items } ->
    items
    |> List.map ~f:(fun ({ kind; items } : Old.yelu_items_with_kind) ->
      ECmakeTargetSources
        {
          target = target_name target;
          visibility = visibility_of_kind kind;
          sources = List.map items ~f:expr;
        })
    |> ESeq
  | Ytgt_link_libraries { targets = [ target ]; items } ->
    items
    |> List.map ~f:(fun ({ kind; items } : Old.yelu_items_with_kind) ->
      ECmakeTargetLinkLibraries
        {
          target = target_name target;
          visibility = visibility_of_kind kind;
          items = List.map items ~f:expr;
        })
    |> ESeq
  | Ytgt_link_libraries { targets; _ } ->
    fail "target_link_libraries bridge currently supports exactly one target, got %d"
      (List.length targets)
  | Ytgt_include_directories { target; before = false; system = false; items } ->
    items
    |> List.map ~f:(fun ({ kind; items } : Old.yelu_items_with_kind) ->
      ECmakeTargetIncludeDirectories
        {
          target = target_name target;
          visibility = visibility_of_kind kind;
          dirs = List.map items ~f:expr;
        })
    |> ESeq
  | Ytgt_include_directories { before = true; _ } ->
    fail "target_include_directories(BEFORE) is outside the current Yelu1 bridge slice"
  | Ytgt_include_directories { system = true; _ } ->
    fail "target_include_directories(SYSTEM) is outside the current Yelu1 bridge slice"
  | Ytgt_compile_definitions { target; items } ->
    items
    |> List.map ~f:(fun ({ kind; items } : Old.yelu_items_with_kind) ->
      ECmakeTargetCompileDefinitions
        {
          target = target_name target;
          visibility = visibility_of_kind kind;
          definitions = List.map items ~f:expr;
        })
    |> ESeq
  | Ytgt_compile_options { target; before = false; items } ->
    items
    |> List.map ~f:(fun ({ kind; items } : Old.yelu_items_with_kind) ->
      ECmakeTargetCompileOptions
        {
          target = target_name target;
          visibility = visibility_of_kind kind;
          options_ = List.map items ~f:expr;
        })
    |> ESeq
  | Ytgt_compile_options { before = true; _ } ->
    fail "target_compile_options(BEFORE) is outside the current Yelu1 bridge slice"
  | Ytgt_compile_features { target; features } ->
    features
    |> List.map ~f:(fun ({ kind; feature } : Old.yelu_target_feature) ->
      ECmakeTargetCompileFeatures
        {
          target = target_name target;
          visibility = visibility_of_kind kind;
          features = [ EString feature ];
        })
    |> ESeq
  | Ytgt_link_options { target; before = false; items } ->
    items
    |> List.map ~f:(fun ({ kind; items } : Old.yelu_items_with_kind) ->
      ECmakeTargetLinkOptions
        {
          target = target_name target;
          visibility = visibility_of_kind kind;
          options_ = List.map items ~f:expr;
        })
    |> ESeq
  | Ytgt_link_options { before = true; _ } ->
    fail "target_link_options(BEFORE) is outside the current Yelu1 bridge slice"
  | Ytgt_link_directories { target; before = false; items } ->
    items
    |> List.map ~f:(fun ({ kind; items } : Old.yelu_items_with_kind) ->
      ECmakeTargetLinkDirectories
        {
          target = target_name target;
          visibility = visibility_of_kind kind;
          dirs = List.map items ~f:expr;
        })
    |> ESeq
  | Ytgt_link_directories { before = true; _ } ->
    fail "target_link_directories(BEFORE) is outside the current Yelu1 bridge slice"
  | Ytgt_add_custom_target { name; all; commands; depends; comment } ->
    ECmakeAddCustomTarget
      {
        name = EString name;
        all;
        commands = List.map commands ~f:build_command;
        depends = List.map depends ~f:expr;
        comment;
      }
  | Ytgt_add_custom_command { outputs; commands; depends; verbatim; comment } ->
    ECmakeAddCustomCommand
      {
        outputs = List.map outputs ~f:expr;
        commands = List.map commands ~f:build_command;
        depends = List.map depends ~f:expr;
        comment;
        verbatim;
      }
  | _ -> fail "unsupported yelu_cmake target statement for Yelu1 bridge"

let install_statement : Old.yelu_install_stmt -> Yelu_tiny.expr = function
  | Yinstall_targets { targets; destination; export } ->
    ECmakeInstallTargets
      {
        targets = List.map targets ~f:target_name;
        destination = expr destination;
        export = Option.map export ~f:expr;
      }
  | Yinstall_files { files; destination } ->
    ECmakeInstallFiles { files = List.map files ~f:expr; destination = expr destination }
  | _ -> fail "unsupported yelu_cmake install statement for Yelu1 bridge"

let rec stmt : Old.yelu_stmt -> Yelu_tiny.expr = function
  | Ys_string string_stmt -> string_statement string_stmt
  | Ys_list list_stmt -> list_statement list_stmt
  | Ys_path path_stmt -> path_statement path_stmt
  | Ys_file file_stmt -> file_statement file_stmt
  | Ys_target target_stmt -> target_statement target_stmt
  | Ys_install install_stmt -> install_statement install_stmt
  | Ys_var var_stmt -> var_statement var_stmt
  | Ys_cmake cmake_stmt -> cmake_op_statement cmake_stmt
  | Ys_dir dir_stmt -> dir_statement dir_stmt
  | Ys_test test_stmt -> test_statement test_stmt
  | Ys_property prop_stmt -> property_statement prop_stmt
  | Ys_find find_stmt -> find_statement find_stmt
  | Ys_try try_stmt -> try_statement try_stmt
  | Yc_extern_cvar _ | Yc_extern_target _ -> EUnit
  | Yc_function { name; args; body } ->
    ECmakeFunction { name = command_name name; args; body = stmts_to_expr body }
  | Yc_apply { name; args } ->
    ECmakeApply { name = command_name name; args = List.map args ~f:expr }
  (* Production [Ylet] is sequence-shaped (its scope is the rest of the
     enclosing list). Tiny's [ELet] is expression-shaped. The conversion
     happens in [stmts_to_expr] when handling [Ystmt_list]; a standalone
     [Ylet] outside a sequence has no observable scope, so we emit an empty
     [body] for completeness. *)
  | Ylet { var = Yvar name; value } ->
    ELet { var = name; value = expr value; body = EUnit }
  | Yif { cond; then_; else_ } ->
    Yelu_surface_cmake_if.ECmakeIfStmt
      {
        cond = expr cond;
        then_ = stmt then_;
        else_ = Option.map else_ ~f:stmt;
      }
  | Ystmt_list stmts -> stmts_to_expr stmts
  | _ -> fail "unsupported yelu_cmake statement for Yelu1 bridge"

(* Walk a statement list, recognising [Ylet] as an expression-let whose body
   is the remainder of the list. Other statements are sequenced via [ESeq]
   right-nested. Single-element lists collapse to that element. *)
and stmts_to_expr = function
  | [] -> EUnit
  | [Old.Ylet { var = Yvar name; value }] ->
    ELet { var = name; value = expr value; body = EUnit }
  | Old.Ylet { var = Yvar name; value } :: rest ->
    ELet { var = name; value = expr value; body = stmts_to_expr rest }
  | [s] -> stmt s
  | s :: rest -> ESeq [ stmt s; stmts_to_expr rest ]
