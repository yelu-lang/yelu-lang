# Worklog — June 2026

## 2026-06-01: Parse-print oracle milestone closed

Full archival record was in `probes/parse_print_oracle.md` (now deleted; this entry captures the closure).

**Result.** STRUCT=0 / FORMAT=0 across 729 real-world cmake files:
tutorial (25/25), fmt (11/11), z3 (108/108), llvm/llvm (596/596).
Full llvm-project (3035 files): 3004 OK, 1 FORMAT, 30 STRUCT
(pre-existing `project()`-printer issues). Every remaining
`generic` Apply call is dynamic-only — resolving runtime
`include()` paths, `${CMAKE_MODULE_PATH}`, macro/function scope,
generator expressions — out of scope for a tree-sitter-only pass.

**Shipped.**
- `tool/cmake_roundtrip/` pipeline: `parse.py` → `print2.exe` → gersemi
- `Cmake_text_parse` library extracted from `print2.ml` into `yelu_langs`
- Two-tier Class A name accounting: corpus-local index (`project_index.exe`)
  + cmake-stdlib `Modules/` index (935 callables)
- Tier 1–4 IR-printer cleanup: 16 commits, per-command typed parsers
  for `list`, `string`, `file`, `execute_process`, `get_property`,
  `set_property` subcommands
- Per-command parser contract sheet (§8 of the audit doc)

**Successor.** Behavior-level oracle (matrix: yc-eval vs real cmake)
tracked in [`status.md`](../yelu_cmake/status.md).

---

## 2026-06-05: fmT probe Phase 1–7 — full project migration

Full record in [`probes/fmt/migration_status.md`](../../probes/fmt/migration_status.md).

**Result.** All 7 phases closed. 24/24 matrix cells matched
(real vs predicted CMakeCache.txt). First `.ye` file in production
(`probes/fmt/join_paths.ye`). Hybrid pilot: `.ml` + `.ye` coexist
in a single manifest.

**Key commits.** Phase 1.1–1.8 (8 helper files `.ml`), Phase 2
(support/ files as whole_file emits), Phase 3–4 (test subdirs),
Phase 5 (cuda-test), Phase 6 (main CMakeLists.txt), Phase 7
(Shape C lockup with `raw_cmake` escape).

---

## 2026-06-06: Driver architecture + tool renaming

- `pipelines.md` + `tool_interface.md` merged → `driver.md`
- Per-language driver modules: `cmake_driver.ml`, `yc_driver.ml`,
  `ycn_driver.ml` + cross-lang utils (`yc_to_cmake.ml`, `cmake_to_yc.ml`,
  `yc_ycn.ml`)
- `tool/cmake_roundtrip/` → `tool/cmake_text/` with per-file renames:
  `parse.py` → `cmake_to_json.py`, `print2.ml` → `cmake_reprint.ml`, etc.
- `[tool-interface]` header annotations on 10 pipeline modules

---

## 2026-06-08: fmT probe Phase 8 — .yc concrete-syntax conversion

Full record in [`probes/fmt/migration_status.md`](../../probes/fmt/migration_status.md).

**Result.** 11/11 `.yc` files compile and pass the matrix oracle.
`yc_apply` in `main.ml` dropped from ~100 → 35. Raw escapes 14 → 3
(remaining 3 are dynamic visibility — by design). All `.yc` files
use the git-worktree hybrid driver; manifest auto-discovers helpers
by naming convention (4-line manifest.json).

**Key changes across ~25 commits:**
- **Parser:** `add_test` keyword form, `set_property` SOURCE/CACHE scopes,
  LPAREN in `p_expr_y1` + `p_cond_atom_y1`, `ver_ge`/`ver_le`, message
  mode keywords, `policy_set` multi-arg, `include_guard` GLOBAL, `:=`
  target accepting `${var}`, `cache` kwargs `~type:`/`~force`, `option`
  help+default, `add_lib_alias`, `enable_language` lang+optional,
  `get_target_property` 3-arg, `configure_file` @ONLY, `add_custom_target`
  keyword sections, `configure_package_config_file` `INSTALL_DESTINATION`,
  `export` TARGETS/NAMESPACE/FILE, `include` literalize module name,
  install keyword forms (TARGETS/FILES/EXPORT/DIRECTORY),
  `cmake_name_of_yelu` raw-fallback mapping, `parent_scope` restore
- **Lexer:** `\"` + `\\` escape in `path_lit`; cmake pp: `quoted()` escapes
  `\`→`\\` and `"`→`\"`
- **IR:** `ECmakeSetPropertySource`, `ECmakeSetPropertyCache`,
  `ECmakeExportTargets`, full install IR (component/artifact_clauses/
  directory), `ECmakeConfigureFile.only`, `ECmakeAddCustomTarget.sources`,
  `custom_target.sources` env type
- **Driver:** auto-discovery by naming convention, git-worktree hybrid
  source, categorized cache diff, log file with stderr capture,
  wellform `~warn` callback, numbered `[yelu][emit][warning][N]` format,
  `manifest.json` simplified to 4 lines
- **Wellform:** `Raw_cmake_escape` carries `text`+`reason`,
  `format_raw_escape` with truncation for multi-line blocks

**Archived phase log** (Phases 0–7) in
[`migration_status.md`](../../probes/fmt/migration_status.md).

---

