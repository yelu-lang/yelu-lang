# E1 deadcode audit — prompt

Use this prompt to invite a fresh AI reviewer (Claude, Codex, or a
human reading like one) to audit the E1 deadcode milestone before
we move on to E2 or Y17. Paste the body below into a fresh chat;
attach the repo or the four named commits.

---

You are auditing the **E1 deadcode milestone** of the `yelu`
project, a research compiler that lowers a typed surface DSL
(`yelu_cmake`) to CMake. Through E1, the legacy implementation
(`src/langs/yelu_legacy/`) has been disconnected from all
production and test code paths — it stays on disk for reference
but no longer compiles into anything. Your job is to push back on
that claim where it's overstated, and to surface anything we
should fix before E2 (deletion).

## Scope

Read these four commits as a single unit:

- `c85fb3d` — byte oracle + pair-wise parser oracle retired
  (inline expected strings replace the legacy reference)
- `d0def93` — 22 step binaries + step-shaped tests off legacy
  `Step_common`; `ylet` infinite-loop fix
- `a99d9f7` — test/test-yelu helpers + parser-test structural
  assertions; `test_yelu_check.ml` deleted
- `5b11ae7` — 26 `test/test-runcmake/*` files off
  `Lang_yelu_compile`; `Yelu_cmake_utils` gap-fills;
  `src/langs/dune` excludes 24 `yelu_legacy/` modules from
  `yelu_langs`

Also read:

- `doc/yelu_cmake/status.md` (current state, known IR shape gaps,
  post-retirement cleanup list)
- `doc/yelu_cmake/retirement_plan.md` (E1 section, sequencing
  summary)
- `CLAUDE.md` (project guide; treat as authoritative on
  architecture vocabulary)

## What I want from you

Prioritize **disagreement over agreement.** Tell me where E1 is
weaker than the docs claim, where the gap-fills are likely to
bite, and what's worth fixing before E2 vs what's fine to ship.

Specifically:

1. **Is `yelu_legacy/` truly deadcode?** Verify by reading
   `src/langs/dune`, then grepping the tree for any remaining
   `Lang_yelu_*` or `Yelu_cmake_legacy_bridge` mentions outside
   `src/langs/yelu_legacy/`. Are the comment-only references in
   `src/langs/yelu/yelu_parse.ml` and
   `src/langs/yelu/yelu_cmake_utils.ml` benign or a code smell?
   Should the dune exclusion be expressed differently (e.g.,
   move `yelu_legacy/` to a separate library; `include_subdirs
   no` with explicit listing)?
2. **The gap-fill stubs in `Yelu_cmake_utils`.** Look at the
   commit `5b11ae7` in particular:
   - `ystrless` / `ystrgreater` / `ystrless_equal` /
     `ystrgreater_equal` stubbed to `ECmakeStringEqual` — wrong
     semantics, accepted because the IR doesn't model
     `STRLESS` / `STRGREATER`. Is this a reasonable tradeoff or
     should we have added the IR ctors instead?
   - `yc_string_json_*` collapsed to opaque
     `ECmakeStringJson { op_name = "JSON_op"; args = [json] }`
     ignoring path / sub-op / value. Same question.
   - `yc_math` `~output_format` accepted and discarded; tests
     using `Hexdecimal` get decimal.
   - `add_exe` / `add_lib` `~exclude_from_all` silently dropped.
   - `yc_add_custom_command_target` stubbed via empty-outputs
     `ECmakeAddCustomCommand` — does this risk hiding real
     callers expecting target-form semantics?
3. **The `ylet` runtime bug.** In `d0def93`, `ylet name value`
   now demotes `EVar n → EString n` at bind time. The fix was
   triggered by an infinite recursion in
   `Yelu_cmake_emit_debug.arg` on `ylet "do_test" (ycstr
   "do_test")`. Is this fix correct (it mirrors the legacy
   bridge's `let_value` transformation) or does it paper over a
   deeper substitution-env issue in `emit_debug`? Could it lose
   information for genuine `let x = ${y}` patterns?
4. **The 15 dropped parser test cases.** In `a99d9f7`, 15
   `assert_parses` cases exercising legacy-only parser syntax
   (`option ~msg:`, `~global`, alias commands, custom targets,
   foreach IN, block, extern, set_env, etc.) were deleted
   because the new parser does not accept them. Should some of
   them have been kept as `xfail` markers, or is deletion right
   given the new parser will grow into these features fresh?
5. **`test_yelu_check.ml` deletion.** The whole file went away
   because it tested `Cmake_check` typecheck + `Lang_yelu_wellform`
   on the legacy AST, with no IR equivalent (Y17 is the planned
   replacement). Is this premature? Should we have kept the test
   data and ported the assertions to a TODO/xfail group, or is
   "delete now, rebuild fresh on the IR for Y17" the right call?
6. **The `make cmake-commands` failure handling.** It was
   already broken pre-E1 (`Failure("expected target name")` on
   `a99d9f7`); after E1 it surfaces 12 cmake build-level failures
   (`-PRIVATE_FLAG` rejected by `cc`). The migration treated
   these as pre-existing and moved on. Is that justified? Could
   anything in the migration (e.g., visibility-group ordering,
   `target_link_options` expansion) have changed the cmake text
   in a way that turns a previously-passing build into a failing
   one?
7. **Inline expected strings vs golden files.** The original E1
   plan called for checked-in `.cmake` golden files for the 194
   byte-oracle programs. The implementation uses inline OCaml
   string literals in `test_yelu_compile.ml`. Same byte-equality
   signal — but did this trade make the test file worse to read,
   maintain, or update? Is there a hybrid that's better?
8. **What's missing from `status.md`'s "Known IR shape gaps"?**
   Read the section, then grep `Yelu_cmake_utils.ml` for any
   `failwith` / `?(_)` / `discard` patterns I missed enumerating.
9. **E2 readiness.** Assume E1 holds green for N weeks. Is E2
   (`git rm -r src/langs/yelu_legacy/`) just mechanical, or are
   there hidden dependencies? Specifically: does anything in the
   "Y17 — types on yelu_cmake" plan still need the legacy
   typecheck / wellform as a reference, or can E2 land
   independently?

## Format

Return a structured report with:

- One-line verdict per numbered question (agree / disagree /
  nuance)
- A "things that should be fixed before E2" list (specific
  files + line numbers where relevant)
- A "things that are fine as-is" list with a one-sentence
  justification each
- Anything you noticed outside the questions above that the
  retirement plan / status doc should mention but doesn't

Keep it tight. The goal is decision-quality input, not a
restatement of the codebase. If a question can be answered with
"the docs already cover this," say so and move on.
