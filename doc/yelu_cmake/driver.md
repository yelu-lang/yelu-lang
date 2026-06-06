# Driver — pipelines graph + tool-interface matrix

Each language in the yelu ecosystem has a driver module in
[`src/langs/drivers/`](../../src/langs/drivers/) that exports a uniform
set of operations: **parse**, **print**, **eval**, **compile**, **check**.
A language has two forms: **IR** (AST) and **text** (concrete syntax).
A driver covers both — parse maps text→IR, print maps IR→text, eval and
check operate on either form.

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
  │ .ye text │──parse→│          │ to/from │         │
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
- **yc** — `Yelu_cmake.expr` (IR, cmake-faithful) + `.ye` text
- **ycn** — `Yelu_cmake.expr` (IR, normal form) + `.ycn` text

Key observations:
- **yc is the hub.** Inbound from .ye, cmake, ycn, .ml; outbound to cmake, ycn,
  debug text. Every path between cmake and ycn passes through yc.
- **cmake→yc and yc→cmake** are mirror paths: `emit_ast` / `from_emit_top`.
- **ycn has only one neighbour** (yc). The `.ycn` parser would add a second inbound.
- **.ye is asymmetric:** parseable but not printable. The canonical output form
  is cmake text via yc→cmake emit.

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

Two forms: IR (`Yelu_cmake.expr`, cmake-faithful) and text (`.ye`).
Parse is code; print→.ye is a stub.

| Op | Function | Strategy | Notes |
|---|---|---|---|
| parse ← .ye | `parse_ye` | code | `Yelu_parse.parse_program_y1` |
| parse ← cmake | `parse_cmake` | code | `Cmake_driver.compile_to_yc` path |
| parse ← ycn | `parse_ycn` | code | `Yelu_cmake_convert.from_normal` |
| compile → cmake | `compile_to_cmake_ast` | code | `Yelu_cmake_emit.emit_ast` |
| compile → ycn | `to_ycn` | code | `Yelu_cmake_convert.to_normal` |
| print → cmake text (debug) | `print_cmake_debug` | code | `Yelu_cmake_emit_debug.emit_script` |
| print → .ye | `print_ye` | **stub** | `failwith "not implemented"` |
| eval | `eval` | code | `Yelu_cmake_eval.eval_expr` |
| check (type) | `typecheck` | **stub** | Per-theory functors |
| check (wellform) | `wellform` | **stub** | Retired |

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
| `yc_to_cmake` | .ye → yc → cmake → cmake text | `compile_ye` | `yelu compile` |
| `cmake_to_yc` | cmake text → JSON CST → cmake AST → yc | `file_to_json` | matrix oracle |
| `yc_ycn` | yc ↔ ycn via convert | `to_ycn`, `from_ycn` | lift-lower oracle |

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

**Two missing printers.** yc→.ye and ycn→.ycn. Both would close the round-trip
for their respective syntax surfaces.

**One missing parser.** .ycn text → ycn. Design notes exist; no code.

**Every evaluator is code** (yc, ycn) — enabling the matrix oracle to predict
CMakeCache.txt without running cmake. The cmake evaluator is `cmake -P` (tool).

**yc is the hub.** Every path between cmake and ycn passes through yc. Adding a
new surface (e.g., an LSP or a syntax highlighter) means adding an operation to
the relevant driver, visible in one place.

## 7. Related

- [`structure.md`](structure.md) — file-level code map
- [`cmake_vs_normal.md`](cmake_vs_normal.md) — yc vs ycn feature comparison
- [`ycn_concrete_syntax.md`](ycn_concrete_syntax.md) — proposal for the missing `.ycn` parser
- [`../../probes/cache_matrix.md`](../../probes/cache_matrix.md) — matrix oracle methodology
- [`../../probes/parse_print_oracle.md`](../../probes/parse_print_oracle.md) — parse-print oracle methodology