## 2026-06-01: Cache namespace + `-D` cmd-line input — shipped

Consolidated from the retired `cache_plan.md` (deleted 2026-06-09 once
fully implemented; this is the durable record). Was the lead forward
item ahead of the behavior-level oracle, because cache + `-D` is
foundational — every cmake user touches it, and the behavior-level
oracle cannot ground-truth `-DFOO=BAR` programs without it.

**Design (now realized in code; code is source of truth):**
- `cache_vars : value Map.M(String).t` namespace in `env`
  ([`yelu_cmake.ml`](../../src/langs/yelu/yelu_cmake.ml)), global to the
  configure run (outside the `frames` scope chain, since cmake's cache
  is shared across `add_subdirectory` / `function()` / `block()`).
- Read path: `find_var` consults frames first, `cache_vars` as
  fallback (normal wins). `var_defined` follows the same rule.
- `ECmakeSetCache`: first-write-wins + dual-write to current frame.
- `ECmakeOption`: no-op if name already in cache (honors pre-set/`-D`),
  else write declared default + dual-write.
- `unset(VAR)` clears normal only; `unset(VAR CACHE)` clears both.
- `-D` channel: `populate_cmd_line` + `?cmd_line:(string*string) list`
  on `eval_yelu_cmake_expr` / `eval_yelu_cmake_normal_expr`
  ([`yelu_cmake_convert.ml`](../../src/langs/yelu/yelu_cmake_convert.ml)).
- Spec ground truth: [`../cmake/cache_semantics.md`](../cmake/cache_semantics.md)
  (12 cases verified against cmake 4.3.1).

**Tests (three tiers, all landed):**
- Unit — [`test_yelu_cache.ml`](../../test/test-yelu/test_yelu_cache.ml):
  16 `check_cache_eval` calls covering the 12-case matrix across yc + ycn.
- Dual-eval — `test_yelu_dual_eval.ml` extended with `?cmd_line` cases
  (`-D` populates cache, normal-wins, option suppression, set-CACHE no-op).
- Real-cmake oracle — [`test_yelu_cache_oracle.ml`](../../test/test-runcmake/test_yelu_cache_oracle.ml)
  (the stretch step 10); the broader fmt 24-cell matrix
  (`test_fmt_matrix_smoke.ml`) is a superset cache oracle, 24/24.

**Commits:** `de961b1` (env namespace + cmd-line, steps 1–7),
`3d3d902` (12-row spec verification, step 8), `2350f29` (ycn `ESetCache`
+ dual-eval, steps 6+9), `b46f761` (symmetric yc/ycn verification +
`EUnsetVarCache`).

**Residual gaps** (migrated to `../yelu_cmake/status.md` Deferred):
- `CACHE … FORCE` precedence over `-D` — IR carries `force : bool`
  ([`lang_cmake.ml`](../../src/langs/cmake/lang_cmake.ml) `Set_cache`)
  but yc-eval does not yet honor it.
- `$CACHE{VAR}` explicit-read syntax — not in IR (only a comment at
  `yelu_cmake.ml`); cache fallback covers most uses.
- Cross-run cache persistence (real `CMakeCache.txt` on disk) — the
  `-D` channel is the single-configure proxy.

**Unblocked by this:** the behavior-level oracle (now the lead forward
item), optimizer correctness under known `-D`, community `-D` demos,
and Y17's cache-vs-normal namespace type distinction.

---

## 2026-06-09: src/langs dedup (refactoring_plan P0+P1 — shipped)

Consolidated from the retired `refactoring_plan_2026_06_09.md` (deleted
same day; this is the durable record). The plan audited `src/langs/yelu/`
for duplicated conversion tables and functions that belonged in shared
modules. P0 + P1 (items 1–6) landed in `6a41f96`; the P2 design items
(7–9) moved to `../yelu_cmake/status.md` § "Post-retirement cleanup"
(items 8–10).

**Done (1–6):**
1. **`message_mode` string→enum** — canonical in
   `Yelu_cmake_utils.message_mode_of_string`; `yelu_cmake_emit` now
   references it (its copy deleted). Note: `yelu_cmake_from_emit`'s
   enum→string `message_mode_to_string` is **intentionally** kept
   separate from `Lang_cmake_strings.of_message_mode` — it maps
   `Mm_none → "STATUS"` (IR-reconstruction default) vs the canonical's
   `Mm_none → ""` (emit: no mode keyword). Not a dedup target.
2. **`version_of_string`** — `yelu_cmake_emit` uses
   `Lang_cmake_utils.version_of_string` (which handles `..` ranges,
   e.g. `3.8...3.28 → 3.8`); emit copy deleted.
3. **`visibility_of_expr`** — lifted from the parser into
   `Yelu_cmake_utils` (was `visibility_of_expr_y1`); parser references it.
4. **String escaping** — `Lang_cmake_strings.escape_quoted` / `quoted`
   canonical; `yelu_emit_main.escape` and `lang_cmake_pp.quoted` both
   delegate (the third, `yelu_cmake_emit_debug`, moved to `yelu_legacy`).
5. **`bool_literal_of_string`** — moved to `Yelu_cmake` (next to
   `expect_bool`); `yelu_cmake_from_emit` references it. Full unification
   with eval-side `expect_bool` is a Y17 item.
