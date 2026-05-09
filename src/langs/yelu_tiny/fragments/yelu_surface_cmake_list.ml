open Base
open Yelu_tiny

let name = "tiny_cmake_list"
let requires = [ "core.list"; "core.int"; "core.string" ]
let provides = [ "list.append"; "list.get"; "list.length"; "list.join" ]

type expr +=
  | ECmakeListAppend of { list : string; items : expr list }
  | ECmakeListGet of { list : string; index : expr; out : string }
  | ECmakeListLength of { list : string; out : string }
  | ECmakeListJoin of { list : string; glue : expr; out : string }

let eval_strings ~eval env exprs =
  List.fold exprs ~init:(env, []) ~f:(fun (env, rev_strings) expr ->
    let env, value = eval env expr in
    env, expect_string value :: rev_strings)
  |> fun (env, rev_strings) -> env, List.rev rev_strings

let list_value env name =
  match find_var env name with
  | None -> []
  | Some value -> expect_list value

let eval_case ~eval env = function
  | ECmakeListAppend { list; items } ->
    let env, strings = eval_strings ~eval env items in
    let values = list_value env list @ List.map strings ~f:(fun s -> VString s) in
    Some (set_var env ~key:list ~data:(VList values), VUnit)
  | ECmakeListGet { list; index; out } ->
    let env, index = eval env index in
    (match List.nth (list_value env list) (expect_int index) with
     | Some value -> Some (set_var env ~key:out ~data:value, VUnit)
     | None -> fail "list index out of range")
  | ECmakeListLength { list; out } ->
    let values = list_value env list in
    Some (set_var env ~key:out ~data:(VInt (List.length values)), VUnit)
  | ECmakeListJoin { list; glue; out } ->
    let env, glue = eval env glue in
    let strings = List.map (list_value env list) ~f:expect_string in
    Some
      ( set_var env ~key:out
          ~data:(VString (String.concat ~sep:(expect_string glue) strings)),
        VUnit )
  | _ -> None
