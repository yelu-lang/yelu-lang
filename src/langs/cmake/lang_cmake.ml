open Base
(* CMake 3.31.0 *)

(* An AST of cmake-command

   When the block() is inside a foreach() or while() command, the break() and continue() commands can be used inside the block.
   https://cmake.org/cmake/help/latest/command/block.html
*)

type permissions = string list
type directory = string
type path = string
type file = path
type id = string
type version = { major : int; minor : int; patch : string }

(* source *)
type source = string
type test = string
type policy = Policy
type var = string
type output = string
(* [Bracket] carries the source-level bracket level (number of `=`
   between the outer `[` and inner `[`/`]`). Level 0 = `[[...]]`,
   level 1 = `[=[...]=]`, level 2 = `[==[...]==]`, etc. Preserving
   the level lets parser/printer round-trip be byte-equal even on
   bracket-arg variants. *)
type arg = Bare of string | Quoted of string | Bracket of int * string
type description = arg
type cache_entry = Cache_entry

type cache_type = Ct_bool | Ct_filepath | Ct_path | Ct_string | Ct_internal
type before_or_after = Before | After | Default_order
type depend = string
type comment = string
type doc = string
type option_ = string
type job_pool = string list

(* target *)
type target = string
type feature = string
type items_with_kind = { kind : string; items : arg list }
type target_feature = { kind : string; feature : string }
type set = SSet
type file_set_type = Fs_headers | Fs_cxxmodules
type target_kind = Public | Private | Interface | Plain

type library_type =
  | Lib_static
  | Lib_shared
  | Lib_module
  | Lib_unknown
  | Lib_object
  | Lib_interface
  | Lib_global

type supported_lang =
  | Lang_none
  | Lang_c
  | Lang_cxx
  | Lang_csharp
  | Lang_cuda
  | Lang_objc
  | Lang_objcxx
  | Lang_fortran
  | Lang_hipy
  | Lang_ispc
  | Lang_swift
  | Lang_asm
  | Lang_asm_nasm
  | Lang_asm_marmasm
  | Lang_asm_masm
  | Lang_asm_att

type compatibility =
  | Any_newer_version
  | Same_major_version
  | Same_minor_version
  | Exact_version

type target_file_set = {
  kind : string;
  file_set : set;
  type_ : file_set_type;
  base_dirs : directory list;
  files : file list;
}

type target_sources_item =
  | Tsi_plain of items_with_kind
  | Tsi_file_set of target_file_set

type link_library_kind = Ll_debug | Ll_optimized | Ll_general

type link_library_group = {
  item : string;
  items : string list;
  kind : link_library_kind;
}

type land_dep = { lang : string; depend : depend }
type definition = Def_var of var | Def_var_kv of { var : var; value : arg }
type property = { prop : string; value : arg }
type include_guard_scope = Ig_directory | Ig_global
type set_property_mode = Sp_set | Sp_defined | Sp_brief_doc | Sp_full_doc
type add_executable_option = Ae_win32 | Ae_macos_bundle | Ae_exclude_from_all

type custom_command = { command : string; args : string list }
type custom_when = Cw_pre_build | Cw_pre_link | Cw_post_build

(* Argument Caveats *)
type pseudo_var = Argn | Argc | Argv | Argv0
type math_output_format = Decical | Hexdecimal

type message_mode =
  | Mm_none
  | Mm_status
  | Mm_notice
  | Mm_verbose
  | Mm_debug
  | Mm_trace
  | Mm_warning
  | Mm_author_warning
  | Mm_check_start
  | Mm_check_pass
  | Mm_check_fail
  | Mm_send_error
  | Mm_fatal_error
  | Mm_deprecation

type message_reporting_state = Mr_check_start | Mr_check_pass | Mr_check_fail

(* Shared argument record for find_library / find_path / find_file / find_program *)
type find_var_args = {
  var : var;
  names : arg list;
  hints : arg list;
  paths : arg list;
  path_suffixes : string list;
  doc : string option;
  required : bool;
  no_cache : bool;
  no_default_path : bool;
  no_package_root_path : bool;
  no_cmake_path : bool;
  no_cmake_environment_path : bool;
  no_system_environment_path : bool;
  no_cmake_system_path : bool;
  no_cmake_install_prefix : bool;
}

