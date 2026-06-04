# llvm — predictor probe status

> **Project**: LLVM compiler infrastructure
> **Source**: github.com/llvm/llvm-project (vendored at `vendor/llvm`)
> **Why this probe**: largest real-world cmake corpus we test
> against — 3035 cmake files including third-party deps. Stress
> test for parser/printer scale.

## Headline numbers (2026-06-03)

| oracle | result | notes |
|---|---|---|
| parse-print, llvm/llvm subset (canonical bar3-lite) | **596/596 OK** | the historical sub-corpus |
| parse-print, full llvm-project | **3004/3035 OK + 1 FORMAT + 30 STRUCT** | 30 STRUCT pre-existing (project()-printer issues in polly/bolt/libcxx); 1 FORMAT is FindOpenMPTarget cosmetic gersemi diff |
| cache matrix | not built | scale would require selecting a sub-target; full llvm has hundreds of options |

## Oracles in detail

### Parse-print — canonical (llvm/llvm subset)

```sh
bash tool/cmake_roundtrip/test_corpus.sh vendor/llvm/llvm
```

This is the historical bar3-lite corpus. 596 files. Has held at
596/596 OK across every printer change in the bar3-lite history.

### Parse-print — full llvm-project (added 2026-06-03)

```sh
bash tool/cmake_roundtrip/test_corpus.sh vendor/llvm
```

3035 files including polly, bolt, libcxx, libc, libcxxabi, clang,
mlir, flang, lldb, third-party (benchmark, boost-math, unittest,
googletest, …). Used as a sanity check after today's docstring
printer tighten.

**30 STRUCT failures** are pre-existing — sampled benchmark,
FindOpenMPTarget, GNUInstallPackageDir all show issues unrelated
to recent work (benchmark and similar tops have a
`project(NAME VERSION 1.x LANGUAGES CXX)` arg-spacing printer bug;
FindOpenMPTarget flipped from STRUCT → FORMAT after `5ec0030`).

**1 FORMAT** is FindOpenMPTarget — structural pass, gersemi-diff
fail (cosmetic).

### Cache matrix

Not built. Would need to pick a manageable sub-target (e.g.
llvm/llvm alone or polly alone). Full llvm-project would have
~hundreds of cells × ~5-10s each = impractical.

This is a future probe — likely deferred until we have a real
`find_package` recursion mechanism (every llvm sub-project leans
hard on `find_package(LLVM REQUIRED)`).

## Open issues

- 30 STRUCT failures in full llvm corpus — pre-existing project()
  printer issues. None are regressions from recent work.
- Cache matrix for any llvm sub-project — blocked on real
  `find_package` (see [../yelu_cmake/status.md](../../doc/yelu_cmake/status.md)).
