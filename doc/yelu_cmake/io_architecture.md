# I/O architecture: library / runner split + callback-via-env

> **Purpose.** Captures the design decision behind keeping
> `yelu_langs` I/O-free and the callback-via-env pattern used to
> bridge cmake's actual I/O behavior (`include()`, future
> `find_package()` / `file()` / `execute_process()`) into the
> evaluator without polluting the language with I/O primitives.

## 1. The split

| layer        | what it contains                                                                                                       | does I/O? |
| ------------ | ---------------------------------------------------------------------------------------------------------------------- | :-------: |
| `yelu_langs` | language types, AST (`Yelu_cmake.expr`, `Lang_cmake.exp`), evaluator, parser, emit, bridge (`Yelu_cmake_from_emit`)     |    no     |
| `yelu_runner`| subprocess invocation (parse.py, cmake), filesystem reads, path resolution (`Cmake_runner`, `Cmake_bridge`, `Cmake_serialize`) |   yes     |
| tests / tools| compose both: spawn cmake, drive evaluator, diff cache state                                                            |    yes    |

The library is a **pure computational module**: given an `env`
and an `expr`, it produces `(env, value)`. Determined entirely
by inputs.

The runner is an **impure adapter**: shells out, reads files,
formats output to disk.

## 2. Why this matters

- **Testability**: `dune test` runs the library's logic without
  spawning anything. The bridge smoke tests run cmake on
  purpose, but that's a separate alias.
- **Determinism**: same env + same expr → same result. The library
  has no hidden dependency on world state.
- **Future-portability**: an LSP server, a GUI inspector, a
  cloud worker — all could embed `yelu_langs` without inheriting
  a cmake or parse.py dependency.
- **Smaller blast radius for changes**: bug in subprocess
  handling can't break language semantics.
- **Clean dependency graph**: `yelu_langs` → no external tools;
  `yelu_runner` depends on `yelu_langs` + tools; tests depend on
  both. No cycles.

## 3. The callback-via-env pattern

Some cmake commands inherently need I/O at evaluation time:
- `include(GNUInstallDirs)` — read and evaluate a `.cmake` file
- `find_package(Threads)` — search prefix paths + `Find<X>.cmake` modules
- `find_program(DOXYGEN doxygen)` — search `$PATH`
- `file(READ x.txt OUT)` — read a file
- `execute_process(COMMAND ...)` — run a subprocess

If we hard-wired these into the library, we'd lose the I/O-free
guarantee. Instead, the library:

1. **Defines a protocol** (function type) for each kind of I/O.
2. **Stores a callback slot** in `env` for that protocol.
3. **Calls the callback at eval time** if registered; falls back
   to a safe stub (bookkeeping-only / VUnit) if not.

The runner (or tests) **registers an implementation** into env
before eval starts.

### Example: include_loader

In `src/langs/yelu/yelu_cmake.ml`:

```ocaml
type env = {
  …
  include_loader :
    (string -> current_list_dir:string -> module_path:string list ->
     expr option) option;
  …
}
```

Note three things:
1. The callback type is purely in terms of types the library
   already exposes (`string`, `expr`). No `yelu_runner` types
   leak into the library's interface.
2. The slot is `_ option`, so eval has a well-defined fallback
   when no loader is registered.
3. It's excluded from `equal_env` (functions can't be compared
   for equality — they're load-time bindings).

In `src/runner/cmake_bridge.ml`:

```ocaml
let loader file ~current_list_dir ~module_path : Yc.expr option =
  match resolve_include ~current_list_dir
          ~cmake_module_path:module_path ~file with
  | None -> None
  | Some path -> parse_file ~path  (* spawns parse.py *)
```

The runner provides the loader; the library doesn't know it
exists at compile time.

In a test setup:

