open Base
open Yelu_cmake

type expr +=
  | EList of expr list
  | EListAppend of expr * expr
  | EListGet of expr * expr
  | EListLength of expr

let eval_case ~eval env = function
  | EList exprs ->
    let env, values =
      List.fold exprs ~init:(env, []) ~f:(fun (env, values) expr ->
        let env, value = eval env expr in
        env, value :: values)
    in
    Some (env, VList (List.rev values))
  | EListAppend (list_expr, value_expr) ->
    let env, values = eval env list_expr in
    let env, value = eval env value_expr in
    Some (env, VList (expect_list values @ [ value ]))
  | EListGet (list_expr, index_expr) ->
    let env, values = eval env list_expr in
    let env, index = eval env index_expr in
    (match List.nth (expect_list values) (expect_int index) with
     | Some value -> Some (env, value)
     | None -> fail "list index out of range")
  | EListLength expr ->
    let env, values = eval env expr in
    Some (env, VInt (List.length (expect_list values)))
  | _ -> None
