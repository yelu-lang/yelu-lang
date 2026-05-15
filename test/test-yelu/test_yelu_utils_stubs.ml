(* Pinning tests for the "Known IR shape gaps" set documented in
   doc/yelu_cmake/status.md and the Yelu_cmake_utils header.

   Two stub flavors are exercised:
   - **Accept-and-discard**: helper accepts the unmodeled argument
     and emits cmake that ignores it. We assert the emitted text
     so a future fix to the IR ctor produces a visible diff.
   - **Failwith**: helper refuses to emit. We assert the exception
     so a future fix that adds real IR support and removes the
     failwith produces a visible diff.

   When the IR grows the real ctor, the matching test here should
   be the first thing to break; replace its expected output / drop
   the [Alcotest.check_raises] in the same commit that adds the
   ctor. *)

open Base
open Yelu_langs.Yelu_cmake
open Yelu_langs.Yelu_cmake_normal_target
open Yelu_langs.Yelu_cmake_utils

let emit_text expr =
  let cmake_ast = Yelu_langs.Yelu_cmake_emit.emit_ast expr in
  Fmt.str "%a" (Fmt.vbox Yelu_langs.Lang_cmake_pp.pp) cmake_ast

(* ============================================================
   Accept-and-discard stubs
   ============================================================ *)

let math_output_format_discarded =
  Alcotest.test_case "yc_math ~output_format is discarded" `Quick (fun () ->
    let with_hex =
      yc_math ~output_format:Yelu_langs.Lang_cmake.Hexdecimal "100 * 0xA" "r"
    in
    let with_dec =
      yc_math ~output_format:Yelu_langs.Lang_cmake.Decical "100 * 0xA" "r"
    in
    let without_format = yc_math "100 * 0xA" "r" in
    let t1 = emit_text with_hex in
    let t2 = emit_text with_dec in
    let t3 = emit_text without_format in
    Alcotest.(check string) "hex same as dec" t2 t1;
    Alcotest.(check string) "dec same as no-format" t3 t2;
    (* Sanity: emitted text contains a math(EXPR ...) call *)
    Alcotest.(check bool) "is math call" true
      (String.is_substring t1 ~substring:"math(EXPR"))

let add_exe_exclude_from_all_discarded =
  Alcotest.test_case "add_exe ~exclude_from_all silently dropped" `Quick (fun () ->
    let with_flag = add_exe ~exclude_from_all:true ~sources:[EString "a.c"] (ETarget "T") in
    let without = add_exe ~sources:[EString "a.c"] (ETarget "T") in
    Alcotest.(check string) "flag discarded"
      (emit_text without) (emit_text with_flag);
    Alcotest.(check bool) "no EXCLUDE_FROM_ALL in output" false
      (String.is_substring (emit_text with_flag) ~substring:"EXCLUDE_FROM_ALL"))

let add_lib_exclude_from_all_discarded =
  Alcotest.test_case "add_lib ~exclude_from_all silently dropped" `Quick (fun () ->
    let with_flag =
      add_lib ~exclude_from_all:true ~sources:[EString "a.c"] (ETarget "T") in
    let without =
      add_lib ~sources:[EString "a.c"] (ETarget "T") in
    Alcotest.(check string) "flag discarded"
      (emit_text without) (emit_text with_flag);
    Alcotest.(check bool) "no EXCLUDE_FROM_ALL in output" false
      (String.is_substring (emit_text with_flag) ~substring:"EXCLUDE_FROM_ALL"))

(* ============================================================
   Failwith stubs
   ============================================================ *)

let check_raises_failure name f =
  Alcotest.test_case name `Quick (fun () ->
    match f () with
    | exception Stdlib.Failure _ -> ()
    | _ ->
      Alcotest.failf "%s: expected Failure, got success" name)

let ystrless_raises =
  check_raises_failure "ystrless raises (no IR STRLESS)"
    (fun () -> ystrless (EString "a") (EString "b"))

let ystrgreater_raises =
  check_raises_failure "ystrgreater raises (no IR STRGREATER)"
    (fun () -> ystrgreater (EString "a") (EString "b"))

let ystrless_equal_raises =
  check_raises_failure "ystrless_equal raises (no IR STRLESS_EQUAL)"
    (fun () -> ystrless_equal (EString "a") (EString "b"))

let ystrgreater_equal_raises =
  check_raises_failure "ystrgreater_equal raises (no IR STRGREATER_EQUAL)"
    (fun () -> ystrgreater_equal (EString "a") (EString "b"))

let yc_string_json_get_raises =
  check_raises_failure "yc_string_json_get raises (opaque IR JSON op)"
    (fun () -> yc_string_json_get ~out:"OUT" (EString "{}"))

let yc_string_json_set_raises =
  check_raises_failure "yc_string_json_set raises"
    (fun () -> yc_string_json_set ~out:"OUT" ~value:(EString "v") (EString "{}"))

let yc_add_custom_command_target_raises =
  check_raises_failure "yc_add_custom_command_target raises (no TARGET-form IR)"
    (fun () ->
      yc_add_custom_command_target ~target:"T" ~when_:cw_post_build
        [{ command = "echo"; args = [] }])

let () =
  Alcotest.run "Yelu_cmake_utils stubs" [
    "accept-and-discard", [
      math_output_format_discarded;
      add_exe_exclude_from_all_discarded;
      add_lib_exclude_from_all_discarded;
    ];
    "failwith", [
      ystrless_raises;
      ystrgreater_raises;
      ystrless_equal_raises;
      ystrgreater_equal_raises;
      yc_string_json_get_raises;
      yc_string_json_set_raises;
      yc_add_custom_command_target_raises;
    ];
  ]
