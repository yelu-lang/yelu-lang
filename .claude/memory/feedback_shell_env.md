---
name: No eval $(opam env) prefix needed
description: Don't prefix dune/opam commands with eval $(opam env) — user keeps opam env set in CC's bash env
type: feedback
---

Don't prefix shell commands with `eval $(opam env)`. The user configures opam env in Claude Code's bash environment directly, so `dune`, `opam`, etc. are already on PATH.

**Why:** The user said "I should have set this for cc's bash env, so you don't need that."

**How to apply:** Run `dune build`, `dune test` etc. directly without the `eval $(opam env) &&` prefix. If a command fails because dune isn't found, ask the user to check their CC bash env rather than adding the prefix.
