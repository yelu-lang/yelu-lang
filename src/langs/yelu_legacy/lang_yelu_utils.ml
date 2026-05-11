open Base
open Lang_yelu_cmake

let ycs_to_s = function
  | Ycs_path s | Ycs_keyword s | Ycs_string s | Ycs_eval s -> s

let yge (ge : yelu_genex) : yelu_expr = Yexpr_string (Ycs_string (genex_to_string ge))

let ycvar s : tc_name = { ns = Ns_var; name = s }
let ytarget s : tc_name = { ns = Ns_target; name = s }
let ytruthy expr = expr
let ynot c = Yexpr_not c
let yand a b = Yexpr_and (a, b)
let yor a b = Yexpr_or (a, b)
let yis_target e = match e with Yexpr_name t -> Yexpr_is_target t | _ -> failwith "expected target name"
let yis_defined e = match e with Yexpr_name t -> Yexpr_is_defined t | _ -> failwith "expected cvar name"
let ypolicy_defined id = Yexpr_policy id
let ystrequal a b = Yexpr_str_equal (a, b)
let ystrless a b = Yexpr_str_less (a, b)
let ystrgreater a b = Yexpr_str_greater (a, b)
let ystrless_equal a b = Yexpr_str_less_eq (a, b)
let ystrgreater_equal a b = Yexpr_str_greater_eq (a, b)
let yequal a b = Yexpr_equal (a, b)
let yless a b = Yexpr_less (a, b)
let ygreater a b = Yexpr_greater (a, b)
let yless_equal a b = Yexpr_less_eq (a, b)
let ygreater_equal a b = Yexpr_greater_eq (a, b)
let yin_list value listvar = Yexpr_in_list (value, listvar)
let ymatches value regex = Yexpr_matches (value, regex)
let yexists path = Yexpr_exists path
let yis_directory path = Yexpr_is_directory path
let yis_absolute path = Yexpr_is_absolute path
let yversion_less a b = Yexpr_ver_less (a, b)
let yversion_greater a b = Yexpr_ver_greater (a, b)
let yversion_equal a b = Yexpr_ver_equal (a, b)
let yversion_less_equal a b = Yexpr_ver_less_eq (a, b)
let yversion_greater_equal a b = Yexpr_ver_greater_eq (a, b)
let yvar s = Yexpr_var (Yvar s)
let ylet name value = Ylet { var = Yvar name; value }
let ycstr s = Yexpr_name { ns = Ns_var; name = s }
let ytval s = Yexpr_name { ns = Ns_target; name = s }
let yfile s = Yexpr_string (Ycs_path s)
let ydir s = Yexpr_string (Ycs_path s)
let ypath s = Yexpr_string (Ycs_path s)
let ykeyword s = Yexpr_string (Ycs_keyword s)
let yname s = Yexpr_name { ns = Ns_unknown; name = s }
let ystr s = Yexpr_string (Ycs_string s)
let ystr_eval s = Yexpr_string (Ycs_eval s)
let ybool b = Yexpr_bool b

(* cmake variable reference — erases to ${NAME} for cmake runtime expansion *)
let ycref s = ystr_eval (Fmt.str "${%s}" s)
let ycref_path s suffix = ystr_eval (Fmt.str "${%s}/%s" s suffix)

(* cmake directory constants — friendly keys for well-known cmake dir variables *)
let source_root = "PROJECT_SOURCE_DIR"
let output_root = "PROJECT_BINARY_DIR"
let source_this = "CMAKE_CURRENT_SOURCE_DIR"
let output_this = "CMAKE_CURRENT_BINARY_DIR"
let list_this = "CMAKE_CURRENT_LIST_DIR"

(* directory accessors *)
let dir d = ycref d
let dir_concat d suffix = ycref_path d suffix

(* Extern declarations *)
let yc_extern_cvar s = Yc_extern_cvar { ns = Ns_var; name = s }
let yc_extern_target s = Yc_extern_target { ns = Ns_target; name = s }
let ytarget_def ?(kind = Public) items : yelu_items_with_kind = { kind; items }
let ytarget_feature ?(kind = Public) feature : yelu_target_feature =
  { kind; feature }
let ycmd_of_list cmds = Ystmt_list cmds
let custom_command command args : Lang_cmake.custom_command = { command; args }

