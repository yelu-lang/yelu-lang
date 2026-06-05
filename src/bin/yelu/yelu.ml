(* yelu — driver for project-level yelu-cmake adaptation.

   Subcommands:
     compile FILE [-o OUT]            Single-file source → cmake text.
     hybrid PROBE_DIR --project DIR   Splice probe's helpers into DIR;
                                      run cmake on both vendor and
                                      hybrid; diff caches.

   See probes/<name>/manifest.json for the per-project helper list.
   Doc: doc/yelu_cmake/hybrid_strategy.md.

   Invocation:
     dune exec src/bin/yelu/yelu.exe -- compile probes/fmt/set_verbose.ml
     dune exec src/bin/yelu/yelu.exe -- hybrid probes/fmt --project vendor/fmt
*)

open Base

let usage = {|
yelu — driver for yelu-cmake probes

USAGE:
  yelu compile FILE [-o OUTPUT]
    Compile a .ml or .ye source to cmake text. Stdout unless -o.

  yelu hybrid PROBE_DIR --project SRC_DIR [-D K=V ...]
    Splice PROBE_DIR/manifest.json helpers into SRC_DIR. Run cmake
    on vendor (SRC_DIR) and hybrid (_out/<proj>/hybrid/source/).
    Diff CMakeCache.txt; exit 0 if match.
|}

(* ============================================================
   Subprocess + file helpers. *)

let read_all path =
  let ic = Stdlib.open_in path in
  let n = Stdlib.in_channel_length ic in
  let buf = Bytes.create n in
  Stdlib.really_input ic buf 0 n;
  Stdlib.close_in ic;
  Bytes.to_string buf

let write_all path content =
  let dir = Stdlib.Filename.dirname path in
  if not (Stdlib.Sys.file_exists dir) then Unix.mkdir dir 0o755;
  let oc = Stdlib.open_out path in
  Stdlib.output_string oc content;
  Stdlib.close_out oc

let rec mkdirp path =
  if Stdlib.Sys.file_exists path then ()
  else begin
    mkdirp (Stdlib.Filename.dirname path);
    Unix.mkdir path 0o755
  end

let run_capture cmd =
  let ic = Unix.open_process_in cmd in
  let buf = Buffer.create 4096 in
  let chunk = Bytes.create 4096 in
  (try
     while true do
       let n = Stdlib.input ic chunk 0 (Bytes.length chunk) in
       if n = 0 then raise Stdlib.End_of_file
       else Buffer.add_subbytes buf chunk ~pos:0 ~len:n
     done
   with Stdlib.End_of_file -> ());
  let status = Unix.close_process_in ic in
  let exit_code = match status with
    | Unix.WEXITED n -> n
    | Unix.WSIGNALED _ | Unix.WSTOPPED _ -> -1
  in
  Buffer.contents buf, exit_code

(* ============================================================
   compile: dispatch on extension.

   .ml → subprocess `dune exec <file_without_ml>.exe`
   .ye → in-process Yelu_parse + Yelu_cmake_emit.emit_script *)

let compile_ml file =
  let exe = String.chop_suffix_exn file ~suffix:".ml" ^ ".exe" in
  let cmd = Printf.sprintf "dune exec %s 2>&1" (Stdlib.Filename.quote exe) in
  let out, code = run_capture cmd in
  if code <> 0 then begin
    Stdlib.Printf.eprintf "yelu compile: %s failed (exit %d):\n%s\n" file code out;
    Stdlib.exit 1
  end;
  out

let compile_ye file =
  let src = read_all file in
  match Yelu_langs.Yelu_parse.parse_program_y1 src with
  | Error e ->
    Stdlib.Printf.eprintf "yelu compile: parse error in %s: %s\n" file e;
    Stdlib.exit 1
  | Ok expr ->
    Yelu_langs.Yelu_cmake_emit.emit_script expr

let compile file =
  if String.is_suffix file ~suffix:".ml" then compile_ml file
  else if String.is_suffix file ~suffix:".ye" then compile_ye file
  else begin
    Stdlib.Printf.eprintf "yelu compile: unknown extension: %s\n" file;
    Stdlib.exit 1
  end

(* ============================================================
   Manifest reading. JSON shape (see probes/fmt/manifest.json):

   {
     "project": "fmt",
     "source_dir": "vendor/fmt",
     "out_root": "_out/fmt",
     "helpers": [
       { "source": "probes/fmt/set_verbose.ml",
         "target_file": "CMakeLists.txt",
         "anchor_start": "function (join result_var)",
         "anchor_end": "endfunction ()",
         "anchor_end_occurrence": 2 }
     ]
   } *)

type helper = {
  source : string;
  target_file : string;
  anchor_start : string;
  anchor_end : string;
  anchor_end_occurrence : int;
}

