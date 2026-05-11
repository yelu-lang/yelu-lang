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
    Some (set_function env name { params; body }, VUnit)
  | ECmakeMacro { name; params; body } ->
    let env, name = eval_string ~eval env name in
    (* At eval time we treat macro as function (function-call scope);
       cmake's textual-substitution semantics is a refinement. *)
    Some (set_function env name { params; body }, VUnit)
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
     | Some { params; body } ->
       let env, arg_values = eval_args ~eval env args in
       let saved_vars = env.vars in
       let env = bind_params env params arg_values in
       let env, result = eval env body in
       Some ({ env with vars = saved_vars }, result))
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
  | ECmakeForeach { loop_var; items; body } ->
    (* No-restore semantics, matching cmake: [loop_var] leaks past
       [endforeach] with its final iteration value. Empty [items]
       leaves any prior binding untouched. *)
    let env, item_strings = eval_string_list ~eval env items in
    let env =
      List.fold item_strings ~init:env ~f:(fun env item ->
        let env = set_var env ~key:loop_var ~data:(VString item) in
        let env, _ = eval env body in
        env)
    in
    Some (env, VUnit)
  | _ -> None
