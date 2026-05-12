(* Ergonomic constructors that produce Yelu1 IR ([Yelu_cmake_ir.expr])
   directly, mirroring the shape of [Lang_yelu_utils] (which builds
   the legacy [Lang_yelu_cmake] AST).

   Each helper here is a one-line wrapper around a Yelu1 ctor, so step
   files can switch their [open] from [Lang_yelu_utils] to this module
   and emit directly without the legacy AST → bridge round trip.

   For helpers whose legacy API takes a typed enum
   ([Lang_cmake.message_mode] etc.) but whose IR ctor takes a [string],
   we reuse the bridge's [string_of_*] helpers rather than
   re-enumerating each case.

   See doc/yelu_tiny/retirement_plan.md item E for context. *)

open Base
open Yelu_cmake_ir
open Yelu_theory_target  (* ETarget *)

(* ============================================================
   Expression helpers — return [expr]. Mirror legacy 1:1.
   ============================================================ *)

(* cvar/target names are bare strings in the IR. Identity helpers
   keep step-file readability ([ycvar "FOO"] reads better than ["FOO"]). *)
let ycvar (s : string) : string = s
let ytarget (s : string) : string = s

let yvar s = EVar s
let yname s = EVar s
let ycstr s = EVar s
let ytval s = ETarget s
let yfile s = EString s
let ydir s = EString s
let ypath s = EString s
let ykeyword s = EString s
let ystr s = EString s
let ybool b = EBool b

(* [${VAR}] inline refs stay as [EString] in Yelu1 (matching the
   legacy [Ycs_eval] flow); [$<...>] generator expressions go through
   [ECmakeGenex]. Mirrors [Yelu_parse.p_expr_y1]. *)
let ystr_eval s =
  if String.is_substring s ~substring:"$<" then
    Yelu_surface_cmake_string.ECmakeGenex s
  else
    EString s

let ycref s = ystr_eval (Fmt.str "${%s}" s)
let ycref_path s suffix = ystr_eval (Fmt.str "${%s}/%s" s suffix)

(* cmake directory constants — same string values as legacy. *)
let source_root = "PROJECT_SOURCE_DIR"
let output_root = "PROJECT_BINARY_DIR"
let source_this = "CMAKE_CURRENT_SOURCE_DIR"
let output_this = "CMAKE_CURRENT_BINARY_DIR"
let list_this = "CMAKE_CURRENT_LIST_DIR"

let dir d = ycref d
let dir_concat d suffix = ycref_path d suffix

(* ============================================================
   Let binding + sequence. Legacy [ylet] is sequence-shaped (binds
   the rest of the enclosing list); Yelu1 [ELet] is expression-shaped
   (carries its body inside). [ycmd_of_list] folds the body in, same
   logic as the bridge's [stmts_to_expr]
   ([yelu_cmake_legacy_bridge.ml:1056]).
   ============================================================ *)

let ylet name value = ELet { var = name; value; body = EUnit }

let rec ycmd_of_list = function
  | [] -> EUnit
  | [ ELet { var; value; body = EUnit } ] ->
    ELet { var; value; body = EUnit }
  | ELet { var; value; body = EUnit } :: rest ->
    ELet { var; value; body = ycmd_of_list rest }
  | [ s ] -> s
  | s :: rest -> ESeq [ s; ycmd_of_list rest ]

(* ============================================================
   Var family — set / option / unset / cache / env.
   Mirrors [yelu_cmake_legacy_bridge.var_statement] case-by-case.
   ============================================================ *)

open Yelu_surface_cmake_store

let yc_set ?(parent_scope = false) cvar values =
  let value =
    match values with
    | [] -> EString ""
    | [ v ] -> v
    | vs -> Yelu_theory_list.EList vs
  in
  if parent_scope then ECmakeSetParentScope { name = cvar; value }
  else ESetVar (cvar, value)

let yc_option ?(value = EBool false) ~msg cvar =
  ECmakeOption { name = cvar; message = msg; value }

