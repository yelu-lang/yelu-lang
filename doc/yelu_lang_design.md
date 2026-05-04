# Yelu Language Design

Research directions and open design questions. For current implementation state see
`yelu_lang_coverage.md`. For done history see `worklog_2026_04.md`.

---

## Language Architecture — Core vs Pack

**Motivation**: as yelu grows beyond cmake, the language-agnostic parts should be
separable from the cmake-specific parts. A user targeting JSON, Nix, or Dockerfile
should reuse the same core and import only the relevant pack.

```
yelu-core                      cmake-pack
──────────────────────         ─────────────────────────────────────
bool, int, string              target, cmake_list, cmake_cvar
list<T>, dict<K,V>             Ycvar_bool / _string / _path / _internal
option<T>, result<T,E>         find_library, find_package
let, if, for, match            foreach (configure-time)
fun, module, import            generator expression $<...>
                               compile_to_cmake : program → cmake_ast
```

The cmake-pack is imported as a module: `import cmake_pack as cmake`. A `yelu-json`
pack would expose a different API — same core language, different primitives and
lowering target.

**Analogy to existing languages**:

| Language       | Core                    | Pack/Library                    |
| -------------- | ----------------------- | ------------------------------- |
| Nix            | nix expression language | nixpkgs (package collection)    |
| OCaml          | core language + Stdlib  | opam libraries                  |
| Haskell        | Prelude + base          | hackage packages                |
| yelu (planned) | yelu-core               | cmake-pack, json-pack, nix-pack |

### Fragment composition

The `fragments/` directory introduces a second axis alongside core/pack:
**atomic fragments vs. compound languages**. But at the interface level, the
distinction dissolves — both satisfy the same structural contract:

- Syntax: AST constructors (a functor over `LANG_TYPES`, or a concrete type)
- Type fragment: what types its expressions produce and consume (`yelu_type`)
- Checker: a function from program to `type_error list`
- Semantics: an interpreter or compiler to a target language

A compound language (`cmake-pack`) is just a language that `include`s several
fragments at its substrate. A fragment (`lang_yelu_cond`, `lang_yelu_genex`) is
a language with a restricted domain. From the outside — from the perspective of
a type checker, an interpreter, or a user — they are indistinguishable in kind.

The practical implication: a `LANG` signature (OCaml module type) that any
fragment or compound language satisfies. Composition is then one language
including another, not a special operation. The `fragments/` label is a
construction-time convenience; at runtime they are all just languages.

This echoes the SMT-LIB vocabulary (theories, logics, languages) where the
same interface contract applies at every level of composition, and a "logic"
is simply a named combination of theories under a fixed set of constraints.

Linguistic analogy (not adopted as terminology): a compound pack resembles a
pidgin — assembled from contributing fragments, each with its own grammar,
unified into a working whole. Two future cmake styles (`fp_cmake`,
`imperative_cmake`) would be different compounds built from largely the same
fragments combined differently.

---

## Primitive Types — Planned yelu-core Types

Compile-time types (known to yelu before cmake runs). They correspond to what cmake
arguments ultimately carry, but with semantic distinctions cmake collapses into strings.

| yelu type   | Meaning                             | cmake lowering                          |
| ----------- | ----------------------------------- | --------------------------------------- |
| `bool`      | true/false                          | `ON`/`OFF`                              |
| `int`       | integer                             | bare string                             |
| `string`    | generic string                      | quoted/bare arg                         |
| `file`      | file path                           | quoted arg (cmake expects path)         |
| `dir`       | directory path                      | quoted arg                              |
| `name`      | cmake name (variable, target, test) | bare arg — context determines namespace |
| `list<T>`   | compile-time typed sequence         | `arg list` → unrolled or `"a;b;c"`      |
| `option<T>` | present or absent                   | `Some` → arg, `None` → omitted          |
| `dict<K,V>` | key-value map                       | property pairs, cmake cache             |

