# CMake `install()` and installation paths

Install is the one cmake stage that, run naively, **writes outside the project
tree** — and cmake gives you no undo. This doc explains the path model and states
the **project principle** every yelu experiment, test, and probe follows.

## The path model (and why it's a footgun)

- **`CMAKE_INSTALL_PREFIX`** is the root every `install(... DESTINATION ...)`
  is relative to. Its **default on Unix is `/usr/local`** — i.e. a *bare*
  `cmake --install <build>` writes into **system directories**. `install(TARGETS
  … LIBRARY DESTINATION lib)` lands at `/usr/local/lib`, headers at
  `/usr/local/include`, and so on (usually via `GNUInstallDirs`).
- **`DESTDIR`** (env, honored at `cmake --install` time) prepends a *staging*
  root — `DESTDIR=/tmp/stage cmake --install …` puts files at
  `/tmp/stage/usr/local/…`. Packaging tools use it; it does **not** change the
  embedded prefix (rpaths, config-file paths still say `/usr/local`).
- **`cmake --install <build> --prefix <p>`** overrides the prefix at install
  time without reconfiguring — the clean way to redirect.
- **There is no `cmake --uninstall`.** cmake writes an `install_manifest.txt`
  but ships no uninstall target. Undoing a system-wide install means manually
  `xargs rm < install_manifest.txt` — fragile, and it won't remove created
  directories. This is why an accidental system install is genuinely costly.

## Project principle — always a sandboxed, test-target-related prefix

> **Never install system-wide in any yelu context.** Every `cmake --install`
> (or install-exercising oracle) MUST target a throwaway prefix **under `_out/`,
> scoped to the test target** — never `/usr/local`, never a bare install.

Concretely, the prefix is **`_out/<project>/<tag>/install`**, where `<tag>`
identifies the test target — a **matrix cell** (e.g. `_out/json/JSON_Install=ON/install`),
a build_equiv cell, or a step id. This:

- **matches the `_out/<project>` build-output convention** (see
  [`probes/PROBE_CHARTER.md`](../../probes/PROBE_CHARTER.md) § layout), so
  install scratch lives beside build scratch and cleanup is one `rm -rf _out/<project>`;
- **lets install *combinations* coexist** — several option cells each install to
  their own prefix without collision, which is exactly what you need to compare
  install layouts across a matrix;
- **keeps verification side-effect-free** — same spirit as sandboxing configure
  to a temp build dir.

Always pass the prefix explicitly and inspect in place:

```sh
cmake --install "$build" --prefix "_out/<project>/<tag>/install"
find "_out/<project>/<tag>/install"    # inspect what landed where
```

For staging semantics use `DESTDIR` **on top of** a sandbox prefix, never as a
substitute for one.

## Where this bites today

- The build-level oracle (`build_equiv`, Level 7 in
  [`../framework/testing.md`](../framework/testing.md)) compares **in-place**
  build artifacts and does **not** run install — so it never touches a prefix.
  Good default. **When an install channel is added** (e.g. comparing the
  installed layout / exported Config package of vanilla-cmake vs yc — a natural
  next oracle for projects like nlohmann/json with `JSON_Install=ON`), it must
  install each side to a per-cell `_out/<project>/<tag>/install` and diff the
  trees there.
- Probes that translate an install-heavy project (json, most anchor-tier
  candidates ship `install()` + `export()`): configure-time matrix cells don't
  install, but any install verification obeys the principle above.

## Related

- [`painpoints.md`](painpoints.md) § 7 — `install(EXPORT …)` as an unnamed
  named-entity namespace (the export-set modeling angle, distinct from paths).
- Memory: `feedback-cmake-install-prefix` (the operational form of this rule).
