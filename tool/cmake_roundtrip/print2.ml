(* cmake_roundtrip: typed mapping of Stage-1 untyped cmake AST into
   [Lang_cmake.exp], then reprint via [Lang_cmake_pp].

   Pipeline:
     stdin (Stage-1 JSON from parse.py)
       -> file_of_json     (this file)
       -> parse_cmd        (per-command Lang_cmake.exp when modeled)
       -> Lang_cmake_pp.pp (production cmake printer)
       -> untyped_emit     (verbatim fallback for un-modeled commands)
     stdout: reprinted cmake

   For each Stage-1 [Cmd], [parse_cmd] returns [Some Lang_cmake.exp]
   when the command is one of the modeled builtins, else [None]. The
   None branch routes to [untyped_emit] which constructs a real
   [Lang_cmake.Apply { name; args }] and reprints via the production
   [Lang_cmake_pp] Apply arm. This is the "generic" bucket in
   coverage tallies — correct destination for project- or
   module-defined cmake calls like z3_add_component, tablegen, the
   add_llvm_* family.

   Block shapes (if / foreach / while / function / macro / block)
   walk recursively. The body is a nested statement list reprinted
   by the same dispatcher (modeled / generic / other recursively
   apply). Block heads and tails are NOT dispatched through
   [parse_cmd] today — they're reprinted by [print_block_head] as
   raw `name(args)` text. They contribute to neither the modeled
   nor generic counts; the `other` bucket counts the block wrapper
   node itself (one per block), not its head/tail. Body commands
   inside blocks still count toward modeled / generic via
   recursive walk.

   The byte-equality oracle: tree-sitter on both source and reprint
   must extract the same (command_name, arg-list) sequence (STRUCT),
   and gersemi-normalized both sides must match modulo
   whitespace/comment layout (FORMAT). Both held at 0 across
   tutorial + z3 + llvm as of Stage 2-c. *)


(* The Stage-1 AST + JSON reader + parse_cmd dispatcher are now in
   the library at src/langs/cmake/cmake_text_parse.ml, so other
   consumers (the from_emit bridge for yc-eval, future analysis
   tools) can ingest cmake without copying the dispatcher. The
   round-trip oracle's emission side stays here: untyped_emit,
   print_block_head, emit_stmt, emit, plus the coverage tally
   accounting via STAGE2_COVERAGE and CORPUS_INDEX_FILE /
   CMAKE_STDLIB_INDEX_FILE env vars. *)

open Base
module L = Yelu_langs.Lang_cmake
module Pp = Yelu_langs.Lang_cmake_pp
open Yelu_langs.Cmake_text_parse


(* ============================================================
   Emit: walk Stage-1 AST; typed commands -> Lang_cmake_pp;
   others -> Stage-1 raw emission.
   ============================================================ *)

let pp_exp_to_string (e : L.exp) : string =
  (* Default formatter line width is 80, which causes [Fmt.sp]
     break hints in arms like [Apply] / multi-arg builtins to wrap
     long calls across lines. For the round-trip oracle we want
     single-line output everywhere; gersemi handles the wrap
     downstream (or on the comparison side). Set both max_indent
     and margin to a large value — Format clamps margin to
     max_indent if you only set one. *)
  let buf = Buffer.create 256 in
  let ff = Stdlib.Format.formatter_of_buffer buf in
  Stdlib.Format.pp_set_geometry ff ~max_indent:999_999 ~margin:1_000_000;
  Stdlib.Format.fprintf ff "%a%!" Pp.pp e;
  Buffer.contents buf

let indent depth = String.make (depth * 2) ' '

(* Generic call-by-name. Route un-modeled commands through the real
   [Lang_cmake.Apply] constructor and the production [Lang_cmake_pp]
   Apply printer so the generic path exercises the same IR shape as
   modeled commands. [pp_exp_to_string] sets margin/max-indent high to
   avoid incidental wrapping where the printer permits it, but the
   production Apply printer may still choose a multi-line layout for
   some argument-list shapes. *)
