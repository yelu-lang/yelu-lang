(** conf-run level tests for math(EXPR).
    Mirrors Tests/RunCMake/math/MATH.cmake and MATH-ToleratedExpression.cmake. *)

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

(* Mirrors Tests/RunCMake/math/MATH.cmake *)
let math =
  check_cmake "math" (Ystmt_list [
    yc_math "100 * 10" (ycvar "r");
    yifthen (ynot (ystrequal (ycref "r") (ystr "1000")))
      (yc_message ~mode:Mm_fatal_error ["100 * 10 should be 1000"]);
    yc_math "100 * 10" (ycvar "r") ~output_format:Yelu_langs.Lang_cmake.Decical;
    yifthen (ynot (ystrequal (ycref "r") (ystr "1000")))
      (yc_message ~mode:Mm_fatal_error ["100 * 10 DECIMAL should be 1000"]);
    yc_math "100 * 0xA" (ycvar "r") ~output_format:Yelu_langs.Lang_cmake.Decical;
    yifthen (ynot (ystrequal (ycref "r") (ystr "1000")))
      (yc_message ~mode:Mm_fatal_error ["100 * 0xA DECIMAL should be 1000"]);
    yc_math "100 * 0xA" (ycvar "r") ~output_format:Yelu_langs.Lang_cmake.Hexdecimal;
    yifthen (ynot (ystrequal (ycref "r") (ystr "0x3e8")))
      (yc_message ~mode:Mm_fatal_error ["100 * 0xA HEXADECIMAL should be 0x3e8"]);
  ])

(* Mirrors Tests/RunCMake/math/MATH-ToleratedExpression.cmake
   Tolerated expression uses single-quotes around the expression (deprecated syntax).
   cmake exits 0 but emits a dev warning to stderr. *)
let math_tolerated =
  Alcotest.test_case "math_tolerated" `Quick (fun () ->
      let prog = Ystmt_list [
        yc_math "'2*1-1'" (ycvar "var");
        yifthen (ynot (ystrequal (ycref "var") (ystr "1")))
          (yc_message ~mode:Mm_fatal_error ["tolerated expression should eval to 1"]);
      ] in
      let result = run_script (compile prog) in
      check_exit 0 result;
      check_stderr_matches
        "Unexpected character in expression at position 1" result)

(* Mirrors Tests/RunCMake/math/Overflow.cmake
   cmake exits 0 for all overflow; values wrap with 64-bit signed semantics.
   Note: cmake emits CMake Warning (dev) in configure mode, but NOT in -P script
   mode — so we only verify the computed values, not the warning. *)
let math_overflow =
  check_cmake "overflow" (Ystmt_list [
    (* 0x7FFFFFFFFFFFFFFF + 1 wraps to INT64_MIN *)
    yc_math "0x7FFFFFFFFFFFFFFF + 1" (ycvar "r");
    yifthen (ynot (ystrequal (ycref "r") (ystr "-9223372036854775808")))
      (yc_message ~mode:Mm_fatal_error ["overflow +1 wrap failed"]);
    (* -0x7FFFFFFFFFFFFFFF - 2 wraps to INT64_MAX *)
    yc_math "-0x7FFFFFFFFFFFFFFF - 2" (ycvar "r");
    yifthen (ynot (ystrequal (ycref "r") (ystr "9223372036854775807")))
      (yc_message ~mode:Mm_fatal_error ["overflow -1 wrap failed"]);
    (* 4 << 65: shift exponent too large, wraps mod 64 → 4 << 1 = 8 *)
    yc_math "4 << 65" (ycvar "r");
    yifthen (ynot (ystrequal (ycref "r") (ystr "8")))
      (yc_message ~mode:Mm_fatal_error ["shift-too-large wrap failed"]);
  ])

(* Division, modulo, and bitwise operators *)
let math_ops =
  check_cmake "ops" (Ystmt_list [
    yc_math "17 / 5" (ycvar "r");
    yifthen (ynot (ystrequal (ycref "r") (ystr "3")))
      (yc_message ~mode:Mm_fatal_error ["17 / 5 should be 3 (integer division)"]);
    yc_math "17 % 5" (ycvar "r");
    yifthen (ynot (ystrequal (ycref "r") (ystr "2")))
      (yc_message ~mode:Mm_fatal_error ["17 % 5 should be 2"]);
    (* bitwise: 12 = 0b1100, 10 = 0b1010 *)
    yc_math "12 & 10" (ycvar "r");
    yifthen (ynot (ystrequal (ycref "r") (ystr "8")))
      (yc_message ~mode:Mm_fatal_error ["12 & 10 should be 8"]);
    yc_math "12 | 10" (ycvar "r");
    yifthen (ynot (ystrequal (ycref "r") (ystr "14")))
      (yc_message ~mode:Mm_fatal_error ["12 | 10 should be 14"]);
    yc_math "12 ^ 10" (ycvar "r");
    yifthen (ynot (ystrequal (ycref "r") (ystr "6")))
      (yc_message ~mode:Mm_fatal_error ["12 ^ 10 should be 6"]);
    yc_math "1 << 3" (ycvar "r");
    yifthen (ynot (ystrequal (ycref "r") (ystr "8")))
      (yc_message ~mode:Mm_fatal_error ["1 << 3 should be 8"]);
    yc_math "16 >> 2" (ycvar "r");
    yifthen (ynot (ystrequal (ycref "r") (ystr "4")))
      (yc_message ~mode:Mm_fatal_error ["16 >> 2 should be 4"]);
  ])

(* Bitwise NOT — unary ~ operator *)
let math_bitnot =
  check_cmake "bitnot" (Ystmt_list [
    yc_math "~0" (ycvar "r");
    yifthen (ynot (ystrequal (ycref "r") (ystr "-1")))
      (yc_message ~mode:Mm_fatal_error ["~0 should be -1"]);
    yc_math "~1" (ycvar "r");
    yifthen (ynot (ystrequal (ycref "r") (ystr "-2")))
      (yc_message ~mode:Mm_fatal_error ["~1 should be -2"]);
    yc_math "~0" (ycvar "r") ~output_format:Yelu_langs.Lang_cmake.Hexdecimal;
    yifthen (ynot (ystrequal (ycref "r") (ystr "0xffffffffffffffff")))
      (yc_message ~mode:Mm_fatal_error ["~0 hex should be 0xffffffffffffffff"]);
  ])

let () =
  Alcotest.run "math"
    [ ("math",      [ math ]);
      ("tolerated", [ math_tolerated ]);
      ("overflow",  [ math_overflow ]);
      ("ops",       [ math_ops ]);
      ("bitnot",    [ math_bitnot ]);
    ]
