---
name: Ask before implementing semantically-loaded constructs
description: User wants design discussion before code on constructs that touch scope, binding, control flow, or evaluation order — even if surface shape looks routine
type: feedback
---

When a new construct affects **scope discipline, variable binding lifetimes,
control flow, or evaluation order**, pause and surface the design choices
*before* writing code. The 2026-05-10 foreach miss is the canonical example:
the bridge addition looked routine (mirror surface/theory, lift/lower, emit)
so I implemented save/bind/eval/restore by analogy with F2 functions. But
cmake's `foreach()` is the *opposite* of a function call on scope — the
loop variable leaks (no restore on exit). The implementation passed the
emit-only bridge tests but had wrong eval semantics that no test would catch.

**Why:** these constructs are where research questions live. F2 got a real
design conversation (call-by-value vs name, dynamic vs lexical scope,
save-and-restore vs deep binding, macros vs functions). Sliding foreach in
without that same conversation defeats the point of co-developing the
yelu1+yelu2 axes.

**How to apply:** when a new bridge case touches any of:
- variable scope (introduces or restores a binding)
- control flow (loops, conditionals beyond plain if, exceptions, returns)
- evaluation order (left-to-right vs other, call-by-X)
- name resolution (lexical vs dynamic, hygiene)

…stop and ask. Cheap to surface a couple of options with their tradeoffs;
costly to slide in wrong semantics that emit-only tests can't observe.

**Counter-examples (don't pause):** mechanical attrition — add a new
target/property/file/string variant whose emit form is obvious and whose
eval is a stub. Those should keep flowing without ceremony.

The user's wording was: "when in doubt, you can ask me before heading too
much." Read "in doubt" as "if I had to pattern-match to feel confident
about scope/binding/control-flow choices, that's the doubt — surface it."
