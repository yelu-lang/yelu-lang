(* Ergonomic constructors that produce [Yelu_cmake.expr] directly.
   This module is the single source of truth for step binaries and
   tests building yelu_cmake IR; the legacy bridge / Lang_yelu_utils
   path was retired in E1.

   Each helper is a one-line wrapper around a yelu_cmake ctor.

   Enum-to-string conversions for ctors that take [string] where the
   legacy surface took a typed enum live in
   [Lang_cmake_strings] (in the cmake layer).

   See doc/yelu_cmake/retirement_plan.md for the migration history.

   === Stub helpers (track in doc/yelu_cmake/status.md "Known IR
   shape gaps") ===

   Some helpers in this file accept arguments the IR cannot yet
   represent. Two flavors:

   - **Accept-and-discard** (safe semantic weakening): the cmake
     output is still legal and the discarded option only affects
     a feature we do not yet model.
       - [yc_math ~output_format]      drops the format
                                       (always emits decimal).
       - [add_exe ~exclude_from_all]
         / [add_lib ~exclude_from_all] drop the flag (affects
                                       `make all`, not configure).

   - **Failwith** (callers must wait for IR support): the helper
     refuses to emit until the IR grows the relevant ctor.
       - [ystrless] / [ystrgreater] / [ystrless_equal]
         / [ystrgreater_equal]         (STRLESS / STRGREATER family;
                                        IR currently has only
                                        STREQUAL via ECmakeStringEqual)
       - [yc_add_custom_command_target] (TARGET-form custom command;
                                        IR has only the OUTPUT form)
       - [yc_string_json_*]            (JSON ops; IR's
                                        ECmakeStringJson collapses
                                        to an opaque op_name)
   *)

open Base
open Yelu_cmake
open Yelu_cmake_normal_target  (* ETarget *)

(* Re-export the cmake-level visibility / library / language enums so
   step files (which used to [open Yelu_langs.Lang_yelu_cmake] for
   [Private], [Lib_static], etc.) can get them via this module alone.
   The legacy [Lang_yelu_cmake] file does the same trick. *)
type target_kind = Lang_cmake.target_kind =
  | Public
  | Private
  | Interface
  | Plain

type library_type = Lang_cmake.library_type =
  | Lib_static
  | Lib_shared
  | Lib_module
  | Lib_unknown
  | Lib_object
  | Lib_interface
  | Lib_global

(* ============================================================
   Expression helpers — return [expr]. Mirror legacy 1:1.
   ============================================================ *)

(* cvar/target names are bare strings in the IR. Identity helpers
   keep step-file readability ([ycvar "FOO"] reads better than ["FOO"]). *)
let ycvar (s : string) : string = s
let ytarget (s : string) : string = s

let yvar s = EVar s
(* yname is an unscoped name (Ns_unknown in legacy). Bridge maps
   Yexpr_name{Ns_unknown} to EString (literal), distinct from EVar
   (which emits as ${name}). *)
let yname s = EString s
let ycstr s = EVar s
let ytval s = ETarget s
let yfile s = EString s
let ydir s = EString s
let ypath s = EString s
let ykeyword s = EString s
let ystr s = EString s
let ybool b = EBool b

(* [${VAR}] inline refs stay as [EString] in yelu_cmake (matching the
   legacy [Ycs_eval] flow); [$<...>] generator expressions go through
   [ECmakeGenex]. Mirrors [Yelu_parse.p_expr_y1]. *)
let ystr_eval s =
  if String.is_substring s ~substring:"$<" then
    Yelu_cmake_string.ECmakeGenex s
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
   the rest of the enclosing list); yelu_cmake [ELet] is expression-shaped
   (carries its body inside). [ycmd_of_list] folds the body in, same
   logic as the bridge's [stmts_to_expr]
   ([yelu_cmake_legacy_bridge.ml:1056]).
   ============================================================ *)

(* Mirror the legacy bridge's [let_value] transformation
   (yelu_cmake_legacy_bridge.ml). In argument position, [ycstr "X"] / [EVar "X"]
   means "deref the cmake var X" (emits [${X}]); in let-value position the
   user means "bind the compile-time name to the cmake symbol [X]". Without
   the demotion, [emit_debug.arg] would loop expanding [EVar "X"] under an
   env that maps [X] back to [EVar "X"]. *)
