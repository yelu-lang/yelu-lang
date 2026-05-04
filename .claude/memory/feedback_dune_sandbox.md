---
name: dune sandbox and promote
description: dune sandboxes build rules — alias deps force builds but don't expose files; promote solves cross-rule access
type: feedback
---

**Rule**: When a dune rule needs to read files produced by another part of the build (e.g. a Python test script reading compiled `.exe` files), `(alias dir/all)` is not enough — it forces the build but the files are not exposed in the sandbox. Use `(glob_files ../../src/bin/.../*.exe)` as direct file deps, which requires the files to exist in the source tree.

**Why**: dune's sandbox only symlinks declared file deps into the action environment. `(alias ...)` deps are order-only (force build order) but add no files to the sandbox. Build artifacts not in the source tree are invisible.

**How to apply**: When a test rule needs to read build artifacts, add `(promote (until-clean))` to the producing `(executables ...)` stanza so the artifacts land in the source tree, then declare them as `(glob_files ...)` deps in the consuming rule. Also pass `%{workspace_root}` via `(setenv TOLA %{workspace_root})` so Python scripts can find the workspace root reliably regardless of `__file__` resolution.
