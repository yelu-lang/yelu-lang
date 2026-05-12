open Yelu_cmake
open Yelu_theory_target

let name = "tiny_try"
let requires = [ "core.string"; "path" ]
let provides = [ "try.try_compile" ]

(* The tiny interpreter cannot actually compile; it records the declaration
   and stubs result_var to true so downstream tests can observe the call.
   Real compile-or-not is determined when the lowered cmake script runs. *)

type expr +=
  | ETryCompile of { result_var : string; sources : expr list }

let eval_case ~eval env = function
  | ETryCompile { result_var; sources } ->
    let env, sources = eval_string_list ~eval env sources in
    let env = add_try_compile env { result_var; sources } in
    Some (set_var env ~key:result_var ~data:(VBool true), VUnit)
  | _ -> None