let ylet name value =
  let value = match value with
    | EVar n -> EString n
    | v -> v
  in
  ELet { var = name; value; body = EUnit }

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

open Yelu_cmake_store

let yc_set ?(parent_scope = false) cvar values =
  let value =
    match values with
    | [] -> EString ""
    | [ v ] -> v
    | vs -> Yelu_cmake_normal_list.EList vs
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

open Yelu_cmake_cmake_op

let yc_minimum_required_s ?max:_ min_ =
  let v = Lang_cmake_utils.version_of_string min_ in
  ECmakeMinimumRequired (Lang_cmake_strings.of_version v)

let yc_project ?version ?(languages = []) name =
  let languages_s =
    List.map languages ~f:Lang_cmake_strings.of_supported_lang
  in
  let version_s =
    Option.map version ~f:Lang_cmake_strings.of_version
  in
  ECmakeProject { name; languages = languages_s; version = version_s }

(* Legacy [Ycmake_message] carries [texts : string list]; step files
   pass bare string literals. Wrap each as [EString] for the IR ctor
   (which carries [expr list]). *)
let message_mode_of_string = function
  | "STATUS" -> Lang_cmake.Mm_status
  | "WARNING" -> Lang_cmake.Mm_warning
  | "AUTHOR_WARNING" -> Lang_cmake.Mm_author_warning
  | "FATAL_ERROR" -> Lang_cmake.Mm_fatal_error
  | "SEND_ERROR" -> Lang_cmake.Mm_fatal_error
  | "NOTICE" -> Lang_cmake.Mm_notice
  | "VERBOSE" -> Lang_cmake.Mm_verbose
  | "DEBUG" -> Lang_cmake.Mm_debug
  | "TRACE" -> Lang_cmake.Mm_trace
  | "CHECK_START" -> Lang_cmake.Mm_check_start
  | "" -> Lang_cmake.Mm_none
  | s -> failwith (Printf.sprintf "unknown message mode: %s" s)

let yc_message ?(mode = Lang_cmake.Mm_status) texts =
  ECmakeMessage
    { mode = Lang_cmake_strings.of_message_mode mode;
      texts = List.map texts ~f:(fun s -> EString s) }

let yc_message_mode mode_string texts =
  yc_message ~mode:(message_mode_of_string mode_string) texts

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
    List.map langs ~f:Lang_cmake_strings.of_supported_lang
  in
  ECmakeEnableLanguage { langs = langs_s; optional }

let yc_at_var key = ECmakeAtVar key
let yc_quote_cmd s = ECmakeQuoteCmd s
let yc_raw text = ECmakeRaw text

(* [~output_format] is accepted for legacy parity but discarded — the IR
   does not yet carry the format. The bridge does the same
   ([output_format = _] in yelu_cmake_legacy_bridge.ml). *)
let yc_math ?output_format:_ exp out = ECmakeMath { exp; out }

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

open Yelu_cmake_if

let yif cond then_ else_ =
  ECmakeIfStmt { cond; then_; else_ = Some else_ }
let yifthen cond then_ =
  ECmakeIfStmt { cond; then_; else_ = None }

(* Boolean / atom helpers used inside conds. *)
let ytruthy e = e
let ynot c = Yelu_cmake_normal_bool.ENot c
let yand a b = Yelu_cmake_normal_bool.EAnd (a, b)
let yor a b = Yelu_cmake_normal_bool.EOr (a, b)
let ystrequal a b = Yelu_cmake_string.ECmakeStringEqual (a, b)
let yless a b = Yelu_cmake_normal_int.EIntLess (a, b)
let ygreater a b = Yelu_cmake_normal_int.EIntGreater (a, b)
let yless_equal a b = Yelu_cmake_normal_int.EIntLessEqual (a, b)
let ygreater_equal a b = Yelu_cmake_normal_int.EIntGreaterEqual (a, b)
let yequal a b = Yelu_cmake_normal_int.EIntEqual (a, b)

