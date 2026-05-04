(* Wellform pass — whole-program name binding check.
   Checks that every cmake cvar and target reference has a prior declaration.

   Unlike typecheck (per-theory, per-statement functors), wellform is cross-theory
   and whole-program — a target declared in target theory is referenced in install/
   test/property theory, so no single theory can resolve this alone. *)

open Base
open Lang_yelu_cmake

type error =
  | Undeclared_cvar of { name : string; context : string }
  | Undeclared_target of { name : string; context : string }

type env = {
  bindings : yelu_expr Map.M(String).t;
  cvars : Set.M(String).t;
  targets : Set.M(String).t;
}

let empty_env =
  { bindings = Map.empty (module String);
    cvars = Set.empty (module String);
    targets = Set.empty (module String)
  }

let stage = Lang_yelu_type.Stage_wellform

let is_builtin_cvar s =
  String.is_prefix s ~prefix:"CMAKE_"
  || String.is_prefix s ~prefix:"PROJECT_"
  || String.is_prefix s ~prefix:"CPACK_"
  || String.is_prefix s ~prefix:"CTEST_"
  || String.is_prefix s ~prefix:"BUILD_"

(* Compile-time variable resolution *)
let rec resolve env = function
  | Yexpr_var (Yvar name) ->
    (match Map.find env.bindings name with
     | Some v -> resolve env v
     | None -> Yexpr_var (Yvar name))
  | e -> e

(* Extract cvar/target refs from a resolved expression *)
let cvar_refs_of_expr ?(in_defined = false) = function
  | Yexpr_name { ns = Ns_var; name } -> if in_defined then [] else [ name ]
  | Yexpr_name _ | Yexpr_string _ | Yexpr_bool _ -> []
  | Yexpr_var _ -> []

let target_refs_of_expr = function
  | Yexpr_name { ns = Ns_target; name } -> [ name ]
  | _ -> []

let cvar_name_of_tcname ({ ns; name } : tc_name) =
  match ns with Ns_var -> [ name ] | _ -> []

(* Condition traversal — Yis_defined exempts its argument from cvar checking *)
let rec cvar_refs_of_cond = function
  | Ytruthy arg -> cvar_refs_of_expr arg
  | Ynot c -> cvar_refs_of_cond c
  | Yand (a, b) | Yor (a, b) -> cvar_refs_of_cond a @ cvar_refs_of_cond b
  | Yis_target arg -> cvar_refs_of_expr arg
  | Yis_defined arg -> cvar_refs_of_expr ~in_defined:true arg
  | Yin_list (value, listvar) -> cvar_refs_of_expr value @ cvar_refs_of_expr listvar
  | Ymatches (value, _) | Yexists value | Yis_directory value | Yis_absolute value ->
    cvar_refs_of_expr value
  | Ystrequal (a, b) | Ystrless (a, b) | Ystrgreater (a, b)
  | Ystrless_equal (a, b) | Ystrgreater_equal (a, b)
  | Yequal (a, b) | Yless (a, b) | Ygreater (a, b)
  | Yless_equal (a, b) | Ygreater_equal (a, b)
  | Yversion_less (a, b) | Yversion_greater (a, b)
  | Yversion_equal (a, b) | Yversion_less_equal (a, b)
  | Yversion_greater_equal (a, b) ->
    cvar_refs_of_expr a @ cvar_refs_of_expr b
  | Ypolicy_defined _ -> []

let rec target_refs_of_cond = function
  | Ytruthy arg -> target_refs_of_expr arg
  | Ynot c -> target_refs_of_cond c
  | Yand (a, b) | Yor (a, b) -> target_refs_of_cond a @ target_refs_of_cond b
  | Yis_target _ -> []  (* Yis_target checks existence, exempt from decl check *)
  | Yis_defined _ -> []
  | Yin_list (value, listvar) -> target_refs_of_expr value @ target_refs_of_expr listvar
  | Ymatches (value, _) | Yexists value | Yis_directory value | Yis_absolute value ->
    target_refs_of_expr value
  | Ystrequal (a, b) | Ystrless (a, b) | Ystrgreater (a, b)
  | Ystrless_equal (a, b) | Ystrgreater_equal (a, b)
  | Yequal (a, b) | Yless (a, b) | Ygreater (a, b)
  | Yless_equal (a, b) | Ygreater_equal (a, b)
  | Yversion_less (a, b) | Yversion_greater (a, b)
  | Yversion_equal (a, b) | Yversion_less_equal (a, b)
  | Yversion_greater_equal (a, b) ->
    target_refs_of_expr a @ target_refs_of_expr b
  | Ypolicy_defined _ -> []

(* Check helpers *)
let check_cvar_ref env ~context name =
  if Set.mem env.cvars name || is_builtin_cvar name then []
  else [ Undeclared_cvar { name; context } ]

let check_target_ref env ~context name =
  if Set.mem env.targets name then []
  else [ Undeclared_target { name; context } ]

let check_cvar_refs env ~context names =
  List.concat_map names ~f:(check_cvar_ref env ~context)

let check_target_refs env ~context names =
  List.concat_map names ~f:(check_target_ref env ~context)

(* Env updates *)
let declare_cvar env name = { env with cvars = Set.add env.cvars name }
let declare_target env name = { env with targets = Set.add env.targets name }
let add_cvars env names = List.fold names ~init:env ~f:declare_cvar
let add_targets env names = List.fold names ~init:env ~f:declare_target

(* Resolve an expr, then check any cvar/target refs found *)
let resolve_and_check env ~context expr =
  let resolved = resolve env expr in
  check_cvar_refs env ~context (cvar_refs_of_expr resolved)
  @ check_target_refs env ~context (target_refs_of_expr resolved)

