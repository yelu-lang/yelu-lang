# Surface / formatter / LSP — implementation status

> Living tracker for the yc surface-syntax track: highlighter → formatter
> → language server. Design + decision-map in
> [`surface_lsp_framework.md`](surface_lsp_framework.md). Sibling to
> [`../yelu_cmake/status.md`](../yelu_cmake/status.md) (which tracks the
> behavior-level oracle, the *dynamic*-semantics half).

## Current state (2026-06-10)

- **Milestone 0 — TextMate highlighter — shipped.** `yc_primitives` +
  lexer → `Yc_manifest` (co-truth) → `Yc_driver.manifest` → `Yc_tmgrammar`
  → `yelu tmgrammar` → `editors/vscode/yc/`. Drift-guarded
  (`make tmgrammar-check`), verified on `probes/fmt/main.yc` with the real
  TextMate engine. Detail in `surface_lsp_framework.md` § Milestone 0.
- **Milestone 1 / lexer — lossless located scanner — shipped.**
  `Yelu_lexer.lex_located : string -> ((token * span) list, string) result`
  preserves `#` comments as `COMMENT` trivia and tags each token with a
  span. Non-breaking: `skip` moved from the per-token wrapper into the
  `token_list` assembly, so the existing parser path is byte-identical
  (`lex_located` minus comments ≡ `token_list`, test-locked). Tests in
  `test/test-yelu/test_yelu_lex_located.ml`.

## Target architecture

```
text ──parse──▶ cst_lite ──lower──▶ expr  (eval / check / emit — unchanged)
                  ▲   │
        print_ye  │   │   cst_lite = AST shape + comments + spans
                  └───┘   (Prettier/ESTree "CST-lite", NOT a fully lossless
   formatter: generic over cst_lite        tree — the canonical formatter
   except ~6 structural forms              regenerates whitespace)
```

- **Commands are uniform** at the CST: `name atom* ;` → one generic
  parse rule + one generic print rule. The 140-way per-command mapping
  (`policy_set CMP0074 NEW` → `yc_policy_set ~new_:true "CMP0074"`) lives
  only in `lower` — one direction, no printer mirror.
- **`print_ye` mirrors `parse` over the ~6 bespoke forms only**
  (`if/then/else`, `let … in`, `:=`, blocks `( … )`, `foreach`,
  conditions), locked by the round-trip oracle.
- The `cst_lite` type is **closed** (unlike `expr`), so traversals/visitors
  are ppx-derivable — useful for the printer's trivia handling and LSP
  node-walking.

## Migration strategy — parallel build + emit-level bridge

Do **not** fork the parser. Build the CST path beside the proven AST path,
lock them with an oracle, then retire the direct AST parse:

1. parser emits `cst_lite` (transitionally alongside the current AST);
   `lower : cst_lite -> expr`.
2. **bridge oracle:** over the whole corpus,
   `emit (lower (parse_cst text)) == emit (parse_ast text)` — reuse the
   existing byte-equality emit oracle (`covered=194`), **not** structural
   `expr` equality (awkward on the extensible variant).
3. once green corpus-wide, relocate the per-command construction from the
   parser into `lower`, retire `parse_ast`; production path becomes
   `text → cst_lite → lower → expr`.

This is the layered architecture executed safely; the emit-bridge is the
same retirement discipline as the yelu_cmake byte oracle.

## Phases

| phase | what | status |
| ----- | ---- | ------ |
| M0    | TextMate highlighter | ✅ shipped 2026-06-10 |
| M1.0  | lexer: lossless located scanner (`lex_located`) | ✅ shipped 2026-06-10 |
| M1.1  | `cst_lite` type + parser `text → cst_lite` (consume `lex_located`) | ✅ shipped 2026-06-10 (parses all 11 fmt .yc) |
| M1.2  | `lower : cst_lite → expr` + emit-bridge oracle over the corpus | ✅ shipped 2026-06-10 (byte-identical on all 11 probe files) |
| M1.3  | `print_ye` (the formatter) + round-trip / idempotence oracle | ⏳ |
| M1.4  | statement-level error recovery (partial tree while editing) | ⏳ |
| M1.5  | LSP shell (`linol`) over `Yc_driver`: diagnostics / hover / format / semantic tokens | ⏳ |
| —     | retire `parse_ast`; production path is `text → cst → lower → expr` | ⏳ |

## Testing strategy (target, build out over M1.2–M1.3)

Layered coverage for the parse/lower/print round-trips:

- **Exhaustive single-construct round-trips** — one round-trip per
  length-one expression / construct (each atom, each command shape, each
  cond op, each control form), so every grammar leaf is covered in
  isolation. Length-two combinations are valuable but combinatorially
  large — sample rather than enumerate.
- **Regression collection** — every bug found (e.g. the `~type:STRING`
  cache-assign gap) becomes a pinned case. Grow it over time.
- **Absorb real-world inputs** — harvest test inputs from the probe `.yc`
  files and real-world cmake corpora (z3/llvm/torch), not just synthetic
  snippets. The emit-bridge already runs over the probe corpus; widen it.

## Open decisions / parked

- **Token-stream formatter shortcut** — could ship canonical formatting
  over `lex_located` before the CST (indent by paren/brace depth, break at
  `;`, keep `COMMENT`s), but comment placement is heuristic and it's a
  throwaway track. Default: **skip, go CST-first.**
- **`cst_lite` tier** — AST + comments + spans confirmed; revisit only if a
  use case needs full original-whitespace fidelity.
- **"Belief" definition** — shapes the `check` op's output type (flat
  diagnostics vs a richer fact stream the LSP renders). Open; needed before
  M1.5. See `surface_lsp_framework.md` §4.
- **Manifest `ctor` column** — populate + test-lock once `lower` makes the
  surface↔constructor link verifiable.
- **Doc/box pretty-print algebra** & **invertible/bidirectional grammars**
  — flagged know-how revisits; not on the build path (`surface_lsp_framework.md`
  §3.8 note, § Formatter).
