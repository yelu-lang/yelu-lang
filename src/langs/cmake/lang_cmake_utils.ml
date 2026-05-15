open Base
open Lang_cmake

let version_of_string s =
  let parts = String.split s ~on:'.' in
  match parts with
  | [major; minor] -> { major = Int.of_string major; minor = Int.of_string minor; patch = "" }
  | [major; minor; patch] -> { major = Int.of_string major; minor = Int.of_string minor; patch }
  | _ -> failwith (Printf.sprintf "version_of_string: invalid version %S" s)

let str_ s = Bare s
let quote s = Quoted s
let bracket_str s = Bracket s
let bool_ b = str_ (if b then "ON" else "OFF")
let target_def ?(kind = "PUBLIC") items = { kind; items }
let target_feature ?(kind = "PUBLIC") feature = { kind; feature }
let cmd_of_list cmds = Exp_list cmds

let cmake_minimum_required ?(max : version option = None) min =
  Cmake_cmd (Cmake_minimum_required { min = version_of_string min; max })

let find_package ?(version : string option = None) ?(exact = false) ?(quiet = false)
    ?(config_mode = false) ?(required = false) ?(components = [])
    ?(optional_components = []) name =
  Find_package { name; version; exact; quiet; config_mode; required; components;
                 optional_components }

let add_library_alias name ~alias_of =
  Project_cmd (Add_library_alias { name; target = alias_of })

let include_ ?(optional = false) ?result_var ?(no_policy_scope = false) file =
  Include { file; optional; result_var; no_policy_scope }

let ite cond then_ ?else_ () =
  match else_ with
  | None -> If { cond; then_; else_ = None }
  | Some else_ -> If { cond; then_; else_ = Some else_ }

let ifthen cond then_ = ite cond then_ ()
let if_ cond then_ else_ = ite cond then_ ~else_ ()
let function_ name args cmds = Function { name; args; cmds }
let apply name args = Apply { name; args }
let custom_command command args : Lang_cmake.custom_command = { command; args }

(* foreach *)
let foreach ?(items = []) ?(commands = Exp_list []) loop_var =
  Foreach { loop_var; items; commands }

let foreach_range ?start ?step ?(commands = Exp_list []) loop_var stop =
  Foreach_range { loop_var; start; stop; step; commands }

let foreach_in ?(lists = []) ?(items = []) ?(commands = Exp_list []) loop_var =
  Foreach_in { loop_var; lists; items; commands }

(* list commands *)
let list_append var values = List_cmd (Lc_append { var; values })
let list_prepend var values = List_cmd (Lc_prepend { var; values })
let list_length var out = List_cmd (Lc_length { var; out })
let list_get var indices out = List_cmd (Lc_get { var; indices; out })
let list_sublist var begin_ length out = List_cmd (Lc_sublist { var; begin_; length; out })
let list_find var value out = List_cmd (Lc_find { var; value; out })
let list_insert var index values = List_cmd (Lc_insert { var; index; values })
let list_remove_item var values = List_cmd (Lc_remove_item { var; values })
let list_remove_at var indices = List_cmd (Lc_remove_at { var; indices })
let list_remove_duplicates var = List_cmd (Lc_remove_duplicates { var })
let list_reverse var = List_cmd (Lc_reverse { var })
let list_sort ?order ?compare ?case var = List_cmd (Lc_sort { var; order; compare; case })
let list_join var glue out = List_cmd (Lc_join { var; glue; out })
let list_filter var mode regex = List_cmd (Lc_filter { var; mode; regex })
let list_pop_back ?(out_vars = []) var = List_cmd (Lc_pop_back { var; out_vars })
let list_pop_front ?(out_vars = []) var = List_cmd (Lc_pop_front { var; out_vars })

(* string commands *)
let string_find ?(reverse = false) string substring out =
  String_cmd (Sc_find { string; substring; out; reverse })
let string_replace match_string replace_string out inputs =
  String_cmd (Sc_replace { match_string; replace_string; out; inputs })
let string_regex_match regex out inputs =
  String_cmd (Sc_regex (Sr_match { regex; out; inputs }))
let string_regex_matchall regex out inputs =
  String_cmd (Sc_regex (Sr_matchall { regex; out; inputs }))
let string_regex_replace regex replace out inputs =
  String_cmd (Sc_regex (Sr_replace { regex; replace; out; inputs }))
