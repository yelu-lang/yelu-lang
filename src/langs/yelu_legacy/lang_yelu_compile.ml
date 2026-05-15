open Base
open Lang_yelu_cmake

let stage = Lang_yelu_type.Stage_lower

(* Type erasure: yelu_ast -> cmake_ast, with scope checking *)

(* --- Environment --- *)

type env = {
  cvars : Set.M(String).t;
  targets : Set.M(String).t;
  bindings : yelu_expr Map.M(String).t;
}

let empty_env =
  {
    cvars = Set.empty (module String);
    targets = Set.empty (module String);
    bindings = Map.empty (module String);
  }

let ycs_to_s = function
  | Ycs_path s | Ycs_keyword s | Ycs_string s | Ycs_eval s -> s

let is_builtin_cvar s =
  String.is_prefix s ~prefix:"CMAKE_"
  || String.is_prefix s ~prefix:"PROJECT_"
  || String.is_prefix s ~prefix:"CPACK_"
  || String.is_prefix s ~prefix:"CTEST_"
  || String.is_prefix s ~prefix:"BUILD_"

let warn_undeclared_cvar env ({ name; _ } : tc_name) =
  if not (Set.mem env.cvars name || is_builtin_cvar name
          || String.is_substring name ~substring:"${") then
    Fmt.epr "Warning: undeclared variable '%s'@." name

let warn_undeclared_target env ({ name; _ } : tc_name) =
  if not (Set.mem env.targets name) then
    Fmt.epr "Warning: undeclared target '%s'@." name

let declare_cvar env ({ name; _ } : tc_name) =
  { env with cvars = Set.add env.cvars name }

let declare_target env ({ name; _ } : tc_name) =
  { env with targets = Set.add env.targets name }

(* --- Variable resolution --- *)

let rec resolve_arg env = function
  | Yexpr_var (Yvar name) ->
      (match Map.find env.bindings name with
       | Some v -> resolve_arg env v
       | None -> Fmt.epr "Warning: unbound variable '%s'@." name; Yexpr_string (Ycs_string name))
  | other -> other

let try_declare_target env arg =
  match resolve_arg env arg with
  | Yexpr_name ({ ns = Ns_target; _ } as t) -> declare_target env t
  | _ -> env

let try_declare_cvar env arg =
  match resolve_arg env arg with
  | Yexpr_name ({ ns = Ns_var; _ } as v) -> declare_cvar env v
  | _ -> env

(* --- Erasure helpers --- *)

let erase_cvar ({ name; _ } : tc_name) = name

let cv_name ({ name; _ } : tc_name) = name

let rec erase_arg env = function
  | Yexpr_var (Yvar name) ->
      (match Map.find env.bindings name with
       | Some v -> erase_arg env v
       | None -> Lang_cmake.Bare name)
  | Yexpr_name { name; _ } -> Lang_cmake.Bare name
  | Yexpr_string (Ycs_eval s) ->
      let known_dirs =
        [ "PROJECT_BINARY_DIR"; "PROJECT_SOURCE_DIR";
          "CMAKE_CURRENT_BINARY_DIR"; "CMAKE_CURRENT_SOURCE_DIR";
          "CMAKE_CURRENT_LIST_DIR" ]
      in
      List.iter known_dirs ~f:(fun var ->
          if String.equal s (Fmt.str "${%s}" var) then
            Fmt.epr "Hint: use typed primitive instead of yraw \"${%s}\"@." var);
      (* Bracket strings [=[...]=] must not be double-quoted; pass as Bare.
         All other raw strings are passed Quoted so cmake treats them as
         single tokens. *)
      if String.is_prefix s ~prefix:"[" then Lang_cmake.Bare s
      else Lang_cmake.Quoted s
  | Yexpr_string (Ycs_string s) ->
    (* Empty string must be Quoted so cmake sees "" rather than nothing.
       Strings with whitespace must be Quoted — unquoted whitespace splits args.
       Strings containing "$<" must be Quoted so cmake does not evaluate them
       as generator expressions. *)
    if String.is_empty s
    || String.exists s ~f:Char.is_whitespace
    || String.is_substring s ~substring:"$<"
    || String.exists s ~f:(Char.equal '\\')
    then Lang_cmake.Quoted s
    else Lang_cmake.Bare s
  | Yexpr_string ycs -> Lang_cmake.Bare (ycs_to_s ycs)
  | Yexpr_bool b -> Lang_cmake.Bare (if b then "ON" else "OFF")
  | _ -> Lang_cmake.Bare ""

(* For cmake fields that expect plain string, not arg *)
let rec erase_arg_s env = function
  | Yexpr_var (Yvar name) ->
      (match Map.find env.bindings name with
       | Some v -> erase_arg_s env v
       | None -> name)
  | Yexpr_name { name; _ } -> name
  | Yexpr_string ycs -> ycs_to_s ycs
  | Yexpr_bool b -> if b then "ON" else "OFF"
  | _ -> ""

let string_of_kind = function
  | Interface -> "INTERFACE"
  | Public -> "PUBLIC"
  | Private -> "PRIVATE"
  | Plain -> ""

let string_of_library_type = function
  | Lib_static -> "STATIC"
  | Lib_shared -> "SHARED"
  | Lib_module -> "MODULE"
  | Lib_unknown -> "UNKNOWN"
  | Lib_object -> "OBJECT"
  | Lib_interface -> "INTERFACE"
  | Lib_global -> "GLOBAL"

(* supported_lang / compatibility string conversions now live in
   [Lang_cmake_strings]; callers below use the module form. *)

let erase_items_with_kind env { kind; items } : Lang_cmake.items_with_kind =
  { kind = string_of_kind kind; items = List.map ~f:(erase_arg env) items }

let erase_target_feature ({ kind; feature } : yelu_target_feature) :
    Lang_cmake.target_feature =
  { kind = string_of_kind kind; feature }

(* Quote a string for use as a cmake if() condition operand.
   - Empty strings would disappear unquoted, becoming no argument.
   - Strings with semicolons are split into multiple tokens by cmake.
   - Strings with whitespace are split into multiple tokens by cmake.
   - Variable expansions "${VAR}" need quoting so the expanded value is
     treated as a single string even when it contains semicolons (i.e. a list). *)
let cmake_quote_cond s =
  if String.is_empty s
  || String.exists s ~f:(Char.equal ';')
  || String.exists s ~f:Char.is_whitespace
  || String.is_substring s ~substring:"${"
  || String.exists s ~f:(Char.equal '(')
  || String.exists s ~f:(Char.equal ')')
  then Fmt.str "\"%s\"" s
  else s

