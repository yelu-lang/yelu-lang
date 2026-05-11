# yelu_tiny — Module Structure

Code-anchored guide to `src/langs/yelu_tiny/`. For the *why* see `design.md`;
for current open work see `status.md`.

## Top-level files

```
src/langs/yelu_tiny/
├── yelu_tiny.ml              core IR + env + frame stack + helpers
├── yelu_tiny_yelu1.ml        Yelu1 evaluator   (tiny core + cmake-shaped surfaces)
├── yelu_tiny_yelu2.ml        Yelu2 evaluator   (tiny core + idealized theories)
├── yelu_tiny_translate.ml    lift / lower + public eval API
├── yelu_tiny_cmake_emit.ml   Yelu1 IR → cmake text
├── yelu_cmake_to_yelu1.ml    bridge: production yelu_cmake AST → Yelu1 IR
└── fragments/                per-theory + per-surface modules (see below)
```

### `yelu_tiny.ml`

Open `expr` type (`type expr = ..`); shared values (`VString`, `VBool`,
`VInt`, `VUnit`, `VTarget`, …); the `env` record; helpers used by every
fragment.

The env carries four conceptually distinct kinds of state (kept flat for
eval simplicity, grouped by comment):

| Group               | Fields                                                                                                    |
| ------------------- | --------------------------------------------------------------------------------------------------------- |
| Configure script    | `frames` (stack of `{ locals; parent_snapshot; touched }`), `files`                                       |
| Declarations / logs | `project`, `cmake_min_version`, `messages`, `subdirectories`, `includes`, `find_packages`, `try_compiles` |
| Build / test graph  | `targets`, `custom_targets`, `custom_commands`, `target_properties`, `testing_enabled`, `tests`           |
| Install             | `install_rules`                                                                                           |

The frame stack models cmake's hybrid lexical-feel-with-dynamic-back-door
scope: snapshots on push, plus a `touched` set to distinguish "never
modified" from "explicitly unset" for `block(PROPAGATE)` and
`return(PROPAGATE)`. Three control-flow exceptions live here:
`Break_loop`, `Continue_loop`, `Return_function { env_at_return;
propagated }`. See `../cmake/scope_and_control_flow.md`.

### `yelu_tiny_yelu1.ml` / `yelu_tiny_yelu2.ml`

Each is a small `eval_expr env expr` driver that dispatches to the
appropriate fragment's `eval_case`. Yelu1 calls the `yelu_surface_cmake_*`
fragments; Yelu2 calls the `yelu_theory_*` fragments. The split exists
because the original combined evaluator passed 900 lines and mixed four
concerns. Both end on the same shared cases (literals, `ELet`, control
flow), with a final `fail "unknown ..."` for unmatched constructors.

### `yelu_tiny_translate.ml`

Public API: `eval_yelu1_expr`, `eval_yelu2_expr`, `lift_yelu1_to_yelu2`,
`lower_yelu2_to_yelu1`. Lift/lower are constructor-by-constructor
isomorphisms — most cases are mechanical (rename `ECmakeFoo` →
`EFoo`) but a few (e.g. cmake `ECmakeOption` → tiny `ESetVar`) do real
shape change.

### `yelu_tiny_cmake_emit.ml`

`emit_expr_impl ~env e` produces cmake text. Threads a substitution env so
that `ELet`-bound names resolve to their values at emit time instead of
emitting `${name}`; see [phase 2a in design.md]. Two arg-style helpers,
`arg` and `target_arg`, render expressions in script-positional vs.
target-name context — target names render unquoted by convention.
Conditions go through `cond` / `cond_atom` (separate because cmake's
`if(A AND B)` needs parens to disambiguate from operators).

### `yelu_cmake_to_yelu1.ml`

Translates the production `Lang_yelu_cmake` AST (typed, stringly-cmake)
into Yelu1 IR. The bridge is the demand signal for what tiny needs to
cover: every `_ -> fail "unsupported ..."` is a constructor that needs a
paired surface + theory + emit + lift/lower added. R6 closed the parser
attrition; R3 (genex) is the next bridge demand.

## Fragments

```
src/langs/yelu_tiny/fragments/
├── yelu_theory_<theory>.ml          idealized theory shape (Yelu2)
└── yelu_surface_cmake_<theory>.ml   cmake-shaped surface (Yelu1)
```

For each domain there is *usually* a matched pair. The theory module
defines a small, value-oriented set of constructors; the surface module
defines the cmake-shaped equivalents (often with output-variable side
effects). `translate.ml` maps between them. A few asymmetries by design:

- `yelu_theory_bool` / `yelu_theory_int` — pure, shared between Yelu1
  and Yelu2; no matched cmake-surface module because cmake's bool / int
  ops *are* the pure ops.
- `yelu_surface_cmake_if` — cmake-only statement-if shape; the theory
  side uses tiny's core `EIf` expression form.

### Theory list

`Kind` distinguishes a real theory (value-oriented, eval is meaningful) from
a cmake compatibility surface (emit-faithful, eval delegates to real cmake).
`Mixed` = real for the common ops, compat for the long tail. See
`design.md`'s "Fragment kinds" section.

