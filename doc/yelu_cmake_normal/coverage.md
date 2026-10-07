# ycn Coverage Status

> The ycn (`yelu_cmake_normal`) parallel to yc's
> [`lang_coverage.md`](../yelu_cmake/lang_coverage.md). A **factual snapshot**
> of what the normalized form covers today, measured from the code — not a plan.
> Design/rationale live in [`design/`](design/) and [`typing/`](typing/); the
> surface plan is [`ycn_concrete_syntax.md`](ycn_concrete_syntax.md).

## Where ycn sits

ycn is the **normalized form** on the shared extensible-variant core. It is
**not on the production emit path** — production is `yc → yelu_cmake_emit →
Lang_cmake → text`. ycn is reached only through the `yc ↔ ycn` bridge
(`yelu_cmake_convert`), and is the substrate future analysis / typing (Y17) will
operate on. So "coverage" here means **convert + eval**, not emit-to-text.

```
        parse            to_normal            (future: type / analyze)
 .yc  ────────►  yc  ◄──────────────►  ycn  ────────► …
                  │     from_normal
                  ▼ yelu_cmake_emit  (production)
                cmake text
```

## Coverage matrix (measured)

| Axis                        | Status              | Detail                                                                                                                                                                                             |
| --------------------------- | ------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Theories**                | 16                  | the 14 yc theories + `bool` + `int` (theory primitives the cmake form folds into command shapes). Fragments: `yelu_cmake_normal_<theory>.ml`.                                                      |
| **Constructors**            | 74                  | `E*` across the 16 normal fragments.                                                                                                                                                               |
| **Convert — `to_normal`**   | all theories        | `yc → ycn` (`yelu_cmake_convert.ml`, ~1,750 LOC total).                                                                                                                                            |
| **Convert — `from_normal`** | all theories        | `ycn → yc`.                                                                                                                                                                                        |
| **Eval**                    | 16 / 16 theories    | every normal fragment defines an `eval_case`; dual evaluator is `yelu_cmake_normal_eval.ml`.                                                                                                       |
| **Roundtrip lock**          | **65 tests, gated** | `test_yelu_lift_lower.ml` — 31 `yc→ycn`, 32 `ycn→yc`, 2 full roundtrip. Runs under `dune test` (unlike `make cmake-commands`), so a convert regression **fails the build**. Spans all 16 theories. |

The almost-roundtrip property is `from_normal ∘ to_normal ≡ identity-modulo-emission`.

## Not covered (by design, today)

- **Concrete syntax** — ycn has **no surface parser or printer**. This is the
  next big rock ([`ycn_concrete_syntax.md`](ycn_concrete_syntax.md),
  status.md § Now). yc has a full surface (`Yc_cst_parse` → lower); ycn has none.
- **Direct ycn → cmake emit** — none; ycn lowers to yc first
  (`from_normal`), then yc emits. There is no `ycn_emit`.
- **Typing** — Y17. The normal form is the intended home for a typing pass
  ([`typing/typed_design.md`](typing/typed_design.md)); none exists yet.
- **Wellform** — the six wellform checks run on yc/CST, not ycn.

## Known gaps (ycn coverage registry)

Parallel to yc's [emit/semantic gap registry](../yelu_cmake/lang_coverage.md).
A gap leaves the table when its roundtrip case passes.

| Construct                                            | Symptom                                    | Root cause                                                                                                                        | Status                                                                                                                                                                                                                                |
| ---------------------------------------------------- | ------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `exclude_from_all` on `add_library`/`add_executable` | flag lost across `to_normal`/`from_normal` | `EExecutable`/`ELibrary` (normal target fragment) don't carry the field; `to_normal` drops it, `from_normal` reconstructs `false` | ⬜ **deferred** — fix mirrors the yc-side change (add the field to the 2 ctors + thread `convert.ml`/`normal_target.ml`, ~30 sites; w9 forces every read site). Do with the ycn agenda. Discovered 2026-07 via the cmake-commands dig. |

## How ycn coverage is tracked

- **`test_yelu_lift_lower.ml` (65 tests) is the live lock** — in `dune test`, so
  convert regressions fail the build. This is *stronger* than yc's
  build-verification, which is manual (`make cmake-commands`).
- New ycn constructors / convert arms should add a roundtrip case here; a lossy
  convert surfaces as a roundtrip mismatch.
- This registry records what the roundtrip lock does **not** yet guarantee
  (e.g. the `exclude_from_all` field, which no roundtrip case exercises).
