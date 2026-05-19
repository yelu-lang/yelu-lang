# yelu_cmake — Status & Current Open Work

Living tracker. Strip and update freely; durable design is in
`design.md`, code-anchored module guide in `structure.md`,
chronological history in `../worklog_2026_05.md` (includes the
retirement archive).

## Current state (2026-05-14)

Retirement complete through E1. `src/langs/yelu_legacy/` is on
disk but excluded from the `yelu_langs` library; no `src/` or
`test/` file imports it. Production binaries route through
`Yelu_cmake_utils → Yelu_cmake → Yelu_cmake_emit → Lang_cmake_pp`.

Verification:
- 1010 unit tests pass
- 50/50 `make runcmake-yelu`
- 12/12 `make cmake-only-check`
- 12 step tests pass
- `make cmake-commands` was broken pre-E1 and remains broken
  with pre-existing cmake build issues; not blocking.

## Open work

### E2 — delete yelu_legacy/

Mechanical follow-up to E1: `git rm -r src/langs/yelu_legacy/`,
revert `src/langs/dune` to plain `(include_subdirs unqualified)`,
remove the negative-module list. Removes the brittle dune
exclusion the audit flagged. Gated on:
- E1 holding green for some soak time (currently 1 day)
- Y17 not needing legacy as a reference (decide as Y17 takes
  shape)

### Y17 — types on yelu_cmake

Post-retirement typing pass. The previous attempt (per-fragment
`Stage_typecheck`) was structurally shallow: each fragment
validated its own expression types in isolation, with `wellform`
bolted on top to handle cross-theory name binding. With the
proper theory split (`yelu_cmake` ↔ `yelu_cmake_normal`) the
type design has actual semantic ground — namespace separation
is already in `env`, mutability / set-once / identity rules
belong with each theory module, and `to_normal` / `from_normal`
give a natural place to push richer invariants.

Gating decision before Y17 starts: **how much theory-fragment
isolation to bake in first**. The current setup uses a single
extensible `Yelu_cmake.expr` (`type expr += | ECmakeX ...` per
fragment). Tighter alternatives (split `expr` per theory; share
only a small `core_expr`) are discussed in the post-retirement
cleanup list below (items 6–7). Y17 typing rules can be written
either way; the question is whether forcing the split first
makes per-theory test isolation and per-theory typing cleaner,
or whether it's reorganization for its own sake.

## Known IR shape gaps

Documented gaps where the IR + `emit_ast` path cannot model the
full cmake surface. E1 left these as either `failwith` (helper
refuses to emit) or accept-and-discard (helper emits cmake that
ignores the unmodeled option). Pinned by
`test/test-yelu/test_yelu_utils_stubs.ml`.

- **String-comparison conds beyond equality** — `STRLESS` /
  `STRGREATER` / `STRLESS_EQUAL` / `STRGREATER_EQUAL`. IR has
  only `STREQUAL` via `ECmakeStringEqual`. Helpers `failwith`.
- **`add_executable` / `add_library` with `EXCLUDE_FROM_ALL`** —
  IR ctors don't carry the flag. Accept-and-discard.
- **`target_link_libraries` multi-target** — IR surface takes a
  single target; multi-target callers must split per-target.
- **`add_custom_command(TARGET ...)`** — IR only has the
  OUTPUT-form. Helper `failwith`.
- **`math ~output_format`** — IR's `ECmakeMath` doesn't carry
  format. Accept-and-discard; tests using `Hexdecimal` get
  decimal.
- **JSON ops** — `ECmakeStringJson` is opaque (op_name + path
  dropped). Helpers `failwith`.
- **Parser sentinel defaults** — `out_var_y1` `"?"`,
  `cvar_name_of_y1` `"?"`, `expr_to_int_y1` `0` fallback,
  `string_uuid` `"ns"`/`"n"` placeholders, `cmake_minimum_required`
  `"3.20"` fallback, `project` `"Project"` fallback,
  `policy_set` `""` fallback. Vestigial from byte-equality with
  the legacy parser; tightening pairs naturally with Y17.

## Post-retirement cleanup

