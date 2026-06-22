(* ─── Driver: yc (Yelu_cmake.expr) ──────────────
   yc is the hub of the pipelines graph — five
   inbound paths, three outbound. Every operation
   is code (pure OCaml).
   ─────────────────────────────────────────────── *)

open Yelu_cmake

(* ══  parse  ═══════════════════════════════════ *)

(* Production path goes through [parse_and_check] (CST + check_cst + check_all).
   This direct entry remains for callers that already have an [expr] and just
   need the legacy parser shape — emit-bridge oracle, test infrastructure. *)
let parse_yc src : (expr, string) result =
  Yelu_parse.parse_program_legacy src

let parse_cmake (stmts : Lang_cmake.exp list) : expr =
  Yelu_cmake_from_emit.from_emit_top stmts

let parse_ycn (e : expr) : expr =
  Yelu_cmake_convert.from_normal e

(* ══  cst_lite form  (text ↔ cst_lite ↔ expr) ══
   The concrete-syntax tree that carries comments + source spans
   ([Yc_cst]). It is the substrate for the formatter (print_ye) and the
   LSP. Note: [parse_yc] above is still the production text→expr path; the
   CST path here is proven byte-identical to it via the emit-bridge oracle
   (emit of lower_cst.parse_cst equals emit of parse_yc, in the
   test_yc_cst_bridge tests), but has not yet replaced it (that retirement
   is deferred work; see doc/lang/surface_status.md). *)

let parse_cst (src : string) : (Yc_cst.program, string) result =
  Yc_cst_parse.parse src

let lower_cst (p : Yc_cst.program) : expr =
  Yc_cst_lower.lower_program p

let print_cst (p : Yc_cst.program) : string =
  Yc_cst_print.print_program p

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
   test_yc_cst_bridge).

   Fail-safe: refuses to format on (a) parse error or (b) fatal wellform
   finding (Enum_shadow / Positional_form / closed-world Unknown_command).
   The latter prevents the formatter from prettifying a typo like
   `funnn join(args) (body)` into a clean-looking unknown command — both
   the CLI `yelu fmt` and the LSP `textDocument/formatting` request return
   the Error, so the typo stays visible as a diagnostic rather than being
   cosmetically washed over. *)
let fatal_wellform_message : Yc_wellform.error -> string option = function
  | Yc_wellform.Enum_shadow { name; constructor } ->
    Some (Printf.sprintf "%S shadows the %s constructor" name constructor)
  | Yc_wellform.Positional_form { command } ->
    Some (Printf.sprintf "%s in positional cmake-keyword form" command)
  | Yc_wellform.Unknown_command { name; closed_world = true } ->
    Some (Printf.sprintf "unknown command %S (closed world: no \
                          include / find_package / add_subdirectory / \
                          cmake_call / dynamic fun-name)" name)
  | Yc_wellform.Function_def_typo { name } ->
    Some (Printf.sprintf "`%s args (block)` — adjacent command + standalone \
                          block. This shape has no valid cmake reading; \
                          did you mean `fun %s(args) (body)`?" name name)
  | _ -> None

(* The unified parse + wellform pipeline (B1, 2026-06-21). Single source of
   truth for "parse source, run all wellform checks, return everything the
   surfaces need." Replaces three near-duplicate orchestration sites
   (Yc_driver.format, LSP wellform_diagnostics, bin/yelu/yelu.ml compile_yc).

   Each surface consumes:
   - [expr]      — lowered IR for emit / eval
   - [cst]       — printer source for fmt / lsp range mapping
   - [findings]  — combined check_cst ∪ check_all; per-surface fatal-vs-warning
                   split is in [fatal_wellform_message] above.

   See doc/lang/surface_status.md "Driver interface — CST as a first-class
   form" Tier (b). *)
type checked = {
  expr     : expr;
  cst      : Yc_cst.program;
  findings : Yc_wellform.error list;
}

let parse_and_check (src : string) : (checked, string) Result.t =
  match Yc_cst_parse.parse src with
  | Error e -> Error e
  | Ok cst ->
    let expr = Yc_cst_lower.lower_program cst in
    let findings = Yc_wellform.check_cst cst @ Yc_wellform.check_all expr in
    Ok { expr; cst; findings }

(* Convenience: just the fatal subset, used by format + compile to refuse. *)
let fatals (findings : Yc_wellform.error list) : string list =
  List.filter_map fatal_wellform_message findings

let format (src : string) : (string, string) Result.t =
  match parse_and_check src with
  | Error e -> Error e
  | Ok { cst; findings; _ } ->
    match fatals findings with
    | [] -> Ok (Yc_cst_print.print_program cst)
    | errs -> Error ("wellform: " ^ String.concat "; " errs)

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
