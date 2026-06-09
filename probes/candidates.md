# Real-world cmake candidates — early ycn benchmark suite

> **Purpose.** Identify a small set of widely-used open-source C/C++
> projects to use as the next-tier ycn round-trip and behavior
> targets, beyond the z3 + llvm corpus we already cover.
> z3 / llvm / torch are the long-horizon targets; for *early*
> iteration, smaller projects produce signal faster.

## 1. What ycn currently covers

Anchoring the criteria in actual capability:

| capability                                            | status                                                                                                                                                                          |
| ----------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Syntactic round-trip** (cmake text → IR → cmake text) | ✅ STRUCT=0 / FORMAT=0 across **z3 (108 files), llvm (596), tutorial (25)** as of Bar #3-lite. PyTorch *not* yet probed (a prior chat mistakenly listed it as done — it isn't).  |
| **yelu_cmake ↔ Lang_cmake** (production emit)          | ✅ via `yelu_cmake_emit`                                                                                                                                                         |
| **yelu_cmake ↔ yelu_cmake_normal** (convert)            | ✅ via `to_normal` / `from_normal` (1,750 LOC, exercised by 65 lift_lower + 25 dual_eval tests)                                                                                  |
| **`-D` cmd-line + cache namespace**                     | ✅ landed 2026-06-01 (see `doc/worklog/worklog_2026_06.md` § "Cache namespace"). 14 spec cases × 2 evaluators verified against `cache_semantics.md`.                            |
| **Direct ycn-text emit / ycn parser**                  | ❌ ycn is currently an internal IR only; cmake-text emit always routes through yelu_cmake.                                                                                       |
| **Behavior-level oracle** (configure-output diff)       | ⏭ scoped to cache for step 10; broader oracle is the next major milestone                                                                                                       |

This is the truth-set the benchmark suite should challenge.

## 2. Selection criteria

In order of decreasing weight for our use case:

1. **Tractable cmake size.** ≤ 30 cmake files for the first
   round; ≤ 100 for the next tier. Configure time ≤ 30s to
   keep iteration fast (we're already running corpora through
   `parse.py` and `print2.exe` for each tweak).
2. **Real cmake patterns we want to exercise.** From the
   prompt's list: `add_library / add_executable`,
   `target_include_directories`, `target_link_libraries`,
   `option()`, BUILD_TESTING-gated tests, install rules,
   `*Config.cmake` export, interface/header-only libraries,
   `if(WIN32) / if(APPLE)` branches.
3. **Modern cmake style** (≥ cmake 3.5, `target_*` rather than
   `include_directories()` directory-scope). The older style
   still parses, but modern projects exercise the IR
   constructors we've invested in.
4. **Popularity & visibility.** Stars are a weak proxy but
   a demo-share artifact about "we round-trip *fmt*" is
   stronger than "we round-trip *libfoo*". Threshold: ≥ 5k
   GitHub stars unless the project is foundational (e.g.
   cJSON is ubiquitous despite modest star count).
5. **No exotic build prerequisites.** No GPU, no JIT
   toolchain, no fetched dependencies (FetchContent is OK
   but should be skippable). Network-free configure is
   strongly preferred.

## 3. Per-project profile

Numbers below are approximate; exact counts come from
running `find … -name CMakeLists.txt -o -name '*.cmake' | wc -l`
on a freshly cloned tree. Configure-time numbers are typical
on a developer laptop.

### 3.1 Anchor tier — recommended for first round

