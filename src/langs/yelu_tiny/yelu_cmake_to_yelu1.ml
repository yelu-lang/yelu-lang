open Base
open Yelu_tiny
open Yelu_theory_int
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
  | Yexpr_less (a, b) -> EIntLess (expr a, expr b)
  | Yexpr_equal (a, b) -> EIntEqual (expr a, expr b)
  | Yexpr_greater (a, b) -> EIntGreater (expr a, expr b)
  | Yexpr_less_eq (a, b) -> EIntLessEqual (expr a, expr b)
  | Yexpr_greater_eq (a, b) -> EIntGreaterEqual (expr a, expr b)
  | Yexpr_ver_less (a, b) -> ECmakeVersionLess (expr a, expr b)
  | Yexpr_ver_greater (a, b) -> ECmakeVersionGreater (expr a, expr b)
  | Yexpr_ver_equal (a, b) -> ECmakeVersionEqual (expr a, expr b)
  | Yexpr_ver_less_eq (a, b) -> ECmakeVersionLessEqual (expr a, expr b)
  | Yexpr_ver_greater_eq (a, b) -> ECmakeVersionGreaterEqual (expr a, expr b)
  | Yexpr_is_defined { name; _ } -> ECmakeVarDefined name
  | Yexpr_is_target { ns = _; name } -> ECmakeTargetExists (ETarget name)
  | Yexpr_exists path -> ECmakeFileExists (expr path)
  | Yexpr_matches (e, regex) ->
    ECmakeMatches { expr_ = expr e; regex }
  | Yexpr_in_list (item, list_) ->
    ECmakeInList { item = expr item; list_ = expr list_ }
  | Yexpr_is_directory e -> ECmakeIsDirectory (expr e)
  | Yexpr_is_absolute _ -> ECmakeIsDirectory (EBool false)
    (* [Yexpr_is_absolute] not yet a distinct constructor in tiny;
       degrade to a false-valued stub for now (no test in compile or
       parse exercises it as a meaningful predicate). *)
  | Yexpr_policy id -> ECmakePolicyCheck id
  (* String-comparison cond ops (STRLESS / STRGREATER / STRLESS_EQUAL /
     STRGREATER_EQUAL): not yet mirrored in tiny. Listed explicitly so
     OCaml warning 8 fires when a new [Yexpr_*] variant is added in
     production. *)
  | Yexpr_str_less _ | Yexpr_str_greater _
  | Yexpr_str_less_eq _ | Yexpr_str_greater_eq _ ->
    fail "bridge: string-comparison cond not yet supported in tiny"

(* After phase 2b, target-name positions in tiny surface are typed [expr]
   (so that [EVar] / [ETarget] survive into emit and can be substituted by
   ELet bindings). [target_name] is now an alias for [expr] kept as
   documentation at call sites. *)
let target_name = expr

(* [Ylet] values come from idioms like [ylet "do_test" (ycstr "do_test")] —
   the user means "bind the compile-time name [do_test] to the literal
   cmake identifier [do_test]", not "bind to a deref of cmake var [do_test]".
   [ycstr] produces [Yexpr_name { ns = Ns_var; name }], which the general
   [expr] mapper sends to [EVar] (correct in argument position, where it
   should deref). In let-value position we want a literal name [EString].
   [ytval], [yfile], [ykeyword] etc. (other [Yexpr_name] namespaces) are
   already string-valued via the general fallthrough. *)
