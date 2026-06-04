(** fmt matrix smoke — same bridge chain as test_fmt_bridge_smoke,
    but iterated across every flippable fmt option × {ON, OFF}.

    Discovers WHICH gaps in the predictor are CONFIG-DEPENDENT
    (appear in some cells but not others — the load-bearing ones)
    vs CONFIG-INDEPENDENT (appear in every cell — constant noise
    that's still a gap, but lower priority).

    Per cell (option × value):
      cmd_line   = [(opt, val)]
      Per-cell directory layout (under _out/fmt/matrix/<opt>_<val>/):
        real/                 real cmake on vendor/fmt (reference)
        ycn/                  RESERVED — future: real cmake on yelu-emitted source
        predicted_cache.txt   yc-eval predicted env.cache_vars

      After the run, _out/fmt/config.json summarizes the spec
      (options discovered, cells enumerated, dir layout) so
      downstream tools can re-derive what was tested.
      diff counts {matched, mismatched, real_only, pred_only}

    All cells share the same fmt_project_names + reserved_names —
    classifier inputs don't depend on cmd_line.

    Output: per-cell summary table + cross-cell rollups:
      - "real-only entries seen in N cells" (sorted desc)
      - "options where flipping changes the diff shape"
      - "options where flipping has no effect on diff"

    Each cell calls real cmake once (~0.5s). For 11 fmt options
    × 2 values = 22 cells, total ~11 seconds. Practical.

    Not in any dune alias. Invoke explicitly:
      dune exec test/test-runcmake/test_fmt_matrix_smoke.exe

    Regression gate: assert that the median per-cell matched count
    holds at or above the level the bridge currently achieves
    (currently 10/cell on the single-shot smoke). *)

open Base
module Cp = Yelu_langs.Cmake_text_parse
module Yc = Yelu_langs.Yelu_cmake
module Fe = Yelu_langs.Yelu_cmake_from_emit
module Convert = Yelu_langs.Yelu_cmake_convert
module If_frag = Yelu_langs.Yelu_cmake_if
open Yelu_runner

let fmt_dir       = "vendor/fmt"
let _parse_py     = "tool/cmake_roundtrip/parse.py"  (* now in Cmake_bridge *)
let reserved_path = "tool/cmake_roundtrip/cmake_reserved.tsv"
let cache_vars_exe = "_build/default/tool/cmake_roundtrip/cache_vars.exe"
let matrix_root   = "_out/fmt/matrix"

(* ============================================================
   Subprocess + parse helpers (duplicated from
   test_fmt_bridge_smoke for now; factor into a shared module
   if a third smoke shows up). *)

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

(* parse + bridge consolidated into Yelu_runner.Cmake_bridge.parse_file
   so function/macro/Apply support + ${X} substitution land in one
   place used by both the top-level parse and the include() loader. *)

(* Pre-parse fmt's CMakeLists ONCE. Same AST is reused per cell;
   only the cmd_line + cache state differ. *)
let fmt_program =
  lazy (
    match Cmake_bridge.parse_file ~path:(fmt_dir ^ "/CMakeLists.txt") with
    | Some expr -> expr
    | None ->
      failwith
        (Printf.sprintf "Cmake_bridge.parse_file failed on %s/CMakeLists.txt"
           fmt_dir))

(* ============================================================
   Per-cell runs. *)

let real_cache_for ~cmd_line ~build_dir : (string * string) list =
  let result =
    Cmake_runner.run_configure
      ~source_dir:fmt_dir
      ~build_dir
      ~cmd_line
      ""
  in
  if result.run.exit_code <> 0 then begin
    Stdlib.Printf.eprintf "[matrix] real cmake exit %d for cmd_line=%s\n%s\n"
      result.run.exit_code
      (String.concat ~sep:" "
         (List.map cmd_line ~f:(fun (k, v) -> "-D" ^ k ^ "=" ^ v)))
      result.run.stderr;
    []
  end else
    result.cache

let predicted_cache_for ~cmd_line : (string * string) list =
  let prog = Lazy.force fmt_program in
  let initial_env =
    let env = Yc.empty_env in
    (* See test_fmt_bridge_smoke for the cmake-defaults rationale. *)
    let defaults =
      [ "CMAKE_CURRENT_LIST_DIR", fmt_dir;
        "CMAKE_CURRENT_SOURCE_DIR", fmt_dir;
        "CMAKE_INSTALL_PREFIX", "/usr/local";
        "CMAKE_SOURCE_DIR", fmt_dir;
        "CMAKE_BINARY_DIR", "/tmp/cmake_predict";
      ]
    in
    let env =
      List.fold defaults ~init:env ~f:(fun env (k, v) ->
        Yc.set_var env ~key:k ~data:(Yc.VString v))
    in
    { env with
      include_loader = Some Cmake_bridge.loader;
      subdir_loader = Some Cmake_bridge.subdir_loader }
  in
  let env, _ = Convert.eval_yelu_cmake_expr ~cmd_line initial_env prog in
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
   Diff (Project + Unknown tiers only, per cache_var_namespacing.md). *)

