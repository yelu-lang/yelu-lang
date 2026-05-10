open Yelu_tiny
open Yelu_theory_target

let name = "tiny_cmake_dir"
let requires = [ "core.string"; "path" ]
let provides = [ "dir.add_subdirectory" ]

type expr +=
  | ECmakeAddSubdirectory of expr

let eval_case ~eval env = function
  | ECmakeAddSubdirectory path ->
    let env, path = eval_string ~eval env path in
    Some (add_subdirectory env path, VUnit)
  | _ -> None
