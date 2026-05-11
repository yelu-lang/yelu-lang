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
  (* Additional list() subcommands — emit-faithful, eval stubs. *)
  | ECmakeListPrepend of { list : string; items : expr list }
  | ECmakeListInsert of { list : string; index : int; items : expr list }
  | ECmakeListRemoveItem of { list : string; items : expr list }
  | ECmakeListRemoveAt of { list : string; indices : int list }
  | ECmakeListRemoveDuplicates of { list : string }
  | ECmakeListReverse of { list : string }
  | ECmakeListSort of {
      list : string;
      order : string option;
      compare : string option;
      case : string option;
    }
  | ECmakeListFilter of { list : string; mode : string; regex : string }
  | ECmakeListSublist of {
      list : string; begin_ : int; length : int; out : string
    }
  | ECmakeListFind of { list : string; value : expr; out : string }
  | ECmakeListPopBack of { list : string; out_vars : string list }
  | ECmakeListPopFront of { list : string; out_vars : string list }
  (* Transform: action / selector kept as opaque strings (rendered
     directly by emit). Eval stub. *)
  | ECmakeListTransform of {
      list : string;
      action : string;
      selector : string option;
      output : string option;
    }

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
  (* Additional list() subcommands — eval stubs. Where the op mutates
     the list, we update env conservatively (extending with items, or
     marking empty); where it produces an out var, we bind it to a
     placeholder. *)
  | ECmakeListPrepend { list; items } ->
    let env, strings = eval_strings ~eval env items in
    let values = List.map strings ~f:(fun s -> VString s) @ list_value env list in
    Some (set_var env ~key:list ~data:(VList values), VUnit)
  | ECmakeListInsert { list; index = _; items } ->
    let env, strings = eval_strings ~eval env items in
    let values = list_value env list @ List.map strings ~f:(fun s -> VString s) in
    Some (set_var env ~key:list ~data:(VList values), VUnit)
  | ECmakeListRemoveItem _ | ECmakeListRemoveAt _ ->
    Some (env, VUnit)
  | ECmakeListRemoveDuplicates _ | ECmakeListReverse _
  | ECmakeListSort _ | ECmakeListFilter _ ->
    Some (env, VUnit)
  | ECmakeListSublist { out; _ } ->
    Some (set_var env ~key:out ~data:(VList []), VUnit)
  | ECmakeListFind { out; _ } ->
    Some (set_var env ~key:out ~data:(VInt (-1)), VUnit)
  | ECmakeListPopBack { out_vars; _ }
  | ECmakeListPopFront { out_vars; _ } ->
    let env =
      List.fold out_vars ~init:env ~f:(fun env v ->
        set_var env ~key:v ~data:(VString ""))
    in
    Some (env, VUnit)
  | ECmakeListTransform { output; _ } ->
    (match output with
     | Some v -> Some (set_var env ~key:v ~data:(VList []), VUnit)
     | None -> Some (env, VUnit))
  | _ -> None
