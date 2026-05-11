open Base
open Yelu_tiny
open Yelu_theory_target

let name = "tiny_cmake_property"
let requires = [ "core.string"; "target" ]
let provides =
  [ "property.set_target"; "property.get_target"; "property.set_tests";
    "property.set_property" ]

type expr +=
  | ECmakeSetTargetProperty of { target : expr; property : string; value : expr }
  | ECmakeGetTargetProperty of { var : string; target : expr; property : string }
  | ECmakeSetTestsProperties of {
      tests : expr list;
      properties : (string * expr) list;
    }
  (* Generic [set_property(TARGET t1 t2 ... [APPEND] PROPERTY name value)].
     Emit-level mirror of yc_set_property; eval delegates to
     set_target_property per (target, property) pair. *)
  | ECmakeSetProperty of {
      targets : expr list;
      append : bool;
      properties : (string * expr) list;
    }

let eval_case ~eval env = function
  | ECmakeSetTargetProperty { target; property; value } ->
    let env, target = eval_string ~eval env target in
    let env, value = eval_string ~eval env value in
    Some (set_target_property env ~target ~property ~value, VUnit)
  | ECmakeGetTargetProperty { var; target; property } ->
    let env, target = eval_string ~eval env target in
    let value =
      match find_target_property env ~target ~property with
      | Some v -> v
      | None -> property ^ "-NOTFOUND"
    in
    Some (set_var env ~key:var ~data:(VString value), VUnit)
  | ECmakeSetTestsProperties _ -> Some (env, VUnit)
  | ECmakeSetProperty { targets; append = _; properties } ->
    let env, targets = eval_string_list ~eval env targets in
    let env =
      List.fold targets ~init:env ~f:(fun env target ->
        List.fold properties ~init:env ~f:(fun env (property, value) ->
          let env, value = eval_string ~eval env value in
          set_target_property env ~target ~property ~value))
    in
    Some (env, VUnit)
  | _ -> None
