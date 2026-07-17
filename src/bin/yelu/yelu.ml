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
  (* B1 (2026-06-21): unified parse + wellform pipeline via Yc_driver.
     Compile now goes through the CST path like fmt and the LSP, so
     [check_cst] findings (notably Function_def_typo) reach compile. The
     emit-bridge oracle (covered=194) proves the lowered expr matches the
     legacy [parse_program_y1] path byte-for-byte at emit time. *)
  match Yelu_langs.Yc_driver.parse_and_check src with
  | Error e ->
    Stdlib.Printf.eprintf "yelu compile: parse error in %s: %s\n" file e;
    Stdlib.exit 1
  | Ok { Yelu_langs.Yc_driver.expr; cst = _; findings } ->
    if wellform then begin
      match findings with
      | [] -> ()
      | errors ->
        (* Y14: enum-constructor shadowing is fatal (reject), not a warning. *)
        List.iter errors ~f:(function
          | Yelu_langs.Yc_wellform.Enum_shadow { name; constructor } ->
            Stdlib.Printf.eprintf
              "yelu compile: %s: variable %S shadows the %s constructor; rename it\n"
              file name constructor;
            Stdlib.exit 1
          | Yelu_langs.Yc_wellform.Positional_form { command } ->
            Stdlib.Printf.eprintf
              "yelu compile: %s: %s in the positional cmake-keyword form is not a \
               yc surface; use the ~label= form or yc_raw '…'\n"
              file command;
            Stdlib.exit 1
          | Yelu_langs.Yc_wellform.Unknown_command { name; closed_world = true } ->
            (* Fatal: file has no opening construct (include / find_package /
               add_subdirectory / dynamic cmake_call / non-literal fun name),
               so the command set is statically closed → the unknown name
               MUST be a typo. *)
            Stdlib.Printf.eprintf
              "yelu compile: %s: unknown command %S — no in-file function/macro \
               by that name and no opening construct (include / find_package / \
               add_subdirectory / cmake_call / dynamic fun-name) that would \
               introduce one. Did you mean `fun`/`function`/`macro` to define it?\n"
              file name;
            Stdlib.exit 1
          | Yelu_langs.Yc_wellform.Function_def_typo { name; closed_world = true } ->
            (* CST shape: IDENT args (block) adjacent to standalone block, in a
               closed world — can only be a typo'd fun/function/macro. Open
               world downgrades to a warning below (audit #4). *)
            Stdlib.Printf.eprintf
              "yelu compile: %s: `%s args (block)` — adjacent command + \
               standalone block has no valid cmake reading. \
               Did you mean `fun %s(args) (body)`?\n"
              file name name;
            Stdlib.exit 1
          | Yelu_langs.Yc_wellform.Unknown_kwarg { command; key } ->
            (* Fatal: the parser reads only the kwargs it knows; an unknown
               `~label=` would be silently dropped (silent semantic loss —
               `link_lib foo ~public=[…]` used to emit an empty link list). *)
            Stdlib.Printf.eprintf
              "yelu compile: %s: `%s` does not accept ~%s= — the argument \
               would be silently dropped; check the label spelling\n"
              file command key;
            Stdlib.exit 1
          | Yelu_langs.Yc_wellform.Unknown_command { name; closed_world = false } ->
            (* Warning: file has at least one opening construct, so the
               command set is genuinely open. Could be cross-file user
               functions, cmake-stdlib (cmake_parse_arguments,
               check_language, …), or a dynamic call. Hint the user. *)
            warn (Printf.sprintf
                    "[yelu][unknown-command] %s: %S is not a typed yc primitive \
                     and is not declared as a function/macro in this file. \
                     If this is a cmake-stdlib or cross-file call (this file \
                     has an opening construct, so unknown names cannot be \
                     statically resolved), wrap it in `yc_raw '…'` to silence."
                    file name)
          | Yelu_langs.Yc_wellform.Function_def_typo
              { name; closed_world = false } ->
            (* Warning in open world: the shape looks like a typo'd fun, but
               the name may be a cross-file command followed by a block. *)
            warn (Printf.sprintf
                    "[yelu][fun-typo?] %s: `%s args (block)` looks like a \
                     typo'd `fun %s(args) (body)`; if %s is a cross-file \
                     command this is fine."
                    file name name name)
          | _ -> ());
        let raw_escapes, others =
          List.partition_tf errors ~f:(function
            | Yelu_langs.Yc_wellform.Raw_cmake_escape _ -> true
            | _ -> false)
        in
        (* Unknown_command warnings are already surfaced above with a
           dedicated message; skip the generic Sexp dump for them. *)
        let others = List.filter others ~f:(function
          | Yelu_langs.Yc_wellform.Unknown_command _ -> false
          | _ -> true)
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
    (* Emit can raise (e.g. an Eval_error or an unhandled IR shape). Report it
       cleanly + exit 1, matching the corpus gate — the single-file CLI must not
       dump an OCaml backtrace (audit 2026-06). *)
    (try Yelu_langs.Yelu_cmake_emit.emit_script expr
     with e ->
       Stdlib.Printf.eprintf "yelu compile: %s: emit failed: %s\n"
         file (Exn.to_string e);
       Stdlib.exit 1)

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
                 && not (String.equal name "debug.yc")
                 (* debug.yc is the documented scratch convention (gitignored
                    per .gitignore); skip in the corpus walk so users can
                    keep a typo'd playground without breaking the gate. *)
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
  (* file-api: request the codemodel so this same configure also emits the
     build-model JSON (Y5 supplement; consumed by cmd_hybrid's diff). Must be
     written AFTER the wipe above. *)
  let query = Stdlib.Filename.concat build_dir ".cmake/api/v1/query" in
  mkdirp query;
  write_all (Stdlib.Filename.concat query "codemodel-v2") "";
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

(* ============================================================
   file-api supplement (Y5 / audit follow-up, 2026-07).

   The cache diff below is structurally blind to anything that is not a
   cache variable — target properties, install rules, test definitions.
   Three real bugs hid there (set_target_properties on ${empty}, install
   clauses, add_test's dropped `-C` args). Supplement: query cmake's
   file-api (codemodel-v2) during both configures and diff the normalized
   replies, plus `ctest --show-only=json-v1` for test definitions.
   ============================================================ *)

(* The codemodel query itself is written by [cmake_configure] (which wipes the
   build dir first, so the query must be created there, post-wipe). *)

(* Canonicalize a reply: drop cmake-internal bookkeeping that varies without
   semantic effect (same set the file-api test harness strips —
   test/cmake_file_api_cmp.py), and sort assoc keys so structural equality
   is string equality on the pretty-print. *)
let rec json_canon (j : Yojson.Safe.t) : Yojson.Safe.t =
  let unstable = [ "jsonFile"; "backtrace"; "backtraceGraph"; "id" ] in
  match j with
  | `Assoc kvs ->
    `Assoc
      (kvs
       |> List.filter ~f:(fun (k, _) ->
            not (List.mem unstable k ~equal:String.equal))
       |> List.map ~f:(fun (k, v) -> (k, json_canon v))
       |> List.sort ~compare:(fun (a, _) (b, _) -> String.compare a b))
  | `List xs -> `List (List.map xs ~f:json_canon)
  | x -> x

(* key → canonical-json map of the codemodel replies. [normalize] rewrites the
   vendor/hybrid roots to shared placeholders in the raw text (paths only occur
   inside JSON strings). Reply filenames carry a content hash — key on the
   hashless prefix (`target-fmt-Debug-<hash>.json` → `target-fmt-Debug`),
   mirroring the python harness. *)
let fileapi_reply_map ~normalize build_dir : (string * string) list =
  let reply = Stdlib.Filename.concat build_dir ".cmake/api/v1/reply" in
  if not (Stdlib.Sys.file_exists reply) then []
  else
    Stdlib.Sys.readdir reply |> Array.to_list
    |> List.filter ~f:(fun f ->
         String.is_suffix f ~suffix:".json"
         && (String.is_prefix f ~prefix:"codemodel-v2"
             || String.is_prefix f ~prefix:"target-"))
    |> List.map ~f:(fun f ->
         let key =
           let stem = String.chop_suffix_exn f ~suffix:".json" in
           match String.rsplit2 stem ~on:'-' with
           | Some (k, _hash) -> k
           | None -> stem
         in
         let canon =
           read_all (Stdlib.Filename.concat reply f)
           |> normalize |> Yojson.Safe.from_string |> json_canon
           |> Yojson.Safe.pretty_to_string
         in
         (key, canon))
    |> List.sort ~compare:(fun (a, _) (b, _) -> String.compare a b)

(* Test definitions incl. full command arg lists — the channel that would have
   caught the add_test `-C` drop. *)
let ctest_show ~normalize build_dir : string option =
  let out, code =
    run_capture
      (Printf.sprintf "cd %s && ctest --show-only=json-v1 2>/dev/null"
         (Stdlib.Filename.quote build_dir))
  in
  if code <> 0 then None
  else
    match Yojson.Safe.from_string (normalize out) with
    | j -> Some (Yojson.Safe.pretty_to_string (json_canon j))
    | exception _ -> None

(* First point of divergence between two canonical pretty-prints — enough to
   triage from the log without dumping whole codemodels. *)
let first_divergence a b : (int * string * string) option =
  let la = String.split_lines a and lb = String.split_lines b in
  let rec go i = function
    | x :: xs, y :: ys ->
      if String.equal x y then go (i + 1) (xs, ys) else Some (i, x, y)
    | x :: _, [] -> Some (i, x, "<end>")
    | [], y :: _ -> Some (i, "<end>", y)
    | [], [] -> None
  in
  go 1 (la, lb)

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

  (* 4. Run cmake on both — with the file-api codemodel query in place, so
     each configure also emits the build-model JSON (free: same configure). *)
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
  let cache_semantic =
  if String.equal v_cache h_cache then begin
    log "[yelu] caches MATCH — hybrid is semantically equivalent";
    []
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
    semantic
  end
  in

  (* 6. file-api supplement: diff the codemodel (targets, properties, sources,
     install rules) + ctest definitions — the classes the cache diff cannot
     see. Roots normalized to shared placeholders so vendor/hybrid paths
     compare equal. *)
  let realpath p =
    run_capture (Printf.sprintf "realpath %s" (Stdlib.Filename.quote p))
    |> fst |> String.strip in
  let normalize s =
    List.fold
      [ realpath hybrid_build, "<BUILD>"; realpath vendor_build, "<BUILD>";
        realpath yelu_root, "<SRC>"; source_abs, "<SRC>" ]
      ~init:s
      ~f:(fun acc (root, placeholder) ->
        if String.is_empty root then acc
        else String.substr_replace_all acc ~pattern:root ~with_:placeholder)
  in
  let cm_v = fileapi_reply_map ~normalize vendor_build in
  let cm_h = fileapi_reply_map ~normalize hybrid_build in
  let keys =
    Set.union
      (Set.of_list (module String) (List.map cm_v ~f:fst))
      (Set.of_list (module String) (List.map cm_h ~f:fst))
    |> Set.to_list
  in
  let fileapi_bad =
    List.filter_map keys ~f:(fun key ->
      let find m = List.Assoc.find m key ~equal:String.equal in
      match find cm_v, find cm_h with
      | Some a, Some b when String.equal a b -> None
      | Some a, Some b ->
        (match first_divergence a b with
         | Some (line, va, vh) ->
           log "[yelu] file-api DIFFER %s (line %d):" key line;
           log "    vendor: %s" (String.strip va);
           log "    hybrid: %s" (String.strip vh)
         | None -> ());
        Some (Printf.sprintf "codemodel %s" key)
      | Some _, None ->
        log "[yelu] file-api: %s only in vendor" key;
        Some (Printf.sprintf "%s only in vendor" key)
      | None, Some _ ->
        log "[yelu] file-api: %s only in hybrid" key;
        Some (Printf.sprintf "%s only in hybrid" key)
      | None, None -> None)
  in
  let ctest_bad =
    match ctest_show ~normalize vendor_build, ctest_show ~normalize hybrid_build with
    | Some a, Some b when String.equal a b -> []
    | Some a, Some b ->
      (match first_divergence a b with
       | Some (line, va, vh) ->
         log "[yelu] ctest DIFFER (line %d):" line;
         log "    vendor: %s" (String.strip va);
         log "    hybrid: %s" (String.strip vh)
       | None -> ());
      [ "ctest definitions" ]
    | None, None -> []          (* no ctest / no tests on either side *)
    | Some _, None -> log "[yelu] ctest: hybrid produced no output"; [ "ctest hybrid missing" ]
    | None, Some _ -> log "[yelu] ctest: vendor produced no output"; [ "ctest vendor missing" ]
  in
  log "[yelu] file-api: %d codemodel keys, %d differ%s"
    (List.length keys) (List.length fileapi_bad)
    (if List.is_empty ctest_bad then "; ctest MATCH" else "; ctest DIFFERS");

  log "[yelu] log saved: %s" log_path;
  Stdlib.close_out log_oc;
  if List.is_empty cache_semantic
  && List.is_empty fileapi_bad
  && List.is_empty ctest_bad
  then Stdlib.exit 0
  else Stdlib.exit 1

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
    (* wellform warnings → stderr (the cmake text goes to stdout / -o), so
       `yelu compile` surfaces them instead of silently dropping them. *)
    let cmake_text =
      compile ~warn:(fun s -> Stdlib.Printf.eprintf "%s\n%!" s) file
    in
    (match out with
     | None -> Stdlib.print_string cmake_text
     | Some path -> write_all path cmake_text)
  | "compile-corpus" :: probe_dir :: _ ->
    (* Build-time gate: compile every .yc under [probe_dir] (parse + wellform +
       emit) and fail if any does not compile. Catches the regressions the
       matrix only sees at configure time — positional cmake-keyword forms,
       enum-shadow declarations, parse errors, emit crashes — without needing
       cmake. Wired into `dune test` via probes/fmt/dune. *)
    let helpers = discover_helpers probe_dir in
    let check file =
      let src = read_all file in
      (* B1 (2026-06-21): corpus gate goes through Yc_driver.parse_and_check,
         same pipeline as compile / fmt / LSP. Gains Function_def_typo
         (CST-shape check) for free. *)
      match Yelu_langs.Yc_driver.parse_and_check src with
      | Error e -> Error (Printf.sprintf "parse error: %s" e)
      | Ok { Yelu_langs.Yc_driver.expr; cst = _; findings } ->
        let fatals =
          List.filter_map findings ~f:(function
            | Yelu_langs.Yc_wellform.Positional_form { command } ->
              Some (Printf.sprintf "%s in positional cmake-keyword form" command)
            | Yelu_langs.Yc_wellform.Enum_shadow { name; constructor } ->
              Some (Printf.sprintf "%S shadows the %s constructor" name constructor)
            (* Closed-world Unknown_command IS fatal in the corpus gate as of
               2026-06-21, after the cmake-stdlib name-cache landed
               (Cmake_stdlib_names; doc/yelu_cmake/discovered_cache.md).
               Legitimate stdlib calls (`cmake_parse_arguments`,
               `check_language`, `cuda_add_executable`, …) are now silenced
               via the stdlib whitelist, so the only closed-world unknowns
               left are real typos. *)
            | Yelu_langs.Yc_wellform.Unknown_command { name; closed_world = true } ->
              Some (Printf.sprintf "unknown command %S (closed world)" name)
            | Yelu_langs.Yc_wellform.Function_def_typo
                { name; closed_world = true } ->
              Some (Printf.sprintf
                      "`%s args (block)` — adjacent command + standalone block; \
                       did you mean `fun %s(args) (body)`?" name name)
            | Yelu_langs.Yc_wellform.Unknown_kwarg { command; key } ->
              Some (Printf.sprintf
                      "`%s` does not accept ~%s= (argument would be silently \
                       dropped)" command key)
            | _ -> None)
        in
        if not (List.is_empty fatals) then Error (String.concat ~sep:"; " fatals)
        else
          (try ignore (Yelu_langs.Yelu_cmake_emit.emit_script expr); Ok ()
           with e -> Error ("emit: " ^ Exn.to_string e))
    in
    let results = List.map helpers ~f:(fun h -> (h.source, check h.source)) in
    let failures =
      List.filter_map results ~f:(fun (f, r) ->
        match r with Error e -> Some (f, e) | Ok () -> None)
    in
    let total = List.length results in
    Stdlib.Printf.printf "[yelu] compile-corpus %s: %d/%d ok\n%!"
      probe_dir (total - List.length failures) total;
    List.iter failures ~f:(fun (f, e) ->
      Stdlib.Printf.printf "  FAIL %s: %s\n%!" f e);
    if not (List.is_empty failures) then Stdlib.exit 1
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
