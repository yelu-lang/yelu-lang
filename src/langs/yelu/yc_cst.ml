(* yc_cst — Concrete syntax tree (CST-lite) for yc surface syntax.

   "CST-lite": the AST *shape* enriched with source spans and comments —
   enough to reproduce source (formatter) and map ranges (LSP), but NOT a
   fully lossless tree (the canonical formatter regenerates whitespace).

   Two deliberate choices (see doc/lang/surface_status.md,
   surface_lsp_framework.md §3.2):

   - **Comments are a program-level, span-tagged side list**, not woven
     into nodes. The parser keeps structure and comments separate (pure,
     lossless, no fragile attach-during-parse with backtracking); the
     formatter places comments by comparing spans. (Atom-level spans are a
     later LSP enrichment; v1 keeps spans on statements.)
   - **Commands are uniform** (`S_command {name; args}`); the 14 family
     interpretations + the parse-time atom→expr decisions live in lowering
     (yc_cst_lower, M1.2), one direction only. The type is *closed*, so
     traversals are ppx-derivable. *)

open Base

type span = Yelu_lexer.span [@@deriving sexp_of]

(* Atoms — token-faithful lexemes. Parse-time expr decisions (genex vs
   substitution, int→string, target tagging) move to lowering. *)
type atom =
  | A_name    of string   (* IDENT *)
  | A_string  of string   (* 'single-quoted' body *)
  | A_path    of string   (* "double-quoted" body *)
  | A_eval    of string   (* ${VAR} or $<GENEX>, raw *)
  | A_bool    of bool     (* ON / OFF *)
  | A_int     of int
  | A_keyword of string   (* :PUBLIC *)
  | A_target  of string   (* target NAME *)
  | A_paren   of atom     (* ( atom ) *)
[@@deriving sexp_of]

(* Command arguments — the uniform shape collected for every family. *)
type arg =
  | Pos     of atom
  | Kw      of string * atom       (* ~name:val / ~name val *)
  | Kw_flag of string              (* ~name *)
  | Kw_list of string * atom list  (* ~name:[ a b c ] *)
[@@deriving sexp_of]

(* Conditions — prefix op-applications + infix and/or + paren + bare. *)
type cond =
  | C_app    of string * atom list  (* str_eq a b, defined x, ver_lt a b … *)
  | C_not    of cond
  | C_and    of cond * cond
  | C_or     of cond * cond
  | C_paren  of cond
  | C_target of atom                (* target X exists *)
  | C_expr   of atom                (* bare truthy atom *)
[@@deriving sexp_of]

type flow = Break | Continue | Return [@@deriving sexp_of]

type stmt = { node : stmt_node; span : span }
and stmt_node =
  | S_command  of { name : string; args : arg list }
  | S_assign   of { cache : bool; name : string; values : atom list;
                    kwargs : (string * atom) list; docstring : string option;
                    parent_scope : bool }
  | S_let      of { var : string; ty : string option; value : atom; body : stmt }
  | S_if       of { cond : cond; then_ : block; else_ : else_branch option }
  | S_while    of { cond : cond; body : block }
  | S_foreach  of { var : string; iter : foreach_iter; body : block }
  | S_function of { name : string; params : string list; body : block }
  | S_macro    of { name : string; params : string list; body : block }
  | S_flow     of flow
  | S_block    of block
and else_branch = Else_block of block | Else_if of stmt
and foreach_iter =
  | F_range of { start : int option; stop : int }
  | F_lists of string list
  | F_items of atom list
and block = stmt list
[@@deriving sexp_of]

type comment = { text : string; span : span } [@@deriving sexp_of]

type program = { stmts : stmt list; comments : comment list } [@@deriving sexp_of]
