# Cache variable namespacing

> **Purpose.** When diffing yc-eval's predicted cache against
> real cmake's `CMakeCache.txt`, we need to know which variables
> are *project*-declared (the comparison surface) vs *cmake-emitted*
> housekeeping (filtered out). This doc fixes the categorization
> and the rules.

## 1. Why this matters

A real cmake configure populates the cache with hundreds of
entries. fmt's `CMakeCache.txt` after a typical configure has
**~195 entries**, only **21** of which belong to fmt itself.
The other 174 are cmake's compiler detection, install paths,
CPack defaults, etc. yc-eval predicts what fmt's program does;
it does not (and should not) model cmake's compiler-probe
machinery.

Without filtering, the diff signal is dominated by noise:
"yc-eval missing CMAKE_ADDR2LINE, missing CMAKE_AR, missing
CMAKE_BUILD_TYPE …" — all true but uninteresting. The
classifier scopes the comparison to entries the project
*intended* to expose.

## 2. The four tiers

In order from "definitely reserved" to "almost certainly
project":

| tier | examples | source | oracle policy |
|---|---|---|---|
| **(1) cmake-emitted** | `CMAKE_INSTALL_PREFIX`, `CMAKE_CXX_COMPILER`, `CMAKE_BUILD_TYPE`, `CMAKE_CACHEFILE_DIR` | `cmake --help-variable-list` (800 entries on cmake 4.3) + `CMAKE_*`, `CTEST_*`, `CPACK_*` prefix patterns | **filter out** |
| **(2) build-conventions** | `BUILD_SHARED_LIBS`, `BUILD_TESTING` | hardcoded short list (these are standard but DO behave as user-settable options) | **filter out** by default; could be lifted to (3) per-project |
| **(3) project** | `FMT_FUZZ`, `FMT_TEST`, `LLVM_ENABLE_RTTI` | static enumerator output (`cache_vars.exe`) for the project being tested | **compare** — this is the signal |
| **(4) unknown** | anything else | residual — neither in (1)/(2) nor in (3)'s declared list | **compare and flag** — either a static-walker miss or a dynamic decl |

The first two are the same idea at different granularities;
combining them into a single "reserved" class is fine for
diffing.

The fourth tier deserves attention: an "unknown" entry in
real cmake's cache (but not predicted by yc-eval) means
either (a) the project declared a cache var the static
walker didn't find — likely inside a runtime-`include()`d
helper or a `cmake_dependent_option()` — or (b) cmake/an
add-on module wrote a non-`CMAKE_*` variable. Both are
useful signals.

## 3. Compiler / toolchain-specific (relaxed tier)

Names like `HAVE_FNO_EXCEPTIONS_FLAG`, `HAVE_STDBOOL_H`,
`CMAKE_HAVE_LIBC_PTHREAD`, `GCC_HAVE_FPIC` come from cmake's
`Check<X>` modules — they're emitted at configure-time by
running tiny compile probes. They're not declared by the
project but are also not in `cmake --help-variable-list`
(which only documents *named* variables, not probe results).

**Policy**: prefix-match `HAVE_` / `CMAKE_HAVE_` / `_FOUND$` /
`_INTERNAL$` / `_PRIVATE$` → classify as reserved (tier 1)
even if absent from the variable-list output. Same goes for
compiler-prefixed names if any project ever uses them
(`GCC_*`, `MSVC_*`); the doc reserves the right to relax
this if a real project intentionally uses such names as
options.

This is the "we can relax for completeness" tier you
flagged. We won't try to enumerate every compiler / probe
naming convention; the prefix pattern catches the
overwhelming majority.

## 4. Sources of truth

