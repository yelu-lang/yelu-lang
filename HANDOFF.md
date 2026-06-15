# Handoff — 2026-06-14

> Per-command syntax track for the property family. Worklog entry with
> full detail in [`doc/worklog/worklog_2026_06.md`](doc/worklog/worklog_2026_06.md)
> § "2026-06-13/14"; design questions for the next track in
> [`doc/lang/object_value_design.md`](doc/lang/object_value_design.md).

## What landed

### Property family unified + entity-driven

- `set_property` IR: 4 ctors → 1 (`ECmakeSetProperty { scope; append;
  append_string; properties }`) mirroring `Lang_cmake.Set_property` 1:1.
- `get_property` IR: TARGET-only `{ var; target; property; set_form :
  bool }` → 1 unified `{ var; scope; property; mode : get_property_mode }`
  mirroring `Lang_cmake.Get_property` 1:1.
- `cache_entry = Cache_entry` placeholder (in `Lang_cmake`) lifted to
  `cache_entry = string` — CACHE-scope entry names were being silently
  dropped on emit. Now flow through end-to-end.
- `append_string` field — was missing from the yc IR; cmake AST had it.
- Parser-local `cmake_entity` value + `p_cmake_entity` reading group —
  parallel for `entity_to_sps` / `entity_to_gps`. First-class kinded
  cmake object as a parser concept (`Target foo`, `Source 'main.c'`,
  `Cache FOO`, `Test t`, `Install f`, `Directory ['d']`, `Global`,
  `Variable`). Pos3 prototype — see Y18 / object_value_design.md for
  the value-class promotion design.

### Lane B / Lane C complete for the property family

- `set_property → ["APPEND"; "APPEND_STRING"]` in `command_flags`.
- `get_property → [("PROPERTY", "property")]` in `command_value_labels`
  (Lane C shape-1 — single property name).
- `set_property → [("PROPERTY", "property")]` in the new
  `command_value_list_labels` (Lane C shape-3 — name + multi-value list
  via `~property=[NAME, val1, val2, …]`). The list-kwarg parser
  generalized in `yelu_parse.ml` (was hard-coded to
  `public`/`private`/`interface`); per-command handlers recover the
  list via `filter_map` with source-order preservation.

### `Yelu_lexer.constr_names` — slice 3 + slice 4

- Slice 3: `GLOBAL` / `DIRECTORY` / `SOURCE` / `INSTALL` / `TEST` /
  `CACHE` (set_property + get_property scope discriminators).
- Slice 4: `VARIABLE` + the get_property mode constructors `SET` /
  `DEFINED` / `BRIEF_DOCS` / `FULL_DOCS`.

### `:=` low-priority command-call sugar

```text
var   := get_property Target foo ~property=NAME      # → get_property(var TARGET foo PROPERTY NAME)
var   := get_property Cache FOO ~property=STRINGS    # → get_property(var CACHE ${FOO} PROPERTY STRINGS)
upper := string_toupper 'hello'                       # → string(TOUPPER hello upper)
joined := list_join MYLIST ','                        # → list(JOIN MYLIST , joined)
var   := "hello"                                      # legacy value-assign — unchanged
```

Both parsers (CST + legacy) detect "next IDENT after `:=` is a known
command followed by command-shape tokens" and parse the rest as a full
command call. CST emits a new `S_assign_call` variant; lowering
injects `~out=lhs` and routes through the regular command lowerer.
Legacy parser dispatches via three forward refs populated at file
bottom (call-chain order makes `p_assign_y1` precede its dependencies).

## State of the world

- `dune runtest --force` — **935 tests / 0 failures**.
- Byte-equality oracle (`covered=194`) green throughout.
- tm-grammar regenerated; co-truth lock satisfied.
- `Yc_primitives.command_names` gained `get_property` (was missing —
  surfaced by `is_known_command "get_property"` in the `:=` sugar).
