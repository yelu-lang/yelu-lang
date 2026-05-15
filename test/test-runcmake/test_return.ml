(** conf-run level tests for return / return(PROPAGATE).
    PropagateFromDirectory and block()-using variants are skipped (require
    add_subdirectory or block(), not in yelu).
    CMP0140 / return(PROPAGATE) tests are skipped (cmake_policy not in yelu).
    Function return values use PARENT_SCOPE instead. *)

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

(* Mirrors Tests/RunCMake/return/PropagateNothing.cmake
   return() with no args at script top level — must exit 0. *)
let propagate_nothing =
  check_cmake "propagate_nothing" (yc_return ())

(* return() from inside a function exits the function.
   Result is returned via PARENT_SCOPE (traditional cmake pattern).
   A function searches a list; on match sets found=yes in parent scope and returns.
   This also tests that return() inside a foreach exits the function, not just the loop. *)
let return_from_foreach =
  check_cmake "return_from_foreach" (ESeq [
    yc_function (ycstr "finder") []
      [ yc_foreach_in ~items:[ ystr "a"; ystr "b"; ystr "target"; ystr "c" ] (ycvar "item")
          (ESeq [
            yifthen (ystrequal (ycref "item") (ystr "target"))
              (ESeq [
                yc_set ~parent_scope:true (ycvar "found") [ ystr "yes" ];
                yc_return ();
              ]);
          ]);
        yc_set ~parent_scope:true (ycvar "found") [ ystr "no" ] ];
    yc_apply (ycstr "finder") [];
    yifthen (ynot (ystrequal (ycref "found") (ystr "yes")))
      (yc_message ~mode:Mm_fatal_error ["return from foreach: found should be yes"]);
  ])

(* function scope: set() inside a function is local; after return
   the caller sees its own pre-call value, not the function's local value. *)
let function_scope =
  check_cmake "function_scope" (ESeq [
    yc_function (ycstr "setlocal") []
      [ yc_set (ycvar "x") [ ystr "local" ] ];
    yc_set (ycvar "x") [ ystr "outer" ];
    yc_apply (ycstr "setlocal") [];
    yifthen (ynot (ystrequal (ycref "x") (ystr "outer")))
      (yc_message ~mode:Mm_fatal_error ["function_scope: x should remain outer"]);
  ])

let () =
  Alcotest.run "return"
    [ ("propagate_nothing",  [ propagate_nothing ]);
      ("return_from_foreach", [ return_from_foreach ]);
      ("function_scope",     [ function_scope ]);
    ]