let rec erase_bool env : yelu_expr -> string list = function
  | Yexpr_not c -> "NOT" :: erase_bool env c
  | Yexpr_and (a, b) -> [ "(" ] @ erase_bool env a @ [ "AND" ] @ erase_bool env b @ [ ")" ]
  | Yexpr_or (a, b) -> [ "(" ] @ erase_bool env a @ [ "OR" ] @ erase_bool env b @ [ ")" ]
  | Yexpr_is_target { name; _ } -> [ "TARGET"; name ]
  | Yexpr_is_defined { name; _ } -> [ "DEFINED"; name ]
  | Yexpr_str_equal (a, b) ->
    [ cmake_quote_cond (erase_arg_s env a); "STREQUAL";       cmake_quote_cond (erase_arg_s env b) ]
  | Yexpr_str_less (a, b) ->
    [ cmake_quote_cond (erase_arg_s env a); "STRLESS";        cmake_quote_cond (erase_arg_s env b) ]
  | Yexpr_str_greater (a, b) ->
    [ cmake_quote_cond (erase_arg_s env a); "STRGREATER";     cmake_quote_cond (erase_arg_s env b) ]
  | Yexpr_str_less_eq (a, b) ->
    [ cmake_quote_cond (erase_arg_s env a); "STRLESS_EQUAL";  cmake_quote_cond (erase_arg_s env b) ]
  | Yexpr_str_greater_eq (a, b) ->
    [ cmake_quote_cond (erase_arg_s env a); "STRGREATER_EQUAL"; cmake_quote_cond (erase_arg_s env b) ]
  | Yexpr_equal (a, b) ->
    [ cmake_quote_cond (erase_arg_s env a); "EQUAL";          cmake_quote_cond (erase_arg_s env b) ]
  | Yexpr_less (a, b) ->
    [ cmake_quote_cond (erase_arg_s env a); "LESS";           cmake_quote_cond (erase_arg_s env b) ]
  | Yexpr_greater (a, b) ->
    [ cmake_quote_cond (erase_arg_s env a); "GREATER";        cmake_quote_cond (erase_arg_s env b) ]
  | Yexpr_less_eq (a, b) ->
    [ cmake_quote_cond (erase_arg_s env a); "LESS_EQUAL";     cmake_quote_cond (erase_arg_s env b) ]
  | Yexpr_greater_eq (a, b) ->
    [ cmake_quote_cond (erase_arg_s env a); "GREATER_EQUAL";  cmake_quote_cond (erase_arg_s env b) ]
  | Yexpr_in_list (value, listvar) ->
    [ cmake_quote_cond (erase_arg_s env value);
      "IN_LIST";
      erase_arg_s env listvar ]
  | Yexpr_matches (value, regex) ->
    [ cmake_quote_cond (erase_arg_s env value); "MATCHES"; cmake_quote_cond regex ]
  | Yexpr_exists path ->
    [ "EXISTS"; cmake_quote_cond (erase_arg_s env path) ]
  | Yexpr_is_directory path ->
    [ "IS_DIRECTORY"; cmake_quote_cond (erase_arg_s env path) ]
  | Yexpr_is_absolute path ->
    [ "IS_ABSOLUTE"; cmake_quote_cond (erase_arg_s env path) ]
  | Yexpr_policy p -> [ "POLICY"; p ]
  | Yexpr_ver_less (a, b) ->
    [ cmake_quote_cond (erase_arg_s env a); "VERSION_LESS"; cmake_quote_cond (erase_arg_s env b) ]
  | Yexpr_ver_greater (a, b) ->
    [ cmake_quote_cond (erase_arg_s env a); "VERSION_GREATER"; cmake_quote_cond (erase_arg_s env b) ]
  | Yexpr_ver_equal (a, b) ->
    [ cmake_quote_cond (erase_arg_s env a); "VERSION_EQUAL"; cmake_quote_cond (erase_arg_s env b) ]
  | Yexpr_ver_less_eq (a, b) ->
    [ cmake_quote_cond (erase_arg_s env a); "VERSION_LESS_EQUAL"; cmake_quote_cond (erase_arg_s env b) ]
  | Yexpr_ver_greater_eq (a, b) ->
    [ cmake_quote_cond (erase_arg_s env a); "VERSION_GREATER_EQUAL"; cmake_quote_cond (erase_arg_s env b) ]
  (* simple expressions used as truthy: bool lit, name, string, var *)
  | e -> [ erase_arg_s env e ]

let erase_property env (prop, value) : Lang_cmake.property =
  { prop; value = erase_arg env value }

(* --- Scope checking --- *)

let rec check_arg env = function
  | Yexpr_var (Yvar name) ->
      (match Map.find env.bindings name with
       | Some v -> check_arg env v
       | None -> Fmt.epr "Warning: unbound variable '%s'@." name)
  | Yexpr_name ({ ns = Ns_var; _ } as v) -> warn_undeclared_cvar env v
  | Yexpr_name ({ ns = Ns_target; _ } as t) -> warn_undeclared_target env t
  | Yexpr_name _ -> ()
  | Yexpr_string _ | Yexpr_bool _ -> ()
  | _ -> ()

let rec check_bool env = function
  | Yexpr_not c -> check_bool env c
  | Yexpr_and (a, b) | Yexpr_or (a, b) ->
      check_bool env a; check_bool env b
  | Yexpr_is_target _ -> ()
  | Yexpr_is_defined _ -> ()
  | Yexpr_str_equal (a, b) | Yexpr_str_less (a, b) | Yexpr_str_greater (a, b)
  | Yexpr_str_less_eq (a, b) | Yexpr_str_greater_eq (a, b)
  | Yexpr_equal (a, b) | Yexpr_less (a, b) | Yexpr_greater (a, b)
  | Yexpr_less_eq (a, b) | Yexpr_greater_eq (a, b) ->
      check_arg env a; check_arg env b
  | Yexpr_in_list (value, listvar) ->
      check_arg env value; check_arg env listvar
  | Yexpr_matches (value, _) -> check_arg env value
  | Yexpr_exists e | Yexpr_is_directory e | Yexpr_is_absolute e -> check_arg env e
  | Yexpr_ver_less (a, b) | Yexpr_ver_greater (a, b)
  | Yexpr_ver_equal (a, b) | Yexpr_ver_less_eq (a, b)
  | Yexpr_ver_greater_eq (a, b) ->
      check_arg env a; check_arg env b
  | Yexpr_policy _ -> ()
  (* simple expressions: bool lit, name, string, var — just check args *)
  | e -> check_arg env e

let check_items_with_kind env { kind = _; items } =
  List.iter items ~f:(check_arg env)

(* --- File / path group --- *)

let compile_file_io_stmt env : yelu_file_io_stmt -> env * Lang_cmake.exp = function
  | Yfile_configure { input; output } ->
      ( env,
        Cmake_cmd
          (Configure_file
             { input = erase_arg_s env input;
               output = erase_arg_s env output;
               permission_level = None; permissions = [];
               copy_only = None; escape_quotes = None;
               only = None; newline_style = None }) )
  | Yfile_relative_path { var; base; file } ->
      (env, File_relative_path { var = erase_arg_s env var; base = erase_arg_s env base; file = erase_arg_s env file })
  | Yfile_glob { out; recurse; relative; configure_depends; patterns } ->
      ( env,
        Lang_cmake.File_glob
          { var = cv_name out; recurse;
            relative = Option.map relative ~f:(erase_arg_s env);
            configure_depends;
            patterns = List.map patterns ~f:(erase_arg env) } )
  | Yfile_read { out; file; offset; limit; hex } ->
      (env, Lang_cmake.File_read { var = cv_name out; file = erase_arg env file; offset; limit; hex })
  | Yfile_write { file; append; content } ->
      (env, Lang_cmake.File_write { file = erase_arg env file; append; content = List.map content ~f:(erase_arg env) })
  | Yfile_strings { out; file; regex; encoding; limit_count } ->
      (env, Lang_cmake.File_strings { var = cv_name out; file = erase_arg env file; regex; encoding; limit_count })
  | Yfile_touch { files; nocreate } ->
      (env, Lang_cmake.File_touch { files = List.map files ~f:(erase_arg env); nocreate })
  | Yfile_make_directory { dirs } ->
      (env, Lang_cmake.File_make_directory { dirs = List.map dirs ~f:(erase_arg env) })
  | Yfile_rename { old_; new_; result; no_replace } ->
      ( env,
        Lang_cmake.File_rename
          { old_ = erase_arg env old_; new_ = erase_arg env new_;
            result = Option.map result ~f:cv_name; no_replace } )
  | Yfile_remove { files; recurse } ->
      (env, Lang_cmake.File_remove { files = List.map files ~f:(erase_arg env); recurse })
  | Yfile_copy { input; output; result; only_if_different } ->
      ( env,
        Lang_cmake.File_copy_file
          { input = erase_arg env input; output = erase_arg env output;
            result = Option.map result ~f:cv_name; only_if_different } )
  | Yfile_real_path { out; path; base_dir; expand_tilde } ->
      ( env,
        Lang_cmake.File_real_path
          { var = cv_name out; path = erase_arg env path;
            base_dir = Option.map base_dir ~f:(erase_arg env); expand_tilde } )
  | Yfile_size { out; file } ->
      (env, Lang_cmake.File_size { var = cv_name out; file = erase_arg env file })
  | Yfile_read_symlink { out; link } ->
      (env, Lang_cmake.File_read_symlink { var = cv_name out; link = erase_arg env link })
  | Yfile_timestamp { out; file; format; utc } ->
      (env, Lang_cmake.File_timestamp { var = cv_name out; file = erase_arg env file; format; utc })
