(** conf-run level tests for list sub-commands not covered in test_list.ml.
    Covers: LENGTH, GET, APPEND, FIND, REMOVE_ITEM, REMOVE_AT, REVERSE, INSERT. *)

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

(* LENGTH: returns number of elements *)
let length =
  check_cmake "length" (Ystmt_list [
    yc_set (ycvar "L") [ ystr "a"; ystr "b"; ystr "c" ];
    yc_list_length (ycvar "L") (ycvar "n");
    yifthen (ynot (ystrequal (ycref "n") (ystr "3")))
      (yc_message ~mode:Mm_fatal_error ["LENGTH: 3-element list failed"]);
    (* empty list: length 0 *)
    yc_set (ycvar "E") [];
    yc_list_length (ycvar "E") (ycvar "n");
    yifthen (ynot (ystrequal (ycref "n") (ystr "0")))
      (yc_message ~mode:Mm_fatal_error ["LENGTH: empty list failed"]);
  ])

(* GET: retrieve element(s) by index *)
let get =
  check_cmake "get" (Ystmt_list [
    yc_set (ycvar "L") [ ystr "alpha"; ystr "bravo"; ystr "charlie" ];
    (* single positive index *)
    yc_list_get ~indices:[1] (ycvar "L") (ycvar "out");
    yifthen (ynot (ystrequal (ycref "out") (ystr "bravo")))
      (yc_message ~mode:Mm_fatal_error ["GET index 1 failed"]);
    (* negative index: -1 = last *)
    yc_list_get ~indices:[-1] (ycvar "L") (ycvar "out");
    yifthen (ynot (ystrequal (ycref "out") (ystr "charlie")))
      (yc_message ~mode:Mm_fatal_error ["GET index -1 failed"]);
    (* multiple indices → semicolon-joined result *)
    yc_list_get ~indices:[0; 2] (ycvar "L") (ycvar "out");
    yifthen (ynot (ystrequal (ycref "out") (ystr "alpha;charlie")))
      (yc_message ~mode:Mm_fatal_error ["GET indices 0 2 failed"]);
  ])

(* APPEND: add elements to end of list *)
let append =
  check_cmake "append" (Ystmt_list [
    yc_set (ycvar "L") [ ystr "a"; ystr "b" ];
    yc_list_append (ycvar "L") [ ystr "c"; ystr "d" ];
    yifthen (ynot (ystrequal (ycref "L") (ystr "a;b;c;d")))
      (yc_message ~mode:Mm_fatal_error ["APPEND failed"]);
    (* APPEND to undefined list creates it *)
    yc_list_append (ycvar "New") [ ystr "x" ];
    yifthen (ynot (ystrequal (ycref "New") (ystr "x")))
      (yc_message ~mode:Mm_fatal_error ["APPEND to undefined failed"]);
  ])

(* FIND: returns 0-based index or -1 if not found *)
let find =
  check_cmake "find" (Ystmt_list [
    yc_set (ycvar "L") [ ystr "a"; ystr "b"; ystr "c" ];
    yc_list_find (ycvar "L") (ystr "b") (ycvar "idx");
    yifthen (ynot (ystrequal (ycref "idx") (ystr "1")))
      (yc_message ~mode:Mm_fatal_error ["FIND: b should be at index 1"]);
    (* not present → -1 *)
    yc_list_find (ycvar "L") (ystr "z") (ycvar "idx");
    yifthen (ynot (ystrequal (ycref "idx") (ystr "-1")))
      (yc_message ~mode:Mm_fatal_error ["FIND: missing should return -1"]);
  ])

(* REMOVE_ITEM: remove all occurrences of given values *)
let remove_item =
  check_cmake "remove_item" (Ystmt_list [
    yc_set (ycvar "L") [ ystr "a"; ystr "b"; ystr "a"; ystr "c" ];
    yc_list_remove_item (ycvar "L") [ ystr "a" ];
    yifthen (ynot (ystrequal (ycref "L") (ystr "b;c")))
      (yc_message ~mode:Mm_fatal_error ["REMOVE_ITEM: both a's should be removed"]);
    (* remove value not in list: no-op *)
    yc_list_remove_item (ycvar "L") [ ystr "z" ];
    yifthen (ynot (ystrequal (ycref "L") (ystr "b;c")))
      (yc_message ~mode:Mm_fatal_error ["REMOVE_ITEM: no-op failed"]);
  ])

(* REMOVE_AT: remove by index position *)
let remove_at =
  check_cmake "remove_at" (Ystmt_list [
    yc_set (ycvar "L") [ ystr "a"; ystr "b"; ystr "c"; ystr "d" ];
    yc_list_remove_at (ycvar "L") [ 1 ];
    yifthen (ynot (ystrequal (ycref "L") (ystr "a;c;d")))
      (yc_message ~mode:Mm_fatal_error ["REMOVE_AT index 1 failed"]);
    (* negative index: -1 removes last *)
    yc_list_remove_at (ycvar "L") [ -1 ];
    yifthen (ynot (ystrequal (ycref "L") (ystr "a;c")))
      (yc_message ~mode:Mm_fatal_error ["REMOVE_AT index -1 failed"]);
  ])

(* REVERSE: reverses list in place *)
let reverse =
  check_cmake "reverse" (Ystmt_list [
    yc_set (ycvar "L") [ ystr "a"; ystr "b"; ystr "c" ];
    yc_list_reverse (ycvar "L");
    yifthen (ynot (ystrequal (ycref "L") (ystr "c;b;a")))
      (yc_message ~mode:Mm_fatal_error ["REVERSE failed"]);
    (* single element: no-op *)
    yc_set (ycvar "S") [ ystr "x" ];
    yc_list_reverse (ycvar "S");
    yifthen (ynot (ystrequal (ycref "S") (ystr "x")))
      (yc_message ~mode:Mm_fatal_error ["REVERSE single element failed"]);
  ])

(* INSERT: insert elements at given index *)
let insert =
  check_cmake "insert" (Ystmt_list [
    yc_set (ycvar "L") [ ystr "a"; ystr "c" ];
    yc_list_insert (ycvar "L") 1 [ ystr "b" ];
    yifthen (ynot (ystrequal (ycref "L") (ystr "a;b;c")))
      (yc_message ~mode:Mm_fatal_error ["INSERT at 1 failed"]);
    (* insert at 0: prepend *)
    yc_list_insert (ycvar "L") 0 [ ystr "z" ];
    yifthen (ynot (ystrequal (ycref "L") (ystr "z;a;b;c")))
      (yc_message ~mode:Mm_fatal_error ["INSERT at 0 failed"]);
  ])

let () =
  Alcotest.run "list2"
    [ ("length",      [ length ]);
      ("get",         [ get ]);
      ("append",      [ append ]);
      ("find",        [ find ]);
      ("remove_item", [ remove_item ]);
      ("remove_at",   [ remove_at ]);
      ("reverse",     [ reverse ]);
      ("insert",      [ insert ]);
    ]
