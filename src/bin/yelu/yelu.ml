(* [tool-interface]
   node:     driver (orchestrates yc / cmake text / cmake binary)
   op:       compile: .yc|.ml → cmake text
             hybrid:  manifest → splice → cmake configure → diff
   strategy: code + tool:dune (.ml compile), tool:cmake (configure, hybrid)
   exports:  CLI: yelu compile FILE, yelu hybrid PROBE_DIR
   imports:  Yelu_parse (parse .yc in-process),
             Yelu_cmake_emit (emit cmake text),
             dune exec (compile .ml as subprocess),
             cmake binary (configure, diff)
   ─────────

   yelu — driver for project-level yelu-cmake adaptation.

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
    Compile a .ml or .yc source to cmake text. Stdout unless -o.

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
   .yc → in-process Yelu_parse + Yelu_cmake_emit.emit_script *)

let compile_ml file =
  let exe = String.chop_suffix_exn file ~suffix:".ml" ^ ".exe" in
  let cmd = Printf.sprintf "dune exec %s 2>&1" (Stdlib.Filename.quote exe) in
  let out, code = run_capture cmd in
  if code <> 0 then begin
    Stdlib.Printf.eprintf "yelu compile: %s failed (exit %d):\n%s\n" file code out;
    Stdlib.exit 1
  end;
  out

let compile_yc ?(wellform = true) ?(warn = fun _ -> ()) file =
  let src = read_all file in
  match Yelu_langs.Yelu_parse.parse_program_y1 src with
  | Error e ->
    Stdlib.Printf.eprintf "yelu compile: parse error in %s: %s\n" file e;
    Stdlib.exit 1
  | Ok expr ->
    if wellform then begin
      match Yelu_langs.Yc_wellform.check_all expr with
      | [] -> ()
      | errors ->
        let raw_escapes, others =
          List.partition_tf errors ~f:(function
            | Yelu_langs.Yc_wellform.Raw_cmake_escape _ -> true
            | _ -> false)
        in
        List.iteri others ~f:(fun i e ->
          warn (Printf.sprintf "[yelu][emit][warning][%d] %s"
                  i (Sexp.to_string_hum (Yelu_langs.Yc_wellform.sexp_of_error e))));
        List.iteri raw_escapes ~f:(fun i e ->
          match e with
          | Yelu_langs.Yc_wellform.Raw_cmake_escape { text; reason } ->
            warn (Yelu_langs.Yc_wellform.format_raw_escape ~index:(i + List.length others) file text reason)
          | _ -> ())
    end;
    Yelu_langs.Yelu_cmake_emit.emit_script expr

let compile ?(warn = fun _ -> ()) file =
  if String.is_suffix file ~suffix:".ml" then compile_ml file
  else if String.is_suffix file ~suffix:".yc" then compile_yc ~warn file
  else begin
    Stdlib.Printf.eprintf "yelu compile: unknown extension: %s\n" file;
    Stdlib.exit 1
  end

(* compile dispatches to compile_ml or compile_yc based on extension.
   The optional ~warn callback receives wellform warnings and re-emits
   them through the caller's logging channel (for log-file capture). *)

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
  whole_file : bool;
  anchor_start : string;
  anchor_end : string;
  anchor_end_occurrence : int;
}

type manifest = {
  project : string;
  source_dir : string;
  out_root : string;
  cmake_flags : string list;
  helpers : helper list;
}

(* Auto-discover .yc files in probe_dir. Mapping convention:
   - CMakeLists*.yc          → CMakeLists.txt
   - <snake_case>.yc         → <CamelCase>.cmake  (underscore → module)
   - anything-else.yc        → CMakeLists.txt      (default)
   All discovered helpers are whole_file: true. *)
