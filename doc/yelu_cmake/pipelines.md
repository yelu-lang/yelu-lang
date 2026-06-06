# Pipelines — text ↔ IR map

A complete survey of every reader, writer, and converter that
crosses the cmake / yc / ycn boundaries. Built so the question
"can we go from X to Y?" has a single authoritative answer.

The IRs:
- **cmake** — `Lang_cmake.exp` (and `Lang_cmake.cmd`) under
  [`src/langs/cmake/`](../../src/langs/cmake/). The cmake-side AST,
  closest to cmake's own syntax model.
- **yc** — `Yelu_cmake.expr` under [`src/langs/yelu/`](../../src/langs/yelu/)
  + 14 theory fragments. Cmake-faithful surface; each `ECmake*`
  constructor maps to a cmake command shape.
- **ycn** — `Yelu_cmake_normal.expr` (same `Yelu_cmake.expr` type;
  different fragment constructors). Normalized form with explicit
  `ESetVar` + bool/int as theory primitives. See
  [`cmake_vs_normal.md`](cmake_vs_normal.md).

Text surfaces:
- **cmake text** — the real `CMakeLists.txt` / `.cmake` files.
- **.ye** — yc concrete syntax (parser exists).
- **.ycn / .yn** — ycn concrete syntax (proposal only; no parser —
  see [`ycn_concrete_syntax.md`](ycn_concrete_syntax.md)).

## 0. At a glance

### As a graph

```
                       ╭─────────────╮
                       │  cmake text │   ← real CMakeLists.txt
                       ╰──┬───────▲──╯
                          │       │
              parse.py +  │       │  Lang_cmake_pp.pp
       Cmake_text_parse   │       │
                          ▼       │
                       ╭─────────────╮
                       │  cmake AST  │
                       ╰──┬───────▲──╯
                          │       │
            from_emit_top │       │ emit_ast
                          │       │
                          ▼       │
   ╭──────────╮          ╭──────────╮         ╭──────────╮
   │ .ye text │─Yelu_─→  │    yc    │◄from_normal│  ycn  │
   │          │ parse    │          │──to_normal→│       │
   ╰──────────╯          ╰────┬─────╯         ╰────┬─────╯
                              │                    │
                       Yelu_cmake_eval     Yelu_cmake_normal_eval
                              │                    │
                              ▼                    ▼
                         (env, value)         (env, value)

   ╭──────────╮          no parser
   │.ycn text │   ────── no printer ── (yet)
   ╰──────────╯
```