let yc_minimum_required_s ?max min =
  Ys_cmake (Ycmake_minimum_required
    {
      min = Lang_cmake_utils.version_of_string min;
      max = Option.map ~f:Lang_cmake_utils.version_of_string max;
    })

let yc_project ?version ?(languages = []) name =
  Ys_cmake (Ycmake_project { name; version; languages })

let yc_set ?(parent_scope = false) (cvar : yelu_cvar) values =
  Ys_var (Yvar_set { cvar; values; parent_scope })

let add_exe ?(exclude_from_all = false) ?(sources = []) name =
  Ys_target (Ytgt_add_executable { name; exclude_from_all; sources })

let add_lib ?(exclude_from_all = false) ?type_ ?(sources = []) name =
  Ys_target (Ytgt_add_library { name; type_; exclude_from_all; sources })

let add_lib_imported ?(global = false) ?lib_type name =
  Ys_target (Ytgt_add_library_imported { name; lib_type; global })

let add_lib_alias ~alias_of name = Ys_target (Ytgt_add_library_alias { name; target = alias_of })
let add_exe_alias ~alias_of name = Ys_target (Ytgt_add_executable_alias { name; target = alias_of })

let yc_add_compile_definitions defs = Ys_dir (Ydir_add_compile_definitions { defs })
let yc_add_compile_options options = Ys_dir (Ydir_add_compile_options { options })
let yc_add_link_options options = Ys_dir (Ydir_add_link_options { options })
let yc_link_directories ?(before = false) dirs = Ys_dir (Ydir_link_directories { before; dirs })

let include_dirs ?(before = false) ?(system = false) target items =
  Ys_target (Ytgt_include_directories { target; before; system; items })

let yc_include_directories ?(before = false) ?(system = false) dirs =
  Ys_dir (Ydir_include_directories { dirs; before; system })

let yc_get_property ?(set = false) ~target property var =
  Ys_property (Yprop_get { var; target; property; set })

let yc_get_directory_property property var =
  Ys_property (Yprop_get_directory { var; property })

let link_lib targets items =
  Ys_target (Ytgt_link_libraries { targets; items })

let compile_defs target items =
  Ys_target (Ytgt_compile_definitions { target; items })

let compile_feats target features =
  Ys_target (Ytgt_compile_features { target; features })

let compile_opts ?(before = false) target items =
  Ys_target (Ytgt_compile_options { target; before; items })

let yc_configure_file ~input output = Ys_file (Yfile_configure { input; output })
let gen_file = yc_configure_file
let yc_add_subdirectory source_dir = Ys_dir (Ydir_add_subdirectory { source_dir })

let yc_option ?(value = ybool false) ~msg (cvar : yelu_cvar) = Ys_var (Yvar_option { cvar; msg; value })

let yite cond then_ ?else_ () =
  match else_ with
  | None -> Yif { cond; then_; else_ = None }
  | Some else_ -> Yif { cond; then_; else_ = Some else_ }

let yifthen cond then_ = yite cond then_ ()
let yif cond then_ else_ = yite cond then_ ~else_ ()

(* scripting *)
let yc_include ?(optional = false) file = Yc_include { file; optional }
let yc_function name args body = Yc_function { name; args; body }
let yc_macro name ?(args = []) body = Yc_macro { name; args; body }
let yc_apply name args = Yc_apply { name; args }
let yc_set_env var value = Ys_var (Yvar_set_env { var; value })
let yc_unset_env var = Ys_var (Yvar_unset_env { var })

let yc_set_cache ?(force = false) ?(cache_type = Lang_cmake.Ct_string) ?(docstring = "") (cvar : yelu_cvar) values =
  Ys_var (Yvar_set_cache { cvar; values; cache_type; docstring; force })

let yc_unset_cache (cvar : yelu_cvar) = Ys_var (Yvar_unset_cache { cvar })

let yc_execute_process
    ?(working_directory = None) ?(timeout = None)
    ?(result_variable = None) ?(output_variable = None) ?(error_variable = None)
    ?(input_file = None) ?(output_file = None) ?(error_file = None)
    ?(output_quiet = false) ?(error_quiet = false)
    ?(output_strip_trailing_whitespace = false)
    ?(error_strip_trailing_whitespace = false)
    ?(command_error_is_fatal = None)
    commands =
  Ys_cmake (Ycmake_execute_process
    { commands; working_directory; timeout; result_variable; output_variable;
      error_variable; input_file; output_file; error_file; output_quiet; error_quiet;
      output_strip_trailing_whitespace; error_strip_trailing_whitespace;
      command_error_is_fatal })

