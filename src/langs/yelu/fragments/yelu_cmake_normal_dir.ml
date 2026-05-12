open Yelu_cmake
open Yelu_cmake_normal_target

let name = "tiny_dir"
let requires = [ "core.string"; "path" ]
let provides = [ "dir.add_subdirectory" ]

type expr +=
  | EAddSubdirectory of expr

let eval_case ~eval env = function
  | EAddSubdirectory path ->
    let env, path = eval_string ~eval env path in
    Some (add_subdirectory env path, VUnit)
  | _ -> None
