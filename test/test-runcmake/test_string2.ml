(** conf-run level tests for string sub-commands not covered in test_string.ml.
    Covers: FIND, SUBSTRING, STRIP, REPLACE, REGEX REPLACE. *)

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

(* FIND: returns 0-based index, or -1 if not found *)
let find =
  check_cmake "find" (Ystmt_list [
    yc_string_find (ystr "hello world") (ystr "world") (ycvar "idx");
    yifthen (ynot (ystrequal (ycref "idx") (ystr "6")))
      (yc_message ~mode:Mm_fatal_error ["FIND: world should be at index 6"]);
    yc_string_find (ystr "hello world") (ystr "missing") (ycvar "idx");
    yifthen (ynot (ystrequal (ycref "idx") (ystr "-1")))
      (yc_message ~mode:Mm_fatal_error ["FIND: missing should return -1"]);
    (* REVERSE: find last occurrence *)
    yc_string_find ~reverse:true (ystr "abcabc") (ystr "b") (ycvar "idx");
    yifthen (ynot (ystrequal (ycref "idx") (ystr "4")))
      (yc_message ~mode:Mm_fatal_error ["FIND REVERSE: last b should be at index 4"]);
  ])

(* SUBSTRING: extract by begin+length, or begin to end *)
let substring =
  check_cmake "substring" (Ystmt_list [
    yc_string_substring (ystr "hello world") 6 ~length:5 (ycvar "out");
    yifthen (ynot (ystrequal (ycref "out") (ystr "world")))
      (yc_message ~mode:Mm_fatal_error ["SUBSTRING: world failed"]);
    (* length -1 = rest of string *)
    yc_string_substring (ystr "hello world") 6 ~length:(-1) (ycvar "out");
    yifthen (ynot (ystrequal (ycref "out") (ystr "world")))
      (yc_message ~mode:Mm_fatal_error ["SUBSTRING: length -1 failed"]);
    (* zero-length *)
    yc_string_substring (ystr "hello") 2 ~length:0 (ycvar "out");
    yifthen (ynot (ystrequal (ycref "out") (ystr "")))
      (yc_message ~mode:Mm_fatal_error ["SUBSTRING: length 0 failed"]);
  ])

(* STRIP: remove leading and trailing whitespace *)
let strip =
  check_cmake "strip" (Ystmt_list [
    yc_string_strip (ystr "  hello  ") (ycvar "out");
    yifthen (ynot (ystrequal (ycref "out") (ystr "hello")))
      (yc_message ~mode:Mm_fatal_error ["STRIP: spaces failed"]);
    yc_string_strip (ystr "no spaces") (ycvar "out");
    yifthen (ynot (ystrequal (ycref "out") (ystr "no spaces")))
      (yc_message ~mode:Mm_fatal_error ["STRIP: no-op failed"]);
    yc_string_strip (ystr "") (ycvar "out");
    yifthen (ynot (ystrequal (ycref "out") (ystr "")))
      (yc_message ~mode:Mm_fatal_error ["STRIP: empty failed"]);
  ])

(* REPLACE: literal string replacement *)
let replace =
  check_cmake "replace" (Ystmt_list [
    yc_string_replace (ystr "foo") (ystr "bar") (ycvar "out") [ ystr "foo and foo" ];
    yifthen (ynot (ystrequal (ycref "out") (ystr "bar and bar")))
      (yc_message ~mode:Mm_fatal_error ["REPLACE: foo->bar failed"]);
    (* no match: output equals input *)
    yc_string_replace (ystr "xyz") (ystr "!") (ycvar "out") [ ystr "hello" ];
    yifthen (ynot (ystrequal (ycref "out") (ystr "hello")))
      (yc_message ~mode:Mm_fatal_error ["REPLACE: no-match failed"]);
    (* SKIP: empty match-string replace — implementation-defined in cmake;
       behavior varies across versions. See language_coverage.md §Known Gaps. *)
  ])

(* REGEX REPLACE: regex substitution with back-references *)
let regex_replace =
  check_cmake "regex_replace" (Ystmt_list [
    (* \\\\1 in OCaml → \\1 in cmake source → \1 back-reference in replacement *)
    yc_string_regex_replace "([0-9]+)" (ystr "(\\\\1)") (ycvar "out") [ ystr "abc 42 def" ];
    yifthen (ynot (ystrequal (ycref "out") (ystr "abc (42) def")))
      (yc_message ~mode:Mm_fatal_error ["REGEX REPLACE: back-ref failed"]);
    (* global: all occurrences replaced *)
    yc_string_regex_replace "[aeiou]" (ystr "*") (ycvar "out") [ ystr "hello" ];
    yifthen (ynot (ystrequal (ycref "out") (ystr "h*ll*")))
      (yc_message ~mode:Mm_fatal_error ["REGEX REPLACE: global replace failed"]);
  ])

let () =
  Alcotest.run "string2"
    [ ("find",          [ find ]);
      ("substring",     [ substring ]);
      ("strip",         [ strip ]);
      ("replace",       [ replace ]);
      ("regex_replace", [ regex_replace ]);
    ]