(* String-order comparisons (STRLESS / STRGREATER / STRLESS_EQUAL /
   STRGREATER_EQUAL). The legacy compile path emitted these directly,
   but the IR does not yet have a string-order cond ctor (the legacy
   bridge also raised). Fail explicitly rather than emit ECmakeStringEqual
   silently — wrong-shape stubs are worse than missing helpers. *)
let ystrless _ _ =
  failwith "ystrless: IR does not yet model STRLESS; see status.md \"Known IR shape gaps\""
let ystrgreater _ _ =
  failwith "ystrgreater: IR does not yet model STRGREATER; see status.md \"Known IR shape gaps\""
let ystrless_equal _ _ =
  failwith "ystrless_equal: IR does not yet model STRLESS_EQUAL; see status.md \"Known IR shape gaps\""
let ystrgreater_equal _ _ =
  failwith "ystrgreater_equal: IR does not yet model STRGREATER_EQUAL; see status.md \"Known IR shape gaps\""
let yis_target e =
  match e with
  | ETarget _ -> Yelu_cmake_target.ECmakeTargetExists e
  | EVar s | EString s ->
    Yelu_cmake_target.ECmakeTargetExists (ETarget s)
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

open Yelu_cmake_target

let visibility_of_kind = function
  | Lang_cmake.Public -> "PUBLIC"
  | Lang_cmake.Private -> "PRIVATE"
  | Lang_cmake.Interface -> "INTERFACE"
  | Lang_cmake.Plain -> "PRIVATE"

let vis_of_kind k : visibility = match k with
  | Lang_cmake.Public -> Vis_public
  | Lang_cmake.Private -> Vis_private
  | Lang_cmake.Interface -> Vis_interface
  | Lang_cmake.Plain -> Vis_private

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
  kind : Lang_cmake.target_kind;
  items : expr list;
}

type target_feature = {
  kind : Lang_cmake.target_kind;
  feature : string;
}

let ytarget_def ?(kind = Lang_cmake.Public) items : items_with_kind =
  { kind; items }

let ytarget_feature ?(kind = Lang_cmake.Public) feature : target_feature =
  { kind; feature }

(* [~exclude_from_all] is accepted but dropped: the IR
   [ECmakeAddExecutable] / [ECmakeAddLibrary] do not carry the flag.
   The bridge does the same. Tests pass because EXCLUDE_FROM_ALL
   only affects "make all" behavior, not configure-time output. *)
let add_exe ?exclude_from_all:_ ?(sources = []) name =
  ECmakeAddExecutable { name; sources }

let add_lib ?exclude_from_all:_ ?type_ ?(sources = []) name =
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
        { target; visibility = vis_of_kind kind; items })
    |> (fun xs -> ESeq xs)
  | _ ->
    failwith "link_lib: multi-target not yet plumbed in IR utils"

let include_dirs ?(before = false) ?(system = false) target items =
  items
  |> List.map ~f:(fun ({ kind; items } : items_with_kind) ->
    ECmakeTargetIncludeDirectories
      { target; visibility = vis_of_kind kind;
        before; system; dirs = items })
  |> (fun xs -> ESeq xs)

let compile_defs target items =
  items
  |> List.map ~f:(fun ({ kind; items } : items_with_kind) ->
    ECmakeTargetCompileDefinitions
      { target; visibility = vis_of_kind kind; definitions = items })
  |> (fun xs -> ESeq xs)

let compile_opts ?(before = false) target items =
  items
  |> List.map ~f:(fun ({ kind; items } : items_with_kind) ->
    ECmakeTargetCompileOptions
      { target; visibility = vis_of_kind kind; before; options_ = items })
  |> (fun xs -> ESeq xs)

let compile_feats target features =
  features
  |> List.map ~f:(fun ({ kind; feature } : target_feature) ->
    ECmakeTargetCompileFeatures
      { target; visibility = vis_of_kind kind;
        features = [ EString feature ] })
  |> (fun xs -> ESeq xs)

let yc_target_link_options ?(before = false) target items =
  items
  |> List.map ~f:(fun ({ kind; items } : items_with_kind) ->
    ECmakeTargetLinkOptions
      { target; visibility = vis_of_kind kind; before; options_ = items })
  |> (fun xs -> ESeq xs)

