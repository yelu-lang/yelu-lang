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
    "cmake_op.include";
    "cmake_op.at_var";
  ]

(* [EDynFunction] registers a named, dynamically-scoped callable with
   formal [params] and a [body]. [EApply] looks the name up and invokes
   it.

   Scope follows cmake / Tcl: classic *dynamic scope* implemented by
   *shallow binding* (Bobrow & Wegbreit 1973; EOPL terminology). On
   entry the entire current variable map is saved into the activation
   record; [params] are bound as fresh vars; the body is evaluated in
   that extended env; on return the saved variable map is restored.
   Variable *reads* therefore see the caller's scope (dynamic-scope
   semantics); variable *writes* are local to the call frame, which is
   cmake's "writes local by default" wrinkle — to leak a write you
   would need [PARENT_SCOPE], which is deferred. Side effects on
   non-variable env state (targets, tests, install_rules, custom_*,
   target_properties, messages, …) persist across the call.

   The constructor name carries the scope discipline explicitly so we
   can later add a lexically-scoped / closure-style [EFunction] without
   the two clashing. Macros and ARGV/ARGC/ARGN are deferred. *)
type expr +=
  | EDynFunction of { name : expr; params : string list; body : expr }
  | EApply of { name : expr; args : expr list }
  | EProject of { name : string; languages : string list; version : string option }
  | EMinVersion of string
  | EMessage of { mode : string; texts : expr list }
  (* [EInclude] records a file-or-module name to be evaluated in cmake.
     First slice: record the declaration in [env.includes]; do not
     recursively evaluate the included body. Real cmake handles built-in
     modules (CTest / CPack / CMakePackageConfigHelpers / ...) plus
     local module files. *)
  | EInclude of { file : expr; optional : bool }
  (* [EAtVar key] is an emit-only literal injection: the script line is
     just [@key@]. cmake itself treats it as plain text; the value is
     substituted by [configure_package_config_file] (which runs string-
     replacement over a *.cmake.in template). The bridge maps production
     [Ycmake_at_var key], whose compiler renders it as a [Quote "@key@"]
     line. Eval is a no-op — there is no run-time effect at script
     evaluation time. *)
  | EAtVar of string

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
  | EDynFunction { name; params; body } ->
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
  | EInclude { file; optional = _ } ->
    let env, file = eval_string ~eval env file in
    Some (add_include env file, VUnit)
  | EAtVar _ -> Some (env, VUnit)
  | _ -> None
