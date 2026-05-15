(** conf-run level tests for list(TRANSFORM ...).
    Covers: TOUPPER, TOLOWER, STRIP, APPEND, PREPEND, REPLACE,
    with no selector (all), AT selector, FOR selector, REGEX selector,
    and OUTPUT_VARIABLE. *)

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

(* TOUPPER all elements, OUTPUT_VARIABLE *)
let transform_toupper_all =
  check_cmake "transform_toupper_all" (ESeq [
    yc_set (ycvar "L") [ ystr "foo"; ystr "bar"; ystr "baz" ];
    yc_list_transform ~output:(ycvar "out") (ycvar "L") Lta_toupper;
    yifthen (ynot (ystrequal (ycref "out") (ystr "FOO;BAR;BAZ")))
      (yc_message ~mode:Mm_fatal_error ["TRANSFORM TOUPPER all failed"]);
  ])

(* TOLOWER in-place *)
let transform_tolower_inplace =
  check_cmake "transform_tolower_inplace" (ESeq [
    yc_set (ycvar "L") [ ystr "HELLO"; ystr "WORLD" ];
    yc_list_transform (ycvar "L") Lta_tolower;
    yifthen (ynot (ystrequal (ycref "L") (ystr "hello;world")))
      (yc_message ~mode:Mm_fatal_error ["TRANSFORM TOLOWER inplace failed"]);
  ])

(* STRIP all elements *)
let transform_strip =
  check_cmake "transform_strip" (ESeq [
    yc_set (ycvar "L") [ ystr "  hello  "; ystr " world " ];
    yc_list_transform ~output:(ycvar "out") (ycvar "L") Lta_strip;
    yifthen (ynot (ystrequal (ycref "out") (ystr "hello;world")))
      (yc_message ~mode:Mm_fatal_error ["TRANSFORM STRIP failed"]);
  ])

(* APPEND a suffix to all elements *)
let transform_append =
  check_cmake "transform_append" (ESeq [
    yc_set (ycvar "L") [ ystr "a"; ystr "b"; ystr "c" ];
    yc_list_transform ~output:(ycvar "out") (ycvar "L") (Lta_append (Bare ".txt"));
    yifthen (ynot (ystrequal (ycref "out") (ystr "a.txt;b.txt;c.txt")))
      (yc_message ~mode:Mm_fatal_error ["TRANSFORM APPEND failed"]);
  ])

(* PREPEND a prefix to all elements *)
let transform_prepend =
  check_cmake "transform_prepend" (ESeq [
    yc_set (ycvar "L") [ ystr "foo"; ystr "bar" ];
    yc_list_transform ~output:(ycvar "out") (ycvar "L") (Lta_prepend (Bare "lib"));
    yifthen (ynot (ystrequal (ycref "out") (ystr "libfoo;libbar")))
      (yc_message ~mode:Mm_fatal_error ["TRANSFORM PREPEND failed"]);
  ])

(* REPLACE regex on each element *)
let transform_replace =
  check_cmake "transform_replace" (ESeq [
    yc_set (ycvar "L") [ ystr "foo.c"; ystr "bar.c"; ystr "baz.h" ];
    yc_list_transform ~output:(ycvar "out") (ycvar "L")
      (Lta_replace { match_regex = "\\.c$"; replace = ".cpp" });
    yifthen (ynot (ystrequal (ycref "out") (ystr "foo.cpp;bar.cpp;baz.h")))
      (yc_message ~mode:Mm_fatal_error ["TRANSFORM REPLACE failed"]);
  ])

(* AT selector: only transform elements at given indices *)
let transform_at =
  check_cmake "transform_at" (ESeq [
    yc_set (ycvar "L") [ ystr "a"; ystr "b"; ystr "c"; ystr "d" ];
    yc_list_transform ~selector:(Lts_at [1; 3]) ~output:(ycvar "out")
      (ycvar "L") Lta_toupper;
    yifthen (ynot (ystrequal (ycref "out") (ystr "a;B;c;D")))
      (yc_message ~mode:Mm_fatal_error ["TRANSFORM AT selector failed"]);
  ])

(* FOR selector: transform elements in range [1,2] *)
let transform_for =
  check_cmake "transform_for" (ESeq [
    yc_set (ycvar "L") [ ystr "a"; ystr "b"; ystr "c"; ystr "d" ];
    yc_list_transform ~selector:(Lts_for { start = 1; stop = 2; step = None })
      ~output:(ycvar "out") (ycvar "L") Lta_toupper;
    yifthen (ynot (ystrequal (ycref "out") (ystr "a;B;C;d")))
      (yc_message ~mode:Mm_fatal_error ["TRANSFORM FOR selector failed"]);
  ])

(* REGEX selector: only transform elements matching regex *)
let transform_regex_selector =
  check_cmake "transform_regex_selector" (ESeq [
    yc_set (ycvar "L") [ ystr "foo.c"; ystr "bar.h"; ystr "baz.c" ];
    yc_list_transform ~selector:(Lts_regex "\\.c$") ~output:(ycvar "out")
      (ycvar "L") Lta_toupper;
    yifthen (ynot (ystrequal (ycref "out") (ystr "FOO.C;bar.h;BAZ.C")))
      (yc_message ~mode:Mm_fatal_error ["TRANSFORM REGEX selector failed"]);
  ])

let () =
  Alcotest.run "list4"
    [ ("transform_toupper_all",     [ transform_toupper_all ]);
      ("transform_tolower_inplace", [ transform_tolower_inplace ]);
      ("transform_strip",           [ transform_strip ]);
      ("transform_append",          [ transform_append ]);
      ("transform_prepend",         [ transform_prepend ]);
      ("transform_replace",         [ transform_replace ]);
      ("transform_at",              [ transform_at ]);
      ("transform_for",             [ transform_for ]);
      ("transform_regex_selector",  [ transform_regex_selector ]);
    ]
