---
name: feedback-web-docs-explicit
description: Web docs under docs/ are user-facing; never update them as a side effect of internal work. Wait for explicit instruction.
metadata:
  type: feedback
---

The `docs/` directory (the GitHub Pages site at github.com/yelu-lang/yelu-lang) is user-facing and should be updated only when the user explicitly asks. Do not refresh `docs/index.html`, `docs/architecture/index.html`, or any other web page as a side effect of finishing internal retirement / refactor work. Don't push web doc changes; don't include them in commits that touch internal docs.

**Why:** the web site is the public face of the project. Edit cadence and content choices belong to the user, not to side-effects of automation. The user previously had me eagerly refresh the site after item F landed; clarified that web updates need to be discussed and approved explicitly.

**How to apply:**
- When internal docs change (`doc/yelu_cmake/*.md`, source comments, CLAUDE.md), do not touch `docs/*` even when the same vocabulary update applies.
- If a question arises about whether a piece of work warrants a web update, ask before doing it.
- The exception is when the user names the web docs directly ("update the architecture page", "refresh the home status table", etc.).

Internal docs (everything under `doc/`) and code comments do not need the same gatekeeping — those should stay current.
