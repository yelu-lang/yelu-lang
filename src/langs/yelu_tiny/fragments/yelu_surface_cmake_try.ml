open Yelu_tiny
open Yelu_theory_target

let name = "tiny_cmake_try"
let requires = [ "core.string"; "path" ]
let provides = [ "try.try_compile" ]

type expr +=
  | ECmakeTryCompile of { result_var : string; sources : expr list }

let eval_case ~eval env = function
  | ECmakeTryCompile { result_var; sources } ->
    let env, sources = eval_string_list ~eval env sources in
    let env = add_try_compile env { result_var; sources } in
    Some (set_var env ~key:result_var ~data:(VBool true), VUnit)
  | _ -> None