let yc_unset_cache cvar = ECmakeUnsetVarCache cvar
let yc_set_env var value = ECmakeSetEnvVar { name = var; value }
let yc_unset_env var = ECmakeUnsetEnvVar var

let yc_set_cache
    ?(force = false)
    ?(cache_type = Lang_cmake.Ct_string)
    ?(docstring = "")
    cvar values =
  let cache_type_s = match cache_type with
    | Lang_cmake.Ct_bool -> "BOOL"
    | Lang_cmake.Ct_filepath -> "FILEPATH"
    | Lang_cmake.Ct_path -> "PATH"
    | Lang_cmake.Ct_string -> "STRING"
    | Lang_cmake.Ct_internal -> "INTERNAL"
  in
  ECmakeSetCache
    { name = cvar; values; cache_type = cache_type_s; docstring; force }

(* ============================================================
   cmake_op family — minimum_required / project / message / include /
   include_guard / function / macro / apply / foreach / while /
   break / continue / return / at_var / quote / math.
   Reuse bridge's [string_of_*] for enum→string conversion.
   ============================================================ *)

open Yelu_surface_cmake_cmake_op

let yc_minimum_required_s ?max:_ min_ =
  let v = Lang_cmake_utils.version_of_string min_ in
  ECmakeMinimumRequired (Yelu_cmake_legacy_bridge.string_of_version v)

let yc_project ?version ?(languages = []) name =
  let languages_s =
    List.map languages ~f:Yelu_cmake_legacy_bridge.string_of_supported_lang
  in
  let version_s =
    Option.map version ~f:Yelu_cmake_legacy_bridge.string_of_version
  in
  ECmakeProject { name; languages = languages_s; version = version_s }

(* Legacy [Ycmake_message] carries [texts : string list]; step files
   pass bare string literals. Wrap each as [EString] for the IR ctor
   (which carries [expr list]). *)
let yc_message ?(mode = Lang_cmake.Mm_status) texts =
  ECmakeMessage
    { mode = Yelu_cmake_legacy_bridge.string_of_message_mode mode;
      texts = List.map texts ~f:(fun s -> EString s) }

let yc_include ?(optional = false) file =
  ECmakeInclude { file; optional }

let yc_include_guard scope =
  let scope_s = match scope with
    | Lang_cmake.Ig_directory -> "DIRECTORY"
    | Lang_cmake.Ig_global -> "GLOBAL"
  in
  ECmakeIncludeGuard { scope = scope_s }

let yc_policy_set ?(new_ = true) id = ECmakePolicySet { id; new_ }

let yc_enable_language ?(optional = false) langs =
  let langs_s =
    List.map langs ~f:Yelu_cmake_legacy_bridge.string_of_supported_lang
  in
  ECmakeEnableLanguage { langs = langs_s; optional }

let yc_at_var key = ECmakeAtVar key
let yc_quote_cmd s = ECmakeQuoteCmd s

let yc_math exp out = ECmakeMath { exp; out }

(* Function / macro / apply. Legacy [Yc_function] / [Yc_macro] carry
   [name : yelu_expr] and [body : yelu_stmt list]; we mirror by taking
   [name : expr] and [body : expr list], folding via [ycmd_of_list]. *)
let yc_function name args body =
  ECmakeFunction { name; params = args; body = ycmd_of_list body }
let yc_macro name ?(args = []) body =
  ECmakeMacro { name; params = args; body = ycmd_of_list body }
let yc_apply name args = ECmakeApply { name; args }

(* Foreach / while / control flow. *)
let yc_foreach ?(items = []) loop_var body =
  ECmakeForeach { loop_var; items; body }

let yc_foreach_range ?start ?step ~stop loop_var body =
  ECmakeForeachRange { loop_var; start; stop; step; body }

let yc_foreach_in ?(lists = []) ?(items = []) loop_var body =
  ECmakeForeachInList { loop_var; lists; items; body }

let yc_foreach_zip loop_vars lists body =
  ECmakeForeachZip { loop_vars; lists; body }

