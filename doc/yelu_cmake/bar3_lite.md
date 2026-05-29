# Bar #3-lite — cmake syntactic round-trip

> **Status (2026-05-20).** Shipped through Stage 2-c. STRUCT=0 /
> FORMAT=0 across tutorial (25/25), z3 (108/108), llvm (596/596).
> Audit-ready. Chronological history of the milestone (stages,
> Codex audit responses, retirement context) lives in
> [`../worklog/worklog_2026_05.md`](../worklog/worklog_2026_05.md).
>
> Tracker: [`status.md`](status.md). Tool README:
> [`../../tool/cmake_roundtrip/README.md`](../../tool/cmake_roundtrip/README.md).

## 1. Claim and counter-claim

**Claim.** The production yelu cmake IR (`Lang_cmake.exp`) together
with its printer (`Lang_cmake_pp`) is **structurally faithful to
real-world cmake**. Given any source file from the corpora below,
parsing through tree-sitter-cmake and reprinting via the IR
produces text from which tree-sitter re-extracts the same
`(command_name, arg-list)` sequence as the source.

**Counter-claim we do NOT make.** This is a *syntactic* claim,
not a *semantic* one. The harness does not run cmake. It does
not assert that the reprinted file produces the same configure
output, build graph, or File API JSON as the source. Behavior-
level claims require running real cmake builds — a separate,
more expensive oracle. This stage proves the IR shape is rich
enough to carry every command-call shape real projects use.

## 2. Oracles

Per-file verdict produced by
[`test_corpus.sh`](../../tool/cmake_roundtrip/test_corpus.sh):

- **STRUCT** (load-bearing) — extract `(name, args)` tuples
  from source and reprint via tree-sitter; exact string match.
  Purely a function of `Lang_cmake.exp` expressiveness and
  `Lang_cmake_pp` correctness.
- **FORMAT** (informational) — gersemi-normalize both sides
  (`--line-length 99999`, comments stripped on the source side
  because our parser drops inline-arg comments), then collapse
  whitespace and string-compare. Asserts content equivalence
  modulo cosmetic layout; gersemi's wrap heuristic prevents
  true byte equality, so this is intentionally soft.

| bucket | meaning |
| --- | --- |
| OK | STRUCT pass AND FORMAT pass |
| FORMAT | STRUCT pass, FORMAT fail (cosmetic) |
| STRUCT | STRUCT fail (real parser / printer / IR bug) |
| PARSE | tree-sitter or our JSON reader fail |

OK guarantees that every command in the source is present in the
reprint, in order, with the same name and same number of
arguments, and that every argument carries the same textual
content (modulo whitespace and inline-arg comments).

## 3. Results

```
tutorial step outputs : 25/25  OK   modeled=165   generic=25    other=23
z3                    : 108/108 OK  modeled=1056  generic=707   other=1711
llvm/llvm             : 596/596 OK  modeled=3572  generic=2610  other=4029
```

All three corpora: **STRUCT=0, FORMAT=0**.

Bucket definitions (no ratio is reported — see § 6):

- **modeled** — command mapped to a dedicated `Lang_cmake.exp`
  constructor (`Add_executable`, `Target_link_libraries`,
  `Find_package`, …).
- **generic** — command constructed as `Lang_cmake.Apply { name;
  args }` and reprinted via the production `Lang_cmake_pp` Apply
  arm.
- **other** — one per block wrapper node
  (`if_condition`/`foreach_loop`/`while_loop`/`function_def`/
  `macro_def`/`block_def`) + one per raw passthrough chunk
  (`.cmake.in` templates the tree-sitter grammar mis-lexes) + one
  per tree-sitter ERROR fragment. Block heads/tails are reprinted
  raw via `print_block_head` and contribute to no bucket.

## 4. Running, reading, debugging

### 4.1 Running

```sh
# Project-local venv has tree-sitter / tree-sitter-cmake / gersemi
export PATH=/home/red/.venvs/default/bin:$PATH

dune build tool/cmake_roundtrip/print2.exe

# Corpus
bash tool/cmake_roundtrip/test_corpus.sh /path/to/corpus

# Single file
python3 tool/cmake_roundtrip/parse.py path/to/CMakeLists.txt \
  | _build/default/tool/cmake_roundtrip/print2.exe

# With coverage tally on stderr
python3 tool/cmake_roundtrip/parse.py path/to/CMakeLists.txt \
  | STAGE2_COVERAGE=1 _build/default/tool/cmake_roundtrip/print2.exe \
    >/dev/null
# → [stage2] modeled=N generic=N other=N
```

The harness exits 2 before processing files if `gersemi` or
`print2.exe` is missing — without those pre-flight checks a
broken formatter would make both sides empty and FORMAT would
pass spuriously.

### 4.2 Per-file output

Each file prints one line:

```
OK     relpath  modeled/generic/other
FORMAT relpath  modeled/generic/other
STRUCT relpath
PARSE  relpath
```

End-of-run summary block tallies the buckets and emits
`Stage 2 cmds: modeled=N generic=N other=N`.

### 4.3 Debugging a failure

**STRUCT** — direct diff of source vs round-trip:

```sh
f=path/to/file.cmake
diff <(cat "$f") \
     <(python3 tool/cmake_roundtrip/parse.py "$f" \
         | _build/default/tool/cmake_roundtrip/print2.exe)
```

First diverging command is the bug locus. All five
production-IR bugs surfaced by this milestone (§ 7) were found
this way.

**FORMAT** — diff gersemi-normalized output. Currently 0/729; a
new FORMAT failure on a fresh corpus would surface a gersemi
normalization gap.

**PARSE** — run `parse.py` in isolation; check stderr.
`.cmake.in` templates do *not* hit this bucket — they pass as
OK with `other > 0` via the raw-passthrough fallback.

## 5. Architecture

### File inventory (`tool/cmake_roundtrip/`)

