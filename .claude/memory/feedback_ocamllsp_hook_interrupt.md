---
name: ocamllsp PostToolUse hook interrupts multi-edit turns
description: OCaml LSP fires stale diagnostics via PostToolUse:Edit hook mid-turn, cutting Claude responses short during multi-file refactors
type: feedback
---

During multi-file edits, `ocamllsp` fires a `PostToolUse:Edit` hook after every file save and emits cross-module diagnostics based on stale `.cmi` files. These are injected back into Claude's context mid-turn as `<system-reminder>` blocks, which the Claude Code runtime treats as a turn boundary — cutting the response short before the task is complete.

**Why:** ocamllsp reads compiled `.cmi` files directly; after editing a `.ml` file but before `dune build`, all cross-module type info is stale. The LSP has no way to know the build is dirty.

**How to apply:** Ignore all LSP diagnostics shown in `<ide_diagnostics>` blocks during multi-file OCaml edits. Always verify with `dune build` at the end. Do not re-attempt edits in response to stale LSP errors mid-turn.

**Workaround applied:** Disabled ocamllsp diagnostics in `.vscode/settings.json`:
```json
"ocaml.server.diagnostics": false
```
Re-enable manually when actively writing OCaml (rarely needed). To re-enable: set to `true` or remove the key.

**Future fix (standalone project):** ocamllsp should integrate with `dune rpc` (dune already has an RPC protocol for build status) to suppress cross-module diagnostics when the build is known dirty. Alternatively, mark inter-module errors as "stale" until the next successful build completes. The injection point in the Claude Code extension is `DiagnosticTracking.findDiagnosticsProblems` in `extension.js` — a per-language filter setting (`claudeCode.diagnostics.excludedLanguages`) would be the clean extension-side fix.