- ✅ **fmt matrix 24/24** (regression fixed `f1296a4`). It had gone 0/24:
  the property rewrite emitted entity names derefed (`CACHE ${FOO}`); fixed
  by normalizing bare `EVar` → `EString` (literal) in `p_cmake_entity`.
  The unit `dune test` + byte-equality oracle compare yc-AST↔legacy and the
  two parse paths to **each other** — they do NOT configure the generated
  cmake. The **matrix does** (`yelu matrix probes/fmt`) and is the only
  oracle that caught it; **it was not run** the session that introduced the
  bug. Add it to the verification checklist (it is NOT part of `dune test`).

## What's next (handed off open)

- ✅ **(done `f1296a4`) property-family entity-name deref regression.** Bare
  entity names now lower to literals (`EVar → EString` in `p_cmake_entity`);
  `$var` still derefs. Matrix back to 24/24. The bug-encoding unit assertions
  (`CACHE ${FOO}`) were corrected to the literal form.
- **`set_target_properties` literal target + multi-PROPERTY (latent, NOT a
  matrix-breaker today).** `set_target_properties fmt …` still emits
  `set_target_properties(${fmt} …)` — it's a separate command that does NOT
  go through `p_cmake_entity`, so the entity fix didn't reach it. The corpus's
  only literal-target use (main.yc:139) sits in a branch the matrix doesn't
  configure, so it stays green; but the emit is wrong for a literal target and
  should get the same EVar→EString treatment. Also: multi-`PROPERTY`
  (`PROPERTY VERSION … PROPERTY SOVERSION …`) keeps only the FIRST clause —
  matrix-invisible (properties don't affect configure), needs its own fix.
- **Y18 — first-class object value.** Promote `cmake_entity` from
  parser-local to an IR value class. Whole design needed; questions
  collected in [`doc/lang/object_value_design.md`](doc/lang/object_value_design.md).
  Tied to the long-term object-method form `target_foo.set_property(…)`
  the user flagged.
- **get_property mode-flag-as-kwarg-enum micro-slice.** Trailing
  positional `SET`/`DEFINED`/`BRIEF_DOCS`/`FULL_DOCS` canonicalizes to
  leading-cap (`Defined`) today but does not become `~mode=Defined`.
  Needs a per-command "flag-as-kwarg-enum" rewriter — ~30 lines, only
  get_property genuinely benefits.
- **`set_target_properties PROPERTIES K v K v …`** — shape-3 record
  literal territory. Surface migration parked in
  [`doc/lang/yc_syntax_critique.md`](doc/lang/yc_syntax_critique.md)
  pending record-literal grammar.
- **Three specialized cmake getters yc doesn't have:**
  `get_source_file_property` / `get_test_property` / `get_cmake_property`.
  Mostly cosmetic — generic `get_property Source/Test` now covers two.
- **Property cache-semantics combination test** — exercising Value vs
  SET vs DEFINED. Defer until a weird bug surfaces.

## Build & run

```sh
dune build
dune test                    # 935/935

# Smoke
dune exec src/bin/yelu/yelu.exe -- fmt probes/fmt/main.yc
dune exec src/bin/yelu/yelu.exe -- compile probes/fmt/main.yc

# Grammar co-truth
make tmgrammar-check         # or: dune exec src/bin/yelu/yelu.exe -- tmgrammar -o …
```

## Macros for the next Claude

- LSP exe (`src/bin/yelu_lsp/`) needs the `linol` / `linol-lwt`
  yojson-3 fork pinned at a path that's Linux-only today; on a fresh
  macOS clone, the LSP exe fails to build but every other target
  works. Excluding `src/bin/yelu_lsp/` from the build target list (or
  using `dune build src/langs src/bin/{yelu,cmake,cmake_only,debug}
  test`) is the workaround. Not in scope for the current syntax work.
- Vendor symlinks (`vendor/cmake`, `vendor/fmt`, `vendor/llvm`,
  `vendor/z3`) point at Linux paths (`/home/red/code/contrib/…`). Mac
  equivalents under `/Users/ex/code/contrib/…`. Only matters for the
  cmake-backed targets (`make cmake-check`, file-api, Bar #3-lite
  oracle) — not for `dune test`.
- Markdown lint warnings about table-column alignment in CLAUDE.md
  are pre-existing and not from this session.
