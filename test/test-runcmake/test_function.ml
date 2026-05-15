(** conf-run level tests for function() introspection variables.
    Covers: CMAKE_CURRENT_FUNCTION, CMAKE_CURRENT_LIST_FILE, ARGC/ARGV*.
    SKIP: CMAKE_CURRENT_FUNCTION_LINE — declared since cmake 3.17 but not
    populated in cmake -P script mode (tested on cmake 3.28; always empty).
    SKIP: CMAKE_CURRENT_FUNCTION_LIST_DIR/FILE — same as CMAKE_CURRENT_LIST_*
    in script mode; only differ when include()d from another file. *)

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

(* CMAKE_CURRENT_FUNCTION: name of the currently executing function *)
let current_function_name =
  check_cmake "current_function_name" (ESeq [
    yc_function (ycstr "my_func") []
      [ yc_set ~parent_scope:true (ycvar "fn_name") [ ycref "CMAKE_CURRENT_FUNCTION" ] ];
    yc_apply (ycstr "my_func") [];
    yifthen (ynot (ystrequal (ycref "fn_name") (ystr "my_func")))
      (yc_message ~mode:Mm_fatal_error
        ["CMAKE_CURRENT_FUNCTION: expected my_func"]);
  ])

(* SKIP: CMAKE_CURRENT_FUNCTION_LINE — not populated in cmake -P script mode.
   See language_coverage.md §Known Gaps. *)

(* CMAKE_CURRENT_LIST_FILE: path of the script being processed *)
let current_list_file =
  check_cmake "current_list_file" (ESeq [
    yc_function (ycstr "file_func") []
      [ yc_set ~parent_scope:true (ycvar "cl_file") [ ycref "CMAKE_CURRENT_LIST_FILE" ] ];
    yc_apply (ycstr "file_func") [];
    yifthen (ystrequal (ycref "cl_file") (ystr ""))
      (yc_message ~mode:Mm_fatal_error
        ["CMAKE_CURRENT_LIST_FILE: expected non-empty"]);
    (* must be an absolute path *)
    yifthen (ynot (yis_absolute (ycref "cl_file")))
      (yc_message ~mode:Mm_fatal_error
        ["CMAKE_CURRENT_LIST_FILE: expected absolute path"]);
  ])

(* cmake function args: ARGC, ARGV, ARGN, ARG0 etc. *)
let function_args =
  check_cmake "function_args" (ESeq [
    yc_function (ycstr "arg_func") [ "a"; "b" ]
      [ yc_set ~parent_scope:true (ycvar "argc_out") [ ycref "ARGC" ];
        yc_set ~parent_scope:true (ycvar "argv0_out") [ ycref "ARGV0" ];
        yc_set ~parent_scope:true (ycvar "argv_out") [ ycref "ARGV" ] ];
    yc_apply (ycstr "arg_func") [ ystr "foo"; ystr "bar" ];
    yifthen (ynot (ystrequal (ycref "argc_out") (ystr "2")))
      (yc_message ~mode:Mm_fatal_error ["ARGC should be 2"]);
    yifthen (ynot (ystrequal (ycref "argv0_out") (ystr "foo")))
      (yc_message ~mode:Mm_fatal_error ["ARGV0 should be foo"]);
    yifthen (ynot (ystrequal (ycref "argv_out") (ystr "foo;bar")))
      (yc_message ~mode:Mm_fatal_error ["ARGV should be foo;bar"]);
  ])

let () =
  Alcotest.run "function"
    [ ("current_function_name", [ current_function_name ]);
      ("current_list_file",     [ current_list_file ]);
      ("function_args",         [ function_args ]);
    ]
