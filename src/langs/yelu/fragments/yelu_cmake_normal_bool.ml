open Base
open Yelu_cmake

let name = "tiny_bool"
let requires = [ "core.bool" ]
let provides = [ "bool.not"; "bool.and"; "bool.or" ]

type expr +=
  | ENot of expr
  | EAnd of expr * expr
  | EOr of expr * expr

(* Delegate to the base expect_bool in Yelu_cmake — it implements
   cmake's string-to-bool coercion (OFF/NO/FALSE/0/N/IGNORE/NOTFOUND →
   false; any other non-empty string → true). The fragment used to
   have a stricter local copy that only accepted VBool, which broke
   when conds read cache vars populated by -D (always VString) or
   by plain set(). Discovered via the fmt bridge smoke. *)
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
