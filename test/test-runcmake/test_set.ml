(** conf-run level tests for set / unset.
    Covers: normal set/unset, PARENT_SCOPE, cache first-write-wins, FORCE,
    unset(CACHE). Env-var tests deferred (need cmake_runner env support). *)

open Yelu_langs.Lang_cmake
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

(* set then unset — variable becomes undefined *)
let normal_unset =
  check_cmake "normal_unset" (Ystmt_list [
    yc_set (ycvar "x") [ ystr "hello" ];
    yifthen (ynot (yis_defined (ycstr "x")))
      (yc_message ~mode:Mm_fatal_error ["normal_unset: x should be defined"]);
    yc_set (ycvar "x") [];   (* set to empty = undefine *)
    yifthen (yis_defined (ycstr "x"))
      (yc_message ~mode:Mm_fatal_error ["normal_unset: x should be undefined after empty set"]);
  ])

(* PARENT_SCOPE: set in function propagates to caller *)
let parent_scope =
  check_cmake "parent_scope" (Ystmt_list [
    yc_function (ycstr "setval") []
      [ yc_set ~parent_scope:true (ycvar "result") [ ystr "from_func" ] ];
    yc_apply (ycstr "setval") [];
    yifthen (ynot (ystrequal (ycref "result") (ystr "from_func")))
      (yc_message ~mode:Mm_fatal_error ["parent_scope: result should be from_func"]);
  ])

(* cache first-write-wins: second set without FORCE is ignored *)
let cache_first_write_wins =
  check_cmake "cache_first_write_wins" (Ystmt_list [
    yc_set_cache (ycvar "cfg") [ ystr "initial" ] ~docstring:"test";
    yc_set_cache (ycvar "cfg") [ ystr "ignored" ] ~docstring:"test";
    yifthen (ynot (ystrequal (ycref "cfg") (ystr "initial")))
      (yc_message ~mode:Mm_fatal_error ["cache_first_write_wins: cfg should remain initial"]);
  ])

(* cache FORCE: overrides existing cache entry *)
let cache_force =
  check_cmake "cache_force" (Ystmt_list [
    yc_set_cache (ycvar "cfg") [ ystr "initial" ] ~docstring:"test";
    yc_set_cache ~force:true (ycvar "cfg") [ ystr "overridden" ] ~docstring:"test";
    yifthen (ynot (ystrequal (ycref "cfg") (ystr "overridden")))
      (yc_message ~mode:Mm_fatal_error ["cache_force: cfg should be overridden"]);
  ])

(* cache type PATH *)
let cache_path_type =
  check_cmake "cache_path_type" (Ystmt_list [
    yc_set_cache ~cache_type:Ct_path (ycvar "mypath") [ ystr "/usr/lib" ] ~docstring:"a path";
    yifthen (ynot (ystrequal (ycref "mypath") (ystr "/usr/lib")))
      (yc_message ~mode:Mm_fatal_error ["cache_path_type: mypath should be /usr/lib"]);
  ])

(* unset(CACHE): removes cache entry, variable becomes undefined *)
let unset_cache =
  check_cmake "unset_cache" (Ystmt_list [
    yc_set_cache (ycvar "tmp") [ ystr "val" ] ~docstring:"temp";
    yifthen (ynot (yis_defined (ycstr "tmp")))
      (yc_message ~mode:Mm_fatal_error ["unset_cache: tmp should be defined"]);
    yc_unset_cache (ycvar "tmp");
    yifthen (yis_defined (ycstr "tmp"))
      (yc_message ~mode:Mm_fatal_error ["unset_cache: tmp should be undefined after unset"]);
  ])

(* cache type BOOL: value is ON/OFF *)
let cache_bool_type =
  check_cmake "cache_bool_type" (Ystmt_list [
    yc_set_cache ~cache_type:Ct_bool (ycvar "flag") [ ystr "ON" ] ~docstring:"a bool flag";
    yifthen (ynot (ystrequal (ycref "flag") (ystr "ON")))
      (yc_message ~mode:Mm_fatal_error ["cache_bool_type: flag should be ON"]);
  ])

(* cache type STRING: generic string value *)
let cache_string_type =
  check_cmake "cache_string_type" (Ystmt_list [
    yc_set_cache ~cache_type:Ct_string (ycvar "greeting") [ ystr "hello" ] ~docstring:"a string";
    yifthen (ynot (ystrequal (ycref "greeting") (ystr "hello")))
      (yc_message ~mode:Mm_fatal_error ["cache_string_type: greeting should be hello"]);
  ])

let () =
  Alcotest.run "set"
    [ ("normal_unset",           [ normal_unset ]);
      ("parent_scope",           [ parent_scope ]);
      ("cache_first_write_wins", [ cache_first_write_wins ]);
      ("cache_force",            [ cache_force ]);
      ("cache_path_type",        [ cache_path_type ]);
      ("cache_bool_type",        [ cache_bool_type ]);
      ("cache_string_type",      [ cache_string_type ]);
      ("unset_cache",            [ unset_cache ]);
    ]