let yc_while cond body = ECmakeWhile { cond; body }
let yc_break = ECmakeBreak
let yc_continue = ECmakeContinue
let yc_return ?(propogate_vars = []) () =
  ECmakeReturn { propagate_vars = propogate_vars }

(* ============================================================
   If / cond helpers. The IR uses theory ctors for the boolean
   shape ([ENot], [EAnd], [EOr]) and surface ctors for the
   cmake-specific atoms ([ECmakeStringEqual], [ECmakeTargetExists],
   [ECmakeVarDefined]).
   ============================================================ *)

open Yelu_surface_cmake_if

let yif cond then_ else_ =
  ECmakeIfStmt { cond; then_; else_ = Some else_ }
let yifthen cond then_ =
  ECmakeIfStmt { cond; then_; else_ = None }

(* Boolean / atom helpers used inside conds. *)
let ytruthy e = e
let ynot c = Yelu_theory_bool.ENot c
let yand a b = Yelu_theory_bool.EAnd (a, b)
let yor a b = Yelu_theory_bool.EOr (a, b)
let ystrequal a b = Yelu_surface_cmake_string.ECmakeStringEqual (a, b)
let yis_target e =
  match e with
  | ETarget _ -> Yelu_surface_cmake_target.ECmakeTargetExists e
  | EVar s | EString s ->
    Yelu_surface_cmake_target.ECmakeTargetExists (ETarget s)
  | _ -> failwith "yis_target: expected target name"
let yis_defined e =
  match e with
  | EVar s | EString s -> ECmakeVarDefined s
  | _ -> failwith "yis_defined: expected cvar name"

(* ============================================================
   Target family. Visibility groups carry cvar_kind from legacy AST;
   the bridge folds same-kind groups into ESeq always (even single
   groups). We mirror that for byte equality.
   ============================================================ *)

open Yelu_surface_cmake_target

let visibility_of_kind = function
  | Lang_yelu_cmake.Public -> "PUBLIC"
  | Lang_yelu_cmake.Private -> "PRIVATE"
  | Lang_yelu_cmake.Interface -> "INTERFACE"
  | Lang_yelu_cmake.Plain -> "PRIVATE"

let library_type_name = function
  | Lang_cmake.Lib_static -> "STATIC"
  | Lang_cmake.Lib_shared -> "SHARED"
  | Lang_cmake.Lib_module -> "MODULE"
  | Lang_cmake.Lib_unknown -> "UNKNOWN"
  | Lang_cmake.Lib_object -> "OBJECT"
  | Lang_cmake.Lib_interface -> "INTERFACE"
  | Lang_cmake.Lib_global -> "GLOBAL"

(* Visibility group at the IR-utils API. Legacy [yelu_items_with_kind]
   carries [yelu_expr list]; we carry [expr list] (IR) since helpers
   like [dir] now return [expr]. Same kind enum for source-level
   compatibility (step files write [~kind:Private] etc.). *)
type items_with_kind = {
  kind : Lang_yelu_cmake.target_kind;
  items : expr list;
}

type target_feature = {
  kind : Lang_yelu_cmake.target_kind;
  feature : string;
}

let ytarget_def ?(kind = Lang_yelu_cmake.Public) items : items_with_kind =
  { kind; items }

let ytarget_feature ?(kind = Lang_yelu_cmake.Public) feature : target_feature =
  { kind; feature }

let add_exe ?(exclude_from_all = false) ?(sources = []) name =
  if exclude_from_all then
    failwith "add_executable(EXCLUDE_FROM_ALL) not yet plumbed in IR utils";
  ECmakeAddExecutable { name; sources }

let add_lib ?(exclude_from_all = false) ?type_ ?(sources = []) name =
  if exclude_from_all then
    failwith "add_library(EXCLUDE_FROM_ALL) not yet plumbed in IR utils";
  ECmakeAddLibrary
    { name; type_ = Option.map type_ ~f:library_type_name; sources }

let add_lib_alias ~alias_of name =
  ECmakeAddLibraryAlias { name; target = alias_of }
