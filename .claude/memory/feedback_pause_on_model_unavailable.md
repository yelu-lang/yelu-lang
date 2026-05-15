---
name: feedback-pause-on-model-unavailable
description: When the auto-mode safety check reports the model temporarily unavailable, pause and surface it instead of pushing through
metadata:
  type: feedback
---

If a tool call (typically Bash under auto mode) is blocked with a message like
"claude-opus-4-7[1m] is temporarily unavailable, so auto mode cannot determine
the safety of Bash right now", pause and tell the user. Do not keep retrying
the same call.

**Why:** The user can switch the session to non-auto mode or wait it out
themselves — but only if they know it's happening. Repeated retries waste
turns and obscure the real blocker.

**How to apply:** First occurrence of the message → stop the current
sub-task, summarize where things stand, and let the user choose
(non-auto mode, wait, switch tasks). Don't sleep-and-retry, don't
silently keep working around the block.
