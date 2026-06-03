(* Tests for the cmake-style dynamic-scope function theory in yelu_tiny.

   These tests are written in "language / theory expansion" mode: instead
   of feeding production yelu_cmake AST through the bridge, they construct
   tiny IR directly and assert eval-time behavior. The goal is to pin
   down the semantics of [EDynFunction] / [EApply] (and their cmake-
   flavored surface twins [ECmakeFunction] / [ECmakeApply]) at the IR
   level, independent of the bridge or emit pipeline.

   F2 design choices being tested:

   - Argument evaluation order: left-to-right, call-by-value (args are
     fully evaluated before the body runs).
   - Scope: classic *dynamic scope* implemented via *shallow binding*
     (Bobrow & Wegbreit 1973; EOPL terminology). On entry, save the
     entire current [env.vars]. Bind params as fresh vars. Evaluate
     body. On return, restore the saved [env.vars]. Variable *reads*
     inside the body see the caller's scope (dynamic-scope semantics);
     variable *writes* are local to the call frame, which is cmake's
     "writes local by default" wrinkle. Side effects on non-variable
     env state (targets, tests, install_rules, custom_*,
     target_properties, messages, …) persist across the call.
   - No closures / lexical capture at definition time. The body is
     re-evaluated against the env at each call.
   - Arity mismatch fails. Macros, ARGV/ARGC/ARGN, and PARENT_SCOPE are
     deferred.

   The name [EDynFunction] (rather than the unmarked [EFunction]) leaves
   the unmarked name available for a future lexically-scoped / closure-
   style function in Yelu2.

   Observation strategy: dynamic scope with local-default writes means
   variables set inside a function body do *not* leak to the caller. To
   observe what a function actually did, these tests use side effects on
   non-variable env state, primarily [env.messages] (via
   [ECmakeMessage]). Each message records the texts passed at call time,
   which lets us check "the function saw arg value X" without depending
   on var leakage. *)

open Base
open Yelu_langs.Yelu_cmake
open Yelu_langs.Yelu_cmake_normal_cmake_op
open Yelu_langs.Yelu_cmake_target
open Yelu_langs.Yelu_cmake_cmake_op
open Yelu_langs.Yelu_cmake_convert

(* Helper: evaluate a Yelu1 program from empty env and return (env, value). *)
let eval_from_empty expr = eval_yelu_cmake_expr empty_env expr

(* Helper: assert a specific exception substring fires. *)
let[@warning "-32"] expect_eval_error name expr ~substring =
  Alcotest.test_case name `Quick (fun () ->
    match eval_from_empty expr with
    | exception Eval_error msg ->
      Alcotest.(check bool)
        (Printf.sprintf "Eval_error contains %S" substring)
        true
        (String.is_substring msg ~substring)
    | _ ->
      Alcotest.failf "expected Eval_error containing %S; eval succeeded" substring)

(* Convenience: emit a probe message capturing one or more text values.
   Uses the existing [ECmakeMessage] surface form. *)
let probe_message texts = ECmakeMessage { mode = ""; texts }

(* Convenience: extract the recorded message texts from an env in
   declaration order (oldest first). *)
let message_texts env =
  List.map env.messages ~f:(fun m -> m.texts)

(* --- Function definition records into env.functions. --- *)

let function_definition_records_in_env =
  Alcotest.test_case "function definition registers in env.functions" `Quick
    (fun () ->
      let prog =
        ECmakeFunction
          { name = EString "noop";
            params = [];
            body = EUnit }
      in
      let env, value = eval_from_empty prog in
      Alcotest.(check bool) "result is VUnit" true (equal_value value VUnit);
      Alcotest.(check bool) "function recorded under its name" true
        (Option.is_some (find_function env "noop"));
      Alcotest.(check bool) "no var side effect from definition alone" true
        (Map.is_empty (top_frame env).locals))

(* --- Function call binds args; observed via message side effect. --- *)