let add_exe_alias ~alias_of name =
  ECmakeAddExecutableAlias { name; target = alias_of }

(* Legacy [Ytgt_add_library_imported.lib_type : string option];
   step files pass string literals (e.g. ["UNKNOWN"]). Mirror by
   taking string directly. *)
let add_lib_imported ?(global = false) ?lib_type name =
  ECmakeAddLibraryImported { name; lib_type; global }

let link_lib targets items =
  match targets with
  | [ target ] ->
    items
    |> List.map ~f:(fun ({ kind; items } : items_with_kind) ->
      ECmakeTargetLinkLibraries
        { target; visibility = visibility_of_kind kind; items })
    |> (fun xs -> ESeq xs)
  | _ ->
    failwith "link_lib: multi-target not yet plumbed in IR utils"

let include_dirs ?(before = false) ?(system = false) target items =
  items
  |> List.map ~f:(fun ({ kind; items } : items_with_kind) ->
    ECmakeTargetIncludeDirectories
      { target; visibility = visibility_of_kind kind;
        before; system; dirs = items })
  |> (fun xs -> ESeq xs)

let compile_defs target items =
  items
  |> List.map ~f:(fun ({ kind; items } : items_with_kind) ->
    ECmakeTargetCompileDefinitions
      { target; visibility = visibility_of_kind kind; definitions = items })
  |> (fun xs -> ESeq xs)

let compile_opts ?(before = false) target items =
  items
  |> List.map ~f:(fun ({ kind; items } : items_with_kind) ->
    ECmakeTargetCompileOptions
      { target; visibility = visibility_of_kind kind; before; options_ = items })
  |> (fun xs -> ESeq xs)

let compile_feats target features =
  features
  |> List.map ~f:(fun ({ kind; feature } : target_feature) ->
    ECmakeTargetCompileFeatures
      { target; visibility = visibility_of_kind kind;
        features = [ EString feature ] })
  |> (fun xs -> ESeq xs)

let yc_target_link_options ?(before = false) target items =
  items
  |> List.map ~f:(fun ({ kind; items } : items_with_kind) ->
    ECmakeTargetLinkOptions
      { target; visibility = visibility_of_kind kind; before; options_ = items })
  |> (fun xs -> ESeq xs)

let yc_target_link_directories ?(before = false) target items =
  items
  |> List.map ~f:(fun ({ kind; items } : items_with_kind) ->
    ECmakeTargetLinkDirectories
      { target; visibility = visibility_of_kind kind; before; dirs = items })
  |> (fun xs -> ESeq xs)

let yc_target_sources target items =
  items
  |> List.map ~f:(fun ({ kind; items } : items_with_kind) ->
    ECmakeTargetSources
      { target; visibility = visibility_of_kind kind; sources = items })
  |> (fun xs -> ESeq xs)

let yc_add_dependencies target dep =
  ECmakeAddDependencies { target; dep }

(* Custom commands / targets — IR uses [build_command] records
   ([command : string; args : string list]). Step files pass legacy
   [Lang_cmake.custom_command] records; we convert by name. *)
let custom_command command args : Lang_cmake.custom_command = { command; args }

let to_build_command (cc : Lang_cmake.custom_command) : build_command =
  { command = cc.command; args = cc.args }

let yc_add_custom_command
    ~outputs ?(depends = []) ?(verbatim = false)
    ?(comment : string option = None) commands =
  ECmakeAddCustomCommand
    { outputs;
      commands = List.map commands ~f:to_build_command;
      depends; verbatim; comment }

let yc_add_custom_target
    ?(all = false) ?(commands = []) ?(depends = [])
    ?(comment : string option = None) name =
  ECmakeAddCustomTarget
    { name = EString name; all;
      commands = List.map commands ~f:to_build_command;
      depends; comment }

(* target_sources(FILE_SET) — items are [ytsi_plain] / [ytsi_file_set_headers]. *)
let ytsi_plain kind items : tiny_target_sources_item =
  Tsi_plain { visibility = visibility_of_kind kind; items }