Read it as a directed graph: each arrow is a function that takes
its source as input and produces its destination as output. Three
edges that don't exist (broken / dashed in your head): `.ycn text
→ ycn`, `yc → .ye text`, `ycn → .ycn text`.

### As a table — one row per IR / surface

| IR / surface | how to get one (writers / readers FROM other forms) | how to output one (readers FROM this form's text) | evaluator |
|---|---|---|---|
| **cmake text** | `Lang_cmake_pp.pp` (from cmake AST) | hand-written; or real cmake binary (output target) | n/a — real cmake runs it |
| **cmake AST** | `Cmake_text_parse.file_of_json` (from JSON CST); `Yelu_cmake_emit.emit_ast` (from yc) | `Lang_cmake_pp.pp` → cmake text | intermediate only |
| **yc** | `Yelu_parse.parse_program_y1` (from .ye); `Yelu_cmake_from_emit.from_emit_top` (from cmake AST); `Yelu_cmake_convert.from_normal` (from ycn); hand-written .ml | `emit_ast` → cmake AST; `to_normal` → ycn; `emit_script` → cmake text (debug) | `Yelu_cmake_eval.eval` |
| **ycn** | `Yelu_cmake_convert.to_normal` (from yc); hand-written .ml | `from_normal` → yc | `Yelu_cmake_normal_eval.eval` |
| **.ye text** | hand-written | none (no `yc → .ye` printer) | — |
| **.ycn text** | none (no parser) | none (no printer) | — |

What jumps out:
- **yc** is the hub. Five inbound paths, three outbound. Everything
  that flows between cmake and ycn passes through yc.
- **cmake AST** is a forced intermediate — there's no direct
  `cmake text ↔ yc`; you always pass through `Lang_cmake.exp`.
- **ycn** has only one neighbour (yc). Inbound and outbound both
  go through `Yelu_cmake_convert`. The proposed `.ycn` parser
  would add a second inbound; ycn-direct-emit would add an
  outbound.
- **.ye** is asymmetric: parseable but not printable. We can read
  `.ye` files but not generate them — the canonical "output" form
  is cmake text via the yc emit pipeline.

## 1. Readers (text → IR)

| from               | to        | entry point                                                                                            | used by                                   |
| ------------------ | --------- | ------------------------------------------------------------------------------------------------------ | ----------------------------------------- |
| cmake text         | JSON CST  | `tool/cmake_roundtrip/parse.py` (Python subprocess; libcmake's lexer)                                  | cmake_bridge, parse-print oracle          |
| JSON CST           | cmake AST | [`Cmake_text_parse.file_of_json`](../../src/langs/cmake/cmake_text_parse.ml)                           | cmake_bridge, parse-print oracle          |
| cmake AST          | yc        | [`Yelu_cmake_from_emit.from_emit_top`](../../src/langs/yelu/yelu_cmake_from_emit.ml)                   | cmake_bridge (matrix oracle)              |
| .ye text           | yc        | [`Yelu_parse.parse_program_y1`](../../src/langs/yelu/yelu_parse.ml)                                    | `yelu hybrid`, `yelu compile`, .ye probes |
| .ycn text          | ycn       | **does not exist**                                                                                     | —                                         |
| OCaml source (.ml) | yc / ycn  | no parser; the `.ml` directly constructs the AST using ergonomic ctors from `yelu_cmake_utils.ml` etc. | probes/*.ml, step files, tests            |

The `cmake text → yc` chain is **three stages**:
1. `parse.py` is a thin wrapper over cmake's own parser (we call
   into libcmake) and dumps a JSON CST. We don't reimplement
   cmake's lexer / quoting rules.
2. `Cmake_text_parse.file_of_json` walks the CST and emits a
   stage-1 cmake-AST (`Lang_cmake.cmd list`-ish), per-command
   parsers (one per cmake command name; ~50 of them so far).
3. `Yelu_cmake_from_emit.from_emit_top` lifts the cmake AST into
   `yelu_cmake.expr` — the inverse of `Yelu_cmake_emit.emit_ast`.

The whole chain is the cmake-importer side, used to load vendor
cmake so the yc evaluator can run on it (matrix oracle).

## 2. Writers (IR → text)

| from      | to                      | entry point                                                                          | used by                                              |
| --------- | ----------------------- | ------------------------------------------------------------------------------------ | ---------------------------------------------------- |
| cmake AST | cmake text              | [`Lang_cmake_pp.pp`](../../src/langs/cmake/lang_cmake_pp.ml)                         | all cmake output paths                               |
| yc        | cmake AST               | [`Yelu_cmake_emit.emit_ast`](../../src/langs/yelu/yelu_cmake_emit.ml)                | production yelu compile, probes/fmt emit, step files |
| yc        | cmake text (debug)      | [`Yelu_cmake_emit_debug.emit_script`](../../src/langs/yelu/yelu_cmake_emit_debug.ml) | debug introspection only                             |
| yc        | cmake text (production) | `emit_ast` ▸ `Lang_cmake_pp.pp` (composition)                                        | `Yelu_emit_main.print`, `yelu compile`               |
| ycn       | cmake text              | via `from_normal` → yc → cmake text (composition)                                    | indirect — no direct emitter                         |
| yc        | .ye text                | **does not exist**                                                                   | —                                                    |
| ycn       | .ycn text               | **does not exist**                                                                   | —                                                    |

Two emitters from yc exist: `emit_ast` (production; lowers to
`Lang_cmake` AST first) and `emit_script` (debug; one-shot text).
The production path goes through the typed cmake AST so the
pretty printer can do its `(` / `)` indentation, quoting, comment
placement consistently. The debug path is a shortcut for
introspection.

## 3. IR ↔ IR converters

| from | to  | entry point                                                                    | what it does                                                            |
| ---- | --- | ------------------------------------------------------------------------------ | ----------------------------------------------------------------------- |
| yc   | ycn | [`Yelu_cmake_convert.to_normal`](../../src/langs/yelu/yelu_cmake_convert.ml)   | normalize: ESetVar primitive, decomposed subcommands, bool/int as exprs |
| ycn  | yc  | [`Yelu_cmake_convert.from_normal`](../../src/langs/yelu/yelu_cmake_convert.ml) | lift back to yc shape for emission                                      |

The `to_normal ∘ from_normal ≡ identity-modulo-emission` property
is the lift_lower oracle. 65 tests in
[`test/test-yelu/test_yelu_lift_lower.ml`](../../test/test-yelu/test_yelu_lift_lower.ml).

## 4. Evaluators (IR → values + env)

| input | entry point                                                                     | used by                                                  |
| ----- | ------------------------------------------------------------------------------- | -------------------------------------------------------- |
| yc    | [`Yelu_cmake_eval.eval`](../../src/langs/yelu/yelu_cmake_eval.ml)               | matrix oracle (predicts CMakeCache.txt), .ye smoke tests |
| ycn   | [`Yelu_cmake_normal_eval.eval`](../../src/langs/yelu/yelu_cmake_normal_eval.ml) | dual_eval tests, ycn-side checks                         |

Both evaluators produce `(env, value)` — env is the variable /
target / property store; value is the expression's result.

## 5. Composed pipelines in production

The reader / writer / converter tables above are the primitives.
The pipelines actually run from end to end are compositions of
them. There are five operationally important ones:

### 5.a `yelu compile <file>` — generate cmake from .ye or .ml

```
.ye  ─Yelu_parse.parse_program_y1─→  yc  ─emit_ast─→  cmake AST  ─Lang_cmake_pp.pp─→  cmake text
.ml  ─dune exec subprocess─────────→  yc  ─emit_ast─→  cmake AST  ─Lang_cmake_pp.pp─→  cmake text
```

Source: `src/bin/yelu/yelu.ml` § "compile". The .ml case shells
out to a per-file executable; the .ye case runs the parser
in-process.

### 5.b `yelu hybrid <project>` — splice/replace + run cmake on both

```
manifest.json
  ├─ each .ye / .ml → cmake text (via 5.a)
  ├─ either splice (anchor_start/anchor_end) or whole_file replace
  │  into the vendor cmake tree mirror at _out/<project>/hybrid/source/
  └─ run cmake -B vendor-build -S vendor; cmake -B hybrid-build -S hybrid
     diff CMakeCache.txt; report match/mismatch
