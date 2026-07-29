(** nlohmann/json matrix smoke — the evaluator-channel counterpart to the
    three-channel hybrid matrix (`yelu matrix probes/json`, 18/18).

    Structure mirrors [test_fmt_matrix_smoke] exactly, with json's names:
    for every flippable json option × {ON, OFF}, run

      real cmake on vendor/json                (reference cache)
      Yelu_cmake evaluator on the parsed root  (predicted cache)

    and diff the Project + Unknown cache tiers. The point is *not* to be
    green — it is to separate CONFIG-DEPENDENT predictor gaps (present in
    some cells only — the load-bearing ones) from CONFIG-INDEPENDENT ones
    (present in every cell — constant noise, lower priority).

    Complements, does not replace, the hybrid matrix:
      - hybrid matrix  = vanilla cmake vs *yelu-emitted cmake*, real cmake
                         both sides, cache + codemodel-v2 + ctest channels.
                         That is the probe's definition-of-done oracle.
      - this smoke     = vanilla cmake vs the *in-process evaluator*, cache
                         only. Measures how far the evaluator gets on json.

    Per-cell directory layout (under _out/json/matrix/<opt>_<val>/):
      real/        real cmake on vendor/json (reference)

    Not in any dune alias (needs cmake + the vendor tree). Invoke explicitly:
      dune exec test/test-runcmake/test_json_matrix_smoke.exe

    Regression gate: the median per-cell matched count must not regress below
    the level recorded when this smoke was written (see [median_floor]). *)

open Base
module Yc = Yelu_langs.Yelu_cmake
module Convert = Yelu_langs.Yelu_cmake_convert
open Yelu_runner

let json_dir      = "vendor/json"
let reserved_path = "tool/cmake_text/cmake_reserved_vars.tsv"
let cache_vars_exe = "_build/default/tool/cmake_text/cmake_cache_scan.exe"
let matrix_root   = "_out/json/matrix"

(* The floor the evaluator channel reached on json when this file landed.
   Raise it when the evaluator improves; never lower it silently. *)
let median_floor = 11

(* ============================================================
   Subprocess helpers (same shape as test_fmt_matrix_smoke). *)

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

(* Parse json's root CMakeLists ONCE; the same AST is reused per cell —
   only the cmd_line + cache state differ. *)
let json_program =
  lazy (
    match Cmake_bridge.parse_file ~path:(json_dir ^ "/CMakeLists.txt") with
    | Some expr -> expr
    | None ->
      failwith
        (Printf.sprintf "Cmake_bridge.parse_file failed on %s/CMakeLists.txt"
           json_dir))

(* ============================================================
   Per-cell runs. *)