let yc_file_relative_path ~var ~base file = Ys_file (Yfile_relative_path { var; base; file })

let yc_file_glob ?(recurse = false) ?(relative = None) ?(configure_depends = false)
    (out : yelu_cvar) patterns =
  Ys_file (Yfile_glob { out; recurse; relative; configure_depends; patterns })

let yc_file_read ?(offset = None) ?(limit = None) ?(hex = false) (out : yelu_cvar) file =
  Ys_file (Yfile_read { out; file; offset; limit; hex })

let yc_file_write ?(append = false) file content =
  Ys_file (Yfile_write { file; append; content })

let yc_file_append file content = Ys_file (Yfile_write { file; append = true; content })

let yc_file_strings ?(regex = None) ?(encoding = None) ?(limit_count = None)
    (out : yelu_cvar) file =
  Ys_file (Yfile_strings { out; file; regex; encoding; limit_count })

let yc_file_touch ?(nocreate = false) files = Ys_file (Yfile_touch { files; nocreate })
let yc_file_make_directory dirs = Ys_file (Yfile_make_directory { dirs })

let yc_file_rename ?(result = None) ?(no_replace = false) old_ new_ =
  Ys_file (Yfile_rename { old_; new_; result; no_replace })

let yc_file_remove ?(recurse = false) files = Ys_file (Yfile_remove { files; recurse })

let yc_file_copy_file ?(result = None) ?(only_if_different = false) input output =
  Ys_file (Yfile_copy { input; output; result; only_if_different })

let yc_file_real_path ?(base_dir = None) ?(expand_tilde = false) (out : yelu_cvar) path =
  Ys_file (Yfile_real_path { out; path; base_dir; expand_tilde })

let yc_file_size (out : yelu_cvar) file = Ys_file (Yfile_size { out; file })
let yc_file_read_symlink (out : yelu_cvar) link = Ys_file (Yfile_read_symlink { out; link })

let yc_file_timestamp ?(format = None) ?(utc = false) (out : yelu_cvar) file =
  Ys_file (Yfile_timestamp { out; file; format; utc })

let yc_policy_set ?(new_ = true) id = Ys_cmake (Ycmake_policy_set { id; new_ })

let yc_quote_cmd s = Ys_cmake (Ycmake_quote_cmd s)

let yc_at_var key = Ys_cmake (Ycmake_at_var key)

let yc_set_directory_property ?(append = false) property values =
  Ys_property (Yprop_set_directory { property; append; values })

let yc_link_libraries items = Ys_dir (Ydir_link_libraries { items })

let yc_list_append (cvar : yelu_cvar) values = Ys_list (Ylist_append { cvar; values })

(* testing *)
let yc_enable_testing = Ys_test Ytest_enable_testing
let yc_add_test name command args = Ys_test (Ytest_add_test { name; command; args })
let yc_set_tests_properties tests properties =
  Ys_property (Yprop_set_tests { tests; properties })

(* target properties *)
let yc_set_target_properties target properties =
  Ys_property (Yprop_set_target { target; properties })

let yc_set_property ?(append = false) ~targets properties =
  Ys_property (Yprop_set { targets; append; properties })

let yc_set_source_property ?(property = "COMPILE_OPTIONS") file values =
  Ys_property (Yprop_set_source { file; property; values })

let yc_enable_language ?(optional = false) langs =
  Ys_cmake (Ycmake_enable_language { langs; optional })

let yc_set_global_property properties =
  Ys_property (Yprop_set_global { properties })

let yc_get_filename_component ~mode var filename =
  Ys_path (Ypath_get_filename_component { var; filename; mode })

let yc_get_global_property ~property var =
  Ys_property (Yprop_get_global { var; property })

let yc_include_guard scope = Ys_cmake (Ycmake_include_guard { scope })
let yc_separate_arguments ?(input) ~mode (cvar : yelu_cvar) = Yc_separate_arguments { cvar; mode; input }
let yc_separate_arguments_plain (cvar : yelu_cvar) = Yc_separate_arguments { cvar; mode = Lang_cmake.Sa_plain; input = None }
let yc_target_link_options ?(before = false) target items =
  Ys_target (Ytgt_link_options { target; before; items })
