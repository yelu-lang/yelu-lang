# Yelu Worklog — May 2026

Implementation history for the `yelu_tiny` composition harness.
For current TODO see `yelu_tiny/status.md`; for project-wide
context see `yelu_project_overview.md`.

---

## yelu_tiny composition harness — overview

`yelu_tiny` is a parallel implementation track that re-shapes the
production `yelu_cmake` AST into a *two-axle* layout:

```
Yelu1 = tiny core + cmake-shaped surfaces  (production-compatible)
Yelu2 = tiny core + idealized theories    (refinement target)
```

Three milestones (bars):

- **Bar #1** — tutorial v1 step1–step12 bridge through tiny and
  configure through real cmake.
- **Bar #2** — every production theory (14) has at least a first
  slice in tiny.
- **Bar #3** — real-world cmake rewrites (e.g. z3, llvm, torch)
  flow through tiny end-to-end.

May 2026 reached **Bar #2** (all 14 theories) and **Bar #1 for the
v1 tutorial** (all 12 root steps).

---

## Prototype and theory expansion (2026-05-01 → 2026-05-03)

Initial harness commit `5f62e21` introduced the tiny core plus
fragments for the core theories. Subsequent commits filled in the
remaining theories so each had a first slice:

| Commit | Slice | What was added |
| --- | --- | --- |
| `5f62e21` | Prototype | `yelu_tiny.ml`, env, eval, first fragments |
| `039fd20` | Custom targets | `ECmakeAddCustomTarget` / `ECmakeAddCustomCommand`, build-check tests |
| `d8d15c8` | Target + install | `target_compile_options`, install constructor surfaces |
| `d200786` | File theory | First slice of file I/O surface |
| `63334b5` | add_library + file | Library target form, more file ops |
| `970d4d2` | 6 more theories | `cmake_op`, `dir`, `test`, `property`, `find`, `try` first slices |

At the end of this run **Bar #2** was reached: all 14 production
theories had a tiny first slice plus a matched theory/surface pair.

---

## ELet + emit substitution (2026-05-03 → 2026-05-04)

The bridge needed a compile-time `let` to translate the `ylet "x" v`
production idiom without leaking through to runtime `set()`.

| Commit | What was added |
| --- | --- |
| `5d9304c` | `ELet { var; value; body }` in tiny core (canonical let-expression) |
| `93b52ae` | **Phase 2a:** emit walks an env of bindings; arg / target_arg consult it. ELet header is dropped from emitted cmake. |
| `42ce435` | **Phase 2b:** surface target-name positions typed `expr` (was `string`). `EVar` / `ETarget` survive into emit so substitution actually fires through target-name positions, not just argument positions. |

After 2b, `ylet "tut" (ytval "Tutorial")` followed by
`add_executable(yvar "tut")` emits `add_executable(Tutorial …)`, not
`add_executable(tut …)` or a stray `set(tut "Tutorial")`.

---

## Module split (2026-05-04)

The single `yelu_tiny_eval` module grew unwieldy. Split into five:

| Commit | What was added |
| --- | --- |
| `6bb0659` | Split `yelu_tiny_eval` into `yelu_tiny_yelu1` / `yelu_tiny_yelu2` / `yelu_tiny_translate` |
| `c52164c` | Drop the eval shim; group env fields by cmake phase (configure-time / build-time / install-time) |
| `eb3826b` | Reorganize tiny tests into `test_yelu_tiny_{bridge,emit,lift_lower,steps,function}` |

Net result: tiny core has one module per concern, env layout matches
cmake's lifecycle phases, tests group by what they prove (bridge,
emit, lift/lower roundtrip, step pipeline, function semantics).

---

## Function theory F2 (2026-05-05 → 2026-05-09)

`cmake function()` is the first construct whose semantics (dynamic
scope with shallow binding) doesn't fall out of straightforward
recursive lowering — it needs an activation record.

| Commit | What was added |
| --- | --- |
| `02ad6c9` | PLAN: rewrite Next Steps with breadth-first tier list (A–G) for steps 6–12; F2 design decisions (call-by-value, dynamic scope, shallow binding, deferred macro/ARGV) |
| `da16f88` | F2: `EDynFunction` / `EApply` (theory) and `ECmakeFunction` / `ECmakeApply` (surface); env.functions; save/bind/eval/restore activation record; 13 dedicated theory tests in `test_yelu_tiny_function.ml` |
| `8cb3731` | Rename theory `EFunction` → `EDynFunction`, reserving the unmarked name for a future lexical-scope sibling. Adopted canonical PL terms (Bobrow & Wegbreit 1973, EOPL) in code comments and docs. |

