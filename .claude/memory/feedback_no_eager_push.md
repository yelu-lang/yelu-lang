---
name: feedback-no-eager-push
description: Don't auto-push commits; the user is a solo developer and prefers local commits with explicit pushes
metadata:
  type: feedback
---

Don't run `git push` as a side effect of completing work. Commit freely on local main; let the user decide when to push.

**Why:** the user is the solo developer on this project, so there's no team-coordination pressure to publish. They prefer to keep commits local until they explicitly say push (or stage a batch of related work to push together). Eager pushing also makes it harder to amend / reorder / squash before publication.

**How to apply:**
- After `git commit`, stop. Do not chain `git push`.
- If a task explicitly says "commit and push" or "ship X", push is in scope.
- Pairs with [[feedback-web-docs-explicit]]: the public site updates only on explicit ask. Local commits about the web are fine, but pushing them isn't.
- Mentioning the option ("want me to push?") is fine and useful at natural endpoints; doing it without being asked isn't.
