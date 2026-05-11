(* Yelu1 evaluator: interpret an IR built from cmake-shaped *surface*
   constructors (the [ECmake*] family, plus the shared core nodes from
   [yelu_tiny.ml]). Used to demonstrate that the cmake-faithful surface
   is executable and to compare result envs against the production
   yelu_cmake compiler.

   This module dispatches to each surface fragment's [eval_case] in
   turn. Pure-theory fragments (bool, int, list, target) are also
   consulted because Yelu1 inherits the shared core. *)

open Base
open Yelu_tiny
open Yelu_theory_store
open Yelu_surface_cmake_store

let rec eval_expr env = function
  | EVar name ->
    (match find_var env name with
     | Some value -> env, value
     | None -> fail "unbound variable %S" name)
  | EString s -> env, VString s
  | EBool b -> env, VBool b
  | EInt n -> env, VInt n
  | EUnit -> env, VUnit
  | ESetVar (name, expr) ->
    let env, value = eval_expr env expr in
    set_var env ~key:name ~data:value, VUnit
  | EUnsetVar name ->
    remove_var env name, VUnit
  | EVarDefined name ->
    env, VBool (var_defined env name)
  | ECmakeUnsetVar name ->
    remove_var env name, VUnit
  | ECmakeVarDefined name ->
    env, VBool (var_defined env name)
  | ECmakeOption { name; value; _ } ->
    let env, value = eval_expr env value in
    set_var env ~key:name ~data:value, VUnit
  | ESeq exprs ->
    List.fold exprs ~init:(env, VUnit) ~f:(fun (env, _last) expr ->
      eval_expr env expr)
  | ELet { var; value; body } ->
    let env, value = eval_expr env value in
    let outer = find_var env var in
    let env = set_var env ~key:var ~data:value in
    let env, result = eval_expr env body in
    let env =
      match outer with
      | Some v -> set_var env ~key:var ~data:v
      | None -> remove_var env var
    in
    env, result
  | expr ->
    (match Yelu_theory_bool.eval_case ~eval:eval_expr env expr with
     | Some value -> value
     | None ->
    match Yelu_theory_int.eval_case ~eval:eval_expr env expr with
     | Some value -> value
     | None ->
    match Yelu_theory_list.eval_case ~eval:eval_expr env expr with
     | Some value -> value
     | None ->
    match Yelu_surface_cmake_list.eval_case ~eval:eval_expr env expr with
     | Some value -> value
     | None ->
    match Yelu_surface_cmake_path.eval_case ~eval:eval_expr env expr with
     | Some value -> value
     | None ->
    match Yelu_surface_cmake_file.eval_case ~eval:eval_expr env expr with
     | Some value -> value
     | None ->
    match Yelu_theory_target.eval_case ~eval:eval_expr env expr with
     | Some value -> value
     | None ->
    match Yelu_surface_cmake_target.eval_case ~eval:eval_expr env expr with
     | Some value -> value
     | None ->
    match Yelu_surface_cmake_install.eval_case ~eval:eval_expr env expr with
     | Some value -> value
     | None ->
    match Yelu_surface_cmake_if.eval_case ~eval:eval_expr env expr with
     | Some value -> value
     | None ->
    match Yelu_surface_cmake_string.eval_case ~eval:eval_expr env expr with
     | Some value -> value
     | None ->
    match Yelu_surface_cmake_cmake_op.eval_case ~eval:eval_expr env expr with
     | Some value -> value
     | None ->
    match Yelu_surface_cmake_dir.eval_case ~eval:eval_expr env expr with
     | Some value -> value
     | None ->
    match Yelu_surface_cmake_test.eval_case ~eval:eval_expr env expr with
     | Some value -> value
     | None ->
    match Yelu_surface_cmake_property.eval_case ~eval:eval_expr env expr with
     | Some value -> value
     | None ->
    match Yelu_surface_cmake_find.eval_case ~eval:eval_expr env expr with
     | Some value -> value
     | None ->
    match Yelu_surface_cmake_try.eval_case ~eval:eval_expr env expr with
     | Some value -> value
     | None ->
    (* Store fragment last — most store ops are inlined above; this
       catches the new ECmakeSetParentScope added in R4-b.3c. *)
    match Yelu_surface_cmake_store.eval_case env expr with
     | Some value -> value
     | None -> fail "unknown expression in Yelu1")
