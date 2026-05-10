open Base
open Yelu_tiny
open Yelu_theory_target

let name = "tiny_cmake_install"
let requires = [ "core.string"; "target.add_executable" ]
let provides = [ "install.targets"; "install.files" ]

type expr +=
  | ECmakeInstallTargets of {
      targets : string list;
      destination : expr;
      export : expr option;
    }
  | ECmakeInstallFiles of {
      files : expr list;
      destination : expr;
    }

let eval_case ~eval env = function
  | ECmakeInstallTargets { targets; destination; export } ->
    let env, destination = eval_string ~eval env destination in
    let env, export =
      match export with
      | None -> env, None
      | Some export ->
        let env, export = eval_string ~eval env export in
        env, Some export
    in
    Some (add_install_rule env (InstallTargets { targets; destination; export }), VUnit)
  | ECmakeInstallFiles { files; destination } ->
    let env, files = eval_string_list ~eval env files in
    let env, destination = eval_string ~eval env destination in
    Some (add_install_rule env (InstallFiles { files; destination }), VUnit)
  | _ -> None
