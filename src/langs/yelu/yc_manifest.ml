(* Yc_manifest — the vocabulary co-truth for yc surface syntax.

   One typed table of every yc lexical token, partitioned by lexical
   class, each carrying a TextMate scope. This is the single source the
   TextMate-grammar generator (surface Milestone 0) consumes, and it is
   test-locked to the other *enumerable* providers — [Yc_primitives]
   (command_names + reserved_names) and [Yelu_lexer.reserved] — by
   [test/test-yelu/test_yc_manifest.ml].

   Design rationale and the broader plan live in
   [doc/lang/surface_lsp_framework.md] Sec 3.8. In short: a TextMate
   grammar is a *scanner*, so its natural co-truth is the lexical
   vocabulary (this module), not the parser; the parser stays the sole
   authority on syntax. We cannot derive this table by reflecting over
   [Yelu_cmake.expr] (it is an *extensible* variant — ppx derivers do not
   see open variants spread across fragments), so the table is curated
   and locked to the providers by test, rather than generated from the
   AST. *)

open Base

type lexical_class =
  | Command          (* string_concat, list_append, add_lib  *)
  | Control_keyword  (* let, in, if, then, else, foreach, ... *)
  | Type_keyword     (* target, cvar, cache                   *)
  | Bool_literal     (* ON, OFF                               *)
  | Cond_operator    (* not, and, or, str_eq, ver_lt, ...     *)
  | Enum_constructor (* Public, Private, Static, Name_we, ... *)
  | Punctuation      (* := = ~ .. ( ) { } [ ] , ; :           *)
[@@deriving equal, sexp_of]

type entry = {
  surface       : string;
  (* AST-link column. [None] for now: the surface→constructor map
     (e.g. "string_concat" → ECmakeStringConcat) is a real co-truth, but
     it is not machine-checkable today — extensible variants cannot be
     enumerated without ppx, so a hand-typed column would be unverified
     documentation. The field is kept so the schema is stable; it gets
     populated (and test-locked) when the semantic layer / Y17 makes the
     AST link load-bearing. See surface_lsp_framework.md Sec 3.8. *)
  ctor          : string option;
  lexical_class : lexical_class;
  tm_scope      : string;
}
[@@deriving sexp_of]

(* Default TextMate scope per class. Entries may override [tm_scope];
   punctuation does, because each delimiter wants its own scope. *)
let default_scope = function
  | Command         -> "support.function.yc"
  | Control_keyword -> "keyword.control.yc"
  | Type_keyword    -> "storage.type.yc"
  | Bool_literal    -> "constant.language.boolean.yc"
  | Cond_operator   -> "keyword.operator.word.yc"
  | Enum_constructor -> "constant.language.yc"
  | Punctuation     -> "punctuation.yc"

let mk ?ctor lexical_class surface =
  { surface; ctor; lexical_class; tm_scope = default_scope lexical_class }

(* Commands ride on [Yc_primitives.command_names] — one class and scope
   for all of them, so the ~140 names are not re-typed here. The manifest
   contributes the *classification* (these are commands → support.function);
   command membership stays sourced from yc_primitives until the AST/typed
   IR becomes the generation root (see surface_lsp_framework.md). *)
let command_entries =
  Set.to_list Yc_primitives.command_names |> List.map ~f:(mk Command)

(* The keyword / operator partition — the manifest's own curated
   contribution. Test-locked to (reserved_names \ command_names). *)
let control_keywords =
  [ "let"; "in"; "if"; "then"; "else"; "foreach"; "RANGE";
    "function"; "fun"; "macro"; "while"; "break"; "continue"; "return" ]
  |> List.map ~f:(mk Control_keyword)

let type_keywords =
  [ "target"; "Target"; "cvar"; "Cvar"; "cache" ]
  |> List.map ~f:(mk Type_keyword)

let bool_literals =
  [ "ON"; "OFF" ] |> List.map ~f:(mk Bool_literal)

(* Enum constructors ride on [Yelu_lexer.constr_names] (the lexer's truth for
   which capitalized words are enum choices), so the highlighter can never list
   an enum the lexer doesn't accept, or vice-versa. The surface is the
   leading-cap spelling (`PUBLIC` → `Public`). Test-locked in
   test_yc_manifest. *)
let enum_constructors =
  Set.to_list Yelu_lexer.constr_names
  |> List.map ~f:(fun u -> mk Enum_constructor (String.capitalize (String.lowercase u)))

let cond_operators =
  [ "not"; "and"; "or"; "str_eq"; "str_lt"; "str_gt";
    "eq"; "lt"; "gt"; "ver_lt"; "ver_gt"; "ver_eq";
    "match"; "list_in"; "exists"; "is_dir"; "is_abs";
    "defined"; "policy" ]
  |> List.map ~f:(mk Cond_operator)

(* Symbolic punctuation / operators — sourced from [Yelu_lexer]'s
   delimiter tokens. Not in reserved_names (those are word identifiers),
   so they are enumerated here with per-token scopes. *)
let punctuation =
  [ ":=", "keyword.operator.assignment.yc";
    "=",  "keyword.operator.assignment.yc";
    "~",  "keyword.operator.yc";
    "..", "keyword.operator.range.yc";
    ":",  "punctuation.separator.yc";
    ",",  "punctuation.separator.yc";
    ";",  "punctuation.terminator.yc";
    "(",  "punctuation.section.parens.begin.yc";
    ")",  "punctuation.section.parens.end.yc";
    "{",  "punctuation.section.braces.begin.yc";
    "}",  "punctuation.section.braces.end.yc";
    "[",  "punctuation.section.brackets.begin.yc";
    "]",  "punctuation.section.brackets.end.yc" ]
  |> List.map ~f:(fun (surface, tm_scope) ->
       { surface; ctor = None; lexical_class = Punctuation; tm_scope })

let all : entry list =
  command_entries @ control_keywords @ type_keywords
  @ bool_literals @ cond_operators @ enum_constructors @ punctuation

(* ── Accessors for the generator + driver introspection ── *)

let by_class cls =
  List.filter all ~f:(fun e -> equal_lexical_class e.lexical_class cls)

let surfaces_of_class cls = List.map (by_class cls) ~f:(fun e -> e.surface)

(* Word-classes are everything except [Punctuation] — these are the
   `\b`-bounded identifier-like tokens the grammar renders as `\b(…)\b`
   rules. [Enum_constructor] is a word class too (it gets a `\b` rule), but
   it is sourced from a *different* provider ([Yelu_lexer.constr_names]), so
   it is excluded from [word_surfaces] — the reserved-backed set the lock
   test pins to [Yc_primitives.reserved_names]. *)
let is_word_class = function Punctuation -> false | _ -> true

let is_reserved_backed cls =
  is_word_class cls && not (equal_lexical_class cls Enum_constructor)

let word_surfaces =
  List.filter_map all ~f:(fun e ->
    if is_reserved_backed e.lexical_class then Some e.surface else None)

(* Enum-constructor surfaces, locked to [Yelu_lexer.constr_names]. *)
let constr_surfaces = surfaces_of_class Enum_constructor

(* A single-line textual dump, for the driver `manifest` op / `yelu
   manifest` CLI. One row per entry: surface<TAB>class<TAB>tm_scope. *)
let to_lines () =
  List.map all ~f:(fun e ->
    let cls =
      Sexp.to_string (sexp_of_lexical_class e.lexical_class) in
    Printf.sprintf "%s\t%s\t%s" e.surface cls e.tm_scope)
