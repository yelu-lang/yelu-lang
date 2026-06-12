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

   See probes/<name>/main.json for the per-project helper list.
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
    Splice PROBE_DIR/main.json helpers into SRC_DIR. Run cmake
    on vendor (SRC_DIR) and hybrid (_out/<proj>/yelu/source/).
    Diff CMakeCache.txt; exit 0 if match.

  yelu matrix PROBE_DIR
    Run hybrid for every option in main.json × {ON, OFF}.
    Reports pass/fail per cell; exit 0 if all cells match.

  yelu fmt FILE [-w]
    Format a .yc file (canonical pretty-print). Prints to stdout;
    -w rewrites FILE in place.

  yelu manifest
    Print the yc vocabulary manifest (the surface co-truth):
    one row per token — surface<TAB>class<TAB>tm-scope.

  yelu tmgrammar [-o PATH]
    Generate the VS Code TextMate grammar (yc.tmLanguage.json) from
    the manifest. Default PATH: editors/vscode/yc/syntaxes/yc.tmLanguage.json
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
  if String.equal path "." || Stdlib.Sys.file_exists path then ()
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
        (* Y14: enum-constructor shadowing is fatal (reject), not a warning. *)
        List.iter errors ~f:(function
          | Yelu_langs.Yc_wellform.Enum_shadow { name; constructor } ->
            Stdlib.Printf.eprintf
              "yelu compile: %s: variable %S shadows the %s constructor; rename it\n"
              file name constructor;
            Stdlib.exit 1
          | _ -> ());
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
   Manifest reading. JSON shape (see probes/fmt/main.json):

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
  options : string list;
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
                let name =
                  if String.is_prefix stem ~prefix:"CMakeLists"
                  then "CMakeLists.txt"
                  else if String.is_substring stem ~substring:"_"
                  then snake_to_camel stem ^ ".cmake"
                  else "CMakeLists.txt"
                in
                if String.equal dir "." then name
                else Stdlib.Filename.concat dir name
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
  let options =
    match json |> member "options" with
    | `Null -> []
    | j -> j |> to_list |> List.map ~f:to_string
  in
  let project    = json |> member "project"    |> to_string in
  let source_dir = json |> member "source_dir" |> to_string in
  let out_root   = json |> member "out_root"   |> to_string in
  { project; source_dir; out_root; cmake_flags; options; helpers }

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
   hybrid: check out source_dir via git worktree; overwrite
   target files with generated cmake; run cmake on both; diff. *)

let build_hybrid_tree ~source_dir ~yelu_root ~spliced_files =
  let source_abs = run_capture (Printf.sprintf "realpath %s" (Stdlib.Filename.quote source_dir)) |> fst |> String.strip in
  let _ = run_capture (Printf.sprintf "mkdir -p %s" (Stdlib.Filename.quote yelu_root)) in
  let yelu_abs = run_capture (Printf.sprintf "realpath %s" (Stdlib.Filename.quote yelu_root)) |> fst |> String.strip in
  (* Create worktree once; reuse on subsequent runs. A git worktree has a
     .git file (not directory) at its root — detect that to decide. *)
  let has_worktree = Stdlib.Sys.file_exists (Stdlib.Filename.concat yelu_abs ".git") in
  if not has_worktree then begin
    let _ = run_capture (Printf.sprintf "git -C %s worktree remove --force %s 2>/dev/null || true"
               (Stdlib.Filename.quote source_abs) (Stdlib.Filename.quote yelu_abs)) in
    let _ = run_capture (Printf.sprintf "git -C %s worktree prune" (Stdlib.Filename.quote source_abs)) in
    let _ = run_capture (Printf.sprintf "rm -rf %s" (Stdlib.Filename.quote yelu_abs)) in
    let cmd = Printf.sprintf "git -C %s worktree add --detach %s HEAD 2>&1"
      (Stdlib.Filename.quote source_abs) (Stdlib.Filename.quote yelu_abs) in
    let out, code = run_capture cmd in
    if code <> 0 then begin
      Stdlib.Printf.eprintf "[yelu] git worktree failed:\n%s\n" out;
      Stdlib.exit 1
    end
  end;
  (* Overwrite generated files in-place *)
  Map.iteri spliced_files ~f:(fun ~key:rel_path ~data:content ->
    let target = Stdlib.Filename.concat yelu_abs rel_path in
    mkdirp (Stdlib.Filename.dirname target);
    write_all target content)

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
let strip_cache ~build_dir ~source_dir path =
  (* Normalize paths so vendor/hybrid cache lines are comparable:
     build dirs → $BUILD_DIR, original source + worktree source → $SOURCE_DIR.
     Keeps KEY:TYPE=VALUE intact for value-level comparison. *)
  let build_abs =
    run_capture (Printf.sprintf "realpath %s" (Stdlib.Filename.quote build_dir))
    |> fst |> String.strip in
  let build_yelu_abs =
    run_capture (Printf.sprintf "realpath %s"
      (Stdlib.Filename.quote
         (Stdlib.Filename.concat (Stdlib.Filename.dirname build_dir) "build-yelu")))
    |> fst |> String.strip in
  let source_abs =
    run_capture (Printf.sprintf "realpath %s" (Stdlib.Filename.quote source_dir))
    |> fst |> String.strip in
  let yelu_source =
    run_capture (Printf.sprintf "realpath %s"
      (Stdlib.Filename.quote
         (Stdlib.Filename.concat (Stdlib.Filename.dirname build_dir) "source")))
    |> fst |> String.strip in
  (* Escape / for sed: s|pattern|replacement|g *)
  let sed_pat s = String.substr_replace_all s ~pattern:"/" ~with_:"\\/" in
  let cmd = Printf.sprintf
    "grep -E '^[A-Za-z_][A-Za-z0-9_]*:' %s \
     | grep -vE '^(CMAKE_|CTEST_|_CMAKE|GLOBAL_FLAGS_|PACKAGE_|CPACK_|fmt_DIR)' \
     | sed 's|%s|$BUILD_DIR|g' \
     | sed 's|%s|$BUILD_DIR|g' \
     | sed 's|%s|$SOURCE_DIR|g' \
     | sed 's|%s|$SOURCE_DIR|g' \
     | sort"
    (Stdlib.Filename.quote path)
    (sed_pat build_abs) (sed_pat build_yelu_abs)
    (sed_pat source_abs) (sed_pat yelu_source)
  in
  fst (run_capture cmd)

(* Merge manifest + cmdline flags. Cmdline wins on key conflict:
   manifest ["FMT_FUZZ=ON"] + cmdline ["FMT_FUZZ=OFF"] → ["FMT_FUZZ=OFF"]. *)
let merge_flags ~manifest ~cmdline =
  let key_of = fun s -> match String.split s ~on:'=' with k :: _ -> k | [] -> s in
  let cmdline_keys = List.map cmdline ~f:key_of |> Set.of_list (module String) in
  let manifest_only = List.filter manifest ~f:(fun f ->
    not (Set.mem cmdline_keys (key_of f))) in
  manifest_only @ cmdline

let cmd_hybrid ?(source_dir_override = None) manifest_path d_flags =
  let m = load_manifest manifest_path in
  let source_dir = Option.value source_dir_override ~default:m.source_dir in
  let d_flags = merge_flags ~manifest:m.cmake_flags ~cmdline:d_flags in

  (* Open log early so compile warnings land there via stderr redirect. *)
  let log_dir = Stdlib.Filename.concat (Stdlib.Filename.concat m.out_root "yelu") "log" in
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
  let yelu_root = Stdlib.Filename.concat m.out_root "yelu/source" in
  build_hybrid_tree ~source_dir ~yelu_root ~spliced_files;
  log "[yelu] hybrid source at %s/" yelu_root;

  (* 4. Run cmake on both. *)
  let vendor_build = Stdlib.Filename.concat m.out_root "yelu/build-cmake" in
  let hybrid_build = Stdlib.Filename.concat m.out_root "yelu/build-yelu" in
  let code_v = cmake_configure ~source_dir:source_abs ~build_dir:vendor_build ~d_flags in
  let code_h = cmake_configure ~source_dir:yelu_root ~build_dir:hybrid_build ~d_flags in
  if code_v <> 0 || code_h <> 0 then begin
    log "[yelu] cmake failed (vendor=%d hybrid=%d)" code_v code_h;
    Stdlib.close_out log_oc;
    Stdlib.exit 1
  end;
  log "[yelu] both configures done";

  (* 5. Diff caches and report. *)
  let v_cache = strip_cache ~build_dir:vendor_build ~source_dir
      (Stdlib.Filename.concat vendor_build "CMakeCache.txt") in
  let h_cache = strip_cache ~build_dir:vendor_build ~source_dir
      (Stdlib.Filename.concat hybrid_build "CMakeCache.txt") in
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

(* ============================================================
   manifest / tmgrammar (surface Milestone 0).
   Generation consumes Yc_driver.manifest — the driver is the boundary.
   Vocabulary regexes come from Yc_tmgrammar; the structure rules
   (comments, strings, ${…}/$<…>, numbers, :attrs) are the hand-written
   template here. See doc/lang/surface_lsp_framework.md Sec 3.8. *)

let default_tmgrammar_path = "editors/vscode/yc/syntaxes/yc.tmLanguage.json"

let tmgrammar_json () : Yojson.Safe.t =
  let rule ~re ~name = `Assoc [ "match", `String re; "name", `String name ] in
  (* Structure rules — order matters: comments/strings/interpolation must
     precede keywords so tokens inside them are not re-scanned; :attr must
     precede the bare-colon punctuation rule. *)
  let structure =
    [ rule ~re:"#.*$"                      ~name:"comment.line.number-sign.yc";
      rule ~re:"\"(\\\\.|[^\"\\\\])*\""    ~name:"string.quoted.double.yc";
      rule ~re:"'[^']*'"                   ~name:"string.quoted.single.yc";
      rule ~re:"\\$\\{[^}]*\\}"            ~name:"variable.other.substitution.yc";
      rule ~re:"\\$<[^>]*>"                ~name:"variable.other.genex.yc";
      rule ~re:"\\b[0-9]+\\b"              ~name:"constant.numeric.integer.yc";
      rule ~re:":[A-Za-z0-9_-]+"           ~name:"entity.other.attribute-name.yc";
    ]
  in
  let vocab =
    Yelu_langs.Yc_tmgrammar.vocabulary_rules (Yelu_langs.Yc_driver.manifest ())
    |> List.map ~f:(fun (re, name) -> rule ~re ~name)
  in
  `Assoc
    [ "name", `String "Yelu-cmake";
      "scopeName", `String "source.yc";
      "fileTypes", `List [ `String "yc" ];
      "patterns", `List (structure @ vocab) ]

