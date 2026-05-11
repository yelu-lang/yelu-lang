(* Tests for cmake's block() / return() / set(PARENT_SCOPE) / macro
   semantics in yelu_tiny. Ports of the 24 probes documented in
   doc/cmake_block_return_semantics.md.

   Each test constructs tiny IR directly (no bridge) and asserts the
   observable env state matches the verified cmake output. The tests
   exist because emit-only bridge assertions cannot distinguish a
   wrong scope model from a right one — a live-view model would fail
   P15/P20/P21; save-and-restore without PROPAGATE would fail P2/P9;
   "exit innermost" return would fail P10/P11. *)

open Base
open Yelu_langs.Yelu_tiny
open Yelu_langs.Yelu_surface_cmake_cmake_op
open Yelu_langs.Yelu_surface_cmake_store

let eval_from_empty expr =
  Yelu_langs.Yelu_tiny_translate.eval_yelu1_expr empty_env expr

(* Read X from the current top frame; returns Some string or None. *)
let read env name =
  match find_var env name with
  | Some (VString s) -> Some s
  | Some (VBool b) -> Some (if b then "ON" else "OFF")
  | Some (VInt n) -> Some (Int.to_string n)
  | Some _ -> Some "<other>"
  | None -> None

let check_some name expected env var =
  Alcotest.(check (option string))
    (Printf.sprintf "%s — %s" name var)
    (Some expected)
    (read env var)

let check_none name env var =
  Alcotest.(check (option string))
    (Printf.sprintf "%s — %s should be unbound" name var)
    None
    (read env var)

(* Convenience: build a block. *)
let block ?(propagate = "") ?(scope_vars = []) body =
  ECmakeBlock { scope_vars; propagate; body }

let set_var_e name value =
  ESetVar (name, EString value)

