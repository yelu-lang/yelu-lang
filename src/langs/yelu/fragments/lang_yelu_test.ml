open Base
open Lang_yelu_type

module Make_test_op (T : LANG_TYPES) = struct
  type yelu_test_stmt =
    | Ytest_enable_testing
    | Ytest_add_test of { name : T.expr; command : T.expr; args : T.expr list }
end

module Make_test_check (T : LANG_TYPES) = struct
  include Make_test_op (T)
  let stage = Stage_typecheck

  let check ~(type_of : T.expr -> yelu_type) : yelu_test_stmt -> type_error list = function
    | Ytest_enable_testing -> []
    | Ytest_add_test { name; command; args } ->
      check_compat ~context:"add_test name" Ty_string (type_of name)
      @ check_compat ~context:"add_test command" Ty_string (type_of command)
      @ List.concat_map args ~f:(fun a -> check_compat ~context:"add_test arg" Ty_string (type_of a))
end