let string_regex_quote out inputs =
  String_cmd (Sc_regex (Sr_quote { out; inputs }))
let string_toupper string out = String_cmd (Sc_toupper { string; out })
let string_tolower string out = String_cmd (Sc_tolower { string; out })
let string_length string out = String_cmd (Sc_length { string; out })
let string_substring ?length string begin_ out =
  String_cmd (Sc_substring { string; begin_; length; out })
let string_strip string out = String_cmd (Sc_strip { string; out })
let string_repeat string count out = String_cmd (Sc_repeat { string; count; out })
let string_concat out inputs = String_cmd (Sc_concat { out; inputs })
let string_join glue out inputs = String_cmd (Sc_join { glue; out; inputs })
let string_append var inputs = String_cmd (Sc_append { var; inputs })
let string_prepend var prefix inputs = String_cmd (Sc_prepend { var; prefix; inputs })
let string_compare op string1 string2 out =
  String_cmd (Sc_compare { op; string1; string2; out })
let string_make_c_identifier string out =
  String_cmd (Sc_make_c_identifier { string; out })
let string_timestamp ?format ?(utc = false) out =
  String_cmd (Sc_timestamp { out; format; utc })

let minimum_required_s ?max min =
  Cmake_cmd
    (Cmake_minimum_required
       {
         min = version_of_string min;
         max = Option.map ~f:version_of_string max;
       })

let project ?version ?description ?homepage_url ?(languages = []) name =
  Project_cmd (Project { name; version; description; homepage_url; languages })

let include_guard scope = Include_guard { scope }
let separate_arguments ?(input) ~mode var = Separete_arguments { var; mode; input }

let option_ ?(value = bool_ false) ~msg var = Cmake_option { var; msg; value }
let export_targets targets = Project_cmd (Export_targets { targets })
let export_export ?file name = Project_cmd (Export_export { file; name })
let export_package name = Project_cmd (Export_package { name })
let export_setup name = Project_cmd (Export_setup { name })
let quote_cmd s = Quote s

let add_library ?(exclude_from_all = false) ?type_ ?(sources = []) name =
  Project_cmd (Add_library { name; type_; exclude_from_all; sources })

let add_library_imported ?(global = false) ?lib_type name =
  Project_cmd (Add_library_imported { name; lib_type; global })

let add_executable ?(options = []) ?(sources = []) name =
  Project_cmd (Add_executable { name; options; sources })

let configure_file ?(permissions = []) ?permission_level ?copy_only
    ?escape_quotes ?only ?newline_style ~input output =
  Cmake_cmd
    (Configure_file
       {
         input;
         output;
         permission_level;
         permissions;
         copy_only;
         escape_quotes;
         only;
         newline_style;
       })

let set ?(parent_scope = false) var values = Set { var; values; parent_scope }

let add_subdirectory ?binary_dir ?(exclude_from_all = false) ?(system = false)
    source_dir =
  Project_cmd
    (Add_subdirectory { source_dir; binary_dir; exclude_from_all; system })

let add_custom_command ~outputs ?main_dependency ?(depends = [])
    ?(byproducts = []) ?(implicit_depends = []) ?working_directory ?comment
    ?depfile ?job_pool ?(job_server_aware = false) ?(verbatim = false)
    ?(append = false) ?(uses_terminal = false) ?(codegen = false)
    ?(command_expand_list = []) ?(depends_explicit_only = false) commands =
  Project_cmd
    (Add_custom_command
       {
         outputs;
         commands;
         main_dependency;
         depends;
         byproducts;
         implicit_depends;
         working_directory;
         comment;
         depfile;
         job_pool;
         job_server_aware;
         verbatim;
         append;
         uses_terminal;
         codegen;
         command_expand_list;
         depends_explicit_only;
       })

let target_compile_definitions target items =
  Project_cmd (Target_compile_definitions { target; items })

let target_compile_features target features =
  Project_cmd (Target_compile_features { target; features })

let target_compile_options ?(before = false) target items =
  Project_cmd (Target_compile_options { target; before; items })

let target_include_directories ?system ?before_or_after target items =
  Project_cmd
    (Target_include_directories { target; system; before_or_after; items })

let target_link_libraries targets items =
  Project_cmd (Target_link_libraries { targets; items })