let real_cache_for ~cmd_line ~build_dir : (string * string) list =
  let result =
    Cmake_runner.run_configure
      ~source_dir:json_dir
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
  let prog = Lazy.force json_program in
  let initial_env =
    let env = Yc.empty_env in
    (* Same cmake-defaults rationale as the fmt smoke: the evaluator has no
       cmake bootstrap, so the handful of paths json's root reads must be
       seeded. CMAKE_CURRENT_SOURCE_DIR = CMAKE_SOURCE_DIR is what makes
       MAIN_PROJECT resolve ON, as in a top-level configure. *)
    let defaults =
      [ "CMAKE_CURRENT_LIST_DIR", json_dir;
        "CMAKE_CURRENT_SOURCE_DIR", json_dir;
        "CMAKE_INSTALL_PREFIX", "/usr/local";
        "CMAKE_SOURCE_DIR", json_dir;
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
    match Cache_classify.classify ~project ~reserved name with
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

let cache_scan () : string list =
  let cmd =
    Printf.sprintf "%s %s 2>/dev/null"
      (Stdlib.Filename.quote cache_vars_exe)
      (Stdlib.Filename.quote json_dir)
  in
  String.split_lines (run_capture cmd)

let json_project_names () : string list =
  cache_scan ()
  |> List.filter_map ~f:(fun line ->
       match String.lsplit2 line ~on:'\t' with
       | Some (name, _) when not (String.is_empty name) -> Some name
       | _ -> None)

type opt_decl = {
  name : string;
  kind : string;
  default : string; [@warning "-69"]
}

(* json holds JSON_BuildTests / JSON_CI out of the matrix: both pull a
   subdirectory (tests/, ci.cmake) that the root-only first pass does not
   translate — see probes/json/migration_status.md § Scope. *)
let held_out = [ "JSON_BuildTests"; "JSON_CI" ]

let load_json_options () : opt_decl list =
  cache_scan ()
  |> List.filter_map ~f:(fun line ->
       match String.split line ~on:'\t' with
       | name :: kind :: default :: _ when not (String.is_empty name) ->
         Some { name; kind; default }
       | _ -> None)
  |> List.filter ~f:(fun d ->
       (String.equal d.kind "OPTION" || String.equal d.kind "BOOL")
       && not (List.mem held_out d.name ~equal:String.equal))

let run_cell option value ~project ~reserved : cell_result =
  let cmd_line = [ option, value ] in
  let cell_dir = Printf.sprintf "%s/%s_%s" matrix_root option value in
  let real = real_cache_for ~cmd_line ~build_dir:(cell_dir ^ "/real") in
  let predicted = predicted_cache_for ~cmd_line in
  let matched, mismatched, real_only, pred_only =
    diff ~real ~predicted ~project ~reserved
  in
  { option; value; matched; mismatched; real_only; pred_only }

(* ============================================================
   Summary printers. *)

let print_per_cell_table results =
  Stdlib.Printf.printf "\n=== Per-cell summary ===\n";
  Stdlib.Printf.printf "%-38s %-4s %-7s %-8s %-9s %-9s\n"
    "Option" "Val" "match" "mismatch" "real-only" "pred-only";
  Stdlib.Printf.printf "%s\n" (String.make 82 '-');
  List.iter results ~f:(fun r ->
    Stdlib.Printf.printf "%-38s %-4s %-7d %-8d %-9d %-9d\n"
      r.option r.value r.matched
      (List.length r.mismatched)
      (List.length r.real_only)
      (List.length r.pred_only))

let rollup ~title ~key results =
  let counts =
    List.fold results ~init:(Map.empty (module String)) ~f:(fun acc r ->
      List.fold (key r) ~init:acc ~f:(fun acc name ->
        Map.update acc name ~f:(function None -> 1 | Some n -> n + 1)))
  in
  let total = List.length results in
  if Map.is_empty counts then
    Stdlib.Printf.printf "\n=== %s: none ===\n" title
  else begin
    Stdlib.Printf.printf "\n=== %s by cell-count (out of %d cells) ===\n"
      title total;
    Map.to_alist counts
    |> List.sort ~compare:(fun (_, a) (_, b) -> Int.compare b a)
    |> List.iter ~f:(fun (name, cnt) ->
         Stdlib.Printf.printf "  %3d/%d (%2d%%)  %s\n"
           cnt total (100 * cnt / total) name)
  end

let print_mismatched_examples results =
  let seen = Hashtbl.create (module String) in
  List.iter results ~f:(fun r ->
    List.iter r.mismatched ~f:(fun (name, real, pred) ->
      if not (Hashtbl.mem seen name) then begin
        Hashtbl.set seen ~key:name ~data:();
        Stdlib.Printf.printf "  %s\n    real: %s\n    pred: %s\n" name real pred
      end));
  if Hashtbl.is_empty seen then Stdlib.Printf.printf "  (none)\n"

let print_option_flip_analysis results =
  let by_option =
    List.fold results ~init:(Map.empty (module String)) ~f:(fun acc r ->
      Map.update acc r.option ~f:(function None -> [ r ] | Some xs -> r :: xs))
  in
  Stdlib.Printf.printf "\n=== Option flip analysis ===\n";
  Map.iteri by_option ~f:(fun ~key:opt ~data:cells ->
    let cells =
      List.sort cells ~compare:(fun a b -> String.compare a.value b.value)
    in
    let signature c =
      Printf.sprintf "m=%d ro=%d mm=%d po=%d"
        c.matched (List.length c.real_only)
        (List.length c.mismatched) (List.length c.pred_only)
    in
    match cells with
    | [ a; b ] ->
      if String.equal (signature a) (signature b) then
        Stdlib.Printf.printf "  [stable] %-38s %s\n" opt (signature a)
      else
        Stdlib.Printf.printf "  [FLIPS]  %-38s ON->{%s}  OFF->{%s}\n"
          opt
          (signature (if String.equal a.value "ON" then a else b))
          (signature (if String.equal a.value "OFF" then a else b))
    | _ ->
      Stdlib.Printf.printf "  [skip]   %-38s (only %d cells)\n"
        opt (List.length cells))

(* ============================================================
   Test driver. *)

let smoke () =
  Stdlib.Printf.printf "[matrix] loading json options via cache_scan ...\n%!";
  let options = load_json_options () in
  Stdlib.Printf.printf "[matrix] %d flippable options (held out: %s)\n"
    (List.length options) (String.concat ~sep:", " held_out);

  let project = json_project_names () in
  let reserved =
    let raw = Cache_classify.load_reserved_from_file reserved_path in
    Cache_classify.expand_placeholders ~project_name:"nlohmann_json" raw @ raw
  in
  Stdlib.Printf.printf "[matrix] project namelist %d, reserved %d\n%!"
    (List.length project) (List.length reserved);

  let cells =
    List.concat_map options ~f:(fun opt -> [ opt.name, "ON"; opt.name, "OFF" ])
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
  rollup ~title:"Real-only entries" results
    ~key:(fun r -> List.map r.real_only ~f:fst);
  rollup ~title:"Pred-only entries" results
    ~key:(fun r -> List.map r.pred_only ~f:fst);
  rollup ~title:"Mismatched entries" results
    ~key:(fun r -> List.map r.mismatched ~f:(fun (n, _, _) -> n));
  Stdlib.Printf.printf "\n=== Mismatched values (one example each) ===\n";
  print_mismatched_examples results;
  print_option_flip_analysis results;

  let matched_vals =
    List.map results ~f:(fun r -> r.matched) |> List.sort ~compare:Int.compare
  in
  let median =
    let n = List.length matched_vals in
    if n = 0 then 0 else List.nth_exn matched_vals (n / 2)
  in
  Stdlib.Printf.printf "\n[matrix] median matched per cell: %d (floor %d)\n%!"
    median median_floor;
  Alcotest.(check bool)
    (Printf.sprintf "median matched >= %d (got %d)" median_floor median)
    true (median >= median_floor)

let () =
  Alcotest.run "json_matrix_smoke"
    [ "matrix", [ Alcotest.test_case "all-cells" `Quick smoke ] ]
