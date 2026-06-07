(* Yc_primitives — single source of truth for all typed command names
   and reserved identifiers in yelu_cmake.

   Used by the parser to dispatch to typed handlers, and by the
   wellform checker to flag escaping violations (ECmakeApply that
   shadows a typed primitive, variable names that collide with
   reserved words). *)

open Base

(* ── Typed command names — every cmake builtin with a yc API ── *)

let command_names : Set.M(String).t =
  Set.of_list (module String) [
    (* cmake_op *)
    "cmake_minimum_required"; "project"; "message";
    "include"; "include_guard"; "policy_set";
    "enable_language"; "execute_process"; "separate_arguments";
    "cmake_call"; "cmake_eval"; "cmake_get_log_level"; "math";
    (* string *)
    "string_toupper"; "string_tolower"; "string_length"; "string_strip";
    "string_concat"; "string_replace"; "string_regex_match";
    "string_regex_matchall"; "string_regex_replace"; "string_regex_quote";
    "string_append"; "string_prepend"; "string_join"; "string_find";
    "string_substring"; "string_repeat"; "string_genex_strip";
    "string_compare"; "string_make_c_identifier"; "string_timestamp";
    "string_hex"; "string_uuid"; "string_json";
    (* list *)
    "list_append"; "list_length"; "list_get"; "list_remove_item";
    "list_remove_duplicates"; "list_reverse"; "list_sort"; "list_join";
    "list_find"; "list_prepend"; "list_insert"; "list_remove_at";
    "list_pop_back"; "list_pop_front"; "list_sublist"; "list_filter";
    "list_transform";
    (* path *)
    "path_get"; "path_has"; "path_is_absolute"; "path_is_relative";
    "path_is_prefix"; "path_compare"; "path_set"; "path_append";
    "path_append_string"; "path_remove_filename"; "path_replace_filename";
    "path_remove_extension"; "path_replace_extension"; "path_normal_path";
    "path_relative_path"; "path_absolute_path"; "path_native_path";
    "path_convert_to_cmake"; "path_convert_to_native"; "path_hash";
    "get_filename_component";
    (* file *)
    "file_read"; "file_write"; "file_glob"; "file_copy"; "file_rename";
    "file_remove"; "file_real_path"; "file_size"; "file_timestamp";
    "file_make_directory"; "file_touch"; "file_strings";
    "file_read_symlink"; "configure_file";
    (* target *)
    "add_exe"; "add_lib"; "add_lib_imported"; "add_lib_alias";
    "add_exe_alias"; "add_custom_target"; "add_dependencies";
    "link_lib"; "include_dirs"; "compile_defs"; "compile_opts";
    "compile_feats"; "link_opts"; "link_dirs"; "target_sources";
    "target_link_libraries"; "target_include_directories";
    "target_compile_definitions"; "target_compile_options";
    "precompile_headers";
    (* dir *)
    "add_subdirectory"; "include_directories";
    "add_compile_definitions"; "add_compile_options";
    "add_definitions"; "add_link_options"; "link_directories";
    (* test *)
    "enable_testing"; "add_test";
    (* property *)
    "get_target_property"; "set_target_properties"; "set_property";
    "get_directory_property"; "set_directory_property";
    "set_test_properties"; "set_source_property";
    "set_source_files_properties";
    "set_global_property"; "get_global_property";
    (* find *)
    "find_package"; "find_library"; "find_path";
    "find_program"; "find_file";
    (* install *)
    "install_targets"; "install_files"; "install_export"; "export";
    "configure_package_config_file";
    "write_basic_package_version_file";
    (* try *)
    "try_compile"; "try_run";
  ]

let is_known_command name =
  Set.mem command_names name

(* ── Reserved identifiers — cannot be used as variable/target names ── *)

let reserved_names : Set.M(String).t =
  Set.union_list (module String) [
    command_names;
    Set.of_list (module String) [
      (* control flow *)
      "let"; "in"; "if"; "then"; "else";
      "foreach"; "RANGE"; "function"; "fun"; "macro";
      "while"; "break"; "continue"; "return";
      (* type keywords *)
      "target"; "Target"; "cvar"; "Cvar"; "cache";
      (* boolean *)
      "ON"; "OFF";
      (* condition operators *)
      "not"; "and"; "or"; "str_eq"; "str_lt"; "str_gt";
      "eq"; "lt"; "gt"; "ver_lt"; "ver_gt"; "ver_eq";
      "match"; "list_in"; "exists"; "is_dir"; "is_abs";
      "defined"; "policy";
    ];
  ]

let is_reserved name =
  Set.mem reserved_names name