let target_link_options ?(before = false) target items =
  Project_cmd (Target_link_options { target; before; items })

let target_sources target items =
  Project_cmd (Target_sources { target; items })

let file_set_headers ?(base_dirs = []) ?(files = []) kind =
  Tsi_file_set { kind; file_set = SSet; type_ = Fs_headers; base_dirs; files }

let ts_plain kind items = Tsi_plain { kind; items }

let target_sources_fs target items =
  Project_cmd (Target_sources_file_set { target; items })

let install_targets ?component ?rename ?export ?(permissions = []) targets
    destination =
  Project_cmd
    (Install_targets
       { targets; destination; permissions; component; rename; export })

let install_export ?file ?namespace ?component ?rename ?(permissions = []) export
    destination =
  Project_cmd
    (Install_export
       { file; destination; namespace; permissions; component; rename; export })

let install_files ?component ?rename ?(permissions = []) files destination =
  Project_cmd
    (Install_files { files; destination; permissions; component; rename })

(* testing *)
let enable_testing = Project_cmd Enable_testing

let add_test ?dir name command args =
  Project_cmd (Add_test { name; command; args; dir })

let get_filename_component ?(cache = false) ~mode var filename =
  Get_filename_component { var; filename; mode; cache }

let get_global_property ~property var =
  Get_property
    {
      var;
      global = true;
      directory = "";
      source = "";
      source_directory = "";
      source_target_directory = "";
      install = "";
      test = "";
      test_directory = "";
      variable = false;
      property_name = property;
      set = false;
    }

let set_property ?(global = false) ?(directory = []) ?(targets = [])
    ?(sources = []) ?(source_directories = []) ?(source_target_directories = [])
    ?(installs = []) ?(tests = []) ?(test_directories = []) ?(caches = [])
    ?(append = false) ?(append_string = false) prop_value_pairs =
  let properties =
    List.map ~f:(fun (prop, value) -> { prop; value }) prop_value_pairs
  in
  Set_property
    {
      global;
      directory;
      targets;
      sources;
      source_directories;
      source_target_directories;
      installs;
      tests;
      test_directories;
      caches;
      append;
      append_string;
      properties;
    }

let set_target_properties target prop_value_pairs =
  let properties =
    List.map ~f:(fun (prop, value) -> { prop; value }) prop_value_pairs
  in
  Project_cmd (Set_target_properties { target; properties })

let set_tests_properties ?dir tests prop_value_pairs =
  let properties =
    List.map ~f:(fun (prop, value) -> { prop; value }) prop_value_pairs
  in
  Project_cmd (Set_tests_properties { tests; dir; properties })

let configure_package_config_file ?(path_vars = [])
    ?(no_set_and_check_macro = false)
    ?(no_check_required_components_macro = false) install_dest input output =
  Module_cmd
    (Configure_package_config_file
       {
         input;
         output;
         install_dest;
         path_vars;
         no_set_and_check_macro;
         no_check_required_components_macro;
       })

let write_basic_package_version_file ~compatibility ?(arch_independent = false)
    ?version file =
  Module_cmd
    (Write_basic_package_version_file
       { file; version; compatibility; arch_independent })

(* Default empty find_var_args — override specific fields *)
let find_var_defaults var = {
  var; names = []; hints = []; paths = []; path_suffixes = [];
  doc = None; required = false; no_cache = false; no_default_path = false;
  no_package_root_path = false; no_cmake_path = false;
  no_cmake_environment_path = false; no_system_environment_path = false;
  no_cmake_system_path = false; no_cmake_install_prefix = false;
}

let find_library ?(names = []) ?(hints = []) ?(paths = [])
    ?(path_suffixes = []) ?doc ?(required = false) ?(no_cache = false)
    ?(no_default_path = false) ?(no_package_root_path = false)
    ?(no_cmake_path = false) ?(no_cmake_environment_path = false)
    ?(no_system_environment_path = false) ?(no_cmake_system_path = false)
    ?(no_cmake_install_prefix = false) var =
  Find_library { (find_var_defaults var) with
    names; hints; paths; path_suffixes; doc; required; no_cache;
    no_default_path; no_package_root_path; no_cmake_path;
    no_cmake_environment_path; no_system_environment_path;
    no_cmake_system_path; no_cmake_install_prefix }

