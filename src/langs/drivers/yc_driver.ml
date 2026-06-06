(* ─── Driver: yc (Yelu_cmake.expr) ──────────────
   yc is the hub of the pipelines graph — five
   inbound paths, three outbound. Every operation
   is code (pure OCaml).
   ─────────────────────────────────────────────── *)

open Yelu_cmake

(* ══  parse  ═══════════════════════════════════ *)

let parse_ye src : (expr, string) result =
  Yelu_parse.parse_program_y1 src

let parse_cmake (stmts : Lang_cmake.exp list) : expr =
  Yelu_cmake_from_emit.from_emit_top stmts

let parse_ycn (e : expr) : expr =
  Yelu_cmake_convert.from_normal e

(* ══  print / compile  ═════════════════════════ *)

let compile_to_cmake_ast (e : expr) : Lang_cmake.exp =
  Yelu_cmake_emit.emit_ast e

let print_cmake_debug (e : expr) : string =
  Yelu_cmake_emit_debug.emit_script e

(* → .ye text: not implemented *)
let print_ye _e =
  failwith "yc_driver.print_ye: not implemented"

(* ══  eval  ════════════════════════════════════ *)

let eval env e =
  Yelu_cmake_eval.eval_expr env e

(* ══  convert  ═════════════════════════════════ *)

let to_ycn (e : expr) : expr =
  Yelu_cmake_convert.to_normal e

(* ══  check  ═══════════════════════════════════ *)

(* Typecheck: per-theory Make_*_check functors.
   No single entry point; callers instantiate per theory. *)
let typecheck _prog =
  failwith "yc_driver.typecheck: distributed across per-theory functors"

(* Wellform: name-binding pass retired to yelu_legacy.
   Re-implemented against Yelu_cmake would live here. *)
let wellform _prog =
  failwith "yc_driver.wellform: retired (yelu_legacy), not re-implemented"
