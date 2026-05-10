open Yelu_tiny
open Yelu_theory_target

let name = "tiny_cmake_property"
let requires = [ "core.string"; "target" ]
let provides = [ "property.set_target"; "property.get_target" ]

type expr +=
  | ECmakeSetTargetProperty of { target : expr; property : string; value : expr }
  | ECmakeGetTargetProperty of { var : string; target : expr; property : string }

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
  | _ -> None
