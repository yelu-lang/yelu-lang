open Base
open Yelu_tiny

let name = "tiny_bool"
let requires = [ "core.bool" ]
let provides = [ "bool.not"; "bool.and"; "bool.or" ]

type expr +=
  | ENot of expr
  | EAnd of expr * expr
  | EOr of expr * expr

let expect_bool = function
  | VBool b -> b
  | v -> fail "expected bool, got %s" (Sexp.to_string ([%sexp_of: value] v))

let eval_bool ~eval env expr =
  let env, value = eval env expr in
  env, expect_bool value

let eval_case ~eval env = function
  | ENot expr ->
    let env, value = eval_bool ~eval env expr in
    Some (env, VBool (not value))
  | EAnd (left, right) ->
    let env, left = eval_bool ~eval env left in
    if not left then Some (env, VBool false)
    else
      let env, right = eval_bool ~eval env right in
      Some (env, VBool right)
  | EOr (left, right) ->
    let env, left = eval_bool ~eval env left in
    if left then Some (env, VBool true)
    else
      let env, right = eval_bool ~eval env right in
      Some (env, VBool right)
  | _ -> None
