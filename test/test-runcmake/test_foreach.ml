(** conf-run level tests for foreach.
    Mirrors Tests/RunCMake/foreach/foreach-all-test.cmake positive cases.
    ZIP_LISTS and multiple-iter-vars skipped (yelu gap — needs zip in core). *)

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

(* foreach(RANGE stop) — iterates 0..stop inclusive *)
let range_stop =
  check_cmake "range_stop" (Ystmt_list [
    yc_set (ycvar "acc") [ ystr "" ];
    yc_foreach_range ~stop:3 (ycvar "i")
      (yc_string_append (ycvar "acc") [ ycref "i" ]);
    (* acc should be "0123" *)
    yifthen (ynot (ystrequal (ycref "acc") (ystr "0123")))
      (yc_message ~mode:Mm_fatal_error ["range_stop: acc should be 0123"]);
  ])

(* foreach(RANGE start stop) — iterates start..stop inclusive *)
let range_start_stop =
  check_cmake "range_start_stop" (Ystmt_list [
    yc_set (ycvar "acc") [ ystr "" ];
    yc_foreach_range ~start:2 ~stop:4 (ycvar "i")
      (yc_string_append (ycvar "acc") [ ycref "i" ]);
    (* acc should be "234" *)
    yifthen (ynot (ystrequal (ycref "acc") (ystr "234")))
      (yc_message ~mode:Mm_fatal_error ["range_start_stop: acc should be 234"]);
  ])

(* foreach(RANGE start stop step) — iterates with step *)
let range_step =
  check_cmake "range_step" (Ystmt_list [
    yc_set (ycvar "acc") [ ystr "" ];
    yc_foreach_range ~start:0 ~stop:6 ~step:2 (ycvar "i")
      (yc_string_append (ycvar "acc") [ ycref "i" ]);
    (* acc should be "0246" *)
    yifthen (ynot (ystrequal (ycref "acc") (ystr "0246")))
      (yc_message ~mode:Mm_fatal_error ["range_step: acc should be 0246"]);
  ])

(* foreach(IN ITEMS ...) — iterates literal items *)
let in_items =
  check_cmake "in_items" (Ystmt_list [
    yc_set (ycvar "acc") [ ystr "" ];
    yc_foreach_in ~items:[ ystr "a"; ystr "b"; ystr "c" ] (ycvar "x")
      (yc_string_append (ycvar "acc") [ ycref "x" ]);
    yifthen (ynot (ystrequal (ycref "acc") (ystr "abc")))
      (yc_message ~mode:Mm_fatal_error ["in_items: acc should be abc"]);
  ])

(* foreach(IN LISTS var) — iterates a cmake list variable *)
let in_lists =
  check_cmake "in_lists" (Ystmt_list [
    yc_list_append (ycvar "words") [ ystr "one"; ystr "two"; ystr "three" ];
    yc_set (ycvar "count") [ ystr "0" ];
    yc_foreach_in ~lists:[ ycvar "words" ] (ycvar "w")
      (yc_math "${count} + 1" (ycvar "count"));
    yifthen (ynot (ystrequal (ycref "count") (ystr "3")))
      (yc_message ~mode:Mm_fatal_error ["in_lists: count should be 3"]);
  ])

(* foreach(IN LISTS var ITEMS ...) — combined lists + items *)
let in_lists_and_items =
  check_cmake "in_lists_and_items" (Ystmt_list [
    yc_list_append (ycvar "base") [ ystr "x"; ystr "y" ];
    yc_set (ycvar "count") [ ystr "0" ];
    yc_foreach_in ~lists:[ ycvar "base" ] ~items:[ ystr "z" ] (ycvar "v")
      (yc_math "${count} + 1" (ycvar "count"));
    (* base has 2 items, plus 1 literal = 3 *)
    yifthen (ynot (ystrequal (ycref "count") (ystr "3")))
      (yc_message ~mode:Mm_fatal_error ["in_lists_and_items: count should be 3"]);
  ])

let () =
  Alcotest.run "foreach"
    [ ("range_stop",          [ range_stop ]);
      ("range_start_stop",    [ range_start_stop ]);
      ("range_step",          [ range_step ]);
      ("in_items",            [ in_items ]);
      ("in_lists",            [ in_lists ]);
      ("in_lists_and_items",  [ in_lists_and_items ]);
    ]