```

Used by probes/fmt to verify byte-equivalent configure across the
24-cell matrix.

### 5.c Matrix oracle (yc evaluator vs real cmake)

```
vendor cmake text  ─parse.py─→  JSON  ─Cmake_text_parse─→  cmake AST
                                                            │
                                                            ▼
                                  Yelu_cmake_from_emit.from_emit_top
                                                            │
                                                            ▼
                                                           yc
                                                            │
                                       Yelu_cmake_eval.eval ▼
                                                       predicted env
                                                            │ (extract cache vars)
                                                            ▼
                                                   predicted CMakeCache.txt
                                                            │
                                                            ▼
                       (compare against)  ── real cmake's CMakeCache.txt
```

This is the cmake-importer path. We read vendor cmake and run
our evaluator on it to predict what the cache will look like;
then diff. Used by `test_fmt_matrix_smoke.exe` and friends.

### 5.d Parse-print oracle (cmake → cmake roundtrip)

```
vendor cmake text  ─parse.py─→  JSON  ─Cmake_text_parse─→  cmake AST  ─Lang_cmake_pp─→  cmake text'
                                                                                              │
                                                                                              ▼
                                                                   (compare against original)
```

Tests `cmake AST ↔ cmake text` fidelity. Run via
`tool/cmake_roundtrip/test_corpus.sh`; corpus snapshots in
[`probes/parse_print_oracle.md`](../../probes/parse_print_oracle.md).

### 5.e Lift-lower oracle (yc ↔ ycn roundtrip)

```
yc  ─to_normal─→  ycn  ─from_normal─→  yc'
                                       │
                                       ▼  (compare against original)
