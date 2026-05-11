open Base
open Yelu_cmake_ir

let name = "tiny_cmake_if"
let requires = [ "core.unit"; "core.bool" ]
let provides = [ "if.statement" ]

type expr +=
  | ECmakeIfStmt of {
      cond : expr;
      then_ : expr;
      else_ : expr option;
    }

let expect_bool = function
  | VBool b -> b
  | v -> fail "expected bool, got %s" (Sexp.to_string ([%sexp_of: value] v))

let eval_case ~eval env = function
  | ECmakeIfStmt { cond; then_; else_ } ->
    let env, cond = eval env cond in
    if expect_bool cond then
      let env, _value = eval env then_ in
      Some (env, VUnit)
    else
      (match else_ with
       | None -> Some (env, VUnit)
       | Some else_ ->
         let env, _value = eval env else_ in
         Some (env, VUnit))
  | _ -> None
