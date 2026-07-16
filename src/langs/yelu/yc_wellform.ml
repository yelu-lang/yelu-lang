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
open Yelu_cmake_find
open Yelu_cmake_dir

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
  (* Y14 — a variable declaration whose name shadows an enum constructor
     (case-insensitively). Fatal at the compile boundary (see compile_yc);
     the capitalized form is already blocked at the lexer, this catches the
     lowercase/mixed shadow (`set public := …`). See casing_design.md. *)
  | Enum_shadow of { name : string; constructor : string }
  | Raw_cmake_escape of { text : string; reason : string }
  (* Labeled-only (Step 2): a known command written in the *positional*
     cmake-keyword form (`install_targets … LIBRARY DESTINATION …`). Tagged by
     the parser (`ECmakeRawCmd.from_positional`); fatal at the compile boundary
     — use the `~label=` form or `yc_raw '…'`. See surface_status.md. *)
  | Positional_form of { command : string }
  (* Labeled-only follow-up (audit 2026-07): a `~kwarg` on a KNOWN command that
     the command does not accept. The parser reads only the keys it knows and
     silently drops the rest — `link_lib foo ~public=['bar']` emitted
     `target_link_libraries(foo PRIVATE )` with the libraries discarded, exit 0.
     Fatal at the compile boundary; vocabulary in
     [Yc_primitives.command_kwargs] / [allowed_kwarg]. Unknown/user commands
     are exempt (open vocabulary). CST-level (kwargs are consumed by lowering). *)
  | Unknown_kwarg of { command : string; key : string }
  (* A command name that is neither in [Yc_primitives.command_names] nor
     declared as a [function]/[macro] in this file. Catches typos
     (`funnn` for `fun`, `prejct` for `project`) and surfaces "this is
     defined elsewhere?" hints. Severity depends on [closed_world]:

     - [closed_world = true]: the file contains NO opening construct
       (no [include] / [find_package] / [add_subdirectory] / dynamic
       [cmake_call]/[cmake_eval] / non-literal-name [function]/[macro]).
       The command set is statically closed → the unknown name MUST be
       a typo. Treated as fatal at the compile boundary.
     - [closed_world = false]: the file has at least one opening
       construct, so the command set is genuinely open. Treated as a
       warning; suppress noisy true-positives via [yc_raw '…'] or by
       defining the helper in-file. *)
  | Unknown_command of { name : string; closed_world : bool }
  (* The function-definition typo shape: a command call adjacent to a
     standalone block at the same nesting level — `IDENT args (block)`
     where IDENT is not a known command or in-file decl. There is no
     legitimate cmake/yc reading of that shape (real commands don't take
     a trailing block; control flow goes through dedicated CST variants
     S_if / S_foreach / S_function / S_macro etc.), so it's always a
     `fun`/`function`/`macro` keyword typo. Fatal regardless of
     open-/closed-world — the shape is the signal, not the name. *)
  | Function_def_typo of { name : string; closed_world : bool }
[@@deriving sexp_of]

