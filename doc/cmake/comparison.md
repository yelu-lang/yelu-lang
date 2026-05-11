# CMake Equivalence — Language, Semantics, and Test Coverage

This document is the theory companion to `yelu_infra_test.md`. It grounds the
yelu equivalence question in the properties of cmake as a language, defines the
PL vocabulary, states what each equivalence level proves, and maps each level to
the concrete test observations in the harness. For symbolic/SMT approaches to
full equivalence see `equiv_research.md`.

---

## CMake as a language

CMake's configure-time language (CMakeLists.txt) is a restricted imperative
language with these properties relevant to equivalence checking:

- **Straight-line code + boolean conditionals** — `if(COND) … else() … endif()`;
  no dynamic dispatch, no first-class functions.
- **String-typed state** — all variable values are strings; lists are
  semicolon-joined strings. No numeric tower, no booleans at the value level.
- **6 independent namespaces** — TARGET, Variable, Cache, COMMAND, TEST, POLICY.
  A name like `foo` can exist in all six simultaneously; they never collide.
  Empirically confirmed via 24 namespace probes.
- **Finite iteration** — `foreach` is over a finite list; no unbounded loops.
- **Mutable, scoped state** — `set(VAR val)` overwrites; scope is
  per-directory / per-function with `PARENT_SCOPE` escape.
- **Impure commands** — `find_package`, `execute_process`, `file(READ …)`
  are side-effectful and not symbolically encodable without stubs.
- **Option variables** — `option(FLAG "…" ON)` declares a boolean cache entry.
  These are the *inputs* to a configure run; users set them at cmake invocation
  time. A program with n option variables has 2^n distinct configurations.

The configure-time language (the part yelu targets) is mostly decidable: you can
enumerate all `option()` combinations and run cmake. The build-time part (compiler
invocations, linking) is a separate execution stage.

---

## Entities and actions in PL terms

The pipeline mirrors a C-with-macros model: configure-time is the "macro" layer;
the build system is the "C runtime" layer.

| cmake term                                       | PL term                               |
| ------------------------------------------------ | ------------------------------------- |
| program text (`CMakeLists.txt`)                  | `src`                                 |
| user-supplied cache / option variables           | `input : name → string`               |
| configure-time state (variables, targets, props) | `env : name ⇀ val`                    |
| build graph (`Makefile` / `build.ninja`)         | `build_spec`                          |
| compiled binary or library                       | `artifact`                            |
| `cmake -P script.cmake`                          | `eval : src → env`                    |
| `cmake -S src -B bld` (configure)                | `compile : src × input → build_spec`  |
| File API codemodel query                         | `inspect : build_spec → env`          |
| `cmake --build bld`                              | `run : build_spec → artifact set`     |

The 6 namespaces mean `env` is a product of 6 partial maps; yelu's typed AST
(`Ycvar`, `Ytarget`) selects the right component at compile time. Impure commands
(`find_package`, `execute_process`) are opaque side effects — not captured in
`env` and must be stubbed for symbolic analysis.

**Why `src` is stringly-typed**: cmake's real AST (`cmListFileArgument` in
`Source/cmListFileCache.h`) is completely untyped — every command receives a
`vector<cmListFileArgument>` where each argument carries only a quote-delimiter
tag (`Unquoted | Quoted | Bracket`) and a string value. There are no var, target,
or value types at the cmake level. The cmake layer in yelu mirrors this exactly;
all typed constructs live in the yelu layer and are erased to `arg list` by the
compiler.

---

## Equivalence levels

Two cmake programs P1 and P2 are equivalent at a given level when:

| Level    | Equivalence assertion                                         |
| -------- | ------------------------------------------------------------- |
| `src`    | `P1 = P2` (syntactic equality after normalization)            |
| `interp` | `compile(P1, i) ≅ compile(P2, i)` for a given input `i`      |
| `run`    | `run(compile(P1, i)) = run(compile(P2, i))` for a given `i`  |

`src` is purely syntactic — it rejects semantically equivalent programs with
different statement order or formatting. `interp` and `run` are semantic: they
test observable behavior, not text.

**The fundamental gap**: both `interp` and `run` hold for a given concrete `i`.
With n option variables there are 2^n inputs; none of these levels can prove
equivalence for all configurations. Closing that gap requires symbolic methods;
see `equiv_research.md`.

---

## Test harness: observations

Concrete test variants are different *observations* of `interp` and `run`. The
semantic level is the same; what differs is which part of cmake's output is
inspected, and whether one or two programs are under test:

| Test variant  | Level    | cmake action          | What is compared                                   | Scope                   |
| ------------- | -------- | --------------------- | -------------------------------------------------- | ----------------------- |
| unit tests    | `src`    | none (OCaml only)     | emitted `src` text (Alcotest string match)         | all yelu programs       |
| `script`      | `interp` | `eval`                | stdout of one program vs. expected pattern         | scripting, no targets   |
| `script-pair` | `interp` | `eval` ×2             | stdout of ref vs. yelu (observational equivalence) | scripting, no targets   |
| `configure`   | `interp` | `compile`             | selected `input` bindings in `CMakeCache.txt`      | projects with targets   |
| `file-api`    | `interp` | `compile` + `inspect` | full `env` (targets, flags, deps) from codemodel   | projects with targets   |
| `build`       | `run`    | `compile` + `run`     | artifact set                                       | projects with targets   |

`script-pair` is strictly stronger than `script`: it checks two programs against
each other rather than one against a fixed expected string.
`file-api` is strictly stronger than `configure`: `inspect` returns the full `env`
(target graph, compile flags, link deps), not just selected cache variables.
`build` is needed despite `file-api` because generator expressions (`$<…>`) are
build-time and do not appear expanded in codemodel JSON.

`configure`/`build`/`file-api` do not apply to scripting tests: `inspect`
(codemodel-v2) only has content when targets exist. Pure scripting programs
(`eval`) produce no targets.

---

## Inactive levels

**`ast`** — OCaml structural equality on `Lang_cmake.exp`. Finer than `src`
(format-independent), coarser than `interp`. Useful for isolating PP regressions
from semantic changes. Not active.

**`symbol`** — `nm -D` inspection of shared library exports: a `run`-level
observation at ABI granularity. Blocked: nm infra not wired into the test suite.

---

## File API recipe

```
mkdir -p build/.cmake/api/v1/query
touch build/.cmake/api/v1/query/codemodel-v2
touch build/.cmake/api/v1/query/cache-v2
cmake -S . -B build
# replies appear in build/.cmake/api/v1/reply/
```

`"id"` fields in codemodel replies are content hashes derived from the build
directory path — strip them before diffing. `cache-v2` is path-independent and
can be compared directly.