let compile_path_stmt env : yelu_path_stmt -> env * Lang_cmake.exp = function
  | Ypath_get_filename_component { var; filename; mode } ->
      check_arg env filename;
      ( env,
        Get_filename_component
          { var = cv_name var; filename = erase_arg_s env filename; mode; cache = false } )
  | Ypath_get { path_var; field; out } ->
      (env, Cmake_cmd (Cmake_path (Cpp_get { path_var = cv_name path_var; field; out_var = cv_name out })))
  | Ypath_has { path_var; field; out } ->
      (env, Cmake_cmd (Cmake_path (Cpp_has { path_var = cv_name path_var; field; out_var = cv_name out })))
  | Ypath_is_absolute { path_var; out } ->
      (env, Cmake_cmd (Cmake_path (Cpp_is_absolute { path_var = cv_name path_var; out_var = cv_name out })))
  | Ypath_is_relative { path_var; out } ->
      (env, Cmake_cmd (Cmake_path (Cpp_is_relative { path_var = cv_name path_var; out_var = cv_name out })))
  | Ypath_is_prefix { path_var; input; normalize; out } ->
      (env, Cmake_cmd (Cmake_path (Cpp_is_prefix { path_var = cv_name path_var; input = erase_arg env input; normalize; out_var = cv_name out })))
  | Ypath_compare { input1; op; input2; out } ->
      (env, Cmake_cmd (Cmake_path (Cpp_compare { input1 = erase_arg env input1; op; input2 = erase_arg env input2; out_var = cv_name out })))
  | Ypath_set { path_var; input; normalize } ->
      (env, Cmake_cmd (Cmake_path (Cpp_set { path_var = cv_name path_var; input = erase_arg env input; normalize })))
  | Ypath_append { path_var; inputs; out } ->
      (env, Cmake_cmd (Cmake_path (Cpp_append { path_var = cv_name path_var; inputs = List.map ~f:(erase_arg env) inputs; out_var = Option.map ~f:cv_name out })))
  | Ypath_append_string { path_var; inputs; out } ->
      (env, Cmake_cmd (Cmake_path (Cpp_append_string { path_var = cv_name path_var; inputs = List.map ~f:(erase_arg env) inputs; out_var = Option.map ~f:cv_name out })))
  | Ypath_remove_filename { path_var; out } ->
      (env, Cmake_cmd (Cmake_path (Cpp_remove_filename { path_var = cv_name path_var; out_var = Option.map ~f:cv_name out })))
  | Ypath_replace_filename { path_var; input; out } ->
      (env, Cmake_cmd (Cmake_path (Cpp_replace_filename { path_var = cv_name path_var; input = erase_arg env input; out_var = Option.map ~f:cv_name out })))
  | Ypath_remove_extension { path_var; last_only; out } ->
      (env, Cmake_cmd (Cmake_path (Cpp_remove_extension { path_var = cv_name path_var; last_only; out_var = Option.map ~f:cv_name out })))
  | Ypath_replace_extension { path_var; last_only; input; out } ->
      (env, Cmake_cmd (Cmake_path (Cpp_replace_extension { path_var = cv_name path_var; last_only; input = erase_arg env input; out_var = Option.map ~f:cv_name out })))
  | Ypath_normal_path { path_var; out } ->
      (env, Cmake_cmd (Cmake_path (Cpp_normal_path { path_var = cv_name path_var; out_var = Option.map ~f:cv_name out })))
  | Ypath_relative_path { path_var; base_dir; out } ->
      (env, Cmake_cmd (Cmake_path (Cpp_relative_path { path_var = cv_name path_var; base_dir = Option.map ~f:(erase_arg env) base_dir; out_var = Option.map ~f:cv_name out })))
  | Ypath_absolute_path { path_var; base_dir; normalize; out } ->
      (env, Cmake_cmd (Cmake_path (Cpp_absolute_path { path_var = cv_name path_var; base_dir = Option.map ~f:(erase_arg env) base_dir; normalize; out_var = Option.map ~f:cv_name out })))
  | Ypath_native_path { path_var; normalize; out } ->
      (env, Cmake_cmd (Cmake_path (Cpp_native_path { path_var = cv_name path_var; normalize; out_var = cv_name out })))
  | Ypath_convert_to_cmake { input; normalize; out } ->
      (env, Cmake_cmd (Cmake_path (Cpp_convert_to_cmake { input = erase_arg env input; normalize; out_var = cv_name out })))
  | Ypath_convert_to_native { input; normalize; out } ->
      (env, Cmake_cmd (Cmake_path (Cpp_convert_to_native { input = erase_arg env input; normalize; out_var = cv_name out })))
  | Ypath_hash { path_var; out } ->
      (env, Cmake_cmd (Cmake_path (Cpp_hash { path_var = cv_name path_var; out_var = cv_name out })))

