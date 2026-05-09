open Base
open Yelu_tiny

let name = "tiny_cmake_string"
let requires = [ "core.string"; "core.int" ]
let provides =
  [ "string.concat"; "string.upper"; "string.replace"; "string.length"; "string.equal" ]

type expr +=
  | ECmakeStringConcat of { inputs : expr list; out : string }
  | ECmakeStringToupper of { input : expr; out : string }
  | ECmakeStringReplace of {
      match_ : expr;
      replace : expr;
      input : expr;
      out : string;
    }
  | ECmakeStringLength of { input : expr; out : string }
  | ECmakeStringEqual of expr * expr

let replace_all ~match_ ~replace ~input =
  String.substr_replace_all input ~pattern:match_ ~with_:replace

let eval_string ~eval env expr =
  let env, value = eval env expr in
  env, expect_string value

let eval_strings ~eval env exprs =
  List.fold exprs ~init:(env, []) ~f:(fun (env, rev_strings) expr ->
    let env, string = eval_string ~eval env expr in
    env, string :: rev_strings)
  |> fun (env, rev_strings) -> env, List.rev rev_strings

let eval_case ~eval env = function
  | ECmakeStringConcat { inputs; out } ->
    let env, strings = eval_strings ~eval env inputs in
    Some
      (set_var env ~key:out ~data:(VString (String.concat strings)), VUnit)
  | ECmakeStringToupper { input; out } ->
    let env, string = eval_string ~eval env input in
    Some (set_var env ~key:out ~data:(VString (String.uppercase string)), VUnit)
  | ECmakeStringReplace { match_; replace; input; out } ->
    let env, match_string = eval_string ~eval env match_ in
    let env, replace_string = eval_string ~eval env replace in
    let env, input_string = eval_string ~eval env input in
    Some
      ( set_var env ~key:out
          ~data:
            (VString
               (replace_all
                  ~match_:match_string
                  ~replace:replace_string
                  ~input:input_string)),
        VUnit )
  | ECmakeStringLength { input; out } ->
    let env, string = eval_string ~eval env input in
    Some (set_var env ~key:out ~data:(VInt (String.length string)), VUnit)
  | ECmakeStringEqual (left, right) ->
    let env, left = eval_string ~eval env left in
    let env, right = eval_string ~eval env right in
    Some (env, VBool (String.equal left right))
  | _ -> None
