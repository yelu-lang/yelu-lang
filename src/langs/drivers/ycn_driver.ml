(* ─── Driver: ycn (Yelu_cmake.expr — normalized form) ──
   yc and ycn share the same extensible [Yelu_cmake.expr]
   type. ycn uses normalized constructors (ESetVar, etc.)
   from the yelu_cmake_normal_* fragments. ycn has only one
   neighbour: yc, via Yelu_cmake_convert.
   ─────────────────────────────────────────────────────── *)

open Yelu_cmake

(* ══  parse  ═══════════════════════════════════ *)

(* from yc *)
let parse_yc (e : expr) : expr =
  Yelu_cmake_convert.to_normal e

(* from .ycn text: no parser exists *)
let parse_ycn _src =
  failwith "ycn_driver.parse_ycn: not implemented (design-only)"

(* ══  print / compile  ═════════════════════════ *)

(* → yc (lift) *)
let compile_to_yc (e : expr) : expr =
  Yelu_cmake_convert.from_normal e

(* → .ycn text: no printer exists *)
let print_ycn _e =
  failwith "ycn_driver.print_ycn: not implemented"

(* ══  eval  ════════════════════════════════════ *)

let eval env e =
  Yelu_cmake_normal_eval.eval_expr env e

(* ══  check  ═══════════════════════════════════ *)

(* lift-lower oracle: to_normal ∘ from_normal ≡ id *)
let check_roundtrip (e : expr) : (expr, string) result =
  try Ok (Yelu_cmake_convert.from_normal (Yelu_cmake_convert.to_normal e))
  with exn -> Error (Printexc.to_string exn)
