open Base
open Yelu_tiny

type expr +=
  | ECmakeUnsetVar of string
  | ECmakeUnsetVarCache of string
  | ECmakeVarDefined of string
  | ECmakeOption of { name : string; message : string; value : expr }
  (* [set(<var> <value>... PARENT_SCOPE)] — writes the value to the
     parent frame's locals, not the current frame. Tiny raises a
     dedicated [Eval_error] at the root frame (cmake silently no-ops).
     See doc/cmake_scope_and_control_flow.md "Resolved decisions #1". *)
  | ECmakeSetParentScope of { name : string; value : expr }
  (* Environment-variable namespace: [set(ENV{VAR} value)] /
     [unset(ENV{VAR})]. Tiny eval treats env vars as a no-op (we don't
     simulate the OS env); emit renders the cmake form faithfully so
     real cmake handles them. *)
  | ECmakeSetEnvVar of { name : string; value : expr }
  | ECmakeUnsetEnvVar of string

let eval_case env = function
  | ECmakeUnsetVar name -> Some (remove_var env name, VUnit)
  | ECmakeUnsetVarCache name -> Some (remove_var env name, VUnit)
  | ECmakeVarDefined name -> Some (env, VBool (var_defined env name))
  | ECmakeSetParentScope { name; value } ->
    (* The value expression has already been bridged; eval it to a
       value, then write to parent frame's locals. *)
    let data = match value with
      | EString s -> VString s
      | EBool b -> VBool b
      | EInt n -> VInt n
      | EVar var ->
        (match find_var env var with
         | Some v -> v
         | None -> VString "")
      | _ -> VString ""  (* fallback for richer expressions *)
    in
    Some (set_var_parent_scope env ~key:name ~data, VUnit)
  | ECmakeSetEnvVar _ | ECmakeUnsetEnvVar _ ->
    (* Env-namespace ops are emit-only at this slice; cmake handles
       the OS env at configure time. *)
    Some (env, VUnit)
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
