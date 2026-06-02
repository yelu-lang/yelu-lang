open Base
open Yelu_cmake

let name = "tiny_cmake_if"
let requires = [ "core.unit"; "core.bool" ]
let provides = [ "if.statement" ]

type expr +=
  | ECmakeIfStmt of {
      cond : expr;
      then_ : expr;
      else_ : expr option;
    }

(* Use the base Yelu_cmake.expect_bool which implements cmake's
   string-to-bool coercion. The if-stmt fragment used to have a
   strict local copy; same gap as in yelu_cmake_normal_bool.ml.
   See fmt bridge smoke for context. *)

let eval_case ~eval env = function
  | ECmakeIfStmt { cond; then_; else_ } ->
    let env, cond = eval env cond in
    if Yelu_cmake.expect_bool cond then
      let env, _value = eval env then_ in
      Some (env, VUnit)
    else
      (match else_ with
       | None -> Some (env, VUnit)
       | Some else_ ->
         let env, _value = eval env else_ in
         Some (env, VUnit))
  | _ -> None
