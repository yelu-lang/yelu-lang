(* ─── Driver: yc (Yelu_cmake.expr) ──────────────
   yc is the hub of the pipelines graph — five
   inbound paths, three outbound. Every operation
   is code (pure OCaml).
   ─────────────────────────────────────────────── *)

open Yelu_cmake

(* ══  parse  ═══════════════════════════════════ *)

let parse_yc src : (expr, string) result =
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

(* → .yc text from an [expr]: not implemented — the faithful formatter is
   text→text (it needs the CST's comments/structure, which [expr] drops).
   See [format] below and doc/lang/surface_status.md (M1.3). *)
let print_yc _e =
  failwith "yc_driver.print_yc: not implemented (use [format] / text→CST→text)"

(* The .yc formatter (print_ye): text → canonical text, via the CST.
   parse_cst then print; semantics-preserving + idempotent (oracles in
   test_yc_cst_bridge). *)
let format (src : string) : (string, string) Result.t =
  match Yc_cst_parse.parse src with
  | Ok cst -> Ok (Yc_cst_print.print_program cst)
  | Error e -> Error e

(* ══  eval  ════════════════════════════════════ *)

let eval env e =
  Yelu_cmake_eval.eval_expr env e

(* ══  convert  ═════════════════════════════════ *)

let to_ycn (e : expr) : expr =
  Yelu_cmake_convert.to_normal e

(* ══  introspect  ══════════════════════════════ *)

(* The vocabulary co-truth (Yc_manifest), exposed on the uniform driver
   interface so external consumers — the tm-grammar generator, the
   `yelu manifest` CLI, future tools — read it through the driver rather
   than reaching into Yc_primitives internals. See
   doc/lang/surface_lsp_framework.md Sec 3.8. *)
let manifest () : Yc_manifest.entry list = Yc_manifest.all

(* ══  check  ═══════════════════════════════════ *)

(* Typecheck: per-theory Make_*_check functors.
   No single entry point; callers instantiate per theory. *)
let typecheck _prog =
  failwith "yc_driver.typecheck: distributed across per-theory functors"

(* Wellform: reserved-name + apply-shadowing + raw-tainted checks.
   See [Yc_wellform] for the three independent check functions. *)
let wellform = Yc_wellform.check_all