let compile_list_stmt env : yelu_list_stmt -> env * Lang_cmake.exp = function
  | Ylist_append { cvar; values } ->
      List.iter values ~f:(check_arg env);
      (env, List_cmd (Lc_append { var = cv_name cvar; values = List.map ~f:(erase_arg env) values }))
  | Ylist_length { cvar; out } ->
      (env, List_cmd (Lc_length { var = cv_name cvar; out = cv_name out }))
  | Ylist_get { cvar; indices; out } ->
      (env, List_cmd (Lc_get { var = cv_name cvar; indices; out = cv_name out }))
  | Ylist_remove_item { cvar; values } ->
      List.iter values ~f:(check_arg env);
      (env, List_cmd (Lc_remove_item { var = cv_name cvar;
                                       values = List.map ~f:(erase_arg env) values }))
  | Ylist_remove_duplicates { cvar } ->
      (env, List_cmd (Lc_remove_duplicates { var = cv_name cvar }))
  | Ylist_reverse { cvar } ->
      (env, List_cmd (Lc_reverse { var = cv_name cvar }))
  | Ylist_sort { cvar; order; compare; case } ->
      (env, List_cmd (Lc_sort { var = cv_name cvar; order; compare; case }))
  | Ylist_filter { cvar; mode; regex } ->
      (env, List_cmd (Lc_filter { var = cv_name cvar; mode; regex }))
  | Ylist_join { cvar; glue; out } ->
      check_arg env glue;
      (env, List_cmd (Lc_join { var = cv_name cvar; glue = erase_arg env glue; out = cv_name out }))
  | Ylist_sublist { cvar; begin_; length; out } ->
      (env, List_cmd (Lc_sublist { var = cv_name cvar; begin_; length; out = cv_name out }))
  | Ylist_find { cvar; value; out } ->
      check_arg env value;
      (env, List_cmd (Lc_find { var = cv_name cvar; value = erase_arg env value; out = cv_name out }))
  | Ylist_prepend { cvar; values } ->
      List.iter values ~f:(check_arg env);
      (env, List_cmd (Lc_prepend { var = cv_name cvar;
                                   values = List.map ~f:(erase_arg env) values }))
  | Ylist_insert { cvar; index; values } ->
      List.iter values ~f:(check_arg env);
      (env, List_cmd (Lc_insert { var = cv_name cvar; index;
                                  values = List.map ~f:(erase_arg env) values }))
  | Ylist_remove_at { cvar; indices } ->
      (env, List_cmd (Lc_remove_at { var = cv_name cvar; indices }))
  | Ylist_pop_back { cvar; out_vars } ->
      (env, List_cmd (Lc_pop_back { var = cv_name cvar;
                                    out_vars = List.map ~f:cv_name out_vars }))
  | Ylist_pop_front { cvar; out_vars } ->
      (env, List_cmd (Lc_pop_front { var = cv_name cvar;
                                     out_vars = List.map ~f:cv_name out_vars }))
  | Ylist_transform { cvar; action; selector; output } ->
      (env, List_cmd (Lc_transform { var = cv_name cvar; action; selector;
                                     output = Option.map ~f:cv_name output }))

let compile_install_stmt env : yelu_install_stmt -> env * Lang_cmake.exp = function
  | Yinstall_targets { targets; destination; export } ->
      List.iter targets ~f:(check_arg env);
      check_arg env destination;
      (env, Project_cmd (Install_targets {
        targets = List.map ~f:(erase_arg_s env) targets;
        destination = erase_arg env destination;
        permissions = []; component = None; rename = None;
        export = Option.map ~f:(erase_arg_s env) export }))
  | Yinstall_files { files; destination } ->
      List.iter files ~f:(check_arg env);
      check_arg env destination;
      (env, Project_cmd (Install_files {
        files = List.map ~f:(erase_arg env) files;
        destination = erase_arg env destination;
        permissions = []; component = None; rename = None }))
  | Yinstall_export { file; export; destination; namespace } ->
      Option.iter file ~f:(check_arg env);
      check_arg env export;
      check_arg env destination;
      (env, Project_cmd (Install_export {
        file = Option.map ~f:(erase_arg env) file;
        export = erase_arg env export;
        destination = erase_arg env destination;
        namespace;
        permissions = []; component = None; rename = None }))
  | Yinstall_export_export { name; file } ->
      Option.iter file ~f:(check_arg env);
      (env, Project_cmd (Export_export {
        name = erase_arg_s env name;
        file = Option.map ~f:(erase_arg env) file }))
  | Yinstall_configure_package_config_file
      { install_dest; input; output; no_set_and_check_macro; no_check_required_components_macro } ->
      check_arg env install_dest;
      check_arg env input;
      check_arg env output;
      (env, Module_cmd (Configure_package_config_file {
        input = erase_arg env input;
        output = erase_arg env output;
        install_dest = erase_arg env install_dest;
        path_vars = [];
        no_set_and_check_macro; no_check_required_components_macro }))
  | Yinstall_write_basic_package_version_file { file; version; compatibility; arch_independent } ->
      check_arg env file;
      Option.iter version ~f:(check_arg env);
      (env, Module_cmd (Write_basic_package_version_file {
        file = erase_arg env file;
        version = Option.map ~f:(erase_arg env) version;
        compatibility = Lang_cmake_strings.of_compatibility compatibility;
        arch_independent }))

let compile_cmake_stmt env : yelu_cmake_stmt -> env * Lang_cmake.exp = function
  | Ycmake_minimum_required { min; max } ->
      (env, Cmake_cmd (Cmake_minimum_required { min; max }))
  | Ycmake_project { name; version; languages } ->
      let languages = List.map ~f:Lang_cmake_strings.of_supported_lang languages in
      (env, Project_cmd (Project {
        name; version; description = None; homepage_url = None; languages }))
  | Ycmake_enable_language { langs; optional } ->
      (env, Project_cmd (Enable_language { langs; optional }))
  | Ycmake_policy_set { id; new_ } ->
      (env, Cmake_cmd (Cmake_policy_set { id; new_ }))
  | Ycmake_language_call { cmd; args } ->
      let arg_to_exp a =
        match a with
        | Lang_cmake.Bare s -> Lang_cmake.Var_exp s
        | Lang_cmake.Quoted s -> Lang_cmake.Quote (Printf.sprintf "\"%s\"" s)
        | Lang_cmake.Bracket s -> Lang_cmake.Var_exp (Printf.sprintf "[=[%s]=]" s)
      in
      (env, Cmake_cmd (Cmake_meta_lang (Meta_call {
        cmd = Var_exp cmd;
        arg = List.map ~f:(fun a -> arg_to_exp (erase_arg env a)) args })))
  | Ycmake_language_eval { code } ->
      (env, Cmake_cmd (Cmake_meta_lang (Meta_eval { code })))
  | Ycmake_language_get_log_level { out } ->
      (env, Cmake_cmd (Cmake_meta_lang (Meta_get_msg_log_level { var = cv_name out })))
  | Ycmake_math { exp; out; output_format } ->
      (env, Math_lib {
        var = cv_name out;
        exp = Quote (Printf.sprintf "\"%s\"" exp);
        output_format })
  | Ycmake_variable_watch { var; command } ->
      (env, Variable_watch {
        var = cv_name var; command; access = Vw_read_access;
        value = None; current_list_file = None; stack = [] })
  | Ycmake_execute_process { commands; working_directory; timeout; result_variable;
                              output_variable; error_variable; input_file; output_file;
                              error_file; output_quiet; error_quiet;
                              output_strip_trailing_whitespace;
                              error_strip_trailing_whitespace; command_error_is_fatal } ->
      ( env,
        Lang_cmake.Execute_process
          { commands = List.map commands ~f:(List.map ~f:(erase_arg env));
            working_directory = Option.map working_directory ~f:(erase_arg env);
            timeout;
            result_variable = Option.map result_variable ~f:cv_name;
            output_variable = Option.map output_variable ~f:cv_name;
            error_variable = Option.map error_variable ~f:cv_name;
            input_file = Option.map input_file ~f:(erase_arg env);
            output_file = Option.map output_file ~f:(erase_arg env);
            error_file = Option.map error_file ~f:(erase_arg env);
            output_quiet; error_quiet;
            output_strip_trailing_whitespace; error_strip_trailing_whitespace;
            command_error_is_fatal } )
  | Ycmake_include_guard { scope } -> (env, Include_guard { scope })
  | Ycmake_message { mode; texts } -> (env, Lang_cmake.Message { mode; texts })
  | Ycmake_quote_cmd _ -> failwith "Ycmake_quote_cmd: retired — use Ycmake_language_eval for raw cmake passthrough"
  | Ycmake_at_var key -> (env, Lang_cmake.Quote (Printf.sprintf "@%s@" key))

let compile_test_stmt env : yelu_test_stmt -> env * Lang_cmake.exp = function
  | Ytest_enable_testing -> (env, Project_cmd Enable_testing)
  | Ytest_add_test { name; command; args } ->
      (env, Project_cmd (Add_test {
        name = erase_arg_s env name;
        command = erase_arg_s env command;
        args = List.map ~f:(erase_arg_s env) args;
        dir = None }))

