# fmt — predictor probe status

> **Project**: `{fmt}` C++ formatting library
> **Source**: github.com/fmtlib/fmt (vendored at `vendor/fmt`)
> **Why this probe**: small CMakeLists with rich configure-time
> work (find_program, find_package, try_compile, add_subdirectory,
> function definitions). Good first probe — broad coverage in <600
> lines of cmake.

## Headline numbers (2026-06-08)

| oracle | result | notes |
|---|---|---|
| parse-print | **11/11 OK** | all fmt cmake files round-trip byte-equivalently |
| cache matrix | **24/24 cells perfect** | cache diff shows path-only differences; zero semantic mismatches |
| .yc compilation | **11/11 OK** | all `.yc` concrete-syntax files compile and produce valid cmake |
| yc_apply in main.ml | **35** (down from ~100) | remaining are ergonomic or genuinely unmodeled |

The fmt probe is **complete within the current architecture** —
every cache entry real cmake writes is predicted with the right
value across all 24 (option × ON/OFF) configurations. All 11 files
have both `.ml` (OCaml DSL, reference) and `.yc` (concrete syntax,
matrix-tested) versions.

## Oracles in detail

### Parse-print

```sh
bash tool/cmake_roundtrip/test_corpus.sh vendor/fmt
```

Last result: `OK=11 FORMAT=0 STRUCT=0 PARSE=0`. See
[worklog_2026_06.md](../../doc/worklog/worklog_2026_06.md).

### Cache matrix

```sh
dune exec test/test-runcmake/test_fmt_matrix_smoke.exe
```

Last result: median matched 20, all four diff classes (matched /
mismatched / real_only / pred_only) at their target values. See
[cache_matrix.md](../cache_matrix.md)
for the pipeline.

#### Output layout

```
_out/fmt/matrix/<option>_<value>/    e.g. FMT_FUZZ_ON/
├── real/         cmake on vendor/fmt (reference — today)
├── ycn-cmake/    RESERVED — cmake on yelu-emitted cmake source
│                  (parse vendor/fmt → ycn IR → emit cmake → run cmake on THAT)
└── ycn-native/   RESERVED — ycn's own backend output (ninja/make/etc.)
                  bypassing cmake entirely
```

Three backend slots anticipated:

- **`real/`** is the reference: real cmake configures the original
  `vendor/fmt/CMakeLists.txt`. Today's matrix diffs this against
  the yc-eval predicted cache (no build dir for that side).
- **`ycn-cmake/`** (future): parse cmake → ycn IR (via the existing
  `to_normal` / `from_normal` convert path) → emit cmake → real
  cmake configures THAT. A second diff (`real/CMakeCache.txt` vs
  `ycn-cmake/CMakeCache.txt`) proves the ycn round-trip is
  semantically faithful.
- **`ycn-native/`** (speculative): ycn emits ninja/make/etc.
  directly, no cmake involved. Bar #3 / Y16 territory.

## Adaptation footprint

What the predictor needed to handle fmt completely (each maps to
specific commits — see git log):

- `include()` recursive eval + cmake stdlib `Modules/` search
  (`b893ba4`)
- `${X}` substitution unified via `substitute env s`
  (`35c4e44`)
- Dynamic `CACHE TYPE` and docstring round-trip (`df0dfe3`, `4bdf646`,
  `5ec0030`)
- Cond compounds (`VERSION_*`, `IN_LIST`, `MATCHES`, `LE/GE`,
  `EXISTS`, `COMMAND`, `IS_ABSOLUTE`) + recursive descent
  (`57ed3ca`, `e457e16`, `1b6229a`)
- `option()` canonicalization via `expect_bool` (`3c0cb54`)
- `add_subdirectory` recursion via `subdir_loader`
  (`b5fa2be`)
- `find_program` / `find_package(Threads)` / `try_compile` stubs
  + `return()` bridge (`c42aae8`)
- Function/macro dispatch + ARGN (`631402e`)

## Hybrid pilot — step 1.a (text-level codegen)

[`set_verbose.ml`](set_verbose.ml) reproduces fmt's
`join` + `set_verbose` helpers (CMakeLists.txt lines 21–39) in
yelu IR. Build & emit:

```sh
dune exec probes/fmt/set_verbose.exe
```

Compare against the original (gersemi-normalized, comments
stripped):

```sh
gersemi --line-length 99999 /tmp/fmt_orig.cmake   # from sed -n '21,39p' vendor/fmt/CMakeLists.txt
gersemi --line-length 99999 /tmp/fmt_yelu.cmake   # from set_verbose.exe stdout
```

**Result**: gersemi-equivalent modulo two known cosmetic gaps:

1. Comments dropped — yelu IR doesn't carry comments.
2. One extra blank line inside `set_verbose`'s body after the
   `join(...)` call. Caused by `Apply` printer ending with `@.`
   while `list_br` force-newlines between commands — a
   pre-existing printer inconsistency, not specific to this pilot.
   Filed for future cleanup.

The semantic content (every command, every arg, every
quote/bare distinction) round-trips correctly. The
quote/bare distinction was the load-bearing one — fmt's source
mixes `${ARGN}` bare (foreach items, function call args) with
`"${result}"` quoted (set values inside join). Pilot matches
per-line; uses `EVar` for bare-ref positions and `EString` for
quoted-ref positions.

### Pilot scope (step 1.a)

Codegen only — no real cmake configure, no build oracle.
Achievement: yelu IR → cmake text faithfully reproduces fmt's
hand-written helpers within whitespace normalization.

### Step 1.b — build oracle (✓ completed)

`yelu hybrid` reads [`manifest.json`](manifest.json), compiles each
helper (`.ml` via subprocess; `.yc` via in-process parse), splices
the generated cmake into fmt's CMakeLists at the manifest's
anchors, then runs real cmake on both vendor and the hybrid
source and diffs CMakeCache.txt.

```sh
dune exec src/bin/yelu/yelu.exe -- hybrid probes/fmt
dune exec src/bin/yelu/yelu.exe -- hybrid probes/fmt -D FMT_FUZZ=ON
```

Layout written to `_out/fmt/hybrid/`:

```
_out/fmt/hybrid/
├── source/                vendor/fmt mirrored via symlinks
│   └── CMakeLists.txt     ← spliced version (helpers replaced)
├── build-vendor/          real cmake on vendor/fmt
└── build-hybrid/          real cmake on source/
```

Result: **24/24 cells match.** Every option × {ON,OFF} flip
produces identical CMakeCache.txt entries (project + unknown
tier) between vendor and hybrid. The yelu-emitted helpers are a
drop-in replacement for fmt's hand-written ones.

| step | what it proves | result |
|---|---|---|
| 1.a (text) | yelu codegen produces gersemi-equivalent cmake | ✓ (modulo 2 cosmetic gaps documented) |
| 1.b (build) | hybrid source produces identical CMakeCache | ✓ 24/24 cells |

### Hybrid pilot status — proven on one helper pair

The strategy from [`hybrid_strategy.md`](../../doc/yelu_cmake/hybrid_strategy.md)
is now demonstrated end-to-end on fmt's `join` + `set_verbose`.
Generalizing: each next helper migrated follows the same pattern
(write `probes/fmt/<helper>.{ml,ye}`, add to manifest.json, run
all cells). No new oracle infrastructure needed.

### Mixed-format demo (`.ml` + `.yc`)

[`use_cmake_modules_false.yc`](use_cmake_modules_false.yc) is a
one-liner concrete-syntax demo:

```
( FMT_USE_CMAKE_MODULES := "FALSE" )
```

The manifest has both helpers: `set_verbose.ml` (the original
pilot) AND `use_cmake_modules_false.yc` (the demo). One run of
`yelu hybrid probes/fmt` compiles both via their respective
paths (subprocess for `.ml`, in-process parse for `.yc`),
splices both into the hybrid CMakeLists, and still produces
24/24 cache matches.

The demo proves the driver is **input-format-agnostic** — same
manifest, two source formats, same oracle. Future helpers can
choose `.ml` (OCaml-as-host, full IR ergonomics) or `.yc`
(concrete syntax, when the parser covers the construct) per
helper.

Full-project migration status in
[`migration_status.md`](migration_status.md) — all 7 phases
closed; covers what the matrix oracle does and doesn't prove,
the `raw_cmake` escape, and the unverified Windows / CUDA branches.

## Project spec — user-knob surface

The 12 OPTION declarations in `vendor/fmt/CMakeLists.txt`. Each
is what a downstream user can flip via `-DFMT_X=…`. Default
column matches `cache_vars.exe vendor/fmt`.