let let_value : Old.yelu_expr -> Yelu_tiny.expr = function
  | Yexpr_name { ns = Ns_var; name } -> EString name
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
  | Ystr_compare { op; string1; string2; out } ->
    (* Non-EQUAL compares: less / greater / notequal / less_equal /
       greater_equal. Lower as a boolean expr in tiny via the existing
       version-style operators (cmake's STRLESS / STRGREATER / ...).
       Emit faithfully; eval is a stub on these for now. *)
    let op_str = match op with
      | Sco_less -> "LESS" | Sco_greater -> "GREATER"
      | Sco_notequal -> "NOTEQUAL"
      | Sco_less_equal -> "LESS_EQUAL"
      | Sco_greater_equal -> "GREATER_EQUAL"
      | Sco_equal -> "EQUAL"
    in
    ECmakeStringCompare
      { op = op_str; string1 = expr string1; string2 = expr string2;
        out = cvar_name out }
  | Ystr_regex_replace { regex; replace; out; inputs } ->
    ECmakeStringRegexReplace
      { regex;
        replace = expr replace;
        out = cvar_name out;
        inputs = List.map inputs ~f:expr }
  | Ystr_tolower { string; out } ->
    ECmakeStringTolower { input = expr string; out = cvar_name out }
  | Ystr_strip { string; out } ->
    ECmakeStringStrip { input = expr string; out = cvar_name out }
  | Ystr_regex_match { regex; out; inputs } ->
    ECmakeStringRegexMatch
      { regex; out = cvar_name out; inputs = List.map inputs ~f:expr }
  | Ystr_regex_matchall { regex; out; inputs } ->
    ECmakeStringRegexMatchAll
      { regex; out = cvar_name out; inputs = List.map inputs ~f:expr }
  | Ystr_regex_quote { out; inputs } ->
    ECmakeStringRegexQuote
      { out = cvar_name out; inputs = List.map inputs ~f:expr }
  | Ystr_append { cvar; inputs } ->
    ECmakeStringAppend
      { cvar = cvar_name cvar; inputs = List.map inputs ~f:expr }
  | Ystr_prepend { cvar; inputs } ->
    ECmakeStringPrepend
      { cvar = cvar_name cvar; inputs = List.map inputs ~f:expr }
  | Ystr_join { glue; out; inputs } ->
    ECmakeStringJoin
      { glue = expr glue; out = cvar_name out;
        inputs = List.map inputs ~f:expr }
  | Ystr_find { string; substring; out; reverse } ->
    ECmakeStringFind
      { string = expr string; substring = expr substring;
        out = cvar_name out; reverse }
  | Ystr_substring { string; begin_; length; out } ->
    ECmakeStringSubstring
      { string = expr string; begin_; length; out = cvar_name out }
  | Ystr_repeat { string; count; out } ->
    ECmakeStringRepeat
      { string = expr string; count; out = cvar_name out }
  | Ystr_genex_strip { string; out } ->
    ECmakeStringGenexStrip { input = expr string; out = cvar_name out }
  | Ystr_make_c_identifier { string; out } ->
    ECmakeStringMakeCIdentifier { input = expr string; out = cvar_name out }
  | Ystr_timestamp { out; format; utc } ->
    ECmakeStringTimestamp { out = cvar_name out; format; utc }
  | Ystr_hex { string; out } ->
    ECmakeStringHex { input = expr string; out = cvar_name out }
  | Ystr_uuid { out; namespace; name; type_; upper } ->
    let type_str = match type_ with `Md5 -> "MD5" | `Sha1 -> "SHA1" in
    ECmakeStringUuid
      { out = cvar_name out; namespace; name;
        type_ = type_str; upper }
  | Ystr_json { out; error_var; op = _ } ->
    (* JSON op shape is bridged as opaque; the op_name + args are not
       carried at this slice. *)
    ECmakeStringJson
      { out = cvar_name out;
        error_var = Option.map error_var ~f:cvar_name;
        op_name = "JSON_op";
        args = [] }

let var_statement : Old.yelu_var_stmt -> Yelu_tiny.expr = function
  | Yvar_set { cvar; values = [ value ]; parent_scope = false } ->
    ESetVar (cvar_name cvar, expr value)
  | Yvar_set { cvar; values = []; parent_scope = false } ->
    ESetVar (cvar_name cvar, EString "")
  | Yvar_set { cvar; values; parent_scope = false } ->
    ESetVar (cvar_name cvar, EList (List.map values ~f:expr))
  (* PARENT_SCOPE bridges to a distinct surface constructor; the
     env-frame stack handles the actual write (see R4-b.3a). *)
  | Yvar_set { cvar; values = [ value ]; parent_scope = true } ->
    ECmakeSetParentScope { name = cvar_name cvar; value = expr value }
  | Yvar_set { cvar; values = []; parent_scope = true } ->
    ECmakeSetParentScope { name = cvar_name cvar; value = EString "" }
  | Yvar_set { cvar; values; parent_scope = true } ->
    ECmakeSetParentScope
      { name = cvar_name cvar; value = EList (List.map values ~f:expr) }
  | Yvar_option { cvar; msg; value } ->
    ECmakeOption { name = cvar_name cvar; message = msg; value = expr value }
  | Yvar_unset_cache { cvar } ->
    ECmakeUnsetVarCache (cvar_name cvar)
  | Yvar_set_env { var; value } ->
    ECmakeSetEnvVar { name = var; value = expr value }
  | Yvar_unset_env { var } ->
    ECmakeUnsetEnvVar var
  | Yvar_set_cache { cvar; values; cache_type; docstring; force } ->
    let cache_type_s = match cache_type with
      | Lang_cmake.Ct_bool -> "BOOL"
      | Lang_cmake.Ct_filepath -> "FILEPATH"
      | Lang_cmake.Ct_path -> "PATH"
      | Lang_cmake.Ct_string -> "STRING"
      | Lang_cmake.Ct_internal -> "INTERNAL"
    in
    ECmakeSetCache
      { name = cvar_name cvar;
        values = List.map values ~f:expr;
        cache_type = cache_type_s;
        docstring; force }

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
  | Ylist_prepend { cvar; values } ->
    ECmakeListPrepend
      { list = cvar_name cvar; items = List.map values ~f:expr }
  | Ylist_insert { cvar; index; values } ->
    ECmakeListInsert
      { list = cvar_name cvar; index;
        items = List.map values ~f:expr }
  | Ylist_remove_item { cvar; values } ->
    ECmakeListRemoveItem
      { list = cvar_name cvar; items = List.map values ~f:expr }
  | Ylist_remove_at { cvar; indices } ->
    ECmakeListRemoveAt { list = cvar_name cvar; indices }
  | Ylist_remove_duplicates { cvar } ->
    ECmakeListRemoveDuplicates { list = cvar_name cvar }
  | Ylist_reverse { cvar } ->
    ECmakeListReverse { list = cvar_name cvar }
  | Ylist_sort { cvar; order; compare; case } ->
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
    ECmakeListSort
      { list = cvar_name cvar;
        order = order_s; compare = compare_s; case = case_s }
  | Ylist_filter { cvar; mode; regex } ->
    let mode_s = match mode with
      | Lang_cmake.Lf_include -> "INCLUDE"
      | Lang_cmake.Lf_exclude -> "EXCLUDE"
    in
    ECmakeListFilter { list = cvar_name cvar; mode = mode_s; regex }
  | Ylist_sublist { cvar; begin_; length; out } ->
    ECmakeListSublist
      { list = cvar_name cvar; begin_; length; out = cvar_name out }
  | Ylist_find { cvar; value; out } ->
    ECmakeListFind
      { list = cvar_name cvar; value = expr value; out = cvar_name out }
  | Ylist_pop_back { cvar; out_vars } ->
    ECmakeListPopBack
      { list = cvar_name cvar; out_vars = List.map out_vars ~f:cvar_name }
  | Ylist_pop_front { cvar; out_vars } ->
    ECmakeListPopFront
      { list = cvar_name cvar; out_vars = List.map out_vars ~f:cvar_name }
  | Ylist_transform { cvar; action; selector; output } ->
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
    ECmakeListTransform
      { list = cvar_name cvar;
        action = action_s;
        selector = selector_s;
        output = Option.map output ~f:cvar_name }

let string_of_cmake_path_get_field : Lang_cmake.cmake_path_get_field -> string = function
  | Cpf_root_name -> "ROOT_NAME"
  | Cpf_root_directory -> "ROOT_DIRECTORY"
  | Cpf_root_path -> "ROOT_PATH"
  | Cpf_filename -> "FILENAME"
  | Cpf_extension last_only ->
    if last_only then "EXTENSION LAST_ONLY" else "EXTENSION"
  | Cpf_stem last_only ->
    if last_only then "STEM LAST_ONLY" else "STEM"
  | Cpf_relative_part -> "RELATIVE_PART"
  | Cpf_parent_path -> "PARENT_PATH"

let string_of_cmake_path_has_field : Lang_cmake.cmake_path_has_field -> string = function
  | Cph_root_name -> "HAS_ROOT_NAME"
  | Cph_root_directory -> "HAS_ROOT_DIRECTORY"
  | Cph_root_path -> "HAS_ROOT_PATH"
  | Cph_filename -> "HAS_FILENAME"
  | Cph_extension -> "HAS_EXTENSION"
  | Cph_stem -> "HAS_STEM"
  | Cph_relative_part -> "HAS_RELATIVE_PART"
  | Cph_parent_path -> "HAS_PARENT_PATH"

let string_of_cmake_path_compare_op : Lang_cmake.cmake_path_compare_op -> string = function
  | Cpco_equal -> "EQUAL"
  | Cpco_not_equal -> "NOT_EQUAL"

let path_statement : Old.yelu_path_stmt -> Yelu_tiny.expr = function
  | Ypath_set { path_var; input; normalize } ->
    ECmakePathSet { path = cvar_name path_var; input = expr input; normalize }
  | Ypath_get { path_var; field = Cpf_filename; out } ->
    ECmakePathGetFilename { path = cvar_name path_var; out = cvar_name out }
  | Ypath_get { path_var; field; out } ->
    ECmakePathGet
      { path = cvar_name path_var;
        field = string_of_cmake_path_get_field field;
        out = cvar_name out }
  | Ypath_has { path_var; field; out } ->
    ECmakePathHas
      { path = cvar_name path_var;
        field = string_of_cmake_path_has_field field;
        out = cvar_name out }
  | Ypath_is_absolute { path_var; out } ->
    ECmakePathIsAbsolute { path = cvar_name path_var; out = cvar_name out }
  | Ypath_is_relative { path_var; out } ->
    ECmakePathIsRelative { path = cvar_name path_var; out = cvar_name out }
  | Ypath_is_prefix { path_var; input; normalize; out } ->
    ECmakePathIsPrefix
      { path = cvar_name path_var; input = expr input; normalize;
        out = cvar_name out }
  | Ypath_compare { input1; op; input2; out } ->
    ECmakePathCompare
      { input1 = expr input1;
        op = string_of_cmake_path_compare_op op;
        input2 = expr input2;
        out = cvar_name out }
  | Ypath_append { path_var; inputs; out } ->
    ECmakePathAppend
      { path = cvar_name path_var;
        inputs = List.map inputs ~f:expr;
        out = Option.map out ~f:cvar_name }
  | Ypath_append_string { path_var; inputs; out } ->
    ECmakePathAppendString
      { path = cvar_name path_var;
        inputs = List.map inputs ~f:expr;
        out = Option.map out ~f:cvar_name }
  | Ypath_remove_filename { path_var; out } ->
    ECmakePathRemoveFilename
      { path = cvar_name path_var; out = Option.map out ~f:cvar_name }
  | Ypath_replace_filename { path_var; input; out } ->
    ECmakePathReplaceFilename
      { path = cvar_name path_var; input = expr input;
        out = Option.map out ~f:cvar_name }
  | Ypath_remove_extension { path_var; last_only; out } ->
    ECmakePathRemoveExtension
      { path = cvar_name path_var; last_only;
        out = Option.map out ~f:cvar_name }
  | Ypath_replace_extension { path_var; last_only; input; out } ->
    ECmakePathReplaceExtension
      { path = cvar_name path_var; last_only; input = expr input;
        out = Option.map out ~f:cvar_name }
  | Ypath_normal_path { path_var; out } ->
    ECmakePathNormalPath
      { path = cvar_name path_var; out = Option.map out ~f:cvar_name }
  | Ypath_relative_path { path_var; base_dir; out } ->
    ECmakePathRelativePath
      { path = cvar_name path_var;
        base_dir = Option.map base_dir ~f:expr;
        out = Option.map out ~f:cvar_name }
  | Ypath_absolute_path { path_var; base_dir; normalize; out } ->
    ECmakePathAbsolutePath
      { path = cvar_name path_var;
        base_dir = Option.map base_dir ~f:expr;
        normalize;
        out = Option.map out ~f:cvar_name }
  | Ypath_native_path { path_var; normalize; out } ->
    ECmakePathNativePath
      { path = cvar_name path_var; normalize; out = cvar_name out }
  | Ypath_convert_to_cmake { input; normalize; out } ->
    ECmakePathConvertToCmake
      { input = expr input; normalize; out = cvar_name out }
  | Ypath_convert_to_native { input; normalize; out } ->
    ECmakePathConvertToNative
      { input = expr input; normalize; out = cvar_name out }
  | Ypath_hash { path_var; out } ->
    ECmakePathHash { path = cvar_name path_var; out = cvar_name out }
  | Ypath_get_filename_component { var; filename; mode } ->
    ECmakeGetFilenameComponent
      { var = cvar_name var; filename = expr filename; mode }

let file_statement : Old.yelu_file_io_stmt -> Yelu_tiny.expr = function
  | Yfile_write { file; append = false; content } ->
    ECmakeFileWrite { path = expr file; content = List.map content ~f:expr }
  | Yfile_write { file; append = true; content } ->
    ECmakeFileWriteAppend { path = expr file; content = List.map content ~f:expr }
  | Yfile_read { out; file; offset = None; limit = None; hex = false } ->
    ECmakeFileRead { path = expr file; out = cvar_name out }
  | Yfile_read { out; file; offset; limit; hex } ->
    ECmakeFileReadFull
      { path = expr file; out = cvar_name out; offset; limit; hex }
  | Yfile_strings { out; file; regex; encoding; limit_count } ->
    ECmakeFileStrings
      { out = cvar_name out; path = expr file; regex; encoding; limit_count }
  | Yfile_touch { files; nocreate } ->
    ECmakeFileTouch { files = List.map files ~f:expr; nocreate }
  | Yfile_make_directory { dirs } ->
    ECmakeFileMakeDirectory { dirs = List.map dirs ~f:expr }
  | Yfile_rename { old_; new_; result; no_replace } ->
    ECmakeFileRename
      { old_ = expr old_; new_ = expr new_;
        result = Option.map result ~f:cvar_name; no_replace }
  | Yfile_remove { files; recurse } ->
    ECmakeFileRemove { files = List.map files ~f:expr; recurse }
  | Yfile_copy { input; output; result; only_if_different } ->
    ECmakeFileCopy
      { input = expr input; output = expr output;
        result = Option.map result ~f:cvar_name; only_if_different }
  | Yfile_real_path { out; path; base_dir; expand_tilde } ->
    ECmakeFileRealPath
      { out = cvar_name out; path = expr path;
        base_dir = Option.map base_dir ~f:expr; expand_tilde }
  | Yfile_size { out; file } ->
    ECmakeFileSize { out = cvar_name out; path = expr file }
  | Yfile_read_symlink { out; link } ->
    ECmakeFileReadSymlink { out = cvar_name out; link = expr link }
  | Yfile_timestamp { out; file; format; utc } ->
    ECmakeFileTimestamp
      { out = cvar_name out; path = expr file; format; utc }
  | Yfile_configure { input; output } ->
    ECmakeConfigureFile { input = expr input; output = expr output }
  | Yfile_relative_path { var; base; file } ->
    let var_name =
      match var with
      | Old.Yexpr_name { ns = Ns_var; name } -> name
      | Old.Yexpr_var (Yvar name) -> name
      | _ ->
        fail "file(RELATIVE_PATH) bridge: var must be a cmake variable name"
    in
    ECmakeFileRelativePath
      { var = var_name; base = expr base; file = expr file }
  | Yfile_glob { out; recurse; relative; configure_depends; patterns } ->
    ECmakeFileGlob
      { out = cvar_name out;
        recurse;
        relative = Option.map relative ~f:expr;
        configure_depends;
        patterns = List.map patterns ~f:expr }

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
  | Ycmake_at_var key -> ECmakeAtVar key
  | Ycmake_math { exp; out; output_format = _ } ->
    ECmakeMath { exp; out = cvar_name out }
  | Ycmake_enable_language { langs; optional } ->
    ECmakeEnableLanguage { langs; optional }
  | Ycmake_policy_set { id; new_ } ->
    ECmakePolicySet { id; new_ }
  | Ycmake_language_call { cmd; args } ->
    ECmakeLanguageCall { cmd; args = List.map args ~f:expr }
  | Ycmake_language_eval { code } ->
    ECmakeLanguageEval { code }
  | Ycmake_language_get_log_level { out } ->
    ECmakeLanguageGetLogLevel { out = cvar_name out }
  | Ycmake_variable_watch { var; command } ->
    ECmakeVariableWatch { var = cvar_name var; command }
  | Ycmake_execute_process r ->
    ECmakeExecuteProcess
      { commands = List.map r.commands ~f:(List.map ~f:expr);
        working_directory = Option.map r.working_directory ~f:expr;
        timeout = r.timeout;
        result_variable = Option.map r.result_variable ~f:cvar_name;
        output_variable = Option.map r.output_variable ~f:cvar_name;
        error_variable = Option.map r.error_variable ~f:cvar_name;
        input_file = Option.map r.input_file ~f:expr;
        output_file = Option.map r.output_file ~f:expr;
        error_file = Option.map r.error_file ~f:expr;
        output_quiet = r.output_quiet;
        error_quiet = r.error_quiet;
        output_strip_trailing_whitespace = r.output_strip_trailing_whitespace;
        error_strip_trailing_whitespace = r.error_strip_trailing_whitespace;
        command_error_is_fatal = r.command_error_is_fatal }
  | Ycmake_include_guard { scope } ->
    let scope_s = match scope with
      | Lang_cmake.Ig_directory -> "DIRECTORY"
      | Lang_cmake.Ig_global -> "GLOBAL"
    in
    ECmakeIncludeGuard { scope = scope_s }
  | Ycmake_quote_cmd s ->
    ECmakeQuoteCmd s

let dir_statement : Old.yelu_dir_stmt -> Yelu_tiny.expr = function
  | Ydir_add_subdirectory { source_dir } ->
    ECmakeAddSubdirectory (expr source_dir)
  | Ydir_include_directories { dirs; before; system } ->
    ECmakeIncludeDirectories
      { dirs = List.map dirs ~f:expr; before; system }
  | Ydir_add_compile_definitions { defs } ->
    ECmakeAddCompileDefinitions (List.map defs ~f:expr)
  | Ydir_add_compile_options { options } ->
    ECmakeAddCompileOptions (List.map options ~f:expr)
  | Ydir_add_link_options { options } ->
    ECmakeAddLinkOptions (List.map options ~f:expr)
  | Ydir_add_definitions { defs } ->
    ECmakeAddDefinitions (List.map defs ~f:expr)
  | Ydir_link_directories { dirs; before } ->
    ECmakeLinkDirectories { dirs = List.map dirs ~f:expr; before }
  | Ydir_link_libraries { items } ->
    (* Directory-level link_libraries — rare; render as a stub directive
       at this slice. *)
    ECmakeAddLinkOptions (List.map items ~f:expr)

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
  | Yprop_set { targets; append; properties } ->
    ECmakeSetProperty
      {
        targets = List.map targets ~f:target_name;
        append;
        properties = List.map properties ~f:(fun (p, v) -> p, expr v);
      }
  | Yprop_set_global { properties } ->
    ECmakeSetGlobalProperty
      { properties = List.map properties ~f:(fun (p, v) -> p, expr v) }
  | Yprop_get { var; target; property; set } ->
    ECmakeGetProperty
      { var = cvar_name var; target = expr target; property; set_form = set }
  | Yprop_get_directory { var; property } ->
    ECmakeGetDirectoryProperty { var = cvar_name var; property }
  | Yprop_set_directory { property; append; values } ->
    ECmakeSetDirectoryProperty
      { property; append; values = List.map values ~f:expr }
  | Yprop_set_source { file; property; values } ->
    ECmakeSetSourceProperty
      { file = expr file; property; values = List.map values ~f:expr }
  | Yprop_get_global { var; property } ->
    ECmakeGetGlobalProperty { var = cvar_name var; property }
  | Yprop_define
      { mode; property_name; inherited; brief_docs; full_docs; initialize_from } ->
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

let find_statement : Old.yelu_find_stmt -> Yelu_tiny.expr = function
  | Yfind_package { name; version; exact; quiet; config_mode;
                    required; components; optional_components } ->
    ECmakeFindPackage
      { package_name = name; version; exact; quiet; config_mode;
        required; components; optional_components }
  | Yfind_library { cvar; names; paths; hints; required; _ } ->
    ECmakeFindLibrary
      { out = cvar_name cvar;
        names = List.map names ~f:expr;
        paths = List.map paths ~f:expr;
        hints = List.map hints ~f:expr;
        required }
  | Yfind_path { cvar; names; paths; hints; required; _ } ->
    ECmakeFindPath
      { out = cvar_name cvar;
        names = List.map names ~f:expr;
        paths = List.map paths ~f:expr;
        hints = List.map hints ~f:expr;
        required }
  | Yfind_program { cvar; names; paths; hints; required; _ } ->
    ECmakeFindProgram
      { out = cvar_name cvar;
        names = List.map names ~f:expr;
        paths = List.map paths ~f:expr;
        hints = List.map hints ~f:expr;
        required }
  | Yfind_file { cvar; names; paths; hints; required; _ } ->
    ECmakeFindFile
      { out = cvar_name cvar;
        names = List.map names ~f:expr;
        paths = List.map paths ~f:expr;
        hints = List.map hints ~f:expr;
        required }

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
  | Ytry_compile r ->
    ECmakeTryCompileEx
      { result_var = cvar_name r.result_var;
        sources = List.map r.sources ~f:expr;
        compile_definitions = List.map r.compile_definitions ~f:expr;
        link_libraries = List.map r.link_libraries ~f:expr;
        link_options = List.map r.link_options ~f:expr;
        output_variable = Option.map r.output_variable ~f:cvar_name;
        no_cache = r.no_cache;
        c_standard = r.c_standard;
        cxx_standard = r.cxx_standard }
  | Ytry_run r ->
    ECmakeTryRun
      { run_result_var = cvar_name r.run_result_var;
        compile_result_var = cvar_name r.compile_result_var;
        sources = List.map r.sources ~f:expr;
        compile_definitions = List.map r.compile_definitions ~f:expr;
        link_libraries = List.map r.link_libraries ~f:expr;
        compile_output_variable =
          Option.map r.compile_output_variable ~f:cvar_name;
        run_output_variable =
          Option.map r.run_output_variable ~f:cvar_name;
        args = List.map r.args ~f:expr }

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
  | Ytgt_include_directories { target; before; system; items } ->
    items
    |> List.map ~f:(fun ({ kind; items } : Old.yelu_items_with_kind) ->
      ECmakeTargetIncludeDirectories
        {
          target = target_name target;
          visibility = visibility_of_kind kind;
          before; system;
          dirs = List.map items ~f:expr;
        })
    |> ESeq
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
  | Ytgt_compile_options { target; before; items } ->
    items
    |> List.map ~f:(fun ({ kind; items } : Old.yelu_items_with_kind) ->
      ECmakeTargetCompileOptions
        {
          target = target_name target;
          visibility = visibility_of_kind kind;
          before;
          options_ = List.map items ~f:expr;
        })
    |> ESeq
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
  | Ytgt_link_options { target; before; items } ->
    items
    |> List.map ~f:(fun ({ kind; items } : Old.yelu_items_with_kind) ->
      ECmakeTargetLinkOptions
        {
          target = target_name target;
          visibility = visibility_of_kind kind;
          before;
          options_ = List.map items ~f:expr;
        })
    |> ESeq
  | Ytgt_link_directories { target; before; items } ->
    items
    |> List.map ~f:(fun ({ kind; items } : Old.yelu_items_with_kind) ->
      ECmakeTargetLinkDirectories
        {
          target = target_name target;
          visibility = visibility_of_kind kind;
          before;
          dirs = List.map items ~f:expr;
        })
    |> ESeq
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
  | Ytgt_add_library_alias { name; target } ->
    ECmakeAddLibraryAlias { name; target }
  | Ytgt_add_executable_alias { name; target } ->
    ECmakeAddExecutableAlias { name; target }
  | Ytgt_add_library_imported { name; lib_type; global } ->
    ECmakeAddLibraryImported
      { name = target_name name; lib_type; global }
  | Ytgt_add_dependencies { target; dep } ->
    ECmakeAddDependencies { target; dep }
  | Ytgt_sources_fs { target; items } ->
    let file_set_type : Lang_cmake.file_set_type -> string = function
      | Fs_headers -> "HEADERS"
      | Fs_cxxmodules -> "CXX_MODULES"
    in
    let item : Old.yelu_target_sources_item -> tiny_target_sources_item = function
      | Ytsi_plain { kind; items } ->
        Tsi_plain
          { visibility = visibility_of_kind kind;
            items = List.map items ~f:expr }
      | Ytsi_file_set { kind; type_; base_dirs; files } ->
        Tsi_file_set
          { kind = visibility_of_kind kind;
            type_ = file_set_type type_;
            base_dirs = List.map base_dirs ~f:expr;
            files = List.map files ~f:expr }
    in
    ECmakeTargetSourcesFs
      { target = target_name target; items = List.map items ~f:item }
  | Ytgt_precompile_headers { target; items = [ { kind; items } ] } ->
    ECmakeTargetPrecompileHeaders
      { target = target_name target;
        visibility = visibility_of_kind kind;
        headers = List.map items ~f:expr }
  | Ytgt_precompile_headers { target; items } ->
    items
    |> List.map ~f:(fun ({ kind; items } : Old.yelu_items_with_kind) ->
      ECmakeTargetPrecompileHeaders
        { target = target_name target;
          visibility = visibility_of_kind kind;
          headers = List.map items ~f:expr })
    |> ESeq
  (* TARGET-form custom-command (deferred — production tests use the
     OUTPUT-form via [Ytgt_add_custom_command]). Listed explicitly so
     OCaml warning 8 fires when [yelu_target_stmt] grows new variants. *)
  | Ytgt_add_custom_command_target _ ->
    fail "bridge: TARGET-form add_custom_command not yet supported in tiny"

let string_of_compatibility : Lang_cmake.compatibility -> string = function
  | Any_newer_version -> "AnyNewerVersion"
  | Same_major_version -> "SameMajorVersion"
  | Same_minor_version -> "SameMinorVersion"
  | Exact_version -> "ExactVersion"

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
  | Yinstall_export { file; export; destination; namespace } ->
    ECmakeInstallExport
      {
        export = expr export;
        destination = expr destination;
        file = Option.map file ~f:expr;
        namespace;
      }
  | Yinstall_export_export { name; file } ->
    ECmakeExportExport { name = expr name; file = Option.map file ~f:expr }
  | Yinstall_configure_package_config_file
      { install_dest; input; output;
        no_set_and_check_macro; no_check_required_components_macro } ->
    ECmakeConfigurePackageConfigFile
      {
        install_dest = expr install_dest;
        input = expr input;
        output = expr output;
        no_set_and_check_macro;
        no_check_required_components_macro;
      }
  | Yinstall_write_basic_package_version_file
      { file; version; compatibility; arch_independent } ->
    ECmakeWriteBasicPackageVersionFile
      {
        file = expr file;
        version = Option.map version ~f:expr;
        compatibility = string_of_compatibility compatibility;
        arch_independent;
      }

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
  | Yc_include { file; optional } ->
    ECmakeInclude { file = expr file; optional }
  | Yc_macro { name; args; body } ->
    ECmakeMacro
      { name = expr name; params = args; body = stmts_to_expr body }
  | Yc_function { name; args; body } ->
    (* In production [Yc_function], [args] is the formal parameter list.
       Using [expr] (rather than a name-collapsing helper) preserves
       [EVar] references so the let-binding substitution at emit time
       can resolve a let-bound function name. *)
    ECmakeFunction
      { name = expr name; params = args; body = stmts_to_expr body }
  | Yc_apply { name; args } ->
    (* Same rationale as Yc_function: keep [EVar] / [Yexpr_name] shape
       so the apply target survives ELet substitution. *)
    ECmakeApply { name = expr name; args = List.map args ~f:expr }
  | Yc_foreach { loop_var; items; commands } ->
    ECmakeForeach
      { loop_var = cvar_name loop_var;
        items = List.map items ~f:expr;
        body = stmt commands }
  | Yc_while { cond; commands } ->
    ECmakeWhile { cond = expr cond; body = stmt commands }
  | Yc_break -> ECmakeBreak
  | Yc_continue -> ECmakeContinue
  | Yc_block { scope_vars; propagate; body } ->
    ECmakeBlock
      { scope_vars = List.map scope_vars ~f:cvar_name;
        propagate;
        body = stmts_to_expr body }
  | Yc_return { propogate_vars } ->
    ECmakeReturn { propagate_vars = propogate_vars }
  | Yc_foreach_range { loop_var; start; stop; step; commands } ->
    ECmakeForeachRange
      { loop_var = cvar_name loop_var; start; stop; step;
        body = stmt commands }
  | Yc_separate_arguments { cvar; mode; input } ->
    let mode_s = match mode with
      | Lang_cmake.Sa_plain -> "PLAIN"
      | Lang_cmake.Sa_unix_command -> "UNIX_COMMAND"
      | Lang_cmake.Sa_windows_command -> "WINDOWS_COMMAND"
      | Lang_cmake.Sa_native_command -> "NATIVE_COMMAND"
      | Lang_cmake.Sa_program -> "PROGRAM"
      | Lang_cmake.Sa_args -> "ARGS"
    in
    ECmakeSeparateArguments
      { var = cvar_name cvar; mode = mode_s;
        input = Option.map input ~f:expr }
  | Yc_foreach_zip { loop_vars; lists; commands } ->
    ECmakeForeachZip
      { loop_vars = List.map loop_vars ~f:cvar_name;
        lists = List.map lists ~f:cvar_name;
        body = stmt commands }
  | Yc_foreach_in { loop_var; lists; items; commands } ->
    (* foreach(<loop_var> IN LISTS <list-vars>... ITEMS <items>...). Preserve
       the IN LISTS / IN ITEMS source form via [ECmakeForeachInList] so
       emit can render the cmake keyword faithfully; cmake's [IN LISTS]
       respects semicolon-split list-deref while plain foreach treats
       arguments literally. *)
    ECmakeForeachInList
      { loop_var = cvar_name loop_var;
        lists = List.map lists ~f:cvar_name;
        items = List.map items ~f:expr;
        body = stmt commands }
  (* Production [Ylet] is sequence-shaped (its scope is the rest of the
     enclosing list). Tiny's [ELet] is expression-shaped. The conversion
     happens in [stmts_to_expr] when handling [Ystmt_list]; a standalone
     [Ylet] outside a sequence has no observable scope, so we emit an empty
     [body] for completeness. *)
  | Ylet { var = Yvar name; value } ->
    ELet { var = name; value = let_value value; body = EUnit }
  | Yif { cond; then_; else_ } ->
    Yelu_surface_cmake_if.ECmakeIfStmt
      {
        cond = expr cond;
        then_ = stmt then_;
        else_ = Option.map else_ ~f:stmt;
      }
  | Ystmt_list stmts -> stmts_to_expr stmts

(* Walk a statement list, recognising [Ylet] as an expression-let whose body
   is the remainder of the list. Other statements are sequenced via [ESeq]
   right-nested. Single-element lists collapse to that element. *)
and stmts_to_expr = function
  | [] -> EUnit
  | [Old.Ylet { var = Yvar name; value }] ->
    ELet { var = name; value = let_value value; body = EUnit }
  | Old.Ylet { var = Yvar name; value } :: rest ->
    ELet { var = name; value = let_value value; body = stmts_to_expr rest }
  | [s] -> stmt s
  | s :: rest -> ESeq [ stmt s; stmts_to_expr rest ]
