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

(* Coerce-to-int for cmake-style int comparisons. Real cmake errors
   on non-numeric operands in LESS/GREATER/EQUAL; the predictor
   prefers a soft 0-default so a single unbound variable doesn't
   crash the whole eval. Strings parsed if numeric, else 0;
   bool → 1/0; everything else → 0. Captured via the include
   loader smoke (fmt has `if (NINJA_VERSION VERSION_GREATER_EQUAL
   1.11)` style checks where NINJA_VERSION is unbound). *)
let coerce_int = function
  | VInt n -> n
  | VBool true -> 1
  | VBool false -> 0
  | VString s ->
    (match Int.of_string_opt (String.strip s) with
     | Some n -> n
     | None -> 0)
  | _ -> 0

let eval_int ~eval env expr =
  let env, value = eval env expr in
  env, coerce_int value

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
