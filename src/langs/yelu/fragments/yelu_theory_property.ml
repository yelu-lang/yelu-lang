open Base
open Yelu_cmake_ir
open Yelu_theory_target

let name = "tiny_property"
let requires = [ "core.string"; "target" ]
let provides =
  [ "property.set_target"; "property.get_target"; "property.set_tests";
    "property.set_property" ]

type expr +=
  | ESetTargetProperty of { target : expr; property : string; value : expr }
  | EGetTargetProperty of { var : string; target : expr; property : string }
  | ESetTestsProperties of {
      tests : expr list;
      properties : (string * expr) list;
    }
  | ESetProperty of {
      targets : expr list;
      append : bool;
      properties : (string * expr) list;
    }

let eval_case ~eval env = function
  | ESetTargetProperty { target; property; value } ->
    let env, target = eval_string ~eval env target in
    let env, value = eval_string ~eval env value in
    Some (set_target_property env ~target ~property ~value, VUnit)
  | EGetTargetProperty { var; target; property } ->
    let env, target = eval_string ~eval env target in
    let value =
      match find_target_property env ~target ~property with
      | Some v -> v
      | None -> property ^ "-NOTFOUND"
    in
    Some (set_var env ~key:var ~data:(VString value), VUnit)
  | ESetTestsProperties _ -> Some (env, VUnit)
  | ESetProperty { targets; append = _; properties } ->
    let env, targets = eval_string_list ~eval env targets in
    let env =
      List.fold targets ~init:env ~f:(fun env target ->
        List.fold properties ~init:env ~f:(fun env (property, value) ->
          let env, value = eval_string ~eval env value in
          set_target_property env ~target ~property ~value))
    in
    Some (env, VUnit)
  | _ -> None
