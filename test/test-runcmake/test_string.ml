(** conf-run level tests for string commands.
    Each test mirrors a positive script from Tests/RunCMake/string/.
    The yelu program generates cmake text; cmake -P runs it; exit_code 0 = pass. *)

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

(* Mirrors Tests/RunCMake/string/Append.cmake (subset: no bracket-string cases) *)
let append =
  check_cmake "append" (ESeq [
    (* APPEND with no extra args on "" is a no-op *)
    yc_set (ycvar "out") [ ystr "" ];
    yc_string_append (ycvar "out") [];
    yifthen (ynot (ystrequal (ycref "out") (ystr "")))
      (yc_message ~mode:Mm_fatal_error ["APPEND no-args on empty failed"]);
    (* APPEND single arg *)
    yc_set (ycvar "out") [ ystr "x" ];
    yc_string_append (ycvar "out") [ ystr "a" ];
    yifthen (ynot (ystrequal (ycref "out") (ystr "xa")))
      (yc_message ~mode:Mm_fatal_error ["APPEND single arg failed"]);
    (* APPEND two args *)
    yc_set (ycvar "out") [ ystr "x" ];
    yc_string_append (ycvar "out") [ ystr "a"; ystr "b" ];
    yifthen (ynot (ystrequal (ycref "out") (ystr "xab")))
      (yc_message ~mode:Mm_fatal_error ["APPEND two args failed"]);
  ])

(* Mirrors Tests/RunCMake/string/Join.cmake *)
let join =
  check_cmake "join" (ESeq [
    yc_string_join (ystr "%") (ycvar "out") [];
    yifthen (ynot (ystrequal (ycref "out") (ystr "")))
      (yc_message ~mode:Mm_fatal_error ["JOIN no items should produce empty"]);
    yc_string_join (ystr "%") (ycvar "out") [ ystr "a" ];
    yifthen (ynot (ystrequal (ycref "out") (ystr "a")))
      (yc_message ~mode:Mm_fatal_error ["JOIN single item failed"]);
    yc_string_join (ystr "%") (ycvar "out") [ ystr "a"; ystr "b" ];
    yifthen (ynot (ystrequal (ycref "out") (ystr "a%b")))
      (yc_message ~mode:Mm_fatal_error ["JOIN two items failed"]);
    yc_string_join (ystr "::") (ycvar "out") [ ystr "a"; ystr "b" ];
    yifthen (ynot (ystrequal (ycref "out") (ystr "a::b")))
      (yc_message ~mode:Mm_fatal_error ["JOIN :: glue failed"]);
  ])

(* Mirrors Tests/RunCMake/string/Concat.cmake (subset: no bracket-string cases) *)
let concat =
  check_cmake "concat" (ESeq [
    yc_string_concat (ycvar "out") [];
    yifthen (ynot (ystrequal (ycref "out") (ystr "")))
      (yc_message ~mode:Mm_fatal_error ["CONCAT no args failed"]);
    yc_string_concat (ycvar "out") [ ystr "a" ];
    yifthen (ynot (ystrequal (ycref "out") (ystr "a")))
      (yc_message ~mode:Mm_fatal_error ["CONCAT single arg failed"]);
    yc_string_concat (ycvar "out") [ ystr "a"; ystr "b" ];
    yifthen (ynot (ystrequal (ycref "out") (ystr "ab")))
      (yc_message ~mode:Mm_fatal_error ["CONCAT two args failed"]);
  ])

(* Mirrors Tests/RunCMake/string/Repeat.cmake *)
let repeat =
  check_cmake "repeat" (ESeq [
    yc_string_repeat (ystr "q") 4 (ycvar "q_out");
    yifthen (ynot (ystrequal (ycref "q_out") (ystr "qqqq")))
      (yc_message ~mode:Mm_fatal_error ["REPEAT q*4 failed"]);
    yc_string_repeat (ystr "1234") 0 (ycvar "zero_out");
    yifthen (ynot (ystrequal (ycref "zero_out") (ystr "")))
      (yc_message ~mode:Mm_fatal_error ["REPEAT x*0 failed"]);
    yc_string_repeat (ystr "") 100 (ycvar "empty_out");
    yifthen (ynot (ystrequal (ycref "empty_out") (ystr "")))
      (yc_message ~mode:Mm_fatal_error ["REPEAT empty*100 failed"]);
    yc_string_repeat (ystr "one") 1 (ycvar "one_out");
    yifthen (ynot (ystrequal (ycref "one_out") (ystr "one")))
      (yc_message ~mode:Mm_fatal_error ["REPEAT one*1 failed"]);
  ])

(* Mirrors Tests/RunCMake/string/GenexpStrip.cmake (inlined, no helper function) *)
let genex_strip =
  check_cmake "genex_strip" (ESeq [
    (* "$<BOOL:1>" → "" *)
    yc_string_genex_strip (ystr "$<BOOL:1>") (ycvar "strip");
    yifthen (ynot (ystrequal (ycref "strip") (ystr "")))
      (yc_message ~mode:Mm_fatal_error ["GENEX_STRIP BOOL:1 failed"]);
    (* LHS contains genex; cmake normalises the trailing ; away → "DEBUG" *)
    yc_string_genex_strip (ystr "$<$<CONFIG:Release>:NDEBUG>;DEBUG") (ycvar "strip");
    yifthen (ynot (ystrequal (ycref "strip") (ystr "DEBUG")))
      (yc_message ~mode:Mm_fatal_error ["GENEX_STRIP LHS genex failed"]);
    (* Multiple independent expressions stripped, separators preserved *)
    yc_string_genex_strip (ystr "$<IF:TRUE,TRUE,FALSE> / $<IF:TRUE,TRUE,FALSE>") (ycvar "strip");
    yifthen (ynot (ystrequal (ycref "strip") (ystr " / ")))
      (yc_message ~mode:Mm_fatal_error ["GENEX_STRIP multiple failed"]);
    (* Nested colons stripped *)
    yc_string_genex_strip (ystr "$<1:2:3>") (ycvar "strip");
    yifthen (ynot (ystrequal (ycref "strip") (ystr "")))
      (yc_message ~mode:Mm_fatal_error ["GENEX_STRIP nested colons failed"]);
  ])

let () =
  Alcotest.run "string"
    [ ("append",      [ append ]);
      ("join",        [ join ]);
      ("concat",      [ concat ]);
      ("repeat",      [ repeat ]);
      ("genex_strip", [ genex_strip ]);
    ]
