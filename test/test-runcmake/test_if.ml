(** conf-run level tests for if() condition forms.
    Mirrors Tests/RunCMake/if/ positive scripts.
    Covers operator forms not exercised by other tests:
    IN_LIST, MATCHES, VERSION_LESS/GREATER/EQUAL/LESS_EQUAL/GREATER_EQUAL. *)

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

(* IN_LIST: value is a member of a cmake list variable.
   Requires CMP0057 NEW (cmake 3.3+); cmake_minimum_required sets it. *)
   (* Compatibility with CMake < 3.5 has been removed from CMake. *)
let in_list =
  check_cmake "in_list" (ESeq [
    yc_minimum_required_s "3.5";
    yc_list_append (ycvar "fruits") [ ystr "apple"; ystr "banana"; ystr "cherry" ];
    yifthen (ynot (yin_list (ystr "banana") (ycstr "fruits")))
      (yc_message ~mode:Mm_fatal_error ["in_list: banana should be in fruits"]);
    yifthen (yin_list (ystr "mango") (ycstr "fruits"))
      (yc_message ~mode:Mm_fatal_error ["in_list: mango should not be in fruits"]);
  ])

(* MATCHES: value matches a regex *)
let matches =
  check_cmake "matches" (ESeq [
    yc_set (ycvar "ver") [ ystr "3.14.1" ];
    yifthen (ynot (ymatches (ycref "ver") "^[0-9]+\\.[0-9]+"))
      (yc_message ~mode:Mm_fatal_error ["matches: ver should match version regex"]);
    yifthen (ymatches (ycref "ver") "^[a-z]+$")
      (yc_message ~mode:Mm_fatal_error ["matches: ver should not match alpha regex"]);
  ])

(* VERSION_LESS / VERSION_GREATER / VERSION_EQUAL *)
let version_compare =
  check_cmake "version_compare" (ESeq [
    yifthen (ynot (yversion_less (ystr "1.0") (ystr "2.0")))
      (yc_message ~mode:Mm_fatal_error ["version_compare: 1.0 should be less than 2.0"]);
    yifthen (ynot (yversion_greater (ystr "2.0") (ystr "1.0")))
      (yc_message ~mode:Mm_fatal_error ["version_compare: 2.0 should be greater than 1.0"]);
    yifthen (ynot (yversion_equal (ystr "1.2.3") (ystr "1.2.3")))
      (yc_message ~mode:Mm_fatal_error ["version_compare: 1.2.3 should equal 1.2.3"]);
  ])

(* VERSION_LESS_EQUAL / VERSION_GREATER_EQUAL *)
let version_compare_equal =
  check_cmake "version_compare_equal" (ESeq [
    yifthen (ynot (yversion_less_equal (ystr "1.0") (ystr "1.0")))
      (yc_message ~mode:Mm_fatal_error ["version_compare_equal: 1.0 should be <= 1.0"]);
    yifthen (ynot (yversion_less_equal (ystr "1.0") (ystr "2.0")))
      (yc_message ~mode:Mm_fatal_error ["version_compare_equal: 1.0 should be <= 2.0"]);
    yifthen (ynot (yversion_greater_equal (ystr "2.0") (ystr "2.0")))
      (yc_message ~mode:Mm_fatal_error ["version_compare_equal: 2.0 should be >= 2.0"]);
  ])

(* AND / OR compound conditions *)
let compound =
  check_cmake "compound" (ESeq [
    yc_set (ycvar "x") [ ystr "5" ];
    (* AND: both true *)
    yifthen (ynot (yand (ygreater (ycref "x") (ystr "3")) (yless (ycref "x") (ystr "10"))))
      (yc_message ~mode:Mm_fatal_error ["compound AND: 3 < 5 < 10 failed"]);
    (* OR: at least one true *)
    yifthen (ynot (yor (yequal (ycref "x") (ystr "5")) (yequal (ycref "x") (ystr "99"))))
      (yc_message ~mode:Mm_fatal_error ["compound OR: x==5 OR x==99 failed"]);
    (* NOT (AND): x==0 AND x==1 is false → NOT true; use yif to assert *)
    yif (ynot (yand (yequal (ycref "x") (ystr "0")) (yequal (ycref "x") (ystr "1"))))
      (ESeq [])
      (yc_message ~mode:Mm_fatal_error ["compound NOT(AND false false) should be true"]);
  ])