The two scope wrinkles cmake adds — *reads see the caller's scope*,
*writes are local to the activation frame* — fall out of the
save-and-restore design directly. Side effects on non-variable env
state (targets, tests, install_rules, messages) persist across the
call, matching cmake.

---

## Bar #1 tier list — Tier A through F (2026-05-09 → 2026-05-10)

The PLAN's tier list cleared steps 6–12 breadth-first. Each tier is
the smallest representative slice that gets the step to bridge and
(where applicable) configure through real cmake.

| Tier | Commit | Steps cleared | What was new |
| --- | --- | --- | --- |
| **A** | `86c640d` | step6, step6_ctest | `include()` first slice: theory `EInclude { file; optional }`, env.includes, emit `include("FILE")` / `include("FILE" OPTIONAL)`. |
| **B** | `abb501f` | step7, step7_math | Bridge fix: drop `command_name` short-circuit (latent incompleteness from phase 2b) so `EVar` survives in `yc_function`/`yc_apply` name position. New `let_value` helper maps `ycstr name` to `EString` in let-value position (avoids self-cycle from `ylet "x" (ycstr "x")` and unintended deref from `ylet "x" (ycstr "literal")`). Surface `ECmakeApply` lenient on unknown function (cmake routinely dispatches through `include()`d module functions tiny doesn't simulate); theory `EApply` stays strict. Split `unknown_function_fails` test into lenient surface + strict theory cases. |
| **C** | `1fbf895` | step8_table, step8_math | No new fragment work. step8_table uses `add_custom_command(OUTPUT ...)` (already bridged via `Ytgt_add_custom_command`). TARGET-form sibling remains deferred — no v1 step uses it. |
| **D** | `dd8f0bf` | step9, step10 | No new fragment work. `cpack_basic` and `shared_libs_output_dirs` compose from existing pieces. |
| **E** | `48369f0` | step11_config | `yc_at_var key` slice: theory `EAtVar of string`, surface `ECmakeAtVar`, emit renders `@key@` as a bare line. Eval is a no-op — the literal is substituted later by `configure_package_config_file` over a `.cmake.in` template. |
| **F** | `c7fabd7` | step11, step12 | Package-config family: `EInstallExport` / `EExportExport` / `EConfigurePackageConfigFile` / `EWriteBasicPackageVersionFile` (theory + surface), four matching env install_rule variants, exhaustive install bridge (catch-all removed), emit follows production cmake pretty-printer (FILE / NAMESPACE / NO_SET_AND_CHECK_MACRO / NO_CHECK_REQUIRED_COMPONENTS_MACRO / VERSION / COMPATIBILITY / ARCH_INDEPENDENT). |

After Tier F: **v1 step1–step12 (root) bridge**; step1, 2, 3, 4, 5,
6, 7, 8_table, 10, 12 configure through real cmake. step6_ctest,
step7_math, step8_math, step9, step11, step11_config bridge (separate
cmake tests subsumed by cumulative step10 / step12 fixtures).

### Tier G — deferred

Remaining cleanup: `ECmakeOption` eval through `eval` (currently
ad-hoc match); `ECmakeSetTestsProperties` eval through a new env
namespace; `set_property(TARGET ...)` as the older sibling of
`set_target_properties`. None gate further step coverage.

---

## Patterns worth keeping

- **Bridge fixes were latent incompleteness, not bugs.** Two of three
  Tier B fixes (`command_name` short-circuit; `Yexpr_name { Ns_var }`
  in let-value position) were correct under narrower assumptions
  that earlier steps happened not to exercise. The third (lenient
  `ECmakeApply` on unknown function) was a realism gap — cmake's
  permissive lookup wasn't modeled. See `yelu_tiny/design.md`
  Tier B for the full rationale.

- **Step coverage rarely needed new fragments.** Tiers C and D
  required *only* test additions; the bridge already covered the
  constructs. Tier E added one tiny constructor; Tier F added four.
  This suggests the production theory carving (14 theories) was
  reasonably complete before tiny started; tiny is mostly a
  re-shaping rather than a re-listing.

- **Test infrastructure size.** As of 2026-05-10:
  - `src/langs/yelu_tiny/` — 4,001 lines
  - `test/test-yelu/test_yelu_tiny_*` — 3,442 lines
  - 655 unit tests + 40 cmake-backed configure tests pass.

---

## Linked artifacts

- `doc/yelu_tiny/status.md` — current open work (the slim living tracker).
- `doc/yelu_tiny/design.md` — durable design notes.
- `doc/yelu_tiny/structure.md` — code-anchored module guide.
- `src/langs/yelu_tiny/` — the harness itself.
