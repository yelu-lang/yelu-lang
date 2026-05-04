(** conf-run level tests for while / break / continue.
    The RunCMake/while/ positive tests are all CMP0130 policy tests and not
    useful as yelu targets.  These tests validate the actual loop semantics
    that the yelu layer generates. *)

open Yelu_langs.Lang_yelu_cmake
open Yelu_langs.Lang_yelu_utils
open Yelu_langs.Lang_yelu_compile
open Yelu_langs.Lang_cmake_pp
open Yelu_runner.Cmake_runner

let compile exp =
  let cmake_ast = compile empty_env exp |> snd in
  Fmt.str "%a" (Fmt.vbox pp) cmake_ast

let check_cmake name prog =
  Alcotest.test_case name `Quick (fun () ->
      let result = run_script (compile prog) in
      if result.exit_code <> 0 then
        Alcotest.failf "cmake exited %d\nstderr:\n%s" result.exit_code result.stderr)

(* Count from 1 to 5 with a while loop, check final value *)
let basic_loop =
  check_cmake "basic_loop" (Ystmt_list [
    yc_set (ycvar "i") [ ystr "1" ];
    yc_while (ytruthy (ycstr "i"))
      (Ystmt_list [
        yifthen (ystrequal (ycref "i") (ystr "6"))
          yc_break;
        yc_math "${i} + 1" (ycvar "i");
      ]);
    (* after loop i should be 6 *)
    yifthen (ynot (ystrequal (ycref "i") (ystr "6")))
      (yc_message ~mode:Mm_fatal_error ["basic_loop: i should be 6"]);
  ])

(* break exits the loop immediately *)
let break_test =
  check_cmake "break" (Ystmt_list [
    (* start with a truthy value so the loop body executes at least once *)
    yc_set (ycvar "x") [ ystr "1" ];
    yc_while (ytruthy (ycstr "x"))
      (Ystmt_list [
        yc_set (ycvar "x") [ ystr "99" ];
        yc_break;
        (* this set must not execute *)
        yc_set (ycvar "x") [ ystr "bad" ];
      ]);
    yifthen (ynot (ystrequal (ycref "x") (ystr "99")))
      (yc_message ~mode:Mm_fatal_error ["break: x should be 99"]);
  ])

(* continue skips the rest of the loop body.
   Loop counts i from 1 to 3 (inclusive), then at i=4 sets i="" (falsy) and
   calls continue — the while condition re-evaluates to false and exits.
   count should be 3 (incremented at i=1, 2, 3 only). *)
let continue_test =
  check_cmake "continue" (Ystmt_list [
    yc_set (ycvar "i") [ ystr "1" ];
    yc_set (ycvar "count") [ ystr "0" ];
    yc_while (ytruthy (ycstr "i"))
      (Ystmt_list [
        (* at i=4: set i="" (falsy) and continue → exits the loop *)
        yifthen (ystrequal (ycref "i") (ystr "4"))
          (Ystmt_list [
            yc_set (ycvar "i") [ ystr "" ];
            yc_continue;
          ]);
        (* count this iteration and increment *)
        yc_math "${count} + 1" (ycvar "count");
        yc_math "${i} + 1" (ycvar "i");
      ]);
    yifthen (ynot (ystrequal (ycref "count") (ystr "3")))
      (yc_message ~mode:Mm_fatal_error ["continue: count should be 3"]);
  ])

let () =
  Alcotest.run "while"
    [ ("basic_loop", [ basic_loop ]);
      ("break",      [ break_test ]);
      ("continue",   [ continue_test ]);
    ]