(* Try to extract target name from a resolved expr and declare it *)
let try_declare_target env expr =
  match resolve env expr with
  | Yexpr_name { ns = Ns_target; name } -> declare_target env name
  | _ -> env

(* ============================================================
   Per-statement checkers
   ============================================================ *)

let rec check_json_op env = function
  | Yjop_get { json; _ } | Yjop_get_raw { json; _ } | Yjop_type { json; _ }
  | Yjop_length { json; _ } | Yjop_member { json; _ } | Yjop_remove { json; _ } ->
    resolve_and_check env ~context:"json" json
  | Yjop_set { json; value; _ } ->
    resolve_and_check env ~context:"json" json
    @ resolve_and_check env ~context:"json" value
  | Yjop_equal { json1; json2 } ->
    resolve_and_check env ~context:"json" json1
    @ resolve_and_check env ~context:"json" json2
  | Yjop_string_encode { value } ->
    resolve_and_check env ~context:"json" value

and check_string_stmt env : yelu_string_stmt -> env * error list = function
  | Ystr_toupper { string; out } ->
    let errs = resolve_and_check env ~context:"toupper" string in
    (declare_cvar env out.name, errs)
  | Ystr_tolower { string; out } ->
    let errs = resolve_and_check env ~context:"tolower" string in
    (declare_cvar env out.name, errs)
  | Ystr_length { string; out } ->
    let errs = resolve_and_check env ~context:"string_length" string in
    (declare_cvar env out.name, errs)
  | Ystr_strip { string; out } ->
    let errs = resolve_and_check env ~context:"string_strip" string in
    (declare_cvar env out.name, errs)
  | Ystr_concat { out; inputs } ->
    let errs = List.concat_map inputs ~f:(fun e -> resolve_and_check env ~context:"concat" e) in
    (declare_cvar env out.name, errs)
  | Ystr_replace { match_string; replace_string; out; inputs } ->
    let errs = resolve_and_check env ~context:"replace" match_string
             @ resolve_and_check env ~context:"replace" replace_string
             @ List.concat_map inputs ~f:(fun e -> resolve_and_check env ~context:"replace" e) in
    (declare_cvar env out.name, errs)
  | Ystr_regex_match { out; inputs; _ } | Ystr_regex_matchall { out; inputs; _ }
  | Ystr_regex_quote { out; inputs; _ } ->
    let errs = List.concat_map inputs ~f:(fun e -> resolve_and_check env ~context:"regex" e) in
    (declare_cvar env out.name, errs)
  | Ystr_regex_replace { replace; out; inputs; _ } ->
    let errs = resolve_and_check env ~context:"regex_replace" replace
             @ List.concat_map inputs ~f:(fun e -> resolve_and_check env ~context:"regex_replace" e) in
    (declare_cvar env out.name, errs)
  | Ystr_append { cvar; inputs } ->
    let errs = check_cvar_refs env ~context:"string_append" (cvar_name_of_tcname cvar)
             @ List.concat_map inputs ~f:(fun e -> resolve_and_check env ~context:"string_append" e) in
    (env, errs)
  | Ystr_prepend { cvar; inputs } ->
    let errs = check_cvar_refs env ~context:"string_prepend" (cvar_name_of_tcname cvar)
             @ List.concat_map inputs ~f:(fun e -> resolve_and_check env ~context:"string_prepend" e) in
    (env, errs)
  | Ystr_join { glue; out; inputs } ->
    let errs = resolve_and_check env ~context:"join" glue
             @ List.concat_map inputs ~f:(fun e -> resolve_and_check env ~context:"join" e) in
    (declare_cvar env out.name, errs)
  | Ystr_find { string; substring; out; _ } ->
    let errs = resolve_and_check env ~context:"find" string
             @ resolve_and_check env ~context:"find" substring in
    (declare_cvar env out.name, errs)
  | Ystr_substring { string; out; _ } ->
    let errs = resolve_and_check env ~context:"substring" string in
    (declare_cvar env out.name, errs)
  | Ystr_repeat { string; out; _ } ->
    let errs = resolve_and_check env ~context:"repeat" string in
    (declare_cvar env out.name, errs)
  | Ystr_genex_strip { string; out } ->
    let errs = resolve_and_check env ~context:"genex_strip" string in
    (declare_cvar env out.name, errs)
  | Ystr_compare { string1; string2; out; _ } ->
    let errs = resolve_and_check env ~context:"compare" string1
             @ resolve_and_check env ~context:"compare" string2 in
    (declare_cvar env out.name, errs)
  | Ystr_make_c_identifier { string; out } ->
    let errs = resolve_and_check env ~context:"make_c_identifier" string in
    (declare_cvar env out.name, errs)
  | Ystr_timestamp { out; _ } -> (declare_cvar env out.name, [])
  | Ystr_hex { string; out } ->
    let errs = resolve_and_check env ~context:"hex" string in
    (declare_cvar env out.name, errs)
  | Ystr_uuid { out; _ } -> (declare_cvar env out.name, [])
  | Ystr_json { out; error_var; op } ->
    let op_errs = check_json_op env op in
    let env = declare_cvar env out.name in
    let env = Option.value_map error_var ~default:env ~f:(fun v -> declare_cvar env v.name) in
    (env, op_errs)

