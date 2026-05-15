# cmake_roundtrip — Stage 1 prototype

Round-trip cmake source through a tree-sitter-cmake parser and an
OCaml reprinter, using gersemi as the normalization oracle. The
manifesto-level framing lives in
`doc/yelu_cmake/bar3_feasibility.md` (Bar #3-lite).

## Pipeline

```
input.cmake
  → parse.py (tree-sitter-cmake)        → CST JSON on stdout
  → print.exe (OCaml: yojson + Buffer)  → reprinted cmake on stdout
  → gersemi -                            → canonicalized cmake on stdout
```

Compared against `gersemi input.cmake`. Stage 1 strips blank
lines on both sides before diffing — blank-line preservation is a
Stage 2 item.

## Current status

- All 14 covered statement shapes round-trip: `normal_command`,
  `if_condition` (with `elseif`/`else`), `foreach_loop`,
  `while_loop`, `function_def`, `macro_def`, `block_def`. Each
  preserves: identifier name, ordered arguments, raw argument
  text (so quoting / bracket framing is byte-identical), and
  literal `(`/`)` tokens used for inner grouping (e.g.
  `if((A AND B))`).
- 24/25 yelu-emitted tutorial step files round-trip with
  byte-identical output after gersemi normalization. The 25th
  (`step11_config`) is a `.cmake.in` template with `@PACKAGE_INIT@`
  — not valid cmake source, correctly flagged as ERROR by
  tree-sitter.
- Untyped AST: each argument is a string of raw source text.
  Typed mapping into `Lang_cmake.exp` is Stage 2.

## Files

- `parse.py` — Python wrapper. ~140 lines. Reads cmake on
  stdin or from argv[1]; writes CST JSON on stdout.
- `print.ml` — OCaml reprinter. ~155 lines. Reads JSON on
  stdin; writes cmake on stdout. Untyped AST.
- `dune` — builds `print.exe` (depends on base + yojson).

## Reproducing locally

```sh
# generate the tutorial corpus
mkdir -p /tmp/tutorial_cmake
for f in _build/default/src/bin/yelu/v1/*.exe; do
  "$f" > "/tmp/tutorial_cmake/$(basename "$f" .exe).cmake"
done

# round-trip one file
python3 tool/cmake_roundtrip/parse.py /tmp/tutorial_cmake/step1.cmake \
  | _build/default/tool/cmake_roundtrip/print.exe \
  | gersemi -

# diff against the gersemi-normalized original
diff <(gersemi /tmp/tutorial_cmake/step1.cmake | grep -v "^$") \
     <(python3 tool/cmake_roundtrip/parse.py /tmp/tutorial_cmake/step1.cmake \
       | _build/default/tool/cmake_roundtrip/print.exe \
       | gersemi - | grep -v "^$")
```

## Dependencies

- `tree-sitter` and `tree-sitter-cmake` Python packages (install
  via `uv pip install tree-sitter tree-sitter-cmake`)
- `gersemi` (install via `uv pip install gersemi`)
- OCaml: `base`, `yojson` (both already common deps)

## Known limitations (Stage 1)

- **Untyped args** — each arg is raw source text. Doesn't test
  `Lang_cmake.exp` expressiveness; that's Stage 2.
- **Blank lines collapsed** — tree-sitter exposes them only as
  extra whitespace, not nodes. Diff strips them on both sides.
- **Comments dropped** — tree-sitter parses `line_comment` /
  `bracket_comment` nodes but the parser skips them. Stage 2 or
  later.
- **`.cmake.in` templates not supported** — tree-sitter rejects
  `@VAR@` at file scope. These are configure-time templates,
  not raw cmake.

## Next (Stage 2)

Typed mapping: `CST JSON → Lang_cmake.exp`. Each command's
arguments parse into the per-command typed shape. Start with the
~20 most common commands (`set`, `if`, `add_executable`,
`add_library`, `target_link_libraries`,
`target_include_directories`, `target_compile_*`,
`set_target_properties`, `configure_file`, `install`,
`add_subdirectory`, `include`, `option`, `message`, `foreach`,
`while`, `function`, `macro`, `list`, `string`). Grow
incrementally; commands that fail to parse become the coverage
TODO.