6. **Enum→string tables** — `library_type_name = of_library_type` and
   `yc_include_guard` uses `of_include_guard_scope`; both now live in
   `Lang_cmake_strings`.

**Deferred design (P2 → status.md cleanup 8–10):** parser family split
(`yelu_parse.ml` ~2.1 k lines — defer until parser stabilizes), CLI
driver split (`yelu.ml`), and an escape registry (markdown-first).

### Source docs retired

The two 2026-06-09 audit docs that fed the above were also deleted
(intentionally, as solved/legacy); their dispositions:

- **`code_audit_2026_06_09.md`** (correctness audit, 5 findings).
  #1–3 (target kwarg payload loss, `--project` override, `merge_flags`)
  fixed in `7cceb89`. #4 (lossy raw fallback via `args_to_cmake_text`)
  — structural fix in `030cfb1` (`ECmakeRawCmd`); the residual is tracked
  in `../yelu_cmake/status.md` § "Architecture TODO: eval-before-emit
  resolve pass". #5 (full `dune test` not green) — LLVM cram /
  include-optional / lexer-escape / cache-snapshot-path sub-issues all
  fixed (`42c9ca2`, `b7a1dd6`, and the `cmake_reserved_vars.tsv` path),
  **except** the `ylet` `EVar→EString` demotion bug, which is open and
  now tracked in status.md § "Known bug: `ylet` alias chain" (test
  skipped in `9041558`).
- **`code_quality_review_2026_06_09.md`** (maintainability review) — fully
  consumed: it produced `refactoring_plan_2026_06_09.md`, itself retired
  above (P0/P1 shipped in `6a41f96`, P2 → status.md cleanup 8–10).

## 2026-06-13: Handoff — critique #2 `~`-half (flags + value-labels) + install_targets fix

One-time resume note. This session executed critique #2's `~`-modifier half
(see [doc/lang/yc_syntax_critique.md](../lang/yc_syntax_critique.md) §2 and
[doc/lang/casing_design.md](../lang/casing_design.md)) and uncovered + fixed a
pre-existing `install_targets` correctness bug.

### Shipped (all committed, all on origin/main as of `a34a26e`)

**The `~`-modifier surface** — every cmake keyword-arg is an argument label:
- **Boolean flags** (value-less labels), per-command + command-aware (a bare
  `GLOBAL` is the `include_guard` flag, but `${GLOBAL}` a variable elsewhere):
  `~parent_scope`, `include_guard ~global`, `install_directory ~optional`,
  `find_package ~required`. Mechanism: `command_flags` table + `pr_arg_flagged`
  in [yc_cst_print.ml](../../src/langs/yelu/yc_cst_print.ml); parser reads the
  `~flag` boolean kwarg (positional-detected flags also taught the kwarg).
- **Separator `:` → `=`** (`c21aa41`): accept both, canonicalize to `=`. `=`
  reads as binding, `:` as ascription. Corpus's ~22 `~key:` migrated.