and check_list_stmt env : yelu_list_stmt -> env * error list = function
  | Ylist_append { cvar; values } ->
    let errs = check_cvar_refs env ~context:"list_append" (cvar_name_of_tcname cvar)
             @ List.concat_map values ~f:(fun e -> resolve_and_check env ~context:"list_append" e) in
    (env, errs)
  | Ylist_length { cvar; out } ->
    let errs = check_cvar_refs env ~context:"list_length" (cvar_name_of_tcname cvar) in
    (declare_cvar env out.name, errs)
  | Ylist_get { cvar; out; _ } ->
    let errs = check_cvar_refs env ~context:"list_get" (cvar_name_of_tcname cvar) in
    (declare_cvar env out.name, errs)
  | Ylist_remove_item { cvar; values } ->
    let errs = check_cvar_refs env ~context:"list_remove_item" (cvar_name_of_tcname cvar)
             @ List.concat_map values ~f:(fun e -> resolve_and_check env ~context:"list_remove_item" e) in
    (env, errs)
  | Ylist_remove_duplicates { cvar } | Ylist_reverse { cvar } | Ylist_remove_at { cvar; _ } ->
    let errs = check_cvar_refs env ~context:"list_op" (cvar_name_of_tcname cvar) in
    (env, errs)
  | Ylist_sort { cvar; _ } ->
    let errs = check_cvar_refs env ~context:"list_sort" (cvar_name_of_tcname cvar) in
    (env, errs)
  | Ylist_filter { cvar; _ } ->
    let errs = check_cvar_refs env ~context:"list_filter" (cvar_name_of_tcname cvar) in
    (env, errs)
  | Ylist_join { cvar; glue; out } ->
    let errs = check_cvar_refs env ~context:"list_join" (cvar_name_of_tcname cvar)
             @ resolve_and_check env ~context:"list_join" glue in
    (declare_cvar env out.name, errs)
  | Ylist_sublist { cvar; out; _ } ->
    let errs = check_cvar_refs env ~context:"list_sublist" (cvar_name_of_tcname cvar) in
    (declare_cvar env out.name, errs)
  | Ylist_find { cvar; value; out } ->
    let errs = check_cvar_refs env ~context:"list_find" (cvar_name_of_tcname cvar)
             @ resolve_and_check env ~context:"list_find" value in
    (declare_cvar env out.name, errs)
  | Ylist_prepend { cvar; values } ->
    let errs = check_cvar_refs env ~context:"list_prepend" (cvar_name_of_tcname cvar)
             @ List.concat_map values ~f:(fun e -> resolve_and_check env ~context:"list_prepend" e) in
    (env, errs)
  | Ylist_insert { cvar; values; _ } ->
    let errs = check_cvar_refs env ~context:"list_insert" (cvar_name_of_tcname cvar)
             @ List.concat_map values ~f:(fun e -> resolve_and_check env ~context:"list_insert" e) in
    (env, errs)
  | Ylist_pop_back { cvar; out_vars } ->
    let errs = check_cvar_refs env ~context:"list_pop_back" (cvar_name_of_tcname cvar) in
    (add_cvars env (List.map out_vars ~f:(fun v -> v.name)), errs)
  | Ylist_pop_front { cvar; out_vars } ->
    let errs = check_cvar_refs env ~context:"list_pop_front" (cvar_name_of_tcname cvar) in
    (add_cvars env (List.map out_vars ~f:(fun v -> v.name)), errs)
  | Ylist_transform { cvar; output; _ } ->
    let errs = check_cvar_refs env ~context:"list_transform" (cvar_name_of_tcname cvar) in
    let env = Option.value_map output ~default:env ~f:(fun v -> declare_cvar env v.name) in
    (env, errs)

and check_file_stmt env : yelu_file_io_stmt -> env * error list = function
  | Yfile_read { out; file; _ } ->
    let errs = resolve_and_check env ~context:"file_read" file in
    (declare_cvar env out.name, errs)
  | Yfile_write { file; content; _ } ->
    let errs = resolve_and_check env ~context:"file_write" file
             @ List.concat_map content ~f:(fun e -> resolve_and_check env ~context:"file_write" e) in
    (env, errs)
  | Yfile_strings { out; file; _ } ->
    let errs = resolve_and_check env ~context:"file_strings" file in
    (declare_cvar env out.name, errs)
  | Yfile_touch { files; _ } ->
    let errs = List.concat_map files ~f:(fun e -> resolve_and_check env ~context:"file_touch" e) in
    (env, errs)
  | Yfile_make_directory { dirs } ->
    let errs = List.concat_map dirs ~f:(fun e -> resolve_and_check env ~context:"file_make_directory" e) in
    (env, errs)
  | Yfile_rename { old_; new_; result; _ } ->
    let errs = resolve_and_check env ~context:"file_rename" old_
             @ resolve_and_check env ~context:"file_rename" new_ in
    let env = Option.value_map result ~default:env ~f:(fun v -> declare_cvar env v.name) in
    (env, errs)
  | Yfile_remove { files; _ } ->
    let errs = List.concat_map files ~f:(fun e -> resolve_and_check env ~context:"file_remove" e) in
    (env, errs)
  | Yfile_copy { input; output; result; _ } ->
    let errs = resolve_and_check env ~context:"file_copy" input
             @ resolve_and_check env ~context:"file_copy" output in
    let env = Option.value_map result ~default:env ~f:(fun v -> declare_cvar env v.name) in
    (env, errs)
  | Yfile_real_path { out; path; base_dir; _ } ->
    let errs = resolve_and_check env ~context:"file_real_path" path
             @ Option.value_map base_dir ~default:[]
                 ~f:(fun e -> resolve_and_check env ~context:"file_real_path" e) in
    (declare_cvar env out.name, errs)
  | Yfile_size { out; file } ->
    let errs = resolve_and_check env ~context:"file_size" file in
    (declare_cvar env out.name, errs)
  | Yfile_read_symlink { out; link } ->
    let errs = resolve_and_check env ~context:"file_read_symlink" link in
    (declare_cvar env out.name, errs)
  | Yfile_timestamp { out; file; _ } ->
    let errs = resolve_and_check env ~context:"file_timestamp" file in
    (declare_cvar env out.name, errs)
  | Yfile_relative_path { var; base; file } ->
    let errs = resolve_and_check env ~context:"file_relative_path" var
             @ resolve_and_check env ~context:"file_relative_path" base
             @ resolve_and_check env ~context:"file_relative_path" file in
    (env, errs)
  | Yfile_glob { out; relative; patterns; _ } ->
    let errs = Option.value_map relative ~default:[]
                 ~f:(fun e -> resolve_and_check env ~context:"file_glob" e)
             @ List.concat_map patterns ~f:(fun e -> resolve_and_check env ~context:"file_glob" e) in
    (declare_cvar env out.name, errs)
  | Yfile_configure { input; output } ->
    let errs = resolve_and_check env ~context:"file_configure" input
             @ resolve_and_check env ~context:"file_configure" output in
    (env, errs)