type cell_result = {
  option : string;
  value : string;
  cell_dir : string;       (* _out/fmt/matrix/<option>_<value>/ *)
  ref_build_dir : string;  (* <cell_dir>/real — real cmake on vendor/fmt *)
  ycn_build_dir : string;  (* <cell_dir>/ycn — RESERVED for future *)
  matched : int;
  mismatched : (string * string * string) list;  (* name, real, pred *)
  real_only : (string * string) list;             (* name, real *)
  pred_only : (string * string) list;             (* name, pred *)
}

let diff ~real ~predicted ~project ~reserved =
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
       | Some r, Some p -> mismatched := (name, r, p) :: !mismatched
       | Some r, None -> real_only := (name, r) :: !real_only
       | None, Some p -> pred_only := (name, p) :: !pred_only
       | None, None -> ()));
  (!matched, !mismatched, !real_only, !pred_only)

(* ============================================================
   Driver. *)

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

(* Determine which options are flippable. Pull from cache_vars.exe
   output — column 2 is the kind (OPTION / BOOL / STRING / …).
   OPTION + BOOL get ON/OFF; STRING gets <empty>/<a-value> later
   if useful (skip for first cut). *)
type opt_decl = {
  name : string;
  kind : string;
  default : string; [@warning "-69"]
}

let load_fmt_options () : opt_decl list =
  let cmd =
    Printf.sprintf "%s %s 2>/dev/null"
      (Stdlib.Filename.quote cache_vars_exe)
      (Stdlib.Filename.quote fmt_dir)
  in
  let out = run_capture cmd in
  String.split_lines out
  |> List.filter_map ~f:(fun line ->
       match String.split line ~on:'\t' with
       | name :: kind :: default :: _
         when not (String.is_empty name) ->
         Some { name; kind; default }
       | _ -> None)
  |> List.filter ~f:(fun d ->
       String.equal d.kind "OPTION" || String.equal d.kind "BOOL")

let run_cell option value ~project ~reserved : cell_result =
  let cmd_line = [ option, value ] in
  let cell_dir = Printf.sprintf "%s/%s_%s" matrix_root option value in
  let ref_build_dir = cell_dir ^ "/real" in
  let ycn_build_dir = cell_dir ^ "/ycn" in
  let real = real_cache_for ~cmd_line ~build_dir:ref_build_dir in
  let predicted = predicted_cache_for ~cmd_line in
  let matched, mismatched, real_only, pred_only =
    diff ~real ~predicted ~project ~reserved
  in
  { option; value; cell_dir; ref_build_dir; ycn_build_dir;
    matched; mismatched; real_only; pred_only }

(* ============================================================
   Summary printers. *)

