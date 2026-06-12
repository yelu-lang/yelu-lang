# Driver — pipelines graph + tool-interface matrix

Each language in the yelu ecosystem has a driver module in
[`src/langs/drivers/`](../../src/langs/drivers/) that exports a uniform
set of operations: **parse**, **print**, **eval**, **compile**, **check**
(+ **introspect** / **format** on yc).
A language has two forms: **IR** (AST) and **text** (concrete syntax).
A driver covers both — parse maps text→IR, print maps IR→text, eval and
check operate on either form. **yc additionally has a third form, the
`cst_lite` CST** (comments + spans) sitting between its text and IR — the
substrate for the formatter and LSP; see §2.

Each operation is a direct implementation (`code`), a shell-out to
an external tool (`tool:<name>`), a composition through another driver
(`compose`), or a stub (`failwith "not implemented"`).

## 1. Pipelines graph

```
                      ╭──────────────╮
                      │    cmake     │  ← one language: IR + text
                      ╰──┬────────▲──╯
                         │        │
       parse: tool+code   │        │  print: code (Lang_cmake_pp)
       eval: tool (cmake) │        │
                         │        │
               compile   │        │  compile
               to_yc     ▼        │  from_yc
                      ╭──────────╮         ╭──────────╮
  ╭──────────╮       │    yc    │◄───────→│   ycn   │
  │ .yc text │──parse→│          │ to/from │         │
  ╰──────────╯       ╰────┬─────╯         ╰──────────╯
                          │
                yc.eval   │  ycn.eval
                          ▼
                     (env, value)

  ╭──────────╮       no parser
  │.ycn text │  ──── no printer ── (yet)
  ╰──────────╯
```

Three languages, each in two forms:
- **cmake** — `Lang_cmake.exp` (IR) + cmake text (concrete syntax)
- **yc** — `Yelu_cmake.expr` (IR, cmake-faithful) + `.yc` text
- **ycn** — `Yelu_cmake.expr` (IR, normal form) + `.ycn` text
- `.ye` is reserved for future non-cmake yelu packs (json, nix, …)

Key observations:
- **yc is the hub.** Inbound from .yc, cmake, ycn, .ml; outbound to cmake, ycn,
  debug text. Every path between cmake and ycn passes through yc.
- **cmake→yc and yc→cmake** are mirror paths: `emit_ast` / `from_emit_top`.
- **ycn has only one neighbour** (yc). The `.ycn` parser would add a second inbound.
- **.yc round-trips** via the `cst_lite` form ([`Yc_cst`](../../src/langs/yelu/yc_cst.ml)):
  a comment+span-bearing CST sits between `.yc` text and the `yc` IR.
  `parse_cst` / `print_cst` give text↔cst; `lower_cst` gives cst→IR
  (emit-bridge-proven equal to the legacy `parse_yc`). The formatter
  (`yelu fmt`) is `print_cst ∘ parse_cst`. The canonical *cmake* output is
  still cmake text via yc→cmake emit.

## 2. Language drivers

### cmake (`Cmake_driver`)

Two forms: IR (`Lang_cmake.exp`) and text (`.cmake` / `CMakeLists.txt`).
Parse and eval on the text side are tool:*; print on the IR side is code.

| Op | Function | Strategy | Notes |
|---|---|---|---|
| parse: text → JSON CST | `parse_text_to_json` | tool:cmake_to_json.py | tree-sitter + libcmake |
| parse: JSON CST → stmt list | `parse_json_to_stmts` | code | `Cmake_text_parse.file_of_json` |
| print: IR → text | `print` | code | `Lang_cmake_pp.pp` |
| print: canonical format | `print_canon` | tool:gersemi | |
| eval: script | `eval_script` | tool:cmake | `cmake -P` |
| eval: configure | `eval_configure` | tool:cmake | `cmake -B -S` |
| check: build | `check_build` | tool:cmake | `cmake --build` |
| compile → yc | `compile_to_yc` | code | `Yelu_cmake_from_emit.from_emit_top` |
| compile ← yc | `compile_from_yc` | code | `Yelu_cmake_emit.emit_ast` |

### yc (`Yc_driver`)

**Three** forms now: text (`.yc`), the `cst_lite` CST
([`Yc_cst`](../../src/langs/yelu/yc_cst.ml) — comments + spans), and IR
(`Yelu_cmake.expr`, cmake-faithful). The formatter round-trips text↔text
through the CST; the legacy `parse_yc` still goes text→IR directly, proven
equal to `lower_cst ∘ parse_cst` by the emit-bridge oracle.

