# Boolean expressions and theories — design discussion

> Status: analysis done, implementation deferred. The current code works (382 tests)
> but the `yelu_cond` merge into `yelu_expr` was architectural overreach.
> This doc captures the conclusions for the next attempt.

## The problem

`yelu_cond` had 24 constructors. Some were pure boolean logic (`not`, `and`, `or`),
some were domain tests (`Yis_defined`, `Yis_target`) that conceptually belong to
var/target theories, and some were comparisons (`Ystrequal`, `Yequal`) that
belong to string/int theories. The type was a grab-bag.

The attempt: merge all 24 into `yelu_expr`, make `if` accept `yelu_expr` directly,
remove `Ytruthy`. Result: 382 tests pass, but the merge was wrong in principle.

## What we learned

### 1. `if`/`while` are consumers of boolean-valued things, not owners

In cmake, booleans are only consumed by `if()`/`while()`. They're never assigned
to variables or passed to commands. `set(VAR str_eq a b)` does not exist.

### 2. Cond is the only expression-level fragment

All 14 fragments consume `T.var`/`T.expr`/`T.target` to embed expressions in
their **statement types**. Cond is the outlier: it produces an **expression-level
type** (`yelu_cond`), not a statement type.

| Fragment | Produces | Needs `T`? |
|---|---|---|
| string, target, file, path, list, find, install, test, try, var, property, dir, cmake_op | statement types | yes (T.expr, T.var) |
| cond | expression type (yelu_cond) | no (if domain tests move out) |
| genex | pure data | no |

### 3. `yelu_cond` should be small and standalone

Stripped of domain tests and comparisons, the core boolean theory is:

```ocaml
type yelu_cond =
  | Ytruthy of yelu_expr      (* gateway: any expr returning Ty_bool *)
  | Ynot of yelu_cond
  | Yand of yelu_cond * yelu_cond
  | Yor of yelu_cond * yelu_cond
```

No `T` parameter needed. No functor. Defined alongside `yelu_expr` in
`lang_yelu_cmake.ml`. The `Ytruthy` gateway connects it to `yelu_expr`: any
expression typed `Ty_bool` can flow into `if`.

### 4. Domain tests and comparisons belong in `yelu_expr`

These produce values (they just happen to return `Ty_bool`):

```ocaml
type yelu_expr =
  | ...
  | Yexpr_is_defined of tc_name     (* var theory: "does this var exist?" *)
  | Yexpr_is_target of tc_name      (* target theory: "does this target exist?" *)
  | Yexpr_exists of yelu_expr       (* file theory: "does this path exist?" *)
  | Yexpr_str_equal of yelu_expr * yelu_expr  (* string theory *)
  | Yexpr_equal of yelu_expr * yelu_expr      (* numeric *)
  | ...
```

They're expression constructors in the closed `yelu_expr` type. The typechecker
maps them to `Ty_bool`. Each theory "owns" them by convention (variant in the
central type + typechecker case), not by open recursion.

### 5. The open-recursive problem

Ideally, each theory would contribute boolean-valued constructors to `yelu_expr`
without modifying the central type. OCaml can't express this without polymorphic
variants (lose exhaustiveness) or GADTs (complex). The practical answer at this
scale: a closed sum type with ~30 constructors, manually maintained. The number
is bounded by the cmake surface area (finite commands).

## Recommended design (next attempt)

```
yelu_expr (values, ~12 constructors)     yelu_cond (booleans, 4 constructors)
  Yexpr_name                                Ytruthy of yelu_expr
  Yexpr_string                              Ynot of yelu_cond
  Yexpr_bool                                Yand of yelu_cond * yelu_cond
  Yexpr_var                                 Yor of yelu_cond * yelu_cond
  Yexpr_is_defined of tc_name
  Yexpr_is_target of tc_name             Yif { cond : yelu_cond; ... }
  Yexpr_exists of yelu_expr              Yc_while { cond : yelu_cond; ... }
  Yexpr_str_equal of yelu_expr * yelu_expr
  Yexpr_equal of yelu_expr * yelu_expr
  Yexpr_matches of yelu_expr * string
  ... (~15 comparison/domain-test variants)
```

- `yelu_expr` holds value expressions including domain tests and comparisons
- `yelu_cond` is the boolean logic layer: not, and, or, plus the gateway
- `Yif` takes `yelu_cond`, not `yelu_expr` directly
- `Ytruthy e` is the bridge: `if e then ...` where `e` types as `Ty_bool`
- Domain tests are `yelu_expr` constructors — owned by their theories
- `lang_yelu_cond.ml` becomes a typechecker module only (no type definition)

## Current state (2026-05-06)

The code currently has the merged state (382 tests pass). The revert to the
design above is deferred. Priority: concrete syntax parser completion.