let yc_target_link_directories ?(before = false) target items =
  items
  |> List.map ~f:(fun ({ kind; items } : items_with_kind) ->
    ECmakeTargetLinkDirectories
      { target; visibility = vis_of_kind kind; before; dirs = items })
  |> (fun xs -> ESeq xs)

let yc_target_sources target items =
  items
  |> List.map ~f:(fun ({ kind; items } : items_with_kind) ->
    ECmakeTargetSources
      { target; visibility = vis_of_kind kind; sources = items })
  |> (fun xs -> ESeq xs)

let yc_add_dependencies target deps =
  ECmakeAddDependencies { target; deps }

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

(* TARGET-form add_custom_command. The legacy bridge raised on this and
   the IR has no dedicated TARGET-form ctor. Emitting empty-outputs
   ECmakeAddCustomCommand was the previous stub, but that produces a
   different cmake command shape entirely (OUTPUT-form with no outputs).
   Fail explicitly until the IR grows a TARGET-form ctor. *)
let yc_add_custom_command_target
    ?verbatim:_ ?comment:_ ~target:_ ~when_:_ _commands =
  failwith "yc_add_custom_command_target: IR does not yet model TARGET-form add_custom_command; see status.md \"Known IR shape gaps\""

let cw_pre_build  = Lang_cmake.Cw_pre_build
let cw_pre_link   = Lang_cmake.Cw_pre_link
let cw_post_build = Lang_cmake.Cw_post_build

(* target_sources(FILE_SET) — items are [ytsi_plain] / [ytsi_file_set_headers]. *)
let ytsi_plain kind items : tiny_target_sources_item =
  Tsi_plain { visibility = vis_of_kind kind; items }
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

open Yelu_cmake_dir

let yc_add_subdirectory source_dir = ECmakeAddSubdirectory source_dir

let yc_include_directories ?(before = false) ?(system = false) dirs =
  ECmakeIncludeDirectories { dirs; before; system }

let yc_add_compile_definitions defs = ECmakeAddCompileDefinitions defs
let yc_add_compile_options options = ECmakeAddCompileOptions options
let yc_add_link_options options = ECmakeAddLinkOptions options
let yc_add_definitions defs = ECmakeAddDefinitions defs
let yc_link_directories ?(before = false) dirs =
  ECmakeLinkDirectories { dirs; before }

(* Directory-level [link_libraries(...)] — rare; the bridge renders it as
   [ECmakeAddLinkOptions] (a stub directive at this slice). *)
let yc_link_libraries items = ECmakeAddLinkOptions items

(* ============================================================
   Test family
   ============================================================ *)

open Yelu_cmake_test

let yc_enable_testing = ECmakeEnableTesting
let yc_add_test name command args =
  ECmakeAddTest { name; command; args }

(* ============================================================
   Property family — mirrors bridge's [property_statement].
   ============================================================ *)

open Yelu_cmake_property

let yc_set_tests_properties tests properties =
  ECmakeSetTestsProperties { tests; properties }

let yc_set_target_properties target properties =
  ESeq (List.map properties ~f:(fun (property, value) ->
    ECmakeSetTargetProperty { target; property; value }))

(* Legacy [Yprop_get_target.target] is a string; bridge wraps it
   in ETarget for the IR. Mirror by accepting string and wrapping. *)
let yc_get_target_property var target property =
  ECmakeGetTargetProperty { var; target = ETarget target; property }

let yc_set_property ?(append = false) ~targets properties =
  ECmakeSetProperty { targets; append; properties }

let yc_set_property_source ?(append = false) ~files properties =
  ECmakeSetPropertySource { files; append; properties }

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

let yc_set_source_files_properties files properties =
  ECmakeSetSourceFilesProperties { files; properties }

let yc_get_global_property ~property var =
  ECmakeGetGlobalProperty { var; property }

(* ============================================================
   File family
   ============================================================ *)

open Yelu_cmake_file

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
  Yelu_cmake_path.ECmakeGetFilenameComponent
    { var; filename; mode }

(* ============================================================
   Install family
   ============================================================ *)

open Yelu_cmake_install

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
      compatibility = Lang_cmake_strings.of_compatibility compatibility;
      arch_independent }

