# Yelu documentation

This directory is the engineering record for yelu and its first target,
yelu-cmake. The public-facing static site lives separately in [`docs/`](../docs/).

## Start here

- [`status.md`](status.md) — the one tracker for unfinished work.
- [`project_overview.md`](project_overview.md) — architecture, current test
  evidence, and shipped milestones.
- [`manifesto.md`](manifesto.md) — the project thesis and research trajectory.
- [`yelu_cmake/surface/yc_syntax.md`](yelu_cmake/surface/yc_syntax.md) — the
  current `.yc` language surface.
- [`yelu_cmake/surface/yc_command_reference.md`](yelu_cmake/surface/yc_command_reference.md)
  — generated command reference; do not edit by hand.

The current real-project proof point is the
[`fmt` probe](../probes/fmt/README.md): all 11 of fmt's CMake files have `.yc`
equivalents, every file passes the corpus compile gate, and all 24 option cells
match across cache, File API codemodel, and CTest-definition channels. Build,
test, install, Windows, and CUDA behavior remain outside that oracle.

## Layout

```text
doc/
  README.md, status.md, project_overview.md, manifesto.md
  cmake/                    target-language semantics and empirical notes
  framework/                reusable drivers, loaders, caches, and test harness
  yelu_cmake/               yc: the CMake-faithful IR and `.yc` surface
    surface/                syntax, formatter/LSP, generated command reference
    ir/                     composition internals and fidelity tiers
  yelu_cmake_normal/        ycn: normalized language and forward design
    design/                 value/type-model-dependent language proposals
    typing/                 Y17 and theory-composition design
  research/                 research framing and verification directions
  worklog/                  chronological shipped-work record
  archive/                  resolved or superseded write-ups
```

The placement rule is semantic: CMake ground truth goes in `cmake/`; machinery
that another target pack could reuse goes in `framework/`; a construct that
erases faithfully to CMake belongs to `yelu_cmake/`; a construct requiring a
new value or type model belongs to `yelu_cmake_normal/`.

## Framework and verification

| Document | Purpose |
| --- | --- |
| [`framework/driver.md`](framework/driver.md) | Language-driver operations, cross-language pipelines, and compile/wellform/format/LSP contract. |
| [`framework/module_system.md`](framework/module_system.md) | Library/runner split and callback-based include, subdirectory, and package loading. |
| [`framework/discovered_cache.md`](framework/discovered_cache.md) | Build-time discovered-cache/code-generation pattern. |
| [`framework/cmake_vs_normal.md`](framework/cmake_vs_normal.md) | yc/ycn feature and fragment comparison. |
| [`framework/testing.md`](framework/testing.md) | Comparison levels, harness commands, patterns, and limitations. |

## CMake target semantics

| Document | Purpose |
| --- | --- |
| [`cmake/painpoints.md`](cmake/painpoints.md) | CMake failure modes that motivate yelu's design. |
| [`cmake/install.md`](cmake/install.md) | `install()`/prefix path model + **project principle**: always sandbox installs to a per-test-target `_out/<pj>/<tag>/install`, never system-wide. |
| [`cmake/comparison.md`](cmake/comparison.md) | PL model and equivalence levels. |
| [`cmake/cache_semantics.md`](cmake/cache_semantics.md) | Cache and normal-variable namespaces. |
| [`cmake/cache_var_namespacing.md`](cmake/cache_var_namespacing.md) | Reserved/project cache classification used by the oracle. |
| [`cmake/var_reference_semantics.md`](cmake/var_reference_semantics.md) | Bare names, `${...}`, quoting, and nested dereference. |
| [`cmake/scope_and_control_flow.md`](cmake/scope_and_control_flow.md) | Scope frames, functions/macros, blocks, and `PARENT_SCOPE`. |
| [`cmake/policy.md`](cmake/policy.md) | Policy stack and Y11 design options. |
| [`cmake/genex.md`](cmake/genex.md) | Generator-expression gaps and design direction. |
| [`cmake/script.md`](cmake/script.md) | Script mode versus configure mode. |

## yc — CMake-faithful language

