open Yelu_cmake

let name = "tiny_better_if"
let requires = [ "core.bool" ]
let provides = [ "if.expression" ]

type expr +=
  | EIfExpr of {
      cond : expr;
      then_ : expr;
      else_ : expr;
    }

(* Use the base Yelu_cmake.expect_bool — see yelu_cmake_if.ml. *)

let eval_case ~eval env = function
  | EIfExpr { cond; then_; else_ } ->
    let env, cond = eval env cond in
    if Yelu_cmake.expect_bool cond
    then Some (eval env then_) else Some (eval env else_)
  | _ -> None
