# Yelu Project Memory

## CMake Reference
- [CMake language implementation details](cmake.md) — AST, PP, utils, test layout
- [CMake misc reference](cmake-misc-reference.md) — official docs, books, discourse links
- [Strings and Targets: cmake internals → yelu design](string-target-design.md)

## Language Design (settled)
- [Core design decisions](yelu_lang_decisions.md) — FP flavor, monomorphic typed lists, zip not ZIP_LISTS

## Project / open design directions
- [Macro elimination as a yelu design direction](project_macro_elimination.md) — defer decision to after R5/Bar #3; R4-b.4 paused (current ECmakeMacro is wrong-but-unused dead code)

## Feedback
- [No eval $(opam env)](feedback_shell_env.md) — dune/opam already on PATH in CC env
- [dune sandbox + promote](feedback_dune_sandbox.md) — alias deps force build order but don't expose files in sandbox; use glob_files + promote instead
- [Latin letters not Greek](feedback_option_letters.md) — use a/b/c/d or 1/2/3/4 for option lists
- [OCaml LSP stale diagnostics](feedback_ocamllsp_hook_interrupt.md) — ignore LSP errors during multi-file refactors; verify with dune build
- [Ask before implementing semantically-loaded constructs](feedback_ask_on_semantic_design.md) — scope, binding, control flow, evaluation order: surface design choices before code (foreach 2026-05-10 miss)

## Quick Reference
- `open Base` shadows `result`, `prefix`, `id`, `append` — rename in patterns
- "cc" = Claude Code
- User reads Chinese; project comments may reference Chinese terms
