open Base
open Lang_yelu_type

module Make_find_op (T : LANG_TYPES) = struct
  type yelu_find_stmt =
    | Yfind_library of {
        cvar : T.var;
        names : T.expr list;
        paths : T.expr list;
        hints : T.expr list;
        no_default_path : bool;
        no_cmake_environment_path : bool;
        no_system_environment_path : bool;
        required : bool;
      }
    | Yfind_path of {
        cvar : T.var;
        names : T.expr list;
        paths : T.expr list;
        hints : T.expr list;
        no_default_path : bool;
        no_cmake_environment_path : bool;
        no_system_environment_path : bool;
        required : bool;
      }
    | Yfind_program of {
        cvar : T.var;
        names : T.expr list;
        paths : T.expr list;
        hints : T.expr list;
        no_default_path : bool;
        no_cmake_environment_path : bool;
        no_system_environment_path : bool;
        required : bool;
      }
    | Yfind_file of {
        cvar : T.var;
        names : T.expr list;
        paths : T.expr list;
        hints : T.expr list;
        no_default_path : bool;
        no_cmake_environment_path : bool;
        no_system_environment_path : bool;
        required : bool;
      }
    (* find_package sets implicit variables (<Name>_FOUND, <Name>_INCLUDE_DIRS, etc.)
       that are not representable as a single typed output — see yelu_typed_design.md *)
    | Yfind_package of {
        name : string;
        version : string option;
        exact : bool;
        quiet : bool;
        config_mode : bool;
        required : bool;
        components : string list;
        optional_components : string list;
      }
end

module Make_find_check (T : LANG_TYPES) = struct
  include Make_find_op (T)
  let stage = Stage_typecheck

  (* find_{library,path,program,file}: names are strings, paths/hints are Ty_path,
     result cvar gets Ty_path (holds the found path or <NAME>-NOTFOUND).
     find_package: no typed output — implicit variables not modelled here. *)
  let check ~(type_of : T.expr -> yelu_type)
      : yelu_find_stmt -> type_error list * (T.var * yelu_type) list =
    let strs es ctx = List.concat_map es ~f:(fun e -> check_compat ~context:ctx Ty_string (type_of e)) in
    let paths_ es ctx = List.concat_map es ~f:(fun e -> check_compat ~context:ctx Ty_path (type_of e)) in
    let find4 cvar names paths hints =
      strs names "find names" @ paths_ paths "find paths" @ paths_ hints "find hints",
      [(cvar, Ty_path)]
    in
    function
    | Yfind_library { cvar; names; paths; hints; _ } -> find4 cvar names paths hints
    | Yfind_path { cvar; names; paths; hints; _ } -> find4 cvar names paths hints
    | Yfind_program { cvar; names; paths; hints; _ } -> find4 cvar names paths hints
    | Yfind_file { cvar; names; paths; hints; _ } -> find4 cvar names paths hints
    | Yfind_package _ -> [], []
end
