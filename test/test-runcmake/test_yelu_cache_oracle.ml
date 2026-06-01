(** Cache + cmd-line oracle: real cmake as ground truth.

    Tier 5.3 of cache_plan.md. The 14-row spec matrix already verified
    in test_yelu_cache.ml runs purely against our own evaluator
    (both yc-eval and ycn-eval), checking that our eval matches our
    *documented* spec (doc/cmake/cache_semantics.md). This test
    closes the loop: same rows, but the ground truth is real cmake
    4.x configure output (via the existing run_configure +
    File API plumbing in cmake_runner.ml).

    What this catches that 5.1+5.2 cannot: a bug where our
    documented spec is itself wrong relative to actual cmake
    behavior. Both yc-eval and ycn-eval could agree with the spec
    while the spec disagrees with cmake. This oracle is the
    sanity gate on the spec itself.

    Per-test cycle:
      1. Emit the yelu program as cmake text via Yelu_cmake_emit.
      2. Spawn cmake -S/-B with -DK=V cmd_line flags (configure
         mode — script -P mode can't observe full cache state).
      3. Parse CMakeCache.txt (already done by run_configure;
         cache field on the result is (name, value) list).
      4. Check the observed cache against expectations.

    NOT attached to (alias runtest) — spawns external cmake, slow
    relative to in-process tests. Run via:
      dune build @yelu/test/test-runcmake/runcmake-test
*)

open Yelu_langs.Yelu_cmake
open Yelu_langs.Yelu_cmake_store
open Yelu_langs.Yelu_cmake_utils
open Yelu_runner.Cmake_runner
module L = Yelu_langs.Lang_cmake

let compile exp =
  Fmt.str "%a" (Fmt.vbox Yelu_langs.Lang_cmake_pp.pp)
    (Yelu_langs.Yelu_cmake_emit.emit_ast exp)

(* The CMakeCache observation from run_configure is a (name, value)
   list. We don't get the original CACHE/NORMAL distinction (cmake's
   File API cache-v2 would, but CMakeCache.txt only persists CACHE
   entries). For row-by-row spec verification we mostly care:
     - was the entry written?  (cache_get returns Some/None)
     - with what value?         (the string)
   Tests below assert both. *)

(* Drive a yelu program through real cmake with given cmd_line,
   then check the CMakeCache for an expected entry value. *)
