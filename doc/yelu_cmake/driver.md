# Driver — pipelines graph + tool-interface matrix

Each language node in the yelu ecosystem has a driver module in
[`src/langs/drivers/`](../../src/langs/drivers/) that exports a uniform
set of operations: **parse**, **print**, **eval**, **compile**, **check**.
Each operation is either a direct implementation (`code`), a shell-out to
an external tool (`tool:<name>`), a composition through another driver
(`compose`), or a stub (`failwith "not implemented"`).

The driver directory also contains cross-language utility modules that
compose single-language drivers into full pipelines — making the
dependency graph between languages explicit rather than scattered across
call sites.

## 1. Pipelines graph

```
                       ╭─────────────╮
                       │  cmake text │   ← real CMakeLists.txt
                       ╰──┬───────▲──╯
                          │       │
              cmake_to_json.py +  │       │  cmake_ast_driver.print
       Cmake_text_parse   │       │
                          ▼       │
                       ╭─────────────╮
                       │  cmake AST  │
                       ╰──┬───────▲──╯
                          │       │
           from_emit_top  │       │  yc_driver.compile_to_cmake_ast
                          │       │
                          ▼       │
   ╭──────────╮          ╭──────────╮         ╭──────────╮
   │ .ye text │─yc_drv─→ │    yc    │◄─ycn_drv│   ycn   │
   │          │ .parse   │          │─.to_ycn→│         │
   ╰──────────╯          ╰────┬─────╯         ╰────┬─────╯
                              │                    │
                     yc_driver.eval    ycn_driver.eval
                              │                    │
                              ▼                    ▼
                         (env, value)         (env, value)

   ╭──────────╮          no parser
   │.ycn text │   ────── no printer ── (yet)
   ╰──────────╯
```

Key observations from the graph:
- **yc is the hub.** Five inbound paths, three outbound. Every path between
  cmake and ycn passes through yc.
- **cmake AST is a forced intermediate.** No direct cmake text ↔ yc; always
  pass through `Lang_cmake.exp`.
- **ycn has only one neighbour** (yc). Inbound and outbound both go through
  `Yelu_cmake_convert`. The proposed `.ycn` parser would add a second inbound.
- **.ye is asymmetric:** parseable but not printable. The canonical "output"
  form is cmake text via the yc emit pipeline.

## 2. Single-language drivers

### yc (`Yc_driver`)

| Op | Function | Strategy | Notes |
|---|---|---|---|
| parse ← .ye | `parse_ye` | code | `Yelu_parse.parse_program_y1` |
| parse ← cmake AST | `parse_cmake` | code | `Yelu_cmake_from_emit.from_emit_top` |
| parse ← ycn | `parse_ycn` | code | `Yelu_cmake_convert.from_normal` |
| parse ← .ml | — | tool:dune | Not in driver; handled by `yelu.ml` |
| compile → cmake AST | `compile_to_cmake_ast` | code | `Yelu_cmake_emit.emit_ast` |
| compile → ycn | `to_ycn` | code | `Yelu_cmake_convert.to_normal` |
| print → cmake text (debug) | `print_cmake_debug` | code | `Yelu_cmake_emit_debug.emit_script` |
| print → .ye | `print_ye` | **stub** | `failwith "not implemented"` |
| eval | `eval` | code | `Yelu_cmake_eval.eval_expr` |
| check (type) | `typecheck` | **stub** | Distributed across per-theory functors |
| check (wellform) | `wellform` | **stub** | Retired; needs re-implementation |

### ycn (`Ycn_driver`)

| Op | Function | Strategy | Notes |
|---|---|---|---|
| parse ← yc | `parse_yc` | code | `Yelu_cmake_convert.to_normal` |
| parse ← .ycn text | `parse_ycn` | **stub** | Design-only |
| compile → yc | `compile_to_yc` | code | `Yelu_cmake_convert.from_normal` |
| print → .ycn text | `print_ycn` | **stub** | |
| eval | `eval` | code | `Yelu_cmake_normal_eval.eval_expr` |
| check (roundtrip) | `check_roundtrip` | code | `to_normal ∘ from_normal ≡ id` |

### cmake AST (`Cmake_ast_driver`)

| Op | Function | Strategy | Notes |
|---|---|---|---|
| parse ← JSON CST | `parse_json_cst` | code | `Cmake_text_parse.file_of_json` |
| print → cmake text | `print` | code | `Lang_cmake_pp.pp` |
| from yc | `from_yc` | code | `Yelu_cmake_emit.emit_ast` |
| to yc | `to_yc` | code | `Yelu_cmake_from_emit.from_emit_top` |

