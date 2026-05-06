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

(* --- Dual-write: cache set also writes normal on first configure --- *)
let cache_writes_normal =
  Alcotest.test_case "cache_writes_normal" `Quick (fun () ->
    let result = run_configure (compile (Ystmt_list [
      yc_set_cache (ycvar "dual") [ ystr "cached" ] ~docstring:"test";
      yifthen (ynot (ystrequal (ycref "dual") (ystr "cached")))
        (yc_message ~mode:Mm_fatal_error ["dual: normal should be cached"]);
    ])) in
    check_cache "dual" "cached" result)

(* --- Re-configure: cache already exists, script cache-set is no-op --- *)
let cache_noop_on_reconfigure =
  (* We simulate by calling run_configure twice — but the second run
     creates a fresh temp dir, so the cache from run 1 doesn't persist.
     Instead, test: one configure with two cache-sets of the same name. *)
  Alcotest.test_case "cache_noop_on_reconfigure" `Quick (fun () ->
    let result = run_configure (compile (Ystmt_list [
      yc_set_cache (ycvar "sticky") [ ystr "first" ] ~docstring:"t";
      (* second set without FORCE — should be ignored because cache already exists
         from the first set in the same configure run *)
      yc_set_cache (ycvar "sticky") [ ystr "second" ] ~docstring:"t";
      yifthen (ynot (ystrequal (ycref "sticky") (ystr "first")))
        (yc_message ~mode:Mm_fatal_error ["sticky: should remain first"]);
    ])) in
    check_cache "sticky" "first" result)

(* --- unset(normal) — cache persists, ${VAR} falls back to cache --- *)
let unset_normal_cache_persists =
  Alcotest.test_case "unset_normal_cache_persists" `Quick (fun () ->
    let result = run_configure (compile (Ystmt_list [
      yc_set (ycvar "unc") [ ystr "normal_val" ];
      yc_set_cache (ycvar "unc") [ ystr "cache_val" ] ~docstring:"t";
      yc_set (ycvar "unc") [];  (* unset normal: set to empty *)
      yifthen (ynot (yis_defined (ycstr "unc")))
        (yc_message ~mode:Mm_fatal_error ["unc: should still be defined via cache fallback"]);
      yifthen (ynot (ystrequal (ycref "unc") (ystr "cache_val")))
        (yc_message ~mode:Mm_fatal_error ["unc: should fallback to cache_val"]);
    ])) in
    check_cache "unc" "cache_val" result)

(* --- unset(CACHE) — removes BOTH cache and normal --- *)
let unset_cache_removes_both =
  Alcotest.test_case "unset_cache_removes_both" `Quick (fun () ->
    let result = run_configure (compile (Ystmt_list [
      yc_set_cache (ycvar "rm") [ ystr "val" ] ~docstring:"t";
      yc_unset_cache (ycvar "rm");
      yifthen (yis_defined (ycstr "rm"))
        (yc_message ~mode:Mm_fatal_error ["rm: should be undefined after unset CACHE"]);
    ])) in
  (* cache variable should be absent *)
  match cache_get "rm" result with
  | None -> ()
  | Some _ -> Alcotest.fail "rm: cache entry should be absent after unset CACHE")

(* --- normal then cache (same name): cache overwrites normal --- *)
let normal_then_cache =
  Alcotest.test_case "normal_then_cache" `Quick (fun () ->
    let result = run_configure (compile (Ystmt_list [
      yc_set (ycvar "nc") [ ystr "first_n" ];
      yc_set_cache (ycvar "nc") [ ystr "then_c" ] ~docstring:"t";
      yifthen (ynot (ystrequal (ycref "nc") (ystr "then_c")))
        (yc_message ~mode:Mm_fatal_error ["nc: normal should be overwritten by cache dual-write"]);
    ])) in
    check_cache "nc" "then_c" result)

(* --- cache then normal: normal reads first --- *)
let cache_then_normal =
  Alcotest.test_case "cache_then_normal" `Quick (fun () ->
    let result = run_configure (compile (Ystmt_list [
      yc_set_cache (ycvar "cn") [ ystr "first_c" ] ~docstring:"t";
      yc_set (ycvar "cn") [ ystr "then_n" ];
      yifthen (ynot (ystrequal (ycref "cn") (ystr "then_n")))
        (yc_message ~mode:Mm_fatal_error ["cn: normal should win read"]);
      yifthen (ynot (ystrequal (ycref "cn") (ystr "then_n")))
        (yc_message ~mode:Mm_fatal_error ["cn: read should be then_n"]);
    ])) in
    check_cache "cn" "first_c" result)

(* --- option() equivalence: option(VAR "msg" ON) === set(VAR ON CACHE BOOL "msg") --- *)
let option_equiv_set_cache_bool =
  Alcotest.test_case "option_equiv" `Quick (fun () ->
    let prog_opt = Ystmt_list [
      yc_option ~value:(ybool true) ~msg:"enable foo" (ycvar "opt1");
    ] in
    let prog_set = Ystmt_list [
      yc_set_cache ~cache_type:Ct_bool (ycvar "opt1") [ ystr "ON" ] ~docstring:"enable foo";
    ] in
    let r1 = run_configure (compile prog_opt) in
    let r2 = run_configure (compile prog_set) in
    match cache_get "opt1" r1, cache_get "opt1" r2 with
    | Some v1, Some v2 when String.equal v1 v2 -> ()
    | v1, v2 -> Alcotest.failf "option_equiv: opt1 values differ: option=%s, set_cache=%s"
                 (Option.value ~default:"<none>" v1) (Option.value ~default:"<none>" v2))

let () =
  Alcotest.run "set"
    [ ("normal_unset",                 [ normal_unset ]);
      ("parent_scope",                 [ parent_scope ]);
      ("cache_first_write_wins",       [ cache_first_write_wins ]);
      ("cache_force",                  [ cache_force ]);
      ("cache_path_type",              [ cache_path_type ]);
      ("cache_bool_type",              [ cache_bool_type ]);
      ("cache_string_type",            [ cache_string_type ]);
      ("unset_cache",                  [ unset_cache ]);
      ("cache_writes_normal",          [ cache_writes_normal ]);
      ("cache_noop_on_reconfigure",    [ cache_noop_on_reconfigure ]);
      ("unset_normal_cache_persists",  [ unset_normal_cache_persists ]);
      ("unset_cache_removes_both",     [ unset_cache_removes_both ]);
      ("normal_then_cache",            [ normal_then_cache ]);
      ("cache_then_normal",            [ cache_then_normal ]);
      ("option_equiv",                 [ option_equiv_set_cache_bool ]);
    ]
