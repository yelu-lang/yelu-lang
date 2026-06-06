# Tool-interface matrix — every language node × every operation

Each IR / text surface in the pipelines graph is a language node. For each
node, five canonical operations may exist: **parse**, **print**, **eval**,
**compile**, **check**. Each operation is implemented either as
native OCaml code (`code`), by calling out to an external tool (`tool:`),
via composition through another node (`compose`), or is missing.

The "code vs tool" distinction determines the dependency footprint:
- `code` — pure OCaml function; `dune build` is the only prerequisite.
- `tool:<program>` — shells out; e.g., `tool:cmake`, `tool:gersemi`,
  `tool:parse.py` (tree-sitter + libcmake).

## 1. Per-node matrix

### cmake text

| Op | Impl | Entry point / command | Notes |
|---|---|---|---|
| parse | `tool:parse.py` | `parse.py + tree-sitter-cmake` → JSON CST | Via libcmake's lexer; we don't reimplement cmake quoting |
| parse→cmake AST | `compose` | `parse.py` → `Cmake_text_parse.file_of_json` | Three stages: Python CST → OCaml JSON walk → `Lang_cmake.exp` |
| print | `code` | `Lang_cmake_pp.pp` | Pure OCaml; production-grade |
| print (canonical) | `tool:gersemi` | `gersemi <file>` | Canonical formatter; used by equivalence oracles |
| eval | `tool:cmake` | `cmake -P script.cmake` | Real cmake interpreter |
| eval (configure) | `tool:cmake` | `cmake -B build -S source` | Real cmake configure; produces CMakeCache.txt |
| check | `tool:cmake` | `cmake -P` or `cmake --build` | cmake's own error reporting |
| driver | `code` | `yelu.ml` (§ compile) | Dispatch on .ml/.ye; compiles to cmake text |

### cmake AST (`Lang_cmake.exp`)

| Op | Impl | Entry point | Notes |
|---|---|---|---|
| parse (from cmake text) | `code` | `Cmake_text_parse.file_of_json` | Walks JSON CST; ~50 per-command parsers |
| parse (from JSON CST) | `code` | `Cmake_text_parse` | OCaml library; no external process |
| print | `code` | `Lang_cmake_pp.pp` | → cmake text |
| from yc | `compose` | via `Yelu_cmake_emit.emit_ast` | yc → cmake AST is the production emit path |

### yc (`Yelu_cmake.expr`)

| Op | Impl | Entry point | Notes |
|---|---|---|---|
| parse (from .ye) | `code` | `Yelu_parse.parse_program_y1` | Pure OCaml; 168 tests |
| parse (from cmake AST) | `code` | `Yelu_cmake_from_emit.from_emit_top` | Inverse of emit; used by matrix oracle |
| parse (from ycn) | `code` | `Yelu_cmake_convert.from_normal` | ycn → yc lift |
| parse (from .ml) | `tool:dune` | `dune exec <file>.exe` | OCaml DSL; compiled then run as subprocess |
| print → .ye | **missing** | — | No yc→.ye printer yet |
| print → cmake text (debug) | `code` | `Yelu_cmake_emit_debug.emit_script` | One-shot text; bypasses cmake AST |
| print → cmake text (prod) | `compose` | `emit_ast` ▸ `Lang_cmake_pp.pp` | Production path |
| eval | `code` | `Yelu_cmake_eval.eval` | yc evaluator; used by matrix oracle |
| compile → cmake AST | `code` | `Yelu_cmake_emit.emit_ast` | Production emit |
| compile → ycn | `code` | `Yelu_cmake_convert.to_normal` | Normalize |
| check (type) | `code` | per-theory `*_check` modules | 14 theories |
| check (wellform) | `code` | `Lang_yelu_wellform` | Cross-theory name binding |
| driver | `code` | `yelu.ml` (§ compile, § hybrid) | CLI: compile .ye/.ml, hybrid splice |

### ycn (`Yelu_cmake_normal.expr`)

