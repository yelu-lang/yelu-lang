# Design problem: extensible expression types in a theory-based language

> Originally drafted in the legacy IR era (`lang_yelu_*` modules in
> `src/langs/yelu_legacy/`). The architectural question carries
> forward unchanged into the post-retirement `yelu_cmake` /
> `yelu_cmake_normal` IR: extensible expression types is still the
> open design question, and informs Y17. The code snippets below use
> the legacy names for historical fidelity; see `yelu_theory/plan.md`
> for the current structural-split plan that addresses parts of this.

**Context.** I'm building yelu, a programmable configuration shell language with a
two-layer architecture: a *control side* (binding, branching, iteration) and
*theories* (domain-specific operations over typed namespaces). The first pack
targets cmake and has 14 theories: var, target, string, path, file, list, find,
install, test, try, cond, dir, property, cmake_op.

Each theory is an OCaml functor pair `Make_*_op(T) / Make_*_check(T)` over a
shared `LANG_TYPES` substrate. The pack (`lang_yelu_cmake.ml` in the legacy IR)
instantiates all 14 and composes the top-level statement sum type `yelu_stmt`.

```ocaml
(* In lang_yelu_cmake.ml — legacy IR *)
type yelu_stmt =
  | Ys_string of yelu_string_stmt   (* string theory *)
  | Ys_list of yelu_list_stmt       (* list theory *)
  | Ys_target of yelu_target_stmt   (* target theory *)
  | ...
  | Yif of { cond : yelu_cond; then_ : yelu_stmt; else_ : yelu_stmt option }
  | ...
```

The statement type composes cleanly because each theory contributes its own
variant. But **expressions are different.**

**The problem.** I currently have two separate types for expression-level values:

```ocaml
(* Simple value expressions — 4 constructors, stable *)
type yelu_expr =
  | Yexpr_name of tc_name     (* typed cmake named entity *)
  | Yexpr_string of yc_string (* path, string, eval, keyword *)
  | Yexpr_bool of bool        (* boolean literal *)
  | Yexpr_var of yelu_var     (* compile-time variable *)

(* Boolean-valued condition expressions — 24 constructors, growing *)
type yelu_cond =
  | Ytruthy of yelu_expr
  | Ynot of yelu_cond
  | Yand of yelu_cond * yelu_cond
  | Yor of yelu_cond * yelu_cond
  | Ystrequal of yelu_expr * yelu_expr
  | Yequal of yelu_expr * yelu_expr
  | Ymatches of yelu_expr * string
  | Yis_target of yelu_expr
  | Yis_defined of yelu_expr
  | Yexists of yelu_expr
  | Yis_directory of yelu_expr
  | ...
```

The separation is artificial. `Yexpr_bool of bool` is already a boolean
expression. `Yis_defined` and `Yis_target` conceptually belong to the *var* and
*target* theories, not to cond. String and numeric comparisons could belong to
string/numeric theories. Yet all of them live in `yelu_cond` because that's the
only type `if` accepts:

```ocaml
| Yif of { cond : yelu_cond; ... }
```

**The desired state.** I want `if` to accept any boolean-typed expression:

```ocaml
| Yif of { cond : yelu_expr; ... }
```

where `Yexpr_bool`, `Yexpr_not`, `Yexpr_strequal`, `Yexpr_is_defined`, etc. are
all just `yelu_expr` constructors that the typechecker maps to `Ty_bool`. Each
theory can contribute boolean-valued expression constructors: var theory adds
`Yexpr_is_defined`, target theory adds `Yexpr_is_target`, file theory adds
`Yexpr_exists`, etc.

**The architectural tension.** Statements compose because `yelu_stmt` is a
closed sum type at the pack level — each theory contributes variants, and
OCaml's pattern matching handles the composition by hand. But expressions
(`yelu_expr`) are a single closed variant. If I merge `yelu_cond` into
`yelu_expr`, the expression type grows to 28+ constructors. Adding a new
boolean-valued expression from a new theory means modifying the central type
definition, plus the typechecker, compiler, wellform pass, and parser — each in
their own pattern matches.

So the design question is:

**How should a language with per-theory functors handle an extensible expression
type, where multiple theories contribute constructors that share a common
semantic property (e.g., "evaluates to bool")?**

Options considered:

1. **Closed sum, manually maintained.** All expression constructors in one type.
   Simple, zero framework overhead, but every theory addition touches the
   central type. Acceptable at current scale (14 theories, ~30 expression
   constructors).

2. **Extension slot with sub-type.** `Yexpr_cond of yelu_cond` stays as a slot
   in `yelu_expr`. Boolean ops live in `yelu_cond`. Domain tests
   (`Yis_defined`, etc.) move into `yelu_cond` as well — they're boolean ops.
   `yelu_expr` stays small (4 + 1 slot). `yelu_cond` grows to absorb all
   boolean-valued constructs. Same manual maintenance, but the surface area
   of change is `yelu_cond` only, not `yelu_expr`.

3. **Open/extensible variants.** OCaml has polymorphic variants but they lose
   exhaustiveness checking. Row types / first-class cases exist in research
   languages (OCaml modular implicits, Scala 3 enums, Haskell
   `Data Types à la Carte`) but are heavy for the current scale.

4. **Per-theory expression fragments with pack-level GADT.** Each theory
   defines its own expression sub-type, and the pack ties them together with
   a GADT. Rejected earlier (see `yelu_typed_design.md`) because cmake's type
   lattice has constraints OCaml can't express at the type level.

**Constraints:**
- 14 theories, each should be independently testable
- The typechecker, compiler, wellform pass, concrete syntax parser all need to
  handle every expression constructor
- OCaml with Base, no external framework
- Currently 362 passing tests; refactors must be regression-safe
- The system should be understandable by a single developer
- A second target pack (json/nix) is planned but not started

What's the right architecture for this scale?