let ytsi_file_set_headers ?(base_dirs = []) ?(files = []) kind
    : tiny_target_sources_item =
  Tsi_file_set
    { kind = visibility_of_kind kind;
      type_ = "HEADERS";
      base_dirs; files }

let yc_target_sources_fs target items =
  ECmakeTargetSourcesFs { target; items }

(* ============================================================
   Directory family
   ============================================================ *)

open Yelu_surface_cmake_dir

let yc_add_subdirectory source_dir = ECmakeAddSubdirectory source_dir

let yc_include_directories ?(before = false) ?(system = false) dirs =
  ECmakeIncludeDirectories { dirs; before; system }

let yc_add_compile_definitions defs = ECmakeAddCompileDefinitions defs
let yc_add_compile_options options = ECmakeAddCompileOptions options
let yc_add_link_options options = ECmakeAddLinkOptions options
let yc_add_definitions defs = ECmakeAddDefinitions defs
let yc_link_directories ?(before = false) dirs =
  ECmakeLinkDirectories { dirs; before }

(* ============================================================
   Test family
   ============================================================ *)

open Yelu_surface_cmake_test

let yc_enable_testing = ECmakeEnableTesting
let yc_add_test name command args =
  ECmakeAddTest { name; command; args }

(* ============================================================
   Property family — mirrors bridge's [property_statement].
   ============================================================ *)

open Yelu_surface_cmake_property

let yc_set_tests_properties tests properties =
  ECmakeSetTestsProperties { tests; properties }

let yc_set_target_properties target properties =
  ESeq (List.map properties ~f:(fun (property, value) ->
    ECmakeSetTargetProperty { target; property; value }))

let yc_get_target_property var target property =
  ECmakeGetTargetProperty { var; target; property }

let yc_set_property ?(append = false) ~targets properties =
  ECmakeSetProperty { targets; append; properties }

let yc_set_global_property properties =
  ECmakeSetGlobalProperty { properties }

let yc_get_property ?(set = false) ~target property var =
  ECmakeGetProperty { var; target; property; set_form = set }

let yc_get_directory_property property var =
  ECmakeGetDirectoryProperty { var; property }

let yc_set_directory_property ?(append = false) property values =
  ECmakeSetDirectoryProperty { property; append; values }

let yc_set_source_property ?(property = "COMPILE_OPTIONS") file values =
  ECmakeSetSourceProperty { file; property; values }

let yc_get_global_property ~property var =
  ECmakeGetGlobalProperty { var; property }

(* ============================================================
   File family
   ============================================================ *)

open Yelu_surface_cmake_file

let yc_configure_file ~input output =
  ECmakeConfigureFile { input; output }
let gen_file = yc_configure_file

let yc_file_glob
    ?(recurse = false) ?(relative = None) ?(configure_depends = false)
    out patterns =
  ECmakeFileGlob { out; recurse; relative; configure_depends; patterns }

let yc_file_read ?(offset = None) ?(limit = None) ?(hex = false) out file =
  ECmakeFileReadFull { path = file; out; offset; limit; hex }

let yc_file_write ?(append = false) file content =
  if append then ECmakeFileWriteAppend { path = file; content }
  else ECmakeFileWrite { path = file; content }

let yc_file_append file content =
  ECmakeFileWriteAppend { path = file; content }

let yc_file_strings ?(regex = None) ?(encoding = None) ?(limit_count = None)
    out file =
  ECmakeFileStrings { out; path = file; regex; encoding; limit_count }

let yc_file_touch ?(nocreate = false) files =
  ECmakeFileTouch { files; nocreate }
let yc_file_make_directory dirs =
  ECmakeFileMakeDirectory { dirs }
let yc_file_rename ?(result = None) ?(no_replace = false) old_ new_ =
  ECmakeFileRename { old_; new_; result; no_replace }
let yc_file_remove ?(recurse = false) files =
  ECmakeFileRemove { files; recurse }
let yc_file_copy_file ?(result = None) ?(only_if_different = false) input output =
  ECmakeFileCopy { input; output; result; only_if_different }