let yc_target_link_directories ?(before = false) target items =
  Ys_target (Ytgt_link_directories { target; before; items })
let yc_target_sources target items = Ys_target (Ytgt_sources { target; items })

let ytsi_plain kind items = Ytsi_plain { kind; items }
let ytsi_file_set_headers ?(base_dirs = []) ?(files = []) kind =
  Ytsi_file_set { kind; type_ = Lang_cmake.Fs_headers; base_dirs; files }

let yc_target_sources_fs target items = Ys_target (Ytgt_sources_fs { target; items })
let yc_target_precompile_headers target items = Ys_target (Ytgt_precompile_headers { target; items })

(* install *)
let yc_install_targets ?export targets destination =
  Ys_install (Yinstall_targets { targets; destination; export })

let yc_install_files files destination =
  Ys_install (Yinstall_files { files; destination })

let yc_install_export ?file ?namespace export destination =
  Ys_install (Yinstall_export { file; export; destination; namespace })

(* export *)
let yc_export_export ?file name = Ys_install (Yinstall_export_export { name; file })

(* module commands *)
let yc_configure_package_config_file ?(no_set_and_check_macro = false)
    ?(no_check_required_components_macro = false) install_dest input output =
  Ys_install (Yinstall_configure_package_config_file
    { install_dest; input; output; no_set_and_check_macro;
      no_check_required_components_macro })

let yc_write_basic_package_version_file ~compatibility ?(arch_independent = false)
    ?version file =
  Ys_install (Yinstall_write_basic_package_version_file { file; version; compatibility; arch_independent })

(* custom commands *)
let yc_add_custom_command ~outputs ?(depends = []) ?(verbatim = false)
    ?(comment : string option = None) commands =
  Ys_target (Ytgt_add_custom_command { outputs; commands; depends; verbatim; comment })

let yc_add_custom_command_target ?(verbatim = false) ?(comment : string option = None)
    ~target ~when_ commands =
  Ys_target (Ytgt_add_custom_command_target { target; when_; commands; comment; verbatim })

let cw_pre_build  = Lang_cmake.Cw_pre_build
let cw_pre_link   = Lang_cmake.Cw_pre_link
let cw_post_build = Lang_cmake.Cw_post_build

let yc_add_definitions defs = Ys_dir (Ydir_add_definitions { defs })

(* Tier 1: find_var commands *)
let yc_find_library ?(names = []) ?(paths = []) ?(hints = [])
    ?(no_default_path = false) ?(no_cmake_environment_path = false)
    ?(no_system_environment_path = false) ?(required = false) cvar =
  Ys_find (Yfind_library { cvar; names; paths; hints; no_default_path;
                           no_cmake_environment_path; no_system_environment_path;
                           required })

let yc_find_path ?(names = []) ?(paths = []) ?(hints = [])
    ?(no_default_path = false) ?(no_cmake_environment_path = false)
    ?(no_system_environment_path = false) ?(required = false) cvar =
  Ys_find (Yfind_path { cvar; names; paths; hints; no_default_path;
                        no_cmake_environment_path; no_system_environment_path;
                        required })

let yc_find_program ?(names = []) ?(paths = []) ?(hints = [])
    ?(no_default_path = false) ?(no_cmake_environment_path = false)
    ?(no_system_environment_path = false) ?(required = false) cvar =
  Ys_find (Yfind_program { cvar; names; paths; hints; no_default_path;
                           no_cmake_environment_path; no_system_environment_path;
                           required })

let yc_find_file ?(names = []) ?(paths = []) ?(hints = [])
    ?(no_default_path = false) ?(no_cmake_environment_path = false)
    ?(no_system_environment_path = false) ?(required = false) cvar =
  Ys_find (Yfind_file { cvar; names; paths; hints; no_default_path;
                        no_cmake_environment_path; no_system_environment_path;
                        required })

let yc_find_package ?(version = None) ?(exact = false) ?(quiet = false) ?(config_mode = false)
    ?(required = false) ?(components = []) ?(optional_components = []) name =
  Ys_find (Yfind_package { name; version; exact; quiet; config_mode; required; components; optional_components })

let yc_message ?(mode = Lang_cmake.Mm_status) texts = Ys_cmake (Ycmake_message { mode; texts })

(* Tier 2: iteration *)
let yc_foreach ?(items = []) (loop_var : yelu_cvar) commands =
  Yc_foreach { loop_var; items; commands }