type manifest = {
  project : string;
  source_dir : string;
  out_root : string;
  helpers : helper list;
}

let load_manifest path : manifest =
  let json = Yojson.Safe.from_file path in
  let open Yojson.Safe.Util in
  let helpers =
    json |> member "helpers" |> to_list |> List.map ~f:(fun h ->
      { source       = h |> member "source"       |> to_string;
        target_file  = h |> member "target_file"  |> to_string;
        anchor_start = h |> member "anchor_start" |> to_string;
        anchor_end   = h |> member "anchor_end"   |> to_string;
        anchor_end_occurrence =
          h |> member "anchor_end_occurrence" |> to_int_option
          |> Option.value ~default:1 })
  in
  { project    = json |> member "project"    |> to_string;
    source_dir = json |> member "source_dir" |> to_string;
    out_root   = json |> member "out_root"   |> to_string;
    helpers }

(* ============================================================
   Splice: replace anchor_start-to-Nth-anchor_end (inclusive) in
   target_file with cmake_text. Returns new content.

   Anchor matching: line CONTAINS the anchor string (trimmed). This
   tolerates leading whitespace and trailing argument differences. *)

let splice ~target_content ~anchor_start ~anchor_end ~anchor_end_occurrence
           ~replacement =
  let lines = String.split_lines target_content in
  let find_line ~from str =
    List.findi lines ~f:(fun i line ->
      i >= from && String.is_substring (String.strip line) ~substring:str)
  in
  let start_idx =
    match find_line ~from:0 anchor_start with
    | Some (i, _) -> i
    | None ->
      Stdlib.Printf.eprintf
        "yelu splice: anchor_start %S not found in target\n" anchor_start;
      Stdlib.exit 1
  in
  (* Find Nth occurrence of anchor_end at-or-after start_idx. Starting
     from start_idx (not start_idx+1) lets anchor_start == anchor_end
     with occurrence=1 mean "replace just this one line". Multi-line
     cases still work — different anchors won't both match at start_idx,
     and same-anchor with occurrence>1 still skips to later matches. *)
  let end_idx =
    let rec loop n from =
      match find_line ~from anchor_end with
      | None ->
        Stdlib.Printf.eprintf
          "yelu splice: anchor_end %S occurrence %d not found at-or-after line %d\n"
          anchor_end anchor_end_occurrence start_idx;
        Stdlib.exit 1
      | Some (i, _) ->
        if n = 1 then i else loop (n - 1) (i + 1)
    in
    loop anchor_end_occurrence start_idx
  in
  let before = List.take lines start_idx in
  let after  = List.drop lines (end_idx + 1) in
  String.concat ~sep:"\n" (before @ [replacement] @ after)

(* ============================================================
   hybrid: mirror source_dir with symlinks; splice helpers'
   cmake output into target files; run cmake on both; diff. *)

let build_hybrid_tree ~source_dir ~hybrid_root ~spliced_files =
  (* Remove old hybrid_root if present. *)
  let _ = run_capture (Printf.sprintf "rm -rf %s" (Stdlib.Filename.quote hybrid_root)) in
  mkdirp hybrid_root;
  let source_abs = run_capture (Printf.sprintf "realpath %s" (Stdlib.Filename.quote source_dir)) |> fst |> String.strip in
  let entries =
    Stdlib.Sys.readdir source_abs |> Array.to_list
  in
  List.iter entries ~f:(fun name ->
    let dst = Stdlib.Filename.concat hybrid_root name in
    match Map.find spliced_files name with
    | Some content -> write_all dst content
    | None ->
      let src = Stdlib.Filename.concat source_abs name in
      Unix.symlink src dst)

(* Run cmake -B build_dir -S source_dir with -D flags. *)
let cmake_configure ~source_dir ~build_dir ~d_flags =
  let _ = run_capture (Printf.sprintf "rm -rf %s" (Stdlib.Filename.quote build_dir)) in
  mkdirp build_dir;
  let flags = String.concat ~sep:" "
    (List.map d_flags ~f:(fun f -> "-D" ^ Stdlib.Filename.quote f))
  in
  let cmd = Printf.sprintf "cmake -B %s -S %s %s >/dev/null 2>&1"
    (Stdlib.Filename.quote build_dir)
    (Stdlib.Filename.quote source_dir)
    flags
  in
  let _, code = run_capture cmd in
  code

