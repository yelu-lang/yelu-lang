# Retirement Plan — yelu_cmake (archived)

Retirement of `src/langs/yelu_legacy/` from the production path
is **complete through E1 (2026-05-14)**. This doc was the live
plan during the migration; it now points at the artifacts and
records what remains.

This doc tree (`doc/yelu_cmake/`) is cmake-language-specific.
Future `yelu_shell` / `yelu_c` retirement work would get its own
sibling tree.

## Final state

- `src/langs/yelu/` is the production language. No legacy
  imports anywhere in `src/` or `test/`.
- `src/langs/dune` excludes the 24 `yelu_legacy/` modules from
  the `yelu_langs` library via `(modules :standard \ …)`. The
  modules stay on disk for reference but no longer compile into
  anything that ships.
- Production text generation routes through
  `Yelu_cmake_utils → Yelu_cmake → Yelu_cmake_emit →
  Lang_cmake_pp`. The pair-wise oracle and byte oracle are
  retired; their byte-equality signal lives on as inline
  expected strings (frozen during E1) in
  `test_yelu_compile.ml` and `test_yelu_cmake_parse.ml`.

## History

Detailed retirement journey — Phase 1, Phase 2a, 2c, items A,
B, C, D, E-lite, E-utils, G, F, E1 — lives in
[`../worklog/worklog_2026_05.md`](../worklog/worklog_2026_05.md)
under the "Retirement (May 11 — May 14)" section. Each item was a
PR-sized transition; the worklog captures what landed, in what
commit, and why.

## What remains

### E2 — delete `yelu_legacy/`

Mechanical follow-up. `git rm -r src/langs/yelu_legacy/`, revert
`src/langs/dune` to plain `(include_subdirs unqualified)`, drop
the negative module list. Gated on:

- E1 holding green long enough (soak time TBD)
- Y17 (typecheck reintroduction) not needing legacy as a
  reference

See `status.md` for the current state of these gates.

### Y17 and post-retirement cleanup

Architectural follow-ups (split `cmake_op`, per-fragment convert
/ emit, theory-categorization, split `expr` type, Y17 typing
pass) are tracked in `status.md` under "Open work" and
"Post-retirement cleanup". They are not part of retirement; they
are forward-looking design work on the post-retirement codebase.

## Vocabulary (carried forward)

The project hosts two distinct cmake-domain languages:

- **`yelu_cmake`** — the CMake-command-faithful compatibility
  language (formerly "Yelu1" in early notes). Stable, closest
  to emission, what step files build and what the parser
  produces. Modules: `Yelu_cmake` (core IR + env + eval),
  `Yelu_cmake_eval`, `Yelu_cmake_emit`, `Yelu_cmake_emit_debug`,
  `Yelu_cmake_utils`, `Yelu_parse`, plus per-theory fragments
  `Yelu_cmake_target`, `Yelu_cmake_string`, `Yelu_cmake_file`,
  etc.
- **`yelu_cmake_normal`** — the normalized form of the same
  CMake-domain language (formerly "Yelu2"). Not "more abstract"
  — just a structurally different decomposition that doesn't
  have to mirror CMake's statement / output-variable shape.
  Modules: `Yelu_cmake_normal_eval`, per-theory fragments
  `Yelu_cmake_normal_target`, `Yelu_cmake_normal_string`, etc.
  Conversion lives in `Yelu_cmake_convert` with `to_normal` /
  `from_normal`.

Never refer to either as `yelu_cmake_ir`, `yelu_cmake_surface`,
`yelu_tiny`, or any other representation-tagged name. The two
language names are the project's settled vocabulary.