| Theory     | Kind   | Surface lines | Theory lines | Notes                                                                                                     |
| ---------- | ------ | ------------: | -----------: | --------------------------------------------------------------------------------------------------------- |
| `bool`     | real   |             — |           37 | shared: and / or / not                                                                                    |
| `int`      | real   |             — |           45 | shared: add / less / equal                                                                                |
| `if`       | real   |            31 |           23 | cmake statement-if vs tiny expression-if                                                                  |
| `store`    | real   |            81 |           11 | var set / unset / PARENT_SCOPE / option; cache / env deferred                                             |
| `target`   | real   |           181 |          275 | add_executable, add_library, target_* visibility-aware                                                    |
| `install`  | real   |           105 |          102 | install(TARGETS / FILES / EXPORT) + package-config writer                                                 |
| `test`     | real   |            19 |           19 | enable_testing, add_test                                                                                  |
| `dir`      | real   |            31 |           15 | add_subdirectory + dir-level include/compile/link commands; scope isolation deferred                      |
| `string`   | mixed  |           224 |           61 | core (concat/replace/length/equal): real; regex / timestamp / uuid / json: emit-faithful stubs            |
| `list`     | mixed  |           105 |           31 | core (append/get/length/join/sort): real; advanced transforms: emit-faithful                              |
| `path`     | mixed  |           130 |           44 | core (set / normalize / get-filename): real; native/cmake conversion + many subcommands: emit-faithful    |
| `file`     | mixed  |           131 |           41 | in-memory fs for write / read / exists: real; glob / copy / many fs ops: emit-faithful                    |
| `property` | mixed  |            80 |           47 | target-property: real; global / source / test / directory scopes: emit-faithful                           |
| `cmake_op` | compat |           390 |          103 | project / message / math / include / function / macro / block / while / foreach / execute_process — broad surface bucket |
| `find`     | compat |            37 |           13 | find_package / library / path / program / file — eval is placeholder; real semantics depend on host       |
| `try`      | compat |            60 |           20 | try_compile + try_run — eval stubs result; real probe runs only when emitted cmake script runs            |

Shared theories (`bool`, `int` — no surface module) are used directly by
both evaluators.

### Fragment shape

Every fragment file follows the same skeleton:

```ocaml
open Base
open Yelu_tiny
(* open Yelu_theory_<...> if it builds on another theory *)

type expr +=
  | ECmakeFoo of { ... }       (* surface *)
  | EFoo of { ... }            (* theory *)

let eval_case ~eval env = function
  | ECmakeFoo { ... } ->
      (* compute new env + return value *)
      Some (env', VUnit)
  | _ -> None                  (* let the next fragment try *)
```

The `~eval` parameter is the recursive evaluator passed in by
`yelu_tiny_yelu1.ml` / `yelu_tiny_yelu2.ml`. The `Some / None` shape
lets each fragment claim only the constructors it owns; the driver tries
fragments in a fixed order until one matches.

## Adding a constructor — the 5-step recipe

For a new cmake command `cmake_thing(arg1 arg2 OUT out)`:

1. **Surface** in `fragments/yelu_surface_cmake_<theory>.ml`:
   add `ECmakeThing of { arg1 : expr; arg2 : expr; out : string }`
   plus an `eval_case` arm.
2. **Theory** in `fragments/yelu_theory_<theory>.ml`:
   add `EThing of { ... }` plus its `eval_case` arm (often a thin
   re-shape of the surface eval).
3. **Bridge** in `yelu_cmake_to_yelu1.ml`:
   add a match arm under the appropriate `Y<theory>_*` group that
   produces `ECmakeThing { ... }` from the production AST.
4. **Emit** in `yelu_tiny_cmake_emit.ml`:
   add a match arm that produces the cmake text line(s).
5. **Lift / lower** in `yelu_tiny_translate.ml`:
   one arm in `lift_yelu1_to_yelu2` (`ECmakeThing → EThing`) and one
   in `lower_yelu2_to_yelu1` (`EThing → ECmakeThing`).

Then add at least one test in `test/test-yelu/test_yelu_tiny_*.ml` and,
if the construct interacts with cmake's runtime semantics, one
cmake-backed test in `test/test-runcmake/test_yelu_tiny_cmake.ml`.

For pure-passthrough constructors (no real eval semantics — emit and
hope cmake handles it) the eval case can return `Some (env, VUnit)`;
mark the case with a comment noting the deferral.

## Tests

```
test/test-yelu/
├── yelu_tiny_test_helpers.ml         shared assertions / fixtures
├── test_yelu_tiny_lift_lower.ml      Yelu1 ↔ Yelu2 roundtrip            (65)
├── test_yelu_tiny_bridge.ml          production AST → Yelu1             (43)
├── test_yelu_tiny_steps.ml           tutorial v1 step1–12 + extras      (19)
├── test_yelu_tiny_emit.ml            Yelu1 IR → cmake text              (3)
├── test_yelu_tiny_function.ml        F2 dynamic-scope function          (14)
├── test_yelu_tiny_foreach.ml         foreach scope + loop variants       (5)
└── test_yelu_tiny_block_return.ml    block / return / PARENT_SCOPE      (26 probes)
```

```
test/test-runcmake/
├── test_yelu_tiny_cmake.ml           tiny → real cmake configure       (40)
└── test_runcmake_yelu.ml             stdout-equiv against reference     (50)
```

Parser tests (`test/test-yelu/test_yelu_cmake_parse.ml`, 170) and
compile tests (`test/test-yelu/test_yelu_compile.ml`, 194) inline a
bridge assertion: parse → bridge → emit non-empty. R6 / R4 closed both
attrition lists.

## Cross-references

- `design.md` — the *why* behind the two-axle model, theory invariants,
  let-binding architecture, F2 function semantics.
- `../worklog_2026_05.md` — chronological history of the harness.
- `../cmake/scope_and_control_flow.md` — frame-stack design, 26 probes.
- `../cmake/cache_semantics.md` — cache namespace deferred behavior.
- Bridge attrition phases R1–R7 (R7 reframed as Y17) → `status.md`.