let classify_escape text =
  if String.is_substring text ~substring:"${kind}"
  then "dynamic visibility (by design)"
  else if String.is_prefix text ~prefix:"install(" then "complex install"
  else if String.is_prefix text ~prefix:"get_target_property("
       || String.is_prefix text ~prefix:"set_property("
       || String.is_prefix text ~prefix:"path_convert_to_native"
  then "typed API gap"
  else "raw cmake text"

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
  | ECmakeRawCmd { args; _ } -> List.fold args ~init:acc ~f
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
  let chk name context acc =
    if Yc_primitives.is_reserved name then
      let conflict = if Yc_primitives.is_known_command name
        then "typed primitive" else "reserved keyword"
      in
      Reserved_name { name; context; conflict } :: acc
    else acc
  in
  let rec walk acc e =
    let acc = match e with
      | EVar name -> chk name "variable" acc
      | ECmakeFunction { name; _ } | ECmakeMacro { name; _ } ->
        let n = match name with EString s | EVar s -> s | _ -> "" in
        if Yc_primitives.is_reserved n then
          Reserved_name { name = n; context = "function";
                          conflict = "reserved keyword" } :: acc
        else acc
      (* Declaration sites (audit #4): a var / cache / option / let DECLARED
         with a reserved name previously slipped through — only *references*
         were checked, unlike check_enum_shadow which covers declarations.
         Same sites as the enum-shadow walk; warning severity (Y14's hard
         reject stays scoped to enum constructors — casing_design.md). *)
      | ESetVar (name, _) -> chk name "variable declaration" acc
      | ECmakeSetParentScope { name; _ } -> chk name "variable declaration" acc
      | ECmakeSetCache { name; _ } -> chk name "cache declaration" acc
      | ECmakeOption { name; _ } -> chk name "option declaration" acc
      | ELet { var; _ } -> chk var "let binding" acc
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

(* ── check_enum_shadow (Y14) ───────────────────── *)

(* A variable / cache / option / let DECLARATION must not shadow an enum
   constructor: `set public := …` reads as the `Public` choice and is always
   a mistake. Case-insensitive ([is_known_constr] uppercases); the capitalized
   `set Public` is already a parse error (the lexer tokenizes `Public` as the
   KEYWORD), so together no variable can shadow an enum in any case. *)
let check_enum_shadow e =
  let chk name acc =
    if Yelu_lexer.is_known_constr name
    then
      Enum_shadow
        { name; constructor = String.capitalize (String.lowercase name) }
      :: acc
    else acc
  in
  let rec walk acc e =
    let acc =
      match e with
      | ESetVar (name, _) -> chk name acc
      | ECmakeSetParentScope { name; _ } -> chk name acc
      | ECmakeSetCache { name; _ } -> chk name acc
      | ECmakeOption { name; _ } -> chk name acc
      | ELet { var; _ } -> chk var acc
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
      | ECmakeRawCmd { from_positional = Some command; _ } ->
        Positional_form { command } :: acc
      | _ -> acc
    in
    walk_children walk acc e
  in
  walk [] e

(* ── check_unknown_command ─────────────────────── *)

(* Walk to collect literal `function NAME`/`macro NAME` declarations.
   Dynamic names (`function ${var}(…)`) are skipped — we can only
   statically know literal-string names. Inline structural recursion
   because [walk_children] is monomorphic in [error list]. *)
let collect_defined_names (e : expr) : Set.M(String).t =
  let rec walk acc e =
    let acc = match e with
      | ECmakeFunction { name = (EString s | EVar s); _ }
      | ECmakeMacro    { name = (EString s | EVar s); _ } ->
        Set.add acc (String.lowercase s)
      | _ -> acc
    in
    match e with
    | ESeq es -> List.fold es ~init:acc ~f:walk
    | ELet { value; body; _ } -> walk (walk acc value) body
    | ESetVar (_, v) -> walk acc v
    | ECmakeIfStmt { cond; then_; else_ } ->
      let acc = walk acc cond in
      let acc = walk acc then_ in
      (match else_ with Some e -> walk acc e | None -> acc)
    | ECmakeFunction { body; _ } -> walk acc body
    | ECmakeMacro { body; _ } -> walk acc body
    | ECmakeRawCmd { args; _ } -> List.fold args ~init:acc ~f:walk
    | ECmakeApply { args; _ } -> List.fold args ~init:acc ~f:walk
    | ECmakeOption { value; _ } -> walk acc value
    | ECmakeSetCache { values; _ } -> List.fold values ~init:acc ~f:walk
    | ECmakeSetParentScope { value; _ } -> walk acc value
    | ECmakeSetEnvVar { value; _ } -> walk acc value
    | _ -> acc
  in
  walk (Set.empty (module String)) e

(* Flag generic-fallback command calls whose name is neither in the
   typed primitive set nor declared as a function/macro in this file.
   Catches typos (`funnn`, `prejct`) while preserving cmake's open call
   ecosystem — the warning is **not fatal**, so cross-file user-defined
   helpers and cmake-stdlib calls (`cmake_parse_arguments`,
   `qt6_add_executable`, …) still build. Suppress legitimate but noisy
   ones via `yc_raw '…'`. The [from_positional = None] guard excludes
   the Step-2-rejected positional form, which is already flagged as
   [Positional_form] above (avoid double-flagging). *)
(* Detect any "opening construct" that introduces command names this file
   cannot statically see:
   - [include "Foo.cmake"] — runs the module's cmake, may define commands
   - [find_package Foo] — same via FooConfig.cmake
   - [add_subdirectory d] — runs d/CMakeLists.txt
   - [cmake_call ${cmd} args] / [cmake_eval CODE …] — invokes a command
     whose name is dynamic, or evaluates arbitrary cmake text
   - [function ${var}(…)] / [macro ${var}(…)] — defines a command whose
     name is computed at runtime (non-literal name field)

   The presence of any such construct keeps Unknown_command at warning
   class; the absence escalates it to fatal — the command set is then
   statically closed, so an unknown name MUST be a typo. *)
let has_opening_construct (e : expr) : bool =
  let rec walk e =
    match e with
    (* Typed opening commands. *)
    | ECmakeInclude _ -> true
    | ECmakeFindPackage _ -> true
    | ECmakeAddSubdirectory _ -> true
    | ECmakeLanguageCall _ -> true
    (* Dynamic name in function/macro definition. *)
    | ECmakeFunction { name = (EString _ | EVar _); body; _ }
    | ECmakeMacro    { name = (EString _ | EVar _); body; _ } -> walk body
    | ECmakeFunction _ | ECmakeMacro _ -> true
    (* Recurse through structural nodes. *)
    | ESeq es -> List.exists es ~f:walk
    | ELet { value; body; _ } -> walk value || walk body
    | ESetVar (_, v) -> walk v
    | ECmakeIfStmt { cond; then_; else_ } ->
      walk cond || walk then_
      || (match else_ with Some e -> walk e | None -> false)
    | ECmakeRawCmd { args; _ } | ECmakeApply { args; _ } ->
      List.exists args ~f:walk
    | ECmakeOption { value; _ } -> walk value
    | ECmakeSetCache { values; _ } -> List.exists values ~f:walk
    | ECmakeSetParentScope { value; _ } -> walk value
    | ECmakeSetEnvVar { value; _ } -> walk value
    | _ -> false
  in
  walk e

let check_unknown_command e =
  let defined = collect_defined_names e in
  let closed_world = not (has_opening_construct e) in
  let check_name n acc =
    let nl = String.lowercase n in
    (* Three-tier lookup:
       1. yc typed primitives (Yc_primitives.command_names)
       2. in-file function/macro declarations (whole-program collect)
       3. cmake stdlib (discovered-cache; see doc/yelu_cmake/discovered_cache.md)
       A name in any of these is silent; only true unknowns flow through. *)
    if Yc_primitives.is_known_command nl
    || Set.mem defined nl
    || Cmake_stdlib_names.mem nl
    then acc
    else Unknown_command { name = n; closed_world } :: acc
  in
  let rec walk acc e =
    let acc = match e with
      (* Generic command dispatcher path: an unknown IDENT-headed call
         becomes [ECmakeApply { name = EString id; _ }] in [p_generic_
         command_y1]. A *known* command name on an ECmakeApply is the
         escape-shadowing case caught by [check_apply_shadowing] above —
         we only flag the unknown case here. *)
      | ECmakeApply { name = (EString s | EVar s); _ } ->
        check_name s acc
      (* Some family branches reach the raw fallback as ECmakeRawCmd
         instead. The Step-2 positional-form rejects (from_positional =
         Some) are flagged separately by [check_raw_tainted] — skip
         those to avoid double-flagging. *)
      | ECmakeRawCmd { name; from_positional = None; _ } ->
        check_name name acc
      | _ -> acc
    in
    walk_children walk acc e
  in
  walk [] e

(* ── Public API ────────────────────────────────── *)

let check_all e =
  check_reserved_names e
  @ check_apply_shadowing e
  @ check_enum_shadow e
  @ check_raw_tainted e
  @ check_unknown_command e

(* ── CST-level check: function-definition typo shape ────────

   Detect `IDENT args (block)` adjacent statements at the same nesting
   level — almost always a typo'd `fun`/`function`/`macro` keyword. The
   shape lives at the CST level (S_command + S_block); after lowering
   it becomes an opaque ESeq, so the check runs on the CST directly.

   Called by [Yc_driver.format] and the LSP server's diagnostic feed,
   parallel to [check_all] which runs on the lowered expr. *)

let collect_cst_defined_names (p : Yc_cst.program) : Set.M(String).t =
  let rec walk_stmt acc (s : Yc_cst.stmt) =
    let acc = match s.node with
      | S_function { name; _ } | S_macro { name; _ } ->
        Set.add acc (String.lowercase name)
      | _ -> acc
    in
    walk_into acc s.node
  and walk_into acc = function
    | S_if { then_; else_; _ } ->
      let acc = List.fold then_ ~init:acc ~f:walk_stmt in
      (match else_ with
       | Some (Else_block b) -> List.fold b ~init:acc ~f:walk_stmt
       | Some (Else_if s) -> walk_stmt acc s
       | None -> acc)
    | S_while { body; _ } | S_foreach { body; _ }
    | S_function { body; _ } | S_macro { body; _ } ->
      List.fold body ~init:acc ~f:walk_stmt
    | S_block b -> List.fold b ~init:acc ~f:walk_stmt
    | _ -> acc
  in
  List.fold p.stmts ~init:(Set.empty (module String)) ~f:walk_stmt

(* ── CST-level check: unknown `~kwarg` on a known command ────────
   Runs on the CST because kwargs are consumed by lowering (each _inner reads
   the keys it knows and the rest vanish). Known commands only — unknown/user
   commands have an open vocabulary. Covers S_command and the `:=` command-call
   sugar (S_assign_call). Vocabulary: [Yc_primitives.allowed_kwarg]. *)
let check_cst_kwargs (p : Yc_cst.program) : error list =
  let check_args acc name (args : Yc_cst.arg list) =
    let command = String.lowercase name in
    if not (Yc_primitives.is_known_command command) then acc
    else
      List.fold args ~init:acc ~f:(fun acc (a : Yc_cst.arg) ->
        match a with
        | Kw (k, _) | Kw_flag k | Kw_list (k, _)
          when not (Yc_primitives.allowed_kwarg ~command k) ->
          Unknown_kwarg { command; key = k } :: acc
        | _ -> acc)
  in
  let rec walk_stmt acc (s : Yc_cst.stmt) =
    let acc = match s.node with
      | S_command { name; args } -> check_args acc name args
      | S_assign_call { cmd_name; cmd_args; _ } ->
        check_args acc cmd_name cmd_args
      | _ -> acc
    in
    walk_into acc s.node
  and walk_into acc = function
    | S_if { then_; else_; _ } ->
      let acc = List.fold then_ ~init:acc ~f:walk_stmt in
      (match else_ with
       | Some (Else_block b) -> List.fold b ~init:acc ~f:walk_stmt
       | Some (Else_if s) -> walk_stmt acc s
       | None -> acc)
    | S_while { body; _ } | S_foreach { body; _ }
    | S_function { body; _ } | S_macro { body; _ } ->
      List.fold body ~init:acc ~f:walk_stmt
    | S_block b -> List.fold b ~init:acc ~f:walk_stmt
    | S_let { body; _ } -> walk_stmt acc body
    | _ -> acc
  in
  List.rev (List.fold p.stmts ~init:[] ~f:walk_stmt)

(* CST-side open-world signal — mirror of [has_opening_construct] for what the
   CST can express: an opener command makes the file's command set open (a
   cross-file function could define the "unknown" name). Dynamic fun/macro
   names are not CST-expressible (S_function carries a literal string), so the
   command openers are the complete CST-side set. *)
