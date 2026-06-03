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

## 5. Future directions

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

## 6. Relationship to a future ycn module import

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

## 7. Caveats

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
