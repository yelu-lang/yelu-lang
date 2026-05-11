# Yelu Test Infrastructure — Comparison Levels

This document covers **how to run** tests at each comparison level — harness code,
dune aliases, patterns, gotchas, and blockers. `yelu_lang_coverage.md` refers to
these terms without re-defining them. For **why** each level exists and which levels
apply to which test categories see `cmake/comparison.md`.

---

## Level Taxonomy

Each level subsumes all levels below it (a `build` test also passes `configure`, `script`, and `text`).

| Level         | Mechanism                       | What it asserts                                                                                                     | Harness location                                              |
| ------------- | ------------------------------- | ------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------- |
| `text`        | OCaml Alcotest, no cmake        | Emitted cmake source text matches expected (PP and/or yelu compile)                                                 | `test_cmake_pp.ml`, `test_yelu_compile.ml`                    |
| `script`      | `cmake -P script.cmake`         | cmake interpreter accepts it; exit 0; stdout patterns match                                                         | `test-runcmake/` (runcmake-test alias)                        |
| `script-pair` | `cmake -P` run twice            | Ref cmake and yelu cmake are observationally equivalent under the interpreter (identical stdout, normalized stderr) | `test_runcmake_yelu.ml` (runcmake-yelu alias)                 |
| `configure`   | `cmake -S . -B _build`          | cmake compiles CMakeLists.txt into a build system; exits 0; specific cache variable bindings correct                | `test-runcmake/` configure tests; showcase `make cmake-check` |
| `build`       | `cmake -S -B` + `cmake --build` | Running the compiled build system (make/ninja) produces identical artifact names; sizes reported                    | `test_cmake_commands.ml` (cmake-commands alias)               |
| `file-api`    | configure + File API query      | Full binding environment (target → flags, includes, deps) identical between ref and yelu                            | `test-file-api/` (file-api-test alias)                        |

Future (not yet implemented):

| Level    | PL term   | Mechanism          | What it asserts                                            |
| -------- | --------- | ------------------ | ---------------------------------------------------------- |
| `symbol` | `run-sym` | `nm -D` inspection | Exported symbol sets identical between ref and yelu builds |

---

## Level 1 — `script`: RunCMake compat

**Alias:** `dune build @yelu/test/test-runcmake/runcmake-test`

Each `Tests/RunCMake/<dir>/*.cmake` is a self-contained test. Positive tests call
`message(FATAL_ERROR ...)` on assertion failure, so a wrong result → non-zero exit.

### Pattern A — self-contained exit-0

```cmake
# Tests/RunCMake/variable_watch/RaiseInParentScope.cmake
function(watch variable access value)
  message("${variable} ${access} ${value}")
endfunction()
variable_watch(var watch)
set(var "a")
function(f)
  set(var "b" PARENT_SCOPE)
endfunction(f)
f()
# exit 0, stdout: "var MODIFIED_ACCESS a\nvar MODIFIED_ACCESS b"
```

### Pattern B — shared `check_errors` helper (cmake_path)

`cmake_path` scripts include a helper via `-DRunCMake_SOURCE_DIR=<dir>`:

```cmake
include("${RunCMake_SOURCE_DIR}/check_errors.cmake")
cmake_path(APPEND path "/a/b" "c")
if(NOT path STREQUAL "/a/b/c")
  list(APPEND errors "'${path}' instead of '/a/b/c'")
endif()
check_errors(APPEND ${errors})
# no output on pass; FATAL_ERROR on failure
```

### OCaml harness

```ocaml
let check name dir =
  Alcotest.test_case name `Quick (fun () ->
    let result = run_script_file (Filename.concat dir (name ^ ".cmake")) in
    check_exit 0 result;
    check_stdout_patterns (load_stdout_patterns dir name) result)

(* cmake_path: needs -DRunCMake_SOURCE_DIR *)
let check_cmake_path name =
  Alcotest.test_case name `Quick (fun () ->
    let result = run_script_file ~flags:["-DRunCMake_SOURCE_DIR=" ^ dir]
                   (Filename.concat dir (name ^ ".cmake")) in
    check_exit 0 result)
```

Also included at this level: upstream `include/` tests where `check_include_warning` additionally calls `check_stderr_matches "given empty file name"` — the exit-0 plus stderr content check covers negative-path tests.

---

## Level 2 — `script-pair`: RunCMake yelu pairs

**Alias:** `dune build @yelu/test/test-runcmake/runcmake-yelu`

Each test runs the upstream cmake script **and** a yelu-compiled equivalent, then
asserts both exit 0 and produce **identical stdout**.

### Example — `variable_watch/RaiseInParentScope`

