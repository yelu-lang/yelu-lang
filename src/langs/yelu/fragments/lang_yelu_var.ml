open Base
open Lang_yelu_type

module Make_var_op (T : LANG_TYPES) = struct
  type yelu_var_stmt =
    (* Variable namespace: set(), if(DEFINED), ${} *)
    | Yvar_set of { cvar : T.var; values : T.expr list; parent_scope : bool }
    | Yvar_option of { cvar : T.var; msg : string; value : T.expr }
    | Yvar_set_cache of {
        cvar : T.var;
        values : T.expr list;
        cache_type : Lang_cmake.cache_type;
        docstring : string;
        force : bool;
      }
    | Yvar_unset_cache of { cvar : T.var }
    (* Env namespace: $ENV{}, set(ENV{}) *)
    | Yvar_set_env of { var : string; value : T.expr }
    | Yvar_unset_env of { var : string }
end

module Make_var_check (T : LANG_TYPES) = struct
  include Make_var_op (T)
  let stage = Stage_typecheck

  let cache_type_to_yelu_type = function
    | Lang_cmake.Ct_bool -> Ty_bool
    | Lang_cmake.Ct_path | Lang_cmake.Ct_filepath -> Ty_path
    | Lang_cmake.Ct_string | Lang_cmake.Ct_internal -> Ty_string

  let check ~(type_of : T.expr -> yelu_type)
      : yelu_var_stmt -> type_error list * (T.var * yelu_type) list =
    let strs es ctx =
      List.concat_map es ~f:(fun e -> check_compat ~context:ctx Ty_string (type_of e))
    in
    function
    | Yvar_set { cvar; values; _ } ->
      strs values "var_set", [(cvar, Ty_string)]
    | Yvar_option { cvar; value; _ } ->
      check_compat ~context:"option" Ty_bool (type_of value), [(cvar, Ty_bool)]
    | Yvar_set_cache { cvar; values; cache_type; _ } ->
      strs values "set_cache", [(cvar, cache_type_to_yelu_type cache_type)]
    | _ -> [], []
end
