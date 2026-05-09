open Base
open Yelu_tiny

let name = "tiny_better_string"
let requires = [ "core.string"; "core.int" ]
let provides =
  [ "string.concat"; "string.upper"; "string.replace"; "string.length"; "string.equal" ]

type expr +=
  | EStringConcat of expr list
  | EStringUpper of expr
  | EStringReplaceAll of {
      needle : expr;
      replacement : expr;
      haystack : expr;
    }
  | EStringLen of expr
  | EStringJoin of { sep : expr; items : expr }
  | EStringEqual of expr * expr

let replace_all ~needle ~replacement ~haystack =
  String.substr_replace_all haystack ~pattern:needle ~with_:replacement

let eval_string ~eval env expr =
  let env, value = eval env expr in
  env, expect_string value

let eval_strings ~eval env exprs =
  List.fold exprs ~init:(env, []) ~f:(fun (env, rev_strings) expr ->
    let env, string = eval_string ~eval env expr in
    env, string :: rev_strings)
  |> fun (env, rev_strings) -> env, List.rev rev_strings

let eval_case ~eval env = function
  | EStringConcat exprs ->
    let env, strings = eval_strings ~eval env exprs in
    Some
      (env, VString (String.concat strings))
  | EStringUpper expr ->
    let env, string = eval_string ~eval env expr in
    Some (env, VString (String.uppercase string))
  | EStringReplaceAll { needle; replacement; haystack } ->
    let env, needle = eval_string ~eval env needle in
    let env, replacement = eval_string ~eval env replacement in
    let env, haystack = eval_string ~eval env haystack in
    Some
      ( env,
        VString (replace_all ~needle ~replacement ~haystack) )
  | EStringLen expr ->
    let env, string = eval_string ~eval env expr in
    Some (env, VInt (String.length string))
  | EStringJoin { sep; items } ->
    let env, sep = eval_string ~eval env sep in
    let env, items = eval env items in
    let strings = List.map (expect_list items) ~f:expect_string in
    Some (env, VString (String.concat ~sep strings))
  | EStringEqual (left, right) ->
    let env, left = eval_string ~eval env left in
    let env, right = eval_string ~eval env right in
    Some (env, VBool (String.equal left right))
  | _ -> None