| project        | stars | cmake files | configure | features hit                                                                | notes                                                                                                                                                                                                          |
| -------------- | ----: | ----------: | --------- | --------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **fmt**        |  ~22k |        ~15 | <5s       | add_library, options (`FMT_TEST` `FMT_INSTALL` `FMT_HEADER_ONLY`), tests, install, Config export, headers | Modern cmake exemplar. Compiled-mode AND header-only-mode in one tree. `std::format` was modeled on it — visible to every C++ user. **Strongest anchor.** |
| **nlohmann/json** | ~44k |       ~5–10 | <5s       | INTERFACE library, options, install + export, BUILD_TESTING                  | Header-only canon. Tiny, modern. Best at exercising the INTERFACE-library / Config-export shapes.                                                                                                              |
| **doctest**    |  ~6k  |       ~5–10 | <5s       | INTERFACE library, BUILD_TESTING, install, examples                          | Header-only testing framework. Smallest realistic cmake of any project in this list — useful as a sanity baseline.                                                                                            |
| **spdlog**     |  ~25k |        ~15 | <5s       | add_library, options, deps on **fmt** (FetchContent or `find_package`), install, export | Adds a dependency relationship (fmt) to the suite. Tests how we handle `find_package(fmt)` + downstream `target_link_libraries`. Pairs naturally with fmt above. |
| **cJSON**      |  ~11k |         ~5 | <5s       | add_library, options, tests, install, C-language                              | C (not C++) — confirms language-agnostic round-trip. Small enough to inspect every emitted line by hand.                                                        |

### 3.2 Medium tier — second round

| project        | stars | cmake files | configure | features hit                                                              | notes                                                                                                                                                                |
| -------------- | ----: | ----------: | --------- | ------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **CLI11**      |  ~4k  |        ~10 | <5s       | INTERFACE library, options, tests, install                                | Header-only. Smaller community than nlohmann but useful variety.                                                                                                     |
| **tinyxml2**   |  ~5k  |         ~5 | <5s       | add_library (static AND shared), tests, install, options                  | C++ but very simple. Classic mid-size embedded library style.                                                                                                        |
| **yaml-cpp**   |  ~5k  |       ~10–15 | <10s      | add_library, options, tests, install, Config export, generator expressions | Mid-complexity; uses generator expressions in install rules — good for exercising the genex passthrough.                                                             |
| **re2**        |  ~9k  |        ~10 | <5s       | add_library, options, install, GoogleTest as optional dep                  | Google-grade cmake. Cleaner than abseil's; smaller surface.                                                                                                          |
| **abseil-cpp** | ~14k  |        ~50 | ~30s      | Massive helper-function style (`absl_cc_library`), options, install        | Their custom `absl_cc_library` is structurally similar to llvm's `add_llvm_library` — tests how we handle large project-local helper-function corpora.                |

### 3.3 Harder tier — defer until oracle matures

| project          | stars | cmake files | configure | why deferred                                                                                                                                  |
| ---------------- | ----: | ----------: | --------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| **GLFW**         | ~13k  |        ~30 | <10s      | Heavy `if(WIN32)` / `if(APPLE)` / `if(UNIX AND NOT APPLE)` branches. Excellent platform-branch test but turns simple round-trip into a matrix. |
| **googletest**   | ~35k  |        ~10 | <5s       | Old-style cmake, lots of legacy guards. High visibility but lower modernity. Worth doing after we cover the modern shapes.                     |
| **protobuf**     | ~65k  |        ~30 | ~1 min   | Modern but configure does compiler-feature probes that take time; also bundled vendor deps. Worth doing for visibility, not for iteration speed. |

### 3.4 Not recommended (for this stage)

| project | reason                                                                                          |
| ------- | ----------------------------------------------------------------------------------------------- |
| **boost** | partial cmake (was b2 / bjam); cmake support is incomplete and inconsistent across modules     |
| **OpenSSL** | uses Perl-based Configure system, not CMake                                                  |
| **curl** | has cmake but the configure-only path is messy; autotools is the canonical build               |
| **SQLite** | upstream uses Makefiles; cmake forks are not canonical                                        |

## 4. Coverage map

What each first-round project exercises (✓ = central, ◯ = lightly):

