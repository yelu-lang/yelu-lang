# cmake_roundtrip

Syntactic round-trip oracle for real-world cmake. Parses cmake source
via tree-sitter-cmake, reprints it through `Lang_cmake.exp` +
`Lang_cmake_pp` (production yelu IR), and verifies tree-sitter
re-extracts the same `(command_name, args)` sequence on both sides.

The audit-ready writeup lives in
[`doc/yelu_cmake/bar3_lite_report.md`](../../doc/yelu_cmake/bar3_lite_report.md);
per-parser contracts + audit prompt template are in
[`doc/yelu_cmake/bar3_lite_audit_kit.md`](../../doc/yelu_cmake/bar3_lite_audit_kit.md).

## Pipeline

```
input.cmake
  → parse.py        (tree-sitter-cmake)    → CST JSON on stdout
  → print2.exe      (OCaml, Lang_cmake.exp + Apply fallback) → reprinted cmake
  → gersemi -                                              → canonicalized
```

Per-file verdict from `test_corpus.sh`:

- **OK** — STRUCT match (tree-sitter extracts same command/arg
  sequence from source and reprint) AND gersemi-normalized text
  matches modulo whitespace.
- **FORMAT** — STRUCT match but gersemi-diff fail. Cosmetic.
- **STRUCT** — STRUCT fail. Real parser/printer/IR bug.
- **PARSE** — tree-sitter or our reader fails.

## Current results (2026-05-19)

| corpus | files | OK | FORMAT | STRUCT | PARSE | modeled | generic |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| tutorial step outputs | 25 | 25 | 0 | 0 | 0 | 165 | 25 |
| z3 | 108 | 108 | 0 | 0 | 0 | 1,057 | 706 |
| llvm/llvm | 596 | 596 | 0 | 0 | 0 | 3,573 | 2,609 |

STRUCT=0 / FORMAT=0 across all three corpora. `modeled` = command
mapped to a typed `Lang_cmake.exp` constructor; `generic` =
preserved verbatim via `Apply { name; args }`. No ratio is
reported — many `generic` calls are project- or module-defined
cmake functions (`z3_add_component`, `tablegen`, `add_llvm_*`,
`CheckXxx`) that *should* stay generic.

## Files

| file | purpose |
| --- | --- |
| `parse.py` | Python wrapper around `tree-sitter-cmake`. Reads cmake on stdin or argv[1]; writes CST JSON on stdout. |
| `strip_comments.py` | Tree-sitter–based comment stripper, used by the gersemi-diff oracle preprocessor (our parser drops inline-arg comments). |
| `print2.ml` | OCaml driver. JSON reader → per-command typed parsers → `Lang_cmake_pp` → untyped `Apply` fallback. |
| `test_corpus.sh` | Harness. Runs the pipeline on every `CMakeLists.txt`/`*.cmake` in a directory tree, applies the STRUCT + FORMAT oracles, prints per-file verdicts + summary. |
| `dune` | Builds `print2.exe` (deps: `base`, `yojson`, `yelu_langs`). |

## Reproducing locally

```sh
# Build
dune build tool/cmake_roundtrip/print2.exe

# Round-trip one file
python3 tool/cmake_roundtrip/parse.py path/to/CMakeLists.txt \
  | _build/default/tool/cmake_roundtrip/print2.exe

# Run the full oracle on a corpus
bash tool/cmake_roundtrip/test_corpus.sh path/to/cmake_corpus

# Coverage tally only (stderr line per file)
python3 tool/cmake_roundtrip/parse.py path/to/CMakeLists.txt \
  | STAGE2_COVERAGE=1 _build/default/tool/cmake_roundtrip/print2.exe \
    >/dev/null
```

Output of the coverage flag:

```
[stage2] modeled=7 generic=2 other=0
```

## Dependencies

- Python: `tree-sitter`, `tree-sitter-cmake`
- `gersemi` (cmake formatter; used as the normalization oracle)
- OCaml: `base`, `yojson`, `yelu_langs` (in-tree)

Harness defaults to `gersemi` at `/home/red/.venvs/default/bin/gersemi`;
override via `GERSEMI=/path/to/gersemi`.

## Known shape gaps

Builtins deliberately routed to `Apply` because the production
printer in `Lang_cmake_pp` is lossy or shape inversion is brittle
for a parser-only patch (per-parser detail in
[`doc/yelu_cmake/bar3_lite_audit_kit.md`](../../doc/yelu_cmake/bar3_lite_audit_kit.md) § 5):

- `set_property` / `get_property` — printer drops most IR fields
- `execute_process` — multi-line keyword shape, hard to invert safely
- `file` (`READ` / `STRINGS` / `COPY*` / `DOWNLOAD` / `UPLOAD` /
  `LOCK` / path-query subcommands)

Closing these is downstream work — they belong with the production
IR cleanup (Y17, `doc/yelu_cmake/status.md` "Known IR shape gaps"),
not as parser-only patches.

## Comment handling

Comments inside `argument_list` are dropped by both `parse.py` and
the production IR. The gersemi-diff oracle compensates by running
`strip_comments.py` on the source side too, so the comparison is
content-equivalent modulo comments. Top-level comments
(between commands) are preserved as `raw` nodes and reprinted
verbatim.

Whether `yelu_cmake` / `yelu_cmake_normal` should carry comments
as AST metadata is a separate, deferred design question.

## Class A resolution (deferred)

Calls into project-defined `function()` / `macro()` bodies
(`z3_add_component`, `tablegen`, the `add_llvm_*` family,
`CheckXxx` standard-module helpers) round-trip correctly today
through `Lang_cmake.Apply` and stay in the `generic` bucket. A
two-phase plan (corpus-wide function-name table, then dynamic
dispatch resolution) is deferred — it steps into cmake
configure-time behavior and belongs alongside behavior-level
oracles rather than as a parser-only patch. See
[`doc/yelu_cmake/bar3_lite_report.md`](../../doc/yelu_cmake/bar3_lite_report.md) § 5.
