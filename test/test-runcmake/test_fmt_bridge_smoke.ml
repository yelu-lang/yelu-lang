(** fmt bridge smoke — the first end-to-end run of the chain:

      fmt/CMakeLists.txt
        ↓ parse.py (subprocess)
      JSON CST
        ↓ Cmake_text_parse.file_of_json
      Stage-1 untyped AST
        ↓ stmt_to_yelu (this file): per-Cmd parse_cmd → from_emit
      yelu_cmake.expr (top-level ESeq)
        ↓ eval_yelu_cmake_expr ~cmd_line:[("FMT_FUZZ", "ON")]
      env.cache_vars
        ↓ Cache_serialize.write_predicted_cache
      _out/fmt/bridge_smoke/build_<args>.yc/predicted_cache.txt

    Compared against real cmake's CMakeCache.txt for the same
    -D flags (via run_configure ~source_dir ~build_dir ~cmd_line).
    The diff is filtered through Cache_classify so we surface
    only Project + Unknown tier names — cmake's ~150 housekeeping
    entries (CMAKE_*, CTEST_*, …) get dropped.

    Doesn't ASSERT a specific match yet — the bridge is still
    Day-1 scope (the from_emit module only models a handful of
    commands). This smoke is the gap-discovery harness: it runs
    end-to-end and prints the residual diff so we know which
    next-tier commands to add to from_emit.

    Not attached to any dune alias. Invoke explicitly:
      dune exec test/test-runcmake/test_fmt_bridge_smoke.exe *)

open Base
module Cp = Yelu_langs.Cmake_text_parse
module Yc = Yelu_langs.Yelu_cmake
module Fe = Yelu_langs.Yelu_cmake_from_emit
module Convert = Yelu_langs.Yelu_cmake_convert
module If_frag = Yelu_langs.Yelu_cmake_if
open Yelu_runner

(* ============================================================
   Inputs (paths). The smoke test pins fmt's clone path and
   the tool/snapshot locations relative to project root. *)

let fmt_dir       = "vendor/fmt"
let _parse_py      = "tool/cmake_text/parse.py"  (* now in Cmake_bridge *)
let reserved_path = "tool/cmake_text/cmake_reserved.tsv"
let cache_vars_exe = "_build/default/tool/cmake_text/cache_vars.exe"

let cmd_line = [ "FMT_FUZZ", "ON"; "FMT_TEST", "OFF" ]

(* Single sanitized label used for the build_<args> directory name. *)
let cmd_line_label =
  cmd_line
  |> List.map ~f:(fun (k, v) -> k ^ "_" ^ v)
  |> String.concat ~sep:"_"

let smoke_root = "_out/fmt/bridge_smoke"
let real_build_dir = smoke_root ^ "/build_" ^ cmd_line_label
let yc_predict_dir = real_build_dir ^ ".yc"

(* ============================================================
   Subprocess helpers. *)

let read_all ic =
  let buf = Buffer.create 4096 in
  let chunk = Bytes.create 4096 in
  (try
     while true do
       let n = Stdlib.input ic chunk 0 (Bytes.length chunk) in
       if n = 0 then raise Stdlib.End_of_file
       else Buffer.add_subbytes buf chunk ~pos:0 ~len:n
     done
   with Stdlib.End_of_file -> ());
  Buffer.contents buf

let run_capture cmd =
  let ic = Unix.open_process_in cmd in
  let out = read_all ic in
  let _ = Unix.close_process_in ic in
  out

(* parse_cmake_file + stmts_to_yelu were inlined here in earlier
   commits. Now consolidated into Yelu_runner.Cmake_bridge.parse_file
   so the same logic (with function/macro/Apply support, ${X}
   substitution, etc.) is used by both the top-level test parse and
   the include() loader. *)

(* ============================================================
   Run real cmake against fmt with the cmd_line flags;
   parse its CMakeCache.txt for the actual cache. *)

let real_cache () : (string * string) list =
  Stdlib.Printf.printf "[smoke] real cmake -S %s -B %s -D%s ...\n%!"
    fmt_dir real_build_dir
    (String.concat ~sep:" -D"
       (List.map cmd_line ~f:(fun (k, v) -> k ^ "=" ^ v)));
  let result =
    Cmake_runner.run_configure
      ~source_dir:fmt_dir
      ~build_dir:real_build_dir
      ~cmd_line
      ""
  in
  if result.run.exit_code <> 0 then
    Alcotest.failf "real cmake exit %d\nstderr:\n%s"
      result.run.exit_code result.run.stderr;
  result.cache