let discover_helpers probe_dir =
  let yc_files = ref [] in
  let snake_to_camel s =
    String.split s ~on:'_' |> List.map ~f:String.capitalize |> String.concat
  in
  let rec walk dir =
    if Stdlib.Sys.file_exists dir && Stdlib.Sys.is_directory dir then begin
      let entries = Stdlib.Sys.readdir dir in
      Array.iter entries ~f:(fun name ->
        if String.equal name "." || String.equal name ".." then ()
        else
          let path = Stdlib.Filename.concat dir name in
          match Unix.lstat path with
          | exception _ -> ()
          | stat ->
            if Poly.(stat.Unix.st_kind = Unix.S_DIR) then walk path
            else if String.is_suffix name ~suffix:".yc"
                 && Poly.(stat.Unix.st_kind = Unix.S_REG) then
              let rel_from_probe =
                String.chop_prefix_exn path ~prefix:(probe_dir ^ "/") in
              let target_file =
                let base = Stdlib.Filename.basename rel_from_probe in
                let dir = Stdlib.Filename.dirname rel_from_probe in
                let stem = String.chop_suffix_exn base ~suffix:".yc" in
                if String.is_prefix stem ~prefix:"CMakeLists"
                then Stdlib.Filename.concat dir "CMakeLists.txt"
                else if String.is_substring stem ~substring:"_"
                then Stdlib.Filename.concat dir (snake_to_camel stem ^ ".cmake")
                else Stdlib.Filename.concat dir "CMakeLists.txt"
              in
              yc_files := { source = path; target_file; whole_file = true;
                            anchor_start = ""; anchor_end = "";
                            anchor_end_occurrence = 1 }
                          :: !yc_files)
    end
  in
  walk probe_dir;
  List.rev !yc_files