| name | default | gating impact |
|---|---|---|
| `FMT_DOC` | `${FMT_MASTER_PROJECT}` | `add_doc_target()` helper (find_program doxygen/mkdocs, custom commands) |
| `FMT_INSTALL` | `${FMT_MASTER_PROJECT}` | all `install()`, `export()`, `configure_package_config_file`, CPack source-package, pkgconfig — the entire packaging block |
| `FMT_TEST` | `${FMT_MASTER_PROJECT}` | `add_subdirectory(test)` — entire test tree |
| `FMT_FUZZ` | `OFF` | `add_subdirectory(test/fuzzing)` + `FMT_FUZZ` compile def; **also writes `FMT_FUZZ_LINKMAIN` and `FMT_FUZZ_LDFLAGS` to cache** (only option that gates sibling cache entries) |
| `FMT_CUDA_TEST` | `OFF` | `enable_language(CUDA)` probe. Silent NOTFOUND on missing toolchain. |
| `FMT_OS` | `ON` | `target_sources(fmt PRIVATE src/os.cc)` vs `target_compile_definitions(... FMT_OS=0)`. **Zero cache delta despite materially changing the library.** Cache-only oracles are blind to this. |
| `FMT_MODULE` | `${FMT_USE_CMAKE_MODULES}` | `add_module_library()` with `FILE_SET TYPE CXX_MODULES`. Major C++20 module branch. |
| `FMT_SYSTEM_HEADERS` | `OFF` | `SYSTEM` flag on include dirs |
| `FMT_UNICODE` | `ON` | compile def + MSVC `/utf-8` |
| `FMT_PEDANTIC` | `OFF` | large GNU/Clang/MSVC `PEDANTIC_COMPILE_FLAGS` blocks; ON triggers `HAVE_FNO_EXCEPTIONS_FLAG` cache write (compiler-probe side effect, non-FMT_* namespace) |
| `FMT_WERROR` | `OFF` | `-Werror` / `/WX` |
| `FMT_FUZZ_LINKMAIN` | `On` | INSIDE fuzz subdir; only active when FMT_FUZZ=ON |

Four defaults reference other variables (`${FMT_MASTER_PROJECT}`,
`${FMT_USE_CMAKE_MODULES}`) — these compute earlier in the
script. The predictor's `${X}` substitution resolves them at
eval time; matrix testing flips them independently of their
dependencies.

### Observations beyond the user-knob list

- **Only `FMT_FUZZ` gates sibling FMT_* cache entries.**
  `FMT_FUZZ_LINKMAIN` and `FMT_FUZZ_LDFLAGS` exist only when
  `FMT_FUZZ=ON` triggers `add_subdirectory(test/fuzzing)`.
- **`FMT_OS=OFF` produces zero cache delta.** All effects on
  target properties, not cache. A cache-only oracle (what we
  have today) cannot detect this regression surface.
- **`FMT_CUDA_TEST=ON` is silent on missing toolchain.** cmake
  logs NOTFOUND and proceeds — no error. A naive correctness
  oracle expecting either success-with-target or failure would
  mis-flag the success-without-target case.
- **`FMT_PEDANTIC=ON` writes `HAVE_FNO_EXCEPTIONS_FLAG`** to
  cache (compiler-probe side effect; non-FMT_* namespace). Easy
  to overlook in a FMT_*-only filter.

## Open issues specific to fmt

None. Today's stubs (find_program → NOTFOUND, find_package(Threads) →
canned `FIND_PACKAGE_MESSAGE_DETAILS_Threads`, try_compile → FALSE)
match fmt's reference cmake behavior on this host. They'd flip to
mismatches on a system where the underlying tools/libs differ —
which is the next adaptation problem (per-host vs per-project
stubs), not a fmt-specific one.

## Shape C lockup (Phase 7, 2026-06-04) + .yc conversion (Phase 8, 2026-06-08)

All vendor/fmt cmake sources are migrated to `whole_file` emits —
11 source files, ~870 cmake lines total. Every file has a `.yc`
concrete-syntax version that compiles and passes the matrix oracle.
The `.ml` OCaml DSL versions are retained as reference.

| Target file | `.ml` | `.yc` |
|---|---|---|
| `CMakeLists.txt` | [`main.ml`](main.ml) | [`main.yc`](main.yc) |
| `test/compile-error-test/CMakeLists.txt` | [`compile_error_test.ml`](compile_error_test.ml) | [`compile_error_test.yc`](compile_error_test.yc) |
| `test/CMakeLists.txt` | [`test_main.ml`](test_main.ml) | [`test_main.yc`](test_main.yc) |
| `test/cuda-test/CMakeLists.txt` | [`cuda_test.ml`](cuda_test.ml) | [`cuda_test.yc`](cuda_test.yc) |
| `test/fuzzing/CMakeLists.txt` | [`fuzzing.ml`](fuzzing.ml) | [`fuzzing.yc`](fuzzing.yc) |
| `test/static-export-test/CMakeLists.txt` | [`static_export_test.ml`](static_export_test.ml) | [`static_export_test.yc`](static_export_test.yc) |
| `support/cmake/JoinPaths.cmake` | — | [`join_paths.yc`](join_paths.yc) |
| `test/gtest/CMakeLists.txt` | [`gtest.ml`](gtest.ml) | [`gtest.yc`](gtest.yc) |
| `test/find-package-test/CMakeLists.txt` | [`find_package_test.ml`](find_package_test.ml) | [`find_package_test.yc`](find_package_test.yc) |
| `test/add-subdirectory-test/CMakeLists.txt` | [`add_subdirectory_test.ml`](add_subdirectory_test.ml) | [`add_subdirectory_test.yc`](add_subdirectory_test.yc) |
| `support/cmake/FindSetEnv.cmake` | [`find_setenv.ml`](find_setenv.ml) | [`find_setenv.yc`](find_setenv.yc) |

