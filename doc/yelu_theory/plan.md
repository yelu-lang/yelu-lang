# Theory-fragment split — plan

Plan for the **structural** theory split discussed 2026-05-15. The
**type-level** split (each theory has its own `expr` type) is
explicitly out of scope here; revisit after Y17 surfaces real
constraints. See `status.md` "Post-retirement cleanup" #7 for the
type-level option.

## Goal

Make per-theory tests and (control + theory) test fixtures
ergonomic and conventional, without changing the runtime `expr`
type. The merged result stays exactly `Yelu_cmake.expr` /
`Yelu_cmake_normal.expr`; what changes is **where** each
theory's contribution to the eval / emit / convert pipeline
lives, and **how** tests can be written to exercise one theory
at a time.

This is independent of:
- **Y17 typing** — typing rules can be written against the
  merged `expr` regardless of where the dispatch arms live.
- **Type-level isolation** — defer; Y17 may make the right
  boundary obvious.
- **Q2 (`expr` split)** — defer for the same reason.

## Current state

Per-theory ctors already live in per-fragment files
(`src/langs/yelu/fragments/yelu_cmake_<theory>.ml` and
`yelu_cmake_normal_<theory>.ml`) via OCaml's extensible variants:
`type expr += | ECmakeX of … | ECmakeY of …`. The runtime type
is unified at `Yelu_cmake.expr` / `Yelu_cmake_normal.expr`.

What is **not** per-fragment today:
- **Eval arms** — `src/langs/yelu/yelu_cmake_eval.ml` and
  `yelu_cmake_normal_eval.ml` dispatch a single match across all
  theory ctors.
- **Emit arms (production path)** — `yelu_cmake_emit.ml` (Yelu1
  → `Lang_cmake.exp`) is a single ~1.5k-line match.
- **Emit arms (debug path)** — `yelu_cmake_emit_debug.ml` (~964
  lines) same shape.
- **Convert arms** — `yelu_cmake_convert.ml` (~1.7k lines) holds
  both `to_normal` and `from_normal` as central registries.
- **Control core (`EUnit` / `EVar` / `EString` / `EBool` / `EInt`
  / `ESeq` / `ELet` / `ESetVar`)** is declared at the top of
  `yelu_cmake.ml`, not in a named module.
- **Tests** are organized by axis (compile, parse, emit, steps,
  lift/lower), not by theory.

## Four pieces

Each piece is independent. Land them in any order; build stays
green after each.

### Piece 1 — `Yelu_cmake.Core` module

Move the control ctors out of `yelu_cmake.ml`'s top-level into a
nested `Core` module (or a separate `yelu_cmake_core.ml` file)
that exposes them as the named substrate. Theory fragments
remain extensible (`type expr += ...`) on top of
`Yelu_cmake.expr`, which is built from `Core.expr` plus the
extension points.

**Why first**: makes the "control vs theory" boundary
documentable at the type-system level (every fragment imports
`Core`), without changing any semantics. Surfaces what other
fragments transitively assumed about the control core.

**Cost**: ~half-day reshuffle. Naming + imports; no logic
changes.

**Verifies via**: existing test suite passes unchanged.

### Piece 2 — Per-fragment eval arms

Move each theory's eval contribution from
`yelu_cmake_eval.ml` / `yelu_cmake_normal_eval.ml` into the
fragment file. The central eval becomes a small dispatcher that
tries each fragment's `eval_case ~eval env expr` and falls
through.

Each fragment exports:
```
val eval_case :
  eval:(env -> expr -> env * value) ->
  env -> expr -> (env * value) option
```

The central eval folds across fragments and returns
`Fail "no eval arm for …"` when every fragment returns `None`.
This is essentially the shape the legacy bridge already used.

**Why this matters for per-theory tests**: today the string
theory's eval is tangled with everyone else's at a single match.
After this, a string-only test can call
`Yelu_cmake_string.eval_case` directly and not even link the
list / target fragments at the test-fixture level.