let yc_foreach_range ?start ?step ~stop (loop_var : yelu_cvar) commands =
  Yc_foreach_range { loop_var; start; stop; step; commands }

let yc_foreach_in ?(lists = []) ?(items = []) (loop_var : yelu_cvar) commands =
  Yc_foreach_in { loop_var; lists; items; commands }

let yc_foreach_zip (loop_vars : yelu_cvar list) (lists : yelu_cvar list) commands =
  Yc_foreach_zip { loop_vars; lists; commands }

let yc_while cond commands = Yc_while { cond; commands }
let yc_break = Yc_break
let yc_continue = Yc_continue
let yc_return ?(propogate_vars = []) () = Yc_return { propogate_vars }

(* Tier 2: list commands *)
let yc_list_length (cvar : yelu_cvar) (out : yelu_cvar) = Ys_list (Ylist_length { cvar; out })
let yc_list_get ?(indices = []) (cvar : yelu_cvar) (out : yelu_cvar) = Ys_list (Ylist_get { cvar; indices; out })
let yc_list_remove_item (cvar : yelu_cvar) values = Ys_list (Ylist_remove_item { cvar; values })
let yc_list_remove_duplicates (cvar : yelu_cvar) = Ys_list (Ylist_remove_duplicates { cvar })
let yc_list_reverse (cvar : yelu_cvar) = Ys_list (Ylist_reverse { cvar })

let yc_list_sort ?order ?compare ?case (cvar : yelu_cvar) =
  Ys_list (Ylist_sort { cvar; order; compare; case })

let yc_list_filter mode regex (cvar : yelu_cvar) =
  Ys_list (Ylist_filter { cvar; mode; regex })

let yc_list_join (cvar : yelu_cvar) glue (out : yelu_cvar) = Ys_list (Ylist_join { cvar; glue; out })
let yc_list_sublist (cvar : yelu_cvar) begin_ length (out : yelu_cvar) = Ys_list (Ylist_sublist { cvar; begin_; length; out })
let yc_list_find (cvar : yelu_cvar) value (out : yelu_cvar) = Ys_list (Ylist_find { cvar; value; out })
let yc_list_prepend (cvar : yelu_cvar) values = Ys_list (Ylist_prepend { cvar; values })
let yc_list_insert (cvar : yelu_cvar) index values = Ys_list (Ylist_insert { cvar; index; values })
let yc_list_remove_at (cvar : yelu_cvar) indices = Ys_list (Ylist_remove_at { cvar; indices })
let yc_list_pop_back ?(out_vars = []) (cvar : yelu_cvar) = Ys_list (Ylist_pop_back { cvar; out_vars })
let yc_list_pop_front ?(out_vars = []) (cvar : yelu_cvar) = Ys_list (Ylist_pop_front { cvar; out_vars })

let yc_list_transform ?(selector) ?(output : yelu_cvar option) (cvar : yelu_cvar) action =
  Ys_list (Ylist_transform { cvar; action; selector; output })

(* Tier 2: string commands *)
let yc_string_toupper string (out : yelu_cvar) = Ys_string (Ystr_toupper { string; out })
let yc_string_tolower string (out : yelu_cvar) = Ys_string (Ystr_tolower { string; out })
let yc_string_length string (out : yelu_cvar) = Ys_string (Ystr_length { string; out })
let yc_string_strip string (out : yelu_cvar) = Ys_string (Ystr_strip { string; out })
let yc_string_concat (out : yelu_cvar) inputs = Ys_string (Ystr_concat { out; inputs })

let yc_string_replace match_string replace_string (out : yelu_cvar) inputs =
  Ys_string (Ystr_replace { match_string; replace_string; out; inputs })

let yc_string_regex_match regex (out : yelu_cvar) inputs =
  Ys_string (Ystr_regex_match { regex; out; inputs })
let yc_string_regex_matchall regex (out : yelu_cvar) inputs =
  Ys_string (Ystr_regex_matchall { regex; out; inputs })

let yc_string_regex_replace regex replace (out : yelu_cvar) inputs =
  Ys_string (Ystr_regex_replace { regex; replace; out; inputs })
let yc_string_regex_quote (out : yelu_cvar) inputs =
  Ys_string (Ystr_regex_quote { out; inputs })