| where to get reserved names | what it gives | freshness |
|---|---|---|
| `cmake --help-variable-list` | 800 documented vars (cmake 4.3.1 on this host); grows with cmake version | run-time, version-keyed |
| [`tool/cmake_roundtrip/cmake_reserved.tsv`](../../tool/cmake_roundtrip/cmake_reserved.tsv) | the captured snapshot (cmake 4.3.1, 2026-06-02). Header comments skipped at load; 9 placeholder forms (`<PROJECT-NAME>`, `<LANG>`, `<CONFIG>`, …) — currently only `<PROJECT-NAME>` gets expanded, the rest fall through to the prefix-pattern rules | committed, stable for tests |
| [cmake-variables(7)](https://cmake.org/cmake/help/latest/manual/cmake-variables.7.html) | curated docs grouped by phase / language | docs-team-curated |
| `cmake -B build -LAH` (after configure) | everything `CMakeCache.txt` actually contains for *this configure* | post-hoc, per-project |
| `Modules/Compiler/*.cmake` in cmake source | authoritative writers of compiler-detection vars | source-of-truth, heavy |

For our purposes, `cmake --help-variable-list` is the
canonical machine-readable source. Cache it per cmake version
(the variable namespace grows release-over-release).

| where to get project names | what it gives |
|---|---|
| `cache_vars.exe <project-dir>` | static enumerator output, every `option()` + `set(… CACHE …)` decl |
| `cmake -B build -LAH` filtered to non-`CMAKE_*` entries | dynamic — catches `cmake_dependent_option()` and dynamically-included decls the static walker missed |

The two sources together (static enumerator ∪ dynamic
post-configure dump minus reserved tier) is the most
complete project namelist.

## 5. Classifier algorithm

Given:
- `reserved` — set of cmake-emitted names (from
  `cmake --help-variable-list`)
- `project` — set of names from the static enumerator for
  this project
- a variable name `n` to classify

```
classify(n):
  if n in project:
    return Project
  if n in reserved:
    return Reserved_cmake
  if n in BUILD_CONVENTIONS_SHORTLIST:
    return Reserved_build_convention
  if matches any of:
       prefix "CMAKE_"
       prefix "CTEST_"
       prefix "CPACK_"
       prefix "HAVE_"
       prefix "CMAKE_HAVE_"
       prefix "FETCHCONTENT_"
       suffix "_FOUND"
       suffix "_PRIVATE"
       suffix "_INTERNAL":
    return Reserved_cmake
  return Unknown
```

`BUILD_CONVENTIONS_SHORTLIST` is the hand-curated list of
build-time-convention names that *are* user-settable
options but are not strictly project-declared
(`BUILD_SHARED_LIBS`, `BUILD_TESTING`). Two entries today;
extend as we hit cases.

The order matters: project before reserved means a project
*can* declare a name that's also in cmake's reserved list
(e.g., a project that redefines `BUILD_TESTING` with a
custom option call). Project's declared intent wins.

## 6. Oracle diff policy

For the predicted-vs-real diff:

```
for each name n in (predicted ∪ real):
  tier = classify(n)
  match tier with
  | Project | Unknown -> include in diff
  | Reserved_cmake    -> filter (cmake-emitted; not our concern)
  | Reserved_build_convention -> filter (standard convention)
```

Two interesting buckets in the diff result:
- **Predicted but absent from real**: we predicted a var
  real cmake didn't write. Either our eval has a bug
  (wrote the cache when it shouldn't) or the cmake side
  has a gating `if(...)` we mis-evaluated.
- **Real but absent from predicted**: real cmake wrote
  something we didn't predict. Either our bridge doesn't
  yet model the command that writes it, or the var came
  from a dynamically-included module the static walker
  missed (tier 4 "unknown" candidate).

## 7. Caveats

- **`<PROJECT-NAME>_*` placeholders.** `cmake --help-variable-list`
  contains literal `<PROJECT-NAME>_BINARY_DIR`,
  `<PROJECT-NAME>_VERSION`, etc. — these are TEMPLATES, not
  actual names. At classify time, substitute the project's
  name and add to the reserved set. fmt's cache contains
  `FMT_BINARY_DIR`, `FMT_VERSION`, `FMT_IS_TOP_LEVEL` —
  these are reserved-via-template, not project-declared.
- **`<PackageName>_ROOT` placeholders.** Same issue; takes
  the find_package'd name as the substitution. Less
  immediately critical (rare in our test corpora).
- **Other placeholders** (`<LANG>`, `<CONFIG>`, `<TYPE>`,
  `<FEATURE>`, `<NNNN>`) appear in the snapshot but aren't
  expanded by `expand_placeholders`. They mostly start
  with `CMAKE_` (e.g. `CMAKE_<LANG>_COMPILER`), so the
  prefix-pattern rule catches expanded names like
  `CMAKE_CXX_COMPILER` at classify time. The expanded set
  would be combinatorial — `<LANG>` × `<CONFIG>` ×
  template → thousands of names. Prefix-fallback is the
  pragmatic choice.
- **Project shadowing of reserved names** (e.g., a project
  redefining `BUILD_TESTING`): classifier returns `Project`,
  matching the project's intent.
- **CMake version drift**: `cmake --help-variable-list`
  output grows over releases. Cache the snapshot per cmake
  version and date it. The bridge oracle should fail loud
  if classify's "reserved" snapshot is older than the
  installed cmake.
