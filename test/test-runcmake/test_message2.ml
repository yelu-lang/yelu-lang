(** conf-run tests for message() log-level modes and context/indent.
    VERBOSE/DEBUG/TRACE/DEPRECATION require --log-level flag to be visible.
    CMAKE_MESSAGE_CONTEXT requires --log-context flag. *)

open Yelu_langs.Lang_yelu_utils
open Yelu_langs.Lang_yelu_compile
open Yelu_langs.Lang_cmake_pp
open Yelu_runner.Cmake_runner

let compile exp =
  let cmake_ast = compile empty_env exp |> snd in
  Fmt.str "%a" (Fmt.vbox pp) cmake_ast

(* VERBOSE/DEBUG/TRACE go to stdout; DEPRECATION goes to stderr *)
let check_log_level name level mode text ~on_stderr =
  Alcotest.test_case name `Quick (fun () ->
      let result = run_script ~flags:["--log-level=" ^ level] (compile (
        yc_message ~mode text)) in
      if result.exit_code <> 0 then
        Alcotest.failf "cmake exited %d\nstderr:\n%s" result.exit_code result.stderr;
      if on_stderr then check_stderr_matches (List.hd text) result
      else check_stdout_matches (List.hd text) result)

let msg_verbose =
  check_log_level "verbose" "VERBOSE" Mm_verbose ["verbose message here"] ~on_stderr:false

let msg_debug =
  check_log_level "debug" "DEBUG" Mm_debug ["debug message here"] ~on_stderr:false

let msg_trace =
  check_log_level "trace" "TRACE" Mm_trace ["trace message here"] ~on_stderr:false

(* DEPRECATION is not a log-level value — it always emits to stderr regardless of --log-level *)
let msg_deprecation =
  Alcotest.test_case "deprecation" `Quick (fun () ->
      let result = run_script (compile (yc_message ~mode:Mm_deprecation ["deprecation message here"])) in
      if result.exit_code <> 0 then
        Alcotest.failf "cmake exited %d\nstderr:\n%s" result.exit_code result.stderr;
      check_stderr_matches "deprecation message here" result)

(* VERBOSE not shown when log-level is STATUS (the default) *)
let msg_verbose_hidden =
  Alcotest.test_case "verbose_hidden" `Quick (fun () ->
      let result = run_script (compile (yc_message ~mode:Mm_verbose ["should not appear"])) in
      if result.exit_code <> 0 then
        Alcotest.failf "cmake exited %d\nstderr:\n%s" result.exit_code result.stderr;
      if Re.execp (Re.Posix.compile_pat "should not appear") result.stderr then
        Alcotest.failf "VERBOSE message should be hidden at default log level\nstderr:\n%s"
          result.stderr)

(* CMAKE_MESSAGE_CONTEXT: requires --log-context; prepends [ctx] to output *)
let msg_context =
  Alcotest.test_case "context" `Quick (fun () ->
      let result = run_script ~flags:["--log-context"] (compile (Ystmt_list [
        yc_list_append (ycvar "CMAKE_MESSAGE_CONTEXT") [ystr "myctx"];
        yc_message ~mode:Mm_status ["hello from context"];
      ])) in
      if result.exit_code <> 0 then
        Alcotest.failf "cmake exited %d\nstderr:\n%s" result.exit_code result.stderr;
      check_stdout_matches "[[]myctx[]] hello from context" result)

(* CMAKE_MESSAGE_INDENT: prepends indent strings unconditionally *)
let msg_indent =
  Alcotest.test_case "indent" `Quick (fun () ->
      let result = run_script (compile (Ystmt_list [
        yc_list_append (ycvar "CMAKE_MESSAGE_INDENT") [ystr "  "];
        yc_message ~mode:Mm_status ["indented"];
      ])) in
      if result.exit_code <> 0 then
        Alcotest.failf "cmake exited %d\nstderr:\n%s" result.exit_code result.stderr;
      check_stdout_matches "  indented" result)

let () =
  Alcotest.run "message2"
    [ ("verbose",        [ msg_verbose ]);
      ("debug",          [ msg_debug ]);
      ("trace",          [ msg_trace ]);
      ("deprecation",    [ msg_deprecation ]);
      ("verbose_hidden", [ msg_verbose_hidden ]);
      ("context",        [ msg_context ]);
      ("indent",         [ msg_indent ]);
    ]
