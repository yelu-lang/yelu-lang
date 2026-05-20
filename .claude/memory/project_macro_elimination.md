---
name: Macro elimination as a yelu design direction
description: User is interested in eliminating yc_macro from yelu in the future; data-gated on R5 and Bar #3 usage observations
type: project
---

**Direction (raised 2026-05-11).** User wants to consider whether yelu can
eliminate macros (`yc_macro` / `ECmakeMacro`) from its user-facing surface
in the future. Aligns with the project's "low-entropy configuration"
thesis: macros are textual substitution with reflective call-site access,
hard to type-check.

**Why:** The 2026-05-11 R4-b.3 study found that tiny's existing
`ECmakeMacro` implementation (commit abb501f) treats macros like
function-scoped calls, which is wrong per probes P23/P24 — real cmake
macros are frame-less textual substitution. Fixing that is R4-b.4. But
if yelu eliminates user-authored macros, the fix becomes moot and
yc_macro is removed instead of repaired.

**How to apply:**
- Defer the decision to after **R5** (runcmake-yelu glue, surfaces what
  real cmake test scripts use) and **Bar #3** (real-world cmake projects
  like z3/llvm/torch).
- Use those data points to count: how many macro definitions are
  user-authored vs cmake-stdlib-module-authored?
  - User-authored ones are the ones yelu could refuse.
  - Module-authored ones (e.g. `check_cxx_compiler_flag` from
    `CheckCXXCompilerFlag`) call cmake at configure-time; yelu doesn't
    need to model them. The existing lenient `ECmakeApply` already
    handles "call to function loaded from elsewhere" by emitting a
    faithful call.
- If the data supports it, the elimination is: drop the `yc_macro`
  helper, deprecate `Yc_macro` in the production AST (or just stop
  building it), delete `ECmakeMacro` from tiny.
- Migration shape for what macros do today:
  - **Pure helpers without PARENT_SCOPE writes** → trivially translate
    to `yc_function`.
  - **PARENT_SCOPE side effects** → `yc_function` + explicit
    `set(... PARENT_SCOPE)` or `return(PROPAGATE …)`.
  - **`${ARGN}` variadic** → harder; needs a yelu-side variadic
    mechanism (typed list arg) that lowers to cmake function with
    its own `${ARGN}` handling, OR a different lowering pattern.

**Current state (2026-05-11):** R4-b.4 paused. `ECmakeMacro` in tiny is
wrong-but-unused dead code. Leave as-is until the elimination decision
is made; either delete the constructor (elimination) or fix the eval
(repair). No tests block either choice.

**Related design observation (compiler-classic frame vs dynamic scope):**
The env-frame stack landed in R4-b.3 reads like a classic activation
record (locals + access link) but with a copy-on-entry snapshot instead
of a live chain. That makes reads lexically stable (function can't see
caller's mid-call writes) while writes via PARENT_SCOPE punch through
the severed link. Document this hybrid in `doc/lang/lang_design.md` if /
when discussing yelu's binding-feature library (Y15) more formally.