let cst_has_opening_construct (p : Yc_cst.program) : bool =
  let is_opener n =
    List.mem [ "include"; "find_package"; "add_subdirectory"; "cmake_call" ]
      (String.lowercase n) ~equal:String.equal
  in
  let rec walk_stmt (s : Yc_cst.stmt) =
    match s.node with
    | S_command { name; _ } -> is_opener name
    | S_assign_call { cmd_name; _ } -> is_opener cmd_name
    | S_if { then_; else_; _ } ->
      List.exists then_ ~f:walk_stmt
      || (match else_ with
          | Some (Else_block b) -> List.exists b ~f:walk_stmt
          | Some (Else_if s) -> walk_stmt s
          | None -> false)
    | S_while { body; _ } | S_foreach { body; _ }
    | S_function { body; _ } | S_macro { body; _ } ->
      List.exists body ~f:walk_stmt
    | S_block b -> List.exists b ~f:walk_stmt
    | S_let { body; _ } -> walk_stmt body
    | _ -> false
  in
  List.exists p.stmts ~f:walk_stmt

let check_cst (p : Yc_cst.program) : error list =
  let defined = collect_cst_defined_names p in
  let closed_world = not (cst_has_opening_construct p) in
  let is_known n =
    let nl = String.lowercase n in
    Yc_primitives.is_known_command nl || Set.mem defined nl
  in
  let rec walk_block acc (stmts : Yc_cst.stmt list) =
    match stmts with
    | { node = S_command { name; args = _ }; _ }
      :: ({ node = S_block _; _ } :: _ as rest) when not (is_known name) ->
      (* The smoking gun: unknown command IMMEDIATELY followed by a
         standalone block at the same level. Escalation mirrors
         Unknown_command (audit #4): closed world → fatal (the shape can only
         be a typo'd fun/function/macro); open world → warning (the name may
         be a cross-file command legitimately followed by a block). *)
      let acc = Function_def_typo { name; closed_world } :: acc in
      walk_block acc rest
    | s :: rest ->
      let acc = walk_into acc s.node in
      walk_block acc rest
    | [] -> acc
  and walk_into acc = function
    | S_if { then_; else_; _ } ->
      let acc = walk_block acc then_ in
      (match else_ with
       | Some (Else_block b) -> walk_block acc b
       | Some (Else_if s) -> walk_into acc s.node
       | None -> acc)
    | S_while { body; _ } | S_foreach { body; _ }
    | S_function { body; _ } | S_macro { body; _ } -> walk_block acc body
    | S_block b -> walk_block acc b
    | _ -> acc
  in
  List.rev (walk_block [] p.stmts) @ check_cst_kwargs p
