# fmt — predictor probe status

> **Project**: `{fmt}` C++ formatting library
> **Source**: github.com/fmtlib/fmt (vendored at `/home/red/code/contrib/fmt-all/fmt`)
> **Why this probe**: small CMakeLists with rich configure-time
> work (find_program, find_package, try_compile, add_subdirectory,
> function definitions). Good first probe — broad coverage in <600
> lines of cmake.

## Headline numbers (2026-06-03)

| oracle | result | notes |
|---|---|---|
| parse-print | **11/11 OK** | all fmt cmake files round-trip byte-equivalently after the smart docstring printer (commit `4bdf646` + `5ec0030`) |
| cache matrix | **24/24 cells perfect** | median matched per cell = 20; real-only = 0, mismatched = 0, pred-only = 0 |

The fmt probe is **complete within the current architecture** —
every cache entry real cmake writes is predicted with the right
value across all 24 (option × ON/OFF) configurations.

## Oracles in detail

### Parse-print

```sh
bash tool/cmake_roundtrip/test_corpus.sh /home/red/code/contrib/fmt-all/fmt
```

Last result: `OK=11 FORMAT=0 STRUCT=0 PARSE=0`. See
[parse_print_oracle.md](parse_print_oracle.md).

### Cache matrix

```sh
dune exec test/test-runcmake/test_fmt_matrix_smoke.exe
```

Last result: median matched 20, all four diff classes (matched /
mismatched / real_only / pred_only) at their target values. See
[cache_matrix.md](cache_matrix.md)
for the pipeline.

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

## Historical record

[probe_report.md](probe_report.md) — the 2026-06-01 pre-implementation
scoping report from workflow `wcu6hr40t`. Identifies fmt's option
declarations and the cache surface area; the gaps it lists are now
mostly filled. Kept as a reference for how the initial gap analysis
was conducted.

## Open issues specific to fmt

None. Today's stubs (find_program → NOTFOUND, find_package(Threads) →
canned `FIND_PACKAGE_MESSAGE_DETAILS_Threads`, try_compile → FALSE)
match fmt's reference cmake behavior on this host. They'd flip to
mismatches on a system where the underlying tools/libs differ —
which is the next adaptation problem (per-host vs per-project
stubs), not a fmt-specific one.
