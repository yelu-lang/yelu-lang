open Yelu_tiny
open Yelu_theory_target

let name = "tiny_property"
let requires = [ "core.string"; "target" ]
let provides = [ "property.set_target"; "property.get_target"; "property.set_tests" ]

type expr +=
  | ESetTargetProperty of { target : expr; property : string; value : expr }
  | EGetTargetProperty of { var : string; target : expr; property : string }
  | ESetTestsProperties of {
      tests : expr list;
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
  | _ -> None
