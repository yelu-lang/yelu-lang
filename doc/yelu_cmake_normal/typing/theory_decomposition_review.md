# ycn theory decomposition — review (decision checkpoint)

> **Status**: decision checkpoint — a discussion artifact, not implementation.
> Decides whether the current ycn theory decomposition is **good**, needs
> **improvement**, or should be **left for the future**, before any further
> ycn work (bridge audit, value-crossing rule, core module, concrete syntax).
> First discussed 2026-08-05; the decision record lives at the bottom and is
> the checkpoint's output.

## 1. Purpose and placement

ycn's concrete syntax was the "next big rock" in
[`status.md`](../../status.md). Before committing to a surface, we want to be
sure the substrate the surface will compile to — the 16-fragment theory
decomposition — is one we want to build on. This review is therefore **step 1**
of the ycn sequence:

1. **Theory-decomposition review** (this doc) — good / improve / defer.
2. Bridge-surface audit + convert-coverage lock.
3. Value-crossing rule (temp synthesis vs `ESetVar`-wrapped discipline).
4. Core module + namespace hygiene (`plan.md` piece 1).
5. Manifest future + erasure policy.
6. Concrete syntax.

The review is grounded in a runnable AST probe
([`src/bin/debug/debug_ycn_decomp.ml`](../../../src/bin/debug/debug_ycn_decomp.ml))
that exercises hand-built ycn programs — **no concrete syntax needed** — through
ycn-eval, `from_normal`, emission, yc-eval, and `to_normal` roundtrip.

## 2. The question and the options

**Question**: is the current decomposition (one fragment per cmake command
family, 14 cmake theories + `bool` + `int`, extensible-variant ctors +
per-fragment `eval_case`) a good theory decomposition?

**Options**:

| Option               | What it means                                                                                                             | Cost                      |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------- | ------------------------- |
| **Good as-is**       | Ship it; only fix concrete bugs found along the way                                                                       | lowest                    |
| **Improve in place** | Keep the fragment shape; add enforced discipline (kinds, manifest, coverage lock) and fix the seams §6                    | medium                    |
| **Re-cut now**       | Re-derive theories from the semantic domain (values / state / entities / effects), cmake shapes become a compat layer     | highest                   |
| **Leave for future** | Do Y17 typing on the current shape and let typing constraints reveal the right boundaries (`plan.md`'s original deferral) | lowest now, deferral risk |

## 3. Evidence — the AST probe

Run: `dune exec src/bin/debug/debug_ycn_decomp.exe`

For each program the probe reports: ycn-eval value, emitted cmake text,
yc-eval value through the bridge (`dual`), and ycn-eval after
`to_normal ∘ from_normal` (`stable`). Summary of the 18 programs (2026-08-05):

|   #   | Program                               | Result                                                                    |
| :---: | ------------------------------------- | ------------------------------------------------------------------------- |
|   1   | string pipeline (upper → concat)      | ✅ clean; emits `string(TOUPPER b TMP)` / `string(CONCAT OUT a TMP c)`     |
|   2   | int + bool composition assigned       | ✅ eval/dual/roundtrip; ❌ **emit**: `cannot erase expression to cmake arg` |
|   3   | if-statement, string-truthiness cond  | ✅ clean; emits `if(FLAG) …`                                               |
|   4   | if value-shaped (no assignment)       | ⚠️ **value loss**: ycn `"yes"` → yc `VUnit` (dual false); roundtrip stable |
|   5   | list literal → `EStringJoin`          | ✅ clean                                                                   |
|   6   | in-place append + bare join           | ❌ **from_normal**: bare `EStringJoin` raises `cannot translate unknown …` |
|   7   | list length + get                     | ✅ clean                                                                   |
|   8   | list get out of range                 | ⚠️ eval raises `list index out of range` (faithful: cmake errors too)      |
|   9   | cache first-write-wins                | ✅ clean                                                                   |
|  10   | cache `FORCE` overwrite               | ✅ clean                                                                   |
|  11   | target declare → exists → add sources | ✅ eval/dual/roundtrip; ❌ **emit** for `ESetVar("HAS", ETargetExists …)`   |
|  12   | function def + apply                  | ❌ **from_normal**: nested `EStringConcat` in `message` texts              |
|  13   | project + min version + message       | ✅ clean                                                                   |
|  14   | `ELet` lexical vs `ESetVar`           | ✅ clean                                                                   |
|  15   | `EIntGreater` assigned                | ❌ **from_normal** (bridge-dead ctor)                                      |
|  16   | `EInstallDirectory`                   | ❌ **from_normal** (bridge-dead ctor)                                      |
|  17   | bare concat in `message` texts        | ❌ **from_normal** (value ctor in arg slot)                                |
|  18   | `ESetVar`-wrapped concat              | ✅ clean (the control)                                                     |

## 4. The discussion (2026-08-05, condensed)

### Q1 — What is the decomposition *for*?

The criteria change with the answer. If ycn is the substrate for Y17 typing and
optimization passes, the decomposition must maximize **semantic atomicity**
(each ctor is one operation, no hidden effects) and follow the **semantic
domain**. If ycn is a "better cmake", cmake command families are a fine cut.
If it is the multi-pack research vehicle, the pure core must be
**pack-separable**. Read of the manifesto: all three, in that order — so the
current cut (one fragment per cmake family) is inherited from the target
language, not derived from the semantics.

### Q2 — Is "one fragment per cmake command family" a decomposition at all?

The probe says it is **partial**:

- **Orthogonality**: `EList` collides across core (surface value) and
  `normal_list` (list literal); `EUnsetVar`/`EVarDefined` live in `store` but
  are handled by both core eval loops (store's own arms are dead).
- **Completeness**: 3 of 6 int ops and `EInstallDirectory` are bridge-dead.
- **Compositionality**: value ctors cannot appear in argument positions
  (`message(concat …)` crashes the bridge — no temp synthesis).
- **Honesty**: `ESetCache`/`EFindPackage`/`ETryCompile` are cmake-shaped side
  effects present "so `to_normal` can preserve semantics across the bridge" —
  they violate the compute-then-assign principle.

Notably, `bool`/`int` were *already* split off because the cmake families
could not express them — the seed of a semantic re-cut that stopped at two
theories.

### Q3 — Does the probe change `plan.md`'s deferral?

`plan.md` says "defer the type-level split; Y17 will make the right boundary
obvious." The probe's seams are **structural, not type-theoretic**: namespace
collisions and bridge coverage will not be fixed by a typing pass. The real
choice is therefore narrower: fix-in-place vs re-cut now vs fully defer.

### Q4 — What would "good" mean operationally?

Five criteria:

1. **Orthogonal** — no constructor collisions across fragments/core.
2. **Compositional** — values compose in any argument position.
3. **Complete per theory** — no eval-only / bridge-dead ops.
4. **Honest** — no bridge-shaped ctors masquerading as primitives.
5. **Pack-separable** — the pure core (bool/int/string/list/if/let) is free of
   cmake shapes.

## 5. Theory map (measured 2026-08-05)

Ctor counts = declarations in each fragment; total 74 (matches
[`coverage.md`](../coverage.md)). Bridge surface classes:

- **full** — ctors lower to real yc forms (statement/cond-shaped).
- **wrapped-only** — cross the bridge only inside `ESetVar` (value-shaped).
- **passthrough** — bare use crosses as *itself* (identity); stays ycn-shaped,
  so it evals on the yc side via the shared fragment dispatch but **cannot
  emit** unless hoisted into `ESetVar` or an if-cond.
- **bridge-dead** — no `from_normal` case at all (eval-only; the bridge raises).

| Fragment               | Kind            | Ctors | Bridge surface                              |        Manifest        | Notes                                                                                                                                           |
| ---------------------- | --------------- | :---: | ------------------------------------------- | :--------------------: | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| core (`yelu_cmake.ml`) | control         |   —   | full                                        |           —            | `EVar`/`EVarLookup`/`ESetVar`/`ESeq`/`ELet`; surface `EList`/`ERecord`; raw escapes `ECmakeRaw*`. The "Core module" split is `plan.md` piece 1. |
| `bool`                 | pure value      |   3   | passthrough                                 |     ✅ `tiny_bool`      | cmake truthiness via `expect_bool` (coercion, not a type).                                                                                      |
| `int`                  | pure value      |   6   | 3 passthrough, **3 bridge-dead**            |  ✅ `yelu_theory_int`   | `EIntGreater`/`EIntGreaterEqual`/`EIntLessEqual` eval-only.                                                                                     |
| `string`               | pure value      |   7   | `EStringEqual` cond; 6 wrapped-only         | ✅ `tiny_better_string` | The wrapped-only class is the central gap (§6.3).                                                                                               |
| `list`                 | pure value      |   4   | passthrough (+ wrapped)                     |           ❌            | `EList` name collides with core surface `EList`.                                                                                                |
| `path`                 | pure value      |   2   | passthrough (+ wrapped)                     |           ❌            | Minimal subset (filename/normalize) of yc's 44-ctor path surface.                                                                               |
| `if`                   | control         |   1   | full; **value-lossy** standalone            |   ✅ `tiny_better_if`   | `EIfExpr`; `ESetVar`-wrapped lowers to statement-style `ECmakeIfStmt`.                                                                          |
| `store`                | state / control |   4   | full; **bridge-shaped**                     |           ❌            | `ESetCache` dual-writes cache+frame; `EUnsetVar`/`EVarDefined` overlap core; different `eval_case` signature (no `~eval`).                      |
| `cmake_op`             | meta / control  |   7   | full at statement level                     |   ✅ `tiny_cmake_op`    | Arg slots are `expr`, so nested value ctors hit the wrapped-only gap (probe 12).                                                                |
| `target`               | entity          |  20   | mostly full                                 |           ❌            | `ETarget → VTarget` value is vestigial (ops take `expr`/`string` names); `exclude_from_all` missing (known gap).                                |
| `property`             | entity          |   4   | full                                        |   ✅ `tiny_property`    |                                                                                                                                                 |
| `file`                 | effect          |   4   | 3 full; `EFileRead` wrapped-only            |     ✅ `tiny_file`      |                                                                                                                                                 |
| `find`                 | compat          |   1   | full (stub)                                 |     ✅ `tiny_find`      | Whitelist-only `FIND_PACKAGE_MESSAGE_DETAILS`; real search semantics a gap.                                                                     |
| `try`                  | compat          |   1   | full (stub)                                 |      ✅ `tiny_try`      | FALSE-direction only.                                                                                                                           |
| `install`              | effect          |   7   | 6 full; **`EInstallDirectory` bridge-dead** |           ❌            |                                                                                                                                                 |
| `dir`                  | effect          |   1   | full                                        |      ✅ `tiny_dir`      |                                                                                                                                                 |
| `test`                 | effect          |   2   | full                                        |     ✅ `tiny_test`      |                                                                                                                                                 |

Manifest (`name`/`requires`/`provides`) present on 11/16 fragments; **nothing
consumes it** (§6.6).

## 6. Findings — the seams

1. **Flat constructor namespace.** `EList` (core surface value vs normal list
   literal) and `EUnsetVar`/`EVarDefined` (store vs both core evals) collide;
   correctness silently depends on module-open order.
2. **The bridge is a structural rewrite, not a lowering.** Value ctors cross
   only inside `ESetVar` (or as identity passthrough); bare/nested use raises
   `cannot translate unknown yelu_cmake_normal expression` (probes 6, 12, 17).
   There is no temporary synthesis (`message(concat "a" "b")` is inexpressible).
3. **Value-shaped programs have no erasure path.** Pure compositions
   (`EAnd (EIntLess …)`, probe 2) and assigned boolean domain tests
   (`ETargetExists`, probe 11) eval and roundtrip but fail at emit. A
   truthiness value can only reach cmake via if-context hoisting or rejection.
4. **Bridge-dead constructors.** `EIntGreater`, `EIntGreaterEqual`,
   `EIntLessEqual`, `EInstallDirectory`: eval-only, `from_normal` raises.
   Nothing locks this; the 65-test roundtrip suite simply never exercises them.
5. **Value/statement asymmetry is unmodeled.** `EIfExpr` standalone lowers to
   statement-shaped `ECmakeIfStmt` and loses its value (probe 4). The dual-eval
   oracle compares values only, so this class is invisible to the lock.
6. **Manifest metadata is dead.** 11/16 fragments declare
   `name`/`requires`/`provides`; nothing reads it; 5 fragments don't declare it.
7. **The target value class is vestigial.** `ETarget → VTarget` exists but
   target ops take `expr`/`string` name slots inconsistently
   (`EExecutable name:expr` vs `EAddDependencies target:string`).

## 7. Verdict options and recommendation

- **Good as-is** — contradicted by the seams: collisions and bridge-dead ops
  are defects, not taste.
- **Improve in place** (recommended) — keep the fragment architecture; formalize
  fragment kinds (pure value / state / entity / effect / meta / compat) with an
  **enforced** manifest; add a convert-coverage lock; fix the collisions and
  the 4 bridge-dead ctors; decide the value-crossing rule.
- **Re-cut now** — attractive in principle (semantic theories, cmake as compat),
  but a large cost before Y17 exists to tell us which boundaries matter.
- **Leave for future** — acceptable only if the seams are accepted as known
  debt; the risk is that typing rules written against the current shape are
  wasted if we later re-cut.

**Initial recommendation (2026-08-05)**: the decomposition is *good in shape,
incomplete in execution*. Improve in place, and **defer any semantic re-cut
until Y17 typing on the current shape shows where the boundaries actually
hurt** — `plan.md`'s deferral, plus the discipline the probe showed is missing.

## 8. Decision record

Fill this in when the checkpoint is run; it is the output that gates steps 2–6.

```markdown
## Decision — <date>

- **Verdict**: good-as-is / improve-in-place / re-cut / leave-for-future
- **What changed since 2026-08-05** (new probes, new ctors, Y17 progress):
- **Chosen option and rationale**:
- **Scope of work implied** (which of steps 2–5, or none):
- **Accepted risks / known debt**:
- **Open questions** (e.g. Q1–Q4 answers):
```

## 9. Related and gated

- [`plan.md`](plan.md) — the structural theory-fragment split (pieces 1–4).
- [`coverage.md`](../coverage.md) — measured ycn coverage (16 theories / 74
  ctors / 65-test roundtrip lock).
- [`yc_ycn_boundary.md`](yc_ycn_boundary.md) — placement rule (yc = faithful
  erasure; ycn = value/type model).
- [`typed_design.md`](typed_design.md) — Y17 design space; the primary consumer
  of this review's outcome.
- [`extensible_expr_design.md`](extensible_expr_design.md) and
  [`boolean_and_theories.md`](boolean_and_theories.md) — the two open
  decomposition design questions.
- Probe evidence: [`src/bin/debug/debug_ycn_decomp.ml`](../../../src/bin/debug/debug_ycn_decomp.ml).
