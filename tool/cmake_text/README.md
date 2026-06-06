# cmake_text — tools that operate on cmake text

Syntactic round-trip oracle for real-world cmake. Parses cmake source
via tree-sitter-cmake, reprints it through `Lang_cmake.exp` +
`Lang_cmake_pp` (production yelu IR), and verifies tree-sitter
re-extracts the same `(command_name, args)` sequence on both sides.

## Files

| file | purpose |
| --- | --- |
| `cmake_to_json.py` | Python wrapper around `tree-sitter-cmake`. Reads cmake on stdin or argv[1]; writes CST JSON on stdout. |
| `cmake_strip_comments.py` | Tree-sitter–based comment stripper, used by the gersemi-diff oracle preprocessor (our parser drops inline-arg comments). |
| `cmake_reprint.ml` | OCaml driver. JSON reader → per-command typed parsers → `Lang_cmake_pp` → untyped `Apply` fallback. |
| `cmake_cache_scan.ml` | OCaml. Enumerate every user-settable cmake cache var (`option()` / `set(...CACHE...)`) in a project directory. |
| `cmake_name_index.ml` | OCaml. Walk a cmake corpus and emit `<name>\t<file>\t<function\|macro>` TSV for every function/macro definition. |
| `cmake_reserved_vars.tsv` | Data. Snapshot of 1597 reserved cmake variable names (cmake 4.3.1). |
| `cmake_roundtrip_oracle.sh` | Harness. Runs the pipeline on every `CMakeLists.txt`/`*.cmake` in a directory tree, applies the STRUCT + FORMAT oracles, prints per-file verdicts + summary. |
| `dune` | Builds `cmake_reprint.exe`, `cmake_cache_scan.exe`, `cmake_name_index.exe`. |

## Pipeline

```
input.cmake
  → cmake_to_json.py      (tree-sitter-cmake)    → CST JSON on stdout
  → cmake_reprint.exe     (OCaml, Lang_cmake.exp + Apply fallback) → reprinted cmake
  → gersemi -                                    → canonicalized
```

Per-file verdict from `cmake_roundtrip_oracle.sh`:

- **OK** — STRUCT match (tree-sitter extracts same command/arg
  sequence from source and reprint) AND gersemi-normalized text
  matches modulo whitespace.
- **FORMAT** — STRUCT match but gersemi-diff fail. Cosmetic.
- **STRUCT** — STRUCT fail. Real parser/printer/IR bug.
- **PARSE** — tree-sitter or our reader fails.

## Reproducing locally

```sh
# Build
dune build tool/cmake_text/cmake_reprint.exe

# Round-trip one file
python3 tool/cmake_text/cmake_to_json.py path/to/CMakeLists.txt \
  | _build/default/tool/cmake_text/cmake_reprint.exe

# Run the full oracle on a corpus
bash tool/cmake_text/cmake_roundtrip_oracle.sh path/to/cmake_corpus

# Coverage tally only (stderr line per file)
python3 tool/cmake_text/cmake_to_json.py path/to/CMakeLists.txt \
  | STAGE2_COVERAGE=1 _build/default/tool/cmake_text/cmake_reprint.exe \
    >/dev/null
```

## Dependencies

- Python: `tree-sitter`, `tree-sitter-cmake`
- `gersemi` (cmake formatter; used as the normalization oracle)
- OCaml: `base`, `yojson`, `yelu_langs` (in-tree)

Harness defaults to `gersemi` at `/home/red/.venvs/default/bin/gersemi`;
override via `GERSEMI=/path/to/gersemi`.
