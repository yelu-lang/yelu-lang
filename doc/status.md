# Status — project progress & open work

> **The single tracker for what's unfinished.** Every open task lives here,
> grouped by area, so "what's left?" is answerable in one scan. Rules:
> - **Done → out.** When an item lands, delete it here and write it up in the
>   [worklog](worklog/). Shipped milestones are audited in
>   [`project_overview.md`](project_overview.md) § Project-level milestones.
> - **Rationale → the design docs.** This file is the task list, not the
>   *why*; each item points at its design home when there is one.
> - If a task isn't here, it's either shipped or not yet a task.
>
> Last touched: 2026-07-22.

## Now

- **In flight:** *(nothing active)*
- **Next big rock: ycn concrete syntax** — the gateway to the whole ycn agenda
  (records-as-values, Y17 typing, Y18 entity value are all unwritable until ycn
  has a surface). Design notes:
  [`ycn_concrete_syntax.md`](yelu_cmake_normal/ycn_concrete_syntax.md);
  65-program acceptance corpus already in `test_yelu_lift_lower.ml`.
- **Then (unordered):** a 2nd probe project (spdlog for a real
  `find_package(fmt)` consumer, or nlohmann/json for the fastest clean win —
  *not* gated on anything; fmt already covers 13/15 coverage-map rows), and the
  behavior-level oracle (§ Backlog 2).

**Recently landed** (rolling; full history in the worklog): coverage/dispatch
locks + 5 fixed bugs, the wrong-shaped `~properties=` fix + orphan deletion, the
Tier (b) parser retirement, the doc reorg (layer+facet, then the yc/ycn split).

## Backlog

### 1. ycn + typing — the forward agenda

- **ycn concrete syntax** — see § Now. The gateway.
- **Y17 — a typing pass over the post-retirement IR.** Placement settled:
  typing is **ycn's** job ([`yc_ycn_boundary.md`](yelu_cmake_normal/typing/yc_ycn_boundary.md)).
  Design cluster + reading order in
  [`typed_design.md`](yelu_cmake_normal/typing/typed_design.md). Gating question
  before it starts: how much theory-fragment `expr`-split to bake in first
  (cleanup items 6–7 below).