let find_path ?(names = []) ?(hints = []) ?(paths = [])
    ?(path_suffixes = []) ?doc ?(required = false) ?(no_cache = false)
    ?(no_default_path = false) ?(no_package_root_path = false)
    ?(no_cmake_path = false) ?(no_cmake_environment_path = false)
    ?(no_system_environment_path = false) ?(no_cmake_system_path = false)
    ?(no_cmake_install_prefix = false) var =
  Find_path { (find_var_defaults var) with
    names; hints; paths; path_suffixes; doc; required; no_cache;
    no_default_path; no_package_root_path; no_cmake_path;
    no_cmake_environment_path; no_system_environment_path;
    no_cmake_system_path; no_cmake_install_prefix }

let find_file ?(names = []) ?(hints = []) ?(paths = [])
    ?(path_suffixes = []) ?doc ?(required = false) ?(no_cache = false)
    ?(no_default_path = false) ?(no_package_root_path = false)
    ?(no_cmake_path = false) ?(no_cmake_environment_path = false)
    ?(no_system_environment_path = false) ?(no_cmake_system_path = false)
    ?(no_cmake_install_prefix = false) var =
  Find_file { (find_var_defaults var) with
    names; hints; paths; path_suffixes; doc; required; no_cache;
    no_default_path; no_package_root_path; no_cmake_path;
    no_cmake_environment_path; no_system_environment_path;
    no_cmake_system_path; no_cmake_install_prefix }

let find_program ?(names = []) ?(hints = []) ?(paths = [])
    ?(path_suffixes = []) ?doc ?(required = false) ?(no_cache = false)
    ?(no_default_path = false) ?(no_package_root_path = false)
    ?(no_cmake_path = false) ?(no_cmake_environment_path = false)
    ?(no_system_environment_path = false) ?(no_cmake_system_path = false)
    ?(no_cmake_install_prefix = false) var =
  Find_program { (find_var_defaults var) with
    names; hints; paths; path_suffixes; doc; required; no_cache;
    no_default_path; no_package_root_path; no_cmake_path;
    no_cmake_environment_path; no_system_environment_path;
    no_cmake_system_path; no_cmake_install_prefix }

let message ?(mode = Mm_status) texts = Message { mode; texts }

let math ?(output_format = Decical) ~var exp =
  Math_lib { var; exp; output_format }

let set_cache ?(force = false) ?(cache_type = Ct_string) ?(docstring = "") var values =
  Set_cache { var; values; cache_type; docstring; force }

let unset_cache var = Unset { var; cache = true; parent_scope = false }

let macro name ?(args = []) commands = Macro { name; args; commands }

let file_relative_path ~var ~base file = File_relative_path { var; base; file }

let try_compile ?(compile_defs = []) ?(link_libs = []) ?(link_opts = [])
    ?(cmake_flags = []) ?output_variable ?copy_file ?(no_cache = false)
    ?c_standard ?cxx_standard result_var sources =
  Try_compile {
    tc_result_var = result_var; tc_sources = sources;
    tc_compile_definitions = compile_defs; tc_link_libraries = link_libs;
    tc_link_options = link_opts; tc_cmake_flags = cmake_flags;
    tc_output_variable = output_variable; tc_copy_file = copy_file;
    tc_no_cache = no_cache; tc_c_standard = c_standard;
    tc_cxx_standard = cxx_standard }

let try_run ?(compile_defs = []) ?(link_libs = [])
    ?compile_output_variable ?run_output_variable ?(args = [])
    run_result_var compile_result_var sources =
  Try_run {
    tr_run_result_var = run_result_var; tr_compile_result_var = compile_result_var;
    tr_sources = sources; tr_compile_definitions = compile_defs;
    tr_link_libraries = link_libs;
    tr_compile_output_variable = compile_output_variable;
    tr_run_output_variable = run_output_variable; tr_args = args }

let add_custom_target name ?(all = false) ?(commands = []) ?(depends = [])
    ?(byproducts = []) ?working_directory ?comment ?(verbatim = false)
    ?(uses_terminal = false) ?(sources = []) () =
  Project_cmd (Add_custom_target {
    name; all; commands; depends; byproducts; working_directory; comment;
    job_pool = []; job_server_aware = false; verbatim; uses_terminal;
    command_expand_list = []; sources })
