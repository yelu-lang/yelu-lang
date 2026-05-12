open Yelu_cmake
open Yelu_cmake_normal_target

let name = "tiny_test"
let requires = [ "core.string" ]
let provides = [ "test.enable_testing"; "test.add_test" ]

type expr +=
  | EEnableTesting
  | EAddTest of { name : expr; command : expr; args : expr list }

let eval_case ~eval env = function
  | EEnableTesting -> Some (enable_testing env, VUnit)
  | EAddTest { name; command; args } ->
    let env, name = eval_string ~eval env name in
    let env, command = eval_string ~eval env command in
    let env, args = eval_string_list ~eval env args in
    Some (add_test env { name; command; args }, VUnit)
  | _ -> None