- **Raw-escape unification** — *de-prioritized 2026-07-21.* It's 2 yc-side
  constructors (`ECmakeRaw`/`ECmakeRawCmd`), does **not** ripple through
  `Yelu_cmake_convert` (raw hits its catch-all — can't cross into ycn today),
  and isn't causing bugs. Fold into ycn's opacity-escape design when ycn
  syntax starts, rather than a standalone yc-side pass.
- **ycn-ward redesigns** (need a value/type model → ycn per the boundary rule):
  records-as-first-class-values, value-default reads (bare `foo` = value),
  dotted globals (`$cmake.version`). Context in
  [`yc_syntax.md`](yelu_cmake/surface/yc_syntax.md) and
  [`value_reads.md`](yelu_cmake_normal/design/value_reads.md).

### 2. Behavior-level oracle (Y16 — "does it scale")

The *lead* forward item after Bar #3-lite (syntactic round-trip) shipped. Its
foundational blocker (cache + `-D` cmd-line input) shipped 2026-06-01. Proves
**runtime semantics** match real cmake, not just syntax. Scope:

- **Configure-time evaluation oracle** — run real cmake on source + yelu-emitted
  output; diff the File API (codemodel-v2 + cache-v2) JSON.
- **Dynamic-dispatch resolution** — walk `include()`/`find_package()` chains at
  configure time to populate the function table the static walker can't see
  (379 generic on z3 / 621 on llvm are runtime-loaded-helper calls).
- **Macro vs function scope** — `yelu_cmake_eval` treats scope opaquely; needs
  explicit modeling once running side-by-side with real cmake.
- **Genex `$<…>` delay** — currently opaque `EString`; must eval at the right
  stage.

Adoption framing (per-rewrite verification chain, not all-or-nothing) is in
[`hybrid_strategy.md`](yelu_cmake/hybrid_strategy.md). Sequels, in order:
real-world z3/llvm/torch rewrites → optimize-and-prove-equivalent → decide macro
elimination (Y15 data).

*Down-payment shipped (2026-07-22):* the **build/symbol/runtime** half — a
`build-equiv` checker (`test/test-build/build_equiv.py`, `make build-equiv`, now
in `make coverage`) builds from reference vs yelu-emitted cmake and compares
artifacts, `nm -D` exported symbols, and runtime stdout/exit, with a control
build for the compiler noise floor. 4 fixtures (`hello`, `static_lib`,
`multi_target`, `compile_defs` — the last a behavioral def-reaches-compiler
check); it already caught the SHARED/MODULE library-type emit bug. The remaining
oracle work above is the *configure-time* File API diff. Next: promote the
tutorial steps + the fmt probe into `test/fixtures/build_equiv/`; supersede or
fix the stale-path `run_build_check.py`.

### 3. IR / harness cleanups

Post-retirement cleanup, in value order (detail was in the old yelu_cmake
status; several pair with Y17):

1. **Split `cmake_op`** into smaller surfaces — largest single fragment.
2. **Generated fragment coverage table** (eval/lift/lower/emit/test per fragment).
3. **Move emit/convert arms next to each fragment** — `yelu_cmake_convert.ml`
   (~1.7k) and `yelu_cmake_emit_debug.ml` (~964) are central registries.
4. **Y17** (§ Backlog 1).
5. **Promote compat surfaces to real theories** (genex first, then find/try/cmake_op subsets) — pairs with Y17.
6. **Categorize `yelu_cmake_normal_*` theories** general vs cmake-specific (`bool`/`int`/`string`/`list`/`store` are reusable).
7. **Split the shared `expr` type** between `yelu_cmake` and `yelu_cmake_normal` (small shared core) — pairs with 6 + Y17.
8. **Parser family split** (`yelu_parse.ml`, ~1.5k `_inner` library) — **defer** until the surface stabilizes.
9. **CLI driver split** (`yelu.ml`, ~600 lines) — **defer** until a 2nd major subcommand.
10. **Escape registry** — track every `ECmakeRaw`/`ECmakeApply`/raw-fallback site (reason, location, coverage); start as markdown, code-level waits for Y17.

**Known IR shape gaps (emit side)** — pinned by `test_yelu_utils_stubs.ml`; each
is `failwith` or accept-and-discard:
STRLESS/STRGREATER conds (only STREQUAL modeled) · `EXCLUDE_FROM_ALL` on
add_executable/library (discarded) · `target_link_libraries` multi-target
(caller splits) · `add_custom_command(TARGET …)` (only OUTPUT-form) ·
`math ~output_format` (discarded; Hexdecimal→decimal) · JSON ops
(`ECmakeStringJson` opaque) · parser sentinel defaults (`out_var`/`cvar_name_of`
`"?"`, `expr_to_int` `0`, `string_uuid`/`cmake_minimum_required`/`project`/`policy_set`
placeholders — vestigial, tighten with Y17).

### 4. Deferred — file-loader / module system + eval residuals

Pick up as cmake-corpus expansion demands. Full picture in
[`module_system.md`](framework/module_system.md) §§ 5, 7.

- **`include_guard()` load-once cache** — ~20 LOC; bites when modules accumulate state.
- **`find_package(X)` real recursion** — today a `Threads` whitelist; real =
  `package_loader` callback + `<Pkg>Config.cmake`/`Find<Pkg>.cmake` search
  (200–400 LOC). The big missing piece for llvm/z3/torch scale; own milestone.
- **`find_program/path/library/file` real `$PATH`/`HINTS`/`PATHS` search** — today always-NOTFOUND stub.
- **`try_compile`/`try_run` real probes** — today always-FALSE stub; needs a compiler runner.
- **`file(READ/WRITE/STRINGS/GLOB)`** — per-subcommand callbacks; `file(READ)` most load-bearing (configure-time templates).
- **`execute_process`** — today result=0/empty; needs subprocess runner callback.
- **`configure_file`** — read template, substitute `${X}`, write.
- **Cache residuals:** `CACHE … FORCE` vs `-D` precedence (`force` bit unhonored) · `$CACHE{VAR}` explicit read (not in IR) · cross-run `CMakeCache.txt` persistence.
- **Env namespace** `set(ENV{FOO})`/`$ENV{FOO}` — no-op in eval; needs I/O callback.
- **Genex as delayed values** — flow as opaque `EString` via `Ycs_eval`.
- Misc: fragment-owned parser composition · `add_subdirectory` binary_dir arg · `PARENT_SCOPE` from subdir (works, untested) · property scope beyond target · bool-literal dual-site (`bool_literal_of_string` + `expect_bool`, Y17 follow-up) · a purer functional function-theory (Y15) · property/random testing + formal proof.

### 5. Retirement tail

- **E2 — delete `src/langs/yelu_legacy/`.** `git rm -r`, revert `src/langs/dune`
  to plain `(include_subdirs unqualified)`, drop the negative-module list. Gated
  on: E1 green soak + Y17 not needing legacy as a reference.

### 6. Known bugs

- **`ylet` alias chain (`EVar→EString` demotion).** `ylet` demotes `EVar n` to
  `EString n`, so a chained alias binds to the literal string, not the prior
  binding. The un-demoted form loops (no cycle detection in `target_arg`/`arg`).
  The `ylet chain` test is **commented out** (`test_yelu_compile.ml:149`); fix
  needs cycle detection. `dune test` is green only because it's skipped.

### 7. Surface polish (Parked — small, independent, any order)

Design rationale in [`yc_syntax.md`](yelu_cmake/surface/yc_syntax.md); this is
the task list.

| item | note |
| --- | --- |
| **B2 — token spans on wellform findings** | Findings carry a name, not a span; LSP scans for the first whole-word match. Located lexer already has what's needed. |
| **LSP hover / semantic tokens** (M1.5b tail) | Parse-error spans shipped; these didn't. |
| **Statement-level error recovery** (M1.4) | Only the LSP needs partial trees; formatter is already fail-safe. Do the light version when the LSP needs it. |
| **Cross-file collect** | LSP sees one file; `function`/`macro` behind `include`/`add_subdirectory` read as unknown. Kills the last open-world false-positive class. |
| **"Did you mean X?"** | Levenshtein vs `command_names ∪ defined_names`; cheap `Unknown_command` add-on. |
| **Manifest `ctor` column** | Populate + test-lock now that `lower` makes the surface↔ctor link verifiable. |
| **Version literal** | `cmake_minimum_required 3.8...3.25` / `find_package Foo '9.0'` — first-class unquoted version token; bare version positional is accepted-and-dropped today. |
| **Per-mode `message_*`** | terse `message_fatal`/`_warning`/`_status` → `~mode=` (curated subset). |
| **`get_property ~mode=Defined`** | trailing `SET`/`DEFINED`/`BRIEF_DOCS`/`FULL_DOCS` flag-as-kwarg-enum; ~30 lines. |
| **shape-4 install_targets records** | `~library={destination=…}` — dotted-label stopgap stands. |
| **function labeled args** | `fun f(~x)` / `f ~x='v'` — needs generated `cmake_parse_arguments`; ties to **Y15**. |
| **`Apply_shadows_primitive` first-class message** | fires only as a buried generic warning; give it its own. |
| **Duplicate single-value field → reject** | Y14 pattern (painpoints #11) for record/dotted-label forms. |
| **cache docstring `~doc:`** + **property cache-semantics test** | small cosmetics. |
| **`string_json` unknown op** | fails at emit rather than as a wellform diagnostic (right error, wrong surface). |
| **"Belief" definition** | shapes the `check` op's output type (flat diagnostics vs a richer fact stream). See `surface_lsp_framework.md` §4. |

### 8. Infra

- **No CI** — Yelu CI: build + test on push (repo has none).
- **Y2** option-combination enumeration (2^n boolean combos for step4+, File API diff).
- **Y5** File API cache-v2 diff (extend the oracle beyond codemodel-v2).
- **Y12** cmake-layer test mirroring (sync cmake PP tests with yelu coverage).

## Numbered backlog (Y-IDs — stable, never renumbered)

Quick reference; each maps to an area above. Done: **Y1, Y9, Y10** (worklog 04).

| ID | title | where / status |
| --- | --- | --- |
| Y2 | Option combination enumeration | § 8 |
| Y3 | Z3 symbolic equivalence | research (needs behavior oracle) |
| Y4 | E-graph investigation | research |
| Y5 | File API cache-v2 diff | § 8 |
| Y6 | Semantics hardest to preserve (genex, policy, find) | design |
| Y7 | Cache-sensitivity annotations | design; ties to Y17 |
| Y8 | Multi-stage core (quote/splice) | research; ties to Y17 |
| Y11 | Policy-aware compiler | design |
| Y13 | Persistent value primitive (`@cached`) | design |
| Y14 | Reserved keyword validation | ⚠️ partial (enum-shadow fatal; broader clashes open) |
| Y15 | Binding feature library | design; ties to function labeled args |
| Y16 | Real-world cmake rewrite | § 2 (behavior oracle / hybrid) |
| Y17 | Types on **ycn** | § 1 |
| Y18 | First-class object value | § 1 (ycn); [`object_value.md`](yelu_cmake_normal/design/object_value.md) |

## Where done work + design rationale live

| kind | file |
| --- | --- |
| finished-work narrative (history) | [`worklog/`](worklog/) |
| shipped-milestone audit + architecture | [`project_overview.md`](project_overview.md) |
| yc surface design & rationale (go-to) | [`yc_syntax.md`](yelu_cmake/surface/yc_syntax.md) |
| surface / formatter / LSP design + shipped pipeline | [`surface_lsp_framework.md`](yelu_cmake/surface/surface_lsp_framework.md) §8 |
| layer triage rule (yc vs ycn) | [`yc_ycn_boundary.md`](yelu_cmake_normal/typing/yc_ycn_boundary.md) |
| Y17 / theory-typing design cluster | [`typed_design.md`](yelu_cmake_normal/typing/typed_design.md) |
| harness design + module guide | [`design.md`](yelu_cmake/ir/design.md) · [`structure.md`](yelu_cmake/ir/structure.md) |
| numbered-backlog descriptions + handoff | [`CLAUDE.md`](../CLAUDE.md) |

> **One tracker.** This file replaced two others (`lang/surface_status.md`,
> retired 2026-07-20; `yelu_cmake/status.md`, folded in 2026-07-21) plus the
> Implementation Queue in `project_overview.md`. A second "living tracker" is
> exactly how open state drifts across files — if you need to track something,
> it belongs *here*, grouped under the right area, not in a new doc.
