open Base
open Lang_yelu_type

module Make_install_op (T : LANG_TYPES) = struct
  type yelu_install_stmt =
    | Yinstall_targets of {
        targets : T.expr list;
        destination : T.expr;
        export : T.expr option;
      }
    | Yinstall_files of { files : T.expr list; destination : T.expr }
    | Yinstall_export of {
        file : T.expr option;
        export : T.expr;
        destination : T.expr;
        namespace : string option;
      }
    | Yinstall_export_export of { name : T.expr; file : T.expr option }
    | Yinstall_configure_package_config_file of {
        install_dest : T.expr;
        input : T.expr;
        output : T.expr;
        no_set_and_check_macro : bool;
        no_check_required_components_macro : bool;
      }
    | Yinstall_write_basic_package_version_file of {
        file : T.expr;
        version : T.expr option;
        compatibility : Lang_cmake.compatibility;
        arch_independent : bool;
      }
end

module Make_install_check (T : LANG_TYPES) = struct
  include Make_install_op (T)
  let stage = Stage_typecheck

  let check ~(type_of : T.expr -> yelu_type) : yelu_install_stmt -> type_error list =
    let path e ctx = check_compat ~context:ctx Ty_path (type_of e) in
    let opt_path e ctx = Option.value_map e ~default:[] ~f:(fun x -> path x ctx) in
    function
    | Yinstall_targets { targets; destination; export } ->
      List.concat_map targets ~f:(fun t ->
        check_compat ~context:"install targets" Ty_target (type_of t))
      @ path destination "install destination"
      @ opt_path export "install export"
    | Yinstall_files { files; destination } ->
      List.concat_map files ~f:(fun f -> path f "install files")
      @ path destination "install destination"
    | Yinstall_export { file; export; destination; _ } ->
      opt_path file "install export file"
      @ check_compat ~context:"install export name" Ty_string (type_of export)
      @ path destination "install destination"
    | Yinstall_export_export { name; file } ->
      check_compat ~context:"export name" Ty_string (type_of name)
      @ opt_path file "export file"
    | Yinstall_configure_package_config_file { install_dest; input; output; _ } ->
      path install_dest "config_file install_dest"
      @ path input "config_file input"
      @ path output "config_file output"
    | Yinstall_write_basic_package_version_file { file; version; _ } ->
      path file "version_file"
      @ Option.value_map version ~default:[]
          ~f:(fun v -> check_compat ~context:"version" Ty_version (type_of v))
end
