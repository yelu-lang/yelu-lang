# Independent audit request — yelu surface-syntax work (last week)

> Hand this to an independent AI tool (Codex / GPT / a fresh Claude) for a
> second-opinion review of the 2026-06-12..21 syntax arc. It asks for a fresh
> audit AND an adversarial verify-or-refute of the prior audit (this repo's
> first pass). Findings reconciliation tracked back in the session that
> produced it. HEAD at time of writing: `24663dd`.

## Your task
Independently audit a week of "syntax" work in the **yelu** project, AND
adversarially verify the findings of a prior audit (listed at the bottom).
Report what you find with evidence. Read-only: do NOT edit project files.

## The project
- Repo: `/home/red/code/research/yelu` (OCaml, dune). HEAD = `24663dd` on `main`.
- yelu is a typed surface language (`.yc`) that compiles to CMake.
- Last week's theme: the `.yc` surface became **labeled-only** — a command
  written in cmake's positional keyword form (`set_property foo APPEND PROPERTY
  X Y`) is now a **fatal compile error**; the labeled form
  (`set_property foo ~append ~property=[X, Y]`) is the sole surface. Visibility
  and entity scopes stay positional as **enum constructors** (`Public`,
  `Target`, `Cache`, …) — that's intentional, not a keyword. Also landed: the
  formatter `fmt` became **pass-through** (the positional→labeled codemod was
  deleted), a unified `parse_and_check` pipeline ("B1") shared by compile/fmt/
  LSP, new wellform checks (Positional_form, Enum_shadow, Unknown_command with
  closed/open-world escalation, Function_def_typo, Apply_shadows_primitive,
  Raw_cmake_escape), an LSP, and a build-time corpus compile gate.
- Scope of commits: `git log --since=2026-06-12 --oneline` (≈60 syntax commits).

## Files in scope
Code:
- `src/langs/yelu/yelu_parse.ml`        (parser; per-command reject guards — grep `from_positional = Some`)
- `src/langs/yelu/yc_wellform.ml`       (all wellform checks)
- `src/langs/yelu/yc_cst_print.ml`      (formatter, now pass-through `pr_arg` walk)
- `src/langs/yelu/yelu_lexer.ml`        (`constr_names` enum-constructor casing)
- `src/langs/yelu/yelu_cmake_emit.ml`   (emit: EVar→`${n}` deref vs EString→literal)
- `src/langs/yelu/yc_primitives.ml`     (`command_names` / `is_known_command` / `reserved_names`)
- `src/langs/yelu/cmake_stdlib_names.ml`(stdlib name cache for open-world unknown-command)
- `src/langs/drivers/yc_driver.ml`      (`parse_and_check` B1 pipeline)
- `src/bin/yelu/yelu.ml`                (`compile` / `compile-corpus` / `fmt` CLI + wellform wiring)
- `src/bin/yelu_lsp/yelu_lsp.ml`        (LSP diagnostics + fail-safe-on-fatal)

Docs:
- `doc/lang/{yc_syntax_critique,casing_design,surface_status,surface_lsp_framework}.md`
- `doc/yelu_cmake/{driver,discovered_cache}.md`
- `doc/worklog/worklog_2026_06.md`, `doc/project_overview.md`, `CLAUDE.md`
- `probes/fmt/{README,migration_status}.md`

## What to look for
1. **Reject consistency / holes**: is the labeled-only reject applied to every
   keyword-bearing command that should have it? Find commands that should reject
   positional but don't (silent mis-parse → keywords dereferenced into garbage),
   or that over-reject a legitimate input.
2. **Silent wrong output**: any input that compiles (exit 0) but emits
   semantically-wrong cmake with no diagnostic — especially mistyped/unsupported
   `~label=` kwargs.
3. **Wellform-check soundness**: false-positives / false-negatives in
   Unknown_command (closed vs open world), Function_def_typo, Enum_shadow
   (case-insensitivity), and whether reference vs declaration sites are handled
   consistently.
4. **fmt correctness**: still round-trips all labeled forms (Kw / Kw_flag /
   Kw_list / nested A_list / A_record / comments)? idempotent? fail-safe on
   fatal wellform? `emit(fmt x) == emit(x)`?
5. **B1 pipeline**: do compile / fmt / LSP / corpus-gate genuinely share one
   path and agree on the fatal set? Any divergence (e.g. ungraceful crash on one
   path but not another)?
6. **Doc accuracy & consistency**: claims vs code; cross-doc contradictions
   (test counts, command lists, "done" claims); stale refs to the retired
   legacy OCaml-DSL emitters (`probes/fmt/{main,test_main,compile_error_test}.ml`
   + `Yelu_emit_main`, deleted in commit `221b5c0`); broken relative links;
   stale dates.

## How to verify (do this, don't just read)
- `dune build` and `dune test` (note: `dune test --force` can hit a transient
  symlink `EEXIST` race — re-run; not a real failure).
- Write probe `.yc` files to `/tmp` and run `dune exec src/bin/yelu/yelu.exe --
  compile <file>` / `-- fmt <file>` / `-- compile-corpus <dir>`.
  **Gotcha: yc statements are `;`-separated** — a probe without `;` is a parse
  error, not the behavior you're testing.
- Distinguish **new** (introduced last week) from **pre-existing** (older parser
  behavior merely exposed by the labeled-only push) — label each finding.

## Output contract
A prioritized findings list. For each: **Severity** (High/Medium/Low),
`file:line`, one-line description, **evidence** (the command you ran + output),
and **New vs Pre-existing**. Then a section that, for EACH prior-audit finding
below, marks it **CONFIRMED / REFUTED / PARTIAL** with your own evidence — and
challenge the "confirmed clean" claims too. End with anything the prior audit
**missed**.

## Prior-audit findings to verify or refute
HIGH
- H1: `link_lib foo ~public=['bar','baz']` → `target_link_libraries(foo PRIVATE )`
  — libraries silently dropped, exit 0 (unsupported `~label=` discarded with no
  diagnostic on target commands).
MEDIUM
- M1: reject guards match `EVar|EString`, so a quoted literal equal to a keyword
  over-rejects: `install_files 'lib' 'DESTINATION'` → fatal Positional_form.
- M2: keyword-bearing commands with no reject AND no labeled form silently
  deref keywords: `find_library mylib NAMES foo` → `find_library(${mylib}
  ${NAMES} ${foo})`; same for find_path/program/file, `find_package COMPONENTS`,
  `add_test NAME … COMMAND …`, set_directory/global/test/source_property.
- M3: `Function_def_typo` fires open-world on `include 'Foo'; my_macro arg;
  (message 'x')` even though `my_macro` could come from the include.
- M4: `check_reserved_names` flags reserved *references* but not *declarations*
  (`add_custom_target := 'x'` allowed), unlike `check_enum_shadow`.
- M5: `yelu compile` prints an OCaml backtrace / exits 2 on an emit failure that
  `compile-corpus` catches cleanly.
- M6 (docs): test count contradicts itself — CLAUDE.md says ~975 and ~994 in
  different places; project_overview ~991; actual `dune test` total = 994.
- M7 (docs): `probes/fmt/migration_status.md` inventory links the deleted `.ml`
  emitters and `.yc` paths that never existed; §1 describes
  `Yelu_emit_main.raw_cmake` in present tense as live, though it's orphaned.
LOW
- L1: `command_names` is missing `add_custom_command` (Apply_shadows can't catch
  it; reserved-name asymmetry).
- L2: bare-name `${}` deref of target names in set_target_properties /
  install_targets (claimed by-design footgun, not active on production paths —
  confirm or refute the "by-design / not active" characterization).
- L3: `probes/fmt/README.md` says main.yc is ~450/~600 lines (actual 297);
  `driver.md:90` names `parse_program_y1` not the post-B1 `parse_program_legacy`.

## Claimed CLEAN (challenge these)
fmt round-trip + idempotence + fail-safe; B1 one-path sharing; emit EVar/EString
convention is by-design not buggy; corpus gate catches positional/parse/emit
regressions; labeled-only parser claims match the docs.
