(** Run cmake -P on cmake scripts and cmake -S -B for configure mode.
    Used for conf-run level validation: compile yelu → cmake text → cmake → check output. *)

type run_result = {
  exit_code : int;
  stdout : string;
  stderr : string;
}

type configure_result = {
  run   : run_result;
  cache : (string * string) list;  (* variable name → value, type stripped *)
}

type configured_project = {
  source_dir : string;
  build_dir : string;
  configure : configure_result;
}

let rec mkdirp path =
  if Sys.file_exists path then ()
  else begin
    mkdirp (Filename.dirname path);
    (try Unix.mkdir path 0o700 with Unix.Unix_error (Unix.EEXIST, _, _) -> ())
  end

let write_file path content =
  mkdirp (Filename.dirname path);
  let oc = open_out path in
  output_string oc content;
  close_out oc

let read_all ch =
  let buf = Buffer.create 4096 in
  let tmp = Bytes.create 4096 in
  let rec loop () =
    match input ch tmp 0 4096 with
    | 0 -> ()
    | n ->
      Buffer.add_string buf (Bytes.sub_string tmp 0 n);
      loop ()
    | exception End_of_file -> ()
  in
  loop ();
  Buffer.contents buf

let make_env extra =
  let extra_keys = List.map (fun (k, _) -> k) extra in
  let base = Array.to_list (Unix.environment ())
    |> List.filter (fun entry ->
        let key = match String.index_opt entry '=' with
          | Some i -> String.sub entry 0 i
          | None -> entry in
        not (List.mem key extra_keys))
  in
  Array.of_list (base @ List.map (fun (k, v) -> k ^ "=" ^ v) extra)

