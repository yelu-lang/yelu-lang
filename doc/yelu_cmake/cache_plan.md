# Cache namespace + cmd-line input — plan

> **Status (2026-06-01).** Plan, not yet implemented. Promoted to lead
> forward item ahead of the behavior-level oracle (formerly Bar
> #3-full) because cache + `-D` is foundational: every cmake user
> touches it, and the behavior-level oracle cannot ground-truth
> `-DFOO=BAR` programs without it.

## 1. Motivation

The `-DCMAKE_FOO=Bar` flag is how every real cmake project takes
configure-time input. Today's coverage:

| layer        | status                                                                                                                                                       |
| ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **parser**   | ✅ `set(BUILD_SHARED_LIBS ON CACHE STRING "...")` and `option(X "doc" ON)` round-trip through Bar #3-lite.                                                    |
| **IR**       | ✅ `Lang_cmake.Set_cache` / `Lang_cmake.Option`; yc has `ECmakeSetCache` / `ECmakeOption`.                                                                    |
| **emit**     | ✅ Production path emits cache syntax byte-faithfully.                                                                                                        |
| **eval**     | ❌ `ECmakeSetCache` writes to the same store as plain `set`; `ECmakeOption` always overwrites. No separate cache namespace.                                   |
| **`-D` in**  | ❌ No channel to populate the cache before evaluating. `eval_expr empty_env prog` starts empty.                                                               |
| **tests**    | ❌ Zero behavior tests. Only parse-roundtrip exercises `CACHE` / `option` syntax.                                                                             |
| **design**   | ✅ Done — [`../cmake/cache_semantics.md`](../cmake/cache_semantics.md) enumerates 12 cases against real cmake 4.3.1, including the four `-D` interaction rows. |

Three concrete consequences of leaving this unfixed:

- **Community share is blocked.** A "better cmake" demo that
  predicts the wrong value under `-DUSE_X=OFF` isn't a demo.
- **Behavior-level oracle can't ground-truth.** That oracle compares
  yelu predictions against real cmake under a given `-D`
  configuration; we have nowhere to put the configuration.
- **Optimizer correctness is silently wrong.** A constant-fold
  pass on `if(USE_OPENMP)` would use `option()`'s declared default,
  ignoring any `-DUSE_OPENMP=OFF` the user passed. Every
  cache-conditional branch is a potential miscompile.

## 2. Scope

**In:**

- Add `cache_vars` namespace to `env` alongside the existing
  `frames`/`locals` chain.
- `ECmakeSetCache` semantics: write to `cache_vars` only if absent
  or `FORCE`; dual-write to current frame's `locals` on first
  write (cmake's documented behavior — `cache_semantics.md` §
  "Write path").
- `ECmakeOption` semantics: no-op if name already in `cache_vars`;
  otherwise set cache to the declared default.
- `${VAR}` read fallback: normal first, cache second
  (`cache_semantics.md` § "Read path").
- `unset(VAR)` clears normal only; `unset(VAR CACHE)` clears both.
- `eval_expr` gains an optional `?cmd_line:(string * string) list`
  parameter; entries populate `cache_vars` before walking the
  program (`cache_semantics.md` § "Set 4: -D command-line").

**Out (parked):**

- Cross-run cache persistence (real `CMakeCache.txt` on disk).
  Stub-able via `?cmd_line` for now — the *behavior* during a single
  configure is identical whether the cache came from `-D` or from
  a previous run's serialized state.
- Process-env namespace (`set(ENV{FOO} val)` / `$ENV{FOO}`). Code
  already routes these to a no-op in eval; leave that for now and
  flag as a follow-up.
- Cache typing (`STRING` / `BOOL` / `PATH` / `FILEPATH`). Values
  stay as `value` (the existing IR variant) regardless of declared
  type. Typing is a Y17 concern.
- `CACHE FORCE` precedence over `-D` (real cmake: `-D` always wins
  over even `FORCE` for the initial value). Implement as light
  touch; document the deviation if any.

## 3. Design

### 3.1 env split

```ocaml
type env = {
  frames : frame list;        (* unchanged: lexical/function scope *)
  cache_vars : value Map.M(String).t;   (* NEW: configure-time cache, global *)
  files : ...;                (* unchanged *)
  ...
}
```

Cache is **global to the configure run** — it lives outside
`frames` because cmake's cache is shared across all
`add_subdirectory` / `function()` / `block()` scopes. It is
written by `set(CACHE)`, `option()`, and `-D`; read by `${VAR}`
fallback and explicit `$CACHE{VAR}` (latter not yet in IR;
defer).

### 3.2 read path

```ocaml
let find_var env name =
  match find_in_frames env name with
  | Some v -> Some v                       (* normal wins *)
  | None   -> Map.find env.cache_vars name (* fallback *)
```

`var_defined env name` follows the same rule.

### 3.3 ECmakeSetCache eval

```
if env.cache_vars[name] exists AND not FORCE:
  no-op                            (* cache.md § Write path, 2.3, 4.3 *)
else:
  env.cache_vars[name] := value    (* write cache *)
  set_var env name value           (* dual-write to current frame *)
```

### 3.4 ECmakeOption eval

```
if env.cache_vars[name] exists:
  no-op                            (* honor pre-set / -D *)
else:
  env.cache_vars[name] := value    (* declared default *)
  set_var env name value           (* dual-write *)
```

### 3.5 cmd-line entry

```ocaml
let eval_expr ?(cmd_line = []) env expr =
  let env = List.fold cmd_line ~init:env ~f:(fun env (k, v) ->
    { env with cache_vars = Map.set env.cache_vars ~key:k ~data:(VString v) })
  in
  (* ... existing dispatch ... *)
```

Trivial wrapper; the work happens in 3.1–3.4. Same signature
extension on `eval_yelu_cmake_normal_expr`.

## 4. Implementation steps

| step | what                                                                      | est. LOC | est. time |
| ---- | ------------------------------------------------------------------------- | -------: | --------: |
| 1    | Add `cache_vars` field to `env`; thread through `empty_env` + all helpers |       50 |     1-2 h |
| 2    | Update `find_var` / `var_defined` to consult cache as fallback            |       20 |     30 m  |
| 3    | Implement `ECmakeSetCache` first-write-wins + dual-write                  |       30 |       1 h |
| 4    | Implement `ECmakeOption` cache-suppression                                |       10 |     15 m  |
| 5    | Add `?cmd_line` to `eval_yelu_cmake_expr` + `_normal_expr`                |       15 |     30 m  |
| 6    | Mirror env change on ycn side (`yelu_cmake_normal_store`)                 |       30 |       1 h |
| 7    | Existing tests pass (regression check) — lift_lower, dual_eval, compile   |        — |     30 m  |
| 8    | Unit tests: 12 cases from `cache_semantics.md` (see § 5.1)                |      150 |       3 h |
| 9    | Extend dual_eval helper with `?cmd_line`; add cache-bearing lifted cases  |       50 |       1 h |
| 10   | (Stretch) Real-cmake oracle harness for cache subset (see § 5.3)          |      200 |   half-day|

**Subtotal: 2-3 days for steps 1-9. +half-day for step 10.**

Steps 1-6 are mechanical and can land in one commit. Step 7 is
the regression gate — if any of lift_lower / dual_eval /
test_yelu_compile breaks, fix before continuing. Steps 8-10 are
the test-coverage build-up.

## 5. Testing

Three tiers, each with a different role.

### 5.1 Unit tests — the cache-semantics matrix

**Goal:** every row of `cache_semantics.md`'s four tables
(Set 1 through Set 4, 12 rows total) becomes one or more unit
tests. This is the spec-verification tier — if a test fails
here, our eval disagrees with cmake's documented behavior.

**Helper:** new test file `test_yelu_cache.ml` with

```ocaml
let check_cache_eval
      ?(cmd_line = [])
      name prog
      ~expected_normal       (* what ${VAR} reads as *)
      ~expected_cache        (* what $CACHE{VAR} would read as *)
      ~expected_defined      (* if(DEFINED VAR) *)
  = ...
```

Each row of the tables becomes one `check_cache_eval` call.
For example, row 4.2 — *`-D`, then `set(VAR "n")`*:

```ocaml
check_cache_eval "4.2 -D then set normal"
  ~cmd_line:[("VAR", "cmdline")]
  (yc_set (ycvar "VAR") [ystr "n"])
  ~expected_normal:(VString "n")
  ~expected_cache:(VString "cmdline")
  ~expected_defined:true;
```

12 test cases, mechanical. Each one a literal transcription of
the matrix.

### 5.2 Dual-eval extension — cache-bearing programs round-trip ycn

**Goal:** confirm that `to_normal` + ycn-eval agree with yc-eval
on programs that use cache. This is exactly what the dual_eval
helper already does for the non-cache subset — extending it to
take `?cmd_line` lifts the cache programs in.

**Changes:**
- Extend `check_dual_eval` to take `?cmd_line` (pass to both
  evaluators).
- Lift the cache-bearing rows from `test_yelu_compile.ml`'s
  `primitives` and (future) `find_package` sections through
  dual_eval.

**Likely to surface ycn-side gaps** the same way EStringLower
surfaced — `to_normal` may not yet lower `ECmakeSetCache` /
`ECmakeOption` cleanly. The fix pattern is the established one
(add ycn ctor + eval_case + convert arms).

**Won't catch:** semantic disagreement between our eval and
real cmake. That's tier 5.3.

### 5.3 Full / end-to-end — real cmake as ground truth

**Goal:** our eval predictions agree with what real cmake
actually does under the same `-D` flags. This is a mini
behavior-level oracle, scoped to cache only — it's the
first nibble of the larger behavior-level oracle work.

**Harness shape:**

For each test program:
1. Write a tiny `CMakeLists.txt` from the yelu-emitted text.
2. Run `cmake -DFOO=BAR ... -P script.cmake` (or full
   `cmake -S/-B` with the same `-D`s).
3. Capture observable state via `message()` probes or
   `cmake -LA -N` (lists all cache entries).
4. Compare our eval's `cache_vars` and `find_var` predictions
   to cmake's output.

**Probe strategy:**
The existing `test/test_cmake_probes.py` already shells out to
cmake to verify cache behavior empirically (it's how
`cache_semantics.md` was generated). The full-test harness can
reuse the same approach: a script that runs cmake with given
`-D` flags + a yelu-emitted CMakeLists, prints `cache_vars`
state, compares to yc-eval's prediction.

**Smallest viable harness:** one OCaml test (`test_cache_runcmake.ml`)
that for each of the 12 matrix rows:
- emits the yelu program as cmake text,
- runs cmake with the `cmd_line` flags,
- parses the output's cache state,
- diffs against `expected_cache` from the unit test.

**Coverage:** 12 cases × 2 cmake versions (script `-P` vs
configure mode) = 24 invocations. Cheap; runs in seconds.

**Stretch:** extend to `option()` cross-run persistence by
keeping the build dir between rows (cmake re-reads
`CMakeCache.txt`).

### 5.4 Test-suite roles summarized

| tier | catches                                              | costs                | when to run                |
| ---- | ---------------------------------------------------- | -------------------- | -------------------------- |
| 5.1  | our eval ↛ matches our documented spec                | fast, in-process     | every commit (`dune test`) |
| 5.2  | yc-eval ↛ ycn-eval on cache shapes                    | fast, in-process     | every commit               |
| 5.3  | our spec ↛ matches real cmake                         | spawns `cmake -P`    | nightly or `make check`    |

5.1 + 5.2 are blocking for the commit. 5.3 is the
correctness-of-the-spec gate — gives us confidence the
matrix from `cache_semantics.md` (which was hand-verified
against cmake 4.3.1 once) keeps holding as cmake versions
roll forward.

## 6. Open questions

- **`-D` value parsing.** Real cmake's `-DCMAKE_FOO=Bar` always
  parses `Bar` as a string; type comes from a `set(... CACHE
  <TYPE> ...)` declaration elsewhere. Our `?cmd_line` takes
  `(string * string)` pairs; the value is always `VString`.
  Bool-typed cache reads (`if(USE_X)`) work via cmake's
  string-to-bool table — we already implement this for normal
  vars; verify it also fires on cache-fallback reads.

- **`$CACHE{VAR}` explicit syntax.** Currently not in the IR.
  Defer until a program demands it; cache fallback covers most
  use cases.

- **`cache_vars` snapshot for `block()` / function scope.** Cache
  is documented as global — no scoping. Confirm by reading
  `cache_semantics.md` and `scope_and_control_flow.md`; if
  global, the `cache_vars` field stays a plain `Map.t` (no
  frame stack).

- **`?cmd_line` reaching evaluator-external programs (e.g.,
  `include()`'d files).** Cache is global, so once populated
  it's visible everywhere; no extra plumbing needed.

## 7. Non-goals

- Not a redesign of `find_var`'s fallback chain beyond
  adding cache lookup.
- Not the behavior-level oracle itself — only the cache subset
  of it. `include()` resolution + cmake stdlib `Modules/` search
  landed 2026-06-03; full `find_package` filesystem probe (real
  Find<X>.cmake + Config-mode search) still future. Today's stubs
  (whitelist for Threads) close the fmt-matrix surface without
  modeling the search.
- Not Y17 typing (`STRING` / `BOOL` / `PATH` distinctions). Cache
  values stay untyped (`value`).
- Not cache persistence across runs — the `-D` channel is the
  proxy for "previous run's cache" within a single eval.

## 8. Successor unlocks

Once this lands:

- **Behavior-level oracle** is unblocked — cmd-line input + cache
  semantics is the foundation.
- **Optimizer correctness** — constant folding `if(USE_X)`
  becomes safe under known `-D` configurations.
- **Community demos** — every "configures correctly under
  `-DCMAKE_BUILD_TYPE=Debug`" claim becomes testable.
- **Y17 typing** gains real ground — cache vs normal namespace
  is the first type distinction worth enforcing.
- **post-retirement cleanup item #6** (cache theory split) is
  done in spirit even before the formal theory rename.