let untyped_emit (c : cmd) : string =
  let args = List.map c.args ~f:arg_of_raw in
  pp_exp_to_string (L.Apply { name = c.name; args })

(* Block heads/tails are not currently dispatched through [parse_cmd]:
   they're free-form command records bound to a block shape, and the
   block walker reprints them as raw text. The args field is already
   the source's raw token sequence (preserved by [parse.py]), so this
   is byte-faithful — but it does mean a head like `if(FOO STREQUAL
   "bar")` is reprinted with whitespace exactly as tree-sitter laid
   it out, with no typed-IR detour. Live with this until block-head
   typing is needed; the STRUCT oracle catches any drift. *)
let print_block_head { name; args } =
  Printf.sprintf "%s(%s)" name (String.concat ~sep:" " args)

let rec emit_stmt ~depth buf = function
  | Cmd c ->
    let s =
      match parse_cmd c with
      | Some exp -> pp_exp_to_string exp
      | None -> untyped_emit c
    in
    Buffer.add_string buf (indent depth);
    Buffer.add_string buf s;
    if not (String.is_suffix s ~suffix:"\n") then Buffer.add_char buf '\n'
  | Block { head; body; clauses; tail; _ } ->
    Buffer.add_string buf (indent depth);
    Buffer.add_string buf (print_block_head head);
    Buffer.add_char buf '\n';
    List.iter body ~f:(emit_stmt ~depth:(depth + 1) buf);
    List.iter clauses ~f:(fun (chead, cbody) ->
      Buffer.add_string buf (indent depth);
      Buffer.add_string buf (print_block_head chead);
      Buffer.add_char buf '\n';
      List.iter cbody ~f:(emit_stmt ~depth:(depth + 1) buf));
    Buffer.add_string buf (indent depth);
    Buffer.add_string buf (print_block_head tail);
    Buffer.add_char buf '\n'
  | Raw text ->
    Buffer.add_string buf text;
    if not (String.is_suffix text ~suffix:"\n") then Buffer.add_char buf '\n'
  | Unknown { ts_type; text } ->
    Buffer.add_string buf (indent depth);
    Buffer.add_string buf
      (Printf.sprintf "# unknown(%s): %s\n" ts_type
         (String.substr_replace_all text ~pattern:"\n" ~with_:"\\n"))

let emit stmts =
  let buf = Buffer.create 1024 in
  List.iter stmts ~f:(emit_stmt ~depth:0 buf);
  Buffer.contents buf

(* ============================================================
   Coverage report (optional, via env var)
   ============================================================ *)

(* Class A Phase 1: two-tier name index — project-local + cmake-stdlib.

   Two TSV files, both produced by project_index.exe (which walks
   any directory looking for [function(<name> ...)] / [macro(...)]
   defs):

     [CORPUS_INDEX_FILE]        — defs found under the corpus root
                                  ("project-defined", `resolved` bucket)
     [CMAKE_STDLIB_INDEX_FILE]  — defs found under cmake's Modules dir
                                  ("cmake-stdlib", `stdlib` bucket)

   cmake call dispatch is case-insensitive, so both sets lowercase
   on insert + lookup.

   Bucket precedence when an [Apply] call name resolves:
     project-first (resolved) > cmake-stdlib (stdlib) > generic.
   Same shape as Python: local `sys.path` entries win over the
   system stdlib. In practice almost no corpus shadows stdlib names,
   so the precedence rarely matters; project-first just makes the
   "what's truly external?" answer cleaner.

   The reprint output is unchanged whether the indices are loaded
   or not. This is purely accounting. *)
let project_set : (string, String.comparator_witness) Set.t ref =
  ref (Set.empty (module String))

let stdlib_set : (string, String.comparator_witness) Set.t ref =
  ref (Set.empty (module String))