let print_per_cell_table results =
  Stdlib.Printf.printf "\n=== Per-cell summary ===\n";
  Stdlib.Printf.printf "%-25s %-4s %-7s %-8s %-9s %-9s\n"
    "Option" "Val" "match" "mismatch" "real-only" "pred-only";
  Stdlib.Printf.printf "%s\n" (String.make 70 '-');
  List.iter results ~f:(fun r ->
    Stdlib.Printf.printf "%-25s %-4s %-7d %-8d %-9d %-9d\n"
      r.option r.value r.matched
      (List.length r.mismatched)
      (List.length r.real_only)
      (List.length r.pred_only))

let print_real_only_rollup results =
  let counts =
    List.fold results ~init:(Map.empty (module String)) ~f:(fun acc r ->
      List.fold r.real_only ~init:acc ~f:(fun acc (name, _) ->
        Map.update acc name ~f:(function None -> 1 | Some n -> n + 1)))
  in
  let total = List.length results in
  let sorted =
    Map.to_alist counts
    |> List.sort ~compare:(fun (_, a) (_, b) -> Int.compare b a)
  in
  Stdlib.Printf.printf "\n=== Real-only entries by cell-count (out of %d cells) ===\n"
    total;
  List.iter sorted ~f:(fun (name, cnt) ->
    let pct = 100 * cnt / total in
    Stdlib.Printf.printf "  %3d/%d (%2d%%)  %s\n" cnt total pct name)

let print_pred_only_rollup results =
  let counts =
    List.fold results ~init:(Map.empty (module String)) ~f:(fun acc r ->
      List.fold r.pred_only ~init:acc ~f:(fun acc (name, _) ->
        Map.update acc name ~f:(function None -> 1 | Some n -> n + 1)))
  in
  if Map.is_empty counts then ()
  else begin
    let total = List.length results in
    let sorted =
      Map.to_alist counts
      |> List.sort ~compare:(fun (_, a) (_, b) -> Int.compare b a)
    in
    Stdlib.Printf.printf "\n=== Pred-only entries by cell-count (out of %d cells) ===\n"
      total;
    List.iter sorted ~f:(fun (name, cnt) ->
      let pct = 100 * cnt / total in
      let example =
        List.find_map results ~f:(fun r ->
          List.find r.pred_only ~f:(fun (n, _) -> String.equal n name))
      in
      let val_s = match example with Some (_, v) -> v | None -> "?" in
      Stdlib.Printf.printf "  %3d/%d (%2d%%)  %s = %s\n" cnt total pct name val_s)
  end

let print_mismatched_rollup results =
  let counts =
    List.fold results ~init:(Map.empty (module String)) ~f:(fun acc r ->
      List.fold r.mismatched ~init:acc ~f:(fun acc (name, _, _) ->
        Map.update acc name ~f:(function None -> 1 | Some n -> n + 1)))
  in
  if Map.is_empty counts then
    Stdlib.Printf.printf "\n=== Mismatched: none ===\n"
  else begin
    let total = List.length results in
    let sorted =
      Map.to_alist counts
      |> List.sort ~compare:(fun (_, a) (_, b) -> Int.compare b a)
    in
    Stdlib.Printf.printf "\n=== Mismatched entries by cell-count (out of %d cells) ===\n"
      total;
    List.iter sorted ~f:(fun (name, cnt) ->
      let pct = 100 * cnt / total in
      Stdlib.Printf.printf "  %3d/%d (%2d%%)  %s\n" cnt total pct name);
    (* DEBUG: show one example (real, pred) pair per mismatched name *)
    Stdlib.Printf.printf "\n=== Mismatched values (one example each) ===\n";
    List.iter sorted ~f:(fun (name, _) ->
      let example =
        List.find_map results ~f:(fun r ->
          List.find r.mismatched ~f:(fun (n, _, _) -> String.equal n name))
      in
      match example with
      | Some (_, real, pred) ->
        Stdlib.Printf.printf "  %s\n    real: %s\n    pred: %s\n" name real pred
      | None -> ())
  end