(* All cmake subprocess calls go through cmake_env so they never emit ANSI escape
   codes into captured stderr/stdout. Dune sets CLICOLOR_FORCE=1 when running test
   aliases to force colors in alcotest output; cmake inherits this and wraps every
   message() with \x1b[0m reset codes, breaking hex-encoded pattern checks in the
   message/newline compat test. Force CLICOLOR_FORCE=0 for cmake subprocesses. *)
let cmake_env extra =
  let base = if List.mem_assoc "CLICOLOR_FORCE" extra then extra else ("CLICOLOR_FORCE", "0") :: extra in
  make_env base

let run_script_file ?(env = []) ?(flags = []) ?(cwd = None) path =
  let flags_str = match flags with [] -> "" | fs -> String.concat " " fs ^ " " in
  let cmake_cmd = Printf.sprintf "cmake %s-P %s" flags_str (Filename.quote path) in
  (* RunCMake scripts use include(relative.cmake) which resolves to the process CWD.
     Prefixing with "cd <dir> &&" matches what CTest does when running each test. *)
  let cmd = match cwd with
    | None -> cmake_cmd
    | Some dir -> Printf.sprintf "cd %s && %s" (Filename.quote dir) cmake_cmd
  in
  let stdout_ch, stdin_ch, stderr_ch =
    Unix.open_process_full cmd (cmake_env env)
  in
  close_out stdin_ch;
  let stdout = read_all stdout_ch in
  let stderr = read_all stderr_ch in
  let status = Unix.close_process_full (stdout_ch, stdin_ch, stderr_ch) in
  let exit_code =
    match status with
    | Unix.WEXITED n -> n
    | Unix.WSIGNALED n -> 128 + n
    | Unix.WSTOPPED n -> 128 + n
  in
  { exit_code; stdout; stderr }

let check_exit expected result =
  if result.exit_code <> expected then
    Alcotest.failf "exit %d, expected %d\nstderr:\n%s" result.exit_code expected result.stderr

let check_stderr_matches pattern result =
  let re = Re.Posix.compile_pat pattern in
  if not (Re.execp re result.stderr) then
    Alcotest.failf "stderr did not match pattern %S\ngot:\n%s" pattern result.stderr

let check_stdout_matches pattern result =
  let re = Re.Posix.compile_pat pattern in
  if not (Re.execp re result.stdout) then
    Alcotest.failf "stdout did not match pattern %S\ngot:\n%s" pattern result.stdout

let escape_braces pat =
  (* cmake regex treats { } as literals; PCRE treats {n} as quantifiers.
     Re.Pcre throws a parse error on bare {word}. Escape every { and } that
     is not already preceded by a backslash. *)
  let buf = Buffer.create (String.length pat + 4) in
  let n = String.length pat in
  let i = ref 0 in
  while !i < n do
    let c = pat.[!i] in
    if (c = '{' || c = '}') && (!i = 0 || pat.[!i - 1] <> '\\') then
      (Buffer.add_char buf '\\'; Buffer.add_char buf c)
    else
      Buffer.add_char buf c;
    incr i
  done;
  Buffer.contents buf

let strip_line_anchors pat =
  (* RunCMake stdout patterns use ^ and $ as line anchors (cmake's multiline regex),
     but Re.Posix treats them as string anchors. Strip them so Re.execp finds the
     pattern anywhere in the multi-line stdout string. *)
  let p = if String.length pat > 0 && pat.[0] = '^' then String.sub pat 1 (String.length pat - 1) else pat in
  let n = String.length p in
  if n > 0 && p.[n-1] = '$' then String.sub p 0 (n - 1) else p

let load_stdout_patterns dir name =
  let path = Filename.concat dir (name ^ "-stdout.txt") in
  if not (Sys.file_exists path) then []
  else
    let ic = open_in path in
    let lines = ref [] in
    (try while true do
       let l = String.trim (input_line ic) in
       if l <> "" then lines := (escape_braces (strip_line_anchors l)) :: !lines
     done with End_of_file -> ());
    close_in ic;
    List.rev !lines

let check_stdout_patterns patterns result =
  List.iter (fun pat ->
    let re = Re.Pcre.regexp pat in
    if not (Re.execp re result.stdout) then
      Alcotest.failf "stdout did not match pattern %S\ngot:\n%s" pat result.stdout
  ) patterns

(* Replace any cmake filepath (e.g. "/tmp/yelu_12345.cmake") with "<cmake>"
   so two runs with different temp file names can be compared. *)
let normalize_cmake_filepath s =
  let re = Re.Pcre.regexp {|[^\s:"']+\.cmake|} in
  Re.replace_string re ~by:"<cmake>" s

let check_stderr_normalized ref_result yelu_result cmake_text =
  let ref_norm  = normalize_cmake_filepath ref_result.stderr in
  let yelu_norm = normalize_cmake_filepath yelu_result.stderr in
  if ref_norm <> yelu_norm then
    Alcotest.failf "stderr mismatch\nref :\n%s\nyelu:\n%s\nyelu cmake:\n%s"
      ref_result.stderr yelu_result.stderr cmake_text

let run_script ?(env = []) ?(flags = []) cmake_text =
  let tmp = Filename.temp_file "yelu_" ".cmake" in
  let cleanup () = (try Sys.remove tmp with _ -> ()) in
  match
    let oc = open_out tmp in
    output_string oc cmake_text;
    close_out oc;
    run_script_file ~env ~flags tmp
  with
  | result -> cleanup (); result
  | exception e -> cleanup (); raise e

(* Parse CMakeCache.txt into (name, value) pairs. Lines look like:
     VAR_NAME:TYPE=value
   Comment lines start with # or //; blank lines are skipped. *)
let parse_cache path =
  let ic = open_in path in
  let entries = ref [] in
  (try
    while true do
      let line = input_line ic in
      let line = String.trim line in
      if line <> "" && line.[0] <> '#' && not (String.length line >= 2 && line.[0] = '/' && line.[1] = '/') then
        (* find ':' for type separator, then '=' for value *)
        match String.index_opt line ':' with
        | None -> ()
        | Some colon ->
          let name = String.sub line 0 colon in
          let rest = String.sub line (colon + 1) (String.length line - colon - 1) in
          (match String.index_opt rest '=' with
           | None -> ()
           | Some eq ->
             let value = String.sub rest (eq + 1) (String.length rest - eq - 1) in
             entries := (name, value) :: !entries)
    done
  with End_of_file -> ());
  close_in ic;
  List.rev !entries

let run_configure ?(cmake_min = "3.20") ?(files = []) ?(languages = ["NONE"]) cmake_text =
  (* Ensure cmake_minimum_required appears before project(); cmake 4.x errors without it *)
  let has_project =
    let re = Re.(compile (seq [str "project"; rep (alt [char ' '; char '\t']); char '('])) in
    Re.execp re cmake_text in
  let has_cmake_min =
    let re = Re.(compile (str "cmake_minimum_required")) in
    Re.execp re cmake_text in
  let full_text =
    if not has_project then
      let langs = String.concat " " languages in
      Printf.sprintf "cmake_minimum_required(VERSION %s)\nproject(_yelu_test %s)\n%s" cmake_min langs cmake_text
    else if not has_cmake_min then
      Printf.sprintf "cmake_minimum_required(VERSION %s)\n%s" cmake_min cmake_text
    else cmake_text
  in
  let tmpdir = Filename.temp_file "yelu_conf_" "" in
  Sys.remove tmpdir;
  Unix.mkdir tmpdir 0o700;
  let build = Filename.concat tmpdir "_build" in
  let cleanup () =
    let rec rm path =
      if Sys.is_directory path then begin
        Array.iter (fun e -> rm (Filename.concat path e)) (Sys.readdir path);
        Unix.rmdir path
      end else Sys.remove path
    in
    (try rm tmpdir with _ -> ())
  in
  match
    let cmake_file = Filename.concat tmpdir "CMakeLists.txt" in
    let oc = open_out cmake_file in
    output_string oc full_text;
    close_out oc;
    List.iter (fun (name, content) ->
      write_file (Filename.concat tmpdir name) content) files;
    let cmd = Printf.sprintf "cmake -S %s -B %s" (Filename.quote tmpdir) (Filename.quote build) in
    let stdout_ch, stdin_ch, stderr_ch = Unix.open_process_full cmd (cmake_env []) in
    close_out stdin_ch;
    let stdout = read_all stdout_ch in
    let stderr = read_all stderr_ch in
    let status = Unix.close_process_full (stdout_ch, stdin_ch, stderr_ch) in
    let exit_code = match status with
      | Unix.WEXITED n -> n | Unix.WSIGNALED n -> 128 + n | Unix.WSTOPPED n -> 128 + n
    in
    let cache_path = Filename.concat build "CMakeCache.txt" in
    let cache = if Sys.file_exists cache_path then parse_cache cache_path else [] in
    { run = { exit_code; stdout; stderr }; cache }
  with
  | result -> cleanup (); result
  | exception e -> cleanup (); raise e

let configure_project ?(cmake_min = "3.20") ?(files = []) ?(languages = ["NONE"]) cmake_text =
  let has_project =
    let re = Re.(compile (seq [str "project"; rep (alt [char ' '; char '\t']); char '('])) in
    Re.execp re cmake_text in
  let has_cmake_min =
    let re = Re.(compile (str "cmake_minimum_required")) in
    Re.execp re cmake_text in
  let full_text =
    if not has_project then
      let langs = String.concat " " languages in
      Printf.sprintf "cmake_minimum_required(VERSION %s)\nproject(_yelu_test %s)\n%s" cmake_min langs cmake_text
    else if not has_cmake_min then
      Printf.sprintf "cmake_minimum_required(VERSION %s)\n%s" cmake_min cmake_text
    else cmake_text
  in
  let source_dir = Filename.temp_file "yelu_conf_" "" in
  Sys.remove source_dir;
  Unix.mkdir source_dir 0o700;
  let build_dir = Filename.concat source_dir "_build" in
  let cmake_file = Filename.concat source_dir "CMakeLists.txt" in
  let oc = open_out cmake_file in
  output_string oc full_text;
  close_out oc;
  List.iter (fun (name, content) ->
    write_file (Filename.concat source_dir name) content) files;
  let cmd = Printf.sprintf "cmake -S %s -B %s" (Filename.quote source_dir) (Filename.quote build_dir) in
  let stdout_ch, stdin_ch, stderr_ch = Unix.open_process_full cmd (cmake_env []) in
  close_out stdin_ch;
  let stdout = read_all stdout_ch in
  let stderr = read_all stderr_ch in
  let status = Unix.close_process_full (stdout_ch, stdin_ch, stderr_ch) in
  let exit_code = match status with
    | Unix.WEXITED n -> n | Unix.WSIGNALED n -> 128 + n | Unix.WSTOPPED n -> 128 + n
  in
  let cache_path = Filename.concat build_dir "CMakeCache.txt" in
  let cache = if Sys.file_exists cache_path then parse_cache cache_path else [] in
  { source_dir; build_dir; configure = { run = { exit_code; stdout; stderr }; cache } }

let run_build_target project target =
  let cmd =
    Printf.sprintf "cmake --build %s --target %s"
      (Filename.quote project.build_dir)
      (Filename.quote target)
  in
  let stdout_ch, stdin_ch, stderr_ch = Unix.open_process_full cmd (cmake_env []) in
  close_out stdin_ch;
  let stdout = read_all stdout_ch in
  let stderr = read_all stderr_ch in
  let status = Unix.close_process_full (stdout_ch, stdin_ch, stderr_ch) in
  let exit_code = match status with
    | Unix.WEXITED n -> n | Unix.WSIGNALED n -> 128 + n | Unix.WSTOPPED n -> 128 + n
  in
  { exit_code; stdout; stderr }

let cleanup_configured_project project =
  let rec rm path =
    if Sys.file_exists path then
      if Sys.is_directory path then begin
        Array.iter (fun e -> rm (Filename.concat path e)) (Sys.readdir path);
        Unix.rmdir path
      end else Sys.remove path
  in
  rm project.source_dir

let run_cmd_simple cmd =
  let stdout_ch, stdin_ch, stderr_ch = Unix.open_process_full cmd (cmake_env []) in
  close_out stdin_ch;
  let stdout = read_all stdout_ch in
  let stderr = read_all stderr_ch in
  let status = Unix.close_process_full (stdout_ch, stdin_ch, stderr_ch) in
  let exit_code = match status with
    | Unix.WEXITED n -> n | Unix.WSIGNALED n -> 128 + n | Unix.WSTOPPED n -> 128 + n
  in
  { exit_code; stdout; stderr }

let file_api_compare_script =
  {|
import glob, json, os, shutil, subprocess, sys, tempfile

def strip_unstable(obj):
    if isinstance(obj, dict):
        return {
            k: strip_unstable(v)
            for k, v in obj.items()
            if k not in ("jsonFile", "backtrace", "backtraceGraph", "id")
        }
    if isinstance(obj, list):
        return [strip_unstable(v) for v in obj]
    return obj

def run_cmake(source_dir, build_dir):
    query = os.path.join(build_dir, ".cmake", "api", "v1", "query")
    os.makedirs(query, exist_ok=True)
    open(os.path.join(query, "codemodel-v2"), "w").close()
    result = subprocess.run(
        ["cmake", "-S", source_dir, "-B", build_dir],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        print(result.stderr, file=sys.stderr)
        sys.exit(2)

def normalize_paths(obj, source_dir, build_dir):
    if isinstance(obj, dict):
        return {k: normalize_paths(v, source_dir, build_dir) for k, v in obj.items()}
    if isinstance(obj, list):
        return [normalize_paths(v, source_dir, build_dir) for v in obj]
    if isinstance(obj, str):
        return obj.replace(source_dir, "<src>").replace(build_dir, "<build>")
    return obj

def load_replies(source_dir, build_dir):
    reply_dir = os.path.join(build_dir, ".cmake", "api", "v1", "reply")
    replies = {}
    for pattern in ["codemodel-v2", "target-*"]:
        for path in glob.glob(os.path.join(reply_dir, pattern + "*.json")):
            key = os.path.basename(path).rsplit("-", 1)[0]
            with open(path) as handle:
                replies[key] = normalize_paths(strip_unstable(json.load(handle)), source_dir, build_dir)
    return replies

def write_project(root, cmake_text, files):
    os.makedirs(root, exist_ok=True)
    with open(os.path.join(root, "CMakeLists.txt"), "w") as handle:
        handle.write(cmake_text)
    for spec in files:
        rel, content = spec.split("\x01", 1)
        path = os.path.join(root, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as handle:
            handle.write(content)

with tempfile.TemporaryDirectory(prefix="yelu_file_api_") as tmp:
    left_src = os.path.join(tmp, "left")
    right_src = os.path.join(tmp, "right")
    left_build = os.path.join(tmp, "left-build")
    right_build = os.path.join(tmp, "right-build")
    files = sys.argv[3:]
    write_project(left_src, sys.argv[1], files)
    write_project(right_src, sys.argv[2], files)
    run_cmake(left_src, left_build)
    run_cmake(right_src, right_build)
    left = load_replies(left_src, left_build)
    right = load_replies(right_src, right_build)
    if left != right:
        print("File API replies differ", file=sys.stderr)
        print(json.dumps({"left": left, "right": right}, indent=2, sort_keys=True), file=sys.stderr)
        sys.exit(1)
|}

let compare_file_api ?(files = []) left_cmake right_cmake =
  let script = Filename.temp_file "yelu_file_api_cmp_" ".py" in
  let cleanup () = (try Sys.remove script with _ -> ()) in
  match
    write_file script file_api_compare_script;
    let file_args =
      files
      |> List.map (fun (name, content) -> Filename.quote (name ^ "\001" ^ content))
      |> String.concat " "
    in
    let cmd =
      Printf.sprintf "python3 %s %s %s%s%s"
        (Filename.quote script)
        (Filename.quote left_cmake)
        (Filename.quote right_cmake)
        (if file_args = "" then "" else " ")
        file_args
    in
    run_cmd_simple cmd
  with
  | result -> cleanup (); result
  | exception e -> cleanup (); raise e

type artifact = {
  rel_path : string;   (* path relative to build root, using '/' separator *)
  size     : int;      (* file size in bytes *)
}

(* Walk build_dir, skip cmake-internal paths, return artifact list sorted by rel_path. *)
let enumerate_build_outputs build_dir =
  let cmake_skip_names = ["CMakeFiles"; "CMakeCache.txt"; "cmake_install.cmake";
                          "Makefile"; "build.ninja"; ".ninja_deps"; ".ninja_log"] in
  let cmake_skip_exts  = [".cmake"; ".d"; ".ninja"] in
  let is_cmake_file name =
    List.mem name cmake_skip_names
    || List.exists (fun ext -> Filename.check_suffix name ext) cmake_skip_exts
  in
  let results = ref [] in
  let rec walk rel abs =
    if Sys.is_directory abs then begin
      if not (is_cmake_file (Filename.basename abs)) then
        Array.iter (fun entry ->
          let rel' = if rel = "" then entry else rel ^ "/" ^ entry in
          walk rel' (Filename.concat abs entry)
        ) (Sys.readdir abs)
    end else begin
      if not (is_cmake_file (Filename.basename abs)) then begin
        let st = Unix.stat abs in
        results := { rel_path = rel; size = st.Unix.st_size } :: !results
      end
    end
  in
  walk "" build_dir;
  List.sort (fun a b -> String.compare a.rel_path b.rel_path) !results

let check_artifacts_match ref_arts yelu_arts =
  let pp_arts arts =
    String.concat "\n" (List.map (fun a -> Printf.sprintf "  %s (%d bytes)" a.rel_path a.size) arts)
  in
  (* Layer 2a: same set of relative paths — strict *)
  let ref_names  = List.map (fun a -> a.rel_path) ref_arts in
  let yelu_names = List.map (fun a -> a.rel_path) yelu_arts in
  if ref_names <> yelu_names then
    Alcotest.failf "artifact names differ\nref :\n%s\nyelu:\n%s"
      (pp_arts ref_arts) (pp_arts yelu_arts);
  (* Layer 2b: size comparison — reported but not a hard failure.
     GCC embeds source file paths in ELF .strtab even without -g, so sizes
     differ by a small constant proportional to path length difference between
     the ref source dir and the yelu temp dir. Symbol-level comparison is
     deferred to layer 3 (nm inspection). *)
  List.iter2 (fun r y ->
    if r.size <> y.size then
      Printf.printf "  [size] %s: ref %d, yelu %d (diff %+d)\n%!"
        r.rel_path r.size y.size (y.size - r.size)
  ) ref_arts yelu_arts

type build_result = {
  configure : configure_result;
  build     : run_result;
  artifacts : artifact list;
}

(* Run cmake -S -B (configure) then cmake --build unconditionally.
   Both steps are always attempted; callers decide what to do with the results. *)
let run_configure_and_build ?(cmake_min = "3.20") ?(files = []) ?(languages = ["C"]) cmake_text =
  let has_project =
    let re = Re.(compile (seq [str "project"; rep (alt [char ' '; char '\t']); char '('])) in
    Re.execp re cmake_text in
  let has_cmake_min =
    let re = Re.(compile (str "cmake_minimum_required")) in
    Re.execp re cmake_text in
  let full_text =
    if not has_project then
      let langs = String.concat " " languages in
      Printf.sprintf "cmake_minimum_required(VERSION %s)\nproject(_yelu_test %s)\n%s" cmake_min langs cmake_text
    else if not has_cmake_min then
      Printf.sprintf "cmake_minimum_required(VERSION %s)\n%s" cmake_min cmake_text
    else cmake_text
  in
  let tmpdir = Filename.temp_file "yelu_build_" "" in
  Sys.remove tmpdir;
  Unix.mkdir tmpdir 0o700;
  let build = Filename.concat tmpdir "_build" in
  let cleanup () =
    let rec rm path =
      if Sys.is_directory path then begin
        Array.iter (fun e -> rm (Filename.concat path e)) (Sys.readdir path);
        Unix.rmdir path
      end else Sys.remove path
    in
    (try rm tmpdir with _ -> ())
  in
  match
    let cmake_file = Filename.concat tmpdir "CMakeLists.txt" in
    let oc = open_out cmake_file in
    output_string oc full_text;
    close_out oc;
    List.iter (fun (name, content) ->
      write_file (Filename.concat tmpdir name) content) files;
    let conf_run = run_cmd_simple (Printf.sprintf "cmake -S %s -B %s" (Filename.quote tmpdir) (Filename.quote build)) in
    let cache_path = Filename.concat build "CMakeCache.txt" in
    let cache = if Sys.file_exists cache_path then parse_cache cache_path else [] in
    let conf = { run = conf_run; cache } in
    let build_run = run_cmd_simple (Printf.sprintf "cmake --build %s" (Filename.quote build)) in
    let artifacts = if Sys.file_exists build then enumerate_build_outputs build else [] in
    { configure = conf; build = build_run; artifacts }
  with
  | result -> cleanup (); result
  | exception e -> cleanup (); raise e

(* Run configure + build against an existing source directory (e.g. upstream cmake test dirs). *)
let run_build_existing src_dir =
  let build = Filename.temp_file "yelu_build_ref_" "" in
  Sys.remove build;
  Unix.mkdir build 0o700;
  let cleanup () =
    let rec rm path =
      if Sys.is_directory path then begin
        Array.iter (fun e -> rm (Filename.concat path e)) (Sys.readdir path);
        Unix.rmdir path
      end else Sys.remove path
    in
    (try rm build with _ -> ())
  in
  match
    let conf_run = run_cmd_simple (Printf.sprintf "cmake -S %s -B %s" (Filename.quote src_dir) (Filename.quote build)) in
    let cache_path = Filename.concat build "CMakeCache.txt" in
    let cache = if Sys.file_exists cache_path then parse_cache cache_path else [] in
    let conf = { run = conf_run; cache } in
    let build_run = run_cmd_simple (Printf.sprintf "cmake --build %s" (Filename.quote build)) in
    let artifacts = if Sys.file_exists build then enumerate_build_outputs build else [] in
    { configure = conf; build = build_run; artifacts }
  with
  | result -> cleanup (); result
  | exception e -> cleanup (); raise e

let cache_get name result =
  List.assoc_opt name result.cache

let check_cache name expected result =
  match cache_get name result with
  | None -> Alcotest.failf "cache variable %S not found" name
  | Some v ->
    if v <> expected then
      Alcotest.failf "cache[%S]: expected %S, got %S" name expected v
