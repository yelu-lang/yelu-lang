open Base
open Lang_cmake

let list_sp pp = Fmt.list ~sep:Fmt.sp pp
let list_br pp = Fmt.list ~sep:Stdlib.Format.pp_force_newline pp
let quoted s = "\"" ^ s ^ "\""
let pp_quoted = Fmt.using quoted Fmt.string

let pp_with_key key pp_ele ff = function
  | None -> ()
  | Some ele -> Fmt.pf ff "%s %a " key pp_ele ele

let pp_list_with_key key pp_ele ff = function
  | [] -> ()
  | xs -> Fmt.pf ff "%s %a " key (list_sp pp_ele) xs

let pp_flag key ff flag = if flag then Fmt.pf ff "@;%s " key else ()

let pp_version_opt ff = function
  | None -> ()
  | Some ver -> Fmt.pf ff "VERSION %s" (Lang_cmake_strings.of_version ver)

let pp_target ff s = Fmt.string ff s
let pp_source ff s = Fmt.string ff s
let pp_var ff s = Fmt.string ff s

let pp_cond ff cond =
  Fmt.string ff (String.concat ~sep:" " cond)
let pp_string_quoted ff msg = Fmt.string ff (quoted msg)
let pp_message = pp_string_quoted

let pp_arg ff = function
  | Bare s -> Fmt.string ff s
  | Quoted s -> pp_string_quoted ff s
  (* Bracket content: emit verbatim between delimiters whose `=` count
     matches the source. Tree-sitter strips the optional newline that
     can follow `[=[` and precede `]=]`, so we don't re-add it. *)
  | Bracket (level, s) ->
      let eqs = String.make level '=' in
      Fmt.pf ff "[%s[%s]%s]" eqs s eqs

let string_of_scope = function
  | Function_scope -> "FUNCTION"
  | Directory_scope -> "DIRECTORY"

let pp_scope = Fmt.using string_of_scope Fmt.string

let pp_property ff { prop; value } =
  Fmt.(pf ff "%a %a" string prop pp_arg value)

let pp_parent_scope =
  Fmt.using (fun ps -> if ps then "PARENT_SCOPE" else "") Fmt.string

let pp_args_with_kind ff ({ kind; items } : items_with_kind) =
  Fmt.pf ff "%s %a" kind (list_sp pp_arg) items

let pp_target_feature ff ({ kind; feature } : target_feature) =
  Fmt.pf ff "%s %s" kind feature

let pp_custom_command ff ({ command; args } : custom_command) =
  Fmt.(pf ff "%a %a" string command (list_sp string) args)

(* New helper printers *)

let string_of_include_guard_scope = function
  | Ig_directory -> "DIRECTORY"
  | Ig_global -> "GLOBAL"

let pp_include_guard_scope =
  Fmt.using string_of_include_guard_scope Fmt.string

let pp_message_mode ff mode =
  let s = Lang_cmake_strings.of_message_mode mode in
  if String.length s > 0 then Fmt.pf ff "%s " s

let string_of_message_reporting_state = function
  | Mr_check_start -> "CHECK_START"
  | Mr_check_pass -> "CHECK_PASS"
  | Mr_check_fail -> "CHECK_FAIL"

let pp_message_reporting_state =
  Fmt.using string_of_message_reporting_state Fmt.string

let string_of_math_output_format = function
  | Decical -> "DECIMAL"
  | Hexdecimal -> "HEXADECIMAL"

let pp_math_output_format = Fmt.using string_of_math_output_format Fmt.string

let string_of_separate_arguments_mode = function
  | Sa_plain -> ""
  | Sa_unix_command -> "UNIX_COMMAND"
  | Sa_windows_command -> "WINDOWS_COMMAND"
  | Sa_native_command -> "NATIVE_COMMAND"
  | Sa_program -> "PROGRAM"
  | Sa_args -> "ARGS"

let pp_separate_arguments_mode =
  Fmt.using string_of_separate_arguments_mode Fmt.string

let string_of_before_or_after = function Before -> "BEFORE" | After -> "AFTER" | Default_order -> ""
let pp_before_or_after = Fmt.using string_of_before_or_after Fmt.string


let string_of_define_property_mode = function
  | Dp_global -> "GLOBAL"
  | Dp_directory -> "DIRECTORY"
  | Dp_target -> "TARGET"
  | Dp_source -> "SOURCE"
  | Dp_test -> "TEST"
  | Dp_variable -> "VARIABLE"
  | Dp_cached_variable -> "CACHED_VARIABLE"

let pp_define_property_mode =
  Fmt.using string_of_define_property_mode Fmt.string

let pp_definition ff = function
  | Def_var var -> pp_var ff var
  | Def_var_kv { var; value } -> Fmt.pf ff "%a=%a" pp_var var pp_arg value

let string_of_add_executable_option = function
  | Ae_win32 -> "WIN32"
  | Ae_macos_bundle -> "MACOSX_BUNDLE"
  | Ae_exclude_from_all -> "EXCLUDE_FROM_ALL"

let pp_add_executable_option =
  Fmt.using string_of_add_executable_option Fmt.string

let string_of_link_library_kind = function
  | Ll_debug -> "debug"
  | Ll_optimized -> "optimized"
  | Ll_general -> "general"

let pp_link_library_kind = Fmt.using string_of_link_library_kind Fmt.string

let pp_link_library_group ff { item; items; kind } =
  match kind with
  | Ll_general -> Fmt.(pf ff "%s%a" item (fun ff ls -> if List.length ls > 0 then pf ff " %a" (list_sp string) ls) items)
  | _ -> Fmt.(pf ff "%a %s%a" pp_link_library_kind kind item (fun ff ls -> if List.length ls > 0 then pf ff " %a" (list_sp string) ls) items)

let string_of_file_set_type = function
  | Fs_headers -> "HEADERS"
  | Fs_cxxmodules -> "CXX_MODULES"

let pp_file_set_type = Fmt.using string_of_file_set_type Fmt.string

let pp_target_file_set ff { kind; file_set = _; type_; base_dirs; files } =
  Fmt.(
    pf ff "%s @;FILE_SET %a%a%a" kind pp_file_set_type type_
      (pp_list_with_key "BASE_DIRS" string) base_dirs
      (pp_list_with_key "FILES" string) files)

let pp_target_sources_item ff = function
  | Tsi_plain iwk -> pp_args_with_kind ff iwk
  | Tsi_file_set fs -> pp_target_file_set ff fs

let string_of_dep_provider_cmd = function
  | Dp_find_package -> "FIND_PACKAGE"
  | Dp_fetch_content -> "FETCHCONTENT_MAKEAVAILABLE_SERIAL"

let pp_dep_provider_cmd = Fmt.using string_of_dep_provider_cmd Fmt.string

let string_of_query_key = function
  | Number_logical_cores -> "NUMBER_OF_LOGICAL_CORES"
  | Number_physical_cores -> "NUMBER_OF_PHYSICAL_CORES"
  | Hostname -> "HOSTNAME"
  | FQDN -> "FQDN"
  | Total_virtual_memory -> "TOTAL_VIRTUAL_MEMORY"
  | Available_virtual_memory -> "AVAILABLE_VIRTUAL_MEMORY"
  | Total_physical_memory -> "TOTAL_PHYSICAL_MEMORY"
  | Available_physical_memory -> "AVAILABLE_PHYSICAL_MEMORY"
  | Is_64bit -> "IS_64BIT"
  | Has_fpu -> "HAS_FPU"
  | Has_mmx -> "HAS_MMX"
  | Has_mmx_plus -> "HAS_MMX_PLUS"
  | Has_sse -> "HAS_SSE"
  | Has_sse2 -> "HAS_SSE2"
  | Has_sse_fp -> "HAS_SSE_FP"
  | Has_sse_mmx -> "HAS_SSE_MMX"
  | Has_amd_3dnow -> "HAS_AMD_3DNOW"
  | Has_amd_3dnow_plus -> "HAS_AMD_3DNOW_PLUS"
  | Has_ia64 -> "HAS_IA64"
  | Has_serial_number -> "HAS_SERIAL_NUMBER"
  | Proceessor_name -> "PROCESSOR_NAME"
  | Processor_description -> "PROCESSOR_DESCRIPTION"
  | Os_name -> "OS_NAME"
  | Os_release -> "OS_RELEASE"
  | Os_version -> "OS_VERSION"
  | Os_platform -> "OS_PLATFORM"
  | Msystem_prefix -> "MSYSTEM_PREFIX"
  | Distrib_info -> "DISTRIB_INFO"
  | Distrib_name key -> Fmt.str "DISTRIB_INFO %s" key

let pp_query_key = Fmt.using string_of_query_key Fmt.string

let string_of_windows_reg_view = function
  | Wr_view_64 -> "64"
  | Wr_view_32 -> "32"
  | Wr_view_64_32 -> "64_32"
  | Wr_view_32_64 -> "32_64"
  | Wr_view_host -> "HOST"
  | Wr_view_target -> "TARGET"
  | Wr_view_both -> "BOTH"

let pp_windows_reg_view = Fmt.using string_of_windows_reg_view Fmt.string

let string_of_configure_file_permission = function
  | No_source_permission -> "NO_SOURCE_PERMISSIONS"
  | Use_source_permission -> "USE_SOURCE_PERMISSIONS"
  | File_permission -> "FILE_PERMISSIONS"

let pp_configure_file_permission =
  Fmt.using string_of_configure_file_permission Fmt.string

let string_of_newline_style = function
  | Newline_unix -> "UNIX"
  | Newline_dos -> "DOS"
  | Newline_win32 -> "WIN32"
  | Newline_lf -> "LF"
  | Newline_crlf -> "CRLF"

let pp_newline_style = Fmt.using string_of_newline_style Fmt.string

let string_of_variable_watch_access = function
  | Vw_read_access -> "READ_ACCESS"
  | Vm_unknown_read_access -> "UNKNOWN_READ_ACCESS"
  | Vm_unknown_modified_access -> "UNKNOWN_MODIFIED_ACCESS"
  | Vm_removed_access -> "REMOVED_ACCESS"

let _pp_variable_watch_access =
  Fmt.using string_of_variable_watch_access Fmt.string

let sp_char ff () = Fmt.char ff ' '

let pp_find_var ff cmd { var; names; short_form; hints; paths; path_suffixes; doc;
                         required; no_cache; no_default_path;
                         no_package_root_path; no_cmake_path;
                         no_cmake_environment_path; no_system_environment_path;
                         no_cmake_system_path; no_cmake_install_prefix } =
  let open Fmt in
  pf ff "%s(%s" cmd var;
  if not (List.is_empty names) then
    if short_form
    then pf ff " %a" (list ~sep:sp_char pp_arg) names
    else pf ff " NAMES %a" (list ~sep:sp_char pp_arg) names;
  if not (List.is_empty hints) then
    pf ff " HINTS %a" (list ~sep:sp_char pp_arg) hints;
  if not (List.is_empty paths) then
    pf ff " PATHS %a" (list ~sep:sp_char pp_arg) paths;
  if not (List.is_empty path_suffixes) then
    pf ff " PATH_SUFFIXES %a" (list ~sep:sp_char string) path_suffixes;
  Option.iter doc ~f:(fun s -> pf ff " DOC %S" s);
  if required then pf ff " REQUIRED";
  if no_cache then pf ff " NO_CACHE";
  if no_default_path then pf ff " NO_DEFAULT_PATH";
  if no_package_root_path then pf ff " NO_PACKAGE_ROOT_PATH";
  if no_cmake_path then pf ff " NO_CMAKE_PATH";
  if no_cmake_environment_path then pf ff " NO_CMAKE_ENVIRONMENT_PATH";
  if no_system_environment_path then pf ff " NO_SYSTEM_ENVIRONMENT_PATH";
  if no_cmake_system_path then pf ff " NO_CMAKE_SYSTEM_PATH";
  if no_cmake_install_prefix then pf ff " NO_CMAKE_INSTALL_PREFIX";
  pf ff ")"

let pp_list_sort_order ff = function
  | Ls_ascending -> Fmt.string ff "ASCENDING"
  | Ls_descending -> Fmt.string ff "DESCENDING"

let pp_list_sort_compare ff = function
  | Ls_string -> Fmt.string ff "STRING"
  | Ls_file_basename -> Fmt.string ff "FILE_BASENAME"
  | Ls_natural -> Fmt.string ff "NATURAL"

let pp_list_sort_case ff = function
  | Ls_sensitive -> Fmt.string ff "SENSITIVE"
  | Ls_insensitive -> Fmt.string ff "INSENSITIVE"

let pp_list_filter_mode ff = function
  | Lf_include -> Fmt.string ff "INCLUDE"
  | Lf_exclude -> Fmt.string ff "EXCLUDE"

let pp_list_transform_action ff = function
  | Lta_append v -> Fmt.(pf ff "APPEND %a" pp_arg v)
  | Lta_prepend v -> Fmt.(pf ff "PREPEND %a" pp_arg v)
  | Lta_toupper -> Fmt.string ff "TOUPPER"
  | Lta_tolower -> Fmt.string ff "TOLOWER"
  | Lta_strip -> Fmt.string ff "STRIP"
  | Lta_genex_strip -> Fmt.string ff "GENEX_STRIP"
  | Lta_replace { match_regex; replace } ->
      Fmt.(pf ff "REPLACE \"%s\" \"%s\"" match_regex replace)

let pp_list_transform_selector ff = function
  | Lts_at indices ->
      Fmt.(pf ff " AT %a" (list ~sep:sp_char int) indices)
  | Lts_for { start; stop; step } ->
      Fmt.pf ff " FOR %d %d" start stop;
      Option.iter step ~f:(fun s -> Fmt.pf ff " %d" s)
  | Lts_regex regex ->
      Fmt.pf ff " REGEX \"%s\"" regex

let pp_list_cmd ff = function
  | Lc_length { var; out } ->
      Fmt.(pf ff "list(LENGTH %a %a)@." pp_var var pp_var out)
  | Lc_get { var; indices; out } ->
      Fmt.(pf ff "list(GET %a %a %a)@." pp_var var
        (list ~sep:sp_char int) indices pp_var out)
  | Lc_sublist { var; begin_; length; out } ->
      Fmt.(pf ff "list(SUBLIST %a %d %d %a)@." pp_var var begin_ length pp_var out)
  | Lc_find { var; value; out } ->
      Fmt.(pf ff "list(FIND %a %a %a)@." pp_var var pp_arg value pp_var out)
  | Lc_append { var; values } ->
      Fmt.(pf ff "list(APPEND %a %a)@." pp_var var (list ~sep:sp_char pp_arg) values)
  | Lc_prepend { var; values } ->
      Fmt.(pf ff "list(PREPEND %a %a)@." pp_var var (list ~sep:sp_char pp_arg) values)
  | Lc_insert { var; index; values } ->
      Fmt.(pf ff "list(INSERT %a %d %a)@." pp_var var index
        (list ~sep:sp_char pp_arg) values)
  | Lc_remove_item { var; values } ->
      Fmt.(pf ff "list(REMOVE_ITEM %a %a)@." pp_var var
        (list ~sep:sp_char pp_arg) values)
  | Lc_remove_at { var; indices } ->
      Fmt.(pf ff "list(REMOVE_AT %a %a)@." pp_var var
        (list ~sep:sp_char int) indices)
  | Lc_remove_duplicates { var } ->
      Fmt.(pf ff "list(REMOVE_DUPLICATES %a)@." pp_var var)
  | Lc_reverse { var } ->
      Fmt.(pf ff "list(REVERSE %a)@." pp_var var)
  | Lc_sort { var; order; compare; case } ->
      Fmt.pf ff "list(SORT %a" pp_var var;
      Option.iter order ~f:(fun o -> Fmt.(pf ff " ORDER %a" pp_list_sort_order o));
      Option.iter compare ~f:(fun c -> Fmt.(pf ff " COMPARE %a" pp_list_sort_compare c));
      Option.iter case ~f:(fun cs -> Fmt.(pf ff " CASE %a" pp_list_sort_case cs));
      Fmt.pf ff ")@."
  | Lc_join { var; glue; out } ->
      Fmt.(pf ff "list(JOIN %a %a %a)@." pp_var var pp_arg glue pp_var out)
  | Lc_filter { var; mode; regex } ->
      Fmt.(pf ff "list(FILTER %a %a REGEX \"%s\")@." pp_var var
        pp_list_filter_mode mode regex)
  | Lc_pop_back { var; out_vars } ->
      Fmt.(pf ff "list(POP_BACK %a%a)@." pp_var var
        (fun ff vs -> List.iter ~f:(fun v -> pf ff " %a" pp_var v) vs) out_vars)
  | Lc_pop_front { var; out_vars } ->
      Fmt.(pf ff "list(POP_FRONT %a%a)@." pp_var var
        (fun ff vs -> List.iter ~f:(fun v -> pf ff " %a" pp_var v) vs) out_vars)
  | Lc_transform { var; action; selector; output } ->
      Fmt.pf ff "list(TRANSFORM %a %a" pp_var var pp_list_transform_action action;
      Option.iter selector ~f:(fun s -> pp_list_transform_selector ff s);
      Option.iter output ~f:(fun v -> Fmt.(pf ff " OUTPUT_VARIABLE %a" pp_var v));
      Fmt.pf ff ")@."

let pp_string_compare_op ff = function
  | Sco_less -> Fmt.string ff "LESS"
  | Sco_greater -> Fmt.string ff "GREATER"
  | Sco_equal -> Fmt.string ff "EQUAL"
  | Sco_notequal -> Fmt.string ff "NOTEQUAL"
  | Sco_less_equal -> Fmt.string ff "LESS_EQUAL"
  | Sco_greater_equal -> Fmt.string ff "GREATER_EQUAL"

let pp_string_cmd ff = function
  | Sc_find { string = s; substring; out; reverse } ->
      Fmt.(pf ff "string(FIND %a %a %a%s)" pp_arg s pp_arg substring
        pp_var out (if reverse then " REVERSE" else ""))
  | Sc_replace { match_string; replace_string; out; inputs } ->
      Fmt.(pf ff "string(REPLACE %a %a %a %a)" pp_arg match_string
        pp_arg replace_string pp_var out (list ~sep:sp_char pp_arg) inputs)
  | Sc_regex (Sr_match { regex; out; inputs }) ->
      (* Same %S → literal-quoted fix as D2 (file STRINGS). *)
      Fmt.(pf ff "string(REGEX MATCH %s %a %a)" (quoted regex) pp_var out
        (list ~sep:sp_char pp_arg) inputs)
  | Sc_regex (Sr_matchall { regex; out; inputs }) ->
      Fmt.(pf ff "string(REGEX MATCHALL %s %a %a)" (quoted regex) pp_var out
        (list ~sep:sp_char pp_arg) inputs)
  | Sc_regex (Sr_replace { regex; replace; out; inputs }) ->
      Fmt.(pf ff "string(REGEX REPLACE %s %a %a %a)" (quoted regex) pp_arg replace
        pp_var out (list ~sep:sp_char pp_arg) inputs)
  | Sc_regex (Sr_quote { out; inputs }) ->
      Fmt.(pf ff "string(REGEX QUOTE %a %a)" pp_var out
        (list ~sep:sp_char pp_arg) inputs)
  | Sc_toupper { string = s; out } ->
      Fmt.(pf ff "string(TOUPPER %a %a)" pp_arg s pp_var out)
  | Sc_tolower { string = s; out } ->
      Fmt.(pf ff "string(TOLOWER %a %a)" pp_arg s pp_var out)
  | Sc_length { string = s; out } ->
      Fmt.(pf ff "string(LENGTH %a %a)" pp_arg s pp_var out)
  | Sc_substring { string = s; begin_; length; out } ->
      Fmt.(pf ff "string(SUBSTRING %a %d %s %a)" pp_arg s begin_
        (match length with None -> "-1" | Some n -> Int.to_string n)
        pp_var out)
  | Sc_strip { string = s; out } ->
      Fmt.(pf ff "string(STRIP %a %a)" pp_arg s pp_var out)
  | Sc_genex_strip { string = s; out } ->
      Fmt.(pf ff "string(GENEX_STRIP %a %a)" pp_arg s pp_var out)
  | Sc_repeat { string = s; count; out } ->
      Fmt.(pf ff "string(REPEAT %a %d %a)" pp_arg s count pp_var out)
  | Sc_concat { out; inputs } ->
      Fmt.(pf ff "string(CONCAT %a %a)" pp_var out (list ~sep:sp_char pp_arg) inputs)
  | Sc_join { glue; out; inputs } ->
      Fmt.(pf ff "string(JOIN %a %a %a)" pp_arg glue pp_var out
        (list ~sep:sp_char pp_arg) inputs)
  | Sc_append { var; inputs } ->
      Fmt.(pf ff "string(APPEND %a %a)" pp_var var (list ~sep:sp_char pp_arg) inputs)
  | Sc_prepend { var; prefix = pfx; inputs } ->
      Fmt.pf ff "string(PREPEND %a %a" pp_var var pp_arg pfx;
      List.iter ~f:(fun i -> Fmt.pf ff " %a" pp_arg i) inputs;
      Fmt.string ff ")"
  | Sc_compare { op; string1; string2; out } ->
      Fmt.(pf ff "string(COMPARE %a %a %a %a)" pp_string_compare_op op
        pp_arg string1 pp_arg string2 pp_var out)
  | Sc_make_c_identifier { string = s; out } ->
      Fmt.(pf ff "string(MAKE_C_IDENTIFIER %a %a)" pp_arg s pp_var out)
  | Sc_timestamp { out; format; utc } ->
      Fmt.pf ff "string(TIMESTAMP %a" pp_var out;
      Option.iter format ~f:(fun f -> Fmt.pf ff " %s" (quoted f));
      if utc then Fmt.string ff " UTC";
      Fmt.string ff ")"
  | Sc_hex { string = s; out } ->
      Fmt.(pf ff "string(HEX %a %a)" pp_arg s pp_var out)
  | Sc_uuid { out; namespace; name; type_; upper } ->
      Fmt.pf ff "string(UUID %a NAMESPACE %s NAME %s TYPE %s%s)"
        pp_var out namespace name
        (match type_ with `Md5 -> "MD5" | `Sha1 -> "SHA1")
        (if upper then " UPPER" else "")
  | Sc_json { out; error_var; op } ->
      let pp_path ff ps =
        List.iter ~f:(fun p -> Fmt.(pf ff " %a" pp_arg p)) ps in
      Fmt.pf ff "string(JSON %a" pp_var out;
      Option.iter error_var ~f:(fun e -> Fmt.(pf ff " ERROR_VARIABLE %a" pp_var e));
      (match op with
       | Jop_get { json; path } ->
           Fmt.(pf ff " GET %a%a" pp_arg json pp_path path)
       | Jop_get_raw { json; path } ->
           Fmt.(pf ff " GET_RAW %a%a" pp_arg json pp_path path)
       | Jop_type { json; path } ->
           Fmt.(pf ff " TYPE %a%a" pp_arg json pp_path path)
       | Jop_length { json; path } ->
           Fmt.(pf ff " LENGTH %a%a" pp_arg json pp_path path)
       | Jop_member { json; path } ->
           Fmt.(pf ff " MEMBER %a%a" pp_arg json pp_path path)
       | Jop_remove { json; path } ->
           Fmt.(pf ff " REMOVE %a%a" pp_arg json pp_path path)
       | Jop_set { json; path; value } ->
           Fmt.(pf ff " SET %a%a %a" pp_arg json pp_path path pp_arg value)
       | Jop_equal { json1; json2 } ->
           Fmt.(pf ff " EQUAL %a %a" pp_arg json1 pp_arg json2)
       | Jop_string_encode { value } ->
           Fmt.(pf ff " STRING_ENCODE %a" pp_arg value));
      Fmt.string ff ")"

(* Main printers *)

let rec pp ff e =
  match e with
  (* syntactic *)
  | Int i -> Fmt.int ff i
  | Bool true -> Fmt.string ff "True"
  | Bool false -> Fmt.string ff "False"
  | Var_exp s -> Fmt.string ff s
  | Dollar e -> Fmt.pf ff "${%a}" pp e
  | Exp_list exps -> (list_br pp) ff exps
  | Quote s -> Fmt.string ff s
  (* control flow *)
  | Block { scope_policy = _; scope_var; propagate; body } ->
      let has_propagate = String.length propagate > 0 in
      let scope_str =
        if not (List.is_empty scope_var) || has_propagate then
          if has_propagate then "SCOPE_FOR VARIABLES PROPAGATE " ^ propagate
          else "SCOPE_FOR VARIABLES"
        else ""
      in
      Fmt.(
        pf ff "block(%s)@.@[<2>  %a@]@.endblock()" scope_str (list_br pp) body)
  | While { cond; commands } ->
      Fmt.(
        pf ff "while(%a)@.@[<2>  %a@]@.endwhile()" pp_cond cond pp commands)
  | Break -> Fmt.string ff "break()"
  | Continue -> Fmt.string ff "continue()"
  | Return { propogate_vars } ->
      Fmt.(
        pf ff "return(%a)"
          (pp_list_with_key "PROPAGATE" pp_var)
          propogate_vars)
  | If { cond; then_; else_ } ->
      let rec pp_if_chain ff (cond, then_, else_) =
        Fmt.(pf ff "if (%a)@.@[<2>  %a@]@." pp_cond cond pp then_;
          match else_ with
          | None -> ()
          | Some (If { cond = ec; then_ = et; else_ = ee }) ->
              pf ff "else";
              pp_if_chain ff (ec, et, ee)
          | Some e -> pf ff "else()@.@[<2>  %a@]@." pp e)
      in
      Fmt.(pp_if_chain ff (cond, then_, else_); pf ff "endif()@.")
  | Function { name; args; cmds } ->
      Fmt.(
        pf ff "function(%a %a)@.@[<2>  %a@]@.endfunction()@." pp_var name
          (list_sp string) args
          (list_br pp)
          cmds)
  | Macro { name; args; commands } ->
      Fmt.(
        pf ff "macro(%a %a)@.@[<2>  %a@]@.endmacro()@." pp_var name
          (list_sp pp_var) args pp commands)
  | Apply { name; args } ->
      Fmt.(pf ff "%a(%a)@." pp_var name (list_sp pp_arg) args)
  | Foreach { loop_var; items; commands } ->
      Fmt.pf ff "foreach(%a" pp_var loop_var;
      List.iter ~f:(fun item -> Fmt.pf ff " %a" pp_arg item) items;
      Fmt.pf ff ")@.";
      (match commands with
       | Exp_list [] -> ()
       | cmds -> Fmt.(pf ff "@[<2>  %a@]@." pp cmds));
      Fmt.string ff "endforeach()"
  | Foreach_range { loop_var; start; stop; step; commands } ->
      Fmt.(
        pf ff "foreach(%a RANGE %a%a%a)@." pp_var loop_var
          (pp_with_key "" pp_var)
          start pp_var stop
          (pp_with_key "" pp_var)
          step);
      (match commands with
       | Exp_list [] -> ()
       | cmds -> Fmt.(pf ff "@[<2>  %a@]@." pp cmds));
      Fmt.string ff "endforeach()"
  | Foreach_in { loop_var; lists; items; commands } ->
      Fmt.pf ff "foreach(%a IN" pp_var loop_var;
      if not (List.is_empty lists) then
        Fmt.(pf ff " LISTS %a" (list ~sep:sp_char pp_var) lists);
      if not (List.is_empty items) then
        Fmt.(pf ff " ITEMS %a" (list ~sep:sp_char pp_arg) items);
      Fmt.pf ff ")@.";
      (match commands with
       | Exp_list [] -> ()
       | cmds -> Fmt.(pf ff "@[<2>  %a@]@." pp cmds));
      Fmt.string ff "endforeach()"
  | Foreach_zip { loop_vars; lists; commands } ->
      Fmt.(pf ff "foreach(%a IN ZIP_LISTS %a)@."
        (list ~sep:sp_char pp_var) loop_vars
        (list ~sep:sp_char pp_var) lists);
      (match commands with
       | Exp_list [] -> ()
       | cmds -> Fmt.(pf ff "@[<2>  %a@]@." pp cmds));
      Fmt.string ff "endforeach()"
  | Include { file; optional; result_var; no_policy_scope } ->
      let pp_result_var ff = function
        | None -> ()
        | Some v -> Fmt.pf ff " RESULT_VARIABLE %s" v
      in
      Fmt.(
        pf ff "include(%a%s%a%s)" pp_arg file
          (if optional then " OPTIONAL" else "")
          pp_result_var result_var
          (if no_policy_scope then " NO_POLICY_SCOPE" else ""))
  | Include_guard { scope } ->
      Fmt.pf ff "include_guard(%a)" pp_include_guard_scope scope
  (* state *)
  | Cmake_option { var; msg; value } ->
      Fmt.(pf ff "option(%a %a %a)" pp_var var pp_message msg pp_arg value)
  | Get_cmake_property { var; property } ->
      Fmt.(pf ff "get_cmake_property(%a %a)" pp_var var string property)
  | Get_directory_property { var; directory; property } ->
      Fmt.(
        pf ff "get_directory_property(%a%a %a)" pp_var var
          (fun ff dir ->
            if String.length dir > 0 then pf ff " DIRECTORY %s" dir)
          directory string property)
  | Get_filename_component { var; filename; mode; cache } ->
      Fmt.(
        pf ff "get_filename_component(%a %a %s%a)" pp_var var string filename
          mode (pp_flag "CACHE") cache)
  | Set { var; values; parent_scope } ->
      Fmt.(
        pf ff "set(%a %a %a)" pp_var var (list_sp pp_arg) values pp_parent_scope
          parent_scope)
  | Set_cache { var; values; cache_type; docstring; force } ->
      (* cache_type is now a raw string (was enum, changed
         2026-06-03). Print verbatim — covers "STRING"/"BOOL"/etc.
         for the static path AND "${type}" for the dynamic path
         that parse_set used to reject.

         docstring: if it looks like a cmake variable reference
         (starts with "$"), emit unquoted to round-trip the source
         shape. Else emit quoted (preserves whitespace, supports
         programmatic callers that pass literal text). Same fmt-
         set_verbose() pattern that drove the cache_type fix. *)
      let pp_docstring fmt s =
        if String.length s > 0 && Char.equal s.[0] '$'
        then Fmt.string fmt s
        else Fmt.pf fmt "%S" s
      in
      Fmt.(pf ff "set(%a %a CACHE %s %a%s)"
        pp_var var (list_sp pp_arg) values cache_type
        pp_docstring docstring
        (if force then " FORCE" else ""))
  | Set_env { var; value } ->
      Fmt.(pf ff "set(ENV{%a} %a)" pp_var var pp_arg value)
  | Set_directory_properties { prop_value_pairs } ->
      Fmt.(
        pf ff "set_directory_properties(PROPERTIES %a)"
          (list_sp (pair ~sep:sp pp_var pp_arg))
          prop_value_pairs)
  | Unset { var; cache; parent_scope } ->
      Fmt.(
        pf ff "unset(%a%a%a)" pp_var var (pp_flag "CACHE") cache
          (pp_flag "PARENT_SCOPE")
          parent_scope)
  | Unset_env { var } -> Fmt.(pf ff "unset(ENV{%a})" pp_var var)
  (* property *)
  | Get_property { var; scope; property_name; mode } ->
      let pp_scope ff = function
        | Gps_global -> Fmt.string ff "GLOBAL"
        | Gps_directory None -> Fmt.string ff "DIRECTORY"
        | Gps_directory (Some d) -> Fmt.pf ff "DIRECTORY %s" d
        | Gps_target t -> Fmt.pf ff "TARGET %a" pp_target t
        | Gps_source { source; directory; target_directory } ->
            Fmt.pf ff "SOURCE %a" pp_source source;
            (match directory with
             | Some d -> Fmt.pf ff " DIRECTORY %s" d
             | None -> ());
            (match target_directory with
             | Some t -> Fmt.pf ff " TARGET_DIRECTORY %a" pp_target t
             | None -> ())
        | Gps_install f -> Fmt.pf ff "INSTALL %s" f
        | Gps_test { test; directory } ->
            Fmt.pf ff "TEST %s" test;
            (match directory with
             | Some d -> Fmt.pf ff " DIRECTORY %s" d
             | None -> ())
        | Gps_cache entry -> Fmt.pf ff "CACHE %s" entry
        | Gps_variable -> Fmt.string ff "VARIABLE"
      in
      let mode_suffix = match mode with
        | Gpm_value -> ""
        | Gpm_set -> " SET"
        | Gpm_defined -> " DEFINED"
        | Gpm_brief_docs -> " BRIEF_DOCS"
        | Gpm_full_docs -> " FULL_DOCS"
      in
      Fmt.pf ff "get_property(%a %a PROPERTY %s%s)"
        pp_var var pp_scope scope property_name mode_suffix
  | Set_property { scope; append; append_string; property; values } ->
      let pp_scope ff = function
        | Sps_global -> Fmt.string ff "GLOBAL"
        | Sps_directory None -> Fmt.string ff "DIRECTORY"
        | Sps_directory (Some d) -> Fmt.pf ff "DIRECTORY %s" d
        | Sps_target ts ->
            Fmt.pf ff "TARGET %a" (list_sp pp_target) ts
        | Sps_source { sources; directories; target_directories } ->
            Fmt.pf ff "SOURCE %a" (list_sp pp_source) sources;
            if not (List.is_empty directories) then
              Fmt.pf ff " DIRECTORY %a" (list_sp Fmt.string) directories;
            if not (List.is_empty target_directories) then
              Fmt.pf ff " TARGET_DIRECTORY %a"
                (list_sp pp_target) target_directories
        | Sps_install files ->
            Fmt.pf ff "INSTALL %a" (list_sp Fmt.string) files
        | Sps_test { tests; directories } ->
            Fmt.pf ff "TEST %a" (list_sp Fmt.string) tests;
            if not (List.is_empty directories) then
              Fmt.pf ff " DIRECTORY %a" (list_sp Fmt.string) directories
        | Sps_cache _entries ->
            (* cache_entry is currently the placeholder type Cache_entry
               with no names; emit just the keyword. *)
            Fmt.string ff "CACHE"
      in
      let pp_values ff = function
        | [] -> ()
        | vs -> Fmt.pf ff " %a" (list_sp pp_arg) vs
      in
      Fmt.pf ff "set_property(%a%s%s PROPERTY %s%a)"
        pp_scope scope
        (if append then " APPEND" else "")
        (if append_string then " APPEND_STRING" else "")
        property
        pp_values values
  | Set_directory_property { append = is_append; property; values } ->
      Fmt.(
        pf ff "set_property(DIRECTORY%s PROPERTY %s %a)"
          (if is_append then " APPEND" else "")
          property
          (list_sp pp_arg) values)
  | Set_source_property { file; property; values } ->
      Fmt.(pf ff "set_property(SOURCE %s PROPERTY %s %a)" file property (list_sp pp_arg) values)
  (* info and debug *)
  | Site_name { var } -> Fmt.(pf ff "site_name(%a)" pp_var var)
  | Variable_watch { var; command; _ } ->
      (match command with
       | None -> Fmt.(pf ff "variable_watch(%a)" pp_var var)
       | Some cmd -> Fmt.(pf ff "variable_watch(%a %s)" pp_var var cmd))
  (* list/string/math lib *)
  | List_cmd lc -> pp_list_cmd ff lc
  | String_cmd sc -> pp_string_cmd ff sc
  | Mark_as_advanced { clear; force; vars } ->
      Fmt.(
        pf ff "mark_as_advanced(%a%a%a)" (pp_flag "CLEAR") clear
          (pp_flag "FORCE") force (list_sp pp_var) vars)
  | Math_lib { var; exp; output_format } ->
      Fmt.(
        pf ff "math(EXPR %a %a OUTPUT_FORMAT %a)" pp_var var pp exp
          pp_math_output_format output_format)
  | Message { mode; texts } ->
      Fmt.(pf ff "message(%a%a)" pp_message_mode mode (list_sp pp_string_quoted) texts)
  | Message_config_log { texts } ->
      Fmt.(pf ff "message(CONFIGURE_LOG %a)" (list_sp pp_string_quoted) texts)
  | Option { var; help_text; value } ->
      Fmt.(
        pf ff "option(%a %a %a)" pp_var var
          (list_sp pp_string_quoted)
          help_text pp value)
  | Separete_arguments { var; mode = Sa_plain; _ } ->
      Fmt.(pf ff "separate_arguments(%a)" pp_var var)
  | Separete_arguments { var; mode; input = None } ->
      Fmt.(pf ff "separate_arguments(%a %a)" pp_var var pp_separate_arguments_mode mode)
  | Separete_arguments { var; mode; input = Some inp } ->
      Fmt.(pf ff "separate_arguments(%a %a %a)" pp_var var pp_separate_arguments_mode mode pp_arg inp)
  (* delegated *)
  | Cmake_cmd cmd -> (Fmt.vbox pp_cmake_cmd) ff cmd
  | Project_cmd cmd -> (Fmt.vbox pp_project_cmd) ff cmd
  | Module_cmd cmd -> (Fmt.vbox pp_module_cmd) ff cmd
  (* AST stubs — these constructors carry no fields *)
  | Execute_process { commands; working_directory; timeout; result_variable;
                      output_variable; error_variable; input_file; output_file;
                      error_file; output_quiet; error_quiet;
                      output_strip_trailing_whitespace;
                      error_strip_trailing_whitespace; command_error_is_fatal } ->
      Fmt.string ff "execute_process(";
      List.iter commands ~f:(fun cmd ->
        Fmt.string ff "\n  COMMAND";
        List.iter cmd ~f:(fun a -> Fmt.pf ff " %a" pp_arg a));
      Option.iter working_directory ~f:(fun d -> Fmt.pf ff "\n  WORKING_DIRECTORY %a" pp_arg d);
      Option.iter timeout ~f:(fun t -> Fmt.pf ff "\n  TIMEOUT %g" t);
      Option.iter result_variable ~f:(fun v -> Fmt.pf ff "\n  RESULT_VARIABLE %s" v);
      Option.iter output_variable ~f:(fun v -> Fmt.pf ff "\n  OUTPUT_VARIABLE %s" v);
      Option.iter error_variable ~f:(fun v -> Fmt.pf ff "\n  ERROR_VARIABLE %s" v);
      Option.iter input_file ~f:(fun f -> Fmt.pf ff "\n  INPUT_FILE %a" pp_arg f);
      Option.iter output_file ~f:(fun f -> Fmt.pf ff "\n  OUTPUT_FILE %a" pp_arg f);
      Option.iter error_file ~f:(fun f -> Fmt.pf ff "\n  ERROR_FILE %a" pp_arg f);
      if output_quiet then Fmt.string ff "\n  OUTPUT_QUIET";
      if error_quiet then Fmt.string ff "\n  ERROR_QUIET";
      if output_strip_trailing_whitespace then Fmt.string ff "\n  OUTPUT_STRIP_TRAILING_WHITESPACE";
      if error_strip_trailing_whitespace then Fmt.string ff "\n  ERROR_STRIP_TRAILING_WHITESPACE";
      Option.iter command_error_is_fatal ~f:(fun m -> Fmt.pf ff "\n  COMMAND_ERROR_IS_FATAL %s" m);
      Fmt.string ff ")"
  | File_relative_path { var; base; file } ->
      Fmt.(pf ff "file(RELATIVE_PATH %a %s %s)" pp_var var base file)
  | File_glob { var; recurse; relative; configure_depends; patterns } ->
      let sub = if recurse then "GLOB_RECURSE" else "GLOB" in
      Fmt.pf ff "file(%s %a" sub pp_var var;
      if configure_depends then Fmt.string ff " CONFIGURE_DEPENDS";
      Option.iter relative ~f:(fun p -> Fmt.pf ff " RELATIVE %s" p);
      List.iter patterns ~f:(fun p -> Fmt.pf ff " %a" pp_arg p);
      Fmt.string ff ")"
  | File_read { var; file; offset; limit; hex } ->
      Fmt.pf ff "file(READ %a %a" pp_arg file pp_var var;
      Option.iter offset ~f:(fun n -> Fmt.pf ff " OFFSET %d" n);
      Option.iter limit ~f:(fun n -> Fmt.pf ff " LIMIT %d" n);
      if hex then Fmt.string ff " HEX";
      Fmt.string ff ")"
  | File_write { file; append; content } ->
      let sub = if append then "APPEND" else "WRITE" in
      Fmt.pf ff "file(%s %a" sub pp_arg file;
      List.iter content ~f:(fun a -> Fmt.pf ff " %a" pp_arg a);
      Fmt.string ff ")"
  | File_strings { var; file; regex; encoding; limit_count } ->
      Fmt.pf ff "file(STRINGS %a %a" pp_arg file pp_var var;
      (* Use cmake's literal-quoting (no OCaml escape pass) so embedded
         backslashes like `[\t ]` in regexes survive the round-trip. *)
      Option.iter regex ~f:(fun r -> Fmt.pf ff " REGEX %s" (quoted r));
      Option.iter encoding ~f:(fun e -> Fmt.pf ff " ENCODING %s" e);
      Option.iter limit_count ~f:(fun n -> Fmt.pf ff " LIMIT_COUNT %d" n);
      Fmt.string ff ")"
  | File_touch { files; nocreate } ->
      let sub = if nocreate then "TOUCH_NOCREATE" else "TOUCH" in
      Fmt.pf ff "file(%s" sub;
      List.iter files ~f:(fun f -> Fmt.pf ff " %a" pp_arg f);
      Fmt.string ff ")"
  | File_make_directory { dirs } ->
      Fmt.pf ff "file(MAKE_DIRECTORY";
      List.iter dirs ~f:(fun d -> Fmt.pf ff " %a" pp_arg d);
      Fmt.string ff ")"
  | File_rename { old_; new_; result; no_replace } ->
      Fmt.pf ff "file(RENAME %a %a" pp_arg old_ pp_arg new_;
      Option.iter result ~f:(fun v -> Fmt.pf ff " RESULT %a" pp_var v);
      if no_replace then Fmt.string ff " NO_REPLACE";
      Fmt.string ff ")"
  | File_remove { files; recurse } ->
      let sub = if recurse then "REMOVE_RECURSE" else "REMOVE" in
      Fmt.pf ff "file(%s" sub;
      List.iter files ~f:(fun f -> Fmt.pf ff " %a" pp_arg f);
      Fmt.string ff ")"
  | File_copy_file { input; output; result; only_if_different } ->
      Fmt.pf ff "file(COPY_FILE %a %a" pp_arg input pp_arg output;
      Option.iter result ~f:(fun v -> Fmt.pf ff " RESULT %a" pp_var v);
      if only_if_different then Fmt.string ff " ONLY_IF_DIFFERENT";
      Fmt.string ff ")"
  | File_real_path { var; path; base_dir; expand_tilde } ->
      Fmt.pf ff "file(REAL_PATH %a %a" pp_arg path pp_var var;
      Option.iter base_dir ~f:(fun b -> Fmt.pf ff " BASE_DIRECTORY %a" pp_arg b);
      if expand_tilde then Fmt.string ff " EXPAND_TILDE";
      Fmt.string ff ")"
  | File_size { var; file } ->
      Fmt.pf ff "file(SIZE %a %a)" pp_arg file pp_var var
  | File_read_symlink { var; link } ->
      Fmt.pf ff "file(READ_SYMLINK %a %a)" pp_arg link pp_var var
  | File_timestamp { var; file; format; utc } ->
      Fmt.pf ff "file(TIMESTAMP %a %a" pp_arg file pp_var var;
      (* Same fix as File_strings.regex (D2): use literal-quoted, not
         OCaml-escaped %S, so cmake format strings round-trip. *)
      Option.iter format ~f:(fun f -> Fmt.pf ff " %s" (quoted f));
      if utc then Fmt.string ff " UTC";
      Fmt.string ff ")"
  | Find_package { name; version; exact; quiet; config_mode; required; components; optional_components } ->
      Fmt.pf ff "find_package(%s" name;
      Option.iter version ~f:(fun v -> Fmt.pf ff " %s" v);
      if exact then Fmt.string ff " EXACT";
      if quiet then Fmt.string ff " QUIET";
      if config_mode then Fmt.string ff " CONFIG";
      if required then Fmt.string ff " REQUIRED";
      if not (List.is_empty components) then
        Fmt.(pf ff " COMPONENTS %a" (list ~sep:sp_char string) components);
      if not (List.is_empty optional_components) then
        Fmt.(pf ff " OPTIONAL_COMPONENTS %a" (list ~sep:sp_char string) optional_components);
      Fmt.string ff ")"
  (* find_var commands *)
  | Find_file a -> pp_find_var ff "find_file" a
  | Find_library a -> pp_find_var ff "find_library" a
  | Find_path a -> pp_find_var ff "find_path" a
  | Find_program a -> pp_find_var ff "find_program" a

and pp_cmake_cmd ff cmd =
  match cmd with
  | Cmake_minimum_required { min; max } ->
      (match max with
       | None ->
           Fmt.pf ff "cmake_minimum_required(VERSION %s)"
             (Lang_cmake_strings.of_version min)
       | Some max ->
           Fmt.pf ff "cmake_minimum_required(VERSION %s...%s)"
             (Lang_cmake_strings.of_version min)
             (Lang_cmake_strings.of_version max))
  | Configure_file { input; output; permission_level; copy_only; escape_quotes; only; newline_style; _ } ->
      (* Pre-2026-05-15 this had @ONLY and ESCAPE_QUOTES wired to the
         wrong fields (cross-swap). Tutorial doesn't use these flags;
         llvm's docs/CMakeLists.txt surfaced it via round-trip. *)
      Fmt.(
        pf ff "configure_file(%a %a%a%a%a%a%a)" string input string output
          (pp_with_key "" pp_configure_file_permission)
          permission_level
          (pp_flag "COPYONLY")
          (Option.value ~default:false copy_only)
          (pp_flag "ESCAPE_QUOTES")
          (Option.value ~default:false escape_quotes)
          (pp_flag "@ONLY")
          (Option.value ~default:false only)
          (pp_with_key "NEWLINE_STYLE" pp_newline_style)
          newline_style)
  | Host_system_information { result = res; query } ->
      Fmt.(
        pf ff "cmake_host_system_information(RESULT %a QUERY %a)" pp_var res
          pp_query_key query)
  | Host_system_information_windows_reg
      { result = res; query; view; separator; error_var } ->
      Fmt.(
        pf ff
          "cmake_host_system_information(RESULT %a QUERY %a%a%a%a)" pp_var
          res pp_query_key query
          (pp_with_key "VIEW" pp_windows_reg_view)
          view
          (pp_with_key "SEPARATOR" string)
          separator
          (pp_with_key "ERROR_VARIABLE" pp_var)
          error_var)
  | Cmake_meta_lang meta -> pp_cmake_meta_lang ff meta
  | Cmake_parse_argument { prefix = pfx; one_keyword; multi_keyword; args } ->
      Fmt.(
        pf ff "cmake_parse_arguments(%a %a %a %a)" string pfx
          (pp_string_quoted)
          (String.concat ~sep:";" one_keyword)
          (pp_string_quoted)
          (String.concat ~sep:";" multi_keyword)
          (list_sp string) args)
  | Cmake_parse_argument_argv { n; prefix = pfx; one_keyword; multi_keyword } ->
      Fmt.(
        pf ff "cmake_parse_arguments(PARSE_ARGV %a %a %a %a)" int n string
          pfx
          (pp_string_quoted)
          (String.concat ~sep:";" one_keyword)
          (pp_string_quoted)
          (String.concat ~sep:";" multi_keyword))
  | Cmake_path cmd -> pp_cmake_path ff cmd
  | Cmake_policy_version { min; max } ->
      Fmt.(
        pf ff "cmake_policy(VERSION %a...%a)" string
          (Lang_cmake_strings.of_version min) string (Lang_cmake_strings.of_version max))
  | Cmake_policy_set { id = policy_id; new_ } ->
      Fmt.(pf ff "cmake_policy(SET %s %s)" policy_id (if new_ then "NEW" else "OLD"))
  | Cmake_policy_get { var } ->
      Fmt.(pf ff "cmake_policy(GET %a)" pp_var var)
  | Cmake_policy_push -> Fmt.string ff "cmake_policy(PUSH)"
  | Cmake_policy_pop -> Fmt.string ff "cmake_policy(POP)"

and pp_cmake_path_get_field ff = function
  | Cpf_root_name -> Fmt.string ff "ROOT_NAME"
  | Cpf_root_directory -> Fmt.string ff "ROOT_DIRECTORY"
  | Cpf_root_path -> Fmt.string ff "ROOT_PATH"
  | Cpf_filename -> Fmt.string ff "FILENAME"
  | Cpf_extension last_only ->
      Fmt.string ff (if last_only then "EXTENSION LAST_ONLY" else "EXTENSION")
  | Cpf_stem last_only ->
      Fmt.string ff (if last_only then "STEM LAST_ONLY" else "STEM")
  | Cpf_relative_part -> Fmt.string ff "RELATIVE_PART"
  | Cpf_parent_path -> Fmt.string ff "PARENT_PATH"

and pp_cmake_path_has_field ff = function
  | Cph_root_name -> Fmt.string ff "HAS_ROOT_NAME"
  | Cph_root_directory -> Fmt.string ff "HAS_ROOT_DIRECTORY"
  | Cph_root_path -> Fmt.string ff "HAS_ROOT_PATH"
  | Cph_filename -> Fmt.string ff "HAS_FILENAME"
  | Cph_extension -> Fmt.string ff "HAS_EXTENSION"
  | Cph_stem -> Fmt.string ff "HAS_STEM"
  | Cph_relative_part -> Fmt.string ff "HAS_RELATIVE_PART"
  | Cph_parent_path -> Fmt.string ff "HAS_PARENT_PATH"

and pp_cmake_path_compare_op ff = function
  | Cpco_equal -> Fmt.string ff "EQUAL"
  | Cpco_not_equal -> Fmt.string ff "NOT_EQUAL"

and pp_out_var ff = function
  | None -> ()
  | Some v -> Fmt.(pf ff " OUTPUT_VARIABLE %a" pp_var v)

and pp_cmake_path ff = function
  | Cpp_get { path_var; field = f; out_var } ->
      Fmt.(pf ff "cmake_path(GET %a %a %a)" pp_var path_var pp_cmake_path_get_field f pp_var out_var)
  | Cpp_has { path_var; field = f; out_var } ->
      Fmt.(pf ff "cmake_path(%a %a %a)" pp_cmake_path_has_field f pp_var path_var pp_var out_var)
  | Cpp_is_absolute { path_var; out_var } ->
      Fmt.(pf ff "cmake_path(IS_ABSOLUTE %a %a)" pp_var path_var pp_var out_var)
  | Cpp_is_relative { path_var; out_var } ->
      Fmt.(pf ff "cmake_path(IS_RELATIVE %a %a)" pp_var path_var pp_var out_var)
  | Cpp_is_prefix { path_var; input; normalize; out_var } ->
      Fmt.(pf ff "cmake_path(IS_PREFIX %a %a%s %a)" pp_var path_var pp_arg input
             (if normalize then " NORMALIZE" else "") pp_var out_var)
  | Cpp_compare { input1; op; input2; out_var } ->
      Fmt.(pf ff "cmake_path(COMPARE %a %a %a %a)"
             pp_arg input1 pp_cmake_path_compare_op op pp_arg input2 pp_var out_var)
  | Cpp_set { path_var; input; normalize } ->
      Fmt.(pf ff "cmake_path(SET %a%s %a)" pp_var path_var
             (if normalize then " NORMALIZE" else "") pp_arg input)
  | Cpp_append { path_var; inputs; out_var } ->
      Fmt.(pf ff "cmake_path(APPEND %a %a%a)" pp_var path_var (list_sp pp_arg) inputs pp_out_var out_var)
  | Cpp_append_string { path_var; inputs; out_var } ->
      Fmt.(pf ff "cmake_path(APPEND_STRING %a %a%a)" pp_var path_var (list_sp pp_arg) inputs pp_out_var out_var)
  | Cpp_remove_filename { path_var; out_var } ->
      Fmt.(pf ff "cmake_path(REMOVE_FILENAME %a%a)" pp_var path_var pp_out_var out_var)
  | Cpp_replace_filename { path_var; input; out_var } ->
      Fmt.(pf ff "cmake_path(REPLACE_FILENAME %a %a%a)" pp_var path_var pp_arg input pp_out_var out_var)
  | Cpp_remove_extension { path_var; last_only; out_var } ->
      Fmt.(pf ff "cmake_path(REMOVE_EXTENSION %a%s%a)" pp_var path_var
             (if last_only then " LAST_ONLY" else "") pp_out_var out_var)
  | Cpp_replace_extension { path_var; last_only; input; out_var } ->
      Fmt.(pf ff "cmake_path(REPLACE_EXTENSION %a%s %a%a)" pp_var path_var
             (if last_only then " LAST_ONLY" else "") pp_arg input pp_out_var out_var)
  | Cpp_normal_path { path_var; out_var } ->
      Fmt.(pf ff "cmake_path(NORMAL_PATH %a%a)" pp_var path_var pp_out_var out_var)
  | Cpp_relative_path { path_var; base_dir; out_var } ->
      Fmt.(pf ff "cmake_path(RELATIVE_PATH %a%a%a)" pp_var path_var
             (fun ff -> function None -> () | Some d -> pf ff " BASE_DIRECTORY %a" pp_arg d) base_dir
             pp_out_var out_var)
  | Cpp_absolute_path { path_var; base_dir; normalize; out_var } ->
      Fmt.(pf ff "cmake_path(ABSOLUTE_PATH %a%a%s%a)" pp_var path_var
             (fun ff -> function None -> () | Some d -> pf ff " BASE_DIRECTORY %a" pp_arg d) base_dir
             (if normalize then " NORMALIZE" else "") pp_out_var out_var)
  | Cpp_native_path { path_var; normalize; out_var } ->
      Fmt.(pf ff "cmake_path(NATIVE_PATH %a%s %a)" pp_var path_var
             (if normalize then " NORMALIZE" else "") pp_var out_var)
  | Cpp_convert_to_cmake { input; normalize; out_var } ->
      Fmt.(pf ff "cmake_path(CONVERT %a TO_CMAKE_PATH_LIST %a%s)" pp_arg input pp_var out_var
             (if normalize then " NORMALIZE" else ""))
  | Cpp_convert_to_native { input; normalize; out_var } ->
      Fmt.(pf ff "cmake_path(CONVERT %a TO_NATIVE_PATH_LIST %a%s)" pp_arg input pp_var out_var
             (if normalize then " NORMALIZE" else ""))
  | Cpp_hash { path_var; out_var } ->
      Fmt.(pf ff "cmake_path(HASH %a %a)" pp_var path_var pp_var out_var)

and pp_cmake_meta_lang ff = function
  | Meta_call { cmd; arg } ->
      Fmt.(
        pf ff "cmake_language(CALL %a %a)" pp cmd (list_sp pp) arg)
  | Meta_eval { code } ->
      Fmt.(pf ff "cmake_language(EVAL CODE %S)" code)
  | Meta_defer_call { dir; id = id_; var } ->
      Fmt.(
        pf ff "cmake_language(DEFER%a%a ID_VAR %a)"
          (fun ff d ->
            if String.length d > 0 then pf ff " DIRECTORY %s" d)
          dir
          (fun ff i ->
            if String.length i > 0 then pf ff " ID %s" i)
          id_ pp_var var)
  | Meta_defer_call_ids { dir; var } ->
      Fmt.(
        pf ff "cmake_language(DEFER%a GET_CALL_IDS %a)"
          (fun ff d ->
            if String.length d > 0 then pf ff " DIRECTORY %s" d)
          dir pp_var var)
  | Meta_defer_cancel { dir; id = id_ } ->
      Fmt.(
        pf ff "cmake_language(DEFER%a CANCEL_CALL %a)"
          (fun ff d ->
            if String.length d > 0 then pf ff " DIRECTORY %s" d)
          dir string id_)
  | Meta_set_dep_provider { var; dp_cmd } ->
      Fmt.(
        pf ff "cmake_language(SET_DEPENDENCY_PROVIDER %a SUPPORTED_METHODS %a)"
          pp_var var pp_dep_provider_cmd dp_cmd)
  | Meta_get_msg_log_level { var } ->
      Fmt.(pf ff "cmake_language(GET_MESSAGE_LOG_LEVEL %a)" pp_var var)
  | Meta_exit { exit_code } ->
      Fmt.(pf ff "cmake_language(EXIT %a)" int exit_code)

and pp_project_cmd ff cmd =
  match cmd with
  | Project { name; version; description; homepage_url; languages } ->
      Fmt.(
        pf ff "project(%a %a%a%a%a)" string name pp_version_opt version
          (pp_with_key "DESCRIPTION" pp_string_quoted)
          description
          (pp_with_key "HOMEPAGE_URL" pp_string_quoted)
          homepage_url
          (pp_list_with_key "LANGUAGES" string)
          languages)
  | Add_executable { name; options; sources } ->
      let option_str o = match o with
        | Ae_win32 -> "WIN32" | Ae_macos_bundle -> "MACOSX_BUNDLE"
        | Ae_exclude_from_all -> "EXCLUDE_FROM_ALL"
      in
      let opts_str = match options with
        | [] -> ""
        | _ -> " " ^ String.concat ~sep:" " (List.map ~f:option_str options)
      in
      Fmt.(pf ff "add_executable(%a%s %a)" string name opts_str (list_sp pp_source) sources)
  | Add_executable_imported { name; global } ->
      Fmt.(
        pf ff "add_executable(%a IMPORTED%a)" string name (pp_flag "GLOBAL")
          global)
  | Add_executable_alias { name; target } ->
      Fmt.(pf ff "add_executable(%a ALIAS %a)" string name pp_target target)
  | Add_subdirectory { source_dir; binary_dir; exclude_from_all; system } ->
      Fmt.(
        pf ff "add_subdirectory(%a%a%a%a)" string source_dir
          (pp_with_key "" string)
          binary_dir
          (pp_flag "EXCLUDE_FROM_ALL")
          exclude_from_all (pp_flag "SYSTEM") system)
  | Add_library { name; sources; type_; exclude_from_all } ->
      Fmt.(
        pf ff "add_library(%a %a%a %a)" string name (option string) type_
          (pp_flag "EXCLUDE_FROM_ALL")
          exclude_from_all (list_sp pp_source) sources)
  | Add_library_imported { name; lib_type; global } ->
      Fmt.(
        pf ff "add_library(%a%a IMPORTED%s)" string name
          (option (fun ff t -> pf ff " %s" t))
          lib_type
          (if global then " GLOBAL" else ""))
  | Add_library_object { name; sources } ->
      Fmt.(
        pf ff "add_library(%a OBJECT %a)" string name (list_sp pp_source)
          sources)
  | Add_library_interface { name } ->
      Fmt.(pf ff "add_library(%a INTERFACE)" string name)
  | Add_library_alias { name; target } ->
      Fmt.(pf ff "add_library(%a ALIAS %a)" string name pp_target target)
  (* target *)
  | Target_compile_definitions { target; items } ->
      Fmt.(
        pf ff "target_compile_definitions(%a %a)" pp_target target
          (list_sp pp_args_with_kind)
          items)
  | Target_compile_features { target; features } ->
      Fmt.(
        pf ff "target_compile_features(%a %a)" pp_target target
          (list_sp pp_target_feature)
          features)
  | Target_compile_options { target; items; before } ->
      Fmt.(
        pf ff "target_compile_options(%a%s@[<2>%a@])" pp_target target
          (if before then "BEFORE" else " ")
          (list_sp pp_args_with_kind)
          items)
  | Target_link_libraries { targets; items } ->
      Fmt.(
        pf ff "target_link_libraries(%a %a)" (list_sp pp_target) targets
          (list_sp pp_args_with_kind)
          items)
  | Target_include_directories { target; items; system; before_or_after } ->
      Fmt.(
        pf ff "target_include_directories(%a%a%a @[<2>%a@])" pp_target target
          (pp_flag "SYSTEM")
          (Option.value ~default:false system)
          (pp_with_key "" pp_before_or_after)
          before_or_after
          (list_sp pp_args_with_kind)
          items)
  | Target_link_directories { target; before; items } ->
      Fmt.(
        pf ff "target_link_directories(%a%s@[<2>%a@])" pp_target target
          (if before then " BEFORE " else " ")
          (list_sp pp_args_with_kind)
          items)
  | Target_link_options { target; before; items } ->
      Fmt.(
        pf ff "target_link_options(%a%s@[<2>%a@])" pp_target target
          (if before then " BEFORE " else " ")
          (list_sp pp_args_with_kind)
          items)
  | Target_precompile_headers { target; items } ->
      Fmt.(
        pf ff "target_precompile_headers(%a %a)" pp_target target
          (list_sp pp_args_with_kind)
          items)
  | Target_sources { target; items } ->
      Fmt.(
        pf ff "target_sources(%a %a)" pp_target target
          (list_sp pp_args_with_kind)
          items)
  | Target_sources_file_set { target; items } ->
      Fmt.(
        pf ff "target_sources(%a %a)" pp_target target
          (list_sp pp_target_sources_item)
          items)
  (* custom *)
  | Add_custom_command { outputs; commands; depends; main_dependency;
                         working_directory; comment; verbatim;
                         uses_terminal; append = is_append; _ } ->
      Fmt.(
        pf ff "add_custom_command(OUTPUT %a@;COMMAND %a@.%a%a%a%a%a%a%a)@."
          (list_sp string) outputs
          (list_sp pp_custom_command) commands
          (pp_list_with_key "DEPENDS" string) depends
          (pp_with_key "MAIN_DEPENDENCY" string) main_dependency
          (pp_with_key "WORKING_DIRECTORY" string) working_directory
          (pp_with_key "COMMENT" pp_string_quoted) comment
          (pp_flag "VERBATIM") verbatim
          (pp_flag "USES_TERMINAL") uses_terminal
          (pp_flag "APPEND") is_append)
  | Add_custom_command_target { target; when_; commands; comment; verbatim; uses_terminal } ->
      let when_s = match when_ with
        | Cw_pre_build -> "PRE_BUILD" | Cw_pre_link -> "PRE_LINK" | Cw_post_build -> "POST_BUILD"
      in
      Fmt.(
        pf ff "add_custom_command(TARGET %a %s @;%a%a%a%a)@."
          pp_target target when_s
          (pp_list_with_key "COMMAND" pp_custom_command) commands
          (pp_with_key "COMMENT" pp_string_quoted) comment
          (pp_flag "VERBATIM") verbatim
          (pp_flag "USES_TERMINAL") uses_terminal)
  | Add_custom_target
      { name; all; commands; depends; working_directory; comment;
        verbatim; uses_terminal; sources; _ } ->
      (* cmake's add_custom_target allows multiple COMMAND blocks; each
         must be emitted with its own COMMAND keyword. Using
         pp_list_with_key here would merge them all under a single
         keyword. *)
      let pp_commands ff cs =
        List.iter cs ~f:(fun c ->
          Fmt.pf ff " COMMAND %a" pp_custom_command c)
      in
      Fmt.(
        pf ff "add_custom_target(%s%a%a%a%a%a%a%a%a)" name
          (pp_flag "ALL") all
          pp_commands commands
          (pp_list_with_key " DEPENDS" string) depends
          (pp_with_key " WORKING_DIRECTORY" string) working_directory
          (* COMMENT is conventionally a multi-word quoted string;
             cmake-the-parser would tokenize unquoted as separate args. *)
          (pp_with_key " COMMENT" pp_string_quoted) comment
          (pp_flag "VERBATIM") verbatim
          (pp_flag "USES_TERMINAL") uses_terminal
          (pp_list_with_key " SOURCES" string) sources)
  (* property *)
  | Get_source_file_property { var; file; property } ->
      Fmt.(
        pf ff "get_source_file_property(%a %a %a)" pp_var var string file
          pp_property property)
  | Set_source_files_properties { files; directories; target_directories } ->
      Fmt.(
        pf ff "set_source_files_properties(%a%a%a)"
          (list_sp string) files
          (pp_list_with_key "DIRECTORY" string) directories
          (pp_list_with_key "TARGET_DIRECTORY" pp_target) target_directories)
  | Get_target_property { var; target; property = { prop; _ } } ->
      Fmt.(pf ff "get_target_property(%a %a %s)" pp_var var pp_target target prop)
  | Set_target_properties { targets; properties } ->
      Fmt.(
        pf ff "set_target_properties(%a PROPERTIES %a)"
          (list_sp pp_target) targets
          (list_sp pp_property) properties)
  | Enable_testing -> Fmt.(pf ff "enable_testing()")
  | Add_test { name; command; args; dir } ->
      Fmt.(
        pf ff "add_test(NAME %a COMMAND %a %a%a)" string name string command
          (list_sp string) args
          (pp_with_key "WORKING_DIRECTORY" string)
          dir)
  | Get_test_property { test; property; directory; var } ->
      Fmt.(
        pf ff "get_test_property(%a %a%a %a)" string test pp_property property
          (pp_with_key "DIRECTORY" string)
          directory pp_var var)
  | Set_tests_properties { tests; dir; properties } ->
      Fmt.(
        pf ff "set_tests_properties(%a%a PROPERTIES %a)" (list_sp string) tests
          (pp_with_key "WORKING_DIRECTORY" string)
          dir (list_sp pp_property) properties)
  | Define_property
      { mode; property_name; inherited; brief_docs; full_docs; initialize_from }
    ->
      Fmt.(
        pf ff "define_property(%a@;PROPERTY %a%a%a%a%a)" pp_define_property_mode
          mode string property_name (pp_flag "INHERITED") inherited
          (pp_list_with_key " BRIEF_DOCS" pp_string_quoted)
          brief_docs
          (pp_list_with_key " FULL_DOCS" pp_string_quoted)
          full_docs
          (fun ff v ->
            if String.length v > 0 then
              pf ff "@;INITIALIZE_FROM_VARIABLE %s" v)
          initialize_from)
  (* compile/link *)
  | Add_compile_definitions { defs } ->
      Fmt.(pf ff "add_compile_definitions(%a)" (list_sp pp_definition) defs)
  | Add_compile_options { options_ } ->
      Fmt.(pf ff "add_compile_options(%a)" (list_sp string) options_)
  | Add_definitions { defs } ->
      Fmt.(pf ff "add_definitions(%a)" (list_sp pp_definition) defs)
  | Remove_definitions { defs } ->
      Fmt.(pf ff "remove_definitions(%a)" (list_sp pp_definition) defs)
  | Add_dependencies { target; deps } ->
      Fmt.(pf ff "add_dependencies(%a %a)"
             pp_target target (list_sp string) deps)
  | Add_link_options { options } ->
      Fmt.(pf ff "add_link_options(%a)" (list_sp string) options)
  (* include *)
  | Include_directories { before_or_after; system; dir; dirs } ->
      Fmt.(
        pf ff "include_directories(%a%a %a %a)" pp_before_or_after
          before_or_after (pp_flag "SYSTEM") system string dir
          (list_sp string) dirs)
  | Include_external_msproject
      { projectname; location; type_; guid; platform; deps } ->
      Fmt.(
        pf ff "include_external_msproject(%a %a%a%a%a%a)" string projectname
          string location
          (pp_with_key "TYPE" string)
          type_
          (pp_with_key "GUID" string)
          guid
          (pp_with_key "PLATFORM" string)
          platform
          (pp_list_with_key "" string)
          deps)
  | Include_regular_expression { regex_match; regex_complain } ->
      Fmt.(
        pf ff "include_regular_expression(%a%a)" string regex_match
          (pp_with_key "" string)
          regex_complain)
  (* link *)
  | Link_directories { before_or_after; directory; directories } ->
      let kw_pfx = match before_or_after with
        | Default_order -> ""
        | ba -> string_of_before_or_after ba ^ " "
      in
      Fmt.(pf ff "link_directories(%s%s %a)" kw_pfx directory (list_sp string) directories)
  | Link_libraries { groups } ->
      Fmt.(pf ff "link_libraries(%a)" (list_sp pp_link_library_group) groups)
  (* export *)
  | Export_targets { targets } ->
      Fmt.(pf ff "export(TARGETS %a)" (list_sp pp_target) targets)
  | Export_export { name; file } ->
      Fmt.(
        pf ff "export(EXPORT %a@;%a)" string name
          (pp_with_key "FILE" pp_arg)
          file)
  | Export_package { name } ->
      Fmt.(pf ff "export(PACKAGE %a)" string name)
  | Export_setup { name } ->
      Fmt.(pf ff "export(SETUP %a)" string name)
  (* install *)
  | Install_targets { targets; destination; artifact_clauses; export; _ } ->
      let pp_kind ff = function
        | Iak_archive -> Fmt.string ff "ARCHIVE"
        | Iak_library -> Fmt.string ff "LIBRARY"
        | Iak_runtime -> Fmt.string ff "RUNTIME"
        | Iak_objects -> Fmt.string ff "OBJECTS"
        | Iak_framework -> Fmt.string ff "FRAMEWORK"
        | Iak_bundle -> Fmt.string ff "BUNDLE"
        | Iak_public_header -> Fmt.string ff "PUBLIC_HEADER"
        | Iak_private_header -> Fmt.string ff "PRIVATE_HEADER"
        | Iak_resource -> Fmt.string ff "RESOURCE"
        | Iak_file_set n -> Fmt.pf ff "FILE_SET %s" n
        | Iak_cxx_modules_bmi -> Fmt.string ff "CXX_MODULES_BMI"
      in
      let pp_clause ff { kind; destination = d } =
        Fmt.pf ff " %a" pp_kind kind;
        Option.iter d ~f:(fun a -> Fmt.pf ff " DESTINATION %a" pp_arg a)
      in
      Fmt.pf ff "install(TARGETS %a"
        (list_sp pp_target) targets;
      Option.iter export ~f:(fun e -> Fmt.pf ff " EXPORT %s" e);
      List.iter artifact_clauses ~f:(pp_clause ff);
      Option.iter destination ~f:(fun a ->
        Fmt.pf ff " DESTINATION %a" pp_arg a);
      Fmt.string ff ")"
  | Install_files { files; destination; _ } ->
      Fmt.(
        pf ff "install(FILES %a@[<2>@;DESTINATION %a@])" (list_sp pp_arg) files
          pp_arg destination)
  | Install_export { file; export; destination; namespace; _ } ->
      Fmt.(
        pf ff "install(EXPORT %a@[<2>@;%a@;DESTINATION %a%a@])" pp_arg export
          (pp_with_key "FILE" pp_arg)
          file pp_arg destination
          (pp_with_key "NAMESPACE" string) namespace)
  (* misc *)
  | Aux_source_directory { dir; var } ->
      Fmt.(pf ff "aux_source_directory(%a %a)" string dir pp_var var)
  | Build_command { var; configuration; parallel_level; target; project_name } ->
      Fmt.(
        pf ff "build_command(%a%a%a%a%a)" pp_var var
          (pp_with_key "CONFIGURATION" string)
          configuration
          (pp_with_key "PARALLEL_LEVEL" int)
          parallel_level
          (pp_with_key "TARGET" pp_target)
          target
          (pp_with_key "PROJECT_NAME" string)
          project_name)
  | Cmake_file_api { api_version; code_model } ->
      Fmt.(
        pf ff "cmake_file_api(QUERY API_VERSION %a CODEMODEL %a)" string
          (Lang_cmake_strings.of_version api_version)
          (list_sp (Fmt.using Lang_cmake_strings.of_version string))
          code_model)
  | Create_test_sourcelist { name; drive_name; tests; options; extra_include; function_ } ->
      Fmt.(
        pf ff "create_test_sourcelist(%a %a %a%a%a%a)" string name string
          drive_name (list_sp string) tests
          (pp_list_with_key "" string) options
          (fun ff s ->
            if String.length s > 0 then pf ff " EXTRA_INCLUDE %s" s)
          extra_include
          (fun ff s ->
            if String.length s > 0 then pf ff " FUNCTION %s" s)
          function_)
  | Enable_language { langs; optional } ->
      Fmt.(
        pf ff "enable_language(%a%a)" (list_sp string) langs
          (pp_flag "OPTIONAL")
          optional)
  | Fltk_wrap_ui { resulting_library_name; sources } ->
      Fmt.(
        pf ff "fltk_wrap_ui(%a %a)" string resulting_library_name
          (list_sp pp_source) sources)
  | Load_cache_read { directory; prefix = pfx; entries } ->
      Fmt.(
        pf ff "load_cache(%a READ_WITH_PREFIX %a %a)" string directory string
          pfx (list_sp string) entries)
  | Load_cache { directory; exclude; include_internals } ->
      Fmt.(
        pf ff "load_cache(%a%a%a)" string directory
          (pp_list_with_key "EXCLUDE" string)
          exclude
          (pp_list_with_key "INCLUDE_INTERNALS" string)
          include_internals)
  | Source_group { name; files; regular_exp } ->
      Fmt.(
        pf ff "source_group(%a%a%a)" pp_string_quoted name
          (pp_list_with_key "FILES" string) files
          (fun ff s ->
            if String.length s > 0 then pf ff " REGULAR_EXPRESSION %s" s)
          regular_exp)
  | Source_group_tree { root; prefix = pfx; files } ->
      Fmt.(
        pf ff "source_group(TREE %a%a%a)" string root
          (fun ff s ->
            if String.length s > 0 then pf ff " PREFIX %s" s)
          pfx
          (pp_list_with_key "FILES" string)
          files)
  | Try_compile {
      tc_result_var; tc_bindir; tc_sources; tc_compile_definitions;
      tc_link_libraries; tc_link_options; tc_cmake_flags;
      tc_output_variable; tc_copy_file; tc_no_cache;
      tc_c_standard; tc_cxx_standard } ->
    Fmt.(pf ff "try_compile(%a" pp_var tc_result_var);
    (match tc_bindir with
     | None -> ()
     | Some a -> Fmt.(pf ff " %a" pp_arg a));
    Fmt.pf ff " ";
    pp_list_with_key "SOURCES" pp_arg ff tc_sources;
    if not (List.is_empty tc_compile_definitions) then
      pp_list_with_key "COMPILE_DEFINITIONS" pp_arg ff tc_compile_definitions;
    if not (List.is_empty tc_link_libraries) then
      pp_list_with_key "LINK_LIBRARIES" pp_arg ff tc_link_libraries;
    if not (List.is_empty tc_link_options) then
      pp_list_with_key "LINK_OPTIONS" pp_arg ff tc_link_options;
    if not (List.is_empty tc_cmake_flags) then
      pp_list_with_key "CMAKE_FLAGS" pp_arg ff tc_cmake_flags;
    (match tc_output_variable with
     | None -> () | Some v -> Fmt.(pf ff " OUTPUT_VARIABLE %a" pp_var v));
    (match tc_copy_file with
     | None -> () | Some a -> Fmt.(pf ff " COPY_FILE %a" pp_arg a));
    (match tc_c_standard with
     | None -> () | Some s -> Fmt.pf ff " C_STANDARD %s" s);
    (match tc_cxx_standard with
     | None -> () | Some s -> Fmt.pf ff " CXX_STANDARD %s" s);
    if tc_no_cache then Fmt.pf ff " NO_CACHE";
    Fmt.string ff ")"
  | Try_run {
      tr_run_result_var; tr_compile_result_var; tr_sources;
      tr_compile_definitions; tr_link_libraries;
      tr_compile_output_variable; tr_run_output_variable; tr_args } ->
    Fmt.(pf ff "try_run(%a %a " pp_var tr_run_result_var pp_var tr_compile_result_var);
    pp_list_with_key "SOURCES" pp_arg ff tr_sources;
    if not (List.is_empty tr_compile_definitions) then
      pp_list_with_key "COMPILE_DEFINITIONS" pp_arg ff tr_compile_definitions;
    if not (List.is_empty tr_link_libraries) then
      pp_list_with_key "LINK_LIBRARIES" pp_arg ff tr_link_libraries;
    (match tr_compile_output_variable with
     | None -> () | Some v -> Fmt.(pf ff " COMPILE_OUTPUT_VARIABLE %a" pp_var v));
    (match tr_run_output_variable with
     | None -> () | Some v -> Fmt.(pf ff " RUN_OUTPUT_VARIABLE %a" pp_var v));
    if not (List.is_empty tr_args) then pp_list_with_key "ARGS" pp_arg ff tr_args;
    Fmt.string ff ")"

and pp_module_cmd ff = function
  | Configure_package_config_file
      {
        input;
        output;
        install_dest;
        path_vars;
        no_set_and_check_macro;
        no_check_required_components_macro;
      } ->
      Fmt.(
        pf ff
          "configure_package_config_file(%a@;%a@;INSTALL_DESTINATION %a%a%a%a)"
          pp_arg input pp_arg output pp_arg install_dest
          (pp_list_with_key "PATH_VARS " pp_var)
          path_vars
          (pp_flag "NO_SET_AND_CHECK_MACRO")
          no_set_and_check_macro
          (pp_flag "NO_CHECK_REQUIRED_COMPONENTS_MACRO")
          no_check_required_components_macro)
  | Write_basic_package_version_file
      { file; version; compatibility; arch_independent } ->
      Fmt.(
        pf ff "write_basic_package_version_file(%a@;%a@;COMPATIBILITY %a@;%a)"
          pp_arg file
          (pp_with_key "VERSION" pp_arg)
          version Fmt.string compatibility
          (pp_flag "ARCH_INDEPENDENT")
          arch_independent)
