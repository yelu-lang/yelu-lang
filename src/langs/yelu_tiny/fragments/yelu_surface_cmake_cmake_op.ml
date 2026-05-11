open Base
open Yelu_tiny
open Yelu_theory_target

let name = "tiny_cmake_cmake_op"
let requires = [ "core.string" ]
let provides =
  [ "cmake_op.project";
    "cmake_op.min_version";
    "cmake_op.message";
    "cmake_op.function";
    "cmake_op.apply";
    "cmake_op.include";
    "cmake_op.at_var";
  ]

(* Surface mirror of the cmake_op theory. [ECmakeFunction] / [ECmakeApply]
   carry the same shape as their theory siblings ([EDynFunction] / [EApply])
   and the same scope mechanic: classic dynamic scope via shallow binding
   (save / bind / eval / restore). The cmake-flavored prefix exists so the
   bridge from production [Yc_function] / [Yc_apply] lands cleanly here
   without needing to lift before eval. *)
type expr +=
  | ECmakeProject of { name : string; languages : string list; version : string option }
  | ECmakeMinimumRequired of string
  | ECmakeMessage of { mode : string; texts : expr list }
  | ECmakeFunction of { name : expr; params : string list; body : expr }
  | ECmakeApply of { name : expr; args : expr list }
  (* [macro()] textual substitution. Same shape as [ECmakeFunction] at
     this slice; differences in scope/ARGN semantics are deferred. *)
  | ECmakeMacro of { name : expr; params : string list; body : expr }
  | ECmakeInclude of { file : expr; optional : bool }
  (* See [EAtVar] in the theory fragment for semantics. Emit-only literal
     [@key@] injection, no eval effect, no surface-specific behavior. *)
  | ECmakeAtVar of string
  (* [math(EXPR <out> "<exp>" [OUTPUT_FORMAT ...])] — integer arithmetic
     evaluated by cmake. Eval is a stub (returns VUnit and leaves [out]
     unbound); emit faithfully renders the cmake command. *)
  | ECmakeMath of { exp : string; out : string }
  (* Additional cmake_op subcommands — emit-faithful, eval-stub. *)
  | ECmakeEnableLanguage of { langs : string list; optional : bool }
  | ECmakePolicySet of { id : string; new_ : bool }
  | ECmakeLanguageCall of { cmd : string; args : expr list }
  | ECmakeLanguageEval of { code : string }
  | ECmakeLanguageGetLogLevel of { out : string }
  | ECmakeVariableWatch of { var : string; command : string option }
  | ECmakeExecuteProcess of {
      commands : expr list list;
      working_directory : expr option;
      timeout : float option;
      result_variable : string option;
      output_variable : string option;
      error_variable : string option;
      input_file : expr option;
      output_file : expr option;
      error_file : expr option;
      output_quiet : bool;
      error_quiet : bool;
      output_strip_trailing_whitespace : bool;
      error_strip_trailing_whitespace : bool;
      command_error_is_fatal : string option;
    }
  | ECmakeIncludeGuard of { scope : string }
  | ECmakeQuoteCmd of string
  (* [foreach(<loop_var> <items>...)] — list iteration. On each iteration
     [loop_var] is set in the caller's variable scope; **the binding
     persists after the loop ends**, retaining its final iteration
     value (cmake's actual behavior — no scope boundary at endforeach).
     If [items] is empty, no binding happens and any prior value is
     left untouched. The loop var leaks; that's the design choice
     cmake made and it is *not* the F2 function-call frame.

     Three forms in production:
     - [Yc_foreach { loop_var; items; commands }] — literal item list
     - [Yc_foreach_in { loop_var; lists; items; commands }] — IN LISTS / IN ITEMS
     - [Yc_foreach_range { ... }], [Yc_foreach_zip { ... }] — deferred

     [break()] / [continue()] are not yet modeled. Items lists that
     contain a [${LIST}]-shaped string are flowed to cmake as one
     "item" and cmake splits them at runtime; tiny eval treats each
     [items] entry as one iteration. *)
  | ECmakeForeach of {
      loop_var : string;
      items : expr list;
      body : expr;
    }
  (* [foreach(<var> RANGE [start] stop [step])] — integer iteration. Same
     scope discipline as ECmakeForeach (no restore on exit). *)
  | ECmakeForeachRange of {
      loop_var : string;
      start : int option;
      stop : int;
      step : int option;
      body : expr;
    }
  (* [foreach(<var1> <var2> ... IN ZIP_LISTS <list1> <list2> ...)] —
     parallel iteration over multiple lists. Eval at this slice
     iterates one step per shortest list and binds each loop_var to
     the empty string (we don't model list-deref splitting at
     eval-time). Emit faithfully renders the cmake form. *)
  | ECmakeForeachZip of {
      loop_vars : string list;
      lists : string list;
      body : expr;
    }
  (* [separate_arguments(<var> <mode> [PROGRAM] [SEPARATE_ARGS] [<input>])]
     — string tokenization into a list. Eval stub: bind [var] to the
     input string (no actual tokenization in tiny). *)
  | ECmakeSeparateArguments of {
      var : string;
      mode : string;
      input : expr option;
    }
  (* [while(cond) ... endwhile()] — condition loop. No new scope; the
     body re-evaluates the condition each iteration. break / continue
     are caught by the surrounding loop. Bounded by [while_max_iter] to
     keep eval terminating on accidental infinite loops. *)
  | ECmakeWhile of { cond : expr; body : expr }
  (* [break()] / [continue()] — raise [Break_loop] / [Continue_loop] at
     eval, caught by the innermost surrounding loop. *)
  | ECmakeBreak
  | ECmakeContinue
  (* [block([SCOPE_FOR VARIABLES] [PROPAGATE <var>]) ... endblock()] —
     introduces a new variable frame. On exit, the named [propagate]
     var (if non-empty) is merged into the parent's locals via
     [pop_frame ~propagate]. Scope policies (SCOPE_FOR POLICIES) are
     emit-only at this slice. *)
  | ECmakeBlock of {
      scope_vars : string list;   (* SCOPE_FOR VARIABLES name list, emit-only *)
      propagate : string;          (* single var, "" means none *)
      body : expr;
    }
  (* [return([PROPAGATE <vars>...])] — exits the enclosing function via
     [Return_function] exception; blocks / loops re-raise on the way
     out. [propagate_vars] is the list of var names whose current
     values (at the return site) should be lifted to the caller's
     frame on catch. Per P13, this skips any enclosing block's own
     PROPAGATE list (verified in P22). *)
  | ECmakeReturn of { propagate_vars : string list }

let bind_params env params arg_values =
  match List.zip params arg_values with
  | Ok pairs ->
    List.fold pairs ~init:env ~f:(fun env (name, value) ->
      set_var env ~key:name ~data:value)
  | Unequal_lengths ->
    fail
      "apply: arity mismatch — function expects %d params, got %d args"
      (List.length params) (List.length arg_values)

let eval_args ~eval env args =
  let env, rev_values =
    List.fold args ~init:(env, []) ~f:(fun (env, acc) arg ->
      let env, value = eval env arg in
      env, value :: acc)
  in
  env, List.rev rev_values

let eval_case ~eval env = function
  | ECmakeProject { name; languages; version } ->
    Some (set_project env { name; languages; version }, VUnit)
  | ECmakeMinimumRequired version ->
    Some (set_cmake_min_version env version, VUnit)
  | ECmakeMessage { mode; texts } ->
    let env, texts = eval_string_list ~eval env texts in
    Some (add_message env mode texts, VUnit)
  | ECmakeFunction { name; params; body } ->
    let env, name = eval_string ~eval env name in
    Some (set_function env name { params; body; is_macro = false }, VUnit)
  | ECmakeMacro { name; params; body } ->
    let env, name = eval_string ~eval env name in
    Some (set_function env name { params; body; is_macro = true }, VUnit)
  | ECmakeApply { name; args } ->
    let env, name = eval_string ~eval env name in
    (match find_function env name with
     | None ->
       (* Lenient: cmake routinely invokes functions defined by
          [include(SomeModule)] whose body the tiny eval does not
          simulate. Evaluate the args for their side effects and
          return [VUnit] so the surrounding sequence keeps going. *)
       let env, _ = eval_args ~eval env args in
       Some (env, VUnit)
     | Some { params; body; is_macro = false } ->
       let env, arg_values = eval_args ~eval env args in
       (* Function: push a frame, bind params, evaluate body, catch
          Return_function for PROPAGATE. See R4-b.3 docs. *)
       let caller_depth = List.length env.frames in
       let env = push_frame env in
       let env = bind_params env params arg_values in
       (match eval env body with
        | env, result -> Some (pop_frame env, result)
        | exception Return_function { env_at_return; propagated } ->
          let rec unwind env =
            if List.length env.frames > caller_depth + 1 then
              unwind (pop_frame env)
            else env
          in
          let env_at_return = unwind env_at_return in
          let env_after_pop = pop_frame env_at_return in
          let env_after_pop =
            List.fold propagated ~init:env_after_pop
              ~f:(fun env (name, vopt) ->
                match vopt with
                | Some v -> set_var env ~key:name ~data:v
                | None -> remove_var env name)
          in
          Some (env_after_pop, VUnit))
     | Some { params; body; is_macro = true } ->
       (* Macro: textual substitution. cmake binds params + ARGN /
          ARGV / ARGC / ARGVn as variables in the *caller's* frame for
          the duration of the body (P25/P26). No frame is pushed; free
          writes inside the body leak to the caller (P24). On exit we
          restore the caller's prior bindings for these specific
          names. Free var writes are NOT undone — they persist. *)
       let env, arg_values = eval_args ~eval env args in
       let arg_strings = List.map arg_values ~f:expect_string in
       let n_params = List.length params in
       let n_args = List.length arg_strings in
       let extras = List.drop arg_strings n_params in
       let macro_bindings : (string * value) list =
         List.mapi params ~f:(fun i p ->
           let v =
             match List.nth arg_strings i with
             | Some s -> s
             | None -> ""
           in
           (p, VString v))
         @ [ "ARGN", VString (String.concat ~sep:";" extras);
             "ARGV", VString (String.concat ~sep:";" arg_strings);
             "ARGC", VString (Int.to_string n_args);
           ]
         @ List.mapi arg_strings ~f:(fun i s ->
             (Printf.sprintf "ARGV%d" i, VString s))
       in
       (* Save caller's prior values (or absence) for each bound name. *)
       let saved =
         List.map macro_bindings ~f:(fun (name, _) ->
           (name, find_var env name))
       in
       (* Bind the macro params + ARG* in the caller's frame. *)
       let env =
         List.fold macro_bindings ~init:env ~f:(fun env (k, v) ->
           set_var env ~key:k ~data:v)
       in
       let env, result = eval env body in
       (* Restore the caller's prior bindings. Free writes inside the
          body are unaffected (they targeted other names). *)
       let env =
         List.fold saved ~init:env ~f:(fun env (name, prev) ->
           match prev with
           | Some v -> set_var env ~key:name ~data:v
           | None -> remove_var env name)
       in
       Some (env, result))
  | ECmakeInclude { file; optional = _ } ->
    let env, file = eval_string ~eval env file in
    Some (add_include env file, VUnit)
  | ECmakeAtVar _ -> Some (env, VUnit)
  | ECmakeMath _ -> Some (env, VUnit)
  | ECmakeEnableLanguage _ | ECmakePolicySet _
  | ECmakeLanguageEval _ | ECmakeVariableWatch _
  | ECmakeIncludeGuard _ | ECmakeQuoteCmd _ ->
    Some (env, VUnit)
  | ECmakeLanguageCall _ -> Some (env, VUnit)
  | ECmakeLanguageGetLogLevel { out } ->
    Some (set_var env ~key:out ~data:(VString "STATUS"), VUnit)
  | ECmakeExecuteProcess { result_variable; output_variable; error_variable; _ } ->
    let env = match result_variable with
      | Some v -> set_var env ~key:v ~data:(VString "0")
      | None -> env
    in
    let env = match output_variable with
      | Some v -> set_var env ~key:v ~data:(VString "")
      | None -> env
    in
    let env = match error_variable with
      | Some v -> set_var env ~key:v ~data:(VString "")
      | None -> env
    in
    Some (env, VUnit)
  | ECmakeForeachZip { loop_vars; lists = _; body } ->
    (* Eval stub: bind each loop_var to empty for one iteration and
       evaluate the body once. Real cmake iterates zipped elements; we
       defer that until needed. *)
    let env = List.fold loop_vars ~init:env ~f:(fun env v ->
      set_var env ~key:v ~data:(VString "")) in
    (match eval env body with
     | env, _ -> Some (env, VUnit)
     | exception Break_loop -> Some (env, VUnit)
     | exception Continue_loop -> Some (env, VUnit))
  | ECmakeForeachRange { loop_var; start; stop; step; body } ->
    let s = Option.value start ~default:0 in
    let step = Option.value step ~default:1 in
    let rec loop env i =
      if (step > 0 && i > stop) || (step < 0 && i < stop) || step = 0 then env
      else
        let env = set_var env ~key:loop_var ~data:(VInt i) in
        let env =
          try
            let env, _ = eval env body in
            env
          with Continue_loop -> env
        in
        loop env (i + step)
    in
    let env = try loop env s with Break_loop -> env in
    Some (env, VUnit)
  | ECmakeWhile { cond; body } ->
    (* Bounded condition loop. Re-evaluate [cond] each iteration; if
       truthy, evaluate [body]. break / continue caught here. The
       bound is a tiny safety net — real cmake doesn't enforce one. *)
    let max_iter = 10_000 in
    let rec loop env n =
      if n >= max_iter then
        fail "while: exceeded %d iterations (tiny eval safety bound)" max_iter
      else
        let env, cond_v = eval env cond in
        if expect_bool cond_v then
          let env =
            try
              let env, _ = eval env body in
              env
            with Continue_loop -> env
          in
          loop env (n + 1)
        else env
    in
    let env = try loop env 0 with Break_loop -> env in
    Some (env, VUnit)
  | ECmakeBreak -> raise Break_loop
  | ECmakeContinue -> raise Continue_loop
  | ECmakeReturn { propagate_vars } ->
    (* Capture the propagate values at the return site (which may be
       inside several blocks). The catch site uses these directly so
       intermediate frames being unwound don't lose the values.
       Per P22 / P13, any enclosing block's own PROPAGATE list is
       discarded on unwind. *)
    let propagated =
      List.map propagate_vars ~f:(fun name -> (name, find_var env name))
    in
    raise (Return_function { env_at_return = env; propagated })
  | ECmakeBlock { propagate; body; scope_vars = _ } ->
    (* Per doc/cmake_scope_and_control_flow.md: push a frame; evaluate
       body; on normal exit, [pop_frame ~propagate] merges the named
       var into the parent's locals (also handles the unset case via
       absence in the popped frame's locals). On unwinding via
       break / continue / return, the block's own [propagate] list is
       skipped (verified by P22). *)
    let propagate_names =
      if String.is_empty propagate then [] else [ propagate ]
    in
    let env = push_frame env in
    (match eval env body with
     | env, _ -> Some (pop_frame ~propagate:propagate_names env, VUnit)
     | exception Break_loop ->
       (* Pop frame without propagating, then re-raise. *)
       let _ = pop_frame env in
       raise Break_loop
     | exception Continue_loop ->
       let _ = pop_frame env in
       raise Continue_loop)
  | ECmakeSeparateArguments { var; input; _ } ->
    let env, value = match input with
      | Some e ->
        let env, s = eval_string ~eval env e in
        env, VString s
      | None ->
        (match find_var env var with
         | Some v -> env, v
         | None -> env, VString "")
    in
    Some (set_var env ~key:var ~data:value, VUnit)
  | ECmakeForeach { loop_var; items; body } ->
    (* No-restore semantics, matching cmake: [loop_var] leaks past
       [endforeach] with its final iteration value. Empty [items]
       leaves any prior binding untouched. [break()] / [continue()]
       inside [body] are caught here. *)
    let env, item_strings = eval_string_list ~eval env items in
    let env =
      try
        List.fold item_strings ~init:env ~f:(fun env item ->
          let env = set_var env ~key:loop_var ~data:(VString item) in
          try
            let env, _ = eval env body in
            env
          with Continue_loop -> env)
      with Break_loop -> env
    in
    Some (env, VUnit)
  | _ -> None
