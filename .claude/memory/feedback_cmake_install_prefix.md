---
name: feedback-cmake-install-prefix
description: Never install system-wide; always a per-test-target sandbox prefix under _out/
metadata:
  type: feedback
---

**Project principle** (elevated to doc 2026-07-25 → `doc/cmake/install.md`):
**never install system-wide in any yelu context.** Every `cmake --install`
(or install-exercising oracle) MUST target a throwaway prefix **under `_out/`,
scoped to the test target** — `_out/<project>/<tag>/install`, where `<tag>` is a
matrix cell / build_equiv cell / step id. Never a bare `cmake --install`, which
defaults to `CMAKE_INSTALL_PREFIX` (`/usr/local` on Unix) and writes into system
directories — and cmake has **no uninstall** (only a fragile
`install_manifest.txt`).

**Why test-target-related (not just /tmp):** installs across a matrix need to
*coexist* without collision so install combinations can be compared per cell;
putting them under `_out/<project>/` matches the build-output convention, so
cleanup is one `rm -rf _out/<project>`.

**Why:** the standard harness stops at cmake *configure*; build_equiv compares
build artifacts **in place** and never installs. Running install is only for
when configure/in-place isn't enough (e.g. checking install(TARGETS)/export
Config layout — a natural future oracle for install-heavy probes like
nlohmann/json with `JSON_Install=ON`), and it must be sandboxed.

**How to apply:** `cmake --install "$build" --prefix "_out/<project>/<tag>/install"`;
inspect with `find`. Use `DESTDIR` only *on top of* a sandbox prefix, never
instead of one. Same spirit as [[feedback-dune-sandbox]] — verification stays
side-effect-free. Full model + rationale: `doc/cmake/install.md`.
