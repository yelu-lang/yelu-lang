open Base
open Yelu_cmake

let name = "yelu_theory_int"
let requires = [ "core.int" ]
let provides = [ "int.add"; "int.less"; "int.equal" ]

type expr +=
  | EIntAdd of expr * expr
  | EIntLess of expr * expr
  | EIntEqual of expr * expr
  | EIntGreater of expr * expr
  | EIntLessEqual of expr * expr
  | EIntGreaterEqual of expr * expr

let eval_int ~eval env expr =
  let env, value = eval env expr in
  env, expect_int value

let eval_case ~eval env = function
  | EIntAdd (left, right) ->
    let env, left = eval_int ~eval env left in
    let env, right = eval_int ~eval env right in
    Some (env, VInt (left + right))
  | EIntLess (left, right) ->
    let env, left = eval_int ~eval env left in
    let env, right = eval_int ~eval env right in
    Some (env, VBool (left < right))
  | EIntEqual (left, right) ->
    let env, left = eval_int ~eval env left in
    let env, right = eval_int ~eval env right in
    Some (env, VBool (left = right))
  | EIntGreater (left, right) ->
    let env, left = eval_int ~eval env left in
    let env, right = eval_int ~eval env right in
    Some (env, VBool (left > right))
  | EIntLessEqual (left, right) ->
    let env, left = eval_int ~eval env left in
    let env, right = eval_int ~eval env right in
    Some (env, VBool (left <= right))
  | EIntGreaterEqual (left, right) ->
    let env, left = eval_int ~eval env left in
    let env, right = eval_int ~eval env right in
    Some (env, VBool (left >= right))
  | _ -> None