(* Strip cmake's reserved-name noise; keep project + unknown tier. *)
let strip_cache path =
  let cmd = Printf.sprintf
    "grep -E '^[A-Za-z_][A-Za-z0-9_]*:' %s \
     | grep -vE '^(CMAKE_|CTEST_|_CMAKE|GLOBAL_FLAGS_|PACKAGE_|CPACK_|fmt_DIR)' \
     | cut -d: -f1,3- | sort"
    (Stdlib.Filename.quote path)
  in
  fst (run_capture cmd)

let cmd_hybrid manifest_path d_flags =
  let m = load_manifest manifest_path in
  Stdlib.Printf.printf "[yelu] manifest: project=%s source_dir=%s helpers=%d\n%!"
    m.project m.source_dir (List.length m.helpers);

  (* 1. Compile each helper. *)
  let compiled =
    List.map m.helpers ~f:(fun h ->
      Stdlib.Printf.printf "[yelu] compiling %s\n%!" h.source;
      (h, compile h.source))
  in

  (* 2. Group by target_file; apply splices left-to-right. *)
  let source_abs = run_capture (Printf.sprintf "realpath %s" (Stdlib.Filename.quote m.source_dir)) |> fst |> String.strip in
  let by_target = Hashtbl.create (module String) in
  List.iter compiled ~f:(fun (h, generated) ->
    let target_path = Stdlib.Filename.concat source_abs h.target_file in
    let current =
      Hashtbl.find_or_add by_target h.target_file
        ~default:(fun () -> read_all target_path)
    in
    let new_content = splice
      ~target_content:current
      ~anchor_start:h.anchor_start
      ~anchor_end:h.anchor_end
      ~anchor_end_occurrence:h.anchor_end_occurrence
      ~replacement:generated
    in
    Hashtbl.set by_target ~key:h.target_file ~data:new_content);

  let spliced_files = Map.of_alist_exn (module String)
    (Hashtbl.to_alist by_target)
  in

  (* 3. Build hybrid source tree. *)
  let hybrid_root = Stdlib.Filename.concat m.out_root "hybrid/source" in
  build_hybrid_tree ~source_dir:m.source_dir ~hybrid_root ~spliced_files;
  Stdlib.Printf.printf "[yelu] hybrid source at %s/\n%!" hybrid_root;

  (* 4. Run cmake on both. *)
  let vendor_build = Stdlib.Filename.concat m.out_root "hybrid/build-vendor" in
  let hybrid_build = Stdlib.Filename.concat m.out_root "hybrid/build-hybrid" in
  let code_v = cmake_configure ~source_dir:source_abs ~build_dir:vendor_build ~d_flags in
  let code_h = cmake_configure ~source_dir:hybrid_root ~build_dir:hybrid_build ~d_flags in
  if code_v <> 0 || code_h <> 0 then begin
    Stdlib.Printf.eprintf "[yelu] cmake failed (vendor=%d hybrid=%d)\n" code_v code_h;
    Stdlib.exit 1
  end;
  Stdlib.Printf.printf "[yelu] both configures done\n%!";

  (* 5. Diff. *)
  let v_cache = strip_cache (Stdlib.Filename.concat vendor_build "CMakeCache.txt") in
  let h_cache = strip_cache (Stdlib.Filename.concat hybrid_build "CMakeCache.txt") in
  if String.equal v_cache h_cache then begin
    Stdlib.Printf.printf "[yelu] caches MATCH — hybrid is semantically equivalent\n%!";
    Stdlib.exit 0
  end else begin
    Stdlib.Printf.printf "[yelu] caches DIVERGE:\n%!";
    let diff_cmd = Printf.sprintf "diff <(echo %s) <(echo %s) | head -40"
      (Stdlib.Filename.quote v_cache) (Stdlib.Filename.quote h_cache)
    in
    let out, _ = run_capture (Printf.sprintf "bash -c %s" (Stdlib.Filename.quote diff_cmd)) in
    Stdlib.print_string out;
    Stdlib.exit 1
  end

(* ============================================================
   Arg dispatch. *)

let () =
  let args = Sys.get_argv () |> Array.to_list |> List.tl_exn in
  match args with
  | [] | ["-h"] | ["--help"] -> Stdlib.print_string usage
  | "compile" :: file :: rest ->
    let out =
      let rec find = function
        | [] -> None
        | "-o" :: o :: _ -> Some o
        | _ :: rest -> find rest
      in
      find rest
    in
    let cmake_text = compile file in
    (match out with
     | None -> Stdlib.print_string cmake_text
     | Some path -> write_all path cmake_text)
  | "hybrid" :: probe_dir :: rest ->
    let manifest_path = Stdlib.Filename.concat probe_dir "manifest.json" in
    let d_flags =
      let rec collect = function
        | [] -> []
        | "-D" :: f :: rest -> f :: collect rest
        | _ :: rest -> collect rest
      in
      collect rest
    in
    cmd_hybrid manifest_path d_flags
  | _ ->
    Stdlib.print_string usage;
    Stdlib.exit 1