and check_path_stmt env : yelu_path_stmt -> env * error list = function
  | Ypath_get { path_var; out; _ } ->
    let errs = check_cvar_refs env ~context:"path_get" (cvar_name_of_tcname path_var) in
    (declare_cvar env out.name, errs)
  | Ypath_has { path_var; out; _ } ->
    let errs = check_cvar_refs env ~context:"path_has" (cvar_name_of_tcname path_var) in
    (declare_cvar env out.name, errs)
  | Ypath_is_absolute { path_var; out } | Ypath_is_relative { path_var; out } ->
    let errs = check_cvar_refs env ~context:"path_is" (cvar_name_of_tcname path_var) in
    (declare_cvar env out.name, errs)
  | Ypath_is_prefix { path_var; input; out; _ } ->
    let errs = check_cvar_refs env ~context:"path_is_prefix" (cvar_name_of_tcname path_var)
             @ resolve_and_check env ~context:"path_is_prefix" input in
    (declare_cvar env out.name, errs)
  | Ypath_compare { input1; input2; out; _ } ->
    let errs = resolve_and_check env ~context:"path_compare" input1
             @ resolve_and_check env ~context:"path_compare" input2 in
    (declare_cvar env out.name, errs)
  | Ypath_set { path_var; input; _ } ->
    let errs = check_cvar_refs env ~context:"path_set" (cvar_name_of_tcname path_var)
             @ resolve_and_check env ~context:"path_set" input in
    (env, errs)
  | Ypath_append { path_var; inputs; out } ->
    let errs = check_cvar_refs env ~context:"path_append" (cvar_name_of_tcname path_var)
             @ List.concat_map inputs ~f:(fun e -> resolve_and_check env ~context:"path_append" e) in
    let env = Option.value_map out ~default:env ~f:(fun v -> declare_cvar env v.name) in
    (env, errs)
  | Ypath_append_string { path_var; inputs; out } ->
    let errs = check_cvar_refs env ~context:"path_append_string" (cvar_name_of_tcname path_var)
             @ List.concat_map inputs ~f:(fun e -> resolve_and_check env ~context:"path_append_string" e) in
    let env = Option.value_map out ~default:env ~f:(fun v -> declare_cvar env v.name) in
    (env, errs)
  | Ypath_remove_filename { path_var; out } ->
    let errs = check_cvar_refs env ~context:"path_remove_filename" (cvar_name_of_tcname path_var) in
    let env = Option.value_map out ~default:env ~f:(fun v -> declare_cvar env v.name) in
    (env, errs)
  | Ypath_replace_filename { path_var; input; out } ->
    let errs = check_cvar_refs env ~context:"path_replace_filename" (cvar_name_of_tcname path_var)
             @ resolve_and_check env ~context:"path_replace_filename" input in
    let env = Option.value_map out ~default:env ~f:(fun v -> declare_cvar env v.name) in
    (env, errs)
  | Ypath_remove_extension { path_var; out; _ } ->
    let errs = check_cvar_refs env ~context:"path_remove_extension" (cvar_name_of_tcname path_var) in
    let env = Option.value_map out ~default:env ~f:(fun v -> declare_cvar env v.name) in
    (env, errs)
  | Ypath_replace_extension { path_var; input; out; _ } ->
    let errs = check_cvar_refs env ~context:"path_replace_extension" (cvar_name_of_tcname path_var)
             @ resolve_and_check env ~context:"path_replace_extension" input in
    let env = Option.value_map out ~default:env ~f:(fun v -> declare_cvar env v.name) in
    (env, errs)
  | Ypath_normal_path { path_var; out } ->
    let errs = check_cvar_refs env ~context:"path_normal" (cvar_name_of_tcname path_var) in
    let env = Option.value_map out ~default:env ~f:(fun v -> declare_cvar env v.name) in
    (env, errs)
  | Ypath_relative_path { path_var; base_dir; out } ->
    let errs = check_cvar_refs env ~context:"path_relative" (cvar_name_of_tcname path_var)
             @ Option.value_map base_dir ~default:[]
                 ~f:(fun e -> resolve_and_check env ~context:"path_relative" e) in
    let env = Option.value_map out ~default:env ~f:(fun v -> declare_cvar env v.name) in
    (env, errs)
  | Ypath_absolute_path { path_var; base_dir; out; _ } ->
    let errs = check_cvar_refs env ~context:"path_absolute" (cvar_name_of_tcname path_var)
             @ Option.value_map base_dir ~default:[]
                 ~f:(fun e -> resolve_and_check env ~context:"path_absolute" e) in
    let env = Option.value_map out ~default:env ~f:(fun v -> declare_cvar env v.name) in
    (env, errs)
  | Ypath_native_path { path_var; out; _ } ->
    let errs = check_cvar_refs env ~context:"path_native" (cvar_name_of_tcname path_var) in
    (declare_cvar env out.name, errs)
  | Ypath_convert_to_cmake { input; out; _ } ->
    let errs = resolve_and_check env ~context:"convert_to_cmake" input in
    (declare_cvar env out.name, errs)
  | Ypath_convert_to_native { input; out; _ } ->
    let errs = resolve_and_check env ~context:"convert_to_native" input in
    (declare_cvar env out.name, errs)
  | Ypath_hash { path_var; out } ->
    let errs = check_cvar_refs env ~context:"path_hash" (cvar_name_of_tcname path_var) in
    (declare_cvar env out.name, errs)
  | Ypath_get_filename_component { var; filename; _ } ->
    let errs = resolve_and_check env ~context:"get_filename_component" filename in
    (declare_cvar env var.name, errs)