let compile_try_stmt env : yelu_try_stmt -> env * Lang_cmake.exp = function
  | Ytry_compile { result_var; sources; compile_definitions; link_libraries;
                   link_options; output_variable; no_cache; c_standard; cxx_standard } ->
      (env, Project_cmd (Try_compile {
        tc_result_var = cv_name result_var;
        tc_sources = List.map ~f:(erase_arg env) sources;
        tc_compile_definitions = List.map ~f:(erase_arg env) compile_definitions;
        tc_link_libraries = List.map ~f:(erase_arg env) link_libraries;
        tc_link_options = List.map ~f:(erase_arg env) link_options;
        tc_cmake_flags = [];
        tc_output_variable = Option.map ~f:cv_name output_variable;
        tc_copy_file = None;
        tc_no_cache = no_cache;
        tc_c_standard = c_standard;
        tc_cxx_standard = cxx_standard }))
  | Ytry_run { run_result_var; compile_result_var; sources; compile_definitions;
               link_libraries; compile_output_variable; run_output_variable; args } ->
      (env, Project_cmd (Try_run {
        tr_run_result_var = cv_name run_result_var;
        tr_compile_result_var = cv_name compile_result_var;
        tr_sources = List.map ~f:(erase_arg env) sources;
        tr_compile_definitions = List.map ~f:(erase_arg env) compile_definitions;
        tr_link_libraries = List.map ~f:(erase_arg env) link_libraries;
        tr_compile_output_variable = Option.map ~f:cv_name compile_output_variable;
        tr_run_output_variable = Option.map ~f:cv_name run_output_variable;
        tr_args = List.map ~f:(erase_arg env) args }))

let compile_dir_stmt env : yelu_dir_stmt -> env * Lang_cmake.exp = function
  | Ydir_include_directories { dirs; before; system } ->
      List.iter dirs ~f:(check_arg env);
      let ba = if before then Lang_cmake.Before else Lang_cmake.Default_order in
      (match dirs with
       | [] -> (env, Exp_list [])
       | first :: rest ->
         (env, Project_cmd (Include_directories {
           before_or_after = ba; system;
           dir = erase_arg_s env first;
           dirs = List.map ~f:(erase_arg_s env) rest })))
  | Ydir_add_compile_definitions { defs } ->
      List.iter defs ~f:(check_arg env);
      (env, Project_cmd (Add_compile_definitions {
        defs = List.map defs ~f:(fun a -> Lang_cmake.Def_var (erase_arg_s env a)) }))
  | Ydir_add_compile_options { options } ->
      List.iter options ~f:(check_arg env);
      (env, Project_cmd (Add_compile_options { options_ = List.map ~f:(erase_arg_s env) options }))
  | Ydir_add_link_options { options } ->
      List.iter options ~f:(check_arg env);
      (env, Project_cmd (Add_link_options { options = List.map ~f:(erase_arg_s env) options }))
  | Ydir_add_definitions { defs } ->
      List.iter defs ~f:(check_arg env);
      (env, Project_cmd (Add_definitions {
        defs = List.map defs ~f:(fun d -> Lang_cmake.Def_var (erase_arg_s env d)) }))
  | Ydir_link_directories { before; dirs } ->
      List.iter dirs ~f:(check_arg env);
      let ba = if before then Lang_cmake.Before else Lang_cmake.Default_order in
      (match dirs with
       | [] -> (env, Exp_list [])
       | first :: rest ->
         (env, Project_cmd (Link_directories {
           before_or_after = ba;
           directory = erase_arg_s env first;
           directories = List.map ~f:(erase_arg_s env) rest })))
  | Ydir_add_subdirectory { source_dir } ->
      (env, Project_cmd (Add_subdirectory {
        source_dir = erase_arg_s env source_dir;
        binary_dir = None; exclude_from_all = false; system = false }))
  | Ydir_link_libraries { items } ->
      List.iter items ~f:(check_arg env);
      let erased = List.map ~f:(erase_arg_s env) items in
      let groups = List.map erased ~f:(fun lib ->
        { Lang_cmake.kind = Ll_general; item = lib; items = [] }) in
      (env, Project_cmd (Link_libraries { groups }))

let compile_find_stmt env : yelu_find_stmt -> env * Lang_cmake.exp = function
  | Yfind_library { cvar; names; paths; hints; no_default_path;
                    no_cmake_environment_path; no_system_environment_path; required } ->
      let env = declare_cvar env cvar in
      let open Lang_cmake in
      (env, Find_library { (Lang_cmake_utils.find_var_defaults (cv_name cvar)) with
        names = List.map ~f:(erase_arg env) names;
        paths = List.map ~f:(erase_arg env) paths;
        hints = List.map ~f:(erase_arg env) hints;
        no_default_path; no_cmake_environment_path;
        no_system_environment_path; required })
  | Yfind_path { cvar; names; paths; hints; no_default_path;
                 no_cmake_environment_path; no_system_environment_path; required } ->
      let env = declare_cvar env cvar in
      let open Lang_cmake in
      (env, Find_path { (Lang_cmake_utils.find_var_defaults (cv_name cvar)) with
        names = List.map ~f:(erase_arg env) names;
        paths = List.map ~f:(erase_arg env) paths;
        hints = List.map ~f:(erase_arg env) hints;
        no_default_path; no_cmake_environment_path;
        no_system_environment_path; required })
  | Yfind_program { cvar; names; paths; hints; no_default_path;
                    no_cmake_environment_path; no_system_environment_path; required } ->
      let env = declare_cvar env cvar in
      let open Lang_cmake in
      (env, Find_program { (Lang_cmake_utils.find_var_defaults (cv_name cvar)) with
        names = List.map ~f:(erase_arg env) names;
        paths = List.map ~f:(erase_arg env) paths;
        hints = List.map ~f:(erase_arg env) hints;
        no_default_path; no_cmake_environment_path;
        no_system_environment_path; required })
  | Yfind_file { cvar; names; paths; hints; no_default_path;
                 no_cmake_environment_path; no_system_environment_path; required } ->
      let env = declare_cvar env cvar in
      let open Lang_cmake in
      (env, Find_file { (Lang_cmake_utils.find_var_defaults (cv_name cvar)) with
        names = List.map ~f:(erase_arg env) names;
        paths = List.map ~f:(erase_arg env) paths;
        hints = List.map ~f:(erase_arg env) hints;
        no_default_path; no_cmake_environment_path;
        no_system_environment_path; required })
  | Yfind_package { name; version; exact; quiet; config_mode; required; components; optional_components } ->
      (env, Lang_cmake.Find_package { name; version; exact; quiet; config_mode;
                                      required; components; optional_components })

let compile_var_stmt env : yelu_var_stmt -> env * Lang_cmake.exp = function
  | Yvar_set { cvar; values; parent_scope } ->
      List.iter values ~f:(check_arg env);
      let env = if parent_scope then env else declare_cvar env cvar in
      (env, Set { var = cv_name cvar;
                  values = List.map ~f:(erase_arg env) values;
                  parent_scope })
  | Yvar_option { cvar; msg; value } ->
      check_arg env value;
      let env = declare_cvar env cvar in
      (env, Cmake_option { var = cv_name cvar; msg; value = erase_arg env value })
  | Yvar_set_cache { cvar; values; cache_type; docstring; force } ->
      List.iter values ~f:(check_arg env);
      (env, Set_cache { var = cv_name cvar;
                        values = List.map ~f:(erase_arg env) values;
                        cache_type; docstring; force })
  | Yvar_unset_cache { cvar } ->
      (env, Unset { var = cv_name cvar; cache = true; parent_scope = false })
  | Yvar_set_env { var; value } ->
      check_arg env value;
      (env, Set_env { var; value = erase_arg env value })
  | Yvar_unset_env { var } ->
      (env, Unset_env { var })