| file | LOC | role |
| --- | ---: | --- |
| [`parse.py`](../../tool/cmake_roundtrip/parse.py) | 214 | tree-sitter-cmake → JSON CST. Adjacent-arg concatenation, ERROR-root passthrough, block recognition. |
| [`print2.ml`](../../tool/cmake_roundtrip/print2.ml) | ~1,150 | JSON reader + 30 per-command typed parsers + dispatch + emit + driver. |
| [`strip_comments.py`](../../tool/cmake_roundtrip/strip_comments.py) | 70 | tree-sitter–based comment stripper for the FORMAT oracle preprocessor. |
| [`test_corpus.sh`](../../tool/cmake_roundtrip/test_corpus.sh) | ~175 | Harness: per-file STRUCT + FORMAT + summary. |
| `dune` | 8 | Builds `print2.exe`. |

### Production modules exercised (`src/langs/cmake/`)

- [`lang_cmake.ml`](../../src/langs/cmake/lang_cmake.ml) — IR.
  Round-trip surfaced two bugs here (`Include.no_policy_scope`
  type, `arg.Bracket` level loss) — both fixed in production.
- [`lang_cmake_pp.ml`](../../src/langs/cmake/lang_cmake_pp.ml) —
  printer. Round-trip surfaced three bugs here (`Configure_file`
  flag cross-swap, `Include.result_var` missing keyword,
  `pp_arg.Bracket` newline injection) — all fixed in production.

### Data flow

```
input.cmake
  └─ parse.py        tree-sitter → CST JSON
       └─ print2.ml
            ├─ file_of_json           JSON → Stage-1 untyped AST
            ├─ parse_cmd dispatch     Stage-1 Cmd → Lang_cmake.exp option
            │     ├─ Some e          → Lang_cmake_pp.pp e               (modeled)
            │     └─ None            → Lang_cmake.Apply{name;args}
            │                            → Lang_cmake_pp Apply arm      (generic)
            ├─ block walker           recursive descent (body / clauses)
            │                          heads/tails reprinted raw
            └─ raw / unknown          verbatim passthrough
  └─ stdout: reprinted cmake
```

The dispatcher in `parse_cmd` is a single match on lowercased
command names, 30 modeled branches, catch-all `None` → generic
Apply via the production printer. Each parser follows the
**bail-to-Apply discipline**: if the input would lose
information or force the printer to reorder, return `None`.

## 6. Scope and intentional limits

### Why no `modeled / (modeled+generic)` ratio

Many `generic` commands are project- or module-defined
cmake functions (`z3_add_component`, `tablegen`, `add_llvm_*`,
the `CheckXxx` standard-module family) — they are correctly
never modeled by `Lang_cmake.exp`, which is by design an IR
for cmake **builtins**. A ratio would conflate "we haven't
modeled this builtin yet" with "this is user-defined and
should stay generic". Raw counts are the honest signal.

### Class A: project- and module-defined cmake functions (deferred)

Calls into `function()` / `macro()` bodies defined elsewhere
in the corpus or in cmake's standard `Modules/`. Real cmake
dispatches them dynamically at execution time against a name
table built from `include(...)` and `find_package(...)`. They
round-trip byte-faithfully via `Lang_cmake.Apply` today.

A planned **two-phase Class A** is deferred — it inherently
models cmake configure-time behavior and belongs alongside
behavior-level oracles rather than as a parser-only patch:

- **Phase 1 — function-aware accounting (cheap).** Single pass
  over the corpus collects every `function(<name>...)` /
  `macro(<name>...)` definition. Stage-2 then tags Apply calls
  whose name resolves against the table as `resolved` vs
  `external`. New coverage bucket between `modeled` and
  `generic`. Round-trip oracle unchanged; only the tally
  becomes more honest.
- **Phase 2 — dynamic dispatch resolution (semantic).** Given
  `z3_add_component(api)`, resolve to the function body and
  inline-substitute (macro semantics) or push a scope with
  bound parameters (function semantics). Blockers: conditional
  `include()`, dynamic `CMAKE_MODULE_PATH`, macro vs function
  scope semantics, generator-expression delay.

### Builtins routed to Apply because the printer is lossy

These have a `Lang_cmake.exp` constructor but currently flow
through `Apply` because the printer drops fields or shape
inversion is brittle. They are the target of the upcoming
**IR-printer cleanup** in [`status.md`](status.md):

- Several `file` subcommands (READ, STRINGS, COPY, DOWNLOAD,
  UPLOAD, LOCK, path-query family).

These are not STRUCT failures. They are typed-coverage
opportunities for the IR-printer cleanup pass.

### Comments

- **Top-level** comments (between commands, at file scope or
  inside `body`) preserved as `Raw` nodes; reprinted verbatim.
