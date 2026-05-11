(* Yelu2 evaluator: interpret an IR built from theory-side *idealized*
   constructors (the [E*] forms in the [Yelu_theory_*] modules, plus the
   shared core nodes from [yelu_tiny.ml]).

   Yelu2 is the "cleaner" form that doesn't carry cmake-specific
   shape (no output-var sugar; mutations are explicit via [ESetVar]).
   This evaluator dispatches to each theory fragment's [eval_case].
   Used to test that the theory IR alone can express programs whose
   eval-state matches the corresponding Yelu1 program (proves
   semantic equivalence at the IR level). *)

open Base
open Yelu_cmake_ir
open Yelu_theory_store

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
    match Yelu_theory_path.eval_case ~eval:eval_expr env expr with
     | Some value -> value
     | None ->
    match Yelu_theory_file.eval_case ~eval:eval_expr env expr with
     | Some value -> value
     | None ->
    match Yelu_theory_target.eval_case ~eval:eval_expr env expr with
     | Some value -> value
     | None ->
    match Yelu_theory_install.eval_case ~eval:eval_expr env expr with
     | Some value -> value
     | None ->
    match Yelu_theory_if.eval_case ~eval:eval_expr env expr with
     | Some value -> value
     | None ->
    match Yelu_theory_string.eval_case ~eval:eval_expr env expr with
     | Some value -> value
     | None ->
    match Yelu_theory_cmake_op.eval_case ~eval:eval_expr env expr with
     | Some value -> value
     | None ->
    match Yelu_theory_dir.eval_case ~eval:eval_expr env expr with
     | Some value -> value
     | None ->
    match Yelu_theory_test.eval_case ~eval:eval_expr env expr with
     | Some value -> value
     | None ->
    match Yelu_theory_property.eval_case ~eval:eval_expr env expr with
     | Some value -> value
     | None ->
    match Yelu_theory_find.eval_case ~eval:eval_expr env expr with
     | Some value -> value
     | None ->
    match Yelu_theory_try.eval_case ~eval:eval_expr env expr with
     | Some value -> value
     | None -> fail "unknown expression in Yelu2")
