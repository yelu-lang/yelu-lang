(* Tests for [ECmakeForeach] scope semantics in yelu_tiny.

   The key design decision pinned here: cmake's [foreach()] does NOT
   introduce a new scope. The loop variable is bound in the caller's
   variable scope and **leaks past [endforeach]** with its final
   iteration value. This is the opposite of [function() ... endfunction()]
   (which saves/restores variable bindings — see test_yelu_tiny_function).

   These tests exist precisely because the bridge tests in
   test_yelu_tiny_steps are emit-only and cannot observe this
   distinction. Without these eval-level checks the bridge could
   silently implement the wrong scope discipline (initially it did:
   2026-05-10 had a save/bind/eval/restore implementation patterned
   off F2 that passed every emit test but had wrong semantics for any
   downstream consumer reading [loop_var] after the loop). *)

open Base
open Yelu_langs.Yelu_cmake
open Yelu_langs.Yelu_surface_cmake_cmake_op

let eval_from_empty expr = Yelu_langs.Yelu_cmake_convert.eval_yelu_cmake_expr empty_env expr

(* --- After the loop, loop_var retains the final iteration value. --- *)

let loop_var_leaks_with_final_value =
  Alcotest.test_case "after foreach, loop_var retains final iteration value"
    `Quick
    (fun () ->
      let prog =
        ECmakeForeach
          { loop_var = "X";
            items = [ EString "a"; EString "b"; EString "c" ];
            body = EUnit }
      in
      let env, _ = eval_from_empty prog in
      Alcotest.(check (option string))
        "X is bound to 'c' (the final item)"
        (Some "c")
        (Option.map (find_var env "X") ~f:(function
          | VString s -> s
          | _ -> "<non-string>")))

(* --- After the loop, an outer binding of the same name is overwritten. ---
   This is the opposite of function-call scope; see the F2 tests for the
   restore-on-exit story. *)

let loop_var_overwrites_outer_binding =
  Alcotest.test_case "outer binding of loop_var is overwritten (no restore)"
    `Quick
    (fun () ->
      let prog =
        ESeq
          [ ESetVar ("X", EString "outer");
            ECmakeForeach
              { loop_var = "X";
                items = [ EString "a"; EString "b" ];
                body = EUnit };
          ]
      in
      let env, _ = eval_from_empty prog in
      Alcotest.(check (option string))
        "X is now 'b', not 'outer'"
        (Some "b")
        (Option.map (find_var env "X") ~f:(function
          | VString s -> s
          | _ -> "<non-string>")))

(* --- Empty items list: no binding happens; any prior value is preserved. ---
   cmake's foreach with zero items doesn't enter the loop body at all,
   so the loop_var is not assigned. *)

let empty_items_preserves_prior_binding =
  Alcotest.test_case "foreach with empty items leaves prior binding intact"
    `Quick
    (fun () ->
      let prog =
        ESeq
          [ ESetVar ("X", EString "outer");
            ECmakeForeach { loop_var = "X"; items = []; body = EUnit };
          ]
      in
      let env, _ = eval_from_empty prog in
      Alcotest.(check (option string))
        "X stays 'outer'"
        (Some "outer")
        (Option.map (find_var env "X") ~f:(function
          | VString s -> s
          | _ -> "<non-string>")))

let empty_items_with_unbound_var_stays_unbound =
  Alcotest.test_case "foreach with empty items and no prior binding leaves var unbound"
    `Quick
    (fun () ->
      let prog =
        ECmakeForeach { loop_var = "X"; items = []; body = EUnit }
      in
      let env, _ = eval_from_empty prog in
      Alcotest.(check bool) "X is unbound"
        true (Option.is_none (find_var env "X")))

(* --- Body observation: the body sees the current iteration value. ---
   Use env.messages as a side-effect channel so we can observe one
   message per iteration capturing the loop_var's value at that step. *)

let body_sees_each_iteration_value =
  Alcotest.test_case "loop body observes each iteration value in order"
    `Quick
    (fun () ->
      let prog =
        ECmakeForeach
          { loop_var = "X";
            items = [ EString "a"; EString "b"; EString "c" ];
            body =
              ECmakeMessage { mode = ""; texts = [ EVar "X" ] };
          }
      in
      let env, _ = eval_from_empty prog in
      let msg_texts = List.map env.messages ~f:(fun m -> m.texts) in
      Alcotest.(check (list (list string)))
        "messages captured each iteration in order"
        [ [ "a" ]; [ "b" ]; [ "c" ] ]
        msg_texts)

let () =
  Alcotest.run "yelu_tiny_foreach"
    [ ( "scope_discipline",
        [ loop_var_leaks_with_final_value;
          loop_var_overwrites_outer_binding;
          empty_items_preserves_prior_binding;
          empty_items_with_unbound_var_stays_unbound;
          body_sees_each_iteration_value;
        ] );
    ]
