open Base
open Lang_yelu_type

module Make_property_op (T : LANG_TYPES) = struct
  (* Property namespace: get/set_property, define_property, get/set_target_property, … *)
  (* Property value types are stringly-keyed and dynamic; T.var outputs from get
     operations are not yet tracked (all return Ty_any — see yelu_typed_design.md). *)
  type yelu_property_stmt =
    | Yprop_get of {
        var : T.var;
        target : T.expr;
        property : string;
        set : bool;
      }
    | Yprop_get_directory of { var : T.var; property : string }
    | Yprop_set_directory of {
        property : string;
        append : bool;
        values : T.expr list;
      }
    | Yprop_set_tests of {
        tests : T.expr list;
        properties : (string * T.expr) list;
      }
    | Yprop_set_target of {
        target : T.expr;
        properties : (string * T.expr) list;
      }
    | Yprop_set of {
        targets : T.expr list;
        append : bool;
        properties : (string * T.expr) list;
      }
    | Yprop_set_source of {
        file : T.expr;
        property : string;
        values : T.expr list;
      }
    | Yprop_set_global of { properties : (string * T.expr) list }
    | Yprop_get_global of { var : T.var; property : string }
    | Yprop_get_target of {
        var : T.var;
        target : string;
        property : string;
      }
    | Yprop_define of {
        mode : Lang_cmake.define_property_mode;
        property_name : string;
        inherited : bool;
        brief_docs : string list;
        full_docs : string list;
        initialize_from : string option;
      }
end

module Make_property_check (T : LANG_TYPES) = struct
  include Make_property_op (T)
  let stage = Stage_typecheck

  let check ~(type_of : T.expr -> yelu_type)
      : yelu_property_stmt -> type_error list * (T.var * yelu_type) list =
    ignore type_of;
    (* Property value types are dynamic (stringly-keyed schema);
       deeper typing requires a property registry — see yelu_typed_design.md. *)
    function _ -> [], []
end
