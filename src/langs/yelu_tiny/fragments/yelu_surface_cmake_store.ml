open Base
open Yelu_tiny

type expr +=
  | ECmakeUnsetVar of string
  | ECmakeUnsetVarCache of string
  | ECmakeVarDefined of string
  | ECmakeOption of { name : string; message : string; value : expr }

let eval_case env = function
  | ECmakeUnsetVar name -> Some (remove_var env name, VUnit)
  | ECmakeUnsetVarCache name -> Some (remove_var env name, VUnit)
  | ECmakeVarDefined name -> Some (env, VBool (var_defined env name))
  | ECmakeOption { name; value; _ } ->
    (match value with
     | EBool _ | EString _ | EVar _ ->
       let env, value =
         match value with
         | EBool b -> env, VBool b
         | EString s -> env, VString s
         | EVar var ->
           (match find_var env var with
            | Some value -> env, value
            | None -> fail "unbound variable %S" var)
         | _ -> assert false
       in
       Some (set_var env ~key:name ~data:value, VUnit)
     | _ -> None)
  | _ -> None