and check_target_stmt env : yelu_target_stmt -> env * error list = function
  | Ytgt_add_executable { name; sources; _ } ->
    (* name is being declared, not referenced — only check cvar refs *)
    let resolved = resolve env name in
    let errs = check_cvar_refs env ~context:"add_executable" (cvar_refs_of_expr resolved)
             @ List.concat_map sources ~f:(fun e -> resolve_and_check env ~context:"add_executable" e) in
    (try_declare_target env name, errs)
  | Ytgt_add_library { name; sources; _ } ->
    let resolved = resolve env name in
    let errs = check_cvar_refs env ~context:"add_library" (cvar_refs_of_expr resolved)
             @ List.concat_map sources ~f:(fun e -> resolve_and_check env ~context:"add_library" e) in
    (try_declare_target env name, errs)
  | Ytgt_add_library_imported { name; _ } ->
    let resolved = resolve env name in
    let errs = check_cvar_refs env ~context:"add_library_imported" (cvar_refs_of_expr resolved) in
    (try_declare_target env name, errs)
  | Ytgt_add_library_alias _ | Ytgt_add_executable_alias _ -> (env, [])
  | Ytgt_include_directories { target; items; _ } ->
    let errs = resolve_and_check env ~context:"include_directories" target
             @ List.concat_map items ~f:(fun { items; _ } ->
                 List.concat_map items ~f:(fun e -> resolve_and_check env ~context:"include_directories" e)) in
    (env, errs)
  | Ytgt_link_libraries { targets; items } ->
    let errs = List.concat_map targets ~f:(fun t -> resolve_and_check env ~context:"link_libraries" t)
             @ List.concat_map items ~f:(fun { items; _ } ->
                 List.concat_map items ~f:(fun e -> resolve_and_check env ~context:"link_libraries" e)) in
    (env, errs)
  | Ytgt_compile_definitions { target; items } ->
    let errs = resolve_and_check env ~context:"compile_definitions" target
             @ List.concat_map items ~f:(fun { items; _ } ->
                 List.concat_map items ~f:(fun e -> resolve_and_check env ~context:"compile_definitions" e)) in
    (env, errs)
  | Ytgt_compile_features { target; _ } ->
    let errs = resolve_and_check env ~context:"compile_features" target in
    (env, errs)
  | Ytgt_compile_options { target; items; _ } ->
    let errs = resolve_and_check env ~context:"compile_options" target
             @ List.concat_map items ~f:(fun { items; _ } ->
                 List.concat_map items ~f:(fun e -> resolve_and_check env ~context:"compile_options" e)) in
    (env, errs)
  | Ytgt_link_options { target; items; _ } ->
    let errs = resolve_and_check env ~context:"link_options" target
             @ List.concat_map items ~f:(fun { items; _ } ->
                 List.concat_map items ~f:(fun e -> resolve_and_check env ~context:"link_options" e)) in
    (env, errs)
  | Ytgt_link_directories { target; items; _ } ->
    let errs = resolve_and_check env ~context:"link_directories" target
             @ List.concat_map items ~f:(fun { items; _ } ->
                 List.concat_map items ~f:(fun e -> resolve_and_check env ~context:"link_directories" e)) in
    (env, errs)
  | Ytgt_sources { target; items } ->
    let errs = resolve_and_check env ~context:"target_sources" target
             @ List.concat_map items ~f:(fun { items; _ } ->
                 List.concat_map items ~f:(fun e -> resolve_and_check env ~context:"target_sources" e)) in
    (env, errs)
  | Ytgt_sources_fs { target; items } ->
    let errs = resolve_and_check env ~context:"target_sources_fs" target
             @ List.concat_map items ~f:(function
                 | Ytsi_plain { items; _ } ->
                   List.concat_map items ~f:(fun e -> resolve_and_check env ~context:"sources_fs" e)
                 | Ytsi_file_set { base_dirs; files; _ } ->
                   List.concat_map base_dirs ~f:(fun e -> resolve_and_check env ~context:"sources_fs" e)
                   @ List.concat_map files ~f:(fun e -> resolve_and_check env ~context:"sources_fs" e)) in
    (env, errs)
  | Ytgt_precompile_headers { target; items } ->
    let errs = resolve_and_check env ~context:"precompile_headers" target
             @ List.concat_map items ~f:(fun { items; _ } ->
                 List.concat_map items ~f:(fun e -> resolve_and_check env ~context:"precompile_headers" e)) in
    (env, errs)
  | Ytgt_add_custom_command { outputs; depends; _ } ->
    let errs = List.concat_map outputs ~f:(fun e -> resolve_and_check env ~context:"custom_command" e)
             @ List.concat_map depends ~f:(fun e -> resolve_and_check env ~context:"custom_command" e) in
    (env, errs)
  | Ytgt_add_custom_command_target _ -> (env, [])
  | Ytgt_add_custom_target { depends; _ } ->
    let errs = List.concat_map depends ~f:(fun e -> resolve_and_check env ~context:"custom_target" e) in
    (env, errs)
  | Ytgt_add_dependencies _ -> (env, [])

