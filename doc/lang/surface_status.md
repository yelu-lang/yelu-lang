# Surface / formatter / LSP — implementation status

> Living tracker for the yc surface **machinery**: highlighter → formatter →
> language server (the parse/lower/print/LSP pipeline). The *syntax design*
> that rides on top of this lives in
> [`yc_syntax_critique.md`](yc_syntax_critique.md); design + decision-map in
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
| M1.3  | `print_ye` (the formatter) + round-trip / idempotence oracle | ✅ shipped 2026-06-10 (`yelu fmt`; round-trip+idempotent+comments on all 11 probe files) |
| M1.4  | statement-level error recovery (partial tree while editing) | ⏸ **deferred into M1.5** — only the LSP consumes partial trees; the formatter is already fail-safe (parse error → no overwrite). Do the light top-level version when the LSP needs it. |
| M1.5a | LSP server (`linol-lwt`): `textDocument/formatting` (via `Yc_driver.format`) + parse diagnostics + fail-safe | ✅ shipped 2026-06-10 (`src/bin/yelu_lsp/`; manually verified over JSON-RPC; built against the yojson-3 linol fork @ lsp 1.26) |
| M1.5c | VS Code client wiring (`vscode-languageclient`) to launch `yelu-lsp` — deploy locally; enables format-on-save | ✅ shipped 2026-06-10 (`editors/vscode/yc/extension.js`; packages cleanly) |
| M1.5b | richer diagnostics (parse error spans) + hover / semantic tokens | ◐ parse-error **spans done** (2026-06-12): `Yc_cst_parse.parse_with_pos` carries the offending token's span + a humanized message; the LSP maps byte offset → line/char and reports at the real range (lex errors fall back to file start). Hover / semantic tokens still ⏳ |
| —     | retire `parse_ast`; production path is `text → cst → lower → expr` | ⏳ |

## Deployment gotcha (local VS Code)

The extension is **installed as a copy** under
`~/.vscode-server/extensions/yelu-lang.yc-0.1.0/` (WSL). VS Code reads two
things from *different* places:
- **LSP binary** — from the *workspace* (`_build/default/src/bin/yelu_lsp/yelu_lsp.exe`
  per `package.json`'s `yc.server.path` fallback), so a `dune build` + window
  reload picks up LSP changes.
- **TextMate grammar** — from the *installed copy*'s `syntaxes/yc.tmLanguage.json`,
  **not** the workspace. So regenerating `editors/.../yc.tmLanguage.json` does
  nothing until that copy is updated — no reload or LSP rebuild helps.

Fix applied 2026-06-12: the installed grammar is now a **symlink** to the
workspace file, so `yelu tmgrammar` / `dune promote` regens are live (just
reload the window). If the extension is ever reinstalled, re-symlink (or copy).

## Open surface items

**Done (machinery, 2026-06-12):**
- **`Cmake_keyword` highlighting ✅** — `keyword.other.yc` manifest class for a
  curated set of bare cmake markers; grammar-freshness-locked. (Most of these
  became `~kw` in the `~`-half pass since.)
- **Furthest-failure diagnostics ✅** — `p_stmt` records the deepest token
  attempted (`furthest` ref); on failure the error blames *that* token, not the
  enclosing statement's first. Pinned by `test_error_span_nested`. *Bonus still
  open:* a targeted "X is an enum constructor, not a variable name" message.

**Parked:** dotted globals — the corpus killed "all-caps = global" (`$ARGN`/
`$BMI` are *local* all-caps); real namespacing → **ycn**. Tracked in
[`yc_syntax_critique.md`](yc_syntax_critique.md) § Open and `casing_design.md`.

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

- **Labeled-only surface — remove positional parsing (planned next phase,
  2026-06-19).** The no-ALL_CAPS pass is **complete**: the fmt corpus is now
  fully `~label=` or explicit `yc_raw` (the two un-labelable lines — a
  `target_sources … FILE_SET` clause and the `install_targets … $INSTALL_FILE_SET`
  metaprogramming splice — were macro-escaped in `7cff140`). So yc can become
  **labeled-only**: drop the positional cmake-keyword surface entirely.
  - **Decided policy:** positional cmake-keyword *input* → **raw fallback +
    warning** (not silently mis-parsed). Forgiving (paste-cmake still
    compiles, as raw), reversible to stricter later.
  - **Future to-do (global config):** a toolset switch to choose
    warn / reject / silent per case. Punted; not blocking.
  - **Small design item:** the warning needs to distinguish *"known structured
    command given positional input → fell to raw"* from the existing generic
    `ECmakeRawCmd` (genuinely unknown command). Today `Raw_cmake_escape` fires
    only for explicit `yc_raw` (`ECmakeRaw`), not the auto `ECmakeRawCmd`
    fallback — so this needs a distinct signal (a wellform check or an
    `ECmakeRawCmd ~from_positional` tag).
  - **What's removed when done:** the 19 `split_by_keywords` positional sites
    across the per-command `_inner`s (`yelu_parse.ml`, shared by the legacy
    parser + the CST lower) and the 4 formatter canonicalization walks
    (`pr_install_targets_args` / `pr_command_groups_args` /
    `pr_set_target_properties_args` / the rewriting half of `pr_cmd_args`).
    The CST parser stays generic; the byte-equality oracle (AST-based) and the
    fmt matrix (corpus now labeled/raw) are **not** in the blast radius.
  - **Phased plan:** (1) settle the warning signal; (2) pilot `install_targets`
    (clearest positional/labeled split) — `_inner` reads kwargs only, positional
    → raw+warn, delete its formatter walk, verify (matrix/suite/byte-oracle),
    rewrite its bridge tests (positional-canon → labeled round-trip +
    positional→raw); (3) roll out per family (target → install → property →
    cmake_op), one commit each; (4) collapse the dead machinery. Medium-large,
    multi-session; main cost is bridge-test churn. Full analysis in the
    2026-06-19 session.
- **Driver interface — CST as a first-class form.** *Tier (a) done
  (2026-06-10):* `Yc_driver` now exposes `parse_cst` / `lower_cst` /
  `print_cst` / `format`, and [`../yelu_cmake/driver.md`](../yelu_cmake/driver.md)
  documents the `text ↔ cst_lite ↔ expr` form + ops. *Tier (b) deferred:*
  point the production `parse_yc` at `lower_cst ∘ parse_cst` and retire the
  legacy direct parser (`Yelu_parse.parse_program_y1`). The emit-bridge
  already proves equivalence, so it's safe — but it's a production-path
  change with its own soak, not a doc tidy-up. Do when consolidating on one
  parser.

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
