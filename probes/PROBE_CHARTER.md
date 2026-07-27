# Probe Charter — translating a new project (handoff-mode agents)

> **Read this first if you are an agent assigned to probe a new project.**
> It defines the mission, the boundaries you must not cross, when to pause for a
> human, and the learn → plan → discuss → execute workflow. The *mechanics*
> (steps, matrix methodology, exemplar) live in [`README.md`](README.md),
> [`cache_matrix.md`](cache_matrix.md), and the worked example
> [`fmt/`](fmt/README.md) — this charter is the *how to behave*, not the *how to*.

## Mission

Take **one** real cmake project and reproduce what fmt did:

1. **Translate** its CMake sources to `.yc` under `probes/<project>/`, mirroring
   the upstream directory layout.
2. **Stand up the matrix** — a per-cell oracle over the project's options
   (option × {ON, OFF} cell groups), comparing **vanilla cmake** vs
   **yelu_cmake** per cell across the channels fmt uses (`CMakeCache.txt`, File
   API codemodel-v2, CTest definitions).
3. **Verify equivalence** and **record every gap** you find.

Your deliverable is a *passing probe for one project*, plus an honest list of
what didn't fit. You are **not** improving the yelu_cmake compiler.

## Project layout & path conventions

Every probe follows the same layout (fmt is the reference instance). A new
project copies this exactly, swapping `<project>` and its options:

| Thing | Convention | fmt instance |
| --- | --- | --- |
| **Source tree** | `vendor/<project>` — a **symlink** to the external checkout at `~/code/contrib/<project>-all/<upstream-dir>`. Read-only, not checked in, may be dirty (see boundaries). | `vendor/fmt → ~/code/contrib/fmt-all/fmt` |
| **Build / matrix output** | `_out/<project>/` — configure/build/worktree scratch. | `_out/fmt/` |
| **Driver config** | `probes/<project>/main.json` = `{ "project", "source_dir": "vendor/<project>", "out_root": "_out/<project>", "options": [ …flippable option names… ] }` | [`fmt/main.json`](fmt/main.json) |
| **`.yc` corpus** | `probes/<project>/<path>.yc` mirroring the upstream layout (`CMakeLists.txt` → `main.yc`; subdir `CMakeLists.txt` → `<subdir>/CMakeLists.yc`; `Foo.cmake` → `foo.yc`, snake_case). | `main.yc`, `test/CMakeLists.yc`, `support/cmake/join_paths.yc` |
| **Corpus-compile gate** | `probes/<project>/dune` — copy fmt's verbatim (globs `*.yc`, runs `yelu compile-corpus .` under `dune test`). Wires the corpus into `dune test` automatically. | [`fmt/dune`](fmt/dune) |
| **README / plan** | `probes/<project>/README.md` (status landing page) + `migration_status.md` (plan → running log). | [`fmt/README.md`](fmt/README.md) |

**Setup step (part of the plan, not silent):** if `vendor/<project>` doesn't
exist, the checkout + symlink is a *setup action to propose to the human* — clone
to `~/code/contrib/<project>-all/<dir>` and `ln -s` it to `vendor/<project>`.
**Pin to the latest stable release tag** (not HEAD): the probe must mirror a
*fixed* upstream so the `.yc` corpus and the matrix baseline don't drift when
upstream moves, and a release tag is what real consumers use. Record the tag +
resolved commit in `probes/<project>/README.md`. Don't invent a path; confirm
the location and tag with the human.

## Hard boundaries (do not cross)

These are the guardrails that make autonomous work safe:

