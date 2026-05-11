open Base
open Yelu_tiny
open Yelu_theory_target

let name = "tiny_cmake_cmake_op"
let requires = [ "core.string" ]
let provides =
  [ "cmake_op.project";
    "cmake_op.min_version";
    "cmake_op.message";
    "cmake_op.function";
    "cmake_op.apply";
    "cmake_op.include";
    "cmake_op.at_var";
  ]

(* Surface mirror of the cmake_op theory. [ECmakeFunction] / [ECmakeApply]
   carry the same shape as their theory siblings ([EDynFunction] / [EApply])
   and the same scope mechanic: classic dynamic scope via shallow binding
   (save / bind / eval / restore). The cmake-flavored prefix exists so the
   bridge from production [Yc_function] / [Yc_apply] lands cleanly here
   without needing to lift before eval. *)
type expr +=
  | ECmakeProject of { name : string; languages : string list; version : string option }
  | ECmakeMinimumRequired of string
  | ECmakeMessage of { mode : string; texts : expr list }
  | ECmakeFunction of { name : expr; params : string list; body : expr }
  | ECmakeApply of { name : expr; args : expr list }
  | ECmakeInclude of { file : expr; optional : bool }
  (* See [EAtVar] in the theory fragment for semantics. Emit-only literal
     [@key@] injection, no eval effect, no surface-specific behavior. *)
  | ECmakeAtVar of string

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
  | ECmakeProject { name; languages; version } ->
    Some (set_project env { name; languages; version }, VUnit)
  | ECmakeMinimumRequired version ->
    Some (set_cmake_min_version env version, VUnit)
  | ECmakeMessage { mode; texts } ->
    let env, texts = eval_string_list ~eval env texts in
    Some (add_message env mode texts, VUnit)
  | ECmakeFunction { name; params; body } ->
    let env, name = eval_string ~eval env name in
    Some (set_function env name { params; body }, VUnit)
  | ECmakeApply { name; args } ->
    let env, name = eval_string ~eval env name in
    (match find_function env name with
     | None ->
       (* Lenient: cmake routinely invokes functions defined by
          [include(SomeModule)] whose body the tiny eval does not
          simulate. Evaluate the args for their side effects and
          return [VUnit] so the surrounding sequence keeps going. *)
       let env, _ = eval_args ~eval env args in
       Some (env, VUnit)
     | Some { params; body } ->
       let env, arg_values = eval_args ~eval env args in
       let saved_vars = env.vars in
       let env = bind_params env params arg_values in
       let env, result = eval env body in
       Some ({ env with vars = saved_vars }, result))
  | ECmakeInclude { file; optional = _ } ->
    let env, file = eval_string ~eval env file in
    Some (add_include env file, VUnit)
  | ECmakeAtVar _ -> Some (env, VUnit)
  | _ -> None