let load_set_from_tsv path =
  let ic = Stdlib.open_in path in
  let s = ref (Set.empty (module String)) in
  (try
     while true do
       let line = Stdlib.input_line ic in
       (* Format: <name>\t<file>\t<kind>. Tolerate empty lines. *)
       match String.lsplit2 line ~on:'\t' with
       | Some (name, _) when not (String.is_empty name) ->
         s := Set.add !s (String.lowercase name)
       | _ -> ()
     done
   with Stdlib.End_of_file -> ());
  Stdlib.close_in ic;
  !s

let project_loaded () = not (Set.is_empty !project_set)
let stdlib_loaded () = not (Set.is_empty !stdlib_set)
let any_index_loaded () = project_loaded () || stdlib_loaded ()

(* Coverage tally. Each top-level statement contributes as follows:
   - [Cmd] -> [modeled] if [parse_cmd] returns [Some _], else
     dispatch by name on the loaded indices:
       in [project_set]            -> [resolved]
       in [stdlib_set]              -> [stdlib]
       in neither (or none loaded)  -> [generic]
   - [Block] -> [other] += 1 for the wrapper itself. Body and clause
     bodies recurse: contained [Cmd]s contribute to the same buckets.
     Heads and tails are NOT counted in any bucket (they're reprinted
     by [print_block_head] without dispatch).
   - [Raw] / [Unknown] -> [other] += 1.
   Deliberately no ratio is reported. *)
let count_coverage stmts =
  let modeled = ref 0 in
  let stdlib = ref 0 in
  let resolved = ref 0 in
  let generic = ref 0 in
  let other = ref 0 in
  let rec walk = function
    | Cmd c ->
      (match parse_cmd c with
       | Some _ -> Int.incr modeled
       | None ->
         let key = String.lowercase c.name in
         if project_loaded () && Set.mem !project_set key then Int.incr resolved
         else if stdlib_loaded () && Set.mem !stdlib_set key then Int.incr stdlib
         else Int.incr generic)
    | Block { body; clauses; _ } ->
      Int.incr other;
      List.iter body ~f:walk;
      List.iter clauses ~f:(fun (_, b) -> List.iter b ~f:walk)
    | Raw _ | Unknown _ -> Int.incr other
  in
  List.iter stmts ~f:walk;
  !modeled, !stdlib, !resolved, !generic, !other

(* ============================================================
   Driver
   ============================================================ *)

let read_all_stdin () =
  let buf = Buffer.create 4096 in
  let chunk = Bytes.create 4096 in
  let rec loop () =
    let n = Stdlib.input Stdlib.stdin chunk 0 (Bytes.length chunk) in
    if n > 0 then (Buffer.add_subbytes buf chunk ~pos:0 ~len:n; loop ())
  in
  loop ();
  Buffer.contents buf

let () =
  (* Load name indices (Class A Phase 1). Either, both, or neither
     may be set; the bucket shape adapts. *)
  (match Sys.getenv "CORPUS_INDEX_FILE" with
   | Some path when Stdlib.Sys.file_exists path ->
     project_set := load_set_from_tsv path
   | _ -> ());
  (match Sys.getenv "CMAKE_STDLIB_INDEX_FILE" with
   | Some path when Stdlib.Sys.file_exists path ->
     stdlib_set := load_set_from_tsv path
   | _ -> ());
  let json_str = read_all_stdin () in
  let json = Yojson.Safe.from_string json_str in
  let stmts = file_of_json json in
  (match Sys.getenv "STAGE2_COVERAGE" with
   | Some _ ->
     let m, s, r, g, o = count_coverage stmts in
     if any_index_loaded () then
       Stdlib.Printf.eprintf
         "[stage2] modeled=%d stdlib=%d resolved=%d generic=%d other=%d\n"
         m s r g o
     else
       Stdlib.Printf.eprintf
         "[stage2] modeled=%d generic=%d other=%d\n" m g o
   | None -> ());
  Stdlib.print_string (emit stmts)