let compile_property_stmt env : yelu_property_stmt -> env * Lang_cmake.exp = function
  | Yprop_get { var; target; property; set = _ } ->
      check_arg env target;
      (env, Project_cmd (Get_target_property {
        var = cv_name var; target = erase_arg_s env target;
        property = { prop = property; value = Bare "" } }))
  | Yprop_get_directory { var; property } ->
      (env, Get_directory_property { var = cv_name var; directory = ""; property })
  | Yprop_set_directory { property; append; values } ->
      List.iter values ~f:(check_arg env);
      (env, Set_directory_property { append; property;
                                     values = List.map ~f:(erase_arg env) values })
  | Yprop_set_tests { tests; properties } ->
      List.iter properties ~f:(fun (_, v) -> check_arg env v);
      (env, Project_cmd (Set_tests_properties {
        tests = List.map ~f:(erase_arg_s env) tests;
        dir = None;
        properties = List.map ~f:(erase_property env) properties }))
  | Yprop_set_target { target; properties } ->
      check_arg env target;
      List.iter properties ~f:(fun (_, v) -> check_arg env v);
      (env, Project_cmd (Set_target_properties {
        target = erase_arg_s env target;
        properties = List.map ~f:(erase_property env) properties }))
  | Yprop_set { targets; append = do_append; properties } ->
      List.iter targets ~f:(check_arg env);
      List.iter properties ~f:(fun (_, v) -> check_arg env v);
      (env, Set_property {
        global = false; directory = [];
        targets = List.map ~f:(erase_arg_s env) targets;
        sources = []; source_directories = []; source_target_directories = [];
        installs = []; tests = []; test_directories = []; caches = [];
        append = do_append; append_string = false;
        properties = List.map ~f:(erase_property env) properties })
  | Yprop_set_source { file; property; values } ->
      check_arg env file;
      List.iter values ~f:(check_arg env);
      (env, Set_source_property {
        file = erase_arg_s env file; property;
        values = List.map ~f:(erase_arg env) values })
  | Yprop_set_global { properties } ->
      List.iter properties ~f:(fun (_, v) -> check_arg env v);
      (env, Set_property {
        global = true; directory = []; targets = []; sources = [];
        source_directories = []; source_target_directories = [];
        installs = []; tests = []; test_directories = []; caches = [];
        append = false; append_string = false;
        properties = List.map ~f:(erase_property env) properties })
  | Yprop_get_global { var; property } ->
      (env, Get_property {
        var = cv_name var; global = true; directory = "";
        source = ""; source_directory = ""; source_target_directory = "";
        install = ""; test = ""; test_directory = "";
        variable = false; property_name = property; set = false })
  | Yprop_get_target { var; target; property } ->
      (env, Project_cmd (Get_target_property {
        var = cv_name var; target;
        property = { prop = property; value = Bare "" } }))
  | Yprop_define { mode; property_name; inherited; brief_docs; full_docs; initialize_from } ->
      (env, Project_cmd (Define_property {
        mode; property_name; inherited; brief_docs; full_docs;
        initialize_from = Option.value initialize_from ~default:"" }))

let compile_target_stmt env : yelu_target_stmt -> env * Lang_cmake.exp = function
  | Ytgt_add_executable { name; exclude_from_all; sources } ->
      let env = try_declare_target env name in
      let options = if exclude_from_all then [Lang_cmake.Ae_exclude_from_all] else [] in
      (env, Project_cmd (Add_executable {
        name = erase_arg_s env name; options;
        sources = List.map ~f:(erase_arg_s env) sources }))
  | Ytgt_add_library { name; type_; exclude_from_all; sources } ->
      let env = try_declare_target env name in
      (env, Project_cmd (Add_library {
        name = erase_arg_s env name;
        type_ = Option.map ~f:string_of_library_type type_;
        exclude_from_all;
        sources = List.map ~f:(erase_arg_s env) sources }))
  | Ytgt_add_library_imported { name; lib_type; global } ->
      let env = try_declare_target env name in
      (env, Project_cmd (Add_library_imported { name = erase_arg_s env name; lib_type; global }))
  | Ytgt_add_library_alias { name; target } ->
      (env, Project_cmd (Add_library_alias { name; target }))
  | Ytgt_add_executable_alias { name; target } ->
      (env, Project_cmd (Add_executable_alias { name; target }))
  | Ytgt_include_directories { target; before; system; items } ->
      check_arg env target;
      List.iter items ~f:(check_items_with_kind env);
      (env, Project_cmd (Target_include_directories {
        target = erase_arg_s env target;
        system = (if system then Some true else None);
        before_or_after = (if before then Some Lang_cmake.Before else None);
        items = List.map ~f:(erase_items_with_kind env) items }))
  | Ytgt_link_libraries { targets; items } ->
      List.iter targets ~f:(check_arg env);
      List.iter items ~f:(check_items_with_kind env);
      (env, Project_cmd (Target_link_libraries {
        targets = List.map ~f:(erase_arg_s env) targets;
        items = List.map ~f:(erase_items_with_kind env) items }))
  | Ytgt_compile_definitions { target; items } ->
      check_arg env target;
      List.iter items ~f:(check_items_with_kind env);
      (env, Project_cmd (Target_compile_definitions {
        target = erase_arg_s env target;
        items = List.map ~f:(erase_items_with_kind env) items }))
  | Ytgt_compile_features { target; features } ->
      check_arg env target;
      (env, Project_cmd (Target_compile_features {
        target = erase_arg_s env target;
        features = List.map ~f:erase_target_feature features }))
  | Ytgt_compile_options { target; before; items } ->
      check_arg env target;
      List.iter items ~f:(check_items_with_kind env);
      (env, Project_cmd (Target_compile_options {
        target = erase_arg_s env target; before;
        items = List.map ~f:(erase_items_with_kind env) items }))
  | Ytgt_link_options { target; before; items } ->
      check_arg env target;
      List.iter items ~f:(check_items_with_kind env);
      (env, Project_cmd (Target_link_options {
        target = erase_arg_s env target; before;
        items = List.map ~f:(erase_items_with_kind env) items }))
  | Ytgt_link_directories { target; before; items } ->
      check_arg env target;
      List.iter items ~f:(check_items_with_kind env);
      (env, Project_cmd (Target_link_directories {
        target = erase_arg_s env target; before;
        items = List.map ~f:(erase_items_with_kind env) items }))
  | Ytgt_sources { target; items } ->
      check_arg env target;
      List.iter items ~f:(check_items_with_kind env);
      (env, Project_cmd (Target_sources {
        target = erase_arg_s env target;
        items = List.map ~f:(erase_items_with_kind env) items }))
  | Ytgt_sources_fs { target; items } ->
      let erase_item = function
        | Ytsi_plain iwk ->
            check_items_with_kind env iwk;
            Lang_cmake.Tsi_plain (erase_items_with_kind env iwk)
        | Ytsi_file_set { kind; type_; base_dirs; files } ->
            List.iter base_dirs ~f:(check_arg env);
            List.iter files ~f:(check_arg env);
            Lang_cmake.Tsi_file_set {
              kind = string_of_kind kind;
              file_set = Lang_cmake.SSet;
              type_;
              base_dirs = List.map ~f:(erase_arg_s env) base_dirs;
              files = List.map ~f:(erase_arg_s env) files }
      in
      check_arg env target;
      (env, Project_cmd (Target_sources_file_set {
        target = erase_arg_s env target;
        items = List.map ~f:erase_item items }))
  | Ytgt_precompile_headers { target; items } ->
      check_arg env target;
      List.iter items ~f:(check_items_with_kind env);
      (env, Project_cmd (Target_precompile_headers {
        target = erase_arg_s env target;
        items = List.map ~f:(erase_items_with_kind env) items }))
  | Ytgt_add_custom_command { outputs; commands; depends; verbatim; comment } ->
      List.iter outputs ~f:(check_arg env);
      List.iter depends ~f:(check_arg env);
      (env, Project_cmd (Add_custom_command {
        outputs = List.map ~f:(erase_arg_s env) outputs;
        commands; main_dependency = None;
        depends = List.map ~f:(erase_arg_s env) depends;
        byproducts = []; implicit_depends = [];
        working_directory = None; comment; depfile = None;
        job_pool = None; job_server_aware = false; verbatim;
        append = false; uses_terminal = false; codegen = false;
        command_expand_list = []; depends_explicit_only = false }))
  | Ytgt_add_custom_command_target { target; when_; commands; comment; verbatim } ->
      (env, Project_cmd (Add_custom_command_target {
        target; when_; commands; comment; verbatim; uses_terminal = false }))
  | Ytgt_add_custom_target { name; all; commands; depends; comment } ->
      List.iter depends ~f:(check_arg env);
      (env, Project_cmd (Add_custom_target {
        name; all; commands;
        depends = List.map ~f:(erase_arg_s env) depends;
        byproducts = []; working_directory = None; comment; job_pool = [];
        job_server_aware = false; verbatim = false; uses_terminal = false;
        command_expand_list = []; sources = [] }))
  | Ytgt_add_dependencies { target; dep } ->
      (env, Project_cmd (Add_dependencies { target; dep }))

