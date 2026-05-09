# Yelu Theory Composition Tracker

Status: tiny composition experiment in progress.

This file is the short tracker to update after each step. Durable design context
lives in:

- `doc/yelu_theory_composition_design.md`
- `doc/cmake_cache_semantics.md`
- `doc/yelu_lang_coverage.md`

## Direction

Use `yelu_tiny` as the theory-composition research harness instead of first
refactoring the production `yelu_cmake` pack.

Core migration model:

```text
Yelu1 = tiny core + CMake-shaped surfaces
Yelu2 = tiny core + better/pure Yelu theories

new Yelu code reuses CMake backend:
  Yelu2 -> Yelu1 -> CMake

existing CMake-shaped code can be modernized:
  yelu_cmake AST -> Yelu1 -> Yelu2 -> Yelu1 -> CMake
```

Keep the production parser/compiler/test suite as the compatibility baseline:

```text
src/langs/yelu/lang_yelu_parse.ml
src/langs/yelu/lang_yelu_compile.ml
test/test-runcmake/test_runcmake_yelu.ml
```

## Current Implementation

Main files:

```text
src/langs/yelu_tiny/yelu_tiny.ml
src/langs/yelu_tiny/yelu_tiny_eval.ml
src/langs/yelu_tiny/yelu_tiny_cmake_emit.ml
src/langs/yelu_tiny/yelu_cmake_to_yelu1.ml
src/langs/yelu_tiny/fragments/
```

Tests:

```text
test/test-yelu/test_yelu_tiny_composition.ml
test/test-yelu/test_yelu_cmake_parse.ml
test/test-runcmake/test_yelu_tiny_cmake.ml
```

Implemented tiny fragments:

| Area | Status |
| --- | --- |
| Core | Open `expr`, literals, `EVar`, `ESetVar`, `EUnsetVar`, `ESeq`, `VUnit` effects |
| Store | Pure `EUnsetVar`/`EVarDefined`; CMake `ECmakeUnsetVar`/`ECmakeVarDefined` |
| Bool/if | Shared bool ops; CMake statement-if; Yelu expression-if |
| Int | Add, less-than, equality |
| String | CMake output-var string ops and pure string ops |
| List | Pure list literal/append/get/length and CMake named-list ops |
| Path | First path slice: set, filename, normalize |
| Target Layer A | `add_executable`, target value, `TARGET` predicate |
| Target Layer B | `target_sources`, `target_link_libraries`, `target_include_directories` with visibility |
| Runtime env | Structured `{ vars; targets }` env; target state no longer uses reserved var keys |

Current bridge from production AST to Yelu1 covers representative slices for:

```text
string, store-defined, list, path, target add_executable/existence,
target_sources, target_link_libraries, target_include_directories
```

## Verification Status

Current check commands:

```sh
eval $(opam env) && dune test test/test-yelu/
eval $(opam env) && dune exec test/test-runcmake/test_yelu_tiny_cmake.exe
```

Last verified state:

```text
test/test-yelu/ passed
test_yelu_tiny_cmake passed with 14 tests
```

Verification tracks:

| Track | Current status | Rule |
| --- | --- | --- |
| Semantic equivalence | Active | Compare final `env` and final `value` for Yelu1/Yelu2/lift/lower |
| Parser bridge | Active | Parse production syntax -> old AST -> Yelu1 -> evaluator |
| CMake-backed checks | Active | Add at least one CMake-backed case for each new CMake surface |
| Constructor coverage | Manual | Keep adding focused examples as constructors are added |
| Property/random testing | Later | Add after core/target env settles |
| Formal/SMT proof | Later | Consider only after tiny core and key theories stabilize |

## Current Design State

The target theory now uses a structured environment instead of reserved variable
keys:

```text
env.vars:
  normal Yelu/CMake variables

env.targets:
  target declarations and target-local metadata
```

Target state currently tracks sources, link libraries, and include directories
as visibility-aware records. This is the base for adding more Layer B properties
without accumulating special `__target:*` keys in the normal variable store.

## Next Steps

Recommended order:

1. Add `target_compile_definitions` as the next small Layer B property.
2. Preserve the existing semantic/parser/CMake-backed target tests.
3. Consider a small target-state helper abstraction if another property repeats
   the same visibility-aware append pattern.
4. Only then start build-relevant Layer C with a tiny `add_custom_target` or
   `add_custom_command` slice.

## Deferred Topics

- Cache/env namespaces beyond the current normal-variable store slice.
- `PARENT_SCOPE`.
- Generator expressions as delayed values.
- Build-time artifacts and custom command bodies.
- Fragment-owned parser composition.
- Type annotations and a later `yelu_tiny_typed`.
- Property/generated testing and formal proof.

## Notes

- Old production AST has no dedicated normal-variable `unset(NAME)` constructor.
  Normal unset-like behavior is encoded as `Yvar_set` with an empty value list.
  Dedicated unset constructors exist for cache/env only.
- `target_link_libraries` and `target_include_directories` currently preserve
  `PRIVATE`/`PUBLIC`/`INTERFACE`, but do not model generator expressions or full
  transitive usage requirements yet.
