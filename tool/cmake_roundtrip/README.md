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
- `.cmake.in` templates with `@VAR@` placeholders are handled
  via a tree-sitter-ERROR fallback: when the root has an ERROR
  spanning the whole file, the source is preserved verbatim as
  a `raw` chunk. Gersemi is idempotent on this kind of opaque
  text, so the round-trip stays byte-identical.
- 25/25 yelu-emitted tutorial step files round-trip with
  byte-identical output after gersemi normalization.
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
- **`.cmake.in` template handling is coarse** — when tree-sitter
  flags the whole root as ERROR (mis-lexing `@VAR@` placeholders
  as an unclosed bracket argument), the source is preserved
  verbatim as a single `raw` chunk. We lose any inner structure
  the file might have had. Acceptable for the round-trip claim
  (gersemi is idempotent on the same opaque text), but a finer
  pass-through that parses non-template chunks structurally
  would be a Stage-2+ enhancement. TODO: tree-sitter-cmake
  upstream may also be teachable to accept `@VAR@` tokens.

## Stage 2 — typed mapping into `Lang_cmake.exp`

`print2.exe` (built from `print2.ml`) is the typed variant: walks
the Stage-1 AST, dispatches each `Cmd` to a per-command parser
that produces `Lang_cmake.exp`, and reprints via
`Lang_cmake_pp`. Commands without a typed parser fall through to
Stage-1 untyped emission, so the round-trip stays byte-equal
even at partial coverage.

Set `STAGE2_COVERAGE=1` for a one-line tally on stderr:

```
[stage2] typed=7 untyped=0 other=0
```

### Current coverage (tutorial corpus, 25 files, 213 cmds)

| typed | untyped | block/raw | round-trip |
| ---: | ---: | ---: | --- |
| 155 (73%) | 35 (16%) | 23 (11%) | 25/25 byte-identical (gersemi) |

**Typed commands** (15): `cmake_minimum_required`, `project`,
`set`, `message`, `configure_file`, `add_executable`,
`add_library`, `target_link_libraries`,
`target_include_directories`, `target_compile_definitions`,
`target_compile_options`, `target_compile_features`, `option`,
`include`, `add_subdirectory`.

**Untyped remainder** in the tutorial:
- `install` × 14 — Install_targets / Install_files /
  Install_export, multi-keyword. Worth adding.
- `check_cxx_source_compiles` × 10 — a **cmake module function**
  (defined in `CheckCXXSourceCompiles.cmake`), not a builtin.
  `Lang_cmake.exp` has no ctor because the cmake AST only models
  builtin commands. Correctly falls through to untyped.
- `list` × 7, `set_target_properties` × 3,
  `add_custom_command` × 1 — Stage 2 extensions; ctor exists,
  just need argument parser.

The 23 "block/raw" count is `if`/`foreach`/`while`/`function`/
`macro`/`block` heads + tails + raw passthrough chunks. Typed
mapping of block shapes (`If { cond; then_; else_ }` etc.) is
Stage 2-b.

### Gotchas surfaced during Stage 2

- **`Bool true` printer mismatch.** `Lang_cmake_pp` emits
  `Bool true` as `True`, but cmake idioms (e.g.
  `option(... ON)`) want the original token preserved. Fix: map
  `ON`/`OFF`/`TRUE`/etc. to `Var_exp "ON"` in `parse_option`
  rather than `Bool true`. This is a printer-vs-source-style
  decision that surfaces only via the round-trip oracle.
- **`Include.no_policy_scope : scope option` is wrong shape.**
  The IR field type is `scope option` (with scope =
  Function_scope | Directory_scope) but `NO_POLICY_SCOPE` in
  cmake is a boolean. Tutorial doesn't use it; the parser
  bails to fallback if seen so we don't lossy-map. Real fix is
  an IR field-type correction.

### Next (Stage 2-b)

- `install` parser (the biggest single bucket).
- `list` parser (touches `list_cmd` subtypes).
- Typed block mapping for `if` / `foreach` / `function` etc.
- Try the round-trip on **z3's CMakeLists** corpus to surface
  the next batch of missing commands and IR shape gaps.