let load_manifest manifest_path : manifest =
  let json = Yojson.Safe.from_file manifest_path in
  let open Yojson.Safe.Util in
  let explicit_helpers =
    match json |> member "helpers" with
    | `Null -> []
    | j -> j |> to_list |> List.map ~f:(fun h ->
      let whole_file =
        h |> member "whole_file" |> to_bool_option
        |> Option.value ~default:false
      in
      let str_or_empty k =
        match h |> member k with
        | `Null -> ""
        | j -> to_string j
      in
      { source       = h |> member "source"       |> to_string;
        target_file  = h |> member "target_file"  |> to_string;
        whole_file;
        anchor_start = str_or_empty "anchor_start";
        anchor_end   = str_or_empty "anchor_end";
        anchor_end_occurrence =
          h |> member "anchor_end_occurrence" |> to_int_option
          |> Option.value ~default:1 })
  in
  let probe_dir =
    match Yojson.Safe.Util.(json |> member "probe_dir" |> to_string_option) with
    | Some d -> d
    | None -> Stdlib.Filename.dirname manifest_path
  in
  let discovered = discover_helpers probe_dir in
  let helpers = explicit_helpers @ discovered in
  let helpers = match helpers with
    | [] -> failwith "manifest: no helpers (explicit or auto-discovered .yc)"
    | hs -> hs
  in
  let cmake_flags =
    match json |> member "cmake_flags" with
    | `Null -> []
    | j -> j |> to_list |> List.map ~f:to_string
  in
  let project    = json |> member "project"    |> to_string in
  let source_dir = json |> member "source_dir" |> to_string in
  let out_root   = json |> member "out_root"   |> to_string in
  { project; source_dir; out_root; cmake_flags; helpers }

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
  (* Mirror source_dir as a tree of symlinks, except files that are
     spliced (real, with new content) and the directories above them
     (real, so the spliced descendants are reachable). Spliced files
     are keyed by relative path from source_dir, so "CMakeLists.txt"
     and "support/cmake/JoinPaths.cmake" both work. *)
  let _ = run_capture (Printf.sprintf "rm -rf %s" (Stdlib.Filename.quote hybrid_root)) in
  let source_abs = run_capture (Printf.sprintf "realpath %s" (Stdlib.Filename.quote source_dir)) |> fst |> String.strip in
  (* Set of relative paths that must be REAL directories (vs symlinks):
     every ancestor of every spliced file. *)
  let real_dirs =
    let acc = ref (Set.empty (module String)) in
    Map.iter_keys spliced_files ~f:(fun rel_path ->
      let parts = String.split rel_path ~on:'/' in
      let rec walk current = function
        | [] | [_] -> ()  (* last part is the file itself, not a dir *)
        | part :: rest ->
          let next = if String.is_empty current then part else current ^ "/" ^ part in
          acc := Set.add !acc next;
          walk next rest
      in
      walk "" parts);
    !acc
  in
  let rec mirror rel_dir =
    let src_dir =
      if String.is_empty rel_dir then source_abs
      else Stdlib.Filename.concat source_abs rel_dir
    in
    let dst_dir =
      if String.is_empty rel_dir then hybrid_root
      else Stdlib.Filename.concat hybrid_root rel_dir
    in
    mkdirp dst_dir;
    let entries = Stdlib.Sys.readdir src_dir |> Array.to_list in
    List.iter entries ~f:(fun name ->
      let rel_path =
        if String.is_empty rel_dir then name else rel_dir ^ "/" ^ name
      in
      let src = Stdlib.Filename.concat src_dir name in
      let dst = Stdlib.Filename.concat dst_dir name in
      match Map.find spliced_files rel_path with
      | Some content -> write_all dst content
      | None ->
        if Set.mem real_dirs rel_path then mirror rel_path
        else Unix.symlink src dst)
  in
  mirror ""

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

(* Merge manifest + cmdline flags. Cmdline wins on key conflict:
   manifest ["FMT_FUZZ=ON"] + cmdline ["FMT_FUZZ=OFF"] → ["FMT_FUZZ=OFF"]. *)
let merge_flags ~manifest ~cmdline =
  let key_of = fun s -> match String.split s ~on:'=' with k :: _ -> k | [] -> s in
  let manifest_keys = List.map manifest ~f:key_of |> Set.of_list (module String) in
  let cmdline_only = List.filter cmdline ~f:(fun f ->
    not (Set.mem manifest_keys (key_of f))) in
  manifest @ cmdline_only

let cmd_hybrid ?(source_dir_override = None) manifest_path d_flags =
  let m = load_manifest manifest_path in
  let source_dir = Option.value source_dir_override ~default:m.source_dir in
  let d_flags = merge_flags ~manifest:m.cmake_flags ~cmdline:d_flags in

  (* Open log early so compile warnings land there via stderr redirect. *)
  let log_dir = Stdlib.Filename.concat m.out_root "hybrid" in
  mkdirp log_dir;
  let timestamp = Unix.time () |> Int64.of_float |> Int64.to_string in
  let log_path = Stdlib.Filename.concat log_dir (Printf.sprintf "log_%s.txt" timestamp) in
  let log_oc = Stdlib.open_out log_path in
  let log fmt = Stdlib.Printf.ksprintf (fun s ->
    Stdlib.output_string log_oc s; Stdlib.output_char log_oc '\n';
    Stdlib.print_string s; Stdlib.print_char '\n') fmt
  in
  log "[yelu] manifest: project=%s source_dir=%s helpers=%d flags=%d"
    m.project source_dir (List.length m.helpers) (List.length d_flags);
  log "[yelu] log: %s" log_path;

  (* 1. Compile each helper. *)
  let compiled =
    List.map m.helpers ~f:(fun h ->
      log "[yelu] compiling %s" h.source;
      (h, compile ~warn:(fun s -> log "%s" s) h.source))
  in

  (* 2. Group by target_file; apply splices left-to-right. *)
  let source_abs = run_capture (Printf.sprintf "realpath %s" (Stdlib.Filename.quote source_dir)) |> fst |> String.strip in
  let by_target = Hashtbl.create (module String) in
  List.iter compiled ~f:(fun (h, generated) ->
    let target_path = Stdlib.Filename.concat source_abs h.target_file in
    let current =
      Hashtbl.find_or_add by_target h.target_file
        ~default:(fun () -> read_all target_path)
    in
    let new_content =
      if h.whole_file then generated
      else splice
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
  log "[yelu] hybrid source at %s/" hybrid_root;

  (* 4. Run cmake on both. *)
  let vendor_build = Stdlib.Filename.concat m.out_root "hybrid/build-vendor" in
  let hybrid_build = Stdlib.Filename.concat m.out_root "hybrid/build-hybrid" in
  let code_v = cmake_configure ~source_dir:source_abs ~build_dir:vendor_build ~d_flags in
  let code_h = cmake_configure ~source_dir:hybrid_root ~build_dir:hybrid_build ~d_flags in
  if code_v <> 0 || code_h <> 0 then begin
    log "[yelu] cmake failed (vendor=%d hybrid=%d)" code_v code_h;
    Stdlib.close_out log_oc;
    Stdlib.exit 1
  end;
  log "[yelu] both configures done";

  (* 5. Diff caches and report. *)
  let v_cache = strip_cache (Stdlib.Filename.concat vendor_build "CMakeCache.txt") in
  let h_cache = strip_cache (Stdlib.Filename.concat hybrid_build "CMakeCache.txt") in
  if String.equal v_cache h_cache then begin
    log "[yelu] caches MATCH — hybrid is semantically equivalent";
    log "[yelu] log saved: %s" log_path;
    Stdlib.close_out log_oc;
    Stdlib.exit 0
  end else begin
    (* Classify each diff line. *)
    let v_lines = String.split_lines v_cache in
    let h_lines = String.split_lines h_cache in
    let v_set = Set.of_list (module String) v_lines in
    let h_set = Set.of_list (module String) h_lines in
    let vendor_only = Set.diff v_set h_set |> Set.to_list in
    let hybrid_only = Set.diff h_set v_set |> Set.to_list in
    let is_path_entry s =
      String.is_substring s ~substring:"_out/" || String.is_substring s ~substring:"/fmt/"
      || String.is_substring s ~substring:"CMAKE_CACHEFILE_DIR"
      || String.is_substring s ~substring:"CMAKE_HOME_DIRECTORY"
      || String.is_substring s ~substring:"CMAKE_FIND_PACKAGE_REDIRECTS_DIR"
    in
    let is_non_deterministic s =
      (* cmake artifacts that vary run-to-run: try_compile results,
         LIB_DEPENDS (cmake ≥4.0), build timestamps *)
      String.is_prefix s ~prefix:"compile_result_"
      || String.is_substring s ~substring:"LIB_DEPENDS"
      || String.is_prefix s ~prefix:"CMAKE_CACHE_"
    in
    let all_diffs = vendor_only @ hybrid_only in
    let path_only, rest = List.partition_tf all_diffs ~f:is_path_entry in
    let nondet, semantic = List.partition_tf rest ~f:is_non_deterministic in
    log "[yelu] cache diff: %d entries (%d path, %d non-det, %d semantic)"
      (List.length all_diffs) (List.length path_only)
      (List.length nondet) (List.length semantic);
    if not (List.is_empty semantic) then begin
      log "[yelu] --- semantic ---";
      List.iter semantic ~f:(fun s -> log "  %s" s)
    end;
    if not (List.is_empty nondet) then begin
      log "[yelu] --- non-deterministic (expected) ---";
      List.iter nondet ~f:(fun s -> log "  %s" s)
    end;
    if not (List.is_empty path_only) then begin
      log "[yelu] --- path-only ---";
      List.iter path_only ~f:(fun s -> log "  %s" s)
    end;
    log "[yelu] log saved: %s" log_path;
    Stdlib.close_out log_oc;
    if List.is_empty semantic then Stdlib.exit 0 else Stdlib.exit 1
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
    let source_dir_override, d_flags =
      let rec collect src_acc flags = function
        | [] -> (src_acc, List.rev flags)
        | "--project" :: dir :: r -> collect (Some dir) flags r
        | "-D" :: f :: r -> collect src_acc (f :: flags) r
        | _ :: r -> collect src_acc flags r
      in
      collect None [] rest
    in
    cmd_hybrid ~source_dir_override manifest_path d_flags
  | _ ->
    Stdlib.print_string usage;
    Stdlib.exit 1
