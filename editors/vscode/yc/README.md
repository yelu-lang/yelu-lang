# yc — VS Code syntax highlighting

TextMate-grammar syntax highlighting for yelu-cmake (`.yc`) files. This is
**Milestone 0** of the surface/LSP track — a server-less highlighter; no
language server yet. Design: [`doc/lang/surface_lsp_framework.md`](../../../doc/lang/surface_lsp_framework.md).

## Enable it

Run these in the VS Code **integrated terminal** (the `code` CLI lives
there). Paths below assume the repo at `/home/red/code/research/yelu`.

### One window, no install (quick look)

```sh
code --extensionDevelopmentPath=$PWD/editors/vscode/yc
```

Opens a separate **Extension Development Host** window with `.yc`
highlighting; open e.g. [`probes/fmt/main.yc`](../../../probes/fmt/main.yc).
Closes with that window — nothing installed. (Pressing **F5** with this
folder open does the same.)

### All windows (install)

Package and install:

```sh
cd editors/vscode/yc
npx --yes @vscode/vsce package          # → yc-<version>.vsix
code --install-extension yc-0.0.1.vsix
```

Then **Ctrl+Shift+P → "Developer: Reload Window"**. Open a `.yc` file —
the status bar (bottom-right) should read **Yelu-cmake**. Uninstall with
`code --uninstall-extension yelu-lang.yc`. Or install via the UI:
**Extensions view → "⋯" → "Install from VSIX…"**.

Lighter dev alternative — symlink instead of repackaging on each change
(then edits need only a **Reload Window**):

```sh
ln -s "$PWD/editors/vscode/yc" ~/.vscode-server/extensions/yelu-lang.yc-0.0.1
```

### Remote-WSL note

On Remote-WSL, `code --install-extension` and the symlink target
`~/.vscode-server/extensions/` (the WSL/workspace side) — correct for
editing files inside WSL. After a vocabulary change, run `make tmgrammar`,
then repackage + reinstall (or just **Reload Window** if you symlinked).

## How the grammar is produced (single source of truth)

`syntaxes/yc.tmLanguage.json` is **generated** — do not hand-edit the
vocabulary. Its keyword/command/operator patterns come from the yc
*vocabulary manifest* (`Yc_manifest`), which is test-locked to
`Yc_primitives` and the lexer so the three can't drift. The structure
rules (strings, comments, `${…}` / `$<…>`, numbers, `:attrs`) are the
hand-written template in the `yelu tmgrammar` emitter.

Regenerate after any vocabulary change:

```sh
make tmgrammar          # regenerate this file from the manifest
make tmgrammar-check    # fail if the committed file is stale vs the manifest
```

## Verify highlighting headlessly

The committed grammar is tokenized by the real VS Code TextMate +
Oniguruma engine (so a clean run == correct in-editor highlighting):

```sh
cd test && npm install && node tokenize.js          # default: probes/fmt/main.yc
```

## Known limitations (Milestone 0)

- `$<…>` generator expressions are matched coarsely (no nesting) — the
  regex stops at the first `>`. Accurate genex coloring is a later
  semantic-tokens job once the LSP lands.
- Highlighting is lexical only. Distinctions that need real parsing
  (e.g. a cache var vs a normal var) await LSP **semantic tokens** — see
  the design doc.
