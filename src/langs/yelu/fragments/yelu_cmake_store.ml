open Base
open Yelu_cmake

type expr +=
  | ECmakeUnsetVar of string
  | ECmakeUnsetVarCache of string
  | ECmakeVarDefined of string
  | ECmakeOption of { name : string; message : string; value : expr }
  (* [set(<var> <value>... PARENT_SCOPE)] — writes the value to the
     parent frame's locals, not the current frame. Tiny raises a
     dedicated [Eval_error] at the root frame (cmake silently no-ops).
     See doc/cmake/scope_and_control_flow.md "Resolved decisions #1". *)
  | ECmakeSetParentScope of { name : string; value : expr }
  (* Environment-variable namespace: [set(ENV{VAR} value)] /
     [unset(ENV{VAR})]. Tiny eval treats env vars as a no-op (we don't
     simulate the OS env); emit renders the cmake form faithfully so
     real cmake handles them. *)
  | ECmakeSetEnvVar of { name : string; value : expr }
  | ECmakeUnsetEnvVar of string
  (* [set(<var> <value>... CACHE <type> "<doc>" [FORCE])] — cache namespace
     write. See doc/cmake/cache_semantics.md § "Write path":
       - If [name] already in [cache_vars] (e.g. from -D or a previous
         set/option), this call is a NO-OP unless [force] is true.
       - Otherwise: write to [cache_vars] AND dual-write to the current
         frame's [locals] (so reads in the same configure run see it).
     [doc/yelu_cmake/cache_plan.md] § 3.3 has the design.
     Pre-2026-06-01 eval treated this as a plain [set_var]; existing
     bar3-lite oracle is unaffected (this is eval-only behavior). *)
  | ECmakeSetCache of {
      name : string;
      values : expr list;
      cache_type : string;
      docstring : string;
      force : bool;
    }

(* Accept the recursive [~eval] callback. ECmakeSetCache /
   ECmakeOption need it to evaluate value expressions like
   [EVar X] that come from arg_to_expr's ${X} substitution. *)
let eval_case ~eval env = function
  | ECmakeUnsetVar name -> Some (remove_var env name, VUnit)
  (* unset(VAR CACHE) clears BOTH normal AND cache namespaces —
     cache_semantics.md row 3.3. *)
  | ECmakeUnsetVarCache name -> Some (unset_var_both env name, VUnit)
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
  | ECmakeSetCache { name; values; force; _ } ->
    (* cache_semantics.md § "Write path":
         - If cache_vars[name] exists AND not force -> NO-OP entirely.
         - Otherwise write cache_vars[name] AND dual-write to current
           frame's locals (so reads in this run see it).
       Values are EVALUATED (not pattern-matched) so EVar / nested
       expressions resolve at write time. Previously only EString /
       EBool / EInt literal patterns matched, with everything else
       falling through to VString "" — caught by the fmt bridge
       smoke when set(X ${Y} CACHE ...) was being written as empty.

       Name substitution: cmake substitutes ${X} in the VAR slot
       before writing to cache. Our IR stores name as a plain
       string (set at parse time), so a function body like
         set(${variable} ... CACHE STRING ...)
       gets var = "${variable}" — useless without runtime
       substitution. Quick case here: if the WHOLE name is
       ${IDENT}, resolve via find_var; if the resolved value is
       a non-empty string, use that as the cache key. Nested /
       partial substitution stays deferred. Discovered via
       fmt's set_verbose() function call.
       cmake itself never writes a cache entry whose name is
       literally "${X}" — if substitution fails, the right
       behavior is to skip the write (cache_semantics is silent
       on this; the predictor stays safe). *)
    let n_str = String.length name in
    let effective_name =
      if n_str >= 4
         && Char.equal name.[0] '$' && Char.equal name.[1] '{'
         && Char.equal name.[n_str - 1] '}'
      then
        let inner = String.sub name ~pos:2 ~len:(n_str - 3) in
        match find_var env inner with
        | Some (VString s) when not (String.is_empty s) -> s
        | _ -> name  (* leave as-is; the skip below catches it *)
      else name
    in
    if String.is_substring effective_name ~substring:"${" then
      Some (env, VUnit)
    else
    let name = effective_name in
    if cache_var_defined env name && not force
    then Some (env, VUnit)
    else
      let env, data = match values with
        | [] -> env, VString ""
        | [ v ] -> eval env v
        | vs ->
          (* Multi-value: eval each, join with ";" (cmake list form). *)
          let env, evaluated =
            List.fold vs ~init:(env, []) ~f:(fun (env, acc) v ->
              let env, value = eval env v in
              env, value :: acc)
          in
          let parts =
            List.rev evaluated
            |> List.map ~f:(function
                | VString s -> s
                | VBool true -> "ON"
                | VBool false -> "OFF"
                | VInt n -> Int.to_string n
                | _ -> "")
          in
          env, VString (String.concat ~sep:";" parts)
      in
      let env = set_cache_var env ~key:name ~data in
      let env = set_var env ~key:name ~data in
      Some (env, VUnit)
  | ECmakeOption { name; value; _ } ->
    (* cache_semantics.md § "Equivalences": option(X "msg" V)  ≡
       set(X V CACHE BOOL "msg"). So if X is already in cache (e.g.
       from -D), option() is a NO-OP. Otherwise write the declared
       default to BOTH cache and current frame's locals. *)
    if cache_var_defined env name
    then Some (env, VUnit)
    else (match value with
     | EBool _ | EString _ | EVar _ ->
       let env, data =
         match value with
         | EBool b -> env, VBool b
         | EString s -> env, VString s
         | EVar var ->
           (match find_var env var with
            | Some v -> env, v
            | None -> fail "unbound variable %S" var)
         | _ -> assert false
       in
       let env = set_cache_var env ~key:name ~data in
       let env = set_var env ~key:name ~data in
       Some (env, VUnit)
     | _ -> None)
  | _ -> None