### cmake text (`Cmake_text_driver`)

| Op | Function | Strategy | Notes |
|---|---|---|---|
| parse → JSON CST | `parse_to_json_cst` | tool:cmake_to_json.py | tree-sitter + libcmake |
| print (canonical) | `canon_format` | tool:gersemi | Canonical formatter |
| eval (script) | `eval_script` | tool:cmake | `cmake -P` |
| eval (configure) | `eval_configure` | tool:cmake | `cmake -B -S` |
| check (build) | `check_build` | tool:cmake | `cmake --build` |

## 3. Cross-language pipelines

Composed pipelines that chain single-language drivers. Each is a module in
`src/langs/drivers/` that imports only from driver modules — making the
dependency graph explicit and the pipeline logic testable.

| Module | Pipeline | Entry point | Used by |
|---|---|---|---|
| `yc_to_cmake` | .ye → yc → cmake AST → cmake text | `compile_ye` | `yelu compile` |
| `cmake_to_yc` | cmake text → JSON CST → cmake AST → yc | `import_file` | matrix oracle |
| `yc_roundtrip` | yc → cmake AST → cmake text → cmake AST → yc | `roundtrip` | equivalence check |
| `yc_ycn` | yc ↔ ycn via convert | `to_ycn`, `from_ycn` | lift-lower oracle |
| `cmake_roundtrip` | cmake text → JSON CST → cmake AST → cmake text | `roundtrip_file` | parse-print oracle |

## 4. Tool directory: `tool/cmake_text/`

Executable tools that operate on cmake text files. These are `tool:*`
implementations — they shell out to or wrap external programs (tree-sitter,
gersemi, cmake binary).

| File | Role | Strategy |
|---|---|---|
| `cmake_to_json.py` | cmake text → JSON CST | tool:tree-sitter-cmake |
| `cmake_reprint.ml` | JSON CST → typed IR → reprinted cmake text | code (in-tree exe) |
| `cmake_cache_scan.ml` | Walk project to enumerate `option()` / `set(...CACHE...)` decls | tool:cmake_to_json.py |
| `cmake_name_index.ml` | Walk corpus to index function/macro name→def-site | tool:cmake_to_json.py |
| `cmake_strip_comments.py` | Tree-sitter–based comment stripper for FORMAT oracle | tool:tree-sitter-cmake |
| `cmake_roundtrip_oracle.sh` | Per-file STRUCT+FORMAT+summary oracle over a corpus | tool:cmake_to_json.py + cmake_reprint.exe + gersemi |
| `cmake_reserved_vars.tsv` | Snapshot of 1597 reserved cmake variable names (4.3.1) | data |

Build: `dune build tool/cmake_text/cmake_reprint.exe` (also builds
`cmake_cache_scan.exe`, `cmake_name_index.exe`).

## 5. External tool dependencies

| Tool | Used by | Role |
|---|---|---|
| `cmake` | `Cmake_text_driver`, `yelu hybrid`, tests | Configure, build, script execution |
| `gersemi` | `Cmake_text_driver.canon_format`, cmake-check | Canonical cmake formatting |
| `cmake_to_json.py` (tree-sitter) | `Cmake_text_driver.parse_to_json_cst`, oracles | cmake text → JSON CST |
| `dune` | `yelu compile` (.ml path) | Build OCaml DSL programs |

## 6. What the matrix reveals

**Two missing printers.** yc→.ye and ycn→.ycn. Both would close the round-trip
for their respective syntax surfaces.

**One missing parser.** .ycn text → ycn. Design notes exist; no code.

**Every evaluator is code** (yc, ycn) — enabling the matrix oracle to predict
CMakeCache.txt without running cmake.

**yc is the hub.** Every path between cmake and ycn passes through yc. Adding a
new surface (e.g., an LSP or a syntax highlighter) means adding an operation to
the relevant driver, visible in one place.

## 7. Related

- [`structure.md`](structure.md) — file-level code map
- [`cmake_vs_normal.md`](cmake_vs_normal.md) — yc vs ycn feature comparison
- [`ycn_concrete_syntax.md`](ycn_concrete_syntax.md) — proposal for the missing `.ycn` parser
- [`../../probes/cache_matrix.md`](../../probes/cache_matrix.md) — matrix oracle methodology
- [`../../probes/parse_print_oracle.md`](../../probes/parse_print_oracle.md) — parse-print oracle methodology