let yc_file_real_path ?(base_dir = None) ?(expand_tilde = false) out path =
  ECmakeFileRealPath { out; path; base_dir; expand_tilde }
let yc_file_size out file = ECmakeFileSize { out; path = file }
let yc_file_read_symlink out link = ECmakeFileReadSymlink { out; link }
let yc_file_timestamp ?(format = None) ?(utc = false) out file =
  ECmakeFileTimestamp { out; path = file; format; utc }
let yc_file_relative_path ~var ~base file =
  let var_s = match var with
    | EVar s | EString s -> s
    | _ -> failwith "yc_file_relative_path: ~var must be a cvar name"
  in
  ECmakeFileRelativePath { var = var_s; base; file }

(* ============================================================
   Path family
   ============================================================ *)

(* Legacy [Ypath_get_filename_component] carries [mode] as a string
   already; pass through. *)
let yc_get_filename_component ~mode var filename =
  Yelu_surface_cmake_path.ECmakeGetFilenameComponent
    { var; filename; mode }

(* ============================================================
   Install family
   ============================================================ *)

open Yelu_surface_cmake_install

let yc_install_targets ?export targets destination =
  ECmakeInstallTargets { targets; destination; export }

let yc_install_files files destination =
  ECmakeInstallFiles { files; destination }

let yc_install_export ?file ?namespace export destination =
  ECmakeInstallExport { file; export; destination; namespace }

let yc_export_export ?file name =
  ECmakeExportExport { name; file }

let yc_configure_package_config_file
    ?(no_set_and_check_macro = false)
    ?(no_check_required_components_macro = false)
    install_dest input output =
  ECmakeConfigurePackageConfigFile
    { install_dest; input; output;
      no_set_and_check_macro; no_check_required_components_macro }

(* Legacy [Yinstall_write_basic_package_version_file.version] is
   [yelu_expr option] (step files pass [ystr_eval "..."] for runtime-
   expanded versions). Mirror by taking [expr option]. *)
let yc_write_basic_package_version_file
    ~compatibility ?(arch_independent = false) ?version file =
  ECmakeWriteBasicPackageVersionFile
    { file;
      version;
      compatibility = Yelu_cmake_legacy_bridge.string_of_compatibility compatibility;
      arch_independent }

(* ============================================================
   Find family — mirrors bridge's [find_statement]. The legacy AST
   carries no_default_path / no_cmake_environment_path etc. but the
   IR ctors drop them at this slice.
   ============================================================ *)

open Yelu_surface_cmake_find

let yc_find_library
    ?(names = []) ?(paths = []) ?(hints = [])
    ?(no_default_path = false) ?(no_cmake_environment_path = false)
    ?(no_system_environment_path = false) ?(required = false) cvar =
  let _ = no_default_path, no_cmake_environment_path,
          no_system_environment_path in
  ECmakeFindLibrary { out = cvar; names; paths; hints; required }

let yc_find_path
    ?(names = []) ?(paths = []) ?(hints = [])
    ?(no_default_path = false) ?(no_cmake_environment_path = false)
    ?(no_system_environment_path = false) ?(required = false) cvar =
  let _ = no_default_path, no_cmake_environment_path,
          no_system_environment_path in
  ECmakeFindPath { out = cvar; names; paths; hints; required }

let yc_find_program
    ?(names = []) ?(paths = []) ?(hints = [])
    ?(no_default_path = false) ?(no_cmake_environment_path = false)
    ?(no_system_environment_path = false) ?(required = false) cvar =
  let _ = no_default_path, no_cmake_environment_path,
          no_system_environment_path in
  ECmakeFindProgram { out = cvar; names; paths; hints; required }

let yc_find_file
    ?(names = []) ?(paths = []) ?(hints = [])
    ?(no_default_path = false) ?(no_cmake_environment_path = false)
    ?(no_system_environment_path = false) ?(required = false) cvar =
  let _ = no_default_path, no_cmake_environment_path,
          no_system_environment_path in
  ECmakeFindFile { out = cvar; names; paths; hints; required }