let compile_string_stmt env : yelu_string_stmt -> env * Lang_cmake.exp = function
  | Ystr_toupper { string; out } ->
      check_arg env string;
      (env, String_cmd (Sc_toupper { string = erase_arg env string; out = cv_name out }))
  | Ystr_tolower { string; out } ->
      check_arg env string;
      (env, String_cmd (Sc_tolower { string = erase_arg env string; out = cv_name out }))
  | Ystr_length { string; out } ->
      check_arg env string;
      (env, String_cmd (Sc_length { string = erase_arg env string; out = cv_name out }))
  | Ystr_strip { string; out } ->
      check_arg env string;
      (env, String_cmd (Sc_strip { string = erase_arg env string; out = cv_name out }))
  | Ystr_concat { out; inputs } ->
      List.iter inputs ~f:(check_arg env);
      (env, String_cmd (Sc_concat { out = cv_name out; inputs = List.map ~f:(erase_arg env) inputs }))
  | Ystr_replace { match_string; replace_string; out; inputs } ->
      check_arg env match_string; check_arg env replace_string;
      List.iter inputs ~f:(check_arg env);
      (env, String_cmd (Sc_replace { match_string = erase_arg env match_string;
                                     replace_string = erase_arg env replace_string;
                                     out = cv_name out;
                                     inputs = List.map ~f:(erase_arg env) inputs }))
  | Ystr_regex_match { regex; out; inputs } ->
      List.iter inputs ~f:(check_arg env);
      (env, String_cmd (Sc_regex (Sr_match { regex; out = cv_name out;
                                             inputs = List.map ~f:(erase_arg env) inputs })))
  | Ystr_regex_matchall { regex; out; inputs } ->
      List.iter inputs ~f:(check_arg env);
      (env, String_cmd (Sc_regex (Sr_matchall { regex; out = cv_name out;
                                                inputs = List.map ~f:(erase_arg env) inputs })))
  | Ystr_regex_replace { regex; replace; out; inputs } ->
      check_arg env replace; List.iter inputs ~f:(check_arg env);
      (env, String_cmd (Sc_regex (Sr_replace { regex; replace = erase_arg env replace;
                                               out = cv_name out;
                                               inputs = List.map ~f:(erase_arg env) inputs })))
  | Ystr_regex_quote { out; inputs } ->
      List.iter inputs ~f:(check_arg env);
      (env, String_cmd (Sc_regex (Sr_quote { out = cv_name out;
                                             inputs = List.map ~f:(erase_arg env) inputs })))
  | Ystr_append { cvar; inputs } ->
      List.iter inputs ~f:(check_arg env);
      (env, String_cmd (Sc_append { var = cv_name cvar;
                                    inputs = List.map ~f:(erase_arg env) inputs }))
  | Ystr_prepend { cvar; inputs } ->
      List.iter inputs ~f:(check_arg env);
      (env, String_cmd (Sc_prepend { var = cv_name cvar;
                                     prefix = erase_arg env (List.hd_exn inputs);
                                     inputs = List.tl_exn inputs |> List.map ~f:(erase_arg env) }))
  | Ystr_join { glue; out; inputs } ->
      check_arg env glue; List.iter inputs ~f:(check_arg env);
      (env, String_cmd (Sc_join { glue = erase_arg env glue; out = cv_name out;
                                  inputs = List.map ~f:(erase_arg env) inputs }))
  | Ystr_find { string; substring; out; reverse } ->
      check_arg env string; check_arg env substring;
      (env, String_cmd (Sc_find { string = erase_arg env string;
                                  substring = erase_arg env substring; out = cv_name out; reverse }))
  | Ystr_substring { string; begin_; length; out } ->
      check_arg env string;
      (env, String_cmd (Sc_substring { string = erase_arg env string; begin_; length; out = cv_name out }))
  | Ystr_repeat { string; count; out } ->
      check_arg env string;
      (env, String_cmd (Sc_repeat { string = erase_arg env string; count; out = cv_name out }))
  | Ystr_genex_strip { string; out } ->
      check_arg env string;
      (env, String_cmd (Sc_genex_strip { string = erase_arg env string; out = cv_name out }))
  | Ystr_compare { op; string1; string2; out } ->
      check_arg env string1; check_arg env string2;
      (env, String_cmd (Sc_compare { op; string1 = erase_arg env string1;
                                     string2 = erase_arg env string2; out = cv_name out }))
  | Ystr_make_c_identifier { string; out } ->
      check_arg env string;
      (env, String_cmd (Sc_make_c_identifier { string = erase_arg env string; out = cv_name out }))
  | Ystr_timestamp { out; format; utc } ->
      (env, String_cmd (Sc_timestamp { out = cv_name out; format; utc }))
  | Ystr_hex { string; out } ->
      check_arg env string;
      (env, String_cmd (Sc_hex { string = erase_arg env string; out = cv_name out }))
  | Ystr_uuid { out; namespace; name; type_; upper } ->
      (env, String_cmd (Sc_uuid { out = cv_name out; namespace; name; type_; upper }))
  | Ystr_json { out; error_var; op } ->
      let ep = List.map ~f:(fun s -> Lang_cmake.Bare s) in
      let ej = erase_arg env in
      let cmake_op = match op with
        | Yjop_get { json; path } -> Lang_cmake.Jop_get { json = ej json; path = ep path }
        | Yjop_get_raw { json; path } -> Lang_cmake.Jop_get_raw { json = ej json; path = ep path }
        | Yjop_type { json; path } -> Lang_cmake.Jop_type { json = ej json; path = ep path }
        | Yjop_length { json; path } -> Lang_cmake.Jop_length { json = ej json; path = ep path }
        | Yjop_member { json; path } -> Lang_cmake.Jop_member { json = ej json; path = ep path }
        | Yjop_remove { json; path } -> Lang_cmake.Jop_remove { json = ej json; path = ep path }
        | Yjop_set { json; path; value } ->
            Lang_cmake.Jop_set { json = ej json; path = ep path; value = ej value }
        | Yjop_equal { json1; json2 } -> Lang_cmake.Jop_equal { json1 = ej json1; json2 = ej json2 }
        | Yjop_string_encode { value } -> Lang_cmake.Jop_string_encode { value = ej value }
      in
      (env, String_cmd (Sc_json { out = cv_name out;
                                  error_var = Option.map ~f:cv_name error_var; op = cmake_op }))

