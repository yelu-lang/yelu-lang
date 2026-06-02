(* yelu_cmake_normal evaluator: interpret an IR built from the
   normalized-form constructors (the [E*] forms in the
   [Yelu_cmake_normal_*] fragment modules, plus the shared core nodes
   from [yelu_cmake.ml]).

   yelu_cmake_normal is the "cleaner" form that doesn't carry cmake-specific
   shape (no output-var sugar; mutations are explicit via [ESetVar]).
   This evaluator dispatches to each theory fragment's [eval_case].
   Used to test that the theory IR alone can express programs whose
   eval-state matches the corresponding yelu_cmake program (proves
   semantic equivalence at the IR level). *)

open Base
open Yelu_cmake
open Yelu_cmake_normal_store

let rec eval_expr env = function
  | EVar name ->
    (match find_var env name with
     | Some value -> env, value
     (* Same cmake semantics as yc-eval: undefined → empty string,
        not a crash. See yelu_cmake_eval.ml for context. *)
     | None -> env, VString "")
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
    (match Yelu_cmake_normal_bool.eval_case ~eval:eval_expr env expr with
     | Some value -> value
     | None ->
    match Yelu_cmake_normal_int.eval_case ~eval:eval_expr env expr with
     | Some value -> value
     | None ->
    match Yelu_cmake_normal_list.eval_case ~eval:eval_expr env expr with
     | Some value -> value
     | None ->
    match Yelu_cmake_normal_path.eval_case ~eval:eval_expr env expr with
     | Some value -> value
     | None ->
    match Yelu_cmake_normal_file.eval_case ~eval:eval_expr env expr with
     | Some value -> value
     | None ->
    match Yelu_cmake_normal_target.eval_case ~eval:eval_expr env expr with
     | Some value -> value
     | None ->
    match Yelu_cmake_normal_install.eval_case ~eval:eval_expr env expr with
     | Some value -> value
     | None ->
    match Yelu_cmake_normal_if.eval_case ~eval:eval_expr env expr with
     | Some value -> value
     | None ->
    match Yelu_cmake_normal_string.eval_case ~eval:eval_expr env expr with
     | Some value -> value
     | None ->
    match Yelu_cmake_normal_cmake_op.eval_case ~eval:eval_expr env expr with
     | Some value -> value
     | None ->
    match Yelu_cmake_normal_dir.eval_case ~eval:eval_expr env expr with
     | Some value -> value
     | None ->
    match Yelu_cmake_normal_test.eval_case ~eval:eval_expr env expr with
     | Some value -> value
     | None ->
    match Yelu_cmake_normal_property.eval_case ~eval:eval_expr env expr with
     | Some value -> value
     | None ->
    match Yelu_cmake_normal_find.eval_case ~eval:eval_expr env expr with
     | Some value -> value
     | None ->
    match Yelu_cmake_normal_try.eval_case ~eval:eval_expr env expr with
     | Some value -> value
     | None ->
    (* Store fragment last — catches ESetCache added in cache_plan step 6. *)
    match Yelu_cmake_normal_store.eval_case env expr with
     | Some value -> value
     | None -> fail "unknown expression in yelu_cmake_normal")
