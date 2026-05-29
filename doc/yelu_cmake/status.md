# yelu_cmake — Status & Current Open Work

Living tracker. Strip and update freely; durable design is in
`design.md`, code-anchored module guide in `structure.md`,
chronological history (retirement archive + Bar #3-lite audit
trail) in `../worklog/worklog_2026_05.md`.

## Current state (2026-05-20)

- Retirement of `src/langs/yelu_legacy/` complete through E1.
  `src/langs/yelu_legacy/` is on disk but excluded from the
  `yelu_langs` library; no `src/` or `test/` file imports it.
  Production binaries route through
  `Yelu_cmake_utils → Yelu_cmake → Yelu_cmake_emit → Lang_cmake_pp`.
  Detail in `worklog_2026_05.md` "Retirement (May 11 — May 14)".
- Bar #3-lite syntactic round-trip shipped through Stage 2-c.
  STRUCT=0 / FORMAT=0 across tutorial (25/25), z3 (108/108 —
  modeled 1,056 / generic 707), llvm (596/596 — modeled 3,572 /
  generic 2,610). Audit-ready at `bar3_lite.md`.

Verification baseline:
- 1010 unit tests pass
- 50/50 `make runcmake-yelu`
- 12/12 `make cmake-only-check`
- 12 step tests pass
- `make cmake-commands` was broken pre-E1 and remains broken
  with pre-existing cmake build issues; not blocking.

## Open work

### IR-printer cleanup (Bar #3-lite follow-up)

The round-trip work surfaced a catalogue of cases where the
production `Lang_cmake_pp` printer drops, reorders, or
emits-keyword-the-source-didn't-have. Each forces the
corresponding `print2.ml` parser to bail to generic Apply
(STRUCT-faithful but loses typed access). Closing them
mechanically moves shapes from `generic` into `modeled` and
makes the IR a closer fit for real-world cmake. Per-parser
detail in `bar3_lite.md` § 8.

**Tier 1 — quick wins, expected to bump modeled count noticeably.**

| # | command | issue | shape of fix | status |
| -: | --- | --- | --- | --- |
| A1 | `cmake_minimum_required` | `Cmake_minimum_required.max` field exists; printer drops via `max = _` at `lang_cmake_pp.ml:781` | Wire the printer to emit `<min>...<max>` when `max = Some _`. | ✅ done |
| B1 | `add_dependencies` | `Add_dependencies.dep : depend` single; cmake allows N | Widen to `deps : depend list` in IR + printer + parser. | ✅ done |
| B2 | `set_target_properties` | `Set_target_properties.target` single; cmake allows N | Widen to `targets : target list`. | ✅ done |
| C1 | `find_program` / `find_path` | Printer always emits `NAMES` keyword; bare `find_program(VAR name)` form unmodeled | Either skip NAMES when single bare name, or add a flag on the IR. | ✅ done (added `short_form : bool` to `find_var_args`) |
| C2 | `include_directories` | Printer always emits `BEFORE`/`AFTER`/`SYSTEM` prefix | Make printer respect `before_or_after = Default_order` and `system = false` by emitting cleanly. | ✅ done (parser now consumes the keywords matching cmake spec order) |

**Tier 2 — larger, more design.**

- ✅ **A3 `set_property` printer rewrite** — shipped 2026-05-29.
  Introduced `set_property_scope` sum type
  (`Sps_global` / `Sps_directory` / `Sps_target` / `Sps_source` /
  `Sps_install` / `Sps_test` / `Sps_cache`). Set_property record
  redesigned around `{ scope; append; append_string; property;
  values }` so each call corresponds to ONE cmake `PROPERTY`
  clause (printer used to drop most scope fields and split
  multi-property into N statements). yelu-side production API
  (`yc_set_property` / `yc_set_global_property`) fans out into
  `Exp_list` of single-property calls. Corpus delta: z3 +1, llvm
  +63 modeled. CACHE scope still bails (cache_entry IR is a
  data-less placeholder).
- ✅ **A2 `get_property` printer rewrite** — shipped 2026-05-29.
  Same shape as A3: new `get_property_scope` sum type
  (`Gps_global` / `Gps_directory` / `Gps_target` / `Gps_source` /
  `Gps_install` / `Gps_test` / `Gps_cache` / `Gps_variable`) plus a
  `get_property_mode` enum (`Gpm_value` / `Gpm_set` / `Gpm_defined`
  / `Gpm_brief_docs` / `Gpm_full_docs`). The old printer pattern
  dropped `source_target_directory`, `test_directory`, and the
  DEFINED/BRIEF_DOCS/FULL_DOCS modes via `_;` — bugs the round-trip
  surfaced and the redesign closes. yelu-side
  `ECmakeGetProperty` emit corrected from misusing
  `source_target_directory` to using `Gps_target`. Corpus delta:
  z3 +7, llvm +68 modeled (larger footprint than A3).
- ✅ **D1 `execute_process` typed** — shipped 2026-05-29.
  IR was already complete enough; just needed a parser. The
  printer's canonical keyword order (COMMAND, WORKING_DIRECTORY,
  TIMEOUT, RESULT/OUTPUT/ERROR_VARIABLE, INPUT/OUTPUT/ERROR_FILE,
  OUTPUT/ERROR_QUIET, …_STRIP_TRAILING_WHITESPACE,
  COMMAND_ERROR_IS_FATAL) is enforced by the parser via a rank
  check — sources with out-of-order keywords bail to generic so
  STRUCT stays clean. RESULTS_VARIABLE / COMMAND_ECHO / ENCODING /
  ECHO_OUTPUT_VARIABLE / ECHO_ERROR_VARIABLE bail (IR doesn't carry
  them). Corpus delta: z3 +22, llvm +43 modeled.

**Tier 3 — typed-IR misclassification opportunities.**

- E1 / E2 add_executable / add_library variant parsers
  (`Add_executable_imported`, `Add_library_alias`, etc. — IR
  ctors exist but no parser populates them).
- E3 add_executable `options` (`Ae_win32` / `Ae_macos_bundle`
  ctors exist; parser currently bails on them).
- D2 `file READ` / `file STRINGS` (slot order reversed vs source).

**Ordering recommendation:** Tier 1 as five small per-fix commits
(each with a corpus delta in the commit message). Tier 2 + 3 as
deeper investments after Tier 1's modeled count delta is visible.

### E2 — delete yelu_legacy/

Mechanical follow-up to E1: `git rm -r src/langs/yelu_legacy/`,
revert `src/langs/dune` to plain `(include_subdirs unqualified)`,
remove the negative-module list. Removes the brittle dune
exclusion the audit flagged. Gated on:
- E1 holding green for some soak time
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

## Known IR shape gaps (emit side)

Documented gaps where the IR + `emit_ast` path cannot model the
full cmake surface. E1 left these as either `failwith` (helper
refuses to emit) or accept-and-discard (helper emits cmake that
ignores the unmodeled option). Pinned by
`test/test-yelu/test_yelu_utils_stubs.ml`.

The Bar #3-lite round-trip surfaced a parallel list of
printer-side lossy fields (see "Open work — IR-printer cleanup"
above; per-parser detail in `bar3_lite.md` § 8). The two sets
overlap and would be closed by the same cleanup pass.

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

- **Bar #3-lite — syntactic round-trip.** *Shipped; audit-ready.*
  See [`bar3_lite.md`](bar3_lite.md) — claim, oracles, results,
  per-parser contract sheet, code-quality posture, deferred items.
  History (audits, retirement, stages) in `worklog_2026_05.md`.
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
