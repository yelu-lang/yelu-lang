open Base
open Yelu_tiny
open Yelu_theory_target

let name = "tiny_cmake_op"
let requires = [ "core.string" ]
let provides =
  [ "cmake_op.project";
    "cmake_op.min_version";
    "cmake_op.message";
    "cmake_op.function";
    "cmake_op.apply";
  ]

(* [EFunction] registers a named callable with formal [params] and a [body].
   [EApply] looks the name up and invokes it. Scope is *function-call scope*
   (cmake-style): the entire current variable map is saved on entry, [params]
   are bound to the evaluated arguments as fresh vars, body is evaluated in
   the extended env, and on return the saved variable map is restored —
   so vars set inside the body do not leak to the caller. Side effects on
   non-variable env state (targets, tests, install_rules, custom_*,
   target_properties, messages, …) persist across the call. Macros and
   ARGV/ARGC/ARGN are deferred. *)
type expr +=
  | EFunction of { name : expr; params : string list; body : expr }
  | EApply of { name : expr; args : expr list }
  | EProject of { name : string; languages : string list; version : string option }
  | EMinVersion of string
  | EMessage of { mode : string; texts : expr list }

let bind_params env params arg_values =
  match List.zip params arg_values with
  | Ok pairs ->
    List.fold pairs ~init:env ~f:(fun env (name, value) ->
      set_var env ~key:name ~data:value)
  | Unequal_lengths ->
    fail
      "apply: arity mismatch — function expects %d params, got %d args"
      (List.length params) (List.length arg_values)

let eval_args ~eval env args =
  let env, rev_values =
    List.fold args ~init:(env, []) ~f:(fun (env, acc) arg ->
      let env, value = eval env arg in
      env, value :: acc)
  in
  env, List.rev rev_values

let eval_case ~eval env = function
  | EProject { name; languages; version } ->
    Some (set_project env { name; languages; version }, VUnit)
  | EMinVersion version ->
    Some (set_cmake_min_version env version, VUnit)
  | EMessage { mode; texts } ->
    let env, texts = eval_string_list ~eval env texts in
    Some (add_message env mode texts, VUnit)
  | EFunction { name; params; body } ->
    let env, name = eval_string ~eval env name in
    Some (set_function env name { params; body }, VUnit)
  | EApply { name; args } ->
    let env, name = eval_string ~eval env name in
    (match find_function env name with
     | None -> fail "apply to unknown function %S" name
     | Some { params; body } ->
       let env, arg_values = eval_args ~eval env args in
       let saved_vars = env.vars in
       let env = bind_params env params arg_values in
       let env, result = eval env body in
       Some ({ env with vars = saved_vars }, result))
  | _ -> None