| Op | Impl | Entry point | Notes |
|---|---|---|---|
| parse (from yc) | `code` | `Yelu_cmake_convert.to_normal` | yc → ycn normalize |
| parse (from text) | **missing** | — | `.ycn` parser is design-only |
| print → yc | `code` | `Yelu_cmake_convert.from_normal` | ycn → yc lift |
| print → .ycn text | **missing** | — | No ycn→.ycn printer |
| print → cmake text | `compose` | `from_normal` → yc → emit | Composed path works |
| eval | `code` | `Yelu_cmake_normal_eval.eval` | ycn evaluator |
| check (roundtrip) | `code` | lift_lower oracle (65 tests) | `to_normal ∘ from_normal ≡ id` |

### .ye text

| Op | Impl | Entry point | Notes |
|---|---|---|---|
| parse | `code` | `Yelu_parse.parse_program_y1` | → yc |
| print | **missing** | — | No yc→.ye printer |
| driver | `code` | `yelu.ml` (§ compile) | In-process compilation from .ye |

### .ycn text

| Op | Impl | Entry point | Notes |
|---|---|---|---|
| parse | **missing** | — | Design notes in `ycn_concrete_syntax.md` |
| print | **missing** | — | |

## 2. Tool dependencies

External programs that yelu tooling shells out to:

| Tool | Used by | Role |
|---|---|---|
| `cmake` | yelu hybrid, test-runcmake, RunCMake compat, build-level tests | Configure, build, script execution |
| `gersemi` | cmake-check, parse-print oracle | Canonical cmake formatting |
| `parse.py` (tree-sitter) | parse-print oracle, matrix oracle | cmake text → JSON CST |
| `dune` | yelu compile (.ml) | Build OCaml DSL programs |
| `grep` / `bash` / `diff` | yelu hybrid (§ strip_cache, diff) | Post-processing cmake output |

## 3. Driver: `yelu.ml`

Single universal CLI at `src/bin/yelu/yelu.ml`. Two subcommands:

```
yelu compile FILE [-o OUT]
yelu hybrid PROBE_DIR --project DIR [-D K=V ...]
```

The compile path diverges on file extension:
- `.ye` → in-process parse + emit (pure OCaml)
- `.ml` → `dune exec <file>.exe` (shell out)

The hybrid path orchestrates the full matrix oracle:
1. Compile each helper (.ye or .ml) → cmake text
2. Splice into vendor tree (or whole_file replace)
3. Mirror source tree with symlinks; spliced files are real
4. Run `cmake configure` on both vendor and hybrid
5. Diff CMakeCache.txt

## 4. What the matrix reveals

**yc is the hub.** Five inbound paths (parse .ye, from_emit cmake, from_normal ycn,
OCaml DSL via .ml, and hand-written), three outbound (emit → cmake, to_normal → ycn,
emit_script → debug text). Every path between cmake and ycn passes through yc.

**Two missing printers.** yc→.ye and ycn→.ycn. Both would close the round-trip for
their respective syntax surfaces. The cmake→cmake round-trip already works via gersemi.

**One missing parser.** .ycn text → ycn. Design notes exist; no code.

**Every evaluator is code.** Both yc and ycn evaluators are pure OCaml. The cmake
evaluator is `cmake -P` (tool). Having code evaluators for both yc and ycn enables
the matrix oracle: predict CMakeCache.txt without running cmake, then validate
against real cmake.

## 5. Related

- [`pipelines.md`](pipelines.md) — complete text↔IR graph with composition paths
- [`structure.md`](structure.md) — file-level code map
- [`cmake_vs_normal.md`](cmake_vs_normal.md) — yc vs ycn feature comparison
- [`../../probes/cache_matrix.md`](../../probes/cache_matrix.md) — matrix oracle methodology
- [`../../probes/parse_print_oracle.md`](../../probes/parse_print_oracle.md) — parse-print oracle methodology
- `../../ecosem/` — ecosystem semantics project; component interface schema
