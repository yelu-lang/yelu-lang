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

| phase | what                                                                                                          | status                                                                                                                                                                                                                                                                      |
| ----- | ------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| M0    | TextMate highlighter                                                                                          | ✅ shipped 2026-06-10                                                                                                                                                                                                                                                        |
| M1.0  | lexer: lossless located scanner (`lex_located`)                                                               | ✅ shipped 2026-06-10                                                                                                                                                                                                                                                        |
| M1.1  | `cst_lite` type + parser `text → cst_lite` (consume `lex_located`)                                            | ✅ shipped 2026-06-10 (parses all 11 fmt .yc)                                                                                                                                                                                                                                |
| M1.2  | `lower : cst_lite → expr` + emit-bridge oracle over the corpus                                                | ✅ shipped 2026-06-10 (byte-identical on all 11 probe files)                                                                                                                                                                                                                 |
| M1.3  | `print_ye` (the formatter) + round-trip / idempotence oracle                                                  | ✅ shipped 2026-06-10 (`yelu fmt`; round-trip+idempotent+comments on all 11 probe files)                                                                                                                                                                                     |
| M1.4  | statement-level error recovery (partial tree while editing)                                                   | ⏸ **deferred into M1.5** — only the LSP consumes partial trees; the formatter is already fail-safe (parse error → no overwrite). Do the light top-level version when the LSP needs it.                                                                                      |
| M1.5a | LSP server (`linol-lwt`): `textDocument/formatting` (via `Yc_driver.format`) + parse diagnostics + fail-safe  | ✅ shipped 2026-06-10 (`src/bin/yelu_lsp/`; manually verified over JSON-RPC; built against the yojson-3 linol fork @ lsp 1.26)                                                                                                                                               |
| M1.5c | VS Code client wiring (`vscode-languageclient`) to launch `yelu-lsp` — deploy locally; enables format-on-save | ✅ shipped 2026-06-10 (`editors/vscode/yc/extension.js`; packages cleanly)                                                                                                                                                                                                   |
| M1.5b | richer diagnostics (parse error spans) + hover / semantic tokens                                              | ◐ parse-error **spans done** (2026-06-12): `Yc_cst_parse.parse_with_pos` carries the offending token's span + a humanized message; the LSP maps byte offset → line/char and reports at the real range (lex errors fall back to file start). Hover / semantic tokens still ⏳ |
| —     | retire `parse_ast`; production path is `text → cst → lower → expr`                                            | ⏳                                                                                                                                                                                                                                                                           |

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
  - **Decided policy (2026-06-19): reject.** A positional cmake-keyword *input*
    is a **compile error** ("positional form of `<cmd>` isn't a yc surface; use
    `~label=` or `yc_raw '…'`"). Reject was chosen over raw fallback after the
    analysis below showed raw is *not* a cheap safety net. `yc_raw` remains the
    escape for anyone who genuinely wants literal cmake (written faithfully by
    hand, as the corpus does). Global config (warn / reject / silent per case)
    is a future to-do.
  - **Why not raw fallback** (the two findings that flipped the call): (1)
    `ECmakeRawCmd` emits `EVar n → ${n}` (deref), so positional bare keywords
    (`LIBRARY`→`${LIBRARY}`) emit garbage unless mapped `EVar→EString`; and (2)
    a yc command name encodes an *implicit subcommand keyword* the cmake name
    drops (`install_targets`→`install(`**`TARGETS`**`…)`), so faithful raw needs
    per-command reconstruction (`install_targets`→`TARGETS`, etc.). Raw =
    re-deriving the structured emit just to throw the structure away. Reject
    needs **none** of that — the command is rejected before emit, so the args
    never have to be faithful.
  - **Reject mechanism:** the per-command `_inner`, on detecting positional
    cmake keywords, falls to a raw command **tagged with the yc command name**
    (the cmake `name` alone is too coarse — `install` is shared by
    install_targets/files/export, and rollout is incremental). A `Yc_wellform`
    check turns the tag into a **fatal** error (like `Enum_shadow`), surfaced via
    `compile_yc`. Needs `ECmakeRawCmd` to carry the yc name (`from_positional :
    string option`, ~6 construction sites default `None`).
  - **What's removed when done:** the 19 `split_by_keywords` positional sites
    across the per-command `_inner`s (`yelu_parse.ml`, shared by the legacy
    parser + the CST lower) and the 4 formatter canonicalization walks
    (`pr_install_targets_args` / `pr_command_groups_args` /
    `pr_set_target_properties_args` / the rewriting half of `pr_cmd_args`).
    The CST parser stays generic; the byte-equality oracle (AST-based) and the
    fmt matrix (corpus now labeled/raw) are **not** in the blast radius.
  - **Phased plan:** (1) reject mechanism — `from_positional` tag + the
    `Yc_wellform` fatal check ✅ **done** (commit 83fd8ab); (2) pilot
    `install_targets` ✅ **done** (commit 83fd8ab) — `_inner` reads kwargs +
    leading targets only, positional keywords → tagged raw (rejected), dropped
    the two-level split + deleted `pr_install_targets_args` /
    `install_artifact_kinds` / `install_top_kw` / `install_targets_emit_safe`,
    verified (matrix 24/24, suite, byte-oracle), positional bridge assertions
    moved to a `test_yc_wellform` reject test + labeled round-trip kept in
    `test_yc_cst_bridge`; (3) **roll out per family** ✅ **done** —
    one commit each:
    - target (commit 6677d4c): `add_custom_command` / `add_custom_target`
      positional COMMAND/OUTPUT/DEPENDS/SOURCES/COMMENT/ALL/… → reject. The
      visibility-group commands (`target_link_libraries`, `target_sources`, …)
      are untouched — their positional keyword *is* the enum-constructor
      surface (`Public`/`Private`/`Interface`).
    - install (commit b20f1cd): `install_files` / `install_export` /
      `install_directory` positional DESTINATION/COMPONENT/NAMESPACE/… → reject.
    - property (commit 3cb4893): `set_property` / `get_property` /
      `set_target_properties` positional PROPERTY/APPEND/mode/PROPERTIES →
      reject (entity scope `Target`/`Source`/`Cache`/… stays — enum surface).
      Migrated two discovered helpers (cuda-test, static-export-test) to labels.
    - cmake_op (commit e39311c): `execute_process` positional COMMAND/
      *_VARIABLE/… → reject. Migrated compile-error-test (3 calls).
    - **Deferred (no `~label=` equivalent yet — positional kept until a label is
      designed, else they'd orphan the functionality):** `export TARGETS/
      NAMESPACE/FILE`, `configure_package_config_file INSTALL_DESTINATION`,
      `set_source_files_properties PROPERTIES` (corpus-load-bearing,
      main.yc:179), `cmake_minimum_required VERSION` (canonical), message modes
      (canonical), `enable_language OPTIONAL`, `include_guard GLOBAL` (enum-ish).
    - **Reject does not fire under `emit_ast`/fmt** (no wellform pass), so the
      emit-bridge + matrix oracles are blind to it — each family's reject has
      its own `test_yc_wellform` case + labeled round-trip in
      `test_yc_cst_bridge`. The matrix only caught the corpus regressions
      because the **discovered helpers** (`probes/fmt/test/*/CMakeLists.yc`) are
      compiled through the fatal `compile_yc` path; `compile main.yc` alone was
      byte-identical and hid them.
    (4) **cleanup** ✅ **done** — two parts, both decided this session:
    - *Parser* (commit 1c0ffed): dropped the now-vestigial `split_by_keywords`
      calls in `set_property` / `get_property` / `set_target_properties` (the
      reject fires upstream, so the split could never find a section there).
      `split_by_keywords` itself **stays** — still load-bearing for the deferred
      commands (`set_source_files_properties` / `export` /
      `configure_package_config_file`) and the test family. It is an active
      helper, not dead legacy.
    - *Formatter* (commit 5c9b92d): `fmt` is now **pass-through** — the
      positional→labeled walks (`pr_command_groups_args` /
      `pr_set_target_properties_args` / the rewriting half of `pr_cmd_args`, +
      the `command_flags`/`command_value_labels`/`command_value_list_labels`
      tables) are **deleted**. **Decision (2026-06-19): no codemod in `fmt`.**
      `fmt` should only bless good (labeled) code; a positional→labeled codemod
      belongs in a separate 2to3-style migration tool, not in the formatter. At
      this design-implementation stage the corpus is small enough to just update
      old input files. Consequence: non-rejected commands keep their positional
      surface as good code (`find_package Foo REQUIRED`, `include_guard GLOBAL`)
      and fmt leaves them be; the `~required`/`~global` kwarg aliases stay
      parser-accepted. Verified: corpus fmt idempotent + emit-stable.
    Step 2 is **complete**. Full analysis in the 2026-06-19 session.
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