(* === Probe P1 — block scope: writes don't leak === *)
let p1_block_no_leak =
  Alcotest.test_case "P1: block writes don't leak past endblock" `Quick
    (fun () ->
      let prog =
        ESeq
          [ set_var_e "X" "outer";
            block (set_var_e "X" "inside");
          ]
      in
      let env, _ = eval_from_empty prog in
      check_some "P1" "outer" env "X")

(* === Probe P2 — block(PROPAGATE X): named var lifts === *)
let p2_block_propagate =
  Alcotest.test_case "P2: block(PROPAGATE X) lifts X to parent" `Quick
    (fun () ->
      let prog =
        ESeq
          [ set_var_e "X" "outer";
            set_var_e "Y" "outer-y";
            block ~propagate:"X"
              (ESeq
                 [ set_var_e "X" "from-block";
                   set_var_e "Y" "from-block-y";
                 ]);
          ]
      in
      let env, _ = eval_from_empty prog in
      check_some "P2" "from-block" env "X";
      check_some "P2" "outer-y" env "Y")

(* === Probe P3 — PROPAGATE name not modified inside === *)
let p3_propagate_unchanged =
  Alcotest.test_case "P3: PROPAGATE name never set inside keeps parent value"
    `Quick
    (fun () ->
      let prog =
        ESeq
          [ set_var_e "X" "outer";
            block ~propagate:"X" EUnit;
          ]
      in
      let env, _ = eval_from_empty prog in
      check_some "P3" "outer" env "X")

(* === Probe P4 — PROPAGATE + unset inside === *)
let p4_propagate_unset =
  Alcotest.test_case "P4: PROPAGATE + unset(X) inside lifts the unset" `Quick
    (fun () ->
      let prog =
        ESeq
          [ set_var_e "X" "outer";
            block ~propagate:"X" (ECmakeUnsetVar "X");
          ]
      in
      let env, _ = eval_from_empty prog in
      check_none "P4" env "X")

(* === Probe P5 — nested block === *)
let p5_nested_block =
  Alcotest.test_case "P5: nested blocks each restore independently" `Quick
    (fun () ->
      let prog =
        ESeq
          [ set_var_e "X" "outer";
            block
              (ESeq
                 [ set_var_e "X" "outer-block";
                   block (set_var_e "X" "inner-block");
                 ]);
          ]
      in
      let env, _ = eval_from_empty prog in
      check_some "P5" "outer" env "X")

(* === Probe P6 — PROPAGATE lifts one frame, not all === *)
let p6_propagate_one_frame =
  Alcotest.test_case
    "P6: inner-block PROPAGATE reaches outer block only, not top" `Quick
    (fun () ->
      let prog =
        ESeq
          [ set_var_e "X" "outer";
            block
              (block ~propagate:"X" (set_var_e "X" "from-inner"));
          ]
      in
      let env, _ = eval_from_empty prog in
      check_some "P6" "outer" env "X")

(* === Probe P7 — set(X PARENT_SCOPE) inside inner block === *)
let p7_parent_scope_in_block =
  Alcotest.test_case "P7: PARENT_SCOPE writes to enclosing block" `Quick
    (fun () ->
      (* Wrap in an outer block so the inner PARENT_SCOPE has a target;
         a PARENT_SCOPE at the root frame would (correctly) error. *)
      let prog =
        ESeq
          [ set_var_e "X" "outer";
            block ~propagate:"X"
              (block
                 (ECmakeSetParentScope
                    { name = "X"; value = EString "from-inner" }));
          ]
      in
      let env, _ = eval_from_empty prog in
      check_some "P7" "from-inner" env "X")

(* === Probe P14 — set(PARENT_SCOPE) inside function reaches caller === *)
let p14_parent_scope_function =
  Alcotest.test_case "P14: PARENT_SCOPE inside function reaches caller" `Quick
    (fun () ->
      let body =
        ECmakeSetParentScope { name = "X"; value = EString "from-function" }
      in
      let prog =
        ESeq
          [ set_var_e "X" "outer";
            ECmakeFunction { name = EString "do_thing"; params = []; body };
            ECmakeApply { name = EString "do_thing"; args = [] };
          ]
      in
      let env, _ = eval_from_empty prog in
      check_some "P14" "from-function" env "X")

(* === Probe P16 — block scope: outer X restored === *)
let p16_block_scope_restored =
  Alcotest.test_case "P16: block-local writes are dropped at endblock" `Quick
    (fun () ->
      let prog =
        ESeq
          [ set_var_e "X" "outer-v1";
            block (set_var_e "X" "local-set");
          ]
      in
      let env, _ = eval_from_empty prog in
      check_some "P16" "outer-v1" env "X")

(* === Probe P17 — function local-set doesn't leak; PARENT_SCOPE does === *)
let p17_function_mixed =
  Alcotest.test_case
    "P17: function local-set is dropped; PARENT_SCOPE-set leaks" `Quick
    (fun () ->
      let body =
        ESeq
          [ set_var_e "X" "function-X";  (* local write — dropped *)
            ECmakeSetParentScope { name = "Y"; value = EString "function-Y" };
          ]
      in
      let prog =
        ESeq
          [ set_var_e "X" "outer-v1";
            set_var_e "Y" "outer-y";
            ECmakeFunction { name = EString "do_thing"; params = []; body };
            ECmakeApply { name = EString "do_thing"; args = [] };
          ]
      in
      let env, _ = eval_from_empty prog in
      check_some "P17" "outer-v1" env "X";
      check_some "P17" "function-Y" env "Y")

(* === Probe P18 — multi-var PROPAGATE: set / unchanged / unset === *)
let p18_propagate_mixed =
  Alcotest.test_case
    "P18: PROPAGATE for multi-var: set / unchanged / unset all work" `Quick
    (fun () ->
      (* Single-var propagate per ECmakeBlock; build three nested blocks
         to test the three cases separately. The model promises the same
         per-var behavior. *)
      let prog_set =
        ESeq
          [ set_var_e "A" "outer-A";
            block ~propagate:"A" (set_var_e "A" "from-block");
          ]
      in
      let prog_unchanged =
        ESeq
          [ set_var_e "B" "outer-B";
            block ~propagate:"B" EUnit;
          ]
      in
      let prog_unset =
        ESeq
          [ set_var_e "C" "outer-C";
            block ~propagate:"C"
              (ESeq
                 [ set_var_e "C" "transient";
                   ECmakeUnsetVar "C";
                 ]);
          ]
      in
      let env_a, _ = eval_from_empty prog_set in
      let env_b, _ = eval_from_empty prog_unchanged in
      let env_c, _ = eval_from_empty prog_unset in
      check_some "P18.set" "from-block" env_a "A";
      check_some "P18.unchanged" "outer-B" env_b "B";
      check_none "P18.unset" env_c "C")

(* === Probe P15 / P20 / P21 — snapshot semantics: reads see snapshot, not live parent ===
   Critical test: after set(X v PARENT_SCOPE), reads of X inside the same frame
   should still return the snapshot value, not the new parent value. *)
let p_snapshot_function =
  Alcotest.test_case
    "P15/P20: function's own reads don't see its PARENT_SCOPE write" `Quick
    (fun () ->
      let body =
        ESeq
          [ ECmakeSetParentScope { name = "X"; value = EString "new-parent" };
            (* Inside the function, X should still resolve to "before-call"
               via the entry snapshot — not to "new-parent". *)
            ECmakeMessage { mode = ""; texts = [ EVar "X" ] };
          ]
      in
      let prog =
        ESeq
          [ set_var_e "X" "before-call";
            ECmakeFunction { name = EString "do_thing"; params = []; body };
            ECmakeApply { name = EString "do_thing"; args = [] };
          ]
      in
      let env, _ = eval_from_empty prog in
      let captured =
        List.map env.messages ~f:(fun m -> m.texts) |> List.last
      in
      Alcotest.(check (option (list string)))
        "function sees snapshot, not its own PARENT_SCOPE write"
        (Some [ "before-call" ])
        captured;
      check_some "P15/P20" "new-parent" env "X")

let p_snapshot_block =
  Alcotest.test_case
    "P21: inner block's own reads don't see its PARENT_SCOPE write" `Quick
    (fun () ->
      let inner_body =
        ESeq
          [ ECmakeSetParentScope { name = "X"; value = EString "inner-PARENT" };
            ECmakeMessage { mode = ""; texts = [ EVar "X" ] };
          ]
      in
      let prog =
        ESeq
          [ set_var_e "X" "outer";
            block
              (ESeq
                 [ block inner_body;
                   ECmakeMessage { mode = ""; texts = [ EVar "X" ] };
                 ]);
          ]
      in
      let env, _ = eval_from_empty prog in
      let msgs = List.map env.messages ~f:(fun m -> m.texts) in
      Alcotest.(check (list (list string)))
        "messages capture snapshot, then propagated value"
        [ [ "outer" ];          (* inner-PS read uses its snapshot *)
          [ "inner-PARENT" ];   (* outer block sees the PARENT_SCOPE write *)
        ]
        msgs;
      check_some "P21" "outer" env "X"  (* top is untouched *))

(* === Probe P8 — basic function + return === *)
let p8_function_return =
  Alcotest.test_case "P8: function + return() exits the function body" `Quick
    (fun () ->
      let body =
        ESeq
          [ ECmakeMessage { mode = ""; texts = [ EString "function-start" ] };
            ECmakeReturn { propagate_vars = [] };
            ECmakeMessage { mode = ""; texts = [ EString "unreachable" ] };
          ]
      in
      let prog =
        ESeq
          [ ECmakeFunction { name = EString "do_thing"; params = []; body };
            ECmakeApply { name = EString "do_thing"; args = [] };
            ECmakeMessage { mode = ""; texts = [ EString "after-call" ] };
          ]
      in
      let env, _ = eval_from_empty prog in
      Alcotest.(check (list (list string)))
        "function-start + after-call; unreachable not printed"
        [ [ "function-start" ]; [ "after-call" ] ]
        (List.map env.messages ~f:(fun m -> m.texts)))

(* === Probe P9 — return(PROPAGATE x) lifts x to caller === *)
let p9_return_propagate =
  Alcotest.test_case "P9: return(PROPAGATE) lifts named var to caller" `Quick
    (fun () ->
      let body =
        ESeq
          [ set_var_e "RESULT" "from-function";
            ECmakeReturn { propagate_vars = [ "RESULT" ] };
          ]
      in
      let prog =
        ESeq
          [ set_var_e "RESULT" "outer";
            ECmakeFunction { name = EString "make_result"; params = []; body };
            ECmakeApply { name = EString "make_result"; args = [] };
          ]
      in
      let env, _ = eval_from_empty prog in
      check_some "P9" "from-function" env "RESULT")

(* === Probe P10 — return inside foreach inside function: exits function === *)
let p10_return_through_foreach =
  Alcotest.test_case "P10: return inside foreach exits the function" `Quick
    (fun () ->
      let body =
        ESeq
          [ ECmakeForeach
              { loop_var = "item";
                items = [ EString "a"; EString "b"; EString "target"; EString "c" ];
                body =
                  Yelu_langs.Yelu_surface_cmake_if.ECmakeIfStmt
                    { cond =
                        Yelu_langs.Yelu_surface_cmake_string.ECmakeStringEqual
                          (EVar "item", EString "target");
                      then_ =
                        ESeq
                          [ ECmakeSetParentScope
                              { name = "found"; value = EString "yes" };
                            ECmakeReturn { propagate_vars = [] };
                          ];
                      else_ = None };
              };
            ECmakeSetParentScope { name = "found"; value = EString "no" };
          ]
      in
      let prog =
        ESeq
          [ ECmakeFunction { name = EString "finder"; params = []; body };
            ECmakeApply { name = EString "finder"; args = [] };
          ]
      in
      let env, _ = eval_from_empty prog in
      check_some "P10" "yes" env "found")

(* === Probe P11 — return inside block inside function exits function === *)
let p11_return_through_block =
  Alcotest.test_case "P11: return inside block exits the function" `Quick
    (fun () ->
      let body =
        ESeq
          [ block
              (ESeq
                 [ ECmakeReturn { propagate_vars = [] };
                   ECmakeMessage { mode = ""; texts = [ EString "after-return" ] };
                 ]);
            ECmakeMessage { mode = ""; texts = [ EString "after-block" ] };
          ]
      in
      let prog =
        ESeq
          [ ECmakeFunction { name = EString "do_block"; params = []; body };
            ECmakeApply { name = EString "do_block"; args = [] };
          ]
      in
      let env, _ = eval_from_empty prog in
      Alcotest.(check (list (list string)))
        "neither after-return nor after-block prints"
        []
        (List.map env.messages ~f:(fun m -> m.texts)))

(* === Probe P22 — return(PROPAGATE B) inside block(PROPAGATE A) ===
   The block's own PROPAGATE list (A) is skipped on unwind; only the
   return's PROPAGATE list (B) reaches the caller. *)
let p22_return_overrides_block_propagate =
  Alcotest.test_case
    "P22: return(PROPAGATE B) inside block(PROPAGATE A) skips block's PROPAGATE"
    `Quick
    (fun () ->
      let body =
        block ~propagate:"A"
          (ESeq
             [ set_var_e "A" "from-block-A";
               set_var_e "B" "from-block-B";
               ECmakeReturn { propagate_vars = [ "B" ] };
             ])
      in
      let prog =
        ESeq
          [ set_var_e "A" "outer-A";
            set_var_e "B" "outer-B";
            ECmakeFunction { name = EString "do_thing"; params = []; body };
            ECmakeApply { name = EString "do_thing"; args = [] };
          ]
      in
      let env, _ = eval_from_empty prog in
      check_some "P22.A" "outer-A" env "A";        (* block PROPAGATE skipped *)
      check_some "P22.B" "from-block-B" env "B")  (* return PROPAGATE wins *)

(* === Tiny-only diagnostic: PARENT_SCOPE at root frame === *)
let parent_scope_at_root_fails =
  Alcotest.test_case
    "tiny-only: set(X PARENT_SCOPE) at root frame raises Eval_error" `Quick
    (fun () ->
      let prog =
        ECmakeSetParentScope { name = "X"; value = EString "nowhere-to-go" }
      in
      match eval_from_empty prog with
      | exception Eval_error msg ->
        Alcotest.(check bool)
          "error mentions PARENT_SCOPE at root and the cmake-divergence note"
          true
          (String.is_substring msg ~substring:"PARENT_SCOPE at root"
           && String.is_substring msg ~substring:"cmake silently no-ops")
      | _ ->
        Alcotest.fail "expected Eval_error for PARENT_SCOPE at root frame")

let () =
  Alcotest.run "yelu_tiny_block_return"
    [ ( "block_scope",
        [ p1_block_no_leak;
          p2_block_propagate;
          p3_propagate_unchanged;
          p4_propagate_unset;
          p5_nested_block;
          p6_propagate_one_frame;
          p18_propagate_mixed;
        ] );
      ( "parent_scope",
        [ p7_parent_scope_in_block;
          p14_parent_scope_function;
          p17_function_mixed;
          parent_scope_at_root_fails;
        ] );
      ( "snapshot_semantics",
        [ p_snapshot_function;
          p_snapshot_block;
          p16_block_scope_restored;
        ] );
      ( "return",
        [ p8_function_return;
          p9_return_propagate;
          p10_return_through_foreach;
          p11_return_through_block;
          p22_return_overrides_block_propagate;
        ] );
    ]