| Op | Function | Strategy | Notes |
|---|---|---|---|
| parse ← .yc → IR (legacy/prod) | `parse_yc` | code | `Yelu_parse.parse_program_y1` |
| parse ← .yc → cst | `parse_cst` | code | `Yc_cst_parse.parse` |
| lower cst → IR | `lower_cst` | code | `Yc_cst_lower.lower_program` (emit-bridge ≡ `parse_yc`) |
| print cst → .yc | `print_cst` | code | `Yc_cst_print.print_program` |
| format: .yc → .yc | `format` | code | `print_cst ∘ parse_cst` (= `yelu fmt`); fail-safe |
| parse ← cmake | `parse_cmake` | code | `Cmake_driver.compile_to_yc` path |
| parse ← ycn | `parse_ycn` | code | `Yelu_cmake_convert.from_normal` |
| compile → cmake | `compile_to_cmake_ast` | code | `Yelu_cmake_emit.emit_ast` |
| compile → ycn | `to_ycn` | code | `Yelu_cmake_convert.to_normal` |
| print → cmake text (debug) | `print_cmake_debug` | code | `Yelu_cmake_emit_debug.emit_script` |
| print → .yc from IR | `print_yc` | **stub** | `expr` drops comments/spans; use `print_cst` / `format` instead |
| introspect: vocabulary manifest | `manifest` | code | `Yc_manifest.all` (drives tm-grammar, `yelu manifest`) |
| eval | `eval` | code | `Yelu_cmake_eval.eval_expr` |
| check (type) | `typecheck` | **stub** | Per-theory functors |
| check (wellform) | `wellform` | code | `Yc_wellform.check_all` |

### ycn (`Ycn_driver`)

Two forms: IR (`Yelu_cmake.expr`, normal) and text (`.ycn`).
Parser and printer are both stubs; only the IR form is operational.

| Op | Function | Strategy | Notes |
|---|---|---|---|
| parse ← yc | `parse_yc` | code | `Yelu_cmake_convert.to_normal` |
| parse ← .ycn text | `parse_ycn` | **stub** | Design-only |
| compile → yc | `compile_to_yc` | code | `Yelu_cmake_convert.from_normal` |
| print → .ycn text | `print_ycn` | **stub** | |
| eval | `eval` | code | `Yelu_cmake_normal_eval.eval_expr` |
| check (roundtrip) | `check_roundtrip` | code | `to_normal ∘ from_normal ≡ id` |

## 3. Cross-language pipelines

| Module | Pipeline | Entry point | Used by |
|---|---|---|---|
| `yc_to_cmake` | .yc → yc → cmake → cmake text | `compile_yc` | `yelu compile` |
| `cmake_to_yc` | cmake text → JSON CST → cmake AST → yc | `file_to_json` | matrix oracle |
| `yc_ycn` | yc ↔ ycn via convert | `to_ycn`, `from_ycn` | lift-lower oracle |
| `Yc_driver.format` | .yc text → cst_lite → .yc text | `format` | `yelu fmt`, yelu-lsp formatting |
| `Yc_cst_lower` | .yc text → cst_lite → yc IR | `lower_cst ∘ parse_cst` | emit-bridge oracle |

## 4. Tool directory: `tool/cmake_text/`

Executable tools that operate on cmake text files. These are `tool:*`
implementations — they shell out to or wrap external programs (tree-sitter,
gersemi, cmake binary).

| File | Role | Strategy |
|---|---|---|
| `cmake_to_json.py` | cmake text → JSON CST | tool:tree-sitter |
| `cmake_reprint.ml` | JSON CST → typed IR → cmake text | code (in-tree exe) |
| `cmake_cache_scan.ml` | Enumerate `option()` / `set(...CACHE...)` decls | tool:cmake_to_json.py |
| `cmake_name_index.ml` | Index function/macro name→def-site | tool:cmake_to_json.py |
| `cmake_strip_comments.py` | Tree-sitter comment stripper | tool:tree-sitter |
| `cmake_roundtrip_oracle.sh` | Per-file STRUCT+FORMAT+summary | tool:cmake_to_json.py + cmake_reprint.exe + gersemi |
| `cmake_reserved_vars.tsv` | 1597 reserved cmake var names (4.3.1) | data |

## 5. External tool dependencies

| Tool | Used by | Role |
|---|---|---|
| `cmake` | `Cmake_driver`, `yelu hybrid`, tests | Configure, build, script |
| `gersemi` | `Cmake_driver.print_canon`, cmake-check | Canonical formatting |
| `cmake_to_json.py` (tree-sitter) | `Cmake_driver.parse_text_to_json`, oracles | cmake text → JSON CST |
| `dune` | `yelu compile` (.ml path) | Build OCaml DSL programs |

## 6. What the matrix reveals

**Two missing printers.** yc→.yc and ycn→.ycn. Both would close the round-trip
for their respective syntax surfaces.

**One missing parser.** .ycn text → ycn. Design notes exist; no code.

**Every evaluator is code** (yc, ycn) — enabling the matrix oracle to predict
CMakeCache.txt without running cmake. The cmake evaluator is `cmake -P` (tool).

**yc is the hub.** Every path between cmake and ycn passes through yc. Adding a
new surface (e.g., an LSP or a syntax highlighter) means adding an operation to
the relevant driver, visible in one place.

## 7. Related

- [`ir_tiers.md`](ir_tiers.md) — 4-tier IR fidelity: typed → cmake_lang → yc_raw → yc_apply
- [`structure.md`](structure.md) — file-level code map
- [`cmake_vs_normal.md`](cmake_vs_normal.md) — yc vs ycn feature comparison
- [`ycn_concrete_syntax.md`](ycn_concrete_syntax.md) — proposal for the missing `.ycn` parser
- [`../../probes/cache_matrix.md`](../../probes/cache_matrix.md) — matrix oracle methodology
- [`../worklog/worklog_2026_06.md`](../worklog/worklog_2026_06.md) — parse-print oracle close (2026-05-31)
