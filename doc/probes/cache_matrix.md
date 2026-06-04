# fmt matrix smoke — coverage pipeline infra

> **Purpose.** Code-anchored walkthrough of the fmt matrix smoke test
> ([test/test-runcmake/test_fmt_matrix_smoke.ml](../test/test-runcmake/test_fmt_matrix_smoke.ml)) —
> the per-cell real-vs-predicted cmake-cache diff that's been our
> primary signal for closing the predictor's gaps.

## At a glance

```
            fmt CMakeLists.txt
                   |
        +----------+-----------+
        |                      |
        v                      v
   cache_vars.exe         Cmake_bridge.parse_file
   (static walk)          (parse.py → C.exp → yc)
        |                      |
        v                      |
   11 OPTION/BOOL              | parse-once,
   declarations                | reused per cell
        |                      |
        v                      v
   24 (opt × {ON,OFF}) cells   yc AST
        |                      |
        +-----------+----------+
                    |
              for each cell:
                    |
          +---------+----------+
          v                    v
   real cmake               yc-eval
   (spawn process,          (in-process,
   ~300ms)                  ~30ms)
          |                    |
          v                    v
   CMakeCache.txt          env.cache_vars
   parsed → (k, v) list    Map → (k, v) list
          |                    |
          +---------+----------+
                    v
        diff w/ classifier tier filter
        (Project + Unknown only;
         drop Reserved_cmake / _build noise)
                    |
                    v
        {matched, mismatched, real_only, pred_only}
                    |
                    v
        rollups across all 24 cells
```

## Phase 1 — Static option discovery

[`tool/cmake_roundtrip/cache_vars.ml`](../tool/cmake_roundtrip/cache_vars.ml)
statically walks the cmake CST (parse.py → JSON) and emits one TSV
row per cache-writing site:

```
<name>\t<kind>\t<default>\t<help>\t<file>\t<conditional>
```

where `<kind> = OPTION | BOOL | STRING | PATH | FILEPATH | INTERNAL`.
`<default>` may be a literal, empty, or a `${VAR}` reference (kept
verbatim — eval-time problem, not parse-time).