**Yelu program:**
```ocaml
let vw_raise_in_parent_scope =
  Yexp_list [
    yc_function (ystr "watch") ["variable"; "access"; "value"] [
      yc_message ~mode:Mm_none [ "${variable} ${access} ${value}" ]
    ];
    yc_variable_watch ~command:(Some "watch") (ycvar "var");
    yc_set (ycvar "var") [ystr "a"];
    yc_function (ystr "f") [] [
      yc_set ~parent_scope:true (ycvar "var") [ystr "b"]
    ];
    yc_cmake_language_call "f" [];
  ]
```

Both produce `var MODIFIED_ACCESS a\nvar MODIFIED_ACCESS b`. When a yelu change
silently alters semantics (PP quoting, arg ordering), the upstream output is
ground truth and the test catches the drift immediately.

### Two harness variants

```ocaml
(* Reference is the upstream .cmake file. *)
let check_pair name dir ?(cmake_flags = []) yelu_prog = ...

(* Reference is an inline cmake string — used when the upstream script produces
   no stdout (only FATAL_ERROR on failure). Write a minimal cmake that does the
   same operation and prints the result. *)
let check_pair_text name ref_cmake yelu_prog = ...

(* Like check_pair_text but also compares normalized stderr (filepath-normalized).
   Used for negative-path tests: EmptyString / EmptyStringOptional. *)
let check_pair_text_stderr name ref_cmake yelu_prog = ...
```

### Inline reference pattern (cmake_path, most string/list/math ops)

```ocaml
let cp_append_ref = {|
cmake_path(SET path "/a/b")
cmake_path(APPEND path "c")
message("${path}")
|}

let cp_append_yelu =
  Yexp_list [
    yc_cmake_path_set (ycvar "path") (ystr "/a/b");
    yc_cmake_path_append (ycvar "path") [ystr "c"];
    yc_message ~mode:Mm_none ["${path}"];
  ]
```

### Stderr alignment (negative-path tests)

For tests that produce warnings with no stdout, the upstream `-stderr.txt` pattern
files assume CTest framework (scripts run via `include()` from a parent), so the
call stack differs in `-P` mode. Fix: normalize by replacing any `*.cmake` path
with `<cmake>` and compare normalized stderr between two `-P` runs, not against
the upstream pattern file.

```ocaml
let normalize_cmake_filepath s =
  let re = Re.Pcre.regexp {|[^\s:"']+\.cmake|} in
  Re.replace_string re ~by:"<cmake>" s
```

---

## Level 4 — `build`: cmake-commands tests

**Alias:** `dune build @yelu/test/test-runcmake/cmake-commands`

Source: `Tests/CMakeCommands/` — one subdirectory per command, ~15–90 lines per
`CMakeLists.txt`, configure-time property assertions via `message(SEND_ERROR ...)`.

### check_build_pair

Runs the upstream source dir AND yelu-generated cmake through configure + build.
Both are **fate-sharing**: all four outcomes are checked independently.

```
ref:  cmake -S Tests/CMakeCommands/<name> -B tmpdir_ref → cmake --build tmpdir_ref
yelu: cmake -S tmpdir_src -B tmpdir_build → cmake --build tmpdir_build
```

```ocaml
let check_build_pair name ref_name ?(files = []) yelu_prog =
  Alcotest.test_case name `Quick (fun () ->
    let ref_result  = run_build_existing (ref_dir ref_name) in
    let cmake_text  = compile yelu_prog in
    let yelu_result = run_configure_and_build ~files cmake_text in
    (* Layer 1: fate-sharing exit codes *)
    (if ref_result.configure.run.exit_code <> 0 then failf "ref configure failed ...");
    (if ref_result.build.exit_code <> 0 then failf "ref build failed ...");
    (if yelu_result.configure.run.exit_code <> 0 then failf "yelu configure failed ...");
    (if yelu_result.build.exit_code <> 0 then failf "yelu build failed ...");
    (* Layer 2: artifact comparison *)
    check_artifacts_match ref_result.artifacts yelu_result.artifacts)
```

### check_build_yelu

Used when the upstream reference cmake requires a newer cmake version than
what is installed (e.g., cmake 3.30+ genex in `Tests/CompileOptions/`). Runs
only the yelu-generated cmake — no reference cmake, no artifact comparison.

```
yelu: cmake -S tmpdir_src -B tmpdir_build → cmake --build tmpdir_build
```

```ocaml
let check_build_yelu name ?(files = []) yelu_prog =
  Alcotest.test_case name `Quick (fun () ->
    let cmake_text = compile yelu_prog in
    let r = run_configure_and_build ~files cmake_text in
    (if r.configure.run.exit_code <> 0 then failf "configure failed ...");
    if r.build.exit_code <> 0 then failf "build failed ...")
```

Do **not** add files to the upstream cmake source tree as a workaround —
if the upstream reference is incompatible, use `check_build_yelu` or mark
the test blocked.

### Artifact comparison (check_artifacts_match)