(* Run yc-eval on the bridged program; capture predicted cache_vars.
   The env is pre-populated with:
   - CMAKE_CURRENT_LIST_DIR set to fmt_dir (for resolving relative
     includes like the project-local support/cmake/JoinPaths.cmake)
   - include_loader set to Yelu_runner.Cmake_bridge.loader (so
     include(GNUInstallDirs) etc. actually loads the module file). *)
let predicted_cache () : (string * string) list =
  let cmake_file = fmt_dir ^ "/CMakeLists.txt" in
  Stdlib.Printf.printf "[smoke] parse %s + bridge + eval ...\n%!" cmake_file;
  let prog =
    match Cmake_bridge.parse_file ~path:cmake_file with
    | Some expr -> expr
    | None -> Alcotest.failf "Cmake_bridge.parse_file failed on %s" cmake_file
  in
  let initial_env =
    let env = Yc.empty_env in
    (* Pre-populate cmake's most common auto-detected defaults.
       cmake itself sets these during configure; our predictor
       doesn't simulate the autodetect machinery. Each one is
       a real-only / mismatched diff entry until populated.
       Future: factor into a Yelu_runner.Cmake_defaults module
       keyed by host OS + cmake version. *)
    let defaults =
      [ "CMAKE_CURRENT_LIST_DIR", fmt_dir;
        "CMAKE_INSTALL_PREFIX", "/usr/local";
        "CMAKE_SOURCE_DIR", fmt_dir;
        "CMAKE_BINARY_DIR", "/tmp/cmake_predict";
      ]
    in
    let env =
      List.fold defaults ~init:env ~f:(fun env (k, v) ->
        Yc.set_var env ~key:k ~data:(Yc.VString v))
    in
    { env with include_loader = Some Cmake_bridge.loader }
  in
  let env, _ =
    Convert.eval_yelu_cmake_expr ~cmd_line initial_env prog
  in
  Cache_serialize.write_predicted_cache
    ~env ~path:(yc_predict_dir ^ "/predicted_cache.txt");
  (* Convert env.cache_vars to (name, string) for comparison. *)
  Map.to_alist env.cache_vars
  |> List.map ~f:(fun (k, v) ->
       let s = match v with
         | Yc.VString s -> s
         | Yc.VBool true -> "ON"
         | Yc.VBool false -> "OFF"
         | Yc.VInt n -> Int.to_string n
         | _ -> "<non-string>"
       in
       (k, s))

