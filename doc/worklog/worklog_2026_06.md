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