and check_dir_stmt env : yelu_dir_stmt -> env * error list = function
  | Ydir_include_directories { dirs; _ } ->
    let errs = List.concat_map dirs ~f:(fun e -> resolve_and_check env ~context:"include_directories" e) in
    (env, errs)
  | Ydir_add_compile_definitions { defs } ->
    let errs = List.concat_map defs ~f:(fun e -> resolve_and_check env ~context:"add_compile_definitions" e) in
    (env, errs)
  | Ydir_add_compile_options { options } ->
    let errs = List.concat_map options ~f:(fun e -> resolve_and_check env ~context:"add_compile_options" e) in
    (env, errs)
  | Ydir_add_link_options { options } ->
    let errs = List.concat_map options ~f:(fun e -> resolve_and_check env ~context:"add_link_options" e) in
    (env, errs)
  | Ydir_add_definitions { defs } ->
    let errs = List.concat_map defs ~f:(fun e -> resolve_and_check env ~context:"add_definitions" e) in
    (env, errs)
  | Ydir_link_directories { dirs; _ } ->
    let errs = List.concat_map dirs ~f:(fun e -> resolve_and_check env ~context:"link_directories" e) in
    (env, errs)
  | Ydir_add_subdirectory { source_dir } ->
    let errs = resolve_and_check env ~context:"add_subdirectory" source_dir in
    (env, errs)
  | Ydir_link_libraries { items } ->
    let errs = List.concat_map items ~f:(fun e -> resolve_and_check env ~context:"link_libraries" e) in
    (env, errs)

and check_var_stmt env : yelu_var_stmt -> env * error list = function
  | Yvar_set { cvar; values; parent_scope } ->
    let errs = List.concat_map values ~f:(fun e -> resolve_and_check env ~context:"set" e) in
    let env = if parent_scope then env else declare_cvar env cvar.name in
    (env, errs)
  | Yvar_option { cvar; value; _ } ->
    let errs = resolve_and_check env ~context:"option" value in
    (declare_cvar env cvar.name, errs)
  | Yvar_set_cache { cvar; values; _ } ->
    let errs = List.concat_map values ~f:(fun e -> resolve_and_check env ~context:"set_cache" e) in
    (declare_cvar env cvar.name, errs)
  | Yvar_unset_cache _ | Yvar_set_env _ | Yvar_unset_env _ -> (env, [])

and check_property_stmt env : yelu_property_stmt -> env * error list = function
  | Yprop_get { var; target; _ } ->
    let errs = resolve_and_check env ~context:"get_property" target in
    (declare_cvar env var.name, errs)
  | Yprop_get_directory { var; _ } -> (declare_cvar env var.name, [])
  | Yprop_set_directory { values; _ } ->
    let errs = List.concat_map values ~f:(fun e -> resolve_and_check env ~context:"set_directory_property" e) in
    (env, errs)
  | Yprop_set_tests { tests; properties } ->
    let errs = List.concat_map tests ~f:(fun e -> resolve_and_check env ~context:"set_tests_properties" e)
             @ List.concat_map properties ~f:(fun (_, v) -> resolve_and_check env ~context:"set_tests_properties" v) in
    (env, errs)
  | Yprop_set_target { target; properties } ->
    let errs = resolve_and_check env ~context:"set_target_properties" target
             @ List.concat_map properties ~f:(fun (_, v) -> resolve_and_check env ~context:"set_target_properties" v) in
    (env, errs)
  | Yprop_set { targets; properties; _ } ->
    let errs = List.concat_map targets ~f:(fun t -> resolve_and_check env ~context:"set_property" t)
             @ List.concat_map properties ~f:(fun (_, v) -> resolve_and_check env ~context:"set_property" v) in
    (env, errs)
  | Yprop_set_source { file; values; _ } ->
    let errs = resolve_and_check env ~context:"set_source_property" file
             @ List.concat_map values ~f:(fun e -> resolve_and_check env ~context:"set_source_property" e) in
    (env, errs)
  | Yprop_set_global { properties } ->
    let errs = List.concat_map properties ~f:(fun (_, v) -> resolve_and_check env ~context:"set_global_property" v) in
    (env, errs)
  | Yprop_get_global { var; _ } -> (declare_cvar env var.name, [])
  | Yprop_get_target { var; _ } -> (declare_cvar env var.name, [])
  | Yprop_define _ -> (env, [])

and check_find_stmt env : yelu_find_stmt -> env * error list = function
  | Yfind_library { cvar; names; paths; hints; _ }
  | Yfind_path { cvar; names; paths; hints; _ }
  | Yfind_program { cvar; names; paths; hints; _ }
  | Yfind_file { cvar; names; paths; hints; _ } ->
    let errs = List.concat_map names ~f:(fun e -> resolve_and_check env ~context:"find" e)
             @ List.concat_map paths ~f:(fun e -> resolve_and_check env ~context:"find" e)
             @ List.concat_map hints ~f:(fun e -> resolve_and_check env ~context:"find" e) in
    (declare_cvar env cvar.name, errs)
  | Yfind_package _ -> (env, [])