let yc_string_append (cvar : yelu_cvar) inputs = Ys_string (Ystr_append { cvar; inputs })
let yc_string_prepend (cvar : yelu_cvar) inputs = Ys_string (Ystr_prepend { cvar; inputs })
let yc_string_join glue (out : yelu_cvar) inputs = Ys_string (Ystr_join { glue; out; inputs })
let yc_string_find ?(reverse = false) string substring (out : yelu_cvar) =
  Ys_string (Ystr_find { string; substring; out; reverse })
let yc_string_substring string begin_ ?length (out : yelu_cvar) =
  Ys_string (Ystr_substring { string; begin_; length; out })
let yc_string_repeat string count (out : yelu_cvar) = Ys_string (Ystr_repeat { string; count; out })
let yc_string_genex_strip string (out : yelu_cvar) = Ys_string (Ystr_genex_strip { string; out })

let yc_string_compare op string1 string2 (out : yelu_cvar) =
  Ys_string (Ystr_compare { op; string1; string2; out })

let yc_string_make_c_identifier string (out : yelu_cvar) =
  Ys_string (Ystr_make_c_identifier { string; out })

let yc_string_timestamp ?(utc = false) ?format (out : yelu_cvar) =
  Ys_string (Ystr_timestamp { out; format; utc })

let yc_string_hex string (out : yelu_cvar) = Ys_string (Ystr_hex { string; out })

let yc_string_uuid ?(upper = false) ~namespace ~name ~type_ (out : yelu_cvar) =
  Ys_string (Ystr_uuid { out; namespace; name; type_; upper })

let yc_string_json_get ?(error_var : yelu_cvar option) ?(path = []) ~(out : yelu_cvar) json =
  Ys_string (Ystr_json { out; error_var; op = Yjop_get { json; path } })

let yc_string_json_get_raw ?(error_var : yelu_cvar option) ?(path = []) ~(out : yelu_cvar) json =
  Ys_string (Ystr_json { out; error_var; op = Yjop_get_raw { json; path } })

let yc_string_json_type ?(error_var : yelu_cvar option) ?(path = []) ~(out : yelu_cvar) json =
  Ys_string (Ystr_json { out; error_var; op = Yjop_type { json; path } })

let yc_string_json_length ?(error_var : yelu_cvar option) ?(path = []) ~(out : yelu_cvar) json =
  Ys_string (Ystr_json { out; error_var; op = Yjop_length { json; path } })

let yc_string_json_member ?(error_var : yelu_cvar option) ?(path = []) ~(out : yelu_cvar) json =
  Ys_string (Ystr_json { out; error_var; op = Yjop_member { json; path } })

let yc_string_json_remove ?(error_var : yelu_cvar option) ?(path = []) ~(out : yelu_cvar) json =
  Ys_string (Ystr_json { out; error_var; op = Yjop_remove { json; path } })

let yc_string_json_set ?(error_var : yelu_cvar option) ?(path = []) ~(out : yelu_cvar) ~value json =
  Ys_string (Ystr_json { out; error_var; op = Yjop_set { json; path; value } })

let yc_string_json_equal ~(out : yelu_cvar) json1 json2 =
  Ys_string (Ystr_json { out; error_var = None; op = Yjop_equal { json1; json2 } })

let yc_string_json_string_encode ~(out : yelu_cvar) value =
  Ys_string (Ystr_json { out; error_var = None; op = Yjop_string_encode { value } })

(* math *)
let yc_math ?(output_format = Lang_cmake.Decical) exp (out : yelu_cvar) =
  Ys_cmake (Ycmake_math { exp; out; output_format })

let yc_language_call cmd args =
  Ys_cmake (Ycmake_language_call { cmd; args })

let yc_language_eval code =
  Ys_cmake (Ycmake_language_eval { code })

let yc_language_get_log_level (out : yelu_cvar) =
  Ys_cmake (Ycmake_language_get_log_level { out })

let yc_block ?(scope_vars = []) ?(propagate = "") body =
  Yc_block { scope_vars; propagate; body }

(* cmake_path utilities *)
let yc_path_get path_var field (out : yelu_cvar) =
  Ys_path (Ypath_get { path_var; field; out })

let yc_path_has path_var field (out : yelu_cvar) =
  Ys_path (Ypath_has { path_var; field; out })

let yc_path_is_absolute path_var (out : yelu_cvar) =
  Ys_path (Ypath_is_absolute { path_var; out })

