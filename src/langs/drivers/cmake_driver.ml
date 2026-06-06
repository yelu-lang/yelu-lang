(* ─── Driver: cmake (Lang_cmake.exp + cmake text) ──
   cmake is one language in two forms:
   - IR: Lang_cmake.exp (typed cmake AST)
   - text: concrete cmake syntax (CMakeLists.txt)

   Parse and eval on the text side are tool:* (shell out
   to cmake_to_json.py, gersemi, cmake). Print on the IR
   side is code (Lang_cmake_pp). Cross-language to/from
   yc is code (emit_ast / from_emit_top).
   ─────────────────────────────────────────────────── *)

(* ══  helpers  ═══════════════════════════════════ *)

let run_capture cmd =
  let ic = Unix.open_process_in cmd in
  let buf = Buffer.create 4096 in
  (try while true do Buffer.add_char buf (Stdlib.input_char ic) done; assert false
   with End_of_file -> ());
  let status = Unix.close_process_in ic in
  let exit_code = match status with
    | Unix.WEXITED n -> n | _ -> -1
  in
  Buffer.contents buf, exit_code

(* ══  parse: text → IR  ══════════════════════════ *)

(* cmake text → JSON CST (tool:tree-sitter) *)
let parse_text_to_json file =
  let py = "tool/cmake_text/cmake_to_json.py" in
  let cmd = Printf.sprintf "python3 %s %s 2>/dev/null"
    (Stdlib.Filename.quote py) (Stdlib.Filename.quote file)
  in
  let out, code = run_capture cmd in
  if code = 0 then Ok out
  else Error (Printf.sprintf "cmake_to_json.py exit %d: %s" code out)

(* JSON CST → cmake AST stmt list (code) *)
let parse_json_to_stmts json : Cmake_text_parse.stmt list =
  Cmake_text_parse.file_of_json json

(* ══  print: IR → text  ═══════════════════════════ *)

let print (e : Lang_cmake.exp) : string =
  let buf = Buffer.create 1024 in
  let fmt = Stdlib.Format.formatter_of_buffer buf in
  Lang_cmake_pp.pp fmt e;
  Stdlib.Format.pp_print_flush fmt ();
  Buffer.contents buf

(* gersemi canonical formatting (tool) *)
let print_canon text =
  let gersemi =
    try Sys.getenv "GERSEMI" with Not_found -> "/home/red/.venvs/default/bin/gersemi"
  in
  let cmd = Printf.sprintf "echo %s | %s - 2>/dev/null"
    (Stdlib.Filename.quote text) (Stdlib.Filename.quote gersemi)
  in
  let out, code = run_capture cmd in
  if code = 0 then Ok out
  else Error (Printf.sprintf "gersemi exit %d" code)

(* ══  eval: text → output  ═══════════════════════ *)

(* cmake -P (tool:cmake) *)
let eval_script file =
  let out, code = run_capture
    (Printf.sprintf "cmake -P %s 2>&1" (Stdlib.Filename.quote file))
  in
  if code = 0 then Ok out
  else Error (Printf.sprintf "cmake -P exit %d: %s" code out)

(* cmake configure (tool:cmake) *)
let eval_configure ~source_dir ~build_dir ?(d_flags = []) () =
  let flags = String.concat " "
    (List.map (fun f -> "-D" ^ Stdlib.Filename.quote f) d_flags)
  in
  let cmd = Printf.sprintf "cmake -B %s -S %s %s 2>&1"
    (Stdlib.Filename.quote build_dir) (Stdlib.Filename.quote source_dir) flags
  in
  let _, code = run_capture cmd in
  code

(* ══  check: build  ══════════════════════════════ *)

let check_build build_dir =
  let _, code = run_capture
    (Printf.sprintf "cmake --build %s 2>&1" (Stdlib.Filename.quote build_dir))
  in
  code = 0

(* ══  cross-language: cmake ↔ yc  ═══════════════ *)

let compile_to_yc (e : Lang_cmake.exp) : Yelu_cmake.expr =
  Yelu_cmake_from_emit.from_emit_top [e]

let compile_from_yc (e : Yelu_cmake.expr) : Lang_cmake.exp =
  Yelu_cmake_emit.emit_ast e