| feature                          | fmt | nlohmann | doctest | spdlog | cJSON |
| -------------------------------- | :-: | :------: | :-----: | :----: | :---: |
| `add_library` (compiled)         |  ✓  |          |         |   ✓    |   ✓   |
| `add_library INTERFACE`           |  ✓  |    ✓     |    ✓    |   ◯    |       |
| `add_executable` (tests/examples) |  ✓  |    ✓     |    ✓    |   ✓    |   ✓   |
| `target_include_directories`      |  ✓  |    ✓     |    ✓    |   ✓    |   ✓   |
| `target_link_libraries`           |  ✓  |          |         |   ✓    |   ◯   |
| `target_compile_definitions`      |  ✓  |    ✓     |         |   ✓    |       |
| `option()`                        |  ✓  |    ✓     |    ✓    |   ✓    |   ✓   |
| `set(CACHE ...)`                  |  ◯  |    ◯     |         |   ◯    |   ◯   |
| `if(WIN32)` / platform branches   |  ✓  |    ◯     |         |   ✓    |   ◯   |
| `BUILD_TESTING` gated tests       |  ✓  |    ✓     |    ✓    |   ✓    |   ✓   |
| `install(TARGETS …)` rules        |  ✓  |    ✓     |    ✓    |   ✓    |   ✓   |
| `*Config.cmake` export            |  ✓  |    ✓     |    ◯    |   ✓    |   ◯   |
| `find_package` of own deps        |     |          |         |   ✓    |       |
| generator expressions `$<…>`      |  ◯  |    ◯     |         |   ◯    |       |
| C language                        |     |          |         |        |   ✓   |

The 5-project suite covers every row at least once.

## 5. Recommended first benchmark round (5 projects)

In suggested order of attack:

1. **fmt** — anchor. Most-recognized name, modern-cmake reference,
   sufficient feature surface that bugs surface fast. If we
   round-trip fmt cleanly, the demo writes itself.
2. **nlohmann/json** — INTERFACE-library + install + export.
   Tests the header-only / Config-export shapes that fmt
   doesn't dominantly exercise.
3. **spdlog** — adds a real dependency (fmt) to the suite.
   Surfaces `find_package(fmt)` + downstream linkage. Pairs
   semantically with fmt as a real consumer.
4. **doctest** — sanity baseline. Smallest realistic cmake;
   regression-detector if a later commit breaks the simple
   path.
5. **cJSON** — C-language confirmation. Different surface
   conventions (no `target_compile_features`, more direct
   compiler-flag use). Round-trip should still hold; if not,
   we've learned something specific.

This is the *first* round; second round picks from § 3.2.
Avoid GLFW / protobuf / abseil-cpp until the oracle plumbing
(behavior-level, beyond cache) is in place — they're high-value
but high-iteration-cost.

## 6. What "benchmark" means here

Two distinct measurements, both should run on every candidate:

1. **Round-trip** (Bar #3-lite oracle, already implemented):
   `tool/cmake_roundtrip/test_corpus.sh <path-to-clone>`.
   Expected: STRUCT=0, FORMAT=0 on all files. Per-file
   modeled/stdlib/resolved/generic/other counts get logged.

2. **Cache + cmd-line behavior** (per-project extension of the shipped
   cache oracle, future):
   For each project's documented options, run real cmake with
   various `-D` flag combinations; capture cache state via
   `cmake -LA -N` or message() probes; compare to yc-eval's
   prediction. Specific test programs are drawn from the
   project's actual CMakeLists, not synthetic.

Phase 1 (round-trip) is mechanical — clone, run, log.
Phase 2 needs harness work but the per-project surface is
documented in each project's README.

## 7. Caveats

- **Numbers are approximate.** Star counts and cmake file
  counts drift; treat the table as a sketch, not a contract.
  Concrete counts come from `find <repo> -name CMakeLists.txt
  -o -name '*.cmake' | wc -l` on a fresh clone.
- **Modern cmake bias.** This list favors projects that
  follow target-centric cmake (≥ 3.5 era). Older codebases
  exist (zlib, openssl-cmake-port) but exercise less of the
  IR we've built.
- **PyTorch is not yet in scope.** A prior prompt suggested
  it was already done; it's not. PyTorch's `FetchContent` +
  CUDA detection + vendored deps make it the hardest target
  in the broader ecosystem; defer until z3/llvm-level
  capability has been validated on multiple smaller
  projects first.
- **`abseil-cpp`** is the closest analog of llvm's
  `add_llvm_library` style outside llvm itself. Once we add
  it (second round), it tests how well our generic-Apply
  + project-index machinery handles a large project-local
  helper-function corpus. Strongly recommended for the
  *second* round.
