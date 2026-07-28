# nlohmann/json — probe plan (PLAN, pre-execution)

> **Status: PLAN.** This is the learn→plan output from a dry-run, reviewed before
> handoff. The *execute* phase (writing `main.yc` + the `dune` gate + a matrix
> smoke, then iterating) has not started. Follow [`../PROBE_CHARTER.md`](../PROBE_CHARTER.md).

## Project & pin

| | |
| --- | --- |
| Project | [nlohmann/json](https://github.com/nlohmann/json) — header-only JSON, INTERFACE-library canon |
| **Pinned tag** | **v3.12.0** |
| **Commit** | `55f93686c01528224f448c19128836e7df245f72` |
| Source | `vendor/json` → `~/code/contrib/json-all/json` (symlink; **setup done**) |
| Build/matrix out | `_out/json/` |
| Root CMakeLists | 225 lines |

## Scope — root-only first pass

Translate **only the root `CMakeLists.txt`**. Base config holds the two
subdir/dep-pulling options **OFF** so no `add_subdirectory` fires:

- `JSON_BuildTests=OFF` — skips `add_subdirectory(tests)` (+ `CTest`, thirdparty).
- `JSON_CI=OFF` — skips `include(ci)` and its targets.

Deferred to a later pass: `tests/` (many subdirs, thirdparty deps), any CI.
(v3.12.0 has **no** `NLOHMANN_JSON_BUILD_MODULES` — the C++20-modules path that
exists on HEAD is absent here, so nothing to defer there.)

## File inventory (first pass)

| upstream | → `.yc` | notes |
| --- | --- | --- |
| `CMakeLists.txt` (225 L) | `probes/json/main.yc` | the whole first pass — INTERFACE lib + options + install/export |

## Matrix axes (9 options — the `main.json` list)

The 9 options that don't pull a subdirectory, each × {ON, OFF}. `JSON_Install`
defaults ON (json is the main project) so the install/export block is exercised.
`JSON_BuildTests` / `JSON_CI` are **not** matrix axes in this pass (held OFF).

## Policy — resolved, no pause needed

- `if (POLICY CMP0077)` → yc if-predicate (`ECmakePolicyCheck`) ✓
- `cmake_policy(SET CMP0077 NEW)` → `policy_set CMP0077 NEW` ✓ (faithful emit)

CMP0077 is the only policy; both forms are modelled. No `yc_raw`, no pause.

## Expected gaps to verify (watch, not known blockers)

Per the charter, **pause + record** if any of these turns out to be a yc gap:

1. **Install/export Config-package shapes** — the block uses `install(DIRECTORY
   … DESTINATION)`, `install(FILES …)`, `install(TARGETS … EXPORT … INCLUDES
   DESTINATION)`, `install(EXPORT … NAMESPACE … DESTINATION)`, and
   `export(TARGETS … NAMESPACE … FILE)`. fmt exercised `install(TARGETS EXPORT)`;
   the `install(EXPORT)` set + `export(TARGETS)` are the shapes to confirm.
2. **`configure_file` ×2** (the `…Config.cmake.in` / version / pkgconfig files)
   — emit-only (the matrix runs real cmake), so just needs faithful emission.
3. **stdlib includes** — `GNUInstallDirs`, `CMakePackageConfigHelpers`,
   `CPack` — emit-only; real cmake resolves them.
4. **`${MAIN_PROJECT}` detection** — the `CMAKE_SOURCE_DIR STREQUAL
   CMAKE_CURRENT_SOURCE_DIR` logic driving option defaults; verify the condition
   erases faithfully.

## Translation order (execute phase)

Root `CMakeLists.txt` top-to-bottom → `main.yc`; corpus-compile after each chunk;
then add a matrix smoke modelled on `test_fmt_matrix_smoke.ml` + the `dune` gate;
iterate to N/N cells across cache / codemodel / ctest.

## Open decisions

- Tag (**v3.12.0**) and scope (**root-only**) — resolved with the human.
- Nothing else blocking. Follow the pause protocol on any yc gap or milestone.
