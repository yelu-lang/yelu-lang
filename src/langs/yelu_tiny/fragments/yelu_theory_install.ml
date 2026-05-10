open Base
open Yelu_tiny
open Yelu_theory_target

type expr +=
  | EInstallTargets of {
      targets : expr list;
      destination : expr;
      export : expr option;
    }
  | EInstallFiles of {
      files : expr list;
      destination : expr;
    }

let eval_targets ~eval env targets =
  let env, targets =
    List.fold targets ~init:(env, []) ~f:(fun (env, targets) target ->
      let env, target = eval env target in
      env, expect_target target :: targets)
  in
  env, List.rev targets

let eval_case ~eval env = function
  | EInstallTargets { targets; destination; export } ->
    let env, targets = eval_targets ~eval env targets in
    let env, destination = eval_string ~eval env destination in
    let env, export =
      match export with
      | None -> env, None
      | Some export ->
        let env, export = eval_string ~eval env export in
        env, Some export
    in
    Some (add_install_rule env (InstallTargets { targets; destination; export }), VUnit)
  | EInstallFiles { files; destination } ->
    let env, files = eval_string_list ~eval env files in
    let env, destination = eval_string ~eval env destination in
    Some (add_install_rule env (InstallFiles { files; destination }), VUnit)
  | _ -> None
