(** conf-run level tests for string sub-commands not covered in test_string.ml
    or test_string2.ml.
    Covers: TOUPPER, TOLOWER, LENGTH, PREPEND, REGEX MATCH, COMPARE,
    MAKE_C_IDENTIFIER.
    SKIP: TIMESTAMP — output is time-dependent, not assertable in a static test. *)

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

(* TOUPPER / TOLOWER *)
let case_convert =
  check_cmake "case_convert" (ESeq [
    yc_string_toupper (ystr "hello World") (ycvar "out");
    yifthen (ynot (ystrequal (ycref "out") (ystr "HELLO WORLD")))
      (yc_message ~mode:Mm_fatal_error ["TOUPPER failed"]);
    yc_string_tolower (ystr "Hello WORLD") (ycvar "out");
    yifthen (ynot (ystrequal (ycref "out") (ystr "hello world")))
      (yc_message ~mode:Mm_fatal_error ["TOLOWER failed"]);
    (* empty string: no-op *)
    yc_string_toupper (ystr "") (ycvar "out");
    yifthen (ynot (ystrequal (ycref "out") (ystr "")))
      (yc_message ~mode:Mm_fatal_error ["TOUPPER empty failed"]);
  ])

(* LENGTH: number of characters *)
let length =
  check_cmake "length" (ESeq [
    yc_string_length (ystr "hello") (ycvar "n");
    yifthen (ynot (ystrequal (ycref "n") (ystr "5")))
      (yc_message ~mode:Mm_fatal_error ["LENGTH: hello should be 5"]);
    yc_string_length (ystr "") (ycvar "n");
    yifthen (ynot (ystrequal (ycref "n") (ystr "0")))
      (yc_message ~mode:Mm_fatal_error ["LENGTH: empty should be 0"]);
  ])

(* PREPEND: prepend to a cmake variable *)
let prepend =
  check_cmake "prepend" (ESeq [
    yc_set (ycvar "s") [ ystr "world" ];
    yc_string_prepend (ycvar "s") [ ystr "hello " ];
    yifthen (ynot (ystrequal (ycref "s") (ystr "hello world")))
      (yc_message ~mode:Mm_fatal_error ["PREPEND failed"]);
    (* prepend empty: no-op *)
    yc_string_prepend (ycvar "s") [ ystr "" ];
    yifthen (ynot (ystrequal (ycref "s") (ystr "hello world")))
      (yc_message ~mode:Mm_fatal_error ["PREPEND empty failed"]);
  ])

(* REGEX MATCH: store first match *)
let regex_match =
  check_cmake "regex_match" (ESeq [
    yc_string_regex_match "[0-9]+" (ycvar "out") [ ystr "abc 42 def 7" ];
    yifthen (ynot (ystrequal (ycref "out") (ystr "42")))
      (yc_message ~mode:Mm_fatal_error ["REGEX MATCH: first number should be 42"]);
    (* no match: out is empty string *)
    yc_string_regex_match "[0-9]+" (ycvar "out") [ ystr "no digits here" ];
    yifthen (ynot (ystrequal (ycref "out") (ystr "")))
      (yc_message ~mode:Mm_fatal_error ["REGEX MATCH: no match should give empty"]);
  ])

(* COMPARE: lexicographic comparison, result 0/1 *)
let compare =
  check_cmake "compare" (ESeq [
    yc_string_compare Sco_equal (ystr "abc") (ystr "abc") (ycvar "r");
    yifthen (ynot (ystrequal (ycref "r") (ystr "1")))
      (yc_message ~mode:Mm_fatal_error ["COMPARE EQUAL: abc==abc should be 1"]);
    yc_string_compare Sco_equal (ystr "abc") (ystr "xyz") (ycvar "r");
    yifthen (ynot (ystrequal (ycref "r") (ystr "0")))
      (yc_message ~mode:Mm_fatal_error ["COMPARE EQUAL: abc==xyz should be 0"]);
    yc_string_compare Sco_less (ystr "abc") (ystr "xyz") (ycvar "r");
    yifthen (ynot (ystrequal (ycref "r") (ystr "1")))
      (yc_message ~mode:Mm_fatal_error ["COMPARE LESS: abc<xyz should be 1"]);
    yc_string_compare Sco_greater (ystr "xyz") (ystr "abc") (ycvar "r");
    yifthen (ynot (ystrequal (ycref "r") (ystr "1")))
      (yc_message ~mode:Mm_fatal_error ["COMPARE GREATER: xyz>abc should be 1"]);
    yc_string_compare Sco_notequal (ystr "abc") (ystr "xyz") (ycvar "r");
    yifthen (ynot (ystrequal (ycref "r") (ystr "1")))
      (yc_message ~mode:Mm_fatal_error ["COMPARE NOTEQUAL: abc!=xyz should be 1"]);
  ])

(* MAKE_C_IDENTIFIER: replace non-identifier chars with _ *)
let make_c_identifier =
  check_cmake "make_c_identifier" (ESeq [
    yc_string_make_c_identifier (ystr "foo-bar.baz") (ycvar "out");
    yifthen (ynot (ystrequal (ycref "out") (ystr "foo_bar_baz")))
      (yc_message ~mode:Mm_fatal_error ["MAKE_C_IDENTIFIER: foo-bar.baz failed"]);
    (* leading digit gets _ prefix *)
    yc_string_make_c_identifier (ystr "2fast") (ycvar "out");
    yifthen (ynot (ystrequal (ycref "out") (ystr "_2fast")))
      (yc_message ~mode:Mm_fatal_error ["MAKE_C_IDENTIFIER: 2fast should become _2fast"]);
    (* already valid: unchanged *)
    yc_string_make_c_identifier (ystr "hello_world") (ycvar "out");
    yifthen (ynot (ystrequal (ycref "out") (ystr "hello_world")))
      (yc_message ~mode:Mm_fatal_error ["MAKE_C_IDENTIFIER: hello_world should be unchanged"]);
  ])

(* REGEX MATCHALL: collect all non-overlapping matches as a semicolon list.
   SKIP: zero-length match behavior (CMP0186, blocked until Y11). *)
let regex_matchall =
  check_cmake "regex_matchall" (ESeq [
    yc_string_regex_matchall "[0-9]+" (ycvar "out") [ ystr "a1 b22 c333" ];
    yifthen (ynot (ystrequal (ycref "out") (ystr "1;22;333")))
      (yc_message ~mode:Mm_fatal_error ["REGEX MATCHALL: numbers failed"]);
    (* no match: out is empty *)
    yc_string_regex_matchall "[0-9]+" (ycvar "out") [ ystr "no digits" ];
    yifthen (ynot (ystrequal (ycref "out") (ystr "")))
      (yc_message ~mode:Mm_fatal_error ["REGEX MATCHALL: no match should give empty"]);
  ])

let () =
  Alcotest.run "string3"
    [ ("case_convert",      [ case_convert ]);
      ("length",            [ length ]);
      ("prepend",           [ prepend ]);
      ("regex_match",       [ regex_match ]);
      ("regex_matchall",    [ regex_matchall ]);
      ("compare",           [ compare ]);
      ("make_c_identifier", [ make_c_identifier ]);
    ]