and check_install_stmt env : yelu_install_stmt -> env * error list = function
  | Yinstall_targets { targets; destination; export } ->
    let errs = List.concat_map targets ~f:(fun t -> resolve_and_check env ~context:"install" t)
             @ resolve_and_check env ~context:"install" destination
             @ Option.value_map export ~default:[] ~f:(fun e -> resolve_and_check env ~context:"install" e) in
    (env, errs)
  | Yinstall_files { files; destination } ->
    let errs = List.concat_map files ~f:(fun f -> resolve_and_check env ~context:"install" f)
             @ resolve_and_check env ~context:"install" destination in
    (env, errs)
  | Yinstall_export { file; export; destination; _ } ->
    let errs = Option.value_map file ~default:[] ~f:(fun e -> resolve_and_check env ~context:"install" e)
             @ resolve_and_check env ~context:"install" export
             @ resolve_and_check env ~context:"install" destination in
    (env, errs)
  | Yinstall_export_export { name; file } ->
    let errs = resolve_and_check env ~context:"export" name
             @ Option.value_map file ~default:[] ~f:(fun e -> resolve_and_check env ~context:"export" e) in
    (env, errs)
  | Yinstall_configure_package_config_file { install_dest; input; output; _ } ->
    let errs = resolve_and_check env ~context:"config_file" install_dest
             @ resolve_and_check env ~context:"config_file" input
             @ resolve_and_check env ~context:"config_file" output in
    (env, errs)
  | Yinstall_write_basic_package_version_file { file; version; _ } ->
    let errs = resolve_and_check env ~context:"version_file" file
             @ Option.value_map version ~default:[] ~f:(fun e -> resolve_and_check env ~context:"version" e) in
    (env, errs)

and check_test_stmt env : yelu_test_stmt -> env * error list = function
  | Ytest_enable_testing -> (env, [])
  | Ytest_add_test { name; command; args } ->
    let errs = resolve_and_check env ~context:"add_test" name
             @ resolve_and_check env ~context:"add_test" command
             @ List.concat_map args ~f:(fun e -> resolve_and_check env ~context:"add_test" e) in
    (env, errs)

and check_try_stmt env : yelu_try_stmt -> env * error list = function
  | Ytry_compile { result_var; sources; compile_definitions; link_libraries;
                   link_options; output_variable; _ } ->
    let errs = List.concat_map sources ~f:(fun e -> resolve_and_check env ~context:"try_compile" e)
             @ List.concat_map compile_definitions ~f:(fun e -> resolve_and_check env ~context:"try_compile" e)
             @ List.concat_map link_libraries ~f:(fun e -> resolve_and_check env ~context:"try_compile" e)
             @ List.concat_map link_options ~f:(fun e -> resolve_and_check env ~context:"try_compile" e) in
    let env = declare_cvar env result_var.name in
    let env = Option.value_map output_variable ~default:env ~f:(fun v -> declare_cvar env v.name) in
    (env, errs)
  | Ytry_run { run_result_var; compile_result_var; sources; compile_definitions;
               link_libraries; compile_output_variable; run_output_variable; args } ->
    let errs = List.concat_map sources ~f:(fun e -> resolve_and_check env ~context:"try_run" e)
             @ List.concat_map compile_definitions ~f:(fun e -> resolve_and_check env ~context:"try_run" e)
             @ List.concat_map link_libraries ~f:(fun e -> resolve_and_check env ~context:"try_run" e)
             @ List.concat_map args ~f:(fun e -> resolve_and_check env ~context:"try_run" e) in
    let env = declare_cvar env run_result_var.name in
    let env = declare_cvar env compile_result_var.name in
    let env = Option.value_map compile_output_variable ~default:env ~f:(fun v -> declare_cvar env v.name) in
    let env = Option.value_map run_output_variable ~default:env ~f:(fun v -> declare_cvar env v.name) in
    (env, errs)

and check_cmake_stmt env : yelu_cmake_stmt -> env * error list = function
  | Ycmake_minimum_required _ | Ycmake_project _ | Ycmake_enable_language _
  | Ycmake_policy_set _ | Ycmake_include_guard _ | Ycmake_message _
  | Ycmake_quote_cmd _ | Ycmake_at_var _ -> (env, [])
  | Ycmake_language_call { args; _ } ->
    let errs = List.concat_map args ~f:(fun e -> resolve_and_check env ~context:"language_call" e) in
    (env, errs)
  | Ycmake_language_eval _ -> (env, [])
  | Ycmake_language_get_log_level { out } -> (declare_cvar env out.name, [])
  | Ycmake_math { out; _ } -> (declare_cvar env out.name, [])
  | Ycmake_variable_watch _ -> (env, [])
  | Ycmake_execute_process { commands; working_directory; result_variable;
                              output_variable; error_variable;
                              input_file; output_file; error_file; _ } ->
    let errs = List.concat_map commands ~f:(fun cmd ->
                 List.concat_map cmd ~f:(fun e -> resolve_and_check env ~context:"execute_process" e))
             @ Option.value_map working_directory ~default:[]
                 ~f:(fun e -> resolve_and_check env ~context:"execute_process" e)
             @ Option.value_map input_file ~default:[]
                 ~f:(fun e -> resolve_and_check env ~context:"execute_process" e)
             @ Option.value_map output_file ~default:[]
                 ~f:(fun e -> resolve_and_check env ~context:"execute_process" e)
             @ Option.value_map error_file ~default:[]
                 ~f:(fun e -> resolve_and_check env ~context:"execute_process" e) in
    let env = Option.value_map result_variable ~default:env ~f:(fun v -> declare_cvar env v.name) in
    let env = Option.value_map output_variable ~default:env ~f:(fun v -> declare_cvar env v.name) in
    let env = Option.value_map error_variable ~default:env ~f:(fun v -> declare_cvar env v.name) in
    (env, errs)

