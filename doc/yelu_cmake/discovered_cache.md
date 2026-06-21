# Discovered cache — a driver-level pattern

> A piece of information the runtime needs that is **expensive to discover**
> (parsing external docs, walking source trees), **externally sourced**
> (depends on a vendor / language we don't control), **largely static**
> across runs, and **versioned** by its source. Bake it at build time, embed
> the fingerprint, validate on demand. Generalizes the cmake-stdlib name
> lookup landed 2026-06-21; the same recipe applies to cmake reserved
> variables, cmake policies, generator-expression ops, and any future
> "what does cmake actually know about" query.

## Motivation

The wellform pass needs to answer "is this name a real cmake command, or
a typo?" The yc-typed primitives live in `Yc_primitives.command_names`
(committed source). But cmake's command set is much bigger — every
function/macro in `cmake/Modules/*.cmake` is also a real command, and
discovering it cheaply means walking ~1000 `.cmake` files with a
tree-sitter parser. We do **not** want to do that at every wellform call.

We also want the answer to be:

- **fast at runtime** — `Set.mem` on a baked-in array
- **reproducible** — the embedded names match a known cmake version
- **invariant of deployment** — yelu shouldn't require a cmake installation
  to run (cmake stays a build-time / dev-time dependency)
- **observable** — the user can ask "what cmake version was this cache
  built against?" and decide whether to regenerate

The pattern below answers all four.

## The shape — four operations

```text
              ┌──────────────────────────────────────────┐
              │                                          │
            (1) discover   ──→   (2) cache_file (committed)
              ▲                            │
              │  stale?                    │  (3) build-time embed
              │                            ▼
            (4) validate     ←──→   in-binary data module
                                          │
                                          ▼
                                   runtime API (O(1) lookup)
```

1. **discover** — run a generator against the external source (cmake's
   `Modules/`, `Help/`, etc.). Slow; offline; produces a TSV with a
   versioned header.
2. **cache** — commit the TSV to `tool/cmake_text/`. This is the
   *file-level cache* — the build's "we ran the discovery once and here's
   the answer."
3. **embed** — a dune rule reads the TSV at build time and emits an OCaml
   data module (names array + fingerprint string) compiled into the
   binary. No runtime file I/O, no deployment-path search.
4. **validate** — on demand (CLI flag / LSP request / `--version` output),
   show the cached fingerprint. The user compares it against their current
   cmake version and decides whether to regenerate. Option (d) from the
   2026-06-21 design discussion: simple, no I/O dependency, the
   regeneration is a manual step.

## Fingerprint — what goes in the TSV header

Every TSV starts with comment lines that the build embeds as constants:

```text
# <name> — discovered-cache for <purpose>.
# Pattern: doc/yelu_cmake/discovered_cache.md.
#
# Generated: <YYYY-MM-DD>
# cmake-version: <X.Y.Z>
# source-root: <path or "<builtin>">
# generator: <tool-name-or-"hand-curated">
```

These four lines are the minimum. The dune codegen rule reads them with
`grep -E '^# <field>: '` and embeds the values as `let <field> = "..."`
constants in the generated module.

## How `Cmake_stdlib_names` follows the pattern (first instance)

| File                                                | Role                                                                |
| --------------------------------------------------- | ------------------------------------------------------------------- |
| `tool/cmake_text/cmake_stdlib_names.tsv`            | Committed TSV with version header + names. Hand-curated v0.         |
| `src/langs/yelu/dune`                               | dune `(rule)` reading the TSV, emitting `cmake_stdlib_names_data.ml` |
| `src/langs/yelu/cmake_stdlib_names_data.ml`         | **Generated** — name array + `cmake_version_at_cache` + `generated_date` constants. Not committed. |
| `src/langs/yelu/cmake_stdlib_names.ml`              | Runtime API: `mem : string -> bool` (case-insensitive), `count`, version accessors. |
| `src/langs/yelu/yc_wellform.ml` (`check_unknown_command`) | Three-tier lookup: `Yc_primitives.is_known_command nl || Set.mem defined nl || Cmake_stdlib_names.mem nl`. |

The two non-generated source files (TSV + runtime API) are the only
things to maintain. Everything else is mechanical.

## Validity check — option (d), manual regen

We chose the *simplest* validity model in v0:

- The TSV header carries `cmake-version: X.Y.Z` and `Generated: YYYY-MM-DD`.
- The build embeds these as compile-time constants.
- The runtime API exposes them (`Cmake_stdlib_names.cmake_version_at_cache`
  / `.generated_date`).
- **No automatic file-system check.** No `vendor/cmake` probing, no
  `cmake --version` subprocess, no path-walking.
- When the user wants to verify currency, they read the fingerprint
  (e.g., printed as part of `yelu --version` — future addition) and
  compare against their cmake. If stale, regenerate the TSV.

This keeps yelu binaries fully self-contained at runtime, which matters
if/when yelu is shipped as a standalone tool. Cmake remains a
*build-time* requirement (for regenerating the TSV) but not a *runtime*
one.

When we need stricter freshness later (e.g., as a developer aid),
options (a)/(b)/(c) from the design discussion are upgrade paths — but
they pull `vendor/cmake` into the deployment surface and we'd want a
real reason before paying that cost.

## Regenerating a cache

For `cmake_stdlib_names` v0 (hand-curated):

1. Edit `tool/cmake_text/cmake_stdlib_names.tsv` directly to add/remove names.
2. Bump the `# Generated:` and `# cmake-version:` headers.
3. `dune build` — the codegen rule picks up the change automatically.
4. `dune test` — the corpus gate will catch any closed-world unknowns
   that the new whitelist no longer covers.

For a future cmake-version bump (v1+, automated):

```sh
# 1. Set vendor/cmake to the new version (symlink update).
# 2. Regenerate the TSV via the existing tool.
dune exec tool/cmake_text/cmake_name_index.exe -- vendor/cmake/Modules \
  > tool/cmake_text/cmake_stdlib_names.tsv.gen
# 3. Merge with the hand-curated <builtin> entries (cmake C-side commands).
# 4. Update the # cmake-version: header.
# 5. dune build && dune test.
```

The hand-curated supplement covers cmake C-side builtins that
`cmake_name_index` (which only sees function/macro defs) misses.

## Adding a new instance — the recipe

1. Identify the discovery (what external info do you need?). Examples
   listed below.
2. Author the TSV under `tool/cmake_text/<name>.tsv` with the four-line
   header.
3. Add a `(rule)` in the relevant library's `dune` file, mirroring the
   `cmake_stdlib_names` shape.
4. Write the runtime API module (`<Name>.ml`) wrapping the generated
   data — `mem` / `find` / version accessors per your need.
5. Wire into the wellform check or whatever consumer needs the lookup.
6. Tests: assert the embed produces the expected values + the consumer
   uses them correctly.
7. Update this doc's instance table below.

## Known and candidate instances

| Cache                    | Source                                        | Status                                                                                        |
| ------------------------ | --------------------------------------------- | --------------------------------------------------------------------------------------------- |
| `Cmake_stdlib_names`     | `vendor/cmake/Modules/*.cmake` + C-side builtins | ✅ **shipped 2026-06-21**. v0 hand-curated (~80 names); auto-regen via cmake_name_index v1+. |
| `cmake_reserved_vars`    | `vendor/cmake/Help/variable/*.rst`            | TSV exists at `tool/cmake_text/cmake_reserved_vars.tsv` but is **loaded at runtime** by tests (path-walking). Re-architect to follow the pattern when next touched. |
| `cmake_policies`         | `vendor/cmake/Help/policy/CMP*.rst`           | not started. Useful when implementing Y11 (policy-aware compiler).                            |
| `cmake_genex_ops`        | `vendor/cmake/Help/manual/cmake-generator-expressions.7.rst` | not started. Useful for genex-aware syntax highlighting and wellform checks.   |
| `cmake_builtin_commands` | `vendor/cmake/Help/command/*.rst`             | currently inline in `cmake_stdlib_names.tsv` `<builtin>` entries; could split into a dedicated cache. |
| Per-corpus `function`/`macro` index | `probes/<project>/**/*.cmake`     | `cmake_name_index.exe` produces this per-project (corpus-local cache); used by the existing `cmake_reprint` pipeline. Same pattern, different scope (per-corpus vs cmake-stdlib). |

## Related

- [`driver.md`](driver.md) §6.5 — the compile/wellform/format/LSP contract
  that wellform plugs into. The stdlib cache is one input to that pipeline.
- [`../lang/surface_lsp_framework.md`](../lang/surface_lsp_framework.md)
  §7.5 — the open/closed-world rule for `Unknown_command`. The stdlib
  cache shifts which calls count as "known", which directly affects which
  files compile under closed-world fatal.