- **Value-labels (shape 1)** for the install family: `install_directory`,
  `install_files`, `install_export` → `~destination=`/`~component=`/
  `~namespace=`/`~file=`. Mechanism: `command_value_labels` table +
  `pr_cmd_args` (look-ahead printer; a value-keyword consumes its following
  positional). Order-independence verified (labels in any order → identical
  cmake — cmake's keyword-ordering pain compiled away). Corpus shape-1 complete.

**install_targets correctness fix (shape 4)** — surfaced that the command was
already deeply lossy, independent of surface work:
- `dbc0b6a` — printer was dropping `COMPONENT` (bug 2). Now emits it, top-level
  options before per-kind clauses (cmake grammar order).
- `a34a26e` — nested-clause parse (bug 1). Flat `split_by_keywords` couldn't
  handle `DESTINATION`'s dual role (top-level AND per-artifact); replaced with a
  **two-level split** (level 1 at artifact KINDs, level 2 at options) + dotted-
  label kwarg reading (`~library.destination=` → `(LIBRARY, value)`). Positional
  and dotted forms emit identically. **Verified with real `cmake --install`**:
  LIBRARY→libdir, ARCHIVE→archdir.
- `fefe80e` — foundation: lexer `DOT` token + dotted kwarg keys.

**cmake ground truth** (`175a524`, painpoints.md §11): probed
`install(TARGETS)` repeated-keyword semantics — duplicate scalar field =
silent last-wins; split fields across same-kind groups = accumulate.

### Remaining — resume points

Within install_targets (a), in priority order:
1. **Formatter canonicalization** positional `LIBRARY DESTINATION v` →
   `~library.destination=v`, then re-fmt corpus to the dotted surface. Sugar,
   not correctness — the corpus compiles correctly either way today (it's still
   positional). Needs a dedicated install_targets CST walk (re-do the two-level
   recognition on `Cst.arg`).
2. **Duplicate single-value field → reject** (Y14 pattern, painpoints.md §11).
   Needs the wellform/error channel. List fields stay one list value.
3. **`$INSTALL_FILE_SET` dynamic clause** — still dropped (a `FILE_SET`-in-a-
   variable). **Tier-3**: needs a raw-passthrough slot in the install IR. The
   one item needing an IR design decision, not more of the same.

Broader `~`-half (other shapes), tracked in critique §2:
- **Shape 3** — `set_target_properties PROPERTY` → `~properties={k=v}` map
  literal (new `{…}` surface form). 6× in corpus.
- **Shape 2** — `add_custom_command COMMAND` repeated-list, AND blocked on the
  COMMAND_EXPAND_LISTS IR-gap (parsed but dropped on emit — same blindness class
  as install_targets; matrix can't see build-time flags).
- **IR-gap flags** (do NOT cosmetically migrate): COMMAND_EXPAND_LISTS, WIN32,
  MACOSX_BUNDLE, EXCLUDE_FROM_ALL — dropped on emit; need IR fields first.

Two orthogonal pre-existing yc gaps noticed (not on the critique path):
`SHARED` not in the lib-type enum set (lexes as `${SHARED}` var); install_targets
literal target names emit as `${name}` instead of bare.

### Verify on resume
- `dune test` (full suite, was green) · `dune build @runtest`
- `dune exec src/bin/yelu/yelu.exe -- matrix probes/fmt` (24/24, configure-blind)
- emit-bridge + corpus tests in `test/test-yelu/test_yc_cst_bridge.ml`
  (`flags`, `separator`, `value_labels`, `install_targets`)
- For install/build-stage checks: `cmake --install <build> --prefix <tmp>` only
  (never bare — see [.claude/memory/feedback_cmake_install_prefix.md](../../.claude/memory/feedback_cmake_install_prefix.md)).

---

## 2026-06-13/14: per-command syntax — property family unified + `:=` low-priority command-call sugar

Single multi-step session, ~20 source files. Four logical chunks, all
emit byte-equality preserved (oracle stays green).

**1. set_property: 4-ctor IR → 1, plus all surface lanes.**

- IR refactor: `ECmakeSetProperty` / `ECmakeSetPropertySource` /
  `ECmakeSetPropertyCache` / `ECmakeSetGlobalProperty` collapsed into
  one unified `ECmakeSetProperty { scope : set_property_scope; append;
  append_string; properties }` mirroring `Lang_cmake.Set_property` 1:1.
  `set_property_scope` is a 7-variant sum (Global/Directory/Target/
  Source/Install/Test/Cache). Compatibility helpers
  (`yc_set_property` / `yc_set_property_source` / `yc_set_property_cache`
  / `yc_set_global_property`) kept stable so the 21+ external test
  callers don't break.
- `cache_entry = Cache_entry` placeholder lifted to `cache_entry =
  string` in `Lang_cmake` — CACHE-scope entry names (e.g. `FOO` in
  `set_property(CACHE FOO …)`) were being silently dropped in emit;
  now flow through (printer + text-parser + yc emit all wired).
- `append_string : bool` field added (was missing from the yc IR
  entirely; cmake AST had it). Parser + emit + per-command flag table.
- Lane B flags: `~append` / `~append_string` via `command_flags
  set_property` table.
- Lane C shape-3 value-list label: `~property=[name, vals...]` via the
  new `command_value_list_labels` table + `pr_cmd_args` look-ahead
  printer that consumes the keyword + all trailing positionals. Mirror
  parser support: `~property` kwarg recovered via `filter_map` (with
  source-order preservation — kwargs accumulator gets a `List.rev_map`
  for list-valued kwargs to survive the final `List.rev`).

**2. Pos3 entity prototype.**

- Parser-local `cmake_entity` value: `Ent_target | Ent_source | Ent_cache
  | Ent_test | Ent_install | Ent_directory of expr option | Ent_global
  | Ent_variable`. Two lowering helpers (`entity_to_sps`, `entity_to_gps`).
  `Yelu_lexer.constr_names` slice 3 adds `GLOBAL`/`DIRECTORY`/`SOURCE`/
  `INSTALL`/`TEST`/`CACHE` so the leading-cap form (`Cache FOO`) flows
  through the existing constr_names canonicalization. TARGET stays on
  its existing reserved-word path. Replaces the ad-hoc `is_source` /
  `is_cache` / `is_other_scope` predicates with one entity-driven
  dispatch.
- set_property's parser branch rewritten as: read entity → build scope
  → split body → collect properties. Folds extra same-kind positionals
  from the body head into the scope's name list (multi-target case).

**3. get_property: same unification + first typed parser branch.**

- `ECmakeGetProperty` collapsed from TARGET-only `{ var; target;
  property; set_form : bool }` to unified `{ var; scope :
  get_property_scope; property; mode : get_property_mode }`. Mode is a
  5-variant enum (Value default / Set / Defined / Brief_docs /
  Full_docs) replacing the bool. Scope is 8-variant (same as set_property
  + the unique VARIABLE scope).
- Parser dispatch added for `"get_property"` (was missing — every
  get_property in source text fell to yc_raw pre-session). Pos3 entity
  drives scope. `~property=NAME` (Lane C shape-1) + `~mode=Set` kwargs.
  Legacy positional `PROPERTY NAME` + trailing mode flag still
  accepted.
- `constr_names` slice 4: VARIABLE + SET / DEFINED / BRIEF_DOCS /
  FULL_DOCS. The mode-flag-as-kwarg-enum canonicalization (positional
  `DEFINED` → `~mode=Defined`) is **not** in this slice — needs a new
  per-command rewriter; tracked as future micro-slice in
  `yc_cst_print.ml`'s `command_value_labels` comment.

**4. `:=` low-priority command-call expression.**

User framing: `:=` should be low priority so its RHS parses as a
complete expression — including command calls — without inventing
parens. Implemented in both parsers:

- CST (`yc_cst_parse.ml`): new `S_assign_call of { cache; name;
  cmd_name; cmd_args }` CST variant. `p_assign` peeks the post-`:=`
  IDENT; if it's in `Yc_primitives.command_names` and followed by
  command-shape tokens (TILDE kwarg or another positional), parse via
  `p_args` and emit `S_assign_call`. Bare `var := foo` falls through
  to the legacy value-list path.
- Legacy (`yelu_parse.ml`): `p_assign_y1` extended with same
  detection; dispatches to the matching family `_inner` via three
  forward refs (`collect_command_args_fwd` / `dispatch_command_fwd` /
  `fallback_to_raw_fwd`) populated at file bottom. The dispatcher uses
  prefix routing for homogeneous families (`string_` / `list_` /
  `path_` / `file_`) and a "try-each, drop the `ECmakeRawCmd`
  fallback" walk for the per-command families — needed because
  `p_target_command_y1_inner` and a couple of others have a catch-all
  raw fallback that would otherwise shadow the real handler.
- Lowering: `S_assign_call` desugars to `cmd_name + cmd_args +
  Kw("out", A_name name)` and routes through the regular command
  lowerer. `out` is the standard ~out kwarg the typed handlers already
  read via `out_var_y1`.
- Surface examples that now work end-to-end:

  ```text
  var   := get_property Target foo ~property=NAME
  var   := get_property Cache FOO ~property=STRINGS ~mode=Defined
  upper := string_toupper 'hello'
  joined := list_join MYLIST ','
  ```

- `get_property` added to `Yc_primitives.command_names` (was missing
  — surfaced by the `is_known_command "get_property"` check in this
  session's CST sugar).

**Y18 recorded — first-class object value.** The Pos3 prototype is
parser-local. Open questions for promoting to a real value class are
in [`../lang/object_value_design.md`](../lang/object_value_design.md):
operations per kind (`target_foo.set_property(…)`), value flow
(let-bind / args / iterands), eval semantics (forward refs, lazy vs
eager), wellform integration, yc vs ycn placement, multi-entity calls.
The CST `DOT` token (added in `fefe80e`) is already the syntactic
groundwork for the future object-method `entity.method(args)` form.

**Verification.**
- `dune runtest --force` — **935 tests / 0 failures** throughout.
- Byte-equality oracle (`covered=194`) stays green — every IR
  refactor preserved emit byte-identical.
- tm-grammar regenerated and committed; co-truth lock satisfied.

**Files touched.** Production: `lang_cmake.ml`, `lang_cmake_pp.ml`,
`cmake_text_parse.ml`, `yelu_cmake_property.ml` (fragment),
`yelu_cmake_emit.ml`, `yelu_cmake_convert.ml`, `yelu_cmake_utils.ml`,
`yelu_lexer.ml`, `yc_primitives.ml`, `yc_cst.ml`, `yc_cst_parse.ml`,
`yc_cst_print.ml`, `yc_cst_lower.ml`, `yelu_parse.ml`. Legacy:
`yelu_cmake_legacy_bridge.ml`, `yelu_cmake_emit_debug.ml`. Tests:
`test_yc_cst_bridge.ml` (+25 assertions across all four chunks).
Docs: new `doc/lang/object_value_design.md`,
`doc/lang/yc_syntax_critique.md` (APPEND row updated to shipped),
this worklog entry, CLAUDE.md (Y18 + test count 923→935).

## 2026-06-19: no-ALL_CAPS surface pass complete (the `~`-half)

Closure record for critique #2's `~`-modifier half — turning cmake's SHOUTY
positional keyword args into a uniform labeled surface. Design rationale stays
in [`../lang/yc_syntax_critique.md`](../lang/yc_syntax_critique.md); this
archives the shipped arc. Throughout: emit byte-invariant (fmt matrix 24/24),
verified by the emit-bridge + matrix; per-command, accept-both-then-canonicalize.

**The surface, end state.** Every command in `probes/fmt/main.yc` now reads as
`~flag` / `~label=value` / `~label=[list]` / `~properties={record}`, or is an
explicit `yc_raw` escape. cmake keyword args became argument labels.

**Arc (commits):**
- **Casing lanes** (earlier sessions): enum constructors leading-cap
  (`Public`/`Static`/`Name_we`), property scopes (`Global`/`Cache`/`Source`/…),
  Y14 reserved-word reject. `$foo` brace-elision sugar; single-quote canonical.
- **Flags** (value-less labels): `~parent_scope` (`eacb906`), `include_guard
  ~global` (`d74bd90`), `install_directory ~optional` (`bcefe40`),
  `find_package ~required` (`8c03d01`), `set_property ~append`/`~append_string`.
  Mechanism: `command_flags` table + command-aware formatter rewrite (a bare
  `GLOBAL` is the include_guard flag, but `${GLOBAL}` a var is left alone).
- **Separator `:`→`=`** (`c21aa41`) — accept-both, canonicalize to `=`.
- **Value-labels (shape 1):** install_directory pilot (`0e99359`),
  install_files/export (`37ec8be`), get_property, set_property `~property=[…]`.
  `command_value_labels` + look-ahead `pr_cmd_args`; order-independence verified.
- **install_targets correctness fix** — it was *lossy* (COMPONENT dropped,
  nested clauses collapsed): nested-clause two-level-split parse (`a34a26e`),
  COMPONENT printer fix, entity names literal-not-derefed (`f1296a4`), real
  `cmake --install` verified. Then the guarded dotted-label formatter (`49e32fa`).
- **Recursive value grammar** (shapes 2 & 3): core `A_list`/`A_record` +
  `EList`/`ERecord` (`7ca8c5d`); shape-2 `~command`/`~commands` by arity
  (`25f9e19`, retired the multi-COMMAND guard); shape-3
  `set_target_properties ~properties={k=v}` (`a87f9a8`). Comma-list form
  (`5020f6c`).
- **execute_process** (`838fe80` + `25f9e19`) and **add_custom_command/target**
  (`b101aba`) on the shared `pr_command_groups_args` walk.
- **COMMAND_EXPAND_LISTS IR gap** (`591f261`) — was parsed but silently dropped
  on emit (a `string list` placeholder the printer discarded); threaded end to
  end as a real `bool` across the cmake AST + pp + reverse-parser + yc IR.
- **Corpus macro-escaped** (`7cff140`): the two un-labelable lines —
  `target_sources … FILE_SET` (a nested clause, was *actively mis-parsing*) and
  `install_targets … $INSTALL_FILE_SET` (a metaprogramming splice) — became
  `yc_raw`. The corpus is now fully labeled-or-raw.

**Empirical cmake ground truth recorded:** painpoint #11 (repeated-keyword
last-wins vs accumulate, install(TARGETS) probed against cmake 4.3.1).

**Convergence worth noting:** the only two lines the labeled surface *couldn't*
express turned out to be exactly the metaprogramming/nested corners that belong
in the raw bucket — the design's edges line up with cmake's genuinely-dynamic
ones. Next phase (labeled-only — remove positional parsing) tracked in
[`../lang/surface_status.md`](../lang/surface_status.md) § Open decisions.

## 2026-06-19: Step 2 — labeled-only surface (positional reject) + deferred commands cleared

The labeled-only pass. A command written in cmake's positional keyword form
(`set_property foo APPEND PROPERTY X Y`) is now a **fatal compile error**; the
`~label=` form is the sole surface. Policy = **reject** (not raw fallback):
chosen because reject needs no faithful-raw reconstruction.

**Mechanism.** `ECmakeRawCmd` gained `from_positional : string option`; a
command's parser tags it when it sees a positional cmake keyword, and
`Yc_wellform.check_raw_tainted` turns the tag into a fatal `Positional_form`
error (alongside `Enum_shadow`).

**Per-family rollout** (one commit each): pilot `install_targets` (`83fd8ab`);
target — `add_custom_command/target` (`6677d4c`); install —
`install_files/export/directory` (`b20f1cd`); property —
`set_property/get_property/set_target_properties` (`3cb4893`); cmake_op —
`execute_process` (`e39311c`). Entity/visibility enums
(`Public`/`Target`/`Cache`/…) stay positional — they are the enum-constructor
surface, not keywords.

**Deferred commands then cleared** (`b3f40ec`, `41a51dc`, `82ba8a8`): each got a
label — `set_source_files_properties ~properties={…}`, `enable_language
~optional`, `cmake_minimum_required` **bare** (VERSION dropped), `export
~targets=[…]/~namespace=/~file=`, `configure_package_config_file
~install_destination=` (input/output first), `message ~mode=Fatal_error`.
`include_guard GLOBAL` needed nothing (`Global` was already an enum
constructor). **message deliberately did NOT become an enum constructor** —
promoting STATUS/DEBUG/WARNING/… into `constr_names` would globally reserve
common var names (Y14-fatal), breaking the casing "small-closed-set" rule; the
`~mode=` label sidesteps it (and a quoted `'STATUS report'` stays text).

**Phase-4 cleanup.** Parser (`1c0ffed`): dropped vestigial `split_by_keywords`
calls in the rejected property commands (the helper stays — deferred-then-`set_source_files_properties`/`export`/`configure_package_config_file` and the
test family still use it). Formatter (`5c9b92d`): **`fmt` is now pass-through** —
deleted the positional→labeled codemod (`command_flags`/`command_value_labels`/
`command_value_list_labels` + `pr_command_groups_args`/
`pr_set_target_properties_args`, −214/+21 LOC). Decision: `fmt` blesses good
code only; a positional→labeled migration belongs in a separate 2to3-style
tool, not the formatter.

**Oracle blind-spot lesson.** The reject fires only under the fatal `compile_yc`
path, so the emit-bridge + matrix oracles can't see it directly. The matrix
*did* catch corpus regressions — because the **discovered helpers**
(`probes/fmt/test/*/CMakeLists.yc`) compile through `compile_yc`, while
`compile main.yc` alone was byte-identical and hid them. Each command's reject
has its own `test_yc_wellform` case + a labeled round-trip in
`test_yc_cst_bridge`. Every corpus migration verified byte-identical emit; one
latent bug fixed along the way (cuda-test `set_target_properties` was silently
dropped — the code split on `PROPERTY`, not the `PROPERTIES` it was written
with). Throughout: `dune test` green, matrix 24/24, fmt idempotent + emit-stable.

## 2026-06-20/21: wellform → LSP → fmt fail-safe → unified pipeline → cmake-stdlib cache

Three closely-linked threads on the macOS side, all landing as commits
through `c88bef7`:

**Wellform expanded into the diagnostic engine.** Six checks now run via
`Yc_wellform.check_all` (on `expr`) and `Yc_wellform.check_cst` (on the
CST). New variants this period: `Unknown_command { name; closed_world }`
with the closed-world rule (file has no `include` / `find_package` /
`add_subdirectory` / `cmake_call|cmake_eval` / dynamic fun-name → unknown
must be a typo, fatal; otherwise warning); `Function_def_typo { name }`
as a CST shape check for `IDENT args (block)` adjacent to a standalone
`S_block` — only valid as a function definition, fatal regardless of
open/closed world. The CLI / fmt / LSP / corpus-gate fatality split is
captured once in `Yc_driver.fatal_wellform_message`; per-check semantics
+ surfacing contract in
[`../lang/surface_lsp_framework.md`](../lang/surface_lsp_framework.md)
§7.5 and [`../yelu_cmake/driver.md`](../yelu_cmake/driver.md) §6.5.

**fmt is now fail-safe on fatal wellform.** Was parse-then-print only; a
closed-world typo was happily prettified into a clean-looking unknown
command, hiding the bug. Now `Yc_driver.format` lowers CST → expr,
runs wellform, refuses on fatal findings. Both `yelu fmt` (CLI) and the
LSP `textDocument/formatting` request inherit the gate — typo stays
visible as a diagnostic, never cosmetically washed over.

**LSP publishes wellform diagnostics.** Was parse-only. Each finding
maps to an LSP `Diagnostic` with severity (Error / Warning /
Information) and a span resolved by whole-word scan of the source —
heuristic but practical until findings carry token spans natively. The
LSP now matches the diagnostic content of `yelu compile` exactly.

**cmake-stdlib name cache (Plan C — the discovered-cache pattern).**
[`../yelu_cmake/discovered_cache.md`](../yelu_cmake/discovered_cache.md)
generalizes the recipe: discover → commit TSV with version fingerprint
→ dune codegen embeds into the binary → on-demand validity (option (d),
no automatic check). First instance is `Cmake_stdlib_names`
(`tool/cmake_text/cmake_stdlib_names.tsv`, ~80 hand-curated names + C-side
builtins). Three-tier lookup in `check_unknown_command`: typed
primitives ∪ in-file decls ∪ stdlib. Silences the corpus's
`cmake_parse_arguments` / `check_language` / `cuda_add_executable`
warnings; restores closed-world fatal escalation in the corpus gate
(was silenced 2026-06-14 to keep it green). Pattern table parked in the
doc for the next discovery need (`cmake_policies`, `cmake_genex_ops`,
the runtime-loaded `cmake_reserved_vars`).

**B1 — unified `parse_and_check` pipeline.** Was the structural fix that
let everything else compose. Each of compile / fmt / LSP / corpus-gate
had its own "parse, then check" orchestration with subtle drift. Now
`Yc_driver.parse_and_check : string → ({expr; cst; findings}, string)
Result.t` is the single site; consumers are 5-10 lines each. Side
effect: compile + corpus-gate moved off the legacy direct parser
(`Yelu_parse.parse_program_y1`, now renamed `parse_program_legacy`),
which means they automatically gained `check_cst` findings — Function_def_typo
catches typos in compile too now. Caught a real `funs` → `fun` typo on
[`probes/fmt/main.yc`](../../probes/fmt/main.yc) line 13 as a side
effect of the rollout, fixed in the same commit. Plan continuation
(soak the emit-bridge oracle, then delete the legacy parser entirely) in
[`../lang/surface_status.md`](../lang/surface_status.md) Tier (b).

**Editor tooling (the macOS side).** `yelu-lsp` exe builds against the
yojson-3 `linol` fork (pinned via `opam pin git+https://github.com/arbipher/linol#main`);
VS Code extension at [`../../editors/vscode/yc/`](../../editors/vscode/yc/);
symlink install into `~/.vscode/extensions/yelu-lang.yc-0.0.1/` is the
recommended development flow. Reload Window picks up LSP rebuilds.

**Docs reorganized to reflect the new shape:**
- [`../project_overview.md`](../project_overview.md) — full refresh
  (was stale since 2026-06-03; covers surface passes, LSP, wellform,
  property unification, Pos3, command-call sugar, corpus gate).
- [`../yelu_cmake/driver.md`](../yelu_cmake/driver.md) §6.5 — the
  compile/wellform/format/LSP contract that any new pack inherits.
- [`../lang/surface_lsp_framework.md`](../lang/surface_lsp_framework.md)
  §7.5 — full wellform check table + open/closed-world rule + worked
  examples.
- [`../yelu_cmake/discovered_cache.md`](../yelu_cmake/discovered_cache.md)
  — the driver-level pattern doc.
- [`../lang/surface_status.md`](../lang/surface_status.md) — Tier (b)
  active with 7-step plan + status; legacy parser retirement is the
  forcing function.

Throughout: `dune test` green (994/994), corpus gate green (11/11), fmt
matrix 24/24, emit-bridge oracle covered=194 byte-identical between
legacy and CST paths.

## 2026-06-25: two-pass syntax audit + reconciliation + easy fixes

Audited the whole 2026-06-12..21 syntax arc (labeled-only Step 2, fmt
pass-through, B1 unified pipeline, wellform checks, LSP). **Two independent
passes:** an internal 3-agent fan-out (parser/wellform · formatter/pipeline/emit
· docs) and an external AI re-audit. Both artifacts archived here:
[`syntax_audit_request_2026-06.md`](syntax_audit_request_2026-06.md) (the
self-contained prompt) and
[`syntax_audit_report_2026-06.md`](syntax_audit_report_2026-06.md) (the external
tool's findings — it ran build/test/probes independently).

**Reconciliation.** Strong agreement, **zero refutations of any real finding**.
The core work was upheld clean: fmt round-trip + idempotence + fail-safe, the
B1 one-path sharing (compile/fmt/LSP/corpus-gate all via
`Yc_driver.parse_and_check`), the corpus gate's detection, and that the
labeled-only parser claims match the docs. Two findings sharpened:
- **Target-name deref upgraded Low → HIGH.** `set_target_properties fmt …`
  (main.yc:139, not gated) emits `set_target_properties(${fmt} …)` — `${fmt}` is
  variable-expansion, so the property is set on **nothing**. cmake configure
  exits 0 (empty target list = no-op) and the **matrix is blind** to it (target
  properties aren't cache vars), so 24/24 is green while the corpus ships wrong
  cmake. Our first pass had mis-called this "by-design / not active"; the
  external pass + a tie-break against the corpus corrected it.
- **Doc test-count drift** confirmed across 5 sources; actual = 994.

**Easy, deref-independent fixes landed** (all: dune test green, gate 11/11,
matrix 24/24):
- doc drift → 994 everywhere + README/driver stale refs (`7598394`)
- labeled-only reject guards match bare `EVar` only — quoted-keyword literals no
  longer false-positive (`63b3728`)
- `yelu compile` reports emit failures cleanly instead of an OCaml backtrace
  (`0bb63c4`)
- `add_custom_command` registered in `command_names` — closes the apply-shadow
  gap; grammar re-promoted (`d60190f`)

**(1) target-name deref — FIXED at the root (`a57bcf4`), honest emit.** The fix
wasn't the shallow per-command coercion patch; the discussion (with the user)
traced it to a deeper inconsistency: the emitter rendered an unresolved bare
`EVar name` as `${name}`, injecting a read that yc's own spec
([`../cmake/var_reference_semantics.md`](../cmake/var_reference_semantics.md))
forbids — *bare `foo` is the literal "foo"; you must write `$foo` to read.*
Made unresolved `EVar` a literal in `arg` + `target_arg` (the other two
renderers already were). All four now agree; only `EVarLookup` derefs. This
**eliminates the slot-dependent deref** — property/install/test target slots are
correct with no per-command coercion (the `target_first_arg_commands` list is now
wellform-only). Corpus emit diff: 7 changes, all fixes (target names,
cmake_parse_arguments prefix, output-vars, keyword args, metaprogramming
keywords), **zero regressions** — the corpus already wrote every real read as
`$foo`. Byte oracle intact (193/193, covered=194), matrix 24/24 (now emitting
*correct* literal target names), gate 11/11. A **matrix supplement** (file-api /
target-property diff) is still worth adding — not to catch this bug (gone) but
because the matrix's CMakeCache-only diff is structurally blind to the
target-property/install class.

**(2) silent `~label=` drop — FIXED (2026-07-16, `a5d33ae`).** New
`Unknown_kwarg` wellform check (CST-level, `check_cst_kwargs`): a `~label=` on a
KNOWN command that isn't in the command's vocabulary
(`Yc_primitives.command_kwargs` / `allowed_kwarg`, audited from every kwarg read
in the parser) is **fatal** on all surfaces (compile / fmt / LSP / corpus gate).
`link_lib foo ~public=['bar']` now rejects instead of emitting an empty link
list. Family-granular `~out` rule; install_targets dotted artifact keys;
unknown/user commands and assignment kwargs exempt. Also completed the honest
emit for the fifth renderer (`88320dd` — ECmakeRawCmd's raw_arg still derefed
bare idents).

**(3) find / add_test / property-stub families — FIXED (2026-07-16, `3618e9e`).**
Labeled-only rollout completed for the last keyword families: find_* reject
positional NAMES/PATHS/… (labels existed); find_package rejects
REQUIRED/COMPONENTS/… (COMPONENTS was a *silent drop*; ~required is the
surface; bare version `'9.0'` still accepted-and-dropped — version-literal
TODO); add_test gains ~name/~command labels + reject — and the migration
**fixed a live corpus bug**: the old NAME-section split silently dropped
`-C ${CMAKE_BUILD_TYPE}` on three ctest invocations (matrix-blind; restored to
vendor parity, emit-diff verified); the specialized property getters/setters
reject their PROPERTY/PROPERTIES forms (their raw fallback leaked *yc* command
names — `set_global_property(` isn't cmake).

**Still open:** (4) `Function_def_typo` open-world gate +
`check_reserved_names` declaration coverage; the **matrix supplement**
(file-api / target-property / test diff — the add_test `-C` drop is the third
confirmed instance of the CMakeCache blind spot, after target properties and
install clauses). Full detail in the report doc.
