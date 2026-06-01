open Base
open Yelu_cmake

type expr +=
  | EUnsetVar of string
  | EVarDefined of string
  (* Normalized cache write. Mirrors [ECmakeSetCache] in yelu_cmake_store
     so that to_normal can preserve cache semantics across the bridge
     (without this ctor, to_normal would have to passthrough yc-side
     ECmakeSetCache, which ycn-eval has no case for — see cache_plan.md
     step 6). The eval rule is identical to yc-side:
       - no-op if cache_vars[name] AND not force
       - else dual-write cache_vars + current frame's locals.
     Preserves cache_type/docstring so from_normal can lift back to
     ECmakeSetCache faithfully. Note: ECmakeOption lowers to ESetCache
     with cache_type="BOOL" docstring=message; from_normal lifts ALL
     ESetCache back to ECmakeSetCache (the option() origin is lossy
     in this direction — lift_lower doesn't exercise option() today
     so this is harmless). *)
  | ESetCache of {
      name : string;
      values : expr list;
      cache_type : string;
      docstring : string;
      force : bool;
    }

let eval_case env = function
  | EUnsetVar name -> Some (remove_var env name, VUnit)
  | EVarDefined name -> Some (env, VBool (var_defined env name))
  | ESetCache { name; values; force; _ } ->
    if cache_var_defined env name && not force
    then Some (env, VUnit)
    else
      let data = match values with
        | [ EString s ] -> VString s
        | [ EBool b ] -> VBool b
        | [ EInt n ] -> VInt n
        | _ -> VString ""
      in
      let env = set_cache_var env ~key:name ~data in
      let env = set_var env ~key:name ~data in
      Some (env, VUnit)
  | _ -> None
