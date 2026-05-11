open Base
open Yelu_cmake_ir

type expr +=
  | EUnsetVar of string
  | EVarDefined of string

let eval_case env = function
  | EUnsetVar name -> Some (remove_var env name, VUnit)
  | EVarDefined name -> Some (env, VBool (var_defined env name))
  | _ -> None