```ocaml
let initial_env =
  let env = Yc.empty_env in
  let env = Yc.set_var env ~key:"CMAKE_CURRENT_LIST_DIR"
              ~data:(Yc.VString fmt_dir) in
  { env with include_loader = Some Cmake_bridge.loader }
in
Convert.eval_yelu_cmake_expr ~cmd_line initial_env prog
```

The test composes the impure adapter with the pure language at
the outer edge, exactly once.

### What ECmakeInclude eval does

In `src/langs/yelu/fragments/yelu_cmake_cmake_op.ml`:

```ocaml
| ECmakeInclude { file; optional } ->
    …
    (match env.include_loader with
     | None ->
       (* No loader → bookkeeping fallback (pre-2026-06-02). *)
       Some (env, VUnit)
     | Some loader ->
       (* 1. Read CMAKE_CURRENT_LIST_DIR + CMAKE_MODULE_PATH from env.
          2. Cycle-check via env.include_stack.
          3. Push to stack; update CMAKE_CURRENT_LIST_DIR.
          4. loader file ~current_list_dir ~module_path
             returns the included file's yc-expr (or None on
             resolve / parse failure).
          5. eval env included_expr — runs the loaded expression
             with normal yc-eval semantics in the current env.
          6. Pop stack; restore CMAKE_CURRENT_LIST_DIR. *)
```

From the language's point of view, step 5 is "a chunk of
yc-expr appeared in my eval stream." Origin opaque. Semantics
identical to inline-paste.

## 4. What this is *not*

### Not yelu-level meta-programming

The injected loader is an OCaml function, not a `yelu_cmake.expr`.
It can't be:
- Inspected by yelu programs (no `dump_loader` operation)
- Composed via expression operators
- Quoted / unquoted / staged
- Persisted across processes

It's a runtime side-channel for I/O, deliberately invisible to
the language.

### Not a module system

cmake's `include()` has no module-scope semantics — included
files mutate the caller's env directly. Variables, functions,
and targets defined in the included file leak into the caller.
This matches what our eval does too: `eval env included_expr`
runs the expr in the current env, including writes that mutate
the env.

A real module system would:
- Isolate the included file's bindings in a sub-scope
- Expose only an explicit interface
- Resolve symbol references through that interface

cmake doesn't do this; ycn doesn't (yet) do this. The current
include_loader pattern is faithful to cmake's "textual paste"
semantics.

### Example: subdir_loader

Added 2026-06-03 alongside the fmt matrix work. Same protocol
shape as `include_loader`, narrower resolution rule:

```ocaml
type env = {
  …
  subdir_loader : (string -> expr option) option;
  …
}
```

The caller (`EAddSubdirectory` eval) resolves the relative path
against `CMAKE_CURRENT_SOURCE_DIR` before calling. The runner-side
loader (`Cmake_bridge.subdir_loader`) just appends `CMakeLists.txt`
and parses.

What `EAddSubdirectory` eval does differently from `ECmakeInclude`:

