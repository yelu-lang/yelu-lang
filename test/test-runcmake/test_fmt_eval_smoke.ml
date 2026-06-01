(* Integration smoke test for two Phase 1 changes:
   - [run_configure] now takes [?source_dir] / [?build_dir] so we can drive
     an existing project (fmt) into a chosen build dir without synthetic tmp dirs.
   - [Cache_serialize.write_predicted_cache] writes [env.cache_vars] to disk
     in a CMakeCache.txt-comparable shape.

   This test exercises both end-to-end on a single fmt configure with
   FMT_TEST=OFF FMT_FUZZ=ON: real cmake configure (Task A), yc-eval predicted
   cache (Task B), and ycn-eval predicted cache (Task B via to_normal).
   Outputs land under /tmp/fmt_eval_scaffold/ for inspection.

   Not wired into a dune alias yet — run with
     dune exec test/test-runcmake/test_fmt_eval_smoke.exe
*)

open Yelu_langs.Yelu_cmake
open Yelu_langs.Yelu_cmake_utils
open Yelu_langs.Yelu_cmake_convert
open Yelu_runner.Cmake_runner
module Cs = Yelu_runner.Cache_serialize

let source_dir = "/home/red/code/contrib/fmt-all/fmt"
let build_dir  = "/tmp/fmt_eval_scaffold/build_FMT_TEST_OFF_FMT_FUZZ_ON"
let yc_pred    = build_dir ^ ".yc/predicted_cache.txt"
let ycn_pred   = build_dir ^ ".ycn/predicted_cache.txt"
let cmd_line   = [ ("FMT_TEST", "OFF"); ("FMT_FUZZ", "ON") ]

let prog =
  ESeq [
    yc_set_cache "FMT_TEST" [ ystr "OFF" ];
    yc_set_cache "FMT_FUZZ" [ ystr "ON" ];
  ]

let pp_cache_entry name value =
  Printf.sprintf "  %s = %s" name value

let () =
  Printf.printf "== Task A: run_configure with explicit source/build dirs ==\n%!";
  Printf.printf "  source_dir = %s\n" source_dir;
  Printf.printf "  build_dir  = %s\n%!" build_dir;
  let result =
    run_configure ~source_dir ~build_dir ~cmd_line ""
  in
  Printf.printf "  cmake exit = %d\n%!" result.run.exit_code;
  if result.run.exit_code <> 0 then begin
    Printf.printf "  stderr:\n%s\n" result.run.stderr;
    exit 1
  end;
  let cache_path = Filename.concat build_dir "CMakeCache.txt" in
  Printf.printf "  CMakeCache.txt exists = %b\n" (Sys.file_exists cache_path);
  let fmt_test_real = List.assoc_opt "FMT_TEST" result.cache in
  let fmt_fuzz_real = List.assoc_opt "FMT_FUZZ" result.cache in
  Printf.printf "  real FMT_TEST = %s\n"
    (Option.value fmt_test_real ~default:"<absent>");
  Printf.printf "  real FMT_FUZZ = %s\n%!"
    (Option.value fmt_fuzz_real ~default:"<absent>");

  Printf.printf "\n== Task B-yc: eval yc-form, serialize predicted cache ==\n%!";
  let (env_yc, _v_yc) = eval_yelu_cmake_expr empty_env prog in
  Cs.write_predicted_cache ~env:env_yc ~path:yc_pred;
  Printf.printf "  wrote %s (exists=%b)\n%!" yc_pred (Sys.file_exists yc_pred);

  Printf.printf "\n== Task B-ycn: eval ycn-form, serialize predicted cache ==\n%!";
  let (env_ycn, _v_ycn) = eval_yelu_cmake_normal_expr empty_env (to_normal prog) in
  Cs.write_predicted_cache ~env:env_ycn ~path:ycn_pred;
  Printf.printf "  wrote %s (exists=%b)\n%!" ycn_pred (Sys.file_exists ycn_pred);

  Printf.printf "\n== 3-way diff: FMT_TEST / FMT_FUZZ across real / yc / ycn ==\n%!";
  let read_pred path =
    if not (Sys.file_exists path) then []
    else begin
      let ic = open_in path in
      let entries = ref [] in
      (try
        while true do
          let line = input_line ic in
          let line = String.trim line in
          if line <> "" && line.[0] <> '#' then
            match String.index_opt line '=' with
            | None -> ()
            | Some eq ->
              let name = String.sub line 0 eq in
              let value = String.sub line (eq + 1) (String.length line - eq - 1) in
              entries := (name, value) :: !entries
        done
      with End_of_file -> ());
      close_in ic;
      List.rev !entries
    end
  in
  let yc_entries = read_pred yc_pred in
  let ycn_entries = read_pred ycn_pred in
  let get name lst = Option.value (List.assoc_opt name lst) ~default:"<absent>" in
  Printf.printf "  FMT_TEST  real=%s  yc=%s  ycn=%s\n"
    (Option.value fmt_test_real ~default:"<absent>")
    (get "FMT_TEST" yc_entries)
    (get "FMT_TEST" ycn_entries);
  Printf.printf "  FMT_FUZZ  real=%s  yc=%s  ycn=%s\n%!"
    (Option.value fmt_fuzz_real ~default:"<absent>")
    (get "FMT_FUZZ" yc_entries)
    (get "FMT_FUZZ" ycn_entries);

  Printf.printf "\n== predicted-cache contents (yc) ==\n";
  List.iter (fun (n, v) -> print_endline (pp_cache_entry n v)) yc_entries;
  Printf.printf "\n== predicted-cache contents (ycn) ==\n";
  List.iter (fun (n, v) -> print_endline (pp_cache_entry n v)) ycn_entries;

  Printf.printf "\n== real CMakeCache.txt: top 30 entries (for housekeeping survey) ==\n";
  let rec take n = function
    | [] -> []
    | _ when n = 0 -> []
    | x :: xs -> x :: take (n - 1) xs
  in
  List.iter (fun (n, v) -> print_endline (pp_cache_entry n v))
    (take 30 result.cache);
  Printf.printf "  (real cache total entries: %d)\n" (List.length result.cache);

  let ok =
    fmt_test_real = Some "OFF"
    && fmt_fuzz_real = Some "ON"
    && get "FMT_TEST" yc_entries = "OFF"
    && get "FMT_FUZZ" yc_entries = "ON"
    && get "FMT_TEST" ycn_entries = "OFF"
    && get "FMT_FUZZ" ycn_entries = "ON"
  in
  Printf.printf "\n== overall ok = %b ==\n" ok;
  if not ok then exit 2