- **Inside `argument_list`** dropped by `parse.py` (the
  production IR doesn't model them). The FORMAT oracle
  compensates via `strip_comments.py` on the source side.

Whether `yelu_cmake` / `yelu_cmake_normal` should carry comments
as AST metadata is a deferred design question.

## 7. Production bugs surfaced

Five bugs in the production yelu IR + printer that the
existing test suite did not catch — caught only by running
the round-trip on z3 and especially llvm:

| # | bug | fix |
| -: | --- | --- |
| 1 | `Include.no_policy_scope` typed as `scope option` (irrelevant enum); cmake's `NO_POLICY_SCOPE` is a boolean flag. | `13d813c` |
| 2 | `Configure_file` flags `@ONLY` and `ESCAPE_QUOTES` wired to the wrong fields in the printer (cross-swap). | `6a6295a` |
| 3 | `Include.result_var` printed without the `RESULT_VARIABLE` keyword. | `6a6295a` |
| 4 | `pp_arg.Bracket` added surrounding newlines around content. | `6a6295a` |
| 5 | `Lang_cmake.arg.Bracket of string` lost the bracket-quote level (`[==[…]==]` vs `[=[…]=]`). Widened to `Bracket of int * string`. | `91cb43e` |

This is the strongest single argument for the round-trip as
ongoing infrastructure: it catches IR shape bugs that the
synthetic tutorial corpus does not exercise, on a real
high-quality codebase that no other yelu test path reaches.

## 8. Per-parser contract sheet

30 cmake builtins modeled, dispatched in `parse_cmd`. Each
row is the contract a per-parser audit would attack on two
axes: **STRUCT preservation** (tree-sitter re-extracts the
same `(name, args)` sequence) AND **typed-IR classification**
(the chosen `Lang_cmake.exp` constructor and field assignments
match what the source meant). STRUCT can pass while typed
meaning is misclassified — see § 9 for the canonical
`add_executable WIN32 main.c` example that motivated the
dual-axis framing.

Coverage by stage (30 dispatched commands, 15 + 8 + 7):

| stage | count | parsers |
| --- | ---: | --- |
| original Stage 2 | 15 | `cmake_minimum_required`, `project`, `set`, `message`, `configure_file`, `add_executable`, `add_library`, `target_link_libraries`, `target_include_directories`, `target_compile_definitions`, `target_compile_options`, `target_compile_features`, `option`, `include`, `add_subdirectory` |
| Stage 2-b | 8 | `unset`, `add_dependencies`, `find_package`, `get_filename_component`, `set_target_properties`, `add_custom_target`, `list`, `string` |
| Stage 2-c | 7 | `return`, `include_directories`, `find_program`, `find_path`, `install`, `add_custom_command`, `file` |
| Tier 2 cleanup | 3 | `set_property`, `get_property`, `execute_process` |

(Helper functions like `parse_find_var_names` back two dispatched
commands; subcommand dispatchers like `parse_list` /
`parse_string` / `parse_file` enumerate many cmake subcommands
within a single dispatched name.)

Line numbers are as of commit `db83c7e`. Use `grep -n "^let
parse_<name>"` if stale. "Lossy IR field" = IR has the field
but the printer drops it; parser must bail on inputs that
would populate it.

### 8.1 cmake_minimum_required

- **Location**: [`print2.ml:210`](../../tool/cmake_roundtrip/print2.ml#L210)
- **IR**: [`Cmake_minimum_required` at `lang_cmake.ml:599`](../../src/langs/cmake/lang_cmake.ml#L599)
- **Printer**: [`lang_cmake_pp.ml:781`](../../src/langs/cmake/lang_cmake_pp.ml#L781)
- **Accepts**:
  - `cmake_minimum_required(VERSION <min>)` with numeric
    dot-separated `<min>`.
  - `cmake_minimum_required(VERSION <min>...<max>)` range form
    with numeric dot-separated `<min>` and `<max>` — printer
    wired up to emit both bounds 2026-05-25.
- **Bails on**: non-numeric `<min>` or `<max>` (e.g. `${VAR}`);
  trailing `FATAL_ERROR` / other tokens; non-VERSION first arg.

### 8.2 project

- **Location**: [`print2.ml:240`](../../tool/cmake_roundtrip/print2.ml#L240)
- **IR**: [`Project` at `lang_cmake.ml:875`](../../src/langs/cmake/lang_cmake.ml#L875)
- **Printer**: [`lang_cmake_pp.ml:966`](../../src/langs/cmake/lang_cmake_pp.ml#L966)
- **Accepts**: `project(<name> [VERSION <ver>] [LANGUAGES <l>...])`,
  numeric VERSION.
- **Bails on**: non-numeric VERSION, DESCRIPTION / HOMEPAGE_URL
  (printer always quotes them → arg shape mismatch), unknown
  keywords.
- **Known gaps**: DESCRIPTION/HOMEPAGE_URL fields exist in IR
  but printer quoting prevents accept; would need either bare
  or quoted source convention.

### 8.3 set

- **Location**: [`print2.ml:277`](../../tool/cmake_roundtrip/print2.ml#L277)
- **IR**: [`Set` at `lang_cmake.ml:421`](../../src/langs/cmake/lang_cmake.ml#L421)
- **Printer**: [`lang_cmake_pp.ml:566`](../../src/langs/cmake/lang_cmake_pp.ml#L566)
- **Accepts**: `set(<var> <val>... [PARENT_SCOPE])`.
- **Bails on**: CACHE form, `set(ENV{<var>} <val>)`.
- **Known gaps**: cache / env namespaces are tracked in
  `status.md` "Deferred".

### 8.4 message

- **Location**: [`print2.ml:310`](../../tool/cmake_roundtrip/print2.ml#L310)
- **IR**: [`Message` at `lang_cmake.ml:535`](../../src/langs/cmake/lang_cmake.ml#L535)
- **Printer**: [`lang_cmake_pp.ml:654`](../../src/langs/cmake/lang_cmake_pp.ml#L654)
- **Accepts**: `message([<mode>] <text>...)` with all-quoted texts.
- **Bails on**: bare text (printer always quotes), mixed
  quoted/bare, `CONFIGURE_LOG` mode (separate ctor).

### 8.5 configure_file

- **Location**: [`print2.ml:328`](../../tool/cmake_roundtrip/print2.ml#L328)
- **IR**: [`Configure_file` at `lang_cmake.ml:619`](../../src/langs/cmake/lang_cmake.ml#L619)
- **Printer**: [`lang_cmake_pp.ml:783`](../../src/langs/cmake/lang_cmake_pp.ml#L783)
- **Accepts**: `configure_file(<in> <out> [COPYONLY] [ESCAPE_QUOTES]
  [@ONLY])` with bare in/out.
- **Bails on**: quoted in/out, `NEWLINE_STYLE`, permission keywords.

### 8.6 add_executable

- **Location**: [`print2.ml:355`](../../tool/cmake_roundtrip/print2.ml#L355)
- **IR**: [`Add_executable`](../../src/langs/cmake/lang_cmake.ml#L727)
  + [`Add_executable_imported`](../../src/langs/cmake/lang_cmake.ml#L732)
  + [`Add_executable_alias`](../../src/langs/cmake/lang_cmake.ml#L733)
- **Printer**: [`lang_cmake_pp.ml:1013`](../../src/langs/cmake/lang_cmake_pp.ml#L1013)
- **Accepts** (updated 2026-05-29):
  - `add_executable(<name> [WIN32] [MACOSX_BUNDLE] [EXCLUDE_FROM_ALL] <src>...)`
    — options consumed positionally in source order into the IR's
    `options` field (`Ae_win32` / `Ae_macos_bundle` /
    `Ae_exclude_from_all`).
  - `add_executable(<name> IMPORTED [GLOBAL])` → `Add_executable_imported`.
  - `add_executable(<name> ALIAS <target>)` → `Add_executable_alias`.
- **Bails on**: reserved option keyword appearing among `sources`
  after a non-option arg (would misclassify), or arg-list shape
  not matching one of the above.

### 8.7 add_library

- **Location**: [`print2.ml:372`](../../tool/cmake_roundtrip/print2.ml#L372)
- **IR**: [`Add_library`](../../src/langs/cmake/lang_cmake.ml#L734)
  + [`Add_library_imported`](../../src/langs/cmake/lang_cmake.ml#L740)
  + [`Add_library_object`](../../src/langs/cmake/lang_cmake.ml#L741)
  + [`Add_library_interface`](../../src/langs/cmake/lang_cmake.ml#L742)
  + [`Add_library_alias`](../../src/langs/cmake/lang_cmake.ml#L743)
- **Printer**: [`lang_cmake_pp.ml:1036`](../../src/langs/cmake/lang_cmake_pp.ml#L1036)
- **Accepts** (updated 2026-05-29):
  - `add_library(<name> [STATIC|SHARED|MODULE|UNKNOWN] [EXCLUDE_FROM_ALL] <src>...)`
  - `add_library(<name> OBJECT <src>...)` → `Add_library_object`.
  - `add_library(<name> INTERFACE)` → `Add_library_interface`.
  - `add_library(<name> [<type>] IMPORTED [GLOBAL])` →
    `Add_library_imported` (type ∈ STATIC/SHARED/MODULE/UNKNOWN/OBJECT/INTERFACE).
  - `add_library(<name> ALIAS <target>)` → `Add_library_alias`.
- **Bails on**: IMPORTED with non-recognized lib_type; misplaced
  ALIAS / IMPORTED keyword.

### 8.8 target_link_libraries

- **Location**: [`print2.ml:430`](../../tool/cmake_roundtrip/print2.ml#L430)
- **IR**: [`Target_link_libraries` at `lang_cmake.ml:732`](../../src/langs/cmake/lang_cmake.ml#L732)
- **Printer**: [`lang_cmake_pp.ml:1034`](../../src/langs/cmake/lang_cmake_pp.ml#L1034)
- **Accepts**: `target_link_libraries(<t> {PRIVATE|PUBLIC|INTERFACE <lib>...}+)`
  with at least one visibility keyword. Mixed visibility groups
  round-trip correctly.
- **Bails on**: plain (legacy) form without any visibility.

### 8.9 target_include_directories

- **Location**: [`print2.ml:560`](../../tool/cmake_roundtrip/print2.ml#L560)
- **IR**: [`Target_include_directories` at `lang_cmake.ml:721`](../../src/langs/cmake/lang_cmake.ml#L721)
- **Printer**: [`lang_cmake_pp.ml:1039`](../../src/langs/cmake/lang_cmake_pp.ml#L1039)
- **Accepts**: `target_include_directories(<t> [SYSTEM] [BEFORE|AFTER]
  {PRIVATE|PUBLIC|INTERFACE <dir>...}+)`.
- **Bails on**: plain form, SYSTEM positioned after visibility.

### 8.10–8.12 target_compile_{definitions,options,features}

- **Locations**: [`print2.ml:443/455/474`](../../tool/cmake_roundtrip/print2.ml#L443)
- **IR / Printer**: see `Target_compile_*` family in
  `lang_cmake.ml:707..` and `lang_cmake_pp.ml:1018..`.
- **Accepts**: `target_compile_X(<t> [BEFORE] {PRIVATE|PUBLIC|INTERFACE <item>...}+)`.
- **Bails on**: plain form (no visibility), quoted features.

### 8.13 option

- **Location**: [`print2.ml:497`](../../tool/cmake_roundtrip/print2.ml#L497)
- **IR**: [`Option` at `lang_cmake.ml:537`](../../src/langs/cmake/lang_cmake.ml#L537)
- **Printer**: [`lang_cmake_pp.ml:658`](../../src/langs/cmake/lang_cmake_pp.ml#L658)
- **Accepts**: `option(<var> <help> [<value>])` with quoted help,
  value ∈ {ON, OFF, TRUE, FALSE, …}.
- **Bails on**: bare help.
- **Known gaps**: `Bool true` prints as `True` (workaround: route
  ON/OFF/TRUE/… as `Var_exp`).

### 8.14 include

- **Location**: [`print2.ml:513`](../../tool/cmake_roundtrip/print2.ml#L513)
- **IR**: [`Include` at `lang_cmake.ml:395`](../../src/langs/cmake/lang_cmake.ml#L395)
- **Printer**: [`lang_cmake_pp.ml:539`](../../src/langs/cmake/lang_cmake_pp.ml#L539)
- **Accepts**: `include(<file> [OPTIONAL] [RESULT_VARIABLE <v>] [NO_POLICY_SCOPE])`.
- **Bails on**: unknown trailing keywords.

### 8.15 add_subdirectory

- **Location**: [`print2.ml:535`](../../tool/cmake_roundtrip/print2.ml#L535)
- **IR**: [`Add_subdirectory` at `lang_cmake.ml:700`](../../src/langs/cmake/lang_cmake.ml#L700)
- **Printer**: [`lang_cmake_pp.ml:991`](../../src/langs/cmake/lang_cmake_pp.ml#L991)
- **Accepts**: `add_subdirectory(<src> [<bin>] [EXCLUDE_FROM_ALL] [SYSTEM])`.
- **Bails on**: quoted src/bin.

### 8.16 unset

- **Location**: [`print2.ml:594`](../../tool/cmake_roundtrip/print2.ml#L594)
- **IR**: [`Unset` at `lang_cmake.ml:432`](../../src/langs/cmake/lang_cmake.ml#L432)
- **Printer**: [`lang_cmake_pp.ml:584`](../../src/langs/cmake/lang_cmake_pp.ml#L584)
- **Accepts**: `unset(<var> [CACHE | PARENT_SCOPE])`.
- **Bails on**: `unset(ENV{<var>})` (separate `Unset_env` ctor).

### 8.17 add_dependencies

- **Location**: [`print2.ml:604`](../../tool/cmake_roundtrip/print2.ml#L604)
- **IR**: [`Add_dependencies` at `lang_cmake.ml:681`](../../src/langs/cmake/lang_cmake.ml#L681)
- **Printer**: [`lang_cmake_pp.ml:1171`](../../src/langs/cmake/lang_cmake_pp.ml#L1171)
- **Accepts**: `add_dependencies(<target> <dep>...)` — one or more
  bare deps. IR widened to `deps : depend list` 2026-05-25; the
  yelu_cmake `ECmakeAddDependencies` and `EAddDependencies`
  fragments + smart constructor `yc_add_dependencies` were
  widened in the same change.
- **Bails on**: zero deps (empty after target); quoted/bracketed
  args.

### 8.18 find_package

- **Location**: [`print2.ml:614`](../../tool/cmake_roundtrip/print2.ml#L614)
- **IR**: [`Find_package` at `lang_cmake.ml:518`](../../src/langs/cmake/lang_cmake.ml#L518)
- **Printer**: [`lang_cmake_pp.ml:761`](../../src/langs/cmake/lang_cmake_pp.ml#L761)
- **Accepts**: `find_package(<name> [<ver>] [EXACT] [QUIET] [REQUIRED]
  [CONFIG|MODULE|NO_MODULE] [COMPONENTS <c>...]
  [OPTIONAL_COMPONENTS <c>...])`.
- **Bails on**: top-level keyword (REQUIRED/EXACT/…) appearing
  after COMPONENTS (printer would reorder); GLOBAL /
  BYPASS_PROVIDER / NO_*_PATH / REGISTRY_VIEW / HINTS / PATHS /
  PATH_SUFFIXES / NAMES (IR doesn't model).

### 8.19 get_filename_component

- **Location**: [`print2.ml:676`](../../tool/cmake_roundtrip/print2.ml#L676)
- **IR**: [`Get_filename_component` at `lang_cmake.ml:414`](../../src/langs/cmake/lang_cmake.ml#L414)
- **Printer**: [`lang_cmake_pp.ml:562`](../../src/langs/cmake/lang_cmake_pp.ml#L562)
- **Accepts**: `get_filename_component(<var> <filename> <mode> [CACHE])`
  with valid mode.
- **Bails on**: `PROGRAM_ARGS <var>` (unmodeled), `BASE_DIR`,
  non-standard trailers.

### 8.20 set_target_properties

- **Location**: [`print2.ml:691`](../../tool/cmake_roundtrip/print2.ml#L691)
- **IR**: [`Set_target_properties` at `lang_cmake.ml:650`](../../src/langs/cmake/lang_cmake.ml#L650)
- **Printer**: [`lang_cmake_pp.ml:1127`](../../src/langs/cmake/lang_cmake_pp.ml#L1127)
- **Accepts**: `set_target_properties(<target>... PROPERTIES <k> <v>...)`
  — one or more bare targets, bare keys, values may be quoted.
  IR widened to `targets : target list` 2026-05-25.
- **Bails on**: missing PROPERTIES, quoted targets/keys, odd k/v
  count after PROPERTIES.

### 8.21 add_custom_target

- **Location**: [`print2.ml:713`](../../tool/cmake_roundtrip/print2.ml#L713)
- **IR**: [`Add_custom_target` at `lang_cmake.ml:775`](../../src/langs/cmake/lang_cmake.ml#L775)
- **Printer**: [`lang_cmake_pp.ml:1101`](../../src/langs/cmake/lang_cmake_pp.ml#L1101)
- **Accepts** (Tier 4 expansion 2026-05-29):
  `add_custom_target(<name> [ALL] [COMMAND <cmd> [<args>...]]...
   [DEPENDS <dep>...] [WORKING_DIRECTORY <dir>] [COMMENT <comment>]
   [VERBATIM] [USES_TERMINAL] [SOURCES <src>...])`. Keywords must be
  in canonical printer order; multiple COMMAND blocks are supported.
  COMMENT must be quoted in source (printer emits quoted).
- **Bails on**: `BYPRODUCTS` (IR has it but printer drops); `JOB_POOL`
  / `JOB_SERVER_AWARE` / `COMMAND_EXPAND_LISTS` (IR has them but
  printer drops); out-of-order keywords.
- **Printer fix**: previously used `pp_list_with_key " COMMAND"`
  which merged multiple COMMAND blocks into a single keyword; now
  uses per-element iteration so each COMMAND keyword is emitted
  separately. `COMMENT` field switched from raw `string` to
  `pp_string_quoted` so multi-word comments don't tokenize as
  separate args in re-extracted tree-sitter sequence.

### 8.22 list (subcommand dispatch)

- **Location**: [`print2.ml:739`](../../tool/cmake_roundtrip/print2.ml#L739)
- **IR**: [`List_cmd` at `lang_cmake.ml:531`](../../src/langs/cmake/lang_cmake.ml#L531)
- **Accepts** (Stage 2-b + Tier 4 list batch 2026-05-29): LENGTH,
  REVERSE, REMOVE_DUPLICATES, APPEND, PREPEND, REMOVE_ITEM, FIND,
  JOIN, GET (multi-index), SUBLIST, INSERT, REMOVE_AT, POP_BACK,
  POP_FRONT.
- **Bails on**: SORT (multi-keyword), FILTER (mode + regex),
  TRANSFORM (action + selector + optional output); quoted/bracketed
  slots.

### 8.23 string (subcommand dispatch)

- **Location**: [`print2.ml:767`](../../tool/cmake_roundtrip/print2.ml#L767)
- **IR**: [`String_cmd` at `lang_cmake.ml:532`](../../src/langs/cmake/lang_cmake.ml#L532)
- **Accepts** (Stage 2-b + Tier 4 string batch 2026-05-29):
  TOUPPER, TOLOWER, LENGTH, STRIP, CONCAT, APPEND, PREPEND,
  REPLACE, FIND, SUBSTRING, COMPARE, MAKE_C_IDENTIFIER, HEX,
  GENEX_STRIP, JOIN, TIMESTAMP, REGEX MATCH / MATCHALL / REPLACE.
  REGEX printer also switched from `%S` (OCaml escape) to literal-
  quoted, matching the D2 fix for `file(STRINGS REGEX ...)`.
- **Bails on**: REGEX QUOTE (separate ctor not parsed), RANDOM,
  UUID, JSON, REPEAT.

### 8.24 return

- **Location**: [`print2.ml:809`](../../tool/cmake_roundtrip/print2.ml#L809)
- **IR**: [`Return` at `lang_cmake.ml:370`](../../src/langs/cmake/lang_cmake.ml#L370)
- **Printer**: [`lang_cmake_pp.ml:473`](../../src/langs/cmake/lang_cmake_pp.ml#L473)
- **Accepts**: `return()`, `return(PROPAGATE <var>...)`.

### 8.25 include_directories

- **Location**: [`print2.ml:822`](../../tool/cmake_roundtrip/print2.ml#L822)
- **IR**: [`Include_directories` at `lang_cmake.ml:791`](../../src/langs/cmake/lang_cmake.ml#L791)
- **Printer**: [`lang_cmake_pp.ml:1176`](../../src/langs/cmake/lang_cmake_pp.ml#L1176)
- **Accepts**: `include_directories([AFTER|BEFORE] [SYSTEM] <dir>...)`
  — one or more bare dirs, with optional `BEFORE`/`AFTER` and
  `SYSTEM` prefixes (matching cmake spec and the printer's emit
  order). Parser updated 2026-05-25.
- **Bails on**: empty arglist; quoted dirs; SYSTEM appearing
  before BEFORE/AFTER (printer canonicalizes the order).

### 8.26 find_program / find_path (shared `parse_find_var_names`)

- **Location**: [`print2.ml:839`](../../tool/cmake_roundtrip/print2.ml#L839)
- **IR**: `Find_program` / `Find_path`, both use `find_var_args`
  at [`lang_cmake.ml:135`](../../src/langs/cmake/lang_cmake.ml#L135).
- **Printer**: `pp_find_var` at `lang_cmake_pp.ml:235`.
- **Accepts**:
  - **Short form**: `find_program(<var> <name> [REQUIRED])` —
    single positional name, no `NAMES` keyword. IR records
    `short_form = true` (added 2026-05-25) so the printer
    re-emits the form without injecting `NAMES`.
  - **NAMES form**: `find_program(<var> NAMES <n>... [REQUIRED])`
    — one or more names after the keyword.
  - Both shapes apply to `find_path` as well.
- **Bails on**: HINTS / PATHS / PATH_SUFFIXES / DOC / NO_*_PATH /
  NO_CACHE / REGISTRY_VIEW; positional name that collides with
  a reserved keyword.

### 8.27 install

- **Location**: [`print2.ml:946`](../../tool/cmake_roundtrip/print2.ml#L946)
- **IR**: [`Install_targets`](../../src/langs/cmake/lang_cmake.ml#L840),
  [`Install_files`](../../src/langs/cmake/lang_cmake.ml#L849).
- **Printer**: [`lang_cmake_pp.ml:1221`](../../src/langs/cmake/lang_cmake_pp.ml#L1221) (TARGETS), [`1227`](../../src/langs/cmake/lang_cmake_pp.ml#L1227) (FILES).
- **Accepts**: `install(TARGETS <t>... [EXPORT <name>] DESTINATION <d>)`,
  `install(FILES <f>... DESTINATION <d>)`.
- **Bails on**: DIRECTORY / SCRIPT / CODE / EXPORT-standalone;
  COMPONENT / RENAME / PERMISSIONS / OPTIONAL on TARGETS; per-
  target-type sub-clauses (ARCHIVE / LIBRARY / RUNTIME / …).

### 8.28 add_custom_command (TARGET form only)

- **Location**: [`print2.ml:878`](../../tool/cmake_roundtrip/print2.ml#L878)
- **IR**: [`Add_custom_command_target` at `lang_cmake.ml:767`](../../src/langs/cmake/lang_cmake.ml#L767)
  (OUTPUT form has [`Add_custom_command`](../../src/langs/cmake/lang_cmake.ml#L748) but no parser yet).
- **Printer**: [`lang_cmake_pp.ml:1090`](../../src/langs/cmake/lang_cmake_pp.ml#L1090) (TARGET); [`1076`](../../src/langs/cmake/lang_cmake_pp.ml#L1076) (OUTPUT).
- **Accepts**: `add_custom_command(TARGET <t> {PRE_BUILD|PRE_LINK|POST_BUILD}
  COMMAND <prog> <args>...)` with bare args, single COMMAND.
- **Bails on**: OUTPUT form, multiple COMMAND blocks,
  COMMENT / VERBATIM / USES_TERMINAL / BYPRODUCTS /
  WORKING_DIRECTORY / DEPFILE.

### 8.29 file (subcommand dispatch)

- **Location**: [`print2.ml:909`](../../tool/cmake_roundtrip/print2.ml#L909)
- **IR**: `File_*` family in `lang_cmake.ml:493..515`.
- **Printer**: `lang_cmake_pp.ml:699..756`.
- **Accepts**: WRITE, APPEND, MAKE_DIRECTORY, REMOVE,
  REMOVE_RECURSE, TOUCH, TOUCH_NOCREATE, GLOB, GLOB_RECURSE —
  the latter two only when no CONFIGURE_DEPENDS / RELATIVE /
  LIST_DIRECTORIES / FOLLOW_SYMLINKS keywords are present.
- **Accepts (added 2026-05-29 / D2)**: READ (with optional
  `OFFSET <n>` / `LIMIT <n>` / `HEX`) and STRINGS (with optional
  `REGEX <r>` / `ENCODING <e>` / `LIMIT_COUNT <n>` in canonical
  printer order). STRINGS bails on out-of-order keywords;
  modeled-side printer for REGEX switched from `%S` (OCaml escape)
  to literal-quoted so embedded backslashes (`[\t ]` etc.) survive
  the round-trip.
- **Accepts (added 2026-05-29 / Tier 4 file batch)**:
  RELATIVE_PATH (`<var> <base> <file>`), RENAME (`<old> <new>
  [RESULT <v>] [NO_REPLACE]`), COPY_FILE (`<in> <out> [RESULT <v>]
  [ONLY_IF_DIFFERENT]`), REAL_PATH (`<path> <var> [BASE_DIRECTORY
  <d>] [EXPAND_TILDE]`), SIZE (`<file> <var>`), READ_SYMLINK
  (`<link> <var>`), TIMESTAMP (`<file> <var> [<format>] [UTC]`).
  TIMESTAMP printer also switched to literal-quoted format string
  (same fix as STRINGS REGEX).
- **Bails on**: STRINGS unmodeled keywords (LENGTH_MAXIMUM,
  LENGTH_MINIMUM, LIMIT_INPUT, LIMIT_OUTPUT, NEWLINE_CONSUME,
  NO_HEX_CONVERSION, ECHO_OUTPUT_VARIABLE); COPY, DOWNLOAD, UPLOAD,
  LOCK, TO_NATIVE_PATH, TO_CMAKE_PATH (no IR ctors).

### 8.32 execute_process (Tier 2 cleanup, 2026-05-29)

- **Location**: [`print2.ml`](../../tool/cmake_roundtrip/print2.ml) `parse_execute_process`
- **IR**: [`Execute_process` at `lang_cmake.ml:522`](../../src/langs/cmake/lang_cmake.ml#L522) — unchanged, the existing record already covered the keywords parser handles.
- **Printer**: [`lang_cmake_pp.ml:705`](../../src/langs/cmake/lang_cmake_pp.ml#L705) — unchanged, emits multi-line with `\n  KW <args>` per keyword.
- **Accepts**: `execute_process(COMMAND <c1> [<args>...] [COMMAND <c2> [<args>...]]... [WORKING_DIRECTORY <d>] [TIMEOUT <s>] [RESULT_VARIABLE <v>] [OUTPUT_VARIABLE <v>] [ERROR_VARIABLE <v>] [INPUT_FILE <f>] [OUTPUT_FILE <f>] [ERROR_FILE <f>] [OUTPUT_QUIET] [ERROR_QUIET] [OUTPUT_STRIP_TRAILING_WHITESPACE] [ERROR_STRIP_TRAILING_WHITESPACE] [COMMAND_ERROR_IS_FATAL <ANY|LAST|NONE>])` — keywords MUST appear in the canonical order above (matching the printer's emit order), or the parser bails. COMMAND blocks may repeat at the start.
- **Bails on**:
  - Keywords out of canonical order in source (e.g. `OUTPUT_QUIET` before `RESULT_VARIABLE`) — printer would silently reorder, breaking STRUCT.
  - `RESULTS_VARIABLE` / `COMMAND_ECHO` / `ENCODING` / `ECHO_OUTPUT_VARIABLE` / `ECHO_ERROR_VARIABLE` — IR doesn't carry these fields.
  - Non-numeric `TIMEOUT`.
  - Unrecognized trailing tokens.
- **Known gaps**: IR is missing five cmake-modern keywords (see Bails on); adding them would close more shapes. The order constraint is a surface-syntax limitation of the printer; cmake itself doesn't care about keyword order, so bailing on out-of-order source is conservative but correct.

### 8.31 get_property (Tier 2 cleanup, 2026-05-29)

- **Location**: [`print2.ml`](../../tool/cmake_roundtrip/print2.ml) `parse_get_property`
- **IR**: [`Get_property` at `lang_cmake.ml:459`](../../src/langs/cmake/lang_cmake.ml#L459)
  with the new `get_property_scope` sum type at `lang_cmake.ml:140`
  and `get_property_mode` enum at `lang_cmake.ml:160`.
- **Printer**: [`lang_cmake_pp.ml:593`](../../src/langs/cmake/lang_cmake_pp.ml#L593)
- **Accepts**:
  - `get_property(<var> GLOBAL PROPERTY <name> [SET|DEFINED|BRIEF_DOCS|FULL_DOCS])`
  - `get_property(<var> DIRECTORY [<dir>] PROPERTY <name> [...])`
  - `get_property(<var> TARGET <t> PROPERTY <name> [...])`
  - `get_property(<var> SOURCE <src> [DIRECTORY <dir> | TARGET_DIRECTORY <t>] PROPERTY <name> [...])`
  - `get_property(<var> INSTALL <f> PROPERTY <name> [...])`
  - `get_property(<var> TEST <test> [DIRECTORY <dir>] PROPERTY <name> [...])`
  - `get_property(<var> CACHE <entry> PROPERTY <name> [...])`
  - `get_property(<var> VARIABLE PROPERTY <name> [...])`
- **Bails on**:
  - Quoted scope args (IR slots are bare).
  - Unrecognized trailing mode (must be SET / DEFINED / BRIEF_DOCS /
    FULL_DOCS or absent).
  - Multiple sub-scope keywords inside SOURCE (DIRECTORY and
    TARGET_DIRECTORY are mutually exclusive per cmake spec; parser
    keeps only the first).
- **Known gaps**: pre-redesign printer (the `_;` pattern at the
  old lang_cmake_pp.ml:600) silently dropped `source_target_directory`,
  `test_directory`, and the `DEFINED`/`BRIEF_DOCS`/`FULL_DOCS` modes
  — bugs the round-trip surfaced. yelu-side `ECmakeGetProperty`
  emit corrected to use `Gps_target` instead of misusing
  `source_target_directory`.

### 8.30 set_property (Tier 2 cleanup, 2026-05-29)

- **Location**: [`print2.ml`](../../tool/cmake_roundtrip/print2.ml) `parse_set_property`
- **IR**: [`Set_property` at `lang_cmake.ml:455`](../../src/langs/cmake/lang_cmake.ml#L455)
  with the new `set_property_scope` sum type at `lang_cmake.ml:108`.
- **Printer**: [`lang_cmake_pp.ml:622`](../../src/langs/cmake/lang_cmake_pp.ml#L622)
- **Accepts**:
  - `set_property(GLOBAL [APPEND] [APPEND_STRING] PROPERTY <name> [<value>...])`
  - `set_property(DIRECTORY [<dir>] [APPEND] [APPEND_STRING] PROPERTY <name> [<value>...])`
  - `set_property(TARGET <t>... [APPEND] [APPEND_STRING] PROPERTY <name> [<value>...])`
  - `set_property(SOURCE <src>... [DIRECTORY <dir>...] [TARGET_DIRECTORY <t>...] [APPEND] [APPEND_STRING] PROPERTY <name> [<value>...])`
  - `set_property(INSTALL <f>... [APPEND] [APPEND_STRING] PROPERTY <name> [<value>...])`
  - `set_property(TEST <test>... [DIRECTORY <dir>...] [APPEND] [APPEND_STRING] PROPERTY <name> [<value>...])`
- **Bails on**:
  - `CACHE <entry>...` scope — IR's `cache_entry` is currently the
    placeholder type `Cache_entry` with no per-entry names; preserving
    via Apply is safer until the type carries data.
  - Quoted scope args (IR slots are bare `string`).
- **Known gaps**: `cache_entry` needs widening before CACHE scope
  can be modeled. The yelu-side production API (`yc_set_property`,
  `yc_set_global_property`) was also updated to fan out into an
  `Exp_list` of single-property `Set_property` calls so it matches
  the cmake spec's "one PROPERTY clause per call" semantics.

## 9. Code-quality posture

### Strengths

- **Single-file driver, no cross-module state.** `print2.ml` is
  a flat pipeline: JSON reader → AST → dispatch → per-command
  parser → emit. No mutation, no global registries.
- **Bail-to-Apply discipline.** Every parser returns `None` on
  shapes that would force the printer to drop or reorder
  information. The Apply fallback then preserves the call
  STRUCT-faithfully.
- **Real production-IR usage.** No IR fork; bug fixes flow back
  to production.
- **Each shipped stage verified end-to-end** before commit; commit
  messages cite per-corpus STRUCT/FORMAT/modeled deltas.

### Weaknesses

- **`print2.ml` is one large file** (~1,150 lines, 30 parsers).
  Acceptable for a prototype; would benefit from a split if this
  becomes long-lived tool.
- **No per-parser unit tests.** Verification is end-to-end against
  real corpora. Pro: corpora are larger and more diverse than any
  hand-written test. Con: a future IR refactor could silently
  shift `Apply` vs typed routing in ways STRUCT can't catch.
- **`parse.py` is the only Python in the project.** A Python
  dependency for the OCaml round-trip is awkward;
  `ocaml-tree-sitter` is the alternative if it becomes load-bearing.
- **Corpus locations + gersemi binary path are hard-coded** in
  the docs and harness. Reproducing on another machine requires
  substitutions.

### What a reviewer should spot-check

1. Pick a per-parser row in § 8; compare to the cited IR ctor and
   printer arm. Accepted forms must match what the printer emits.
2. Read `parse_cmd` dispatch's lowercase guard — mixed-case
   command names route to `None`, preserving source casing.
3. Read `normalize()` in `test_corpus.sh` — the FORMAT oracle's
   claim is exactly what this function permits.
4. Run the harness on a fresh project. STRUCT failures point to
   real IR or printer bugs.

The major lesson from the 2026-05-20 audit: **STRUCT pass does
not imply typed correctness.** `add_executable(App WIN32 main.c)`
can round-trip STRUCT-perfectly with `WIN32` inside `sources`
instead of `options`; the bug is invisible to the round-trip
oracle but real for any downstream consumer of the typed IR.
Future audits must score both axes.

## 10. Open / deferred

- **Lossy IR-printer cleanup** — see [`status.md`](status.md)
  "Open work". Largest single typed-coverage opportunity; would
  close most of § 6's "routed to Apply because the printer is
  lossy" list.
- **Class A semantic resolution** (§ 6) — deferred, awaits
  behavior-level oracle.
- **Comments inside argument lists** — currently dropped;
  whether IR should carry them is open.
- **Behavior-level oracle** — File API JSON diff against real
  cmake configure. Substantial engineering, would catch what
  STRUCT/FORMAT cannot.
- **Corpus extension** to fmt / catch2 / spdlog / pytorch — no
  technical blocker; cheap stress test of the current claim.
