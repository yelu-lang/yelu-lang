# doc/archive — resolved / historical write-ups

Docs kept for the record but no longer part of the live documentation set:
resolved bug stories, superseded design notes. Nothing here describes current
behavior — treat every file as a snapshot of when it was written.

For current docs start at [`../status.md`](../status.md) (in-flight),
[`../project_overview.md`](../project_overview.md) (audit + doc index), or the
per-area trackers listed there.

Contents:

- `bug_kwarg_at_end.md` — `~label:value` lexed as `~flag` + stray KEYWORD (fixed).
- `bug_nested_genex.md` — nested `$<…>` genex; an OCaml-combinator evaluation-order story (fixed).
- `bug_target_keyword.md` — TARGET keyword token in expression position (fixed).
- `concrete_syntax_parser.md` — the **retired token-level parser** (Angstrom lexer → `token list` → pure OCaml parser), deleted in Tier (b). Kept for the two-pass rationale + the Angstrom gotchas. Its "Surface syntax (current)" example is pre-`~`-half and no longer valid. Current parser: `lang/surface_lsp_framework.md` §8.

The chronological history of shipped work lives in
[`../worklog/`](../worklog/), not here.
