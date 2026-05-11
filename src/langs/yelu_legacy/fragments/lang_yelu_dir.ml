open Base
open Lang_yelu_type

module Make_dir_op (T : LANG_TYPES) = struct
  type yelu_dir_stmt =
    | Ydir_include_directories of {
        dirs : T.expr list;
        before : bool;
        system : bool;
      }
    | Ydir_add_compile_definitions of { defs : T.expr list }
    | Ydir_add_compile_options of { options : T.expr list }
    | Ydir_add_link_options of { options : T.expr list }
    | Ydir_add_definitions of { defs : T.expr list }
    | Ydir_link_directories of { before : bool; dirs : T.expr list }
    | Ydir_add_subdirectory of { source_dir : T.expr }
    | Ydir_link_libraries of { items : T.expr list }
end

module Make_dir_check (T : LANG_TYPES) = struct
  include Make_dir_op (T)
  let stage = Stage_typecheck

  let check ~(type_of : T.expr -> yelu_type) : yelu_dir_stmt -> type_error list =
    let paths es ctx = List.concat_map es ~f:(fun e -> check_compat ~context:ctx Ty_path (type_of e)) in
    let strs es ctx = List.concat_map es ~f:(fun e -> check_compat ~context:ctx Ty_string (type_of e)) in
    function
    | Ydir_include_directories { dirs; _ } -> paths dirs "include_directories"
    | Ydir_add_compile_definitions { defs } -> strs defs "add_compile_definitions"
    | Ydir_add_compile_options { options } -> strs options "add_compile_options"
    | Ydir_add_link_options { options } -> strs options "add_link_options"
    | Ydir_add_definitions { defs } -> strs defs "add_definitions"
    | Ydir_link_directories { dirs; _ } -> paths dirs "link_directories"
    | Ydir_add_subdirectory { source_dir } ->
      check_compat ~context:"add_subdirectory" Ty_path (type_of source_dir)
    | Ydir_link_libraries { items = _ } -> []
end