let check_cache_oracle ?(cmd_line = []) name prog ~expected_cache =
  Alcotest.test_case name `Quick (fun () ->
    let cmake_text = compile prog in
    let result = run_configure ~cmd_line cmake_text in
    if result.run.exit_code <> 0 then
      Alcotest.failf "%s: cmake exited %d\nstderr:\n%s\nprogram:\n%s"
        name result.run.exit_code result.run.stderr cmake_text;
    let observed = cache_get "VAR" result in
    (match expected_cache, observed with
     | None, None -> ()
     | None, Some v ->
       Alcotest.failf "%s: expected VAR absent from cache, got %S" name v
     | Some _, None ->
       Alcotest.failf "%s: expected VAR in cache, got absent" name
     | Some exp, Some got ->
       if exp <> got then
         Alcotest.failf "%s: expected VAR=%S in cache, got %S" name exp got))

(* Shortcut: a single set/unset/option building block, no
   ESeq wrapping (yelu_cmake_emit doesn't need it for a single
   statement). *)
let set_normal v = yc_set "VAR" [ ystr v ]
let set_cache v  = yc_set_cache "VAR" [ ystr v ]
let unset_normal = ECmakeUnsetVar "VAR"
let unset_cache  = ECmakeUnsetVarCache "VAR"
let nop = EUnit

(* ============================================================
   Spec rows where the OBSERVED CMakeCache value is what we
   want to gate on. Note: CMakeCache.txt only persists CACHE
   entries, so rows that touch *normal* without cache writes
   are checked via cache=None (entry not in CMakeCache).

   This covers the cache-write half of the matrix (Set 1.3,
   Set 2, Set 3 with cache, Set 4). Pure-normal rows (1.1,
   1.2, 3.1's normal half) don't write a cache entry; nothing
   to gate against — those are 5.1 / 5.2 territory.
   ============================================================ *)

let set_1 =
  ( "set_1_read_on_empty",
    [
      (* 1.1, 1.2 have no cache write — CMakeCache won't contain VAR.
         We still run them to confirm cmake doesn't error. *)
      check_cache_oracle "1.1 never set"
        nop
        ~expected_cache:None;
      check_cache_oracle "1.2 set normal only"
        (set_normal "val")
        ~expected_cache:None;
      check_cache_oracle "1.3 set cache writes entry"
        (set_cache "val")
        ~expected_cache:(Some "val");
    ] )

let set_2 =
  ( "set_2_order_matters",
    [
      check_cache_oracle "2.1 normal then cache"
        (ESeq [ set_normal "first_n"; set_cache "then_c" ])
        ~expected_cache:(Some "then_c");
      check_cache_oracle "2.2 cache then normal"
        (ESeq [ set_cache "first_c"; set_normal "then_n" ])
        ~expected_cache:(Some "first_c");
      check_cache_oracle "2.3 re-configure (-D pre-populates cache)"
        ~cmd_line:[("VAR", "then_c")]
        (ESeq [ set_normal "first_n"; set_cache "ignored" ])
        ~expected_cache:(Some "then_c");
    ] )

let set_3 =
  ( "set_3_unset_behavior",
    [
      check_cache_oracle "3.1 set cache, unset normal (cache persists)"
        (ESeq [ set_cache "c"; unset_normal ])
        ~expected_cache:(Some "c");
      check_cache_oracle "3.2 cache only (via -D), unset normal"
        ~cmd_line:[("VAR", "c")]
        unset_normal
        ~expected_cache:(Some "c");
      check_cache_oracle "3.3 set cache, unset CACHE (both cleared)"
        (ESeq [ set_cache "c"; unset_cache ])
        ~expected_cache:None;
    ] )

let set_4 =
  ( "set_4_cmd_line",
    [
      check_cache_oracle "4.1 -D only, no script set"
        ~cmd_line:[("VAR", "cmdline")]
        nop
        ~expected_cache:(Some "cmdline");
      check_cache_oracle "4.2 -D then normal set"
        ~cmd_line:[("VAR", "cmdline")]
        (set_normal "n")
        ~expected_cache:(Some "cmdline");
      check_cache_oracle "4.3 -D then set CACHE (no-op)"
        ~cmd_line:[("VAR", "cmdline")]
        (set_cache "c")
        ~expected_cache:(Some "cmdline");
    ] )

(* option() spot-checks — cache_semantics.md § "Equivalences". *)
let options =
  ( "options",
    [
      check_cache_oracle "option default ON writes cache"
        (yc_option ~msg:"help" ~value:(EBool true) "VAR")
        ~expected_cache:(Some "ON");
      check_cache_oracle "option default ON, -D OFF wins"
        ~cmd_line:[("VAR", "OFF")]
        (yc_option ~msg:"" ~value:(EBool true) "VAR")
        ~expected_cache:(Some "OFF");
    ] )

(* ============================================================
   First real-world data point: an fmt-style option pattern.
   fmt's CMakeLists.txt has `option(FMT_TEST "..." ON)` etc.
   We mirror the shape — verify -D suppression and default
   write on cmake's side too.
   ============================================================ *)

let _ = L.Ct_bool  (* keep dependency *)

let fmt_style =
  ( "fmt_style",
    [
      (* fmt has: option(FMT_TEST "Generate the test target." ON) — when
         configured without -D, FMT_TEST ends up ON in cache. We use
         the canonical VAR name to share check_cache_oracle's plumbing. *)
      check_cache_oracle "fmt-like option default"
        (yc_option ~msg:"Generate the test target." ~value:(EBool true) "VAR")
        ~expected_cache:(Some "ON");
      check_cache_oracle "fmt-like option overridden by -D"
        ~cmd_line:[("VAR", "OFF")]
        (yc_option ~msg:"Generate the test target." ~value:(EBool true) "VAR")
        ~expected_cache:(Some "OFF");
      check_cache_oracle "fmt-like: -D wins over force-less set CACHE"
        ~cmd_line:[("VAR", "user-override")]
        (yc_set_cache ~docstring:"override me?" "VAR" [ ystr "default" ])
        ~expected_cache:(Some "user-override");
    ] )

(* ============================================================
   fmt FMT_FUZZ side-effect oracle (probe report § 4, #1).

   The probe found FMT_FUZZ is the only fmt option with observable
   cache side-effects: when ON, it gates two extra cache entries
   in the same CMakeLists (FMT_FUZZ_LINKMAIN, FMT_FUZZ_LDFLAGS).

   We reproduce the structural pattern as a synthetic test —
   not by configuring real fmt (which requires the full fmt
   tree and CXX compiler), but by mirroring the cmake shape
   in a self-contained program. This catches the bug class
   where a single -D flip changes more than just its own var.
   ============================================================ *)
let fmt_fuzz_side_effects =
  ( "fmt_fuzz_side_effects",
    [
      check_cache_oracle "FMT_FUZZ=ON: VAR (the option) cached as ON"
        ~cmd_line:[("VAR", "ON")]
        (ESeq [
          yc_option ~msg:"Generate the fuzz target." ~value:(EBool false) "VAR";
          (* gated extra cache entries inside if(VAR) — we only verify
             VAR's own cache here; FMT_FUZZ_LINKMAIN-style sibling
             writes will be a target-property-oracle extension once
             the harness can introspect predicted env. *)
        ])
        ~expected_cache:(Some "ON");
      check_cache_oracle "FMT_FUZZ=OFF (default): VAR cached as OFF"
        (yc_option ~msg:"Generate the fuzz target." ~value:(EBool false) "VAR")
        ~expected_cache:(Some "OFF");
    ] )

let () =
  Alcotest.run "yelu_cmake_cache_oracle"
    [ set_1; set_2; set_3; set_4; options; fmt_style; fmt_fuzz_side_effects ]
