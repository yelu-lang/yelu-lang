(* ─── Driver: cmake AST (Lang_cmake.exp) ─────────
   The typed cmake AST — intermediate between raw
   cmake text and yc. Print is production-grade;
   parse from JSON CST goes through Stage-1 untyped
   stmt (Cmake_text_parse), then per-command parse_cmd.
   ────────────────────────────────────────────────── *)

(* ══  parse  ═══════════════════════════════════════ *)

(* from JSON CST. Returns Stage-1 untyped stmt list;
   caller can iterate per-command parse_cmd for typed. *)
let parse_json_cst json : Cmake_text_parse.stmt list =
  Cmake_text_parse.file_of_json json

(* ══  print  ═══════════════════════════════════════ *)

let print (e : Lang_cmake.exp) : string =
  let buf = Buffer.create 1024 in
  let fmt = Format.formatter_of_buffer buf in
  Lang_cmake_pp.pp fmt e;
  Format.pp_print_flush fmt ();
  Buffer.contents buf

(* ══  from/to yc  ═════════════════════════════════ *)

let from_yc (e : Yelu_cmake.expr) : Lang_cmake.exp =
  Yelu_cmake_emit.emit_ast e

let to_yc (e : Lang_cmake.exp) : Yelu_cmake.expr =
  Yelu_cmake_from_emit.from_emit_top [e]