| Document | Purpose |
| --- | --- |
| [`yelu_cmake/surface/yc_syntax.md`](yelu_cmake/surface/yc_syntax.md) | Canonical `.yc` syntax and rationale. |
| [`yelu_cmake/surface/casing_design.md`](yelu_cmake/surface/casing_design.md) | Identifier and constructor casing lanes. |
| [`yelu_cmake/surface/surface_lsp_framework.md`](yelu_cmake/surface/surface_lsp_framework.md) | Parser, formatter, diagnostics, LSP, and migration architecture. |
| [`yelu_cmake/surface/yc_command_reference.md`](yelu_cmake/surface/yc_command_reference.md) | Generated 138-command table, freshness-locked by `dune test`. |
| [`yelu_cmake/ir/design.md`](yelu_cmake/ir/design.md) | Theory-composition design of the yc/ycn IR harness. |
| [`yelu_cmake/ir/structure.md`](yelu_cmake/ir/structure.md) | File-level map of `src/langs/yelu/`. |
| [`yelu_cmake/ir/ir_tiers.md`](yelu_cmake/ir/ir_tiers.md) | Typed-to-raw fidelity tiers and fallback strategy. |
| [`yelu_cmake/lang_coverage.md`](yelu_cmake/lang_coverage.md) | CMake test-suite coverage map; current command breadth is generated above. |
| [`yelu_cmake/hybrid_strategy.md`](yelu_cmake/hybrid_strategy.md) | Gradual adoption and CMake-as-assembly strategy. |

## ycn — normalized language and forward agenda

| Document | Purpose |
| --- | --- |
| [`yelu_cmake_normal/coverage.md`](yelu_cmake_normal/coverage.md) | **ycn coverage status** — measured snapshot (16 theories / 74 ctors / 65-test roundtrip lock) + what's not covered + the ycn gap registry. |
| [`yelu_cmake_normal/ycn_concrete_syntax.md`](yelu_cmake_normal/ycn_concrete_syntax.md) | Proposed `.ycn` syntax; the next major implementation milestone. |
| [`yelu_cmake_normal/design/language.md`](yelu_cmake_normal/design/language.md) | Broader core/pack, staging, and type-design directions. |
| [`yelu_cmake_normal/design/object_value.md`](yelu_cmake_normal/design/object_value.md) | Y18 first-class CMake entity value. |
| [`yelu_cmake_normal/design/value_reads.md`](yelu_cmake_normal/design/value_reads.md) | Postponed value-default variable-read design. |
| [`yelu_cmake_normal/typing/yc_ycn_boundary.md`](yelu_cmake_normal/typing/yc_ycn_boundary.md) | Placement rule: faithful erasure in yc, value/type model in ycn. |
| [`yelu_cmake_normal/typing/typed_design.md`](yelu_cmake_normal/typing/typed_design.md) | Y17 type-system design space and reading order. |
| [`yelu_cmake_normal/typing/plan.md`](yelu_cmake_normal/typing/plan.md) | Theory-fragment structural split plan. |
| [`yelu_cmake_normal/typing/boolean_and_theories.md`](yelu_cmake_normal/typing/boolean_and_theories.md) | Boolean/theory composition post-mortem. |
| [`yelu_cmake_normal/typing/extensible_expr_design.md`](yelu_cmake_normal/typing/extensible_expr_design.md) | Extensible-expression design problem. |

## Research, probes, and history

| Document | Purpose |
| --- | --- |
| [`research/research_framing.md`](research/research_framing.md) | Experiment design and contamination-aware evaluation framing. |
| [`research/cmake_equivalence.md`](research/cmake_equivalence.md) | Z3 and e-graph directions for CMake equivalence. |
| [`research/beyond.md`](research/beyond.md) | Speculative multi-pack and AI-language-stack direction (Chinese). |
| [`probes/README.md`](../probes/README.md) | Real-world project probes and their current state. |
| [`probes/cache_matrix.md`](../probes/cache_matrix.md) | Configure-time matrix methodology. |
| [`probes/candidates.md`](../probes/candidates.md) | Candidate projects after fmt. |
| [`worklog/worklog_2026_04.md`](worklog/worklog_2026_04.md) | April implementation history. |
| [`worklog/worklog_2026_05.md`](worklog/worklog_2026_05.md) | IR harness, retirement, and round-trip history. |
| [`worklog/worklog_2026_06.md`](worklog/worklog_2026_06.md) | fmt migration, surface work, audit closure, and parser retirement. |
| [`worklog/syntax_audit_request_2026-06.md`](worklog/syntax_audit_request_2026-06.md) | Archived independent-audit brief. |
| [`worklog/syntax_audit_report_2026-06.md`](worklog/syntax_audit_report_2026-06.md) | Archived audit findings. |
| [`archive/README.md`](archive/README.md) | Index of resolved bugs and superseded parser notes. |

## Document ownership

- Put every unfinished task in [`status.md`](status.md); do not create a second
  tracker.
- Record shipped architecture and evidence in
  [`project_overview.md`](project_overview.md).
- Add chronological completion notes to `worklog/` and resolved one-off designs
  or bug stories to `archive/`.
- Update this file when documents move or their authority changes.