let yc_path_is_relative path_var (out : yelu_cvar) =
  Ys_path (Ypath_is_relative { path_var; out })

let yc_path_is_prefix ?(normalize = false) path_var input (out : yelu_cvar) =
  Ys_path (Ypath_is_prefix { path_var; input; normalize; out })

let yc_path_compare input1 op input2 (out : yelu_cvar) =
  Ys_path (Ypath_compare { input1; op; input2; out })

let yc_path_set ?(normalize = false) path_var input =
  Ys_path (Ypath_set { path_var; input; normalize })

let yc_path_append ?(out : yelu_cvar option = None) path_var inputs =
  Ys_path (Ypath_append { path_var; inputs; out })

let yc_path_append_string ?(out : yelu_cvar option = None) path_var inputs =
  Ys_path (Ypath_append_string { path_var; inputs; out })

let yc_path_remove_filename ?(out : yelu_cvar option = None) path_var =
  Ys_path (Ypath_remove_filename { path_var; out })

let yc_path_replace_filename ?(out : yelu_cvar option = None) path_var input =
  Ys_path (Ypath_replace_filename { path_var; input; out })

let yc_path_remove_extension ?(last_only = false) ?(out : yelu_cvar option = None) path_var =
  Ys_path (Ypath_remove_extension { path_var; last_only; out })

let yc_path_replace_extension ?(last_only = false) ?(out : yelu_cvar option = None) path_var input =
  Ys_path (Ypath_replace_extension { path_var; last_only; input; out })

let yc_path_normal_path ?(out : yelu_cvar option = None) path_var =
  Ys_path (Ypath_normal_path { path_var; out })

let yc_path_relative_path ?(base_dir : yelu_expr option = None) ?(out : yelu_cvar option = None) path_var =
  Ys_path (Ypath_relative_path { path_var; base_dir; out })

let yc_path_absolute_path ?(base_dir : yelu_expr option = None) ?(normalize = false) ?(out : yelu_cvar option = None) path_var =
  Ys_path (Ypath_absolute_path { path_var; base_dir; normalize; out })

let yc_path_native_path ?(normalize = false) path_var (out : yelu_cvar) =
  Ys_path (Ypath_native_path { path_var; normalize; out })

let yc_path_convert_to_cmake ?(normalize = false) input (out : yelu_cvar) =
  Ys_path (Ypath_convert_to_cmake { input; normalize; out })

let yc_path_convert_to_native ?(normalize = false) input (out : yelu_cvar) =
  Ys_path (Ypath_convert_to_native { input; normalize; out })

let yc_path_hash path_var (out : yelu_cvar) =
  Ys_path (Ypath_hash { path_var; out })

let yc_try_compile ?(compile_definitions = []) ?(link_libraries = [])
    ?(link_options = []) ?(output_variable : yelu_cvar option = None)
    ?(no_cache = false) ?(c_standard : string option = None)
    ?(cxx_standard : string option = None)
    result_var sources =
  Ys_try (Ytry_compile { result_var; sources; compile_definitions; link_libraries;
                         link_options; output_variable; no_cache; c_standard; cxx_standard })

let yc_try_run ?(compile_definitions = []) ?(link_libraries = [])
    ?(compile_output_variable : yelu_cvar option = None)
    ?(run_output_variable : yelu_cvar option = None) ?(args = [])
    run_result_var compile_result_var sources =
  Ys_try (Ytry_run { run_result_var; compile_result_var; sources; compile_definitions;
                     link_libraries; compile_output_variable; run_output_variable; args })

let yc_add_custom_target ?(all = false) ?(commands = []) ?(depends = [])
    ?(comment : string option = None) name =
  Ys_target (Ytgt_add_custom_target { name; all; commands; depends; comment })

let yc_get_target_property var target property =
  Ys_property (Yprop_get_target { var; target; property })

let yc_define_property ?(inherited = false) ?(brief_docs = []) ?(full_docs = [])
    ?(initialize_from : string option = None) mode property_name =
  Ys_property (Yprop_define { mode; property_name; inherited; brief_docs; full_docs; initialize_from })

let yc_add_dependencies target dep =
  Ys_target (Ytgt_add_dependencies { target; dep })

let yc_variable_watch ?(command : string option = None) var =
  Ys_cmake (Ycmake_variable_watch { var; command })
