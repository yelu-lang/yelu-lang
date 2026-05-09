open Base
open Yelu_tiny

type expr +=
  | ECmakeUnsetVar of string
  | ECmakeVarDefined of string

let eval_case env = function
  | ECmakeUnsetVar name -> Some (remove_var env name, VUnit)
  | ECmakeVarDefined name -> Some (env, VBool (var_defined env name))
  | _ -> None