**Open questions**:
- Should `list<T>` allow mixed-type lists? (cmake's lists are untyped strings)
- Should `dict` be ordered? cmake property lists are ordered; cmake cache is not.
- Is `dag<T>` needed, or derived from `list<(T, list<T>)>`? cmake's target dependency
  graph is a DAG — a typed collection enables static cycle detection.

## Configure-time Types — cmake-pack Additions

Types that survive compile time and exist at cmake configure time:

| cmake-pack type  | Meaning                                                | Tier                                   |
| ---------------- | ------------------------------------------------------ | -------------------------------------- |
| `target`         | cmake target handle (exe / lib / interface)            | already in yelu as `Ytarget`           |
| `cmake_list`     | cmake Variable holding a `;`-joined list               | Tier 2 — needed for `foreach IN LISTS` |
| `Ycvar_normal`   | last-write-wins normal variable                        | Tier 5                                 |
| `Ycvar_bool`     | option() / CACHE BOOL — first-write-wins               | Tier 5                                 |
| `Ycvar_path`     | CACHE PATH — find_* result, cached across reconfigures | Tier 5                                 |
| `Ycvar_internal` | CACHE INTERNAL — not shown in cmake-gui                | Tier 5                                 |

---

## Target Type Model (open design questions)

### Handle vs primitive

`Ytarget` is a *reference* into cmake's TARGET namespace, not a value.
`Yc_add_library` constructs a target and returns an `exp`; `Ytarget "foo"` is
what you pass around afterward — a typed pointer. The two roles are currently
conflated: there is no yelu construct that *introduces* a `yelu_target` binding
and returns it as a typed value. The right model is:

```
let foo : static_lib = add_library "foo" [src "foo.c"]   -- introduces a typed handle
target_link_libraries app [Private foo]                  -- consumes it
```

vs the current state where `Yc_add_library` is a statement and `ytval "foo"` is
an unverified string cast to target type. The gap: declaration and reference are
not connected — yelu can't tell whether `ytval "nonexistent"` is valid.

**Future paths**: static scope analysis (track declared targets, reject unknown
references) or runtime guard insertion (`if(NOT TARGET foo) message(FATAL_ERROR
...)`) generated automatically at use sites.

### Library forms as distinct nominal types

`library_type` is currently a single enum (`Lib_static | Lib_shared | Lib_object
| Lib_interface | ...`). But INTERFACE, OBJECT, and STATIC/SHARED impose
structurally different constraints that are checkable at the yelu layer:

| Form | Has sources | PRIVATE items meaningful | Build artifact |
|------|-------------|--------------------------|----------------|
| `static_lib` / `shared_lib` | ✓ | ✓ | ✓ |
| `object_lib` | ✓ | ✓ | — (`.o` pool, no archive) |
| `interface_lib` | — | — | — |

With a single enum, `target_link_libraries(iface PRIVATE foo)` where `iface` is
an INTERFACE library is accepted by yelu — but PRIVATE items on an INTERFACE
target propagate to no one, making the call silently wrong. With distinct nominal
types (`interface_lib`, `object_lib`, `static_lib`), yelu can reject the call at
the use site: `target_link_libraries` on an `interface_lib` would only accept
`Interface` items, not `Private` or `Public`.

OBJECT libraries have their own use pattern: they are consumed via
`$<TARGET_OBJECTS:name>` as a source argument to other targets, not via
`target_link_libraries`. A distinct `object_lib` type enables yelu to enforce
this and reject `target_link_libraries(app myobj)` as a type error.

**Proposed direction**: replace `library_type` enum with distinct target types
at the yelu surface. The cmake-pack lowering handles the `add_library(... OBJECT
...)` emission; the yelu layer enforces the structural rules per form.

### Propagation graph (future research)

`target_link_libraries(app PUBLIC mylib)` does more than link — it propagates
`mylib`'s PUBLIC include directories, compile definitions, and transitive
dependencies into `app`. Currently yelu types the *call site* (enforces
PUBLIC/PRIVATE/INTERFACE keywords) but treats the propagation semantics as
opaque to cmake.

The research direction: statically track which properties flow along PUBLIC
edges, enabling yelu to answer questions like "does `app` transitively depend on
`openssl`?" or "which targets expose `include/` to their consumers?". This
connects to Tier 6 (if yelu owns the build graph) and Tier 7 (if propagation
facts are stage-annotated values). Not a near-term priority — the open question
is how much of the cmake property propagation model can be encoded as types
without requiring a full symbolic interpreter.

---

## Settled Design Decisions (2026-04-14)

These are resolved — do not re-open without new evidence.

**1. Multi-variable iteration (`ZIP_LISTS`) → derived from `zip`**

cmake's `foreach(x y IN ZIP_LISTS l1 l2)` is not a special construct; it is
`zip(l1, l2)` with tuple destructuring in `for`. yelu-core provides:

```
zip : list<A> -> list<B> -> list<(A, B)>

for (x, y) in zip(sources, headers) do ...
```

The cmake-pack lowering targets `Foreach_in` with `ZIP_LISTS`. No new syntax in
yelu-core needed — multi-var iteration is a library function, not a keyword.

**2. Monomorphic typed lists as the first type system**

Full polymorphism (`list<T>` with type variables) is deferred. The first step is a
fixed set of monomorphic list types: `string_list`, `file_list`, `dir_list`,
`target_list`, `name_list`. Each is a distinct type; cross-use (`link_lib [a_file]`)
is a type error. Target: ≤12 cases, one per `yarg` variant.

**3. FP-flavored core — no `return` keyword in yelu-core**

yelu-core is expression-oriented: every construct is an expression, functions return
their last expression. `Yc_return`/`Yc_break`/`Yc_continue` are cmake-pack primitives
that emit cmake control flow — not yelu-core control flow.

**4. From cmake examples to core types — inductive approach**

Each real cmake project translated through yelu reveals missing core types. Current
gaps from step1–12 translations:
- `list(APPEND VAR items)` → mutating a `cmake_list` (configure-time mutation)
- `foreach(x IN LISTS VAR)` → iterating a `cmake_list`
- `set(VAR val CACHE BOOL "doc")` → `Ycvar_bool` with a doc string

The RunCMake tests are the primary source for discovering unexpressed patterns.

---

## cmake Policy as Scope-Local Versioning (context for Y11)

cmake policies are unlike versioning in other language ecosystems. In Python/Node/Ruby,
a version is a property of the *process* — the whole program runs under one interpreter,
and env tools (pyenv/nvm/rbenv) isolate projects by swapping the binary. In cmake,
`cmake_minimum_required` activates a policy set *within* the running process, and
`cmake_policy(PUSH/POP)` scopes policies to call stacks — so two subdirectories in the
same configure session can simultaneously operate under different behavioral versions.
The "version" is a property of the *scope*, not the process.

Consequences for yelu:

- **Top-level programs**: yelu can emit a `cmake_minimum_required` preamble that
  activates all policies its constructs need. This is the Y11 case — solvable.
- **Subdirectory inclusion**: when yelu-generated code is `add_subdirectory`'d into a
  larger cmake project, the parent's policy stack is external state yelu cannot see or
  control. A construct that requires CMP0140 NEW may encounter CMP0140 OLD because the
  parent set it. The preamble approach doesn't compose across subdirectory boundaries.
- **Research question**: can yelu constructs be written to be *policy-neutral* — either
  by avoiding constructs that change behavior across policies, or by emitting
  `cmake_policy(PUSH) ... cmake_policy(POP)` guards around each generated block?
  Cost: verbose output; benefit: composable regardless of caller context.

---

## Tier 5 — Explicit variable lifecycle types (research)

**Goal**: make cmake's implicit multi-run state model explicit in yelu's type system,
so both humans and LLMs can reason about what survives a reconfigure vs what is
recomputed fresh.

**Background**: cmake has two fundamentally different write semantics:

| Semantics            | cmake mechanism                            | Analogue                                            |
| -------------------- | ------------------------------------------ | --------------------------------------------------- |
| **Last-write-wins**  | Normal variables (`set(VAR val)`)          | Standard assignment in most languages               |
| **First-write-wins** | Cache variables (`set(VAR val CACHE ...)`) | Make `?=`, NixOS `mkDefault`, Ansible role defaults |

cmake's priority stack:
```
-DVAR=val (command line)           highest — sticks across all reconfigures
set(VAR val CACHE ... FORCE)       always overwrites
set(VAR val CACHE ...)             only writes if no cache entry exists yet
                                   ← the "first-write-wins" level
```
Normal variables shadow cache variables locally, adding another layer of confusion.

**Proposed type system** — replace the single `Ycvar` with typed variants:

| cmake concept                | Current yelu | Tier 5 yelu                                                                       |
| ---------------------------- | ------------ | --------------------------------------------------------------------------------- |
| Normal variable              | `Ycvar`      | `Ycvar_normal` — ephemeral, last-write-wins, scope-tracked                        |
| `option()` / `CACHE BOOL`    | `Ycvar`      | `Ycvar_bool` — persistent, first-write-wins, user-overridable                     |
| `CACHE STRING/PATH/FILEPATH` | `Ycvar`      | `Ycvar_string / _path / _filepath` — same, type constrains `-D` input             |
| `CACHE INTERNAL`             | `Ycvar`      | `Ycvar_internal` — persistent, not shown in cmake-gui, implies FORCE              |
| `set(... FORCE)`             | `Ycvar`      | explicit `~force:true` annotation — documents "this intentionally overrides user" |
| `find_library` result        | `Ycvar`      | `Ycvar_path` — makes it obvious why the result is cached across reconfigures      |

**Research connection**: the first-write-wins confusion is a known LLM failure mode —
models generate `set(VAR val CACHE ...)` expecting it to always take effect. A typed
yelu surface makes this class of error statically impossible.

---

## Tier 6 — Collapse the configure/build boundary (research)

**Goal**: users declare targets; yelu manages the full pipeline invisibly.

cmake's conf/build split is an implementation artifact (cmake generates Ninja/Make as
an intermediate). Modern tools hide it: `cargo build`, `bazel build`, `buck2 build`.

