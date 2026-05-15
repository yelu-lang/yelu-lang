(** conf-run level tests for list commands.
    Each test mirrors a positive script from Tests/RunCMake/list/.
    The yelu program generates cmake text; cmake -P runs it; exit_code 0 = pass. *)

open Yelu_langs.Lang_cmake
open Yelu_langs.Yelu_cmake
open Yelu_langs.Yelu_cmake_utils
open Yelu_langs.Lang_cmake_pp
open Yelu_runner.Cmake_runner

let compile exp =
  Fmt.str "%a" (Fmt.vbox pp) (Yelu_langs.Yelu_cmake_emit.emit_ast exp)

let check_cmake name prog =
  Alcotest.test_case name `Quick (fun () ->
      let result = run_script (compile prog) in
      if result.exit_code <> 0 then
        Alcotest.failf "cmake exited %d\nstderr:\n%s" result.exit_code result.stderr)

(* Mirrors Tests/RunCMake/list/JOIN.cmake *)
let join =
  check_cmake "join" (ESeq [
    (* JOIN undefined list → "" *)
    yc_list_join (ycvar "undefList") (ystr "%") (ycvar "out");
    yifthen (ynot (ystrequal (ycref "out") (ystr "")))
      (yc_message ~mode:Mm_fatal_error ["list JOIN undefList should produce empty"]);
    (* JOIN single element *)
    yc_set (ycvar "myList") [ ystr "a" ];
    yc_list_join (ycvar "myList") (ystr "%") (ycvar "out");
    yifthen (ynot (ystrequal (ycref "out") (ystr "a")))
      (yc_message ~mode:Mm_fatal_error ["JOIN single element failed"]);
    (* JOIN two elements *)
    yc_set (ycvar "myList") [ ystr "a"; ystr "b" ];
    yc_list_join (ycvar "myList") (ystr "%") (ycvar "out");
    yifthen (ynot (ystrequal (ycref "out") (ystr "a%b")))
      (yc_message ~mode:Mm_fatal_error ["JOIN two elements failed"]);
    (* JOIN with empty glue *)
    yc_list_join (ycvar "myList") (ystr "") (ycvar "out");
    yifthen (ynot (ystrequal (ycref "out") (ystr "ab")))
      (yc_message ~mode:Mm_fatal_error ["JOIN empty glue failed"]);
  ])

(* Mirrors Tests/RunCMake/list/SUBLIST.cmake *)
let sublist =
  check_cmake "sublist" (ESeq [
    yc_set (ycvar "L") [ ystr "alpha"; ystr "bravo"; ystr "charlie"; ystr "delta" ];
    yc_list_sublist (ycvar "L") 1 2 (ycvar "result");
    yifthen (ynot (ystrequal (ycref "result") (ystr "bravo;charlie")))
      (yc_message ~mode:Mm_fatal_error ["SUBLIST 1 2 failed"]);
    yc_list_sublist (ycvar "L") 0 2 (ycvar "result");
    yifthen (ynot (ystrequal (ycref "result") (ystr "alpha;bravo")))
      (yc_message ~mode:Mm_fatal_error ["SUBLIST 0 2 failed"]);
    (* -1 length = rest of list *)
    yc_list_sublist (ycvar "L") 1 (-1) (ycvar "result");
    yifthen (ynot (ystrequal (ycref "result") (ystr "bravo;charlie;delta")))
      (yc_message ~mode:Mm_fatal_error ["SUBLIST 1 -1 failed"]);
  ])

(* Mirrors Tests/RunCMake/list/PREPEND.cmake *)
let prepend =
  check_cmake "prepend" (ESeq [
    yc_set (ycvar "L") [ ystr "c"; ystr "d" ];
    yc_list_prepend (ycvar "L") [ ystr "a"; ystr "b" ];
    yifthen (ynot (ystrequal (ycref "L") (ystr "a;b;c;d")))
      (yc_message ~mode:Mm_fatal_error ["PREPEND failed"]);
    (* PREPEND to empty list *)
    yc_set (ycvar "E") [];
    yc_list_prepend (ycvar "E") [ ystr "x" ];
    yifthen (ynot (ystrequal (ycref "E") (ystr "x")))
      (yc_message ~mode:Mm_fatal_error ["PREPEND to empty failed"]);
  ])

(* Mirrors Tests/RunCMake/list/POP_BACK.cmake *)
let pop_back =
  check_cmake "pop_back" (ESeq [
    (* POP_BACK from 2-item list, no out var *)
    yc_set (ycvar "L") [ ystr "one"; ystr "two" ];
    yc_list_pop_back (ycvar "L");
    yifthen (ynot (ystrequal (ycref "L") (ystr "one")))
      (yc_message ~mode:Mm_fatal_error ["POP_BACK no-outvar failed"]);
    (* POP_BACK with out var *)
    yc_set (ycvar "L") [ ystr "one"; ystr "two" ];
    yc_list_pop_back ~out_vars:[ycvar "popped"] (ycvar "L");
    yifthen (ynot (ystrequal (ycref "L") (ystr "one")))
      (yc_message ~mode:Mm_fatal_error ["POP_BACK outvar: list wrong"]);
    yifthen (ynot (ystrequal (ycref "popped") (ystr "two")))
      (yc_message ~mode:Mm_fatal_error ["POP_BACK outvar: popped wrong"]);
  ])

(* Mirrors Tests/RunCMake/list/POP_FRONT.cmake *)
let pop_front =
  check_cmake "pop_front" (ESeq [
    yc_set (ycvar "L") [ ystr "one"; ystr "two" ];
    yc_list_pop_front (ycvar "L");
    yifthen (ynot (ystrequal (ycref "L") (ystr "two")))
      (yc_message ~mode:Mm_fatal_error ["POP_FRONT no-outvar failed"]);
    yc_set (ycvar "L") [ ystr "one"; ystr "two" ];
    yc_list_pop_front ~out_vars:[ycvar "head"] (ycvar "L");
    yifthen (ynot (ystrequal (ycref "head") (ystr "one")))
      (yc_message ~mode:Mm_fatal_error ["POP_FRONT outvar: head wrong"]);
    yifthen (ynot (ystrequal (ycref "L") (ystr "two")))
      (yc_message ~mode:Mm_fatal_error ["POP_FRONT outvar: list wrong"]);
  ])

(* Mirrors Tests/RunCMake/list/SORT.cmake (subset: default + case-insensitive) *)
let sort =
  check_cmake "sort" (ESeq [
    (* default sort: case-sensitive ascending string *)
    yc_set (ycvar "L") [ ystr "c/B.h"; ystr "a/c.h"; ystr "B/a.h" ];
    yc_list_sort (ycvar "L");
    yifthen (ynot (ystrequal (ycref "L") (ystr "B/a.h;a/c.h;c/B.h")))
      (yc_message ~mode:Mm_fatal_error ["SORT default failed"]);
    (* case-insensitive ascending *)
    yc_set (ycvar "L") [ ystr "c/B.h"; ystr "a/c.h"; ystr "B/a.h" ];
    yc_list_sort ~case:Ls_insensitive ~order:Ls_ascending (ycvar "L");
    yifthen (ynot (ystrequal (ycref "L") (ystr "a/c.h;B/a.h;c/B.h")))
      (yc_message ~mode:Mm_fatal_error ["SORT case-insensitive ascending failed"]);
  ])

(* Mirrors Tests/RunCMake/list/REMOVE_DUPLICATES-PreserveOrder.cmake *)
let remove_duplicates =
  check_cmake "remove_duplicates" (ESeq [
    yc_set (ycvar "L") [ ystr "a"; ystr "b"; ystr "a"; ystr "c"; ystr "b" ];
    yc_list_remove_duplicates (ycvar "L");
    yifthen (ynot (ystrequal (ycref "L") (ystr "a;b;c")))
      (yc_message ~mode:Mm_fatal_error ["REMOVE_DUPLICATES preserve order failed"]);
  ])

let () =
  Alcotest.run "list"
    [ ("join",               [ join ]);
      ("sublist",            [ sublist ]);
      ("prepend",            [ prepend ]);
      ("pop_back",           [ pop_back ]);
      ("pop_front",          [ pop_front ]);
      ("sort",               [ sort ]);
      ("remove_duplicates",  [ remove_duplicates ]);
    ]
