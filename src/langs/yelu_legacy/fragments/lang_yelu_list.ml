open Base
open Lang_yelu_type

module Make_list_op (T : LANG_TYPES) = struct
  type yelu_list_stmt =
    | Ylist_append of { cvar : T.var; values : T.expr list }
    | Ylist_length of { cvar : T.var; out : T.var }
    | Ylist_get of { cvar : T.var; indices : int list; out : T.var }
    | Ylist_remove_item of { cvar : T.var; values : T.expr list }
    | Ylist_remove_duplicates of { cvar : T.var }
    | Ylist_reverse of { cvar : T.var }
    | Ylist_sort of {
        cvar : T.var;
        order : Lang_cmake.list_sort_order option;
        compare : Lang_cmake.list_sort_compare option;
        case : Lang_cmake.list_sort_case option;
      }
    | Ylist_filter of {
        cvar : T.var;
        mode : Lang_cmake.list_filter_mode;
        regex : string;
      }
    | Ylist_join of { cvar : T.var; glue : T.expr; out : T.var }
    | Ylist_sublist of { cvar : T.var; begin_ : int; length : int; out : T.var }
    | Ylist_find of { cvar : T.var; value : T.expr; out : T.var }
    | Ylist_prepend of { cvar : T.var; values : T.expr list }
    | Ylist_insert of { cvar : T.var; index : int; values : T.expr list }
    | Ylist_remove_at of { cvar : T.var; indices : int list }
    | Ylist_pop_back of { cvar : T.var; out_vars : T.var list }
    | Ylist_pop_front of { cvar : T.var; out_vars : T.var list }
    | Ylist_transform of {
        cvar : T.var;
        action : Lang_cmake.list_transform_action;
        selector : Lang_cmake.list_transform_selector option;
        output : T.var option;
      }
end

module Make_list_check (T : LANG_TYPES) = struct
  include Make_list_op (T)
  let stage = Stage_typecheck

  (* cvar inputs are T.var, not T.expr — they cannot be checked via type_of.
     Only T.expr inputs (values, glue, value) and output vars are typed here.
     Ylist_transform: output→Ty_list Ty_any when present; transform semantics deferred.
     See yelu_typed_design.md for the cvar-as-T.var checker-extension design question. *)
  let check ~(type_of : T.expr -> yelu_type)
      : yelu_list_stmt -> type_error list * (T.var * yelu_type) list =
    let strs es ctx = List.concat_map es ~f:(fun e -> check_compat ~context:ctx Ty_string (type_of e)) in
    function
    | Ylist_append { values; _ } | Ylist_remove_item { values; _ }
    | Ylist_prepend { values; _ } | Ylist_insert { values; _ } ->
      strs values "list values", []
    | Ylist_length { out; _ } -> [], [(out, Ty_int)]
    | Ylist_get { out; _ } -> [], [(out, Ty_string)]
    | Ylist_join { glue; out; _ } ->
      check_compat ~context:"list_join glue" Ty_string (type_of glue), [(out, Ty_string)]
    | Ylist_sublist { out; _ } -> [], [(out, Ty_list Ty_any)]
    | Ylist_find { value; out; _ } ->
      check_compat ~context:"list_find value" Ty_string (type_of value), [(out, Ty_int)]
    | Ylist_pop_back { out_vars; _ } | Ylist_pop_front { out_vars; _ } ->
      [], List.map out_vars ~f:(fun v -> (v, Ty_string))
    | Ylist_transform { output; _ } ->
      [], Option.to_list (Option.map output ~f:(fun v -> (v, Ty_list Ty_any)))
    | Ylist_remove_duplicates _ | Ylist_reverse _ | Ylist_sort _
    | Ylist_filter _ | Ylist_remove_at _ -> [], []
end
