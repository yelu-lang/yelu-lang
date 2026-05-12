open Yelu_cmake
open Yelu_cmake_normal_target

let name = "tiny_cmake_dir"
let requires = [ "core.string"; "path" ]
let provides = [ "dir.add_subdirectory" ]

type expr +=
  | ECmakeAddSubdirectory of expr
  (* Directory-level commands (apply to the current directory and
     subdirectories), distinct from their target_* equivalents. Eval
     is no-op at this slice — they affect cmake's build settings, not
     the env we model. *)
  | ECmakeIncludeDirectories of {
      dirs : expr list; before : bool; system : bool
    }
  | ECmakeAddCompileDefinitions of expr list
  | ECmakeAddCompileOptions of expr list
  | ECmakeAddLinkOptions of expr list
  | ECmakeAddDefinitions of expr list
  | ECmakeLinkDirectories of { dirs : expr list; before : bool }

let eval_case ~eval env = function
  | ECmakeAddSubdirectory path ->
    let env, path = eval_string ~eval env path in
    Some (add_subdirectory env path, VUnit)
  | ECmakeIncludeDirectories _ | ECmakeAddCompileDefinitions _
  | ECmakeAddCompileOptions _ | ECmakeAddLinkOptions _
  | ECmakeAddDefinitions _ | ECmakeLinkDirectories _ ->
    Some (env, VUnit)
  | _ -> None
