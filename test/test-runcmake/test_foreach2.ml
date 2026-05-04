(** conf-run tests for foreach(... IN ZIP_LISTS ...). *)

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

(* ZIP_LISTS: parallel iteration over two lists *)
let zip_basic =
  check_cmake "zip_basic" (Ystmt_list [
    yc_set (ycvar "as") [ystr "a"; ystr "b"; ystr "c"];
    yc_set (ycvar "bs") [ystr "1"; ystr "2"; ystr "3"];
    yc_set (ycvar "ok") [ystr "1"];
    yc_foreach_zip [ycvar "x"; ycvar "y"] [ycvar "as"; ycvar "bs"] (Ystmt_list [
      (* if x_y pair doesn't match expected, clear ok *)
      yifthen (ystrequal (ycref "x") (ystr "a"))
        (yifthen (ynot (ystrequal (ycref "y") (ystr "1")))
          (yc_set (ycvar "ok") []));
      yifthen (ystrequal (ycref "x") (ystr "b"))
        (yifthen (ynot (ystrequal (ycref "y") (ystr "2")))
          (yc_set (ycvar "ok") []));
      yifthen (ystrequal (ycref "x") (ystr "c"))
        (yifthen (ynot (ystrequal (ycref "y") (ystr "3")))
          (yc_set (ycvar "ok") []));
    ]);
    yifthen (ynot (ystrequal (ycref "ok") (ystr "1")))
      (yc_message ~mode:Mm_fatal_error ["ZIP_LISTS pair mismatch"]);
  ])

(* ZIP_LISTS: unequal lengths — shorter list yields empty string for missing elements *)
let zip_unequal =
  check_cmake "zip_unequal" (Ystmt_list [
    yc_set (ycvar "xs") [ystr "a"; ystr "b"; ystr "c"];
    yc_set (ycvar "ys") [ystr "1"];
    yc_set (ycvar "count") [ystr "0"];
    yc_foreach_zip [ycvar "x"; ycvar "y"] [ycvar "xs"; ycvar "ys"] (Ystmt_list [
      yc_math (Fmt.str "${count} + 1") (ycvar "count");
    ]);
    (* all 3 elements of xs are visited *)
    yifthen (ynot (ystrequal (ycref "count") (ystr "3")))
      (yc_message ~mode:Mm_fatal_error ["ZIP_LISTS unequal: expected 3 iterations, got ${count}"]);
  ])

(* ZIP_LISTS: three lists *)
let zip_three =
  check_cmake "zip_three" (Ystmt_list [
    yc_set (ycvar "as") [ystr "a"; ystr "b"];
    yc_set (ycvar "bs") [ystr "1"; ystr "2"];
    yc_set (ycvar "cs") [ystr "x"; ystr "y"];
    yc_set (ycvar "result") [];
    yc_foreach_zip [ycvar "a"; ycvar "b"; ycvar "c"] [ycvar "as"; ycvar "bs"; ycvar "cs"] (Ystmt_list [
      yc_string_concat (ycvar "result") [ycref "result"; ycref "a"; ycref "b"; ycref "c"];
    ]);
    yifthen (ynot (ystrequal (ycref "result") (ystr "a1xb2y")))
      (yc_message ~mode:Mm_fatal_error ["ZIP_LISTS three: expected a1xb2y got ${result}"]);
  ])

let () =
  Alcotest.run "foreach2"
    [ ("zip_basic",   [ zip_basic ]);
      ("zip_unequal", [ zip_unequal ]);
      ("zip_three",   [ zip_three ]);
    ]