Walk the build directory, skip cmake internals (`CMakeFiles/`, `*.cmake`, `*.d`,
`build.ninja`, `Makefile`, etc.), collect `(rel_path, size)` pairs.

- **Layer 2a (strict):** same set of relative artifact paths must match.
  If ref builds `libtarget_link_options.so` then yelu must too, at the same
  relative path within the build tree.
- **Layer 2b (informational):** sizes are reported but not a hard failure.
  GCC embeds source file paths in ELF `.strtab` even without `-g`, causing
  constant-offset size differences (~8 bytes) proportional to temp dir path
  lengths. Strict size equality is a future enhancement once stripped-binary
  or symbol-level comparison is in place.

### Multi-file yelu source trees (`~files` + mkdirp)

When a test's yelu program calls `yc_add_subdirectory`, the subdir's
`CMakeLists.txt` must exist in the temporary source tree. The `~files`
parameter of `run_configure_and_build` accepts `(rel_path, content) list`
entries; each entry is written into the tmpdir before cmake is invoked.

```ocaml
(* path can include separators — "subdir/CMakeLists.txt" *)
let yelu_result = run_configure_and_build
  ~files:[
    ("subdir/CMakeLists.txt", compile subdir_prog);
    ("src/helper.c", helper_c_src);
  ]
  root_cmake_text
```

`write_file` calls `mkdirp` on the parent directory before writing, so
nested paths like `"a/b/c.cmake"` work without pre-creating intermediate
directories.

Two strategies for subdir cmake content:

- **Typed yelu** (`compile subdir_prog`) — subdir is itself a yelu program,
  compiled to a cmake string and passed as a `~files` entry. Preferred when
  the subdir uses constructs in the yelu API.
- **Verbatim cmake string** (`{|...|} raw literal`) — subdir cmake is written
  inline as a raw OCaml string. Used when the subdir cmake uses features not
  yet in the yelu API (genex, complex property sets, etc.).

`check_build_pair` points at `Tests/CMakeCommands/<name>` (one command per
dir). `check_build_pair_tests` points at `Tests/<name>` (arbitrary test
subtrees under the cmake source `Tests/` root).

### What the upstream property assertions check

The upstream `CMakeLists.txt` files contain `get_target_property` + `message(SEND_ERROR ...)`
assertions that fail configure (exit non-zero) if target properties are wrong.
This makes configure exit 0 an oracle for correct property semantics — no manual
comparison needed. The build step additionally verifies that `#error` preprocessor
directives in source files (e.g., `add_compile_definitions`) fire when expected
compile-time macro state is wrong.

---

## Level 5 — `file-api`: File API tests

**Alias:** `dune build @yelu/test/test-file-api/file-api-test`

Runs cmake configure for each step1–12 pair, queries the cmake File API
(`-DCMAKE_EXPORT_COMPILE_COMMANDS=ON` + `.cmake/api/v1/query/`), and compares
codemodel-v2 JSON between the cmake-generated reference and yelu-generated output.

---

## Coverage counts (current)

| Level         | Count             |
| ------------- | ----------------- |
| `text`        | ~193 unit tests   |
| `script`      | 61 compat tests (1 blocked)   |
| `script-pair` | 50 pairs          |
| `configure`   | 23 tests          |
| `build`       | 26 tests (growing) |
| `file-api`    | 12 step pairs     |

---

## Environment gotchas

**`CLICOLOR_FORCE` propagation**: dune sets `CLICOLOR_FORCE=1` when running test
aliases to force colors in alcotest output. cmake inherits this and wraps every
`message()` output with ANSI reset codes (`\x1b[0m`). The `message/newline` compat
test hex-encodes captured stderr for byte-exact comparison — ANSI codes corrupt it.
`cmake_runner.ml`'s `cmake_env` forces `CLICOLOR_FORCE=0` for all cmake subprocess
calls to isolate them from dune's color forcing. Note: `NO_COLOR=1` does not work —
cmake 3.28 ignores it; `CLICOLOR_FORCE` is the actual switch cmake respects.

---

## Blockers

| Item                                    | Blocker                                      |
| --------------------------------------- | -------------------------------------------- |
| `message/newline` script                | cmake emits `\x1b[0m` ANSI reset codes around `message()` output when `CLICOLOR_FORCE` is set (injected by dune for alias runs); hex-encoded stderr comparison fails. `CLICOLOR_FORCE=0` override in `cmake_env` did not resolve on all machines. |
| `include` CMP0146/CMP0148 `script-pair` | Require real cmake modules + policy state    |
| `include` ParentVariable*               | Multi-file fixture infra                     |
| `foreach-all-test` pair                 | PP always emits LISTS-first; needs extension |
| `cmake_path/GET` stem edge case         | Differs cmake 3.28 vs 4.3                    |
| `symbol` level                          | `nm` infra not yet wired into test suite     |