let print_option_flip_analysis results =
  (* Group by option; compare the (matched, real_only count) pair
     across the two values. Print options where flipping has an
     observable effect. *)
  let by_option =
    List.fold results ~init:(Map.empty (module String)) ~f:(fun acc r ->
      Map.update acc r.option ~f:(function
        | None -> [ r ] | Some xs -> r :: xs))
  in
  Stdlib.Printf.printf "\n=== Option flip analysis ===\n";
  Map.iteri by_option ~f:(fun ~key:opt ~data:cells ->
    let cells = List.sort cells ~compare:(fun a b ->
      String.compare a.value b.value) in
    let signature c =
      Printf.sprintf "m=%d ro=%d mm=%d po=%d"
        c.matched (List.length c.real_only)
        (List.length c.mismatched) (List.length c.pred_only)
    in
    match cells with
    | [ a; b ] ->
      if String.equal (signature a) (signature b) then
        Stdlib.Printf.printf "  [stable] %-25s %s\n" opt (signature a)
      else
        Stdlib.Printf.printf "  [FLIPS]  %-25s ON->{%s}  OFF->{%s}\n"
          opt
          (signature (if String.equal a.value "ON" then a else b))
          (signature (if String.equal a.value "OFF" then a else b))
    | _ -> Stdlib.Printf.printf "  [skip]   %-25s (only %d cells)\n"
             opt (List.length cells))

(* ============================================================
   config.json manifest.

   Generated after the matrix run; lands at _out/fmt/config.json.
   Lists what was tested:
   - source dir (vendor/fmt)
   - discovered options
   - enumerated cells with their per-cell directory layout
   - the matrix strategy currently used
   Downstream tools (e.g. a future ycn-vs-real comparator) can read
   this to re-derive the cell list without re-running cache_vars.exe.

   Simple sprintf-built JSON (no Yojson dep needed). *)
let json_escape s =
  String.concat_map s ~f:(function
    | '"' -> "\\\""
    | '\\' -> "\\\\"
    | '\n' -> "\\n"
    | '\t' -> "\\t"
    | c -> String.of_char c)

let write_config_manifest (options : opt_decl list) (results : cell_result list) : unit =
  let path = "_out/fmt/config.json" in
  Yelu_runner.Cache_serialize.mkdirp (Stdlib.Filename.dirname path);
  let buf = Buffer.create 4096 in
  let p = Buffer.add_string buf in
  p "{\n";
  p (Printf.sprintf "  \"project\": \"fmt\",\n");
  p (Printf.sprintf "  \"source_dir\": \"%s\",\n" fmt_dir);
  p (Printf.sprintf "  \"out_root\": \"_out/fmt\",\n");
  p (Printf.sprintf "  \"matrix_root\": \"%s\",\n" matrix_root);
  p (Printf.sprintf "  \"strategy\": \"flip-one-from-default\",\n");
  p "  \"strategies_supported\": [\"flip-one-from-default\"],\n";
  p "  \"per_cell_layout\": {\n";
  p "    \"real\": \"<cell_dir>/real    — real cmake on source_dir\",\n";
  p "    \"ycn\": \"<cell_dir>/ycn     — RESERVED: future cmake on yelu-emitted source\",\n";
  p "    \"pred\": \"<cell_dir>/pred.txt — yc-eval predicted cache (written separately if desired)\"\n";
  p "  },\n";
  p (Printf.sprintf "  \"options\": [\n");
  List.iteri options ~f:(fun i o ->
    let comma = if i = List.length options - 1 then "" else "," in
    p (Printf.sprintf
        "    { \"name\": \"%s\", \"kind\": \"%s\", \"default\": \"%s\" }%s\n"
        (json_escape o.name) (json_escape o.kind) (json_escape o.default) comma));
  p "  ],\n";
  p (Printf.sprintf "  \"cells\": [\n");
  List.iteri results ~f:(fun i r ->
    let comma = if i = List.length results - 1 then "" else "," in
    p "    {\n";
    p (Printf.sprintf "      \"name\": \"%s_%s\",\n" r.option r.value);
    p (Printf.sprintf "      \"cmd_line\": [{ \"key\": \"%s\", \"value\": \"%s\" }],\n"
         r.option r.value);
    p (Printf.sprintf "      \"cell_dir\": \"%s\",\n" r.cell_dir);
    p (Printf.sprintf "      \"ref_build_dir\": \"%s\",\n" r.ref_build_dir);
    p (Printf.sprintf "      \"ycn_build_dir\": \"%s\",\n" r.ycn_build_dir);
    p (Printf.sprintf "      \"result\": { \"matched\": %d, \"mismatched\": %d, \"real_only\": %d, \"pred_only\": %d }\n"
         r.matched (List.length r.mismatched)
         (List.length r.real_only) (List.length r.pred_only));
    p (Printf.sprintf "    }%s\n" comma));
  p "  ]\n";
  p "}\n";
  let oc = Stdlib.open_out path in
  Stdlib.output_string oc (Buffer.contents buf);
  Stdlib.close_out oc;
  Stdlib.Printf.printf "[matrix] wrote %s\n%!" path