(* ============================================================
   Top-level entry points
   ============================================================ *)

let rec check_stmt (env : env) : yelu_stmt -> env * error list = function
  | Ys_string s -> check_string_stmt env s
  | Ys_list s -> check_list_stmt env s
  | Ys_file s -> check_file_stmt env s
  | Ys_path s -> check_path_stmt env s
  | Ys_target s -> check_target_stmt env s
  | Ys_dir s -> check_dir_stmt env s
  | Ys_var s -> check_var_stmt env s
  | Ys_property s -> check_property_stmt env s
  | Ys_find s -> check_find_stmt env s
  | Ys_install s -> check_install_stmt env s
  | Ys_test s -> check_test_stmt env s
  | Ys_try s -> check_try_stmt env s
  | Ys_cmake s -> check_cmake_stmt env s
  | Ylet { var = Yvar name; value } ->
    let resolved = resolve env value in
    let env = { env with bindings = Map.set env.bindings ~key:name ~data:resolved } in
    (env, [])
  | Yif { cond; then_; else_ } ->
    let cond_errs = check_cvar_refs env ~context:"if" (cvar_refs_of_cond cond)
                  @ check_target_refs env ~context:"if" (target_refs_of_cond cond) in
    let then_env, then_errs = check_stmt env then_ in
    let else_env, else_errs =
      Option.value_map else_ ~default:(env, []) ~f:(check_stmt env) in
    let env =
      { env with
        cvars = Set.union then_env.cvars else_env.cvars;
        targets = Set.union then_env.targets else_env.targets } in
    (env, cond_errs @ then_errs @ else_errs)
  | Ystmt_list stmts -> check_stmts env stmts
  (* scripting *)
  | Yc_include { file; _ } ->
    let errs = resolve_and_check env ~context:"include" file in
    (env, errs)
  | Yc_function { name; args; body } ->
    let name_errs = resolve_and_check env ~context:"function" name in
    let body_env = add_cvars env args in
    let _, body_errs = check_stmts body_env body in
    (env, name_errs @ body_errs)
  | Yc_macro { name; args; body } ->
    let name_errs = resolve_and_check env ~context:"macro" name in
    let body_env = add_cvars env args in
    let _, body_errs = check_stmts body_env body in
    (env, name_errs @ body_errs)
  | Yc_apply { name; args } ->
    let errs = resolve_and_check env ~context:"apply" name
             @ List.concat_map args ~f:(fun a -> resolve_and_check env ~context:"apply" a) in
    (env, errs)
  | Yc_separate_arguments { cvar; input; _ } ->
    let errs = check_cvar_refs env ~context:"separate_arguments" (cvar_name_of_tcname cvar)
             @ Option.value_map input ~default:[]
                 ~f:(fun e -> resolve_and_check env ~context:"separate_arguments" e) in
    (declare_cvar env cvar.name, errs)
  | Yc_extern_cvar v -> (declare_cvar env v.name, [])
  | Yc_extern_target t -> (declare_target env t.name, [])
  (* control flow *)
  | Yc_foreach { loop_var; items; commands } ->
    let item_errs = List.concat_map items ~f:(fun e -> resolve_and_check env ~context:"foreach" e) in
    let body_env = declare_cvar env loop_var.name in
    let _, body_errs = check_stmt body_env commands in
    (declare_cvar env loop_var.name, item_errs @ body_errs)
  | Yc_foreach_range { loop_var; commands; _ } ->
    let body_env = declare_cvar env loop_var.name in
    let _, body_errs = check_stmt body_env commands in
    (declare_cvar env loop_var.name, body_errs)
  | Yc_foreach_in { loop_var; lists; items; commands } ->
    let item_errs = List.concat_map items ~f:(fun e -> resolve_and_check env ~context:"foreach_in" e) in
    let list_errs = check_cvar_refs env ~context:"foreach_in"
                      (List.concat_map lists ~f:cvar_name_of_tcname) in
    let body_env = declare_cvar env loop_var.name in
    let _, body_errs = check_stmt body_env commands in
    (declare_cvar env loop_var.name, item_errs @ list_errs @ body_errs)
  | Yc_foreach_zip { loop_vars; lists; commands } ->
    let list_errs = check_cvar_refs env ~context:"foreach_zip"
                      (List.concat_map lists ~f:cvar_name_of_tcname) in
    let body_env = add_cvars env (List.map loop_vars ~f:(fun v -> v.name)) in
    let _, body_errs = check_stmt body_env commands in
    let env = add_cvars env (List.map loop_vars ~f:(fun v -> v.name)) in
    (env, list_errs @ body_errs)
  | Yc_while { cond; commands } ->
    let cond_errs = check_cvar_refs env ~context:"while" (cvar_refs_of_cond cond)
                  @ check_target_refs env ~context:"while" (target_refs_of_cond cond) in
    let _, body_errs = check_stmt env commands in
    (env, cond_errs @ body_errs)
  | Yc_break | Yc_continue | Yc_return _ -> (env, [])
  | Yc_block { scope_vars; body; _ } ->
    let body_env = add_cvars env (List.map scope_vars ~f:(fun v -> v.name)) in
    let _, body_errs = check_stmts body_env body in
    (env, body_errs)

and check_stmts env stmts =
  List.fold stmts ~init:(env, []) ~f:(fun (e, errs) s ->
      let e', new_errs = check_stmt e s in
      (e', errs @ new_errs))