24/24 matrix cells still match. The manifest now runs 100% from `.yc` files.
End-to-end: `vendor/fmt → hybrid tree of .yc-generated cmake → identical
CMakeCache.txt`.

### Two escape hatches

1. **`yc_apply (ystr "<command>") [args...]`** — lenient untyped
   command call. Bypasses the typed IR but still goes through the
   yelu_cmake AST and emit. Used for commands that aren't worth a
   typed constructor (user-defined functions, find/check helpers,
   `cmake_parse_arguments`, etc.). 100+ uses across the 11 files;
   see footprint table below.

2. **`Yelu_emit_main.raw_cmake "<text>"`** — verbatim cmake source
   inserted into the output stream. Bypasses the AST entirely. Used
   for blocks where the cmake-pp quoting layer can't round-trip
   cleanly (e.g. backslash-laden Windows paths with embedded
   quotes). Current count: **1 site** — the
   `FMT_MASTER_PROJECT AND Visual Studio` WINSDK / netfxpath /
   run-msbuild.bat block in `main.ml` (dead code on Linux).

### `yc_apply` footprint (Phase 7 audit)

| Command | Count | Modeled? |
|---|---:|---|
| `message` | 13 | partial — typed for `STATUS`, untyped for `FATAL_ERROR`/`SEND_ERROR`/`WARNING` mix-ins |
| `target_compile_options` | 12 | yes (`ECmakeTargetCompileOptions`) — untyped used when args mix EVar/ystr inconsistently |
| `target_link_libraries` | 9 | yes (`ECmakeTargetLinkLibraries`) — same |
| `include` | 8 | no IR constructor; always via apply |
| `add_test` | 8 | no — meta command |
| `set_verbose` / `join` | 10 | user-defined fmt functions |
| `list` | 7 | yes (multi-form) — apply for ergonomics |
| `set_target_properties` | 6 | no IR — meta property setter |
| `file` | 6 | partial — `READ`/`STRINGS`/`EXISTS` typed; `WRITE`/`MAKE_DIRECTORY`/`TO_NATIVE_PATH` untyped |
| `add_subdirectory` | 6 | no IR constructor |
| `target_compile_definitions` | 5 | yes — apply for ergonomics |
| `project` | 5 | no IR constructor; always via apply |
| `install` | 5 | partial — `ECmakeInstallTargets/Files/Export` exist but lack COMPONENT / FILE_SET / multi-DESTINATION |
| `execute_process` | 5 | no IR constructor |
| `cmake_minimum_required` | 5 | no IR constructor |
| `set_property` | 4 | partial — `ECmakeSetProperty` exists but not `CACHE` / `SOURCE` / `APPEND` forms |
| `find_program` / `find_package` | 6 | partial — find-stubs in eval but no typed args |
| `cmake_parse_arguments` | 3 | no — would require ~1 day of modeling |
| `enable_language` / `cmake_policy` / `check_*` | 5 | no IR constructors |
| user-defined fns (`add_fmt_test`, `expect_compile`, …) | 7 | n/a — these go through apply by design |

**Read**: the bulk of `yc_apply` is for typed commands where we
chose ergonomics over the structured ctor — not for unmodeled
surface. Genuinely unmodeled (no IR at all): `include`,
`add_subdirectory`, `project`, `cmake_minimum_required`,
`execute_process`, `enable_language`, `cmake_policy`,
`cmake_parse_arguments`, plus the long tail of `check_*` /
`set_target_properties` / `set_property CACHE`. The `raw_cmake`
escape is reserved for content that isn't even one command —
multi-line bat-file bodies, Windows-path-with-quotes blocks,
etc.

### What this proves

Y16 framing (from the manifesto): "Rewrite z3/llvm/torch build in
yelu, prove structural equivalence." fmt is the first specimen —
~870 lines of real-world cmake, fully migrated through a hybrid
path that preserves byte-equivalent cache output across the full
12-option × 2-value matrix. The next step is the same exercise
on z3 or llvm; their probe scaffolding lives under
`probes/{z3,llvm}/` and the matrix harness is reusable.