(* ============================================================
   Project name list: invoke cache_vars.exe to get the static
   enumerator's output for fmt. *)

let fmt_project_names () : string list =
  let cmd =
    Printf.sprintf "%s %s 2>/dev/null"
      (Stdlib.Filename.quote cache_vars_exe)
      (Stdlib.Filename.quote fmt_dir)
  in
  let out = run_capture cmd in
  String.split_lines out
  |> List.filter_map ~f:(fun line ->
       match String.lsplit2 line ~on:'\t' with
       | Some (name, _) when not (String.is_empty name) -> Some name
       | _ -> None)

(* ============================================================
   Diff: real cache vs predicted, filtered through the classifier. *)

let diff_caches ~real ~predicted ~project ~reserved =
  let real_set = Map.of_alist_exn (module String) real in
  let pred_set = Map.of_alist_exn (module String) predicted in
  let all_names =
    Set.union
      (Set.of_list (module String) (Map.keys real_set))
      (Set.of_list (module String) (Map.keys pred_set))
  in
  let real_only = ref [] in
  let pred_only = ref [] in
  let mismatched = ref [] in
  let matched = ref 0 in
  Set.iter all_names ~f:(fun name ->
    let tier = Cache_classify.classify ~project ~reserved name in
    match tier with
    | Reserved_cmake | Reserved_build -> ()
    | Project | Unknown ->
      (match Map.find real_set name, Map.find pred_set name with
       | Some r, Some p when String.equal r p -> Int.incr matched
       | Some r, Some p -> mismatched := (name, tier, r, p) :: !mismatched
       | Some r, None -> real_only := (name, tier, r) :: !real_only
       | None, Some p -> pred_only := (name, tier, p) :: !pred_only
       | None, None -> ()));
  !matched, !mismatched, !real_only, !pred_only

let tier_label = function
  | Cache_classify.Project -> "project"
  | Cache_classify.Unknown -> "unknown"
  | _ -> "reserved"

(* ============================================================
   Driver. Run as a single Alcotest "case" that PRINTS the diff
   summary but doesn't fail on residual gaps — bridge is Day-1
   scope. Test PASSES if both halves run cleanly; gaps are
   informational. *)

let smoke () =
  let real = real_cache () in
  let predicted = predicted_cache () in
  let project = fmt_project_names () in
  let reserved =
    let raw = Cache_classify.load_reserved_from_file reserved_path in
    Cache_classify.expand_placeholders ~project_name:"FMT" raw
    @ raw
  in
  Stdlib.Printf.printf "[smoke] real cache: %d entries\n" (List.length real);
  Stdlib.Printf.printf "[smoke] predicted: %d entries\n" (List.length predicted);
  Stdlib.Printf.printf "[smoke] project namelist: %d entries\n" (List.length project);
  Stdlib.Printf.printf "[smoke] reserved namelist: %d entries (after expansion)\n%!"
    (List.length reserved);

  let matched, mismatched, real_only, pred_only =
    diff_caches ~real ~predicted ~project ~reserved
  in

  Stdlib.Printf.printf "\n=== Project+Unknown tier diff ===\n";
  Stdlib.Printf.printf "  matched       : %d\n" matched;
  Stdlib.Printf.printf "  mismatched    : %d\n" (List.length mismatched);
  Stdlib.Printf.printf "  in real only  : %d\n" (List.length real_only);
  Stdlib.Printf.printf "  in pred only  : %d\n%!" (List.length pred_only);

  if not (List.is_empty mismatched) then begin
    Stdlib.Printf.printf "\nMismatched (real != predicted):\n";
    List.iter (List.take mismatched 20) ~f:(fun (n, t, r, p) ->
      Stdlib.Printf.printf "  [%s] %-30s real=%-20s pred=%s\n"
        (tier_label t) n r p)
  end;
  if not (List.is_empty real_only) then begin
    Stdlib.Printf.printf "\nReal-only (missing from predicted) — top 20:\n";
    List.iter (List.take real_only 20) ~f:(fun (n, t, r) ->
      Stdlib.Printf.printf "  [%s] %-30s = %s\n" (tier_label t) n r)
  end;
  if not (List.is_empty pred_only) then begin
    Stdlib.Printf.printf "\nPredicted-only (real cmake didn't write) — top 20:\n";
    List.iter (List.take pred_only 20) ~f:(fun (n, t, p) ->
      Stdlib.Printf.printf "  [%s] %-30s = %s\n" (tier_label t) n p)
  end;

  Stdlib.Printf.printf "\n[smoke] artifacts:\n";
  Stdlib.Printf.printf "  real cache   : %s/CMakeCache.txt\n" real_build_dir;
  Stdlib.Printf.printf "  predicted    : %s/predicted_cache.txt\n%!" yc_predict_dir;
  (* Regression gate: don't let a future change silently destroy
     the prediction count we currently achieve. At the time the
     bridge first landed (commit just after e9b62e8), the smoke
     produced 10 matched + 1 mismatched (FMT_MODULE — a known
     cond-parser limitation on the VERSION_GREATER_EQUAL + AND
     compound), 9 real-only, 0 pred-only. We assert matched >= 8
     to give some slack for cmake-version-driven drift while
     still catching any big regression. *)
  Alcotest.(check bool)
    (Printf.sprintf "matched >= 8 (got %d)" matched)
    true (matched >= 8);
  Alcotest.(check bool)
    (Printf.sprintf "pred-only = 0 (got %d)" (List.length pred_only))
    true (List.is_empty pred_only)

let () =
  Alcotest.run "fmt_bridge_smoke"
    [ "smoke", [ Alcotest.test_case "end-to-end" `Quick smoke ] ]