let yc_find_package
    ?(version = None) ?(exact = false) ?(quiet = false) ?(config_mode = false)
    ?(required = false) ?(components = []) ?(optional_components = []) name =
  ECmakeFindPackage
    { package_name = name; version; exact; quiet; config_mode;
      required; components; optional_components }

(* ============================================================
   List family
   ============================================================ *)

open Yelu_surface_cmake_list

let yc_list_append cvar values = ECmakeListAppend { list = cvar; items = values }
let yc_list_length cvar out = ECmakeListLength { list = cvar; out }
let yc_list_get ?(indices = []) cvar out = ECmakeListGet { list = cvar; indices; out }
let yc_list_remove_item cvar values = ECmakeListRemoveItem { list = cvar; items = values }
let yc_list_remove_duplicates cvar = ECmakeListRemoveDuplicates { list = cvar }
let yc_list_reverse cvar = ECmakeListReverse { list = cvar }
let yc_list_join cvar glue out = ECmakeListJoin { list = cvar; glue; out }
let yc_list_sublist cvar begin_ length out =
  ECmakeListSublist { list = cvar; begin_; length; out }
let yc_list_find cvar value out = ECmakeListFind { list = cvar; value; out }
let yc_list_prepend cvar values = ECmakeListPrepend { list = cvar; items = values }
let yc_list_insert cvar index values =
  ECmakeListInsert { list = cvar; index; items = values }
let yc_list_remove_at cvar indices =
  ECmakeListRemoveAt { list = cvar; indices }
let yc_list_pop_back ?(out_vars = []) cvar =
  ECmakeListPopBack { list = cvar; out_vars }
let yc_list_pop_front ?(out_vars = []) cvar =
  ECmakeListPopFront { list = cvar; out_vars }

(* ============================================================
   String family — only the helpers step files actually use.
   ============================================================ *)

open Yelu_surface_cmake_string

let yc_string_toupper input out = ECmakeStringToupper { input; out }
let yc_string_tolower input out = ECmakeStringTolower { input; out }
let yc_string_regex_replace regex replace out inputs =
  ECmakeStringRegexReplace { regex; replace; inputs; out }

(* ============================================================
   try_compile / try_run — minimal forms.
   ============================================================ *)

open Yelu_surface_cmake_try

let yc_try_compile result_var =
  ECmakeTryCompile { result_var; sources = [] }

let yc_try_run run_result compile_result =
  ECmakeTryRun
    { run_result_var = run_result;
      compile_result_var = compile_result;
      sources = []; compile_definitions = [];
      link_libraries = [];
      compile_output_variable = None;
      run_output_variable = None;
      args = [] }

(* ============================================================
   Extern declarations — IR doesn't track these as ctors today;
   step files use them only for documentation. Map to EUnit so
   builds compose without effect.
   ============================================================ *)

let yc_extern_cvar (_s : string) : expr = EUnit
let yc_extern_target (_s : string) : expr = EUnit

(* ============================================================
   Version / comparison helpers used inside conds.
   ============================================================ *)

let yversion_less a b = ECmakeVersionLess (a, b)
let yversion_greater a b = ECmakeVersionGreater (a, b)
let yversion_equal a b = ECmakeVersionEqual (a, b)
let yversion_less_equal a b = ECmakeVersionLessEqual (a, b)
let yversion_greater_equal a b = ECmakeVersionGreaterEqual (a, b)

(* Legacy [Yexpr_matches] carries [yelu_expr * string]; the regex is a
   raw string. Mirror by accepting string directly. *)
let ymatches value (regex : string) =
  ECmakeMatches { expr_ = value; regex }

let yin_list value list_ = ECmakeInList { item = value; list_ }
let yexists path =
  Yelu_surface_cmake_file.ECmakeFileExists path
let yis_directory path = ECmakeIsDirectory path
let yis_absolute path = ECmakeIsAbsolute path
let ypolicy_defined id = ECmakePolicyCheck id