(* ============================================================
   Find family — mirrors bridge's [find_statement]. The legacy AST
   carries no_default_path / no_cmake_environment_path etc. but the
   IR ctors drop them at this slice.
   ============================================================ *)

open Yelu_cmake_find

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

open Yelu_cmake_list

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

(* yc_list_transform: action / selector are kept as opaque strings,
   matching the bridge's translation. *)
let yc_list_transform ?selector ?output cvar action =
  let action_s = match action with
    | Lang_cmake.Lta_append _ -> "APPEND"
    | Lang_cmake.Lta_prepend _ -> "PREPEND"
    | Lang_cmake.Lta_toupper -> "TOUPPER"
    | Lang_cmake.Lta_tolower -> "TOLOWER"
    | Lang_cmake.Lta_strip -> "STRIP"
    | Lang_cmake.Lta_genex_strip -> "GENEX_STRIP"
    | Lang_cmake.Lta_replace _ -> "REPLACE"
  in
  let selector_s = Option.map selector ~f:(function
    | Lang_cmake.Lts_at _ -> "AT"
    | Lang_cmake.Lts_for _ -> "FOR"
    | Lang_cmake.Lts_regex _ -> "REGEX")
  in
  ECmakeListTransform { list = cvar; action = action_s; selector = selector_s; output }

(* ============================================================
   String family — only the helpers step files actually use.
   ============================================================ *)

open Yelu_cmake_string

let yc_string_toupper input out = ECmakeStringToupper { input; out }
let yc_string_tolower input out = ECmakeStringTolower { input; out }
let yc_string_regex_replace regex replace out inputs =
  ECmakeStringRegexReplace { regex; replace; inputs; out }

(* ============================================================
   try_compile / try_run — minimal forms.
   ============================================================ *)

open Yelu_cmake_try

(* Legacy yc_try_compile carries the full keyword-arg payload;
   bridge folds default-empty payload into the simple
   [ECmakeTryCompile] and non-default into [ECmakeTryCompileEx].
   Mirror that split here so call sites that pass no kwargs get
   the simple ctor. *)
let yc_try_compile
    ?(compile_definitions = []) ?(link_libraries = [])
    ?(link_options = []) ?(output_variable = None)
    ?(no_cache = false) ?(c_standard = None) ?(cxx_standard = None)
    result_var sources =
  if List.is_empty compile_definitions
     && List.is_empty link_libraries
     && List.is_empty link_options
     && Option.is_none output_variable
     && (not no_cache)
     && Option.is_none c_standard
     && Option.is_none cxx_standard
  then ECmakeTryCompile { result_var; sources }
  else
    ECmakeTryCompileEx
      { result_var; sources; compile_definitions; link_libraries;
        link_options; output_variable; no_cache; c_standard; cxx_standard }

let yc_try_run
    ?(compile_definitions = []) ?(link_libraries = [])
    ?(compile_output_variable = None) ?(run_output_variable = None)
    ?(args = [])
    run_result_var compile_result_var sources =
  ECmakeTryRun
    { run_result_var; compile_result_var; sources;
      compile_definitions; link_libraries;
      compile_output_variable; run_output_variable; args }

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
  Yelu_cmake_file.ECmakeFileExists path
let yis_directory path = ECmakeIsDirectory path
let yis_absolute path = ECmakeIsAbsolute path
let ypolicy_defined id = ECmakePolicyCheck id

(* ============================================================
   E1: helpers added so test_yelu_compile can drop legacy AST
   construction. Each wraps the matching IR ctor 1:1; signatures
   mirror the legacy [Lang_yelu_utils] equivalents so the swap is
   a pure [open] change at the call site.

   For helpers whose legacy API takes a typed enum but whose IR
   ctor takes a [string], we either reuse [Lang_cmake_strings]
   (for path enums shared with the bridge) or inline the match
   (for enums only this module needs).
   ============================================================ *)

(* --- Path family --- *)

open Yelu_cmake_path

let yc_path_set ?(normalize = false) path_var input =
  ECmakePathSet { path = path_var; input; normalize }

let yc_path_get path_var field out =
  match field with
  | Lang_cmake.Cpf_filename ->
    ECmakePathGetFilename { path = path_var; out }
  | _ ->
    ECmakePathGet
      { path = path_var;
        field = Lang_cmake_strings.of_cmake_path_get_field field;
        out }

let yc_path_has path_var field out =
  ECmakePathHas
    { path = path_var;
      field = Lang_cmake_strings.of_cmake_path_has_field field;
      out }

let yc_path_is_absolute path_var out =
  ECmakePathIsAbsolute { path = path_var; out }

let yc_path_is_relative path_var out =
  ECmakePathIsRelative { path = path_var; out }

let yc_path_is_prefix ?(normalize = false) path_var input out =
  ECmakePathIsPrefix { path = path_var; input; normalize; out }

let yc_path_compare input1 op input2 out =
  ECmakePathCompare
    { input1;
      op = Lang_cmake_strings.of_cmake_path_compare_op op;
      input2;
      out }

let yc_path_append ?(out = None) path_var inputs =
  ECmakePathAppend { path = path_var; inputs; out }

let yc_path_append_string ?(out = None) path_var inputs =
  ECmakePathAppendString { path = path_var; inputs; out }

let yc_path_remove_filename ?(out = None) path_var =
  ECmakePathRemoveFilename { path = path_var; out }

let yc_path_replace_filename ?(out = None) path_var input =
  ECmakePathReplaceFilename { path = path_var; input; out }

let yc_path_remove_extension ?(last_only = false) ?(out = None) path_var =
  ECmakePathRemoveExtension { path = path_var; last_only; out }

let yc_path_replace_extension
    ?(last_only = false) ?(out = None) path_var input =
  ECmakePathReplaceExtension { path = path_var; last_only; input; out }

let yc_path_normal_path ?(out = None) path_var =
  ECmakePathNormalPath { path = path_var; out }

let yc_path_relative_path ?(base_dir = None) ?(out = None) path_var =
  ECmakePathRelativePath { path = path_var; base_dir; out }

let yc_path_absolute_path
    ?(base_dir = None) ?(normalize = false) ?(out = None) path_var =
  ECmakePathAbsolutePath { path = path_var; base_dir; normalize; out }

let yc_path_native_path ?(normalize = false) path_var out =
  ECmakePathNativePath { path = path_var; normalize; out }

let yc_path_convert_to_cmake ?(normalize = false) input out =
  ECmakePathConvertToCmake { input; normalize; out }

let yc_path_convert_to_native ?(normalize = false) input out =
  ECmakePathConvertToNative { input; normalize; out }

let yc_path_hash path_var out =
  ECmakePathHash { path = path_var; out }

(* --- String family additions --- *)

let yc_string_concat out inputs = ECmakeStringConcat { inputs; out }
let yc_string_length string out = ECmakeStringLength { input = string; out }
let yc_string_strip string out = ECmakeStringStrip { input = string; out }
let yc_string_join glue out inputs = ECmakeStringJoin { glue; out; inputs }

let yc_string_substring string begin_ ?length out =
  ECmakeStringSubstring { string; begin_; length; out }

let yc_string_repeat string count out =
  ECmakeStringRepeat { string; count; out }

let yc_string_genex_strip string out =
  ECmakeStringGenexStrip { input = string; out }

let yc_string_make_c_identifier string out =
  ECmakeStringMakeCIdentifier { input = string; out }

let yc_string_timestamp ?(utc = false) ?format out =
  ECmakeStringTimestamp { out; format; utc }

let yc_string_compare op string1 string2 out =
  let op_s = match op with
    | Lang_cmake.Sco_less -> "LESS"
    | Lang_cmake.Sco_greater -> "GREATER"
    | Lang_cmake.Sco_equal -> "EQUAL"
    | Lang_cmake.Sco_notequal -> "NOTEQUAL"
    | Lang_cmake.Sco_less_equal -> "LESS_EQUAL"
    | Lang_cmake.Sco_greater_equal -> "GREATER_EQUAL"
  in
  ECmakeStringCompare { op = op_s; string1; string2; out }

let yc_string_hex string out = ECmakeStringHex { input = string; out }

let yc_string_uuid ?(upper = false) ~namespace ~name ~type_ out =
  let type_s = match type_ with `Md5 -> "MD5" | `Sha1 -> "SHA1" in
  ECmakeStringUuid { out; namespace; name; type_ = type_s; upper }

(* JSON ops. The legacy bridge collapsed every JSON op into an opaque
   ECmakeStringJson with op_name = "JSON_op" and dropped the path /
   sub-op detail; emit_ast then materialized that as an empty
   string(JSON ... GET) regardless of the original intent — silently
   wrong cmake. Fail explicitly until the IR carries the JSON op + path
   discriminator. *)
let yc_string_json_get ?error_var:_ ?path:_ ~out:_ _ =
  failwith "yc_string_json_get: IR's ECmakeStringJson is opaque; see status.md \"Known IR shape gaps\""

let yc_string_json_get_raw ?error_var:_ ?path:_ ~out:_ _ =
  failwith "yc_string_json_get_raw: IR's ECmakeStringJson is opaque; see status.md \"Known IR shape gaps\""

let yc_string_json_type ?error_var:_ ?path:_ ~out:_ _ =
  failwith "yc_string_json_type: IR's ECmakeStringJson is opaque; see status.md \"Known IR shape gaps\""

let yc_string_json_length ?error_var:_ ?path:_ ~out:_ _ =
  failwith "yc_string_json_length: IR's ECmakeStringJson is opaque; see status.md \"Known IR shape gaps\""

let yc_string_json_member ?error_var:_ ?path:_ ~out:_ _ =
  failwith "yc_string_json_member: IR's ECmakeStringJson is opaque; see status.md \"Known IR shape gaps\""

let yc_string_json_remove ?error_var:_ ?path:_ ~out:_ _ =
  failwith "yc_string_json_remove: IR's ECmakeStringJson is opaque; see status.md \"Known IR shape gaps\""

let yc_string_json_set ?error_var:_ ?path:_ ~out:_ ~value:_ _ =
  failwith "yc_string_json_set: IR's ECmakeStringJson is opaque; see status.md \"Known IR shape gaps\""

let yc_string_json_equal ~out:_ _ _ =
  failwith "yc_string_json_equal: IR's ECmakeStringJson is opaque; see status.md \"Known IR shape gaps\""

let yc_string_json_string_encode ~out:_ _ =
  failwith "yc_string_json_string_encode: IR's ECmakeStringJson is opaque; see status.md \"Known IR shape gaps\""

let yc_string_append cvar inputs = ECmakeStringAppend { cvar; inputs }
let yc_string_prepend cvar inputs = ECmakeStringPrepend { cvar; inputs }

let yc_string_find ?(reverse = false) string substring out =
  ECmakeStringFind { string; substring; out; reverse }

let yc_string_regex_quote out inputs =
  ECmakeStringRegexQuote { out; inputs }

let yc_string_regex_match regex out inputs =
  ECmakeStringRegexMatch { regex; out; inputs }

let yc_string_regex_matchall regex out inputs =
  ECmakeStringRegexMatchAll { regex; out; inputs }

(* Legacy [Ystr_replace] takes [inputs : yelu_expr list]; the IR
   [ECmakeStringReplace] takes a single [input : expr]. Mirror the
   bridge's [one_input] policy: if more than one, fail at construct
   time. *)
let yc_string_replace match_string replace_string out inputs =
  let input = match inputs with
    | [ x ] -> x
    | [] -> EString ""
    | _ -> failwith "yc_string_replace: exactly one input supported"
  in
  ECmakeStringReplace
    { match_ = match_string; replace = replace_string; input; out }

(* --- List family additions (sort + filter) --- *)

let yc_list_sort ?order ?compare ?case cvar =
  let order_s = Option.map order ~f:(function
    | Lang_cmake.Ls_ascending -> "ASCENDING"
    | Lang_cmake.Ls_descending -> "DESCENDING")
  in
  let compare_s = Option.map compare ~f:(function
    | Lang_cmake.Ls_string -> "STRING"
    | Lang_cmake.Ls_file_basename -> "FILE_BASENAME"
    | Lang_cmake.Ls_natural -> "NATURAL")
  in
  let case_s = Option.map case ~f:(function
    | Lang_cmake.Ls_sensitive -> "SENSITIVE"
    | Lang_cmake.Ls_insensitive -> "INSENSITIVE")
  in
  Yelu_cmake_list.ECmakeListSort
    { list = cvar; order = order_s; compare = compare_s; case = case_s }

let yc_list_filter mode regex cvar =
  let mode_s = match mode with
    | Lang_cmake.Lf_include -> "INCLUDE"
    | Lang_cmake.Lf_exclude -> "EXCLUDE"
  in
  Yelu_cmake_list.ECmakeListFilter { list = cvar; mode = mode_s; regex }

(* --- cmake_op / misc additions --- *)

(* Legacy [yc_block] takes [body : yelu_stmt list]; the IR's
   [ECmakeBlock] carries a single body [expr]. Fold the list. *)
let yc_block ?(scope_vars = []) ?(propagate = "") body =
  ECmakeBlock { scope_vars; propagate; body = ycmd_of_list body }

let yc_execute_process
    ?(working_directory = None) ?(timeout = None)
    ?(result_variable = None) ?(output_variable = None)
    ?(error_variable = None) ?(input_file = None) ?(output_file = None)
    ?(error_file = None) ?(output_quiet = false) ?(error_quiet = false)
    ?(output_strip_trailing_whitespace = false)
    ?(error_strip_trailing_whitespace = false)
    ?(command_error_is_fatal = None) commands =
  ECmakeExecuteProcess
    { commands; working_directory; timeout;
      result_variable; output_variable; error_variable;
      input_file; output_file; error_file;
      output_quiet; error_quiet;
      output_strip_trailing_whitespace;
      error_strip_trailing_whitespace;
      command_error_is_fatal }

(* [?input] (rather than [?(input = None)]) so callers can pass
   [~input:e] without explicit [Some], matching the legacy signature. *)
let yc_separate_arguments ?input ~mode cvar =
  let mode_s = match mode with
    | Lang_cmake.Sa_plain -> "PLAIN"
    | Lang_cmake.Sa_unix_command -> "UNIX_COMMAND"
    | Lang_cmake.Sa_windows_command -> "WINDOWS_COMMAND"
    | Lang_cmake.Sa_native_command -> "NATIVE_COMMAND"
    | Lang_cmake.Sa_program -> "PROGRAM"
    | Lang_cmake.Sa_args -> "ARGS"
  in
  ECmakeSeparateArguments { var = cvar; mode = mode_s; input }

let yc_separate_arguments_plain cvar =
  yc_separate_arguments ~mode:Lang_cmake.Sa_plain cvar

let yc_language_call cmd args = ECmakeLanguageCall { cmd; args }
let yc_language_eval code = ECmakeLanguageEval { code }
let yc_language_get_log_level out = ECmakeLanguageGetLogLevel { out }

let yc_variable_watch ?(command = None) var =
  ECmakeVariableWatch { var; command }

(* --- Property addition --- *)

let yc_define_property
    ?(inherited = false) ?(brief_docs = []) ?(full_docs = [])
    ?(initialize_from = None) mode property_name =
  let mode_s = match mode with
    | Lang_cmake.Dp_global -> "GLOBAL"
    | Lang_cmake.Dp_directory -> "DIRECTORY"
    | Lang_cmake.Dp_target -> "TARGET"
    | Lang_cmake.Dp_source -> "SOURCE"
    | Lang_cmake.Dp_test -> "TEST"
    | Lang_cmake.Dp_variable -> "VARIABLE"
    | Lang_cmake.Dp_cached_variable -> "CACHED_VARIABLE"
  in
  ECmakeDefineProperty
    { mode = mode_s; property_name; inherited;
      brief_docs; full_docs; initialize_from }

(* --- Target addition --- *)

let yc_target_precompile_headers target items =
  (* Legacy carries [items] as a [yelu_items_with_kind list]; the IR
     [ECmakeTargetPrecompileHeaders] takes [visibility : string] and
     [headers : expr list]. Mirror the bridge's per-group ESeq fold. *)
  items
  |> List.map ~f:(fun ({ kind; items } : items_with_kind) ->
    ECmakeTargetPrecompileHeaders
      { target; visibility = vis_of_kind kind; headers = items })
  |> (fun xs -> ESeq xs)
