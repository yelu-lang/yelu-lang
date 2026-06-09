(* Yc_wellform — escape and reserved-name checks for yelu_cmake.

   Three independent check functions, each a pure walk over the IR:
   1. check_reserved_names — EVar names must not collide with reserved
      keywords or typed primitive command names.
   2. check_apply_shadowing — ECmakeApply must not use a name that
      has a typed yc API.
   3. check_raw_tainted — ECmakeRaw sites are flagged.

   The walk recurses through the major structural nodes (ESeq, ELet,
   ECmakeIfStmt, ECmakeApply) and falls through to identity for
   all other constructors. This is intentionally shallow — surface
   constructors that carry names (ECmakeFunction, ECmakeFindProgram,
   etc.) are not yet checked; they can be added as the fragments
   are properly catalogued. *)

open Base
open Yelu_cmake
open Yelu_cmake_if
open Yelu_cmake_store
open Yelu_cmake_cmake_op

(* ── Error type ────────────────────────────────── *)

type error =
  | Reserved_name of {
      name : string;
      context : string;
      conflict : string;
    }
  | Apply_shadows_primitive of {
      name : string;
    }
  | Raw_cmake_escape of { text : string; reason : string }
[@@deriving sexp_of]

let classify_escape text =
  if String.is_prefix text ~prefix:"install(" then "complex install command"
  else if String.is_substring text ~substring:"${kind}" then "dynamic visibility"
  else if String.is_substring text ~substring:"yc_raw" then "explicit yc_raw escape"
  else if String.is_prefix text ~prefix:"get_target_property("
       || String.is_prefix text ~prefix:"set_property("
       || String.is_prefix text ~prefix:"path_convert_to_native"
  then "typed API gap (parser missing)"
  else "untyped cmake primitive"

let format_raw_escape ?(index = 0) file text reason =
  let lines = String.split_lines text in
  let body =
    if List.length lines <= 3 then
      String.concat ~sep:"\n        " lines
    else
      Printf.sprintf "%s\n        ... (%d more lines)"
        (String.concat ~sep:"\n        " (List.take lines 2))
        (List.length lines - 2)
  in
  Printf.sprintf "[yelu][emit][warning][%d] %s [%s]:\n        %s"
    index file reason body

(* ── Recursion helper ──────────────────────────── *)

(* Walk the immediate sub-expressions of [e], applying [f] to each.
   Only recurses through the major structural nodes; constructors
   from fragments that aren't explicitly handled are skipped.
   This is intentionally conservative — we don't want to silently
   miss a constructor, but we also don't want the wellform module
   to break every time a fragment adds a field. *)
let walk_children (f : error list -> expr -> error list) (acc : error list) (e : expr) : error list =
  match e with
  | ESeq es -> List.fold es ~init:acc ~f
  | ELet { value; body; _ } -> f (f acc value) body
  | ESetVar (_, v) -> f acc v
  | ECmakeIfStmt { cond; then_; else_ } ->
    let acc = f acc cond in
    let acc = f acc then_ in
    (match else_ with Some e -> f acc e | None -> acc)
  | ECmakeFunction { body; _ } -> f acc body
  | ECmakeMacro { body; _ } -> f acc body
  | ECmakeApply { args; _ } -> List.fold args ~init:acc ~f
  (* Option / SetCache — carry expr values *)
  | ECmakeOption { value; _ } -> f acc value
  | ECmakeSetCache { values; _ } -> List.fold values ~init:acc ~f
  | ECmakeSetParentScope { value; _ } -> f acc value
  | ECmakeSetEnvVar { value; _ } -> f acc value
  (* Unknown — stop, don't recurse *)
  | _ -> acc

(* ── check_reserved_names ──────────────────────── *)

let check_reserved_names e =
  let rec walk acc e =
    let acc = match e with
      | EVar name ->
        if Yc_primitives.is_reserved name then
          let conflict = if Yc_primitives.is_known_command name
            then "typed primitive" else "reserved keyword"
          in
          Reserved_name { name; context = "variable"; conflict } :: acc
        else acc
      | ECmakeFunction { name; _ } | ECmakeMacro { name; _ } ->
        let n = match name with EString s | EVar s -> s | _ -> "" in
        if Yc_primitives.is_reserved n then
          Reserved_name { name = n; context = "function";
                          conflict = "reserved keyword" } :: acc
        else acc
      | _ -> acc
    in
    walk_children walk acc e
  in
  walk [] e

(* ── check_apply_shadowing ─────────────────────── *)

let check_apply_shadowing e =
  let rec walk acc e =
    let acc = match e with
      | ECmakeApply { name; _ } ->
        let n = match name with EString s | EVar s -> s | _ -> "" in
        if Yc_primitives.is_known_command n then
          Apply_shadows_primitive { name = n } :: acc
        else acc
      | _ -> acc
    in
    walk_children walk acc e
  in
  walk [] e

(* ── check_raw_tainted ─────────────────────────── *)

let check_raw_tainted e =
  let rec walk acc e =
    let acc = match e with
      | ECmakeRaw text ->
        Raw_cmake_escape { text; reason = classify_escape text } :: acc
      | _ -> acc
    in
    walk_children walk acc e
  in
  walk [] e

(* ── Public API ────────────────────────────────── *)

let check_all e =
  check_reserved_names e
  @ check_apply_shadowing e
  @ check_raw_tainted e
