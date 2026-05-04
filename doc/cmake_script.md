# cmake Script Mode — Feature Survey and Yelu Status

## The Four Concrete Shapes of cmake Code

cmake code appears in four distinct file shapes, each with different entry
conventions and execution context:

| Shape | Invoked by | Entry convention | Cache | Targets |
| ----- | ---------- | ---------------- | ----- | ------- |
| `CMakeLists.txt` | `cmake -S . -B build` | `cmake_minimum_required` + `project()` | Yes | Yes |
| Find module (`FindFoo.cmake`) | `find_package(Foo)` via `include()` | sets `Foo_FOUND`, `Foo_INCLUDE_DIRS`, … | Yes (caller's) | No |
| Utility script (`.cmake`) | `cmake -P script.cmake` | none required | No | No |
| Toolchain file | `cmake -DCMAKE_TOOLCHAIN_FILE=…` | sets `CMAKE_C_COMPILER`, `CMAKE_SYSTEM_NAME`, … | Yes | No |

All four use the same cmake language. What differs is the *calling convention* —
which variables are set at entry, which are expected at exit — not syntax.

---

## Script Mode (`cmake -P`) in Depth

### Environment at entry

| Variable | Set? | Value |
| -------- | ---- | ----- |
| `CMAKE_SCRIPT_MODE_FILE` | Yes | absolute path to the script |
| `CMAKE_CURRENT_LIST_DIR` | Yes | directory containing the script |
| `CMAKE_CURRENT_LIST_FILE` | Yes | same as `CMAKE_SCRIPT_MODE_FILE` |
| `$ENV{…}` | Yes | inherited from OS process |
| `-DFOO=bar` args | Yes | passed explicitly on command line |
| `CMAKE_SOURCE_DIR` / `CMAKE_BINARY_DIR` | No | not set (no project) |
| cmake cache | No | no `CMakeCache.txt` |
| targets, properties | No | no build graph |

### Wrapping a script for configure-mode testing

A script can be run under configure mode by wrapping it:

```cmake
cmake_minimum_required(VERSION 3.20)
project(TestScript NONE)
include(${CMAKE_CURRENT_SOURCE_DIR}/script.cmake)
```

This gives the script access to cache, File API output, and configure-time
variable semantics. This is the pattern used by cmake's own `Tests/CMakeOnly/`
suite. Useful when you need to assert on `CMakeCache.txt` contents or File API
codemodel output rather than just stdout.

---

## Find Modules — Calling Convention

A Find module is a `.cmake` file that `find_package(Foo)` loads via `include()`.
It runs inside the caller's configure scope and must follow the convention:

```cmake
# inputs (set by caller, may be empty):
#   Foo_ROOT, CMAKE_PREFIX_PATH, HINTS, PATHS, ...

find_path(Foo_INCLUDE_DIR foo/foo.h ...)
find_library(Foo_LIBRARY NAMES foo libfoo ...)

include(FindPackageHandleStandardArgs)
find_package_handle_standard_args(Foo
  REQUIRED_VARS Foo_LIBRARY Foo_INCLUDE_DIR)

# outputs set by find_package_handle_standard_args:
#   Foo_FOUND, Foo_INCLUDE_DIRS, Foo_LIBRARIES
```

The convention (`FOUND`, `INCLUDE_DIRS`, `LIBRARIES`, `VERSION`) is enforced by
`FindPackageHandleStandardArgs` — not by cmake syntax. It's a library contract,
not a language feature.

---

## Current Yelu Status

| Shape | Generation | Test level | Notes |
| ----- | ---------- | ---------- | ----- |
| `CMakeLists.txt` | ✓ (full) | configure | All tutorial steps + showcases |
| Utility script (`.cmake`) | ✓ (same commands) | script (via temp file) | `run_script` in `cmake_runner.ml` writes a temp `.cmake` and runs `cmake -P`; 22 RunCMake test files |
| Find module | Partial | — | `find_library`, `find_path`, `find_package_handle_standard_args` all in yelu, but no typed Find module template |
| Toolchain file | — | — | `CMAKE_C_COMPILER` etc. are plain `Ycvar`s — no dedicated toolchain abstraction |

**Key gap**: yelu has no concept of "which shape am I generating?" A yelu
program is a list of `yelu_exp` — whether it becomes a `CMakeLists.txt`,
a Find module, or a `-P` script depends entirely on what the user puts in it.
There is no typed entry-point or exit-convention enforcement.

---

## What's Needed to Extend Script-Mode Support

### 1. `run_configure` companion to `run_script`

`cmake_runner.ml` has `run_script` (`cmake -P`). A `run_configure` function
would wrap the generated cmake text in a minimal `CMakeLists.txt`, run
`cmake -S -B`, and return the cache and File API output. This enables
asserting on variable values that survive into `CMakeCache.txt`, without
building a full project.

```ocaml
val run_configure : ?cmake_min:string -> string -> configure_result
(* configure_result: { exit_code; stdout; stderr; cache: (string * string) list } *)
```

### 2. Find module template in yelu

A typed Find module template enforces the calling convention:

```ocaml
yc_find_module "Foo" ~required_vars:["Foo_LIBRARY"; "Foo_INCLUDE_DIR"] [
  yc_find_path (ycvar "Foo_INCLUDE_DIR") ~names:["foo/foo.h"] [];
  yc_find_library (ycvar "Foo_LIBRARY") ~names:["foo"] [];
]
(* auto-emits find_package_handle_standard_args + IMPORTED target *)
```

This makes the convention a compiler concern rather than a user convention.

### 3. Script entry-point annotation (optional)

A yelu program could carry an annotation declaring its target shape. The
compiler would then validate that the content is consistent — e.g., a
`Script` shape program should not emit `add_library`. This is a light version
of the staged typing in Tier 7 of `yelu_lang_design.md`.

```ocaml
type yelu_program_shape =
  | Shape_cmakelists   (* CMakeLists.txt — project() required *)
  | Shape_script       (* cmake -P — no project() *)
  | Shape_find_module  (* FindFoo.cmake — FOUND/INCLUDE_DIRS convention *)
  | Shape_toolchain    (* toolchain.cmake — compiler variables *)
```

---

## Relation to Language Design Docs

- **`yelu_lang_design.md` Tier 7** (multi-stage core): script mode (`cmake -P`) is
  the configure stage running without a project. The staged-typing design would
  unify these shapes under a single `@stage` annotation rather than separate
  shape types.
- **`cmake_policy.md`**: policy stack applies in configure mode; in `-P` script
  mode the policy stack starts empty (no `cmake_minimum_required` inheritance).
  Policies still work in `-P` but must be set explicitly.