| step | include() | add_subdirectory() |
|---|---|---|
| resolve | `CMAKE_MODULE_PATH` + cmake's `Modules/` | `CMAKE_CURRENT_SOURCE_DIR/<arg>` |
| frame | no push (inline) | `push_frame` (directory scope) |
| path vars | `CMAKE_CURRENT_LIST_DIR` only | + `CMAKE_CURRENT_SOURCE_DIR` |
| cycle | shared `include_stack` | shared `include_stack` |
| eval errors | propagate | **soft-fail** (unmodeled commands inside subdirs are common; don't crash the prediction) |

`add_subdirectory()` is the only call site that gives subdirs a
*real* directory scope (local writes don't leak to parent). cmake's
own behavior on `include()` is "textual paste"; on
`add_subdirectory()` is "scoped paste with new CWD". We model both
faithfully.

## 5. What we model — coverage map

| cmake construct | wired? | callback used | gap if any |
|---|:-:|---|---|
| `include(file)` (path) | ✓ | `include_loader` | — |
| `include(Module)` (bare name → CMAKE_MODULE_PATH) | partial | `include_loader` | cmake's stdlib `Modules/` dir not in default path (see § 7) |
| `include(Module OPTIONAL)` | ✓ | `include_loader` | — |
| `include_guard()` | ✗ | — | every call re-evaluates; no "load-once" cache (see § 7) |
| `add_subdirectory(dir)` | ✓ | `subdir_loader` | — |
| `add_subdirectory(dir bin)` | partial | `subdir_loader` | binary_dir arg ignored (doesn't affect cache) |
| `find_package(X)` | ✗ | (none) | search paths, version handling, `Find<X>.cmake` modules all unmodeled |
| `find_program(X)` | ✗ | (none) | `$PATH` search; produces `<X>-NOTFOUND` if absent |
| `find_path(X)` / `find_library(X)` | ✗ | (none) | same shape as `find_program` |
| `file(READ X out)` | ✗ | (none) | — |
| `file(WRITE X content)` | ✗ | (none) | — |
| `file(STRINGS …)` / `file(GLOB …)` | ✗ | (none) | — |
| `execute_process(…)` | ✗ | (none) | — |
| `try_compile(…)` / `try_run(…)` | ✗ | (none) | compiler probe — would need a real compiler runner |
| `configure_file(…)` | ✗ | (none) | reads template, substitutes `${X}`, writes |
| `$<…>` (generator expressions) | passthrough only | — | resolved at cmake's generate phase, after our prediction window |

## 6. Future directions

The same callback-via-env pattern extends to other I/O-bearing
commands. Likely additions:

| protocol slot                | command(s) it serves                                      | I/O kind                  |
| ---------------------------- | --------------------------------------------------------- | ------------------------- |
| `find_package_loader`        | `find_package(X)`                                         | filesystem search         |
| `find_program_search`        | `find_program(X)`, `find_path(X)`, `find_library(X)`      | $PATH search              |
| `file_reader` / `file_writer`| `file(READ)`, `file(WRITE)`, `file(STRINGS)`              | filesystem I/O            |
| `execute_process_runner`     | `execute_process(COMMAND ...)`                            | subprocess                |
| `genex_evaluator`            | `$<…>` generator-expression resolution                    | post-configure-phase eval |

Each one keeps `yelu_langs` pure; each one extends the runner's
adapter surface.

## 7. Known gaps and deferred items

These are filed here (not just in `status.md`) because they affect
how readers reason about the loader system itself.

### Every call re-evaluates (no module cache)

cmake's `include()` re-evaluates the named file on every call. The
idempotence primitive is `include_guard()` inside the loaded file:

```cmake
# Inside SomeModule.cmake:
include_guard()         # subsequent include(SomeModule) are no-ops
include_guard(GLOBAL)   # global scope (default DIRECTORY scope)
```

We currently re-evaluate unconditionally. Our `include_stack` only
protects against **direct cycles** (A→B→A within a single chain), not
against load-once semantics. If a file `M.cmake` is included three
times sequentially, we run it three times.

**Why it usually doesn't matter**: most cmake module side effects
are idempotent (function defs, variable assignments). For cache
prediction this is harmless in practice — duplicate writes overwrite
to the same value.

**When it'll bite**: modules that produce different output on
re-eval (counters, lists appended to). Add `include_guard` support
when we hit one.

Effort: ~20 LOC. Add an `evaluated : Set.M(String).t` field to env;
`include_guard()` consults a callback; `ECmakeInclude` adds path to
`evaluated` after first load and short-circuits on subsequent loads
that hit `include_guard()`.

### cmake's stdlib `Modules/` directory not in default module path

cmake ships ~900 `.cmake` files in `${cmake_install}/share/cmake-X.Y/Modules/`
— `FindThreads.cmake`, `CheckSymbolExists.cmake`, `GNUInstallDirs.cmake`,
etc. Real `include(GNUInstallDirs)` finds them automatically; we'd
have to populate `CMAKE_MODULE_PATH` defaults to match.

**Why it matters for the matrix**: the 3 remaining real-only entries
in fmt's matrix (DOXYGEN, FIND_PACKAGE_MESSAGE_DETAILS_Threads,
compile_result_unused) are all written by stdlib modules. Loading
them would close those gaps.

Effort: ~10 LOC to wire the install path into `module_path`
defaults. The harder question is which install path — cmake's `cmake
--system-information` reports it; could shell out or hard-code.

### Subdir scope semantics — what we don't preserve

`add_subdirectory()` uses `push_frame/pop_frame`. This gets local
variable isolation right but doesn't model:

- **`PARENT_SCOPE`** as used by subdirs setting parent values
  (`set(X val PARENT_SCOPE)` from a subdir CMakeLists). We treat it
  the same as a function PARENT_SCOPE; should be functionally
  equivalent but not separately tested.
- **Per-subdir target lists** — cmake keeps a per-directory target
  registry; subdirs inherit. We have one global target map. Affects
  the future `install()` modeling but not cache prediction.
- **`binary_dir` arg** — the optional second arg to
  `add_subdirectory(src bin/src)` changes the build output path.
  Cache writes don't depend on it, so we ignore.

### `find_package()` is the next big missing piece

Most real projects (~all of llvm, z3, torch) drive much of their
configure-time behavior through `find_package(X REQUIRED)`. We
predict zero of this. The architecture is clear (a third loader
callback), the work is in modeling the search semantics:

- Plain mode: search `${pkg}-config.cmake` / `${pkg}Config.cmake`
  along several prefix path variables (`CMAKE_PREFIX_PATH`,
  `<Pkg>_ROOT`, system paths)
- Module mode: search `Find<Pkg>.cmake` along `CMAKE_MODULE_PATH`
  then stdlib `Modules/`
- Version comparison (already handled by our `VERSION_*` cond ops)
- `<Pkg>_FOUND`, `<Pkg>_VERSION`, `<Pkg>_INCLUDE_DIRS`, etc. as
  output cache entries

Effort estimate: 200–400 LOC for plain mode + a basic Find module
shim. Big enough to be its own milestone.

## 8. Bool literals — parse-time vs eval-time

Tangential to the loader topic but a related architectural
question: cmake bool literals (`ON`/`OFF`/`TRUE`/`FALSE`/etc.) are
recognized at TWO places — once at parse time (in `from_emit.ml`),
once at eval time (`expect_bool` in `yelu_cmake.ml`).

### Current state — single source of truth at parse time

After 2026-06-03 refactor, parse-time recognition lives in ONE
helper:

```ocaml
(* yelu_cmake_from_emit.ml *)
let bool_literal_of_string : string -> Yelu_cmake.expr option = …
```

Both `cond_token_to_expr` (cond-position) and the `C.Var_exp` arm
(cmd-arg position) call it. Single bool table, two callers.

`expect_bool` in `yelu_cmake.ml` is the eval-time coercion for
when a `VString` flows into a bool context (if conditions, option
canonicalization). It uses the same set of falsy spellings.

### Why this dual-site arrangement is "cmake-tolerance, legacy"

cmake's actual model is "everything is a string; bool coercion at
consume sites." `set(X On)` stores the literal "On" (case
preserved); `if(X)` coerces; `if(X STREQUAL "On")` does a literal
string compare.

Our parse-time conversion turns `set(X On)` into `ESetVar (X, EBool
true)` → `VBool true`. Later cache emission writes `"ON"`. Two
quiet divergences from cmake:

1. **Case-loss**: real cmake keeps `"On"` (mixed case) in a
   non-cache variable; we lose it to `VBool true → "ON"`.
2. **STREQUAL surprise**: `set(X On); if(X STREQUAL "On")` is true
   in real cmake (literal compare) but false-equivalent in ours
   (`VBool true ≠ VString "On"` unless we add cross-type compare).

Neither bites the current corpus (fmt's matrix doesn't exercise
either). But they're real bugs waiting for the right cmake input.

### Future (Y17 typing redesign)

Collapse to eval-side only:
- Drop `bool_literal_of_string`; parse keeps strings as strings.
- `expect_bool` is the single coercion rule, applied at consume
  sites (if conditions, option-default canonicalization,
  `STREQUAL`/numeric-compare LHS, etc.).
- Storage stays cmake-faithful: `VString "On"` everywhere unless
  we KNOW the storage is BOOL-typed (cache BOOL slot).

Migration path:
1. Audit every `EBool`-producing call site outside this helper —
   most are direct literals from explicit `e_bool true/false`
   constructions, not coerced strings.
2. Add a typed cache cell: `cache_vars` already produces VBool for
   BOOL-typed entries via `expect_bool`. Generalize the same idea
   to non-cache assignments where the IR type carries BOOL.
3. Remove `bool_literal_of_string`; switch the two call sites to
   `e_var s` (treats unknown bare words as variable references,
   matching cmake's grammar).
4. Add tests exercising both case-preservation and STREQUAL
   against unquoted bools.

Effort: ~50 LOC, but the trickiest part is the test pass — much of
the existing test corpus implicitly relies on parse-time bool
production. Each test that breaks needs a small fix to either
quote the bool explicitly or expect a different VString output.

## 9. Relationship to a future ycn module import

ycn (yelu_cmake_normal) is the language's normalized form. It
currently does NOT have an import expression. If/when we add
one, it would look like:

```ocaml
type expr +=
  | EImport of { module_name : string }
  | EImportFrom of { module_name : string; bindings : string list }
```

with semantics that:
- Produce a module-scoped binding rather than a textual paste
- Allow `from M import foo` style explicit imports
- Support type-level checking of imported names (Y17 typing
  intersection)

The same `include_loader` callback could be the I/O hook
underneath, but **the language would know about the import
operation**. That's when it crosses into proper language-level
meta-programming. The current pattern doesn't commit us to a
particular design — it just exposes "we need to load a file"
as a runtime protocol without making it part of the language.

When the time comes, the migration path is:
1. Add `EImport` to ycn-side fragments.
2. Update from_emit's ECmakeInclude lowering to emit
   `EImport` for ycn (with module-scope semantics) and keep
   the textual paste for cmake-shape (yelu_cmake).
3. The runtime loader callback stays the same — it just gets
   called with different surrounding semantics.
4. ycn's evaluator handles the scope discipline; cmake's
   evaluator continues with the textual-paste behavior.

This way the language gradually grows a real module system
without breaking the cmake-shape compatibility we need for
existing real-world projects.

## 10. Caveats

- **A few legacy I/O sites in `yelu_langs`** — there are still
  a couple of `Stdlib.Printf.eprintf` calls in `Yelu_cmake_from_emit`
  for "bridging cond[X] -> default" warnings. They should be
  threaded through env-based logging eventually so even the
  warning channel isn't hard-wired.

- **Determinism caveat**: when `env.include_loader = Some f`,
  the library's purity is conditional on the loader being
  deterministic. A loader that reads disk state can vary
  between runs. For tests, pin the input by controlling
  CMAKE_CURRENT_LIST_DIR + CMAKE_MODULE_PATH explicitly (which
  the smoke tests do).

- **Cycle protection**: include_stack in env catches direct
  recursion (A→B→A). Doesn't catch deeper cycles that pass
  through different paths or symlinks resolving to the same
  file. Currently soft-skips cycles rather than erroring (per
  the "predictor keeps going on unknowns" stance); cmake itself
  errors loudly here.

- **CMAKE_CURRENT_LIST_DIR threading**: we push/pop in
  ECmakeInclude. If a future command does its own paste-style
  eval (e.g., `add_subdirectory`), it'll need the same dance.
  A helper function in `Yelu_cmake` would DRY this up — left
  as a follow-up.
