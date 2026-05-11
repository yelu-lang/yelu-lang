open Base
open Yelu_cmake_ir

let name = "tiny_better_if"
let requires = [ "core.bool" ]
let provides = [ "if.expression" ]

type expr +=
  | EIfExpr of {
      cond : expr;
      then_ : expr;
      else_ : expr;
    }

let expect_bool = function
  | VBool b -> b
  | v -> fail "expected bool, got %s" (Sexp.to_string ([%sexp_of: value] v))

let eval_case ~eval env = function
  | EIfExpr { cond; then_; else_ } ->
    let env, cond = eval env cond in
    if expect_bool cond then Some (eval env then_) else Some (eval env else_)
  | _ -> None