[`load_fmt_options`](../test/test-runcmake/test_fmt_matrix_smoke.ml#L202)
keeps only the `OPTION` + `BOOL` rows — those become the flip axis.
For fmt, 11 such declarations × {ON, OFF} = **24 cells**.

Why static rather than evaluating the predictor and reading its
declarations: static discovery surfaces options gated inside
`if()` that a dynamic walker might never reach. The matrix wants
the full surface area.

## Phase 2 — Parse-once

```ocaml
let fmt_program =
  lazy (
    match Cmake_bridge.parse_file
            ~path:(fmt_dir ^ "/CMakeLists.txt") with
    | Some expr -> expr
    | None -> failwith ...)
```

[`Cmake_bridge.parse_file`](../src/runner/cmake_bridge.ml#L160):

1. shells out to `parse.py` → JSON CST
2. `Cmake_text_parse.file_of_json` → Stage-1 `cmd | block | raw`
3. [`stmts_to_yelu`](../src/runner/cmake_bridge.ml#L105) maps each
   stmt:
   - `Cmd c`: `Cp.parse_cmd c` → `Lang_cmake.exp option`
     - `Some exp → Fe.from_emit exp` (typed bridge)
     - `None → e_apply name args` (lenient — runs evaluated args
       for side effects, returns VUnit; covers unmodeled cmake
       commands AND user-defined function dispatch)
   - `Block { block_type = "if"; … }` → `ECmakeIfStmt`
   - `Block { block_type = "function"; … }` → `ECmakeFunction`
   - `Block { block_type = "macro"; … }` → `ECmakeMacro`

The `lazy` ensures the cost (~250ms for fmt) is paid once and the
AST is reused across all 24 cells. Each cell only re-evals.

## Phase 3 — Per-cell run

### Real cmake

```ocaml
let real_cache_for ~cmd_line ~build_dir =
  let result = Cmake_runner.run_configure
    ~source_dir:fmt_dir ~build_dir ~cmd_line "" in
  if result.run.exit_code <> 0 then [] else result.cache
```

[`Cmake_runner.run_configure`](../src/runner/cmake_runner.ml#L203)
spawns cmake:

```
cmake -B /tmp/fmt_matrix_smoke/FMT_FUZZ_ON \
      -S /home/red/code/contrib/fmt-all/fmt \
      -DFMT_FUZZ=ON
```

After exit, [`parse_cache`](../src/runner/cmake_runner.ml#L160)
reads `CMakeCache.txt`, strips comments/types, returns `(key,
value)` pairs. ~300ms per cell.

### Predicted

```ocaml
let env, _ = Convert.eval_yelu_cmake_expr ~cmd_line initial_env prog in
Map.to_alist env.cache_vars
|> List.map ~f:(fun (k, v) -> k, render v)
```

Three pre-populated state pieces matter:

- **defaults** ([line 111-117](../test/test-runcmake/test_fmt_matrix_smoke.ml#L111)):
  cmake auto-sets `CMAKE_CURRENT_LIST_DIR`, `CMAKE_CURRENT_SOURCE_DIR`,
  `CMAKE_INSTALL_PREFIX`, `CMAKE_SOURCE_DIR`, `CMAKE_BINARY_DIR`.
  Without them, `${CMAKE_CURRENT_LIST_DIR}/...` substitutions yield
  empty and downstream resolution breaks.
- **`include_loader = Some Cmake_bridge.loader`**: enables
  `include(GNUInstallDirs)` to actually load + eval the stdlib
  module. The loader resolves through `CMAKE_MODULE_PATH` then
  cmake's stdlib `Modules/` dir (auto-probed via `cmake -P` in
  `Cmake_bridge.probe_cmake_modules_dir`).
- **`subdir_loader = Some Cmake_bridge.subdir_loader`**: enables
  `add_subdirectory(test)` to descend into nested CMakeLists.txt
  with directory scope semantics (push_frame).

`~cmd_line:[(opt, val)]` is threaded into
`eval_yelu_cmake_expr` and pre-populates `env.cache_vars[opt] =
val` before evaluation starts. That's how `-DFMT_FUZZ=ON` skips
fmt's `option(FMT_FUZZ "..." OFF)` — `option()` is a NO-OP when
the cache entry already exists.

Value rendering ([line 129-137](../test/test-runcmake/test_fmt_matrix_smoke.ml#L129)):
`VBool → "ON"/"OFF"`, `VString` verbatim, `VInt → number`. Matches
`CMakeCache.txt` format.

## Phase 4 — Diff + classifier

```ocaml
let tier = Cache_classify.classify ~project ~reserved name in
match tier with
| Reserved_cmake | Reserved_build -> ()    (* ignore *)
| Project | Unknown ->                     (* compare *)
  match Map.find real_set name, Map.find pred_set name with
  | Some r, Some p when String.equal r p -> Int.incr matched
  | Some r, Some p -> mismatched := (name, r, p) :: …
  | Some r, None -> real_only := …
  | None, Some p -> pred_only := …
```

[`Cache_classify`](../src/runner/cache_classify.ml) is the
**noise filter**. Four tiers:

| tier | source | example |
|---|---|---|
| `Reserved_cmake` | `tool/cmake_roundtrip/cmake_reserved.tsv` (1597 entries, auto-generated from cmake docs) | `CMAKE_GENERATOR`, `CMAKE_CXX_COMPILER` |
| `Reserved_build` | convention (`BUILD_*`) | `BUILD_SHARED_LIBS`, `BUILD_TESTING` |
| `Project` | `fmt_project_names ()` (cache_vars.exe output) | `FMT_DOC`, `FMT_FUZZ` |
| `Unknown` | none of the above | dynamic-decl entries, bridge gaps |

Only `Project | Unknown` are compared. Without this filter the
matrix would surface ~1500 false positives per cell (every cmake
internal variable real cmake writes that we don't model).

The diff yields four lists:
- `matched`: same name, same value → count
- `mismatched`: same name, different value → `(name, real_value, pred_value)`
- `real_only`: real cmake wrote it, we didn't → `(name, real_value)`
- `pred_only`: we wrote it, real cmake didn't → `(name, pred_value)`

## Phase 5 — Cross-cell rollups

After per-cell diffs, three views aggregate the same name across
all 24 cells:

**Real-only rollup** ([`print_real_only_rollup`](../test/test-runcmake/test_fmt_matrix_smoke.ml#L246)):

```
23/24 (95%)  DOXYGEN              ← present in 23 of 24 cells
 1/24 ( 4%)  FMT_FUZZ_LDFLAGS     ← present in 1 of 24 cells
```

The cell-count tells you **whether a gap is config-dependent or
universal**:

- **100% (24/24)** = constant gap; fix lifts every cell
- **95% (23/24)** = gated by one specific option value (e.g.
  DOXYGEN absent when FMT_DOC=OFF, since `add_doc_target()` is
  never called)
- **4% (1/24)** = only present in one specific configuration
  (FMT_FUZZ_LDFLAGS only when FMT_FUZZ=ON because
  `add_subdirectory(test/fuzzing)` is gated)

**Pred-only rollup** ([`print_pred_only_rollup`](../test/test-runcmake/test_fmt_matrix_smoke.ml#L263)):
mirror of the above; tells you what WE write that real cmake
doesn't. Useful for catching over-eager evaluation — fmt's
MKDOCS leaking past `add_doc_target`'s early `return()` showed
up here at 100% before the `ECmakeReturn` bridge.

**Option flip analysis** ([`print_option_flip_analysis`](../test/test-runcmake/test_fmt_matrix_smoke.ml#L281)):
per-option signature comparison.

```
[FLIPS]  FMT_DOC   ON->{m=20 ro=0 mm=0 po=0}  OFF->{m=19 ro=0 mm=0 po=0}
[stable] FMT_OS    m=20 ro=0 mm=0 po=0
```

`[FLIPS]` means flipping ON↔OFF changes the diff shape — option
gates something cache-visible. `[stable]` means it doesn't —
option is inert at the cache level (still does work at later
phases, but no cache surface).

## Regression gate

```ocaml
let median = List.nth_exn sorted (n / 2) in
Alcotest.check (median >= 8)
```

Originally `>= 8` when single-shot smoke was 10/cell. Today's
median is 20, so the gate is loose. **Optional follow-up**:
tighten to `>= 18` to catch subtler regressions.

## Performance

| phase | time | scale |
|---|---|---|
| static option discovery | ~50ms | once |
| parse fmt CMakeLists | ~250ms | once (lazy) |
| real cmake per cell | ~300ms | × 24 = 7.2s |
| yc eval per cell | ~30ms | × 24 = 0.72s |
| **total** | **~11s** | one matrix run |

Real cmake dominates. The architecture is right — we couldn't
predictably get 20× faster than `cmake -B`.

## What sits upstream

Three pieces are load-bearing but invisible inside the test file:

1. **I/O-free callback discipline** — `Cmake_bridge` provides
   `loader` and `subdir_loader` as values registered into the
   pure `Yelu_cmake.env`. The library never spawns processes;
   the runner does. See
   [io_architecture.md § 3](../yelu_cmake/io_architecture.md#3-the-callback-via-env-pattern).
2. **Reserved-name index** — 1597 entries in
   `cmake_reserved.tsv` make tier filtering meaningful. Without
   it the matrix would drown in false positives.
3. **Pre-populated env defaults** — `CMAKE_CURRENT_SOURCE_DIR`
   was an early bug (missing → all `add_subdirectory` paths
   resolved to yelu repo). Easy to forget when porting to a
   second corpus.

## Extending to a new corpus

To rebuild this for, say, `bzip3`:

1. Verify `cache_vars.exe` extracts the project's options
   (`OPTION` + `BOOL` rows).
2. Set `fmt_dir → bzip3_dir`, refresh `cmd_line` defaults
   appropriate to that project.
3. Verify all 24 cells configure cleanly with real cmake first
   (the test treats `exit_code != 0` as an empty real cache —
   catastrophic real-only count). If a cell fails, the project
   likely needs a `find_package` we don't model; add it to the
   `assumed_found_packages` whitelist or accept the per-cell
   gap.
4. Build the project's `<name>_project_names ()` from cache_vars
   output (same as `fmt_project_names`).
5. Run the smoke. Real-only rollup tells you what's missing;
   pred-only tells you what you're over-eager about.

For corpora bigger than fmt (z3, llvm), expect a larger pool of
universal gaps — `find_package(X)` recursion is the next big
piece; until that lands, each new project will surface a
batch of bridges-to-stubs (Threads-style whitelisting).

## Related docs

- [../yelu_cmake/io_architecture.md](../yelu_cmake/io_architecture.md) —
  the library/runner split this whole thing depends on
- [../yelu_cmake/status.md](../yelu_cmake/status.md) — what's
  still deferred and what's loader-stub-only
- [parse_print_oracle.md](parse_print_oracle.md) — the sibling
  oracle (parse → print → tree-sitter-diff round-trip)
- [../cmake/cache_semantics.md](../cmake/cache_semantics.md) —
  cmake's cache vs normal variable namespace (drives why we
  classify Reserved_cmake separately)