let cmd_manifest () =
  List.iter (Yelu_langs.Yc_manifest.to_lines ()) ~f:Stdlib.print_endline

let cmd_tmgrammar out =
  mkdirp (Stdlib.Filename.dirname out);
  let json = Yojson.Safe.pretty_to_string (tmgrammar_json ()) in
  write_all out (json ^ "\n");
  let n = List.length (Yelu_langs.Yc_tmgrammar.vocabulary_rules
                         (Yelu_langs.Yc_driver.manifest ())) in
  Stdlib.Printf.printf "[yelu] wrote %s (%d vocabulary rules)\n%!" out n

let () =
  let args = Sys.get_argv () |> Array.to_list |> List.tl_exn in
  match args with
  | [] | ["-h"] | ["--help"] -> Stdlib.print_string usage
  | "fmt" :: rest ->
    let write = List.mem rest "-w" ~equal:String.equal in
    let files = List.filter rest ~f:(fun a -> not (String.is_prefix a ~prefix:"-")) in
    (match files with
     | [] -> Stdlib.Printf.eprintf "fmt: no input file\n"; Stdlib.exit 1
     | file :: _ when not (Stdlib.Sys.file_exists file) ->
       Stdlib.Printf.eprintf "fmt: %s: no such file\n" file; Stdlib.exit 1
     | file :: _ ->
       (match Yelu_langs.Yc_driver.format (read_all file) with
        (* parse failure → never overwrite; the formatter is fail-safe *)
        | Error e -> Stdlib.Printf.eprintf "fmt: %s: %s\n" file e; Stdlib.exit 1
        | Ok out ->
          (* [format] already terminates with exactly one newline
             (print_program's rstrip); do not add a second. *)
          if write then write_all file out else Stdlib.print_string out))
  | "manifest" :: _ -> cmd_manifest ()
  | "tmgrammar" :: rest when List.mem rest "--stdout" ~equal:String.equal ->
    (* print the grammar to stdout (for the freshness diff rule) *)
    Stdlib.print_string (Yojson.Safe.pretty_to_string (tmgrammar_json ()) ^ "\n")
  | "tmgrammar" :: rest ->
    let out =
      let rec find = function
        | "-o" :: o :: _ -> o
        | _ :: r -> find r
        | [] -> default_tmgrammar_path
      in
      find rest
    in
    cmd_tmgrammar out
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
    let manifest_path = Stdlib.Filename.concat probe_dir "main.json" in
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
  | "matrix" :: probe_dir :: _ ->
    let manifest_path = Stdlib.Filename.concat probe_dir "main.json" in
    let m = load_manifest manifest_path in
    let options = match m.options with
      | [] -> failwith "matrix: no 'options' field in main.json"
      | opts -> opts
    in
    Stdlib.Printf.printf "[yelu] matrix: %d options x {ON,OFF} = %d cells\n%!"
      (List.length options) (List.length options * 2);
    let results = ref [] in
    let exe = Stdlib.Filename.quote
      (Stdlib.Filename.concat (Stdlib.Sys.getcwd ())
         "_build/default/src/bin/yelu/yelu.exe") in
    List.iter options ~f:(fun opt ->
      List.iter ["ON"; "OFF"] ~f:(fun val_ ->
        let flag = Printf.sprintf "%s=%s" opt val_ in
        Stdlib.Printf.printf "[yelu] cell %s ... %!" flag;
        let cmd = Printf.sprintf "cd %s && %s hybrid %s -D%s 2>/dev/null"
          (Stdlib.Filename.quote (Stdlib.Sys.getcwd ()))
          exe (Stdlib.Filename.quote probe_dir) flag in
        let _out, code = run_capture cmd in
        let ok = (code = 0) in
        results := (opt, val_, ok) :: !results;
        Stdlib.Printf.printf "%s\n%!" (if ok then "OK" else "FAIL")));
    let passed = List.count !results ~f:(fun (_, _, ok) -> ok) in
    let total = List.length !results in
    let failed_cells = List.filter !results ~f:(fun (_, _, ok) -> not ok) in
    Stdlib.Printf.printf "[yelu] matrix done: %d/%d cells passed\n%!" passed total;
    if not (List.is_empty failed_cells) then begin
      Stdlib.Printf.printf "[yelu] failed cells:\n%!";
      List.iter failed_cells ~f:(fun (opt, val_, _) ->
        Stdlib.Printf.printf "  %s=%s\n" opt val_)
    end;
    if passed = total then Stdlib.exit 0 else Stdlib.exit 1
  | _ ->
    Stdlib.print_string usage;
    Stdlib.exit 1