**What Tier 6 looks like**:
```
# user writes:
yelu build MathFunctions

# yelu does:
#   1. generate CMakeLists.txt (compile yelu program)
#   2. cmake -S . -B _build (configure)
#   3. cmake --build _build --target MathFunctions (build)
```

**Relation to Tier 5**: if yelu owns the state model (typed cache vars), it can own
the persistence — replacing CMakeCache.txt with its own store. yelu then knows what
changed and invalidates only the right cache entries.

**Evolution path**:
- Short term: yelu generates cmake text, user runs cmake manually (current)
- Medium term: `yelu build` CLI drives conf+build as a unit
- Long term: yelu generates Ninja directly, cmake no longer in the loop

---

## Tier 7 — Multi-stage core: same language across levels (research)

**Goal**: the same language constructs work at every pipeline level; only *when
interpretation happens* differs, not what the language looks like.

**The problem**: currently two distinct constructs for the same concept:

| Concept       | Compile-time (OCaml)  | Configure-time (cmake)   |
| ------------- | --------------------- | ------------------------ |
| Binding       | `Ylet { var; value }` | `Ycvar` + `set()`        |
| Iteration     | OCaml `for` loop      | `Yc_foreach`             |
| Conditional   | OCaml `if`            | `Yc_if`                  |
| Function call | OCaml function call   | `Yc_apply` (cmake macro) |

**The vision** — one construct per concept with staging annotations:
```
let x = "Tutorial"         -- compile-time: resolved before any cmake emitted
@stage cmake
let y = "libm"             -- configure-time: emitted as set(y "libm")
@stage build
let z = target_file(foo)   -- build-time: $<TARGET_FILE:foo>
```

Meta-programming via quote/splice replaces preprocessor + macro tooling — typed and
composable. The cmake `${}` / `$<>` / `$ENV{}` evaluation-time confusion disappears
because staging is explicit and local.

**Relation to Tier 5/6**:
- Tier 5's `Ycvar_bool`/`Ycvar_normal` becomes a stage annotation on `let`
- Tier 6's conf/build collapse is a consequence: if yelu owns staging, the split is
  an implementation detail of cmake-pack lowering

**Open design questions**:
- Is staging syntactic (annotation) or semantic (type-level `Code<T>` as in MetaML)?
- Can stages be user-defined, or fixed (compile / configure / build)?
- Quote/splice API: `quote : expr → code` + `splice : code → expr`?
- Two stages (now vs later) composable into towers, or fixed three-level tower?