- **Do NOT modify the yelu_cmake infrastructure.** No edits under `src/langs/`,
  `src/runner/`, the drivers, `tool/`, or shared test harnesses. Your writable
  surface is:
  - `probes/<project>/` — the `.yc` corpus, `main.json`, `README.md`,
    `migration_status.md`;
  - a new `test/fixtures/build_equiv/<project>/` fixture (optional, follows
    fmt's shape);
  - a new matrix smoke test modelled on `test_fmt_matrix_smoke.ml` (a *new*
    file — do not edit existing ones).
- **If yelu_cmake needs a change to make your project work, that is a finding,
  not your task.** Record it (see Pause protocol) and route around it or stop —
  do not fix the compiler yourself. Infra fixes are a separate, human-directed
  effort (see the session that closed the cmake-commands emit gaps for why:
  those fixes rippled through ~10 files and the emit oracle).
- **Treat the vendored project tree as read-only.** Never let a yelu emit
  overwrite an upstream `CMakeLists.txt` (documented gotcha — it silently made a
  baseline yelu-vs-yelu). Work on copies / worktrees; check
  `git -C <vendor> status` if a baseline looks suspiciously agreeable.
- **Never install system-wide.** Install-heavy projects (json and most anchor
  candidates ship `install()`/`export()`) must, if you verify install at all,
  target a throwaway per-cell prefix `_out/<project>/<tag>/install` — never a
  bare `cmake --install` (which defaults to `/usr/local`, and cmake has no
  uninstall). Configure-time matrix cells don't install; this bites only if you
  add an install channel. Full rationale + principle:
  [`../doc/cmake/install.md`](../doc/cmake/install.md).
- **Do not push.** Commit to a branch; the human pushes.

## Pause protocol — stop and ask a human when

Autonomy is bounded by these checkpoints. Pause, summarize, and wait:

1. **You hit a yelu_cmake bug** — an emit crash, wrong/After-unbuildable output,
   a command with no `_inner` / no emit arm, a mis-modelled argument. Capture it
   in the form the yc gap registry uses (construct → symptom → root cause →
   repro), and pause. Do **not** patch the compiler.
2. **You reach a milestone worth a human eye** — first cell green, the full
   matrix green, or the corpus-compile gate passing for the whole project. These
   are natural checkpoints; a short "here's where I am, here's what's next"
   beats charging ahead.
3. **A question about the candidate project is unclear** — scope (which
   subdirectories/options are in), an exotic `find_package` web, a helper-macro
   corpus you're unsure how to treat, or anything you'd otherwise *guess*.

When you pause, say plainly: what's done, what's blocked, the exact question, and
your recommended answer. Silence-then-guess is the failure mode this protocol
exists to prevent.

## Workflow: learn → plan → discuss → execute

Do **not** start in goal/autonomous mode. Earn it in stages:

1. **Learn.** Read: this charter, [`README.md`](README.md) (the 5-step
   mechanics + per-project state), [`candidates.md`](candidates.md) (pick /
   confirm the project + its profile), [`cache_matrix.md`](cache_matrix.md) (the
   oracle), and the [`fmt/`](fmt/README.md) exemplar end-to-end. Then read the
   candidate's actual CMake sources — options, subdirectories, `find_package`
   calls, helper macros, generator expressions.
2. **Plan.** Write `probes/<project>/migration_status.md` up front as a *plan*:
   the file inventory, the flippable options (the matrix axes), expected gaps
   (commands/args you suspect aren't modelled), and the order you'll translate.
3. **Discuss.** Bring the plan and your open questions to a human. This is the
   moment to resolve unclarities about the *project* (see Pause protocol #3)
   before committing to autonomous execution. Chat until the plan is unambiguous.
4. **Execute (goal mode).** Now run the loop: translate a file → corpus-compile
   it → add its matrix cell → iterate, pausing per the protocol. Keep
   `migration_status.md` updated as the running log.

## Definition of done

A probe is "complete first pass" (fmt's bar) when:

- Every upstream cmake file has a `.yc` equivalent that **parses, wellforms, and
  emits** (the `probes/<project>/dune` corpus-compile gate passes under
  `dune test`).
- The **matrix is N/N cells green** across the three channels (cache, codemodel,
  ctest) for the project's option combinations.
- `probes/<project>/README.md` records the status, adaptation footprint, and any
  raw-escapes / accepted gaps (like fmt's "3 dynamic-visibility raw escapes — by
  design").
- Every yelu_cmake gap you hit is recorded (registry-style) and handed off — not
  silently worked around.

Optionally (fmt's second bar): a `test/fixtures/build_equiv/<project>/` fixture
for build-level equivalence.

## Pointers

| Need | Doc |
| --- | --- |
| The 5-step mechanics + per-project state | [`README.md`](README.md) |
| Which project + its profile | [`candidates.md`](candidates.md) (spdlog is the suggested next; pairs with fmt via `find_package(fmt)`) |
| The matrix oracle methodology | [`cache_matrix.md`](cache_matrix.md) |
| A complete worked example | [`fmt/README.md`](fmt/README.md), [`fmt/migration_status.md`](fmt/migration_status.md), [`fmt/main.json`](fmt/main.json) |
| Build-level equivalence (optional 2nd bar) | [`../doc/framework/testing.md`](../doc/framework/testing.md) § Level 7, [`../test/fixtures/build_equiv/fmt/`](../test/fixtures/build_equiv/fmt/README.md) |
| Where yelu_cmake gaps get recorded | [`../doc/yelu_cmake/lang_coverage.md`](../doc/yelu_cmake/lang_coverage.md) § Emit / semantic coverage gaps |
| Handling `cmake_policy(...)` | [`../doc/cmake/policy.md`](../doc/cmake/policy.md) — the whole family translates to explicit `policy_*` commands (SET/VERSION/GET/PUSH/POP); no `yc_raw`. Pause only if policy *semantics* (stack eval) matter, which is rare and the matrix uses real cmake anyway. |
| Testing a policy a project enables | [`../doc/cmake/policy.md`](../doc/cmake/policy.md) § Testing a policy — flip the policy NEW↔OLD as a matrix cell; assert vanilla ≡ yelu per state **and** NEW≠OLD (proves it's carried, not silently coerced). Worked CMP0077 example to copy. |