**Cost**: ~1 day. Mechanical extraction; each theory carries
~50–200 lines of arms. The most invasive part is the env type
(see Piece 3).

**Verifies via**: existing eval tests pass; add a per-theory
eval test as a smoke check.

### Piece 3 — Per-fragment emit arms (debug path first, production second)

Same shape as Piece 2 but for emit. Start with `emit_debug`
because it's smaller (~964 lines) and not on the production
critical path; production `emit_ast` follows once the debug
split has soaked.

Each fragment exports:
```
val emit_case :
  emit:(expr -> string list) ->
  expr -> string list option
```

for the debug emitter, and the analog for `emit_ast` mapping
into `Lang_cmake.exp`.

**Why split debug first**: catches design issues without putting
the production oracle at risk. Debug emitter has a smaller
surface (no `Lang_cmake.exp` complexity).

**Cost**: ~1–2 days for debug, similar for production.

**Verifies via**: byte-equality of emitted text for all 194
oracle programs (inline goldens in `test_yelu_compile.ml`).

### Piece 4 — Per-theory test files

Add `test/test-yelu/test_yelu_cmake_<theory>.ml` per theory.
Each file:
- Opens only `Yelu_cmake.Core` + the one theory (after Piece 1)
- Constructs test programs using only those ctors
- Calls the theory's `eval_case` / `emit_case` directly (after
  Pieces 2 / 3)
- Asserts eval results + emit text

This is the (control + theory) test surface. It does **not**
enforce theory isolation at the type level — the `expr` is
still extensible — but it gives a clear convention for where
per-theory tests live and what they exercise.

**Cost**: ~1 day per theory once Pieces 1–3 are in. 14 theories
× ~1 hour each.

**Verifies via**: each file is a fresh test suite; build green
+ tests pass.

## What this does **not** do

- **No `expr` split.** `Yelu_cmake.expr` stays one extensible
  type. A future Q2 (poly variants / per-theory expr types)
  would build on top of this layout.
- **No type-level isolation.** A test can still construct a
  list-theory ctor in a "string test" file; nothing prevents
  it. Conventions only.
- **No new IR ctors or semantic changes.** Purely organizational.
- **No subdirectory scope, no real genex eval, no policy
  modeling.** All deferred per `status.md`.

## Sequencing

```
Piece 1 (Core module)
   ↓
Piece 2 (eval) — independent of Piece 3
Piece 3 (emit_debug, then emit_ast) — independent of Piece 2
   ↓
Piece 4 (per-theory tests) — needs Pieces 1–3 in for full benefit
```

Each piece is a single PR. Total: ~1 week of careful work, or
two weeks at a relaxed pace. Build stays green throughout.

## Open questions

- **Eval env type per theory** — today's `env` is a single
  record carrying var / cache / target / file / install / test /
  property / find / function maps. Some theories only touch a
  subset. After Piece 2, do we want per-theory env projections,
  or does every theory keep accessing the full env? Defer to
  Piece 2 design.
- **Fragment naming** — fragments today are
  `yelu_cmake_<theory>.ml`. After Piece 2 each fragment carries
  more than ctors (also `eval_case`); does the naming need to
  shift toward `theory_<name>.ml` or similar? Cosmetic; decide
  during Piece 2.
- **Test layout** — `test_yelu_cmake_<theory>.ml` parallels the
  fragment file. Worth grouping the parser / compile / emit
  per-theory axis under per-theory dirs (`test/test-yelu/string/`
  etc.) once the count grows? Defer.

## Pilot

Pick **string** as the pilot theory for Pieces 2–4:
- Smallest non-trivial theory (~14 helpers, ~140 lines of eval
  arms, ~150 lines of emit arms).
- Touches the env (set_var on output cvar) but nothing
  cross-theory.
- Has the widest test coverage already, so byte-equality drift
  surfaces immediately.

After string lands successfully, fan out to the rest by lines of
arms (cmake_op last — it's 390 lines and the messiest).