type define_property_mode =
  | Dp_global
  | Dp_directory
  | Dp_target
  | Dp_source
  | Dp_test
  | Dp_variable
  | Dp_cached_variable

type cmake_var =
  | Get_os_release_fallback_scripts
  | Get_os_release_fallback_result_of of var
  | Get_os_release_fallback_result

type variable_watch_access =
  | Vw_read_access
  | Vm_unknown_read_access
  | Vm_unknown_modified_access
  | Vm_removed_access

type separate_arguments_mode =
  | Sa_plain               (* old-style: separate_arguments(var) — splits var in-place *)
  | Sa_unix_command
  | Sa_windows_command
  | Sa_native_command
  | Sa_program
  | Sa_args

(* TODO: https://cmake.org/cmake/help/latest/command/cmake_host_system_information.html *)
type host_system_information_windows_reg_view =
  | Wr_view_64
  | Wr_view_32
  | Wr_view_64_32
  | Wr_view_32_64
  | Wr_view_host
  | Wr_view_target
  | Wr_view_both

type configure_file_permission =
  | No_source_permission
  | Use_source_permission
  | File_permission

type newline_style =
  | Newline_unix
  | Newline_dos
  | Newline_win32
  | Newline_lf
  | Newline_crlf

type dep_provider_cmd = Dp_find_package | Dp_fetch_content
type scope = Function_scope | Directory_scope

type query_key =
  | Number_logical_cores
  | Number_physical_cores
  | Hostname
  | FQDN (* Fully qualified domain name *)
  | Total_virtual_memory
  | Available_virtual_memory
  | Total_physical_memory
  | Available_physical_memory
  | Is_64bit
  | Has_fpu
  | Has_mmx
  | Has_mmx_plus
  | Has_sse
  | Has_sse2
  | Has_sse_fp
  | Has_sse_mmx
  | Has_amd_3dnow
  | Has_amd_3dnow_plus
  | Has_ia64
  | Has_serial_number
  | Proceessor_name
  | Processor_description
  | Os_name
  | Os_release
  | Os_version
  | Os_platform
  | Msystem_prefix
  | Distrib_info
  | Distrib_name of string

type cond_check =
  (* Existence Checks *)
  | Exist_command of var
  | Exist_policy of var
  | Exist_target of var
  | Exist_test of var
  | Exist_defined of var

type code = string
type gs_directory = Gs_directory of directory | Gs_target_directory of target

(* list() sub-commands *)
type list_sort_order = Ls_ascending | Ls_descending
type list_sort_compare = Ls_string | Ls_file_basename | Ls_natural
type list_sort_case = Ls_sensitive | Ls_insensitive
type list_filter_mode = Lf_include | Lf_exclude

type list_transform_action =
  | Lta_append of arg
  | Lta_prepend of arg
  | Lta_toupper
  | Lta_tolower
  | Lta_strip
  | Lta_genex_strip
  | Lta_replace of { match_regex : string; replace : string }

type list_transform_selector =
  | Lts_at of int list
  | Lts_for of { start : int; stop : int; step : int option }
  | Lts_regex of string

type list_cmd =
  | Lc_length of { var : var; out : var }
  | Lc_get of { var : var; indices : int list; out : var }
  | Lc_sublist of { var : var; begin_ : int; length : int; out : var }
  | Lc_find of { var : var; value : arg; out : var }
  | Lc_append of { var : var; values : arg list }
  | Lc_prepend of { var : var; values : arg list }
  | Lc_insert of { var : var; index : int; values : arg list }
  | Lc_remove_item of { var : var; values : arg list }
  | Lc_remove_at of { var : var; indices : int list }
  | Lc_remove_duplicates of { var : var }
  | Lc_reverse of { var : var }
  | Lc_sort of {
      var : var;
      order : list_sort_order option;
      compare : list_sort_compare option;
      case : list_sort_case option;
    }
  | Lc_join of { var : var; glue : arg; out : var }
  | Lc_filter of { var : var; mode : list_filter_mode; regex : string }
  | Lc_pop_back of { var : var; out_vars : var list }
  | Lc_pop_front of { var : var; out_vars : var list }
  | Lc_transform of {
      var : var;
      action : list_transform_action;
      selector : list_transform_selector option;
      output : var option;
    }

(* string() sub-commands *)
type string_compare_op =
  | Sco_less | Sco_greater | Sco_equal | Sco_notequal
  | Sco_less_equal | Sco_greater_equal

type string_regex_op =
  | Sr_match of { regex : string; out : var; inputs : arg list }
  | Sr_matchall of { regex : string; out : var; inputs : arg list }
  | Sr_replace of { regex : string; replace : arg; out : var; inputs : arg list }
  | Sr_quote of { out : var; inputs : arg list }

type string_cmd =
  | Sc_find of { string : arg; substring : arg; out : var; reverse : bool }
  | Sc_replace of { match_string : arg; replace_string : arg; out : var; inputs : arg list }
  | Sc_regex of string_regex_op
  | Sc_toupper of { string : arg; out : var }
  | Sc_tolower of { string : arg; out : var }
  | Sc_length of { string : arg; out : var }
  | Sc_substring of { string : arg; begin_ : int; length : int option; out : var }
  | Sc_strip of { string : arg; out : var }
  | Sc_genex_strip of { string : arg; out : var }
  | Sc_repeat of { string : arg; count : int; out : var }
  | Sc_concat of { out : var; inputs : arg list }
  | Sc_join of { glue : arg; out : var; inputs : arg list }
  | Sc_append of { var : var; inputs : arg list }
  | Sc_prepend of { var : var; prefix : arg; inputs : arg list }
  | Sc_compare of { op : string_compare_op; string1 : arg; string2 : arg; out : var }
  | Sc_make_c_identifier of { string : arg; out : var }
  | Sc_timestamp of { out : var; format : string option; utc : bool }
  | Sc_hex of { string : arg; out : var }
  | Sc_uuid of {
      out : var;
      namespace : string;
      name : string;
      type_ : [ `Md5 | `Sha1 ];
      upper : bool;
    }
  | Sc_json of {
      out : var;
      error_var : var option;
      op : json_op;
    }

and json_op =
  | Jop_get of { json : arg; path : arg list }
  | Jop_get_raw of { json : arg; path : arg list }
  | Jop_type of { json : arg; path : arg list }
  | Jop_length of { json : arg; path : arg list }
  | Jop_member of { json : arg; path : arg list }
  | Jop_remove of { json : arg; path : arg list }
  | Jop_set of { json : arg; path : arg list; value : arg }
  | Jop_equal of { json1 : arg; json2 : arg }
  | Jop_string_encode of { value : arg }

type scripting_cmd = exp

and cond = string list

and exp =
  (* Scripting Commands *)
  (* *)
  (* Constant and basic *)
  | Int of int
  | Bool of bool
  | Var_exp of string
  (* Expansion *)
  | Dollar of exp
  (* Structure *)
  | Block of block_exp (* endblock *)
  | While of { cond : cond; commands : exp } (* endwhile *)
  | Break
  | Continue
  | Quote of string
  | Return of { propogate_vars : var list }
  | Function of { name : var; args : string list; cmds : cmd list }
  | Apply of { name : var; args : arg list }
  | Macro of { name : var; args : var list; commands : exp } (* endmacro *)
  | If of { cond : cond; then_ : exp; else_ : exp option }
  | Foreach of { loop_var : var; items : arg list; commands : exp }
  | Foreach_range of {
      loop_var : var;
      start : var option;
      stop : var;
      step : var option;
      commands : exp;
    }
  | Foreach_in of {
      loop_var : var;
      lists : var list;
      items : arg list;
      commands : exp;
    }
  | Foreach_zip of {
      loop_vars : var list;
      lists : var list;
      commands : exp;
    }
  | Exp_list of exp list
  | Include of {
      file : arg;
      optional : bool;
      result_var : var option;
      (* NO_POLICY_SCOPE is a flag in cmake; this field tracks whether
         the call carried it. Previously typed as [scope option] which
         conflated the flag with the unrelated function/directory scope
         enum — fixed 2026-05-15 audit pass. *)
      no_policy_scope : bool;
    }
  | Include_guard of { scope : include_guard_scope }
  (* State *)
  | Cmake_option of { var : var; msg : string; value : arg }
  | Get_cmake_property of { var : var; property : string }
  | Get_directory_property of {
      var : var;
      directory : directory;
      property : string;
    }
  | Get_filename_component of {
      var : var;
      filename : path;
      mode : string;   (* DIRECTORY | NAME | EXT | NAME_WE | PATH | ABSOLUTE | REALPATH *)
      cache : bool;
    }
  (* | Set of { var_value_pairs : (var * arg) list; parent_scope : bool } *)
  | Set of { var : var; values : arg list; parent_scope : bool }
  | Set_cache of {
      var : var;
      values : arg list;
      cache_type : cache_type;
      docstring : string;
      force : bool;
    }
  | Set_env of { var : var; value : arg }
  | Set_directory_properties of { prop_value_pairs : (var * arg) list }
    (* https://cmake.org/cmake/help/latest/command/set_property.html *)
  | Unset of { var : var; cache : bool; parent_scope : bool }
  | Unset_env of { var : var }
  (* property *)
  | Get_property of {
      var : var;
      global : bool;
      directory : directory;
      source : source;
      source_directory : directory;
      source_target_directory : target;
      install : file;
      test : test;
      test_directory : directory;
      variable : bool;
      property_name : string;
      set : bool;
    }
  | Set_property of {
      global : bool;
      directory : directory list;
      targets : target list;
      sources : source list;
      source_directories : directory list;
      source_target_directories : target list;
      installs : file list;
      tests : test list;
      test_directories : directory list;
      caches : cache_entry list;
      append : bool;
      append_string : bool;
      properties : property list;
    }
  | Set_directory_property of { append : bool; property : string; values : arg list }
  | Set_source_property of { file : string; property : string; values : arg list }
  (* Info and debug *)
  | Site_name of { var : var }
  | Variable_watch of {
      var : var;
      command : string option;
      access : variable_watch_access;
      value : exp option;
      current_list_file : path option;
      stack : path list;
    }
  (* API *)
  | Execute_process of {
      commands : arg list list;
      working_directory : arg option;
      timeout : float option;
      result_variable : var option;
      output_variable : var option;
      error_variable : var option;
      input_file : arg option;
      output_file : arg option;
      error_file : arg option;
      output_quiet : bool;
      error_quiet : bool;
      output_strip_trailing_whitespace : bool;
      error_strip_trailing_whitespace : bool;
      command_error_is_fatal : string option;
    }
  | File_relative_path of { var : var; base : path; file : path }
  | File_glob of {
      var : var;
      recurse : bool;
      relative : path option;
      configure_depends : bool;
      patterns : arg list;
    }
  (* file() IO subcommands *)
  | File_read of { var : var; file : arg; offset : int option; limit : int option; hex : bool }
  | File_write of { file : arg; append : bool; content : arg list }
  | File_strings of { var : var; file : arg; regex : string option; encoding : string option; limit_count : int option }
  (* file() filesystem subcommands *)
  | File_touch of { files : arg list; nocreate : bool }
  | File_make_directory of { dirs : arg list }
  | File_rename of { old_ : arg; new_ : arg; result : var option; no_replace : bool }
  | File_remove of { files : arg list; recurse : bool }
  | File_copy_file of { input : arg; output : arg; result : var option; only_if_different : bool }
  (* file() path-query subcommands *)
  | File_real_path of { var : var; path : arg; base_dir : arg option; expand_tilde : bool }
  | File_size of { var : var; file : arg }
  | File_read_symlink of { var : var; link : arg }
  | File_timestamp of { var : var; file : arg; format : string option; utc : bool }
  | Find_file of find_var_args
  | Find_library of find_var_args
  | Find_package of {
      name : string;
      version : string option;
      exact : bool;
      quiet : bool;
      config_mode : bool;
      required : bool;
      components : string list;
      optional_components : string list;
    }
  | Find_path of find_var_args
  | Find_program of find_var_args
  (* List lib *)
  | List_cmd of list_cmd
  | String_cmd of string_cmd
  | Mark_as_advanced of { clear : bool; force : bool; vars : var list }
  | Math_lib of { var : var; exp : exp; output_format : math_output_format }
  | Message of { mode : message_mode; texts : string list }
  | Message_config_log of { texts : string list }
  | Option of { var : var; help_text : string list; value : exp }
  | Separete_arguments of { var : var; mode : separate_arguments_mode; input : arg option }
  | Cmake_cmd of cmake_cmd
  | Project_cmd of project_cmd
  | Module_cmd of module_cmd

(* File Operations *)
and cmd = exp

and block_exp = {
  scope_policy : policy list;
  scope_var : var list;
  propagate : var;
  body : cmd list;
}

and cmake_path_get_field =
  | Cpf_root_name | Cpf_root_directory | Cpf_root_path
  | Cpf_filename | Cpf_extension of bool | Cpf_stem of bool
  | Cpf_relative_part | Cpf_parent_path

and cmake_path_has_field =
  | Cph_root_name | Cph_root_directory | Cph_root_path | Cph_filename
  | Cph_extension | Cph_stem | Cph_relative_part | Cph_parent_path

and cmake_path_compare_op = Cpco_equal | Cpco_not_equal

and cmake_path_cmd =
  (* Decomposition queries *)
  | Cpp_get of { path_var : var; field : cmake_path_get_field; out_var : var }
  | Cpp_has of { path_var : var; field : cmake_path_has_field; out_var : var }
  | Cpp_is_absolute of { path_var : var; out_var : var }
  | Cpp_is_relative of { path_var : var; out_var : var }
  | Cpp_is_prefix of { path_var : var; input : arg; normalize : bool; out_var : var }
  | Cpp_compare of { input1 : arg; op : cmake_path_compare_op; input2 : arg; out_var : var }
  (* Modification *)
  | Cpp_set of { path_var : var; input : arg; normalize : bool }
  | Cpp_append of { path_var : var; inputs : arg list; out_var : var option }
  | Cpp_append_string of { path_var : var; inputs : arg list; out_var : var option }
  | Cpp_remove_filename of { path_var : var; out_var : var option }
  | Cpp_replace_filename of { path_var : var; input : arg; out_var : var option }
  | Cpp_remove_extension of { path_var : var; last_only : bool; out_var : var option }
  | Cpp_replace_extension of { path_var : var; last_only : bool; input : arg; out_var : var option }
  (* Generation *)
  | Cpp_normal_path of { path_var : var; out_var : var option }
  | Cpp_relative_path of { path_var : var; base_dir : arg option; out_var : var option }
  | Cpp_absolute_path of { path_var : var; base_dir : arg option; normalize : bool; out_var : var option }
  | Cpp_native_path of { path_var : var; normalize : bool; out_var : var }
  | Cpp_convert_to_cmake of { input : arg; normalize : bool; out_var : var }
  | Cpp_convert_to_native of { input : arg; normalize : bool; out_var : var }
  | Cpp_hash of { path_var : var; out_var : var }

and cmake_cmd =
  | Host_system_information of { result : var; query : query_key }
  | Host_system_information_windows_reg of {
      result : var;
      query : query_key;
      view : host_system_information_windows_reg_view option;
      separator : string option;
      error_var : var option;
    }
  | Cmake_meta_lang of cmake_meta_lang
  | Cmake_minimum_required of { min : version; max : version option }
  | Cmake_parse_argument of {
      prefix : string;
      one_keyword : string list;
      multi_keyword : string list;
      args : string list;
    }
  | Cmake_parse_argument_argv of {
      n : int;
      prefix : string;
      one_keyword : string list;
      multi_keyword : string list;
    }
  (* https://cmake.org/cmake/help/latest/command/cmake_path.html *)
  | Cmake_path of cmake_path_cmd
  | Cmake_policy_version of { min : version; max : version }
  | Cmake_policy_set of { id : string; new_ : bool }
  | Cmake_policy_get of { var : var }
  | Cmake_policy_push
  | Cmake_policy_pop
  | Configure_file of {
      input : path;
      output : path;
      permission_level : configure_file_permission option;
      permissions : permissions;
      copy_only : bool option;
      escape_quotes : bool option;
      only : bool option;
      newline_style : newline_style option;
    }

and cmake_meta_lang =
  | Meta_call of { cmd : cmd; arg : exp list }
  | Meta_eval of { code : code }
  | Meta_defer_call of { dir : directory; id : id; var : var }
  | Meta_defer_call_ids of { dir : directory; var : var }
  | Meta_defer_cancel of { dir : directory; id : id }
  | Meta_set_dep_provider of { var : var; dp_cmd : dep_provider_cmd }
  | Meta_get_msg_log_level of { var : var }
  | Meta_exit of { exit_code : int }

and project_cmd =
  (* Project Commands *)
  (* Property *)
  | Get_source_file_property of { var : var; file : file; property : property }
  | Set_source_files_properties of {
      files : file list;
      directories : directory list;
      target_directories : target list;
    }
  | Get_target_property of { var : var; target : target; property : property }
  | Set_target_properties of { target : target; properties : property list }
  | Enable_testing
  | Add_test of {
      name : string;
      command : string;
      args : string list;
      dir : directory option;
    }
  | Get_test_property of {
      test : test;
      property : property;
      directory : directory option;
      var : var;
    }
  | Set_tests_properties of {
      tests : test list;
      dir : directory option;
      properties : property list;
    }
  | Define_property of {
      mode : define_property_mode;
      property_name : string;
      inherited : bool;
      brief_docs : doc list;
      full_docs : doc list;
      initialize_from : var;
    }
  | Add_compile_definitions of { defs : definition list }
  | Add_compile_options of { options_ : option_ list }
  | Add_definitions of { defs : definition list }
  | Remove_definitions of { defs : definition list }
  | Add_dependencies of { target : target; dep : depend }
  | Add_executable of {
      name : string;
      options : add_executable_option list;
      sources : source list;
    }
  | Add_executable_imported of { name : string; global : bool }
  | Add_executable_alias of { name : string; target : target }
  | Add_library of {
      name : string;
      exclude_from_all : bool;
      type_ : string option;
      sources : file list;
    }
  | Add_library_imported of { name : string; lib_type : string option; global : bool }
  | Add_library_object of { name : string; sources : file list }
  | Add_library_interface of { name : string }
  | Add_library_alias of { name : string; target : target }
  | Add_link_options of { options : option_ list }
  | Add_subdirectory of {
      source_dir : directory;
      binary_dir : directory option;
      exclude_from_all : bool;
      system : bool;
    }
  (* Target *)
  | Target_compile_features of {
      target : target;
      features : target_feature list;
    }
    (* Any leading -D on an item will be removed *)
  | Target_compile_definitions of {
      target : target;
      items : items_with_kind list;
    }
  | Target_compile_options of {
      target : target;
      before : bool;
      items : items_with_kind list;
    }
  | Target_include_directories of {
      target : target;
      system : bool option;
      before_or_after : before_or_after option;
      items : items_with_kind list;
    }
  | Target_link_directories of {
      target : target;
      before : bool;
      items : items_with_kind list;
    }
  | Target_link_libraries of {
      targets : target list;
      items : items_with_kind list;
    }
  | Target_link_options of {
      target : target;
      before : bool;
      items : items_with_kind list;
    }
  | Target_precompile_headers of {
      target : target;
      items : items_with_kind list;
    }
  | Target_sources of { target : target; items : items_with_kind list }
  | Target_sources_file_set of { target : target; items : target_sources_item list }
  (* custom *)
  | Add_custom_command of {
      outputs : string list;
      commands : custom_command list;
      main_dependency : depend option;
      depends : depend list;
      byproducts : file list;
      implicit_depends : land_dep list;
      working_directory : directory option;
      comment : comment option;
      depfile : file option;
      job_pool : job_pool option;
      job_server_aware : bool;
      verbatim : bool;
      append : bool;
      uses_terminal : bool;
      codegen : bool;
      command_expand_list : string list;
      depends_explicit_only : bool;
    }
  | Add_custom_command_target of {
      target : target;
      when_ : custom_when;
      commands : custom_command list;
      comment : comment option;
      verbatim : bool;
      uses_terminal : bool;
    }
  | Add_custom_target of {
      name : string;
      all : bool;
      commands : custom_command list;
      depends : depend list;
      byproducts : file list;
      working_directory : directory option;
      comment : comment option;
      job_pool : job_pool;
      job_server_aware : bool;
      verbatim : bool;
      uses_terminal : bool;
      command_expand_list : string list;
      sources : file list;
    }
  (* Include *)
  | Include_directories of {
      before_or_after : before_or_after;
      system : bool;
      dir : directory;
      dirs : directory list;
    }
  | Include_external_msproject of {
      projectname : string;
      location : directory;
      type_ : string option;
      guid : string option;
      platform : string option;
      deps : depend list;
    }
  | Include_regular_expression of {
      regex_match : string;
      regex_complain : string option;
    }
  (* Link *)
  | Link_directories of {
      before_or_after : before_or_after;
      directory : directory;
      directories : directory list;
    }
  | Link_libraries of { groups : link_library_group list }
  (* *)
  | Aux_source_directory of { dir : directory; var : var }
  | Build_command of {
      var : var;
      configuration : string option;
      parallel_level : int option;
      target : target option;
      project_name : string option;
    }
  | Cmake_file_api of { api_version : version; code_model : version list }
  | Create_test_sourcelist of {
      name : string;
      drive_name : string;
      tests : test list;
      options : option_ list;
      extra_include : string;
      function_ : string;
    }
  | Enable_language of { langs : string list; optional : bool }
  | Export_targets of { targets : target list }
  | Export_export of { name : string; file : arg option }
  | Export_package of { name : string }
  | Export_setup of { name : string }
  | Fltk_wrap_ui of { resulting_library_name : string; sources : source list }
  | Install_targets of {
      targets : target list;
      (* target_type : string; *)
      destination : arg;
      component : string option;
      rename : string option;
      export : string option;
      permissions : permissions;
    }
  | Install_files of {
      files : arg list;
      destination : arg;
      component : string option;
      rename : string option;
      permissions : permissions;
    }
  | Install_export of {
      file : arg option;
      export : arg;
      destination : arg;
      namespace : string option;
      component : string option;
      rename : string option;
      permissions : permissions;
    }
  | Load_cache_read of {
      directory : directory;
      prefix : string;
      entries : string list;
    }
  | Load_cache of {
      directory : directory;
      exclude : string list;
      include_internals : string list;
    }
  | Project of {
      name : string;
      version : version option;
      description : string option;
      homepage_url : string option;
      languages : string list;
    }
  | Source_group of { name : string; files : string list; regular_exp : string }
  | Source_group_tree of { root : string; prefix : string; files : file list }
  | Try_compile of try_compile_exp
  | Try_run of try_run_exp

and try_compile_exp = {
  tc_result_var : var;
  tc_sources : arg list;
  tc_compile_definitions : arg list;
  tc_link_libraries : arg list;
  tc_link_options : arg list;
  tc_cmake_flags : arg list;
  tc_output_variable : var option;
  tc_copy_file : arg option;
  tc_no_cache : bool;
  tc_c_standard : string option;
  tc_cxx_standard : string option;
}

and try_run_exp = {
  tr_run_result_var : var;
  tr_compile_result_var : var;
  tr_sources : arg list;
  tr_compile_definitions : arg list;
  tr_link_libraries : arg list;
  tr_compile_output_variable : var option;
  tr_run_output_variable : var option;
  tr_args : arg list;
}

and module_cmd =
  (* CMakePackageConfigHelpers *)
  | Configure_package_config_file of {
      input : arg;
      output : arg;
      install_dest : arg;
      path_vars : var list;
      no_set_and_check_macro : bool;
      no_check_required_components_macro : bool;
    }
  | Write_basic_package_version_file of {
      file : arg;
      version : arg option;
      compatibility : string;
      arch_independent : bool;
    }
(* CTest Commands *)

(* Deprecated Commands *)

type special_dir = {
  source_dir : directory; (* for source code and CMakeLists files*)
  binary_dir : directory; (* also build directory *)
}
