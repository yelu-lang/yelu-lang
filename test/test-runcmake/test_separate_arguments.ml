(** conf-run level tests for separate_arguments.
    Mirrors Tests/RunCMake/separate_arguments/ positive scripts.
    WindowsCommand and ProgramCommand* skipped (platform/PATH-search specific). *)

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

(* Mirrors Tests/RunCMake/separate_arguments/EmptyCommand.cmake
   Old-style separate_arguments on an undefined variable leaves it undefined. *)
let empty_command =
  check_cmake "empty_command" (ESeq [
    (* nothing is not set — separate_arguments(nothing) must leave it undefined *)
    yc_separate_arguments_plain (ycvar "nothing");
    yifthen (yis_defined (ycstr "nothing"))
      (yc_message ~mode:Mm_fatal_error ["empty_command: nothing should remain undefined"]);
  ])

(* Mirrors Tests/RunCMake/separate_arguments/PlainCommand.cmake
   Old-style: split "a b  c" → "a;b;;c" (double space → empty middle element). *)
let plain_command =
  check_cmake "plain_command" (ESeq [
    yc_set (ycvar "out") [ ystr "a b  c" ];
    yc_separate_arguments_plain (ycvar "out");
    yifthen (ynot (ystrequal (ycref "out") (ystr "a;b;;c")))
      (yc_message ~mode:Mm_fatal_error ["plain_command failed"]);
  ])

(* Mirrors Tests/RunCMake/separate_arguments/UnixCommand.cmake (simple subset).
   Full test uses complex shell quoting; we cover the structural cases. *)
let unix_simple =
  check_cmake "unix_simple" (ESeq [
    (* plain space-separated words *)
    yc_separate_arguments ~mode:Sa_unix_command ~input:(ystr "a b c") (ycvar "out");
    yifthen (ynot (ystrequal (ycref "out") (ystr "a;b;c")))
      (yc_message ~mode:Mm_fatal_error ["unix_simple: a b c failed"]);
    (* single-quoted token containing space *)
    yc_separate_arguments ~mode:Sa_unix_command ~input:(ystr "a 'b c' d") (ycvar "out");
    yifthen (ynot (ystrequal (ycref "out") (ystr "a;b c;d")))
      (yc_message ~mode:Mm_fatal_error ["unix_simple: quoted token failed"]);
    (* empty input → empty output (defined as empty) *)
    yc_separate_arguments ~mode:Sa_unix_command ~input:(ystr "") (ycvar "out");
    yifthen (ynot (ystrequal (ycref "out") (ystr "")))
      (yc_message ~mode:Mm_fatal_error ["unix_simple: empty input failed"]);
  ])

(* NativeCommand on Linux behaves identically to UnixCommand for the simple cases. *)
let native_command =
  check_cmake "native_command" (ESeq [
    yc_separate_arguments ~mode:Sa_native_command ~input:(ystr "a b c") (ycvar "out");
    yifthen (ynot (ystrequal (ycref "out") (ystr "a;b;c")))
      (yc_message ~mode:Mm_fatal_error ["native_command: a b c failed"]);
  ])

let () =
  Alcotest.run "separate_arguments"
    [ ("empty_command",  [ empty_command ]);
      ("plain_command",  [ plain_command ]);
      ("unix_simple",    [ unix_simple ]);
      ("native_command", [ native_command ]);
    ]
