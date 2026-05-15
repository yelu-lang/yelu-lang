(** conf-run level tests for message().
    STATUS/CHECK_* output goes to stdout (prefixed "-- ") in cmake -P.
    NOTICE output goes to stdout (no prefix).
    WARNING/AUTHOR_WARNING go to stderr.
    FATAL_ERROR/SEND_ERROR exit non-zero. *)

open Yelu_langs.Yelu_cmake
open Yelu_langs.Yelu_cmake_utils
open Yelu_langs.Lang_cmake_pp
open Yelu_runner.Cmake_runner

let compile exp =
  Fmt.str "%a" (Fmt.vbox pp) (Yelu_langs.Yelu_cmake_emit.emit_ast exp)

let check_cmake_result name prog f =
  Alcotest.test_case name `Quick (fun () ->
      f (run_script (compile prog)))

(* STATUS message goes to stdout as "-- msg", exit 0 *)
let status_message =
  check_cmake_result "status_message" (
    yc_message ~mode:Mm_status ["hello from status"]
  ) (fun r ->
    check_exit 0 r;
    check_stdout_matches "hello from status" r)

(* CHECK_START / CHECK_PASS produces "-- Checking ...\n-- Checking ... - done" on stdout *)
let check_pass =
  check_cmake_result "check_pass" (ESeq [
    yc_message ~mode:Mm_check_start ["my feature"];
    yc_message ~mode:Mm_check_pass ["done"];
  ]) (fun r ->
    check_exit 0 r;
    check_stdout_matches "my feature" r;
    check_stdout_matches "my feature - done" r)

(* CHECK_FAIL: "-- optional dep - not found" on stdout, exits 0 *)
let check_fail =
  check_cmake_result "check_fail" (ESeq [
    yc_message ~mode:Mm_check_start ["optional dep"];
    yc_message ~mode:Mm_check_fail ["not found"];
  ]) (fun r ->
    check_exit 0 r;
    check_stdout_matches "optional dep" r;
    check_stdout_matches "optional dep - not found" r)

(* FATAL_ERROR exits non-zero *)
let fatal_error =
  check_cmake_result "fatal_error" (
    yc_message ~mode:Mm_fatal_error ["intentional fatal"]
  ) (fun r ->
    if r.exit_code = 0 then
      Alcotest.failf "expected non-zero exit for FATAL_ERROR, got 0")

(* WARNING is informational, exits 0 *)
let warning_message =
  check_cmake_result "warning_message" (
    yc_message ~mode:Mm_warning ["test warning"]
  ) (fun r ->
    check_exit 0 r;
    check_stderr_matches "test warning" r)

(* NOTICE: important message to stderr (no "CMake Warning" prefix), exits 0 *)
let notice_message =
  check_cmake_result "notice_message" (
    yc_message ~mode:Mm_notice ["notice text"]
  ) (fun r ->
    check_exit 0 r;
    check_stderr_matches "notice text" r)

(* AUTHOR_WARNING: goes to stderr as "CMake Warning (dev):", exits 0 *)
let author_warning_message =
  check_cmake_result "author_warning_message" (
    yc_message ~mode:Mm_author_warning ["dev warning text"]
  ) (fun r ->
    check_exit 0 r;
    check_stderr_matches "dev warning text" r)

(* SEND_ERROR: continues processing but exits non-zero *)
let send_error_message =
  check_cmake_result "send_error_message" (
    yc_message ~mode:Mm_send_error ["send error text"]
  ) (fun r ->
    if r.exit_code = 0 then
      Alcotest.failf "expected non-zero exit for SEND_ERROR, got 0")

let () =
  Alcotest.run "message"
    [ ("status_message",       [ status_message ]);
      ("check_pass",           [ check_pass ]);
      ("check_fail",           [ check_fail ]);
      ("fatal_error",          [ fatal_error ]);
      ("warning_message",      [ warning_message ]);
      ("notice_message",       [ notice_message ]);
      ("author_warning_message", [ author_warning_message ]);
      ("send_error_message",   [ send_error_message ]);
    ]
