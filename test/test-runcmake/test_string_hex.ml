(** conf-run level tests for string(HEX ...).
    Covers: basic ASCII encoding, empty string, multi-byte input. *)

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

(* "abc" → "616263" *)
let hex_ascii =
  check_cmake "hex_ascii" (Ystmt_list [
    yc_string_hex (ystr "abc") (ycvar "out");
    yifthen (ynot (ystrequal (ycref "out") (ystr "616263")))
      (yc_message ~mode:Mm_fatal_error ["HEX: abc should be 616263"]);
  ])

(* empty string → "" *)
let hex_empty =
  check_cmake "hex_empty" (Ystmt_list [
    yc_string_hex (ystr "") (ycvar "out");
    yifthen (ynot (ystrequal (ycref "out") (ystr "")))
      (yc_message ~mode:Mm_fatal_error ["HEX: empty should be empty"]);
  ])

(* "Hello" → "48656c6c6f" *)
let hex_hello =
  check_cmake "hex_hello" (Ystmt_list [
    yc_string_hex (ystr "Hello") (ycvar "out");
    yifthen (ynot (ystrequal (ycref "out") (ystr "48656c6c6f")))
      (yc_message ~mode:Mm_fatal_error ["HEX: Hello should be 48656c6c6f"]);
  ])

(* single space → "20" *)
let hex_space =
  check_cmake "hex_space" (Ystmt_list [
    yc_string_hex (ystr " ") (ycvar "out");
    yifthen (ynot (ystrequal (ycref "out") (ystr "20")))
      (yc_message ~mode:Mm_fatal_error ["HEX: space should be 20"]);
  ])

let () =
  Alcotest.run "string_hex"
    [ ("hex_ascii", [ hex_ascii ]);
      ("hex_empty", [ hex_empty ]);
      ("hex_hello", [ hex_hello ]);
      ("hex_space", [ hex_space ]);
    ]