(* ============================================================
   Test driver. *)

let smoke () =
  Stdlib.Printf.printf "[matrix] loading fmt options via cache_vars.exe ...\n%!";
  let options = load_fmt_options () in
  Stdlib.Printf.printf "[matrix] %d flippable options found\n" (List.length options);

  let project = fmt_project_names () in
  let reserved =
    let raw = Cache_classify.load_reserved_from_file reserved_path in
    Cache_classify.expand_placeholders ~project_name:"FMT" raw @ raw
  in
  Stdlib.Printf.printf "[matrix] project namelist %d, reserved %d\n%!"
    (List.length project) (List.length reserved);

  let cells =
    List.concat_map options ~f:(fun opt ->
      [ opt.name, "ON"; opt.name, "OFF" ])
  in
  Stdlib.Printf.printf "[matrix] running %d cells ...\n%!" (List.length cells);

  let results =
    List.map cells ~f:(fun (opt, v) ->
      Stdlib.Printf.printf "  cell %s=%s ...%!" opt v;
      let r = run_cell opt v ~project ~reserved in
      Stdlib.Printf.printf " m=%d ro=%d mm=%d\n%!"
        r.matched (List.length r.real_only) (List.length r.mismatched);
      r)
  in

  print_per_cell_table results;
  print_real_only_rollup results;
  print_pred_only_rollup results;
  print_mismatched_rollup results;
  print_option_flip_analysis results;

  write_config_manifest options results;

  (* Regression gate: median matched per cell should hold at the
     level the single-shot bridge achieves. With Day-1 from_emit
     scope, the single-shot smoke gets 10/cell; we expect the
     matrix to roughly match. Use median rather than min because
     some cells (e.g., FMT_FUZZ=ON) gate additional entries that
     would naturally bump the count up; FMT_OS=OFF may not. *)
  let matched_vals =
    List.map results ~f:(fun r -> r.matched)
    |> List.sort ~compare:Int.compare
  in
  let median =
    let n = List.length matched_vals in
    if n = 0 then 0
    else List.nth_exn matched_vals (n / 2)
  in
  Stdlib.Printf.printf "\n[matrix] median matched per cell: %d\n%!" median;
  Alcotest.(check bool)
    (Printf.sprintf "median matched >= 8 (got %d)" median)
    true (median >= 8)

let () =
  Alcotest.run "fmt_matrix_smoke"
    [ "matrix", [ Alcotest.test_case "all-cells" `Quick smoke ] ]