```

Used by `test_yelu_lift_lower.ml` — 65 paired tests.

## 6. What doesn't exist (notable gaps)

- **`.ycn` text → ycn parser**. Design notes in
  [`ycn_concrete_syntax.md`](ycn_concrete_syntax.md). Today every
  ycn program is hand-built in OCaml.
- **`yc → .ye` printer**. We can write `.ye` by hand, but can't
  pretty-print a yc AST back to `.ye` syntax. (Round-trip via
  cmake works: `.ye` → yc → cmake text. The cmake-text view is the
  "canonical" output today.)
- **`ycn → .ycn` printer**. Same reason as above + no concrete
  syntax to print to.
- **`ycn → cmake text` direct emitter**. Composition through
  `from_normal → yc → emit_ast → pp` works; there's no
  shortcut. Probably fine — the ycn-to-cmake direction is rare in
  practice (we usually run analysis on ycn, then either emit-via-yc
  or stay in IR).
- **`cmake → ycn` direct importer**. Composition through
  `parse.py → Cmake_text_parse → from_emit_top → to_normal`
  works; there's no shortcut.

## 7. Coverage gaps within existing pipelines

Pipelines exist but aren't fully populated:

- **`Cmake_text_parse`** has ~50 per-command parsers. CMake has
  hundreds of commands. Coverage is enough for the fmt / z3 / llvm
  parse-print corpora but unknown commands fall through to a
  generic `Apply` form (raw arg list, no typed shape).
- **`Yelu_cmake_from_emit`** mirrors the cmake AST surface, so it
  inherits Cmake_text_parse's coverage limits. Unrecognized
  command shapes lift to `yc_apply` (the same lenient form used
  in hand-written probes).
- **`Yelu_cmake_emit`** is the most mature — every typed yc
  constructor has an emit case. New IR ctors land with their
  emit case in the same commit.
- **`Lang_cmake_pp`** is also mature for the constructors that
  exist; gaps are mostly in quoting (the `\"` / `\\` escape gap
  that motivated `Yelu_emit_main.escape` and the `raw_cmake`
  workaround — see
  [`../../probes/fmt/migration_status.md`](../../probes/fmt/migration_status.md)
  § raw_cmake).

## 8. Related

- [`tool_interface.md`](tool_interface.md) — per-node matrix of
  parse/print/eval/compile/check with code-vs-tool annotation.
- [`structure.md`](structure.md) — file-level code map (which
  module lives where).
- [`cmake_vs_normal.md`](cmake_vs_normal.md) — yc vs ycn
  feature comparison (per-fragment ctor counts, parser/emit/eval
  asymmetries).
- [`ycn_concrete_syntax.md`](ycn_concrete_syntax.md) — proposal
  for the missing `.ycn` parser surface.
- [`../../probes/cache_matrix.md`](../../probes/cache_matrix.md)
  — methodology for the matrix oracle (pipeline 5.c).
- [`../../probes/parse_print_oracle.md`](../../probes/parse_print_oracle.md)
  — methodology for the parse-print oracle (pipeline 5.d).