In order of value:

1. **Split `cmake_op`** into smaller surfaces (project/message,
   control flow, function/macro, process, policy/include).
   390-line surface + 103-line theory is the largest single
   fragment and the broadest compatibility bucket.
2. **Generated fragment coverage table** — auto-generate a
   matrix (semantics eval, lift, lower, emit, bridge, unit
   test, cmake-backed test) per fragment so coverage gaps stay
   visible as constructors are added.
3. **Move emit / convert arms closer to each fragment.**
   `yelu_cmake_convert.ml` (~1.7 k lines) and
   `yelu_cmake_emit_debug.ml` (~964 lines) are central
   registries. Per-fragment convert / emit modules reverse the
   entropy trend.
4. **Y17 — fresh typing pass on yelu_cmake** (see "Open work").
5. **Promote compat surfaces to real theories** where worth it
   (genex first, then find / try / cmake_op subsets). Pairs
   with Y17 — typing decisions inform which surfaces deserve
   the lift.
6. **Categorize `yelu_cmake_normal_*` theories: general vs
   cmake-specific.** `bool`, `int`, `string`, `list`, `store`
   are general-purpose theories any future `yelu_*` language
   (`yelu_shell`, `yelu_c`) would also want; they live next to
   the genuinely cmake-specific ones (`target`, `install`,
   `find`, `property`, `try`) only because the historical
   bundle didn't distinguish.
7. **Split the shared `expr` type between `yelu_cmake` and
   `yelu_cmake_normal`.** Today both use the same extensible
   `Yelu_cmake.expr` via `type expr += ...`; the
   `yelu_cmake` expr universe technically contains every
   `yelu_cmake_normal` ctor and vice versa. A clean separation
   gives each language its own `expr`, with shared nodes
   (`EVar`, `EString`, `EBool`, `EInt`, `ESeq`, `ELet`,
   `ESetVar`, `EUnit`) staying in a small shared core. Pairs
   with item 6 and Y17.

## Project-level milestones (separate from retirement)

- **Bar #3-lite — syntactic round-trip.** *Stages 1 / 2 / 2-b / 2-c
  shipped.* STRUCT=0 / FORMAT=0 across tutorial (25/25),
  z3 (108/108), llvm (596/596). Modeled-builtin counts:
  tutorial 165, z3 1,057, llvm 3,573. Per-stage results,
  deliberately-untyped builtin list, and the Class A
  (`function()` / `macro()`-defined calls) next-step plan
  (resolved-apply bucket) are in `bar3_feasibility.md` §
  2026-05-19.
- **Bar #3 — real-world cmake.** Rewrite z3 / llvm / torch
  builds in `yelu_cmake`, prove structural equivalence with the
  original CMakeLists. Not started; the manifesto-level "does
  this scale" test.
- **Macro elimination.** Whether to drop `function()` / `macro()`
  from yelu_cmake in favor of pure-OCaml parameterization, given
  yelu programs are themselves OCaml. Deferred; revisit with
  Bar #3 data. Memo: `.claude/memory/project_macro_elimination.md`.

## Deferred

- Cache / env namespaces beyond the normal-variable slice.
- Generator expressions as delayed values (currently flow as
  opaque `EString`s via `Ycs_eval`; real cmake handles them at
  generate time).
- Fragment-owned parser composition.
- Subdirectory scope enforcement (`add_subdirectory` records
  but does not isolate var / target scopes).
- Property scope expansion beyond target (global / source /
  test / cache).
- A purer functional-style function theory parallel to the
  cmake-style one (Y15 design space; revisit after F2 in
  production).
- Property / random testing and formal proof.

## Notes

- Old production AST has no dedicated normal-variable
  `unset(NAME)` constructor. Normal unset-like behavior is
  encoded as `Yvar_set` with an empty value list. Dedicated
  unset constructors exist for cache / env only.
- `target_link_libraries`, `target_include_directories`, and
  `target_compile_definitions` preserve `PRIVATE` / `PUBLIC` /
  `INTERFACE` visibility, but do not model generator expressions
  or full transitive usage requirements yet.