(* Numeric EQUAL / LESS / GREATER / LESS_EQUAL / GREATER_EQUAL *)
let numeric_compare =
  check_cmake "numeric_compare" (ESeq [
    yifthen (ynot (yequal (ystr "42") (ystr "42")))
      (yc_message ~mode:Mm_fatal_error ["EQUAL: 42 == 42 failed"]);
    yifthen (ynot (yless (ystr "3") (ystr "10")))
      (yc_message ~mode:Mm_fatal_error ["LESS: 3 < 10 failed"]);
    yifthen (ynot (ygreater (ystr "10") (ystr "3")))
      (yc_message ~mode:Mm_fatal_error ["GREATER: 10 > 3 failed"]);
    yifthen (ynot (yless_equal (ystr "5") (ystr "5")))
      (yc_message ~mode:Mm_fatal_error ["LESS_EQUAL: 5 <= 5 failed"]);
    yifthen (ynot (ygreater_equal (ystr "7") (ystr "5")))
      (yc_message ~mode:Mm_fatal_error ["GREATER_EQUAL: 7 >= 5 failed"]);
  ])

(* STRLESS / STRGREATER / STRLESS_EQUAL / STRGREATER_EQUAL *)
let string_compare =
  check_cmake "string_compare" (ESeq [
    yifthen (ynot (ystrless (ystr "apple") (ystr "banana")))
      (yc_message ~mode:Mm_fatal_error ["STRLESS: apple < banana failed"]);
    yifthen (ynot (ystrgreater (ystr "zebra") (ystr "apple")))
      (yc_message ~mode:Mm_fatal_error ["STRGREATER: zebra > apple failed"]);
    yifthen (ynot (ystrless_equal (ystr "abc") (ystr "abc")))
      (yc_message ~mode:Mm_fatal_error ["STRLESS_EQUAL: abc <= abc failed"]);
    yifthen (ynot (ystrgreater_equal (ystr "z") (ystr "a")))
      (yc_message ~mode:Mm_fatal_error ["STRGREATER_EQUAL: z >= a failed"]);
  ])

(* EXISTS / IS_DIRECTORY / IS_ABSOLUTE *)
let file_tests =
  check_cmake "file_tests" (ESeq [
    (* /tmp always exists and is a directory on Linux *)
    yifthen (ynot (yexists (ystr "/tmp")))
      (yc_message ~mode:Mm_fatal_error ["EXISTS: /tmp should exist"]);
    yifthen (ynot (yis_directory (ystr "/tmp")))
      (yc_message ~mode:Mm_fatal_error ["IS_DIRECTORY: /tmp should be a directory"]);
    (* /tmp/nonexistent_yelu_test_xyz should not exist *)
    yifthen (yexists (ystr "/tmp/nonexistent_yelu_test_xyz"))
      (yc_message ~mode:Mm_fatal_error ["EXISTS: nonexistent path should not exist"]);
    (* absolute vs relative *)
    yifthen (ynot (yis_absolute (ystr "/usr")))
      (yc_message ~mode:Mm_fatal_error ["IS_ABSOLUTE: /usr should be absolute"]);
    yifthen (yis_absolute (ystr "relative/path"))
      (yc_message ~mode:Mm_fatal_error ["IS_ABSOLUTE: relative/path should not be absolute"]);
  ])

let () =
  Alcotest.run "if"
    [ ("in_list",              [ in_list ]);
      ("matches",              [ matches ]);
      ("version_compare",      [ version_compare ]);
      ("version_compare_equal", [ version_compare_equal ]);
      ("compound",             [ compound ]);
      ("numeric_compare",      [ numeric_compare ]);
      ("string_compare",       [ string_compare ]);
      ("file_tests",           [ file_tests ]);
    ]