let function_call_binds_args =
  Alcotest.test_case "applied function sees param values via probe" `Quick
    (fun () ->
      let prog =
        ESeq
          [ ECmakeFunction
              { name = EString "echo";
                params = [ "x" ];
                body = probe_message [ EVar "x" ] };
            ECmakeApply
              { name = EString "echo"; args = [ EString "hello" ] };
          ]
      in
      let env, _ = eval_from_empty prog in
      Alcotest.(check (list (list string)))
        "message captured the arg value at call time"
        [ [ "hello" ] ] (message_texts env))

(* --- Function-call scope: params don't leak after return. --- *)

let function_params_do_not_leak =
  Alcotest.test_case "function params are scoped out after call" `Quick
    (fun () ->
      let prog =
        ESeq
          [ ECmakeFunction
              { name = EString "echo";
                params = [ "x" ];
                body = probe_message [ EVar "x" ] };
            ECmakeApply
              { name = EString "echo"; args = [ EString "hello" ] };
          ]
      in
      let env, _ = eval_from_empty prog in
      Alcotest.(check bool) "x is unbound after return" true
        (Option.is_none (find_var env "x")))

(* --- Function-call scope: vars set inside body don't leak. --- *)

let function_local_vars_do_not_leak =
  Alcotest.test_case "vars set inside function body are scoped out" `Quick
    (fun () ->
      let prog =
        ESeq
          [ ECmakeFunction
              { name = EString "inner";
                params = [];
                body =
                  ESeq
                    [ ESetVar ("LOCAL", EString "scratch");
                      probe_message [ EVar "LOCAL" ];
                    ] };
            ECmakeApply { name = EString "inner"; args = [] };
          ]
      in
      let env, _ = eval_from_empty prog in
      Alcotest.(check bool) "LOCAL is gone after call" true
        (Option.is_none (find_var env "LOCAL"));
      Alcotest.(check (list (list string)))
        "the body did see LOCAL during the call"
        [ [ "scratch" ] ] (message_texts env))

(* --- Function-call scope: outer var shadowed by param, restored after. --- *)

let function_shadowing_restores_outer =
  Alcotest.test_case "param shadows outer var; outer restored after" `Quick
    (fun () ->
      let prog =
        ESeq
          [ ESetVar ("x", EString "outer");
            ECmakeFunction
              { name = EString "see_x";
                params = [ "x" ];
                body = probe_message [ EVar "x" ] };
            ECmakeApply
              { name = EString "see_x"; args = [ EString "inner" ] };
          ]
      in
      let env, _ = eval_from_empty prog in
      Alcotest.(check (list (list string)))
        "param value (inner) was visible inside body"
        [ [ "inner" ] ] (message_texts env);
      Alcotest.(check bool) "x is restored to outer after return" true
        (Poly.equal (find_var env "x") (Some (VString "outer"))))

(* --- Function-call scope: non-variable env state leaks. --- *)

let function_target_decls_leak_across_call =
  Alcotest.test_case "target decls inside function persist after return"
    `Quick (fun () ->
      let prog =
        ESeq
          [ ECmakeFunction
              { name = EString "declare_app";
                params = [];
                body =
                  ECmakeAddExecutable
                    { name = EString "app";
                      sources = [ EString "main.c" ] };
              };
            ECmakeApply { name = EString "declare_app"; args = [] };
          ]
      in
      let env, _ = eval_from_empty prog in
      Alcotest.(check bool) "app target survives the call" true
        (Option.is_some (find_target env "app")))

(* --- Dynamic scope: body reads caller's vars at call time. --- *)

let function_body_sees_callers_var =
  Alcotest.test_case
    "dynamic scope: body sees variables bound by the caller"
    `Quick (fun () ->
      let prog =
        ESeq
          [ ESetVar ("greeting", EString "hi");
            ECmakeFunction
              { name = EString "echo_greeting";
                params = [];
                body = probe_message [ EVar "greeting" ] };
            ECmakeApply { name = EString "echo_greeting"; args = [] };
          ]
      in
      let env, _ = eval_from_empty prog in
      Alcotest.(check (list (list string)))
        "function picked up the caller's `greeting`"
        [ [ "hi" ] ] (message_texts env);
      Alcotest.(check bool) "caller's `greeting` still bound after call" true
        (Poly.equal (find_var env "greeting") (Some (VString "hi"))))

(* --- Left-to-right call-by-value: args are fully evaluated before
       the function body runs, in declaration order. --- *)

let args_evaluated_left_to_right =
  Alcotest.test_case "args evaluated left-to-right, call-by-value" `Quick
    (fun () ->
      let prog =
        ESeq
          [ ECmakeFunction
              { name = EString "trace3";
                params = [ "a"; "b"; "c" ];
                body = probe_message [ EVar "a"; EVar "b"; EVar "c" ] };
            ECmakeApply
              { name = EString "trace3";
                args =
                  [ EString "first"; EString "second"; EString "third" ] };
          ]
      in
      let env, _ = eval_from_empty prog in
      Alcotest.(check (list (list string)))
        "args bound to params in positional order"
        [ [ "first"; "second"; "third" ] ] (message_texts env))

(* --- Unknown function: surface is lenient, theory is strict. ---

   Surface [ECmakeApply] is lenient because production cmake routinely
   calls functions loaded via [include(SomeModule)] — bodies whose
   tiny eval does not simulate. A lenient apply lets the surrounding
   sequence keep running and lets emit still produce a faithful
   function-call line. Theory [EApply] stays strict so we can pin
   down the pure operational semantics in tests. *)

let unknown_surface_apply_is_lenient =
  Alcotest.test_case "ECmakeApply on unknown function is a no-op" `Quick
    (fun () ->
      let prog =
        ESeq
          [ ECmakeApply { name = EString "nope"; args = [ EString "ignored" ] };
            probe_message [ EString "after_apply" ];
          ]
      in
      let env, value = eval_from_empty prog in
      Alcotest.(check bool) "final result is VUnit" true
        (equal_value value VUnit);
      Alcotest.(check (list (list string)))
        "subsequent probe still runs"
        [ [ "after_apply" ] ] (message_texts env))

let unknown_theory_apply_fails =
  Alcotest.test_case "EApply on unknown function (theory) fails" `Quick
    (fun () ->
      match eval_yelu_cmake_normal_expr empty_env (EApply { name = EString "nope"; args = [] }) with
      | exception Eval_error msg ->
        Alcotest.(check bool)
          "Eval_error mentions unknown function" true
          (String.is_substring msg ~substring:"unknown function")
      | _ ->
        Alcotest.failf "expected Eval_error; theory EApply was lenient")

(* --- Arity is now LENIENT (cmake-compatible).
   Was: strict arity-mismatch raised an error.
   Now: missing args bind to VString "", excess args bind to
   ${ARGN}. cmake's function() doesn't enforce strict arity —
   the variadic-tail-via-ARGN pattern is idiomatic (e.g., fmt's
   set_verbose declares 4 params but is called with 6 args; the
   extras form the docstring via join(doc ${ARGN})).
   The "needs_two only_one" call now binds a="only_one", b="". *)
let arity_mismatch_is_lenient =
  Alcotest.test_case "lenient arity: missing args bind to empty" `Quick
    (fun () ->
      let _, value =
        eval_yelu_cmake_expr empty_env
          (ESeq
             [ ECmakeFunction
                 { name = EString "needs_two";
                   params = [ "a"; "b" ];
                   body = EVar "b" };
               ECmakeApply
                 { name = EString "needs_two";
                   args = [ EString "only_one" ] };
             ])
      in
      Alcotest.(check string) "b bound to empty for missing arg"
        "(VString\"\")"
        (Sexp.to_string ([%sexp_of: value] value)))

(* --- Re-definition: later definition wins (cmake redefines on duplicate). --- *)

let redefining_function_overwrites =
  Alcotest.test_case "redefining a function replaces the prior binding" `Quick
    (fun () ->
      let prog =
        ESeq
          [ ECmakeFunction
              { name = EString "tag";
                params = [];
                body = probe_message [ EString "first" ] };
            ECmakeFunction
              { name = EString "tag";
                params = [];
                body = probe_message [ EString "second" ] };
            ECmakeApply { name = EString "tag"; args = [] };
          ]
      in
      let env, _ = eval_from_empty prog in
      Alcotest.(check (list (list string)))
        "second definition is the one that ran"
        [ [ "second" ] ] (message_texts env))

(* --- Yelu1 / Yelu2 round-trip preserves function semantics. --- *)

let lift_lower_roundtrip_for_function =
  (* Function definitions are stored in [env.functions] as IR bodies.
     Lifting a Yelu1 program changes the body's surface form (e.g.
     [ECmakeMessage] becomes [EMessage]), so the stored function decl
     diverges structurally between Yelu1 and Yelu2 even when the program
     is behaviorally equivalent. This test compares *observable*
     side effects (messages, targets, vars) across the three eval
     points instead of strict env equality. *)
  Alcotest.test_case
    "lift / lower preserves observable effects of a define-and-apply"
    `Quick (fun () ->
      let prog =
        ESeq
          [ ECmakeFunction
              { name = EString "echo";
                params = [ "x" ];
                body = probe_message [ EVar "x" ] };
            ECmakeApply
              { name = EString "echo"; args = [ EString "hi" ] };
          ]
      in
      let env_a, value_a = eval_yelu_cmake_expr empty_env prog in
      let lifted = to_normal prog in
      let env_b, value_b = eval_yelu_cmake_normal_expr empty_env lifted in
      let lowered = from_normal lifted in
      let env_c, value_c = eval_yelu_cmake_expr empty_env lowered in
      Alcotest.(check bool) "lift preserves return value" true
        (equal_value value_a value_b);
      Alcotest.(check bool) "lower preserves return value" true
        (equal_value value_a value_c);
      Alcotest.(check (list (list string)))
        "lift preserves observable messages"
        (message_texts env_a) (message_texts env_b);
      Alcotest.(check (list (list string)))
        "lower preserves observable messages"
        (message_texts env_a) (message_texts env_c))

(* --- Theory-side: pure EDynFunction / EApply (no cmake prefix) work
       under the Yelu2 evaluator with identical semantics. --- *)

let theory_form_works =
  Alcotest.test_case "EDynFunction / EApply (theory side) under Yelu2" `Quick
    (fun () ->
      let prog =
        ESeq
          [ EDynFunction
              { name = EString "echo";
                params = [ "x" ];
                body = EMessage { mode = ""; texts = [ EVar "x" ] } };
            EApply { name = EString "echo"; args = [ EString "theory" ] };
          ]
      in
      let env, _ = eval_yelu_cmake_normal_expr empty_env prog in
      Alcotest.(check (list (list string)))
        "theory-side body captured arg via message"
        [ [ "theory" ] ] (message_texts env);
      Alcotest.(check bool) "theory-side params don't leak" true
        (Option.is_none (find_var env "x")))

let () =
  Alcotest.run "yelu_tiny_function"
    [ ( "definition_and_apply",
        [ function_definition_records_in_env;
          function_call_binds_args;
          function_params_do_not_leak;
          function_local_vars_do_not_leak;
          function_shadowing_restores_outer;
          function_target_decls_leak_across_call;
          function_body_sees_callers_var;
          args_evaluated_left_to_right;
          redefining_function_overwrites;
        ] );
      ( "errors",
        [ unknown_surface_apply_is_lenient;
          unknown_theory_apply_fails;
          arity_mismatch_is_lenient;
        ] );
      ( "translate_and_theory_side",
        [ lift_lower_roundtrip_for_function;
          theory_form_works;
        ] );
    ]