(* --- Compile with env threading --- *)

let rec compile env : yelu_stmt -> env * Lang_cmake.exp = function
  | Ys_file e -> compile_file_io_stmt env e
  | Ys_path e -> compile_path_stmt env e
  | Ys_string e -> compile_string_stmt env e
  | Ys_list e -> compile_list_stmt env e
  | Ys_target e -> compile_target_stmt env e
  | Ys_var e -> compile_var_stmt env e
  | Ys_property e -> compile_property_stmt env e
  | Ys_find e -> compile_find_stmt env e
  | Ys_install e -> compile_install_stmt env e
  | Ys_dir e -> compile_dir_stmt env e
  | Ys_cmake e -> compile_cmake_stmt env e
  | Ys_test e -> compile_test_stmt env e
  | Ys_try e -> compile_try_stmt env e
  | Ylet { var = Yvar name; value } ->
      check_arg env value;
      let resolved = resolve_arg env value in
      let env = { env with bindings = Map.set env.bindings ~key:name ~data:resolved } in
      (env, Exp_list [])
  | Yif { cond; then_; else_ } ->
      check_bool env cond;
      let then_env, then_cmake = compile env then_ in
      let else_env, else_cmake =
        match else_ with
        | None -> (env, None)
        | Some e ->
            let env', e' = compile env e in
            (env', Some e')
      in
      (* Union: anything declared in either branch is available after *)
      let env =
        {
          cvars = Set.union then_env.cvars else_env.cvars;
          targets = Set.union then_env.targets else_env.targets;
          bindings = env.bindings;
        }
      in
      ( env,
        If { cond = erase_bool env cond; then_ = then_cmake; else_ = else_cmake } )
  | Ystmt_list exps ->
      let env, rev_cmds =
        List.fold exps ~init:(env, []) ~f:(fun (env, acc) exp ->
            let env, cmd = compile env exp in
            match cmd with
            | Exp_list [] -> (env, acc) (* drop empty nodes from externs/ylet *)
            | _ -> (env, cmd :: acc))
      in
      (env, Exp_list (List.rev rev_cmds))
  (* scripting *)
  | Yc_include { file; optional } ->
      check_arg env file;
      ( env,
        Include
          {
            file = erase_arg env file;
            optional;
            result_var = None;
            no_policy_scope = false;
          } )
  | Yc_function { name; args; body } ->
      let env = try_declare_cvar env name in
      let body_env =
        List.fold args ~init:env ~f:(fun env arg ->
            { env with cvars = Set.add env.cvars arg })
      in
      let _body_env, body_cmds = compile_list body_env body in
      (env, Function { name = erase_arg_s env name; args; cmds = body_cmds })
  | Yc_macro { name; args; body } ->
      let body_env =
        List.fold args ~init:env ~f:(fun env arg ->
            { env with cvars = Set.add env.cvars arg })
      in
      let _body_env, body_cmds = compile_list body_env body in
      (env, Macro { name = erase_arg_s env name; args; commands = Exp_list body_cmds })
  | Yc_apply { name; args } ->
      check_arg env name;
      List.iter args ~f:(check_arg env);
      (env, Apply { name = erase_arg_s env name; args = List.map ~f:(erase_arg env) args })
  | Yc_separate_arguments { cvar; mode; input } ->
      Option.iter input ~f:(check_arg env);
      ( env,
        Separete_arguments
          { var = cv_name cvar;
            mode;
            input = Option.map input ~f:(erase_arg env) } )
  (* extern declarations — register in env, emit nothing *)
  | Yc_extern_cvar v -> (declare_cvar env v, Exp_list [])
  | Yc_extern_target t -> (declare_target env t, Exp_list [])
  (* Tier 2: iteration and control flow *)
  | Yc_foreach { loop_var; items; commands } ->
      List.iter items ~f:(check_arg env);
      let lv = cv_name loop_var in
      let body_env = { env with cvars = Set.add env.cvars lv } in
      let _body_env, body_cmake = compile body_env commands in
      ( { env with cvars = Set.add env.cvars lv },
        Foreach
          { loop_var = lv;
            items = List.map ~f:(erase_arg env) items;
            commands = body_cmake } )
  | Yc_foreach_range { loop_var; start; stop; step; commands } ->
      let lv = cv_name loop_var in
      let body_env = { env with cvars = Set.add env.cvars lv } in
      let _body_env, body_cmake = compile body_env commands in
      let int_var n = Int.to_string n in
      ( { env with cvars = Set.add env.cvars lv },
        Foreach_range
          { loop_var = lv;
            start = Option.map ~f:int_var start;
            stop = int_var stop;
            step = Option.map ~f:int_var step;
            commands = body_cmake } )
  | Yc_foreach_in { loop_var; lists; items; commands } ->
      List.iter items ~f:(check_arg env);
      let lv = cv_name loop_var in
      let body_env = { env with cvars = Set.add env.cvars lv } in
      let _body_env, body_cmake = compile body_env commands in
      ( { env with cvars = Set.add env.cvars lv },
        Foreach_in
          { loop_var = lv;
            lists = List.map ~f:cv_name lists;
            items = List.map ~f:(erase_arg env) items;
            commands = body_cmake } )
  | Yc_foreach_zip { loop_vars; lists; commands } ->
      let lv_names = List.map ~f:cv_name loop_vars in
      let body_env = { env with cvars = List.fold lv_names ~init:env.cvars ~f:Set.add } in
      let _body_env, body_cmake = compile body_env commands in
      ( body_env,
        Foreach_zip
          { loop_vars = lv_names;
            lists = List.map ~f:cv_name lists;
            commands = body_cmake } )
  | Yc_while { cond; commands } ->
      check_bool env cond;
      let _body_env, body_cmake = compile env commands in
      (env, While { cond = erase_bool env cond; commands = body_cmake })
  | Yc_break -> (env, Break)
  | Yc_continue -> (env, Continue)
  | Yc_return { propogate_vars } ->
      (env, Return { propogate_vars })
  | Yc_block { scope_vars; propagate; body } ->
      let _body_env, body_cmds = compile_list env body in
      ( env,
        Block
          { scope_policy = [];
            scope_var = List.map ~f:cv_name scope_vars;
            propagate;
            body = body_cmds } )

and compile_list env exps =
  let env, rev_cmds =
    List.fold exps ~init:(env, []) ~f:(fun (env, acc) exp ->
        let env, cmd = compile env exp in
        (env, cmd :: acc))
  in
  (env, List.rev rev_cmds)

and compile_cmd env (yelu_stmt : yelu_stmt) : env * Lang_cmake.cmd =
  compile env yelu_stmt
