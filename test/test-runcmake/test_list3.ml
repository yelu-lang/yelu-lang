(** conf-run level tests for list sub-commands not covered in test_list.ml
    or test_list2.ml.
    Covers: FILTER (INCLUDE/EXCLUDE), SORT DESCENDING, SORT NATURAL,
    SORT NUMBER. *)

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

(* FILTER INCLUDE: keep elements matching regex *)
let filter_include =
  check_cmake "filter_include" (ESeq [
    yc_set (ycvar "L") [ ystr "foo.c"; ystr "bar.h"; ystr "baz.c"; ystr "qux.h" ];
    yc_list_filter Lf_include "\\.c$" (ycvar "L");
    yifthen (ynot (ystrequal (ycref "L") (ystr "foo.c;baz.c")))
      (yc_message ~mode:Mm_fatal_error ["FILTER INCLUDE .c failed"]);
  ])

(* FILTER EXCLUDE: remove elements matching regex *)
let filter_exclude =
  check_cmake "filter_exclude" (ESeq [
    yc_set (ycvar "L") [ ystr "foo.c"; ystr "bar.h"; ystr "baz.c"; ystr "qux.h" ];
    yc_list_filter Lf_exclude "\\.h$" (ycvar "L");
    yifthen (ynot (ystrequal (ycref "L") (ystr "foo.c;baz.c")))
      (yc_message ~mode:Mm_fatal_error ["FILTER EXCLUDE .h failed"]);
  ])

(* SORT DESCENDING: reverse alphabetical order *)
let sort_descending =
  check_cmake "sort_descending" (ESeq [
    yc_set (ycvar "L") [ ystr "banana"; ystr "apple"; ystr "cherry" ];
    yc_list_sort ~order:Ls_descending (ycvar "L");
    yifthen (ynot (ystrequal (ycref "L") (ystr "cherry;banana;apple")))
      (yc_message ~mode:Mm_fatal_error ["SORT DESCENDING failed"]);
  ])

(* SORT COMPARE NATURAL: human-friendly ordering (e.g. 2 before 10) *)
let sort_natural =
  check_cmake "sort_natural" (ESeq [
    yc_set (ycvar "L") [ ystr "file10.txt"; ystr "file2.txt"; ystr "file1.txt" ];
    yc_list_sort ~compare:Ls_natural (ycvar "L");
    yifthen (ynot (ystrequal (ycref "L") (ystr "file1.txt;file2.txt;file10.txt")))
      (yc_message ~mode:Mm_fatal_error ["SORT NATURAL failed"]);
  ])

(* SKIP: SORT COMPARE NUMBER/NUMERIC — does not exist in cmake.
   cmake list(SORT) only supports COMPARE STRING, FILE_BASENAME, NATURAL.
   Ls_numeric in lang_cmake.ml is a false feature; the PP was emitting
   "NUMERIC" (corrected to "NUMBER" but both are invalid).
   See language_coverage.md §Known Gaps. *)

(* SORT COMPARE FILE_BASENAME: sort by filename ignoring directory prefix *)
let sort_file_basename =
  check_cmake "sort_file_basename" (ESeq [
    yc_set (ycvar "L") [ ystr "dir/foo.txt"; ystr "other/bar.txt"; ystr "a/baz.txt" ];
    yc_list_sort ~compare:Ls_file_basename (ycvar "L");
    yifthen (ynot (ystrequal (ycref "L") (ystr "other/bar.txt;a/baz.txt;dir/foo.txt")))
      (yc_message ~mode:Mm_fatal_error ["SORT FILE_BASENAME failed"]);
  ])

let () =
  Alcotest.run "list3"
    [ ("filter_include",    [ filter_include ]);
      ("filter_exclude",    [ filter_exclude ]);
      ("sort_descending",   [ sort_descending ]);
      ("sort_natural",      [ sort_natural ]);
      ("sort_file_basename", [ sort_file_basename ]);
    ]
