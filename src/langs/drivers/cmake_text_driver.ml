(* ─── Driver: cmake text (raw CMakeLists.txt) ──
   Most operations are tool:* — shell out to cmake,
   parse.py, or gersemi. The canonical cmake-text
   printer is Lang_cmake_pp (code, in cmake_ast_driver).
   ─────────────────────────────────────────────── *)

open Base

let run_capture cmd =
  let ic = Unix.open_process_in cmd in
  let buf = Buffer.create 4096 in
  let chunk = Bytes.create 4096 in
  (try while true do
     let n = Stdlib.input ic chunk 0 (Bytes.length chunk) in
     if n = 0 then raise End_of_file
     else Buffer.add_subbytes buf chunk ~pos:0 ~len:n
   done; assert false
   with End_of_file -> ());
  let status = Unix.close_process_in ic in
  let exit_code = match status with
    | Unix.WEXITED n -> n | _ -> -1
  in
  Buffer.contents buf, exit_code

(* ══  parse  ═══════════════════════════════════ *)

(* cmake text → JSON CST via tree-sitter (tool:parse.py) *)
let parse_to_json_cst file =
  let py = "tool/cmake_text/parse.py" in
  let out, code = run_capture (Printf.sprintf "python3 %s %s 2>/dev/null"
    (Stdlib.Filename.quote py) (Stdlib.Filename.quote file))
  in
  if code = 0 then Ok out
  else Error (Printf.sprintf "parse.py exit %d: %s" code out)

(* ══  print (canonical)  ══════════════════════ *)

(* gersemi formatting (tool:gersemi) *)
let canon_format text =
  let gersemi = match Sys.getenv "GERSEMI" with
    | Some g -> g | None -> "/home/red/.venvs/default/bin/gersemi"
  in
  let cmd = Printf.sprintf "echo %s | %s - 2>/dev/null"
    (Stdlib.Filename.quote text) (Stdlib.Filename.quote gersemi)
  in
  let out, code = run_capture cmd in
  if code = 0 then Ok out
  else Error (Printf.sprintf "gersemi exit %d" code)

(* ══  eval  ════════════════════════════════════ *)

(* cmake -P (tool:cmake) *)
let eval_script file =
  let out, code = run_capture
    (Printf.sprintf "cmake -P %s 2>&1" (Stdlib.Filename.quote file))
  in
  if code = 0 then Ok out
  else Error (Printf.sprintf "cmake -P exit %d: %s" code out)

(* cmake configure (tool:cmake) *)
let eval_configure ~source_dir ~build_dir ?(d_flags = []) () =
  let flags = String.concat ~sep:" "
    (List.map d_flags ~f:(fun f -> "-D" ^ Stdlib.Filename.quote f))
  in
  let cmd = Printf.sprintf "cmake -B %s -S %s %s 2>&1"
    (Stdlib.Filename.quote build_dir) (Stdlib.Filename.quote source_dir) flags
  in
  let _, code = run_capture cmd in
  code

(* ══  check  ═══════════════════════════════════ *)

(* cmake --build (tool:cmake) *)
let check_build build_dir =
  let _, code = run_capture
    (Printf.sprintf "cmake --build %s 2>&1" (Stdlib.Filename.quote build_dir))
  in
  code = 0
