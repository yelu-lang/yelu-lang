# CMake Language Implementation Details

## File Layout
- `src/langs/cmake/lang_cmake.ml` (659 lines) — Full AST for CMake 3.31.0
- `src/langs/cmake/lang_cmake_pp.ml` (~930 lines) — Pretty printer (AST → CMake text)
- `src/langs/cmake/lang_cmake_utils.ml` (201 lines) — Ergonomic constructors for building AST
- `src/langs/yelu/lang_yelu.ml` — Yelu AST (typed surface language)
- `src/langs/yelu/lang_yelu_utils.ml` — Yelu helpers (`yvar`, `ytval`, `ycstr`, `yfile`, `ydir`, `ystr`, `yraw`, `ybool`)
- `src/langs/yelu/lang_yelu_compile.ml` — Compiler: yelu_ast → cmake_ast (type erasure + scope checking)
- `src/bin/cmake/step{1-12}*.ml` (27 files) — Tutorial examples using cmake AST directly
- `src/bin/yelu/step{1-12}*.ml` (25 files) — Same tutorials using yelu AST
- `test/test-yelu/test_yelu_compile.ml` — 22 Alcotest tests for yelu compiler
- `vendor/cmake-tutorial/step{1-12}/` — Generated CMake projects with C++ source for validation
- `Makefile.cmake.mk` — Orchestrates: generate → cmake configure → build → test

## Current State (as of 2026-02-24)
- **CMake AST**: Comprehensive CMake 3.31.0 coverage (`lang_cmake.ml`)
- **Pretty printer**: Complete for all variants (`lang_cmake_pp.ml`)
- **Yelu AST**: Typed surface language (`lang_yelu.ml`) with unified `yarg` type:
  - `Yarg_var` (compile-time variable), `Yarg_cvar` (cmake variable), `Yarg_target` (target name), `Yarg_file`/`Yarg_dir`/`Yarg_str` (semantic strings), `Yarg_raw` (cmake expression), `Yarg_bool` (ON/OFF)
- **Yelu compiler**: Type erasure + scope checking (`lang_yelu_compile.ml`), env-threaded
- **Scope checking**: 267→37 warnings; remaining are cross-file/runtime issues (see section below)
- **Stub AST nodes** (bare constructors, no fields — need AST expansion before printer):
  `Execute_process`, `File`, `Find_file`, `Find_library`, `Find_package`, `Find_path`, `Find_program`, `String_lib`, `Try_compile`, `Try_run`
- **No parser** exists yet (neither for CMake nor for yelu-lang)
- **25 yelu step files** in `src/bin/yelu/step*.ml` — outputs identical to cmake step files

## Structural Equivalence Check

Command: `make -f Makefile.cmake.mk cmake-check`

Uses **gersemi** (Python CMake formatter, Lark-based) to normalize both generated output and reference files before diffing. Skips empty references, continues past failures, prints summary.

Results: **24 OK, 0 SKIP, 0 FAIL** — all checks pass (as of 2026-02-22)

## Tutorial Versions

Two tutorial versions exist:

### v1 (old, CMake 3.20) — `vendor/cmake-tutorial/step{1-12}/`
- Our current OCaml translation tests target this version
- Topics: configure_file, USE_MYMATH, SqrtLibrary, CDash, CPack, BUILD_SHARED_LIBS, CMAKE_DEBUG_POSTFIX
- 12 steps, flat directory structure per step

### v2 (new, CMake 3.23+) — `vendor/cmake/Help/guide/tutorial/Step{0-11}/ + Complete/`
- Official Kitware rewrite, completely different curriculum
- New concepts: `target_sources()` + `FILE_SET HEADERS`, `CMakePresets.json`, OBJECT libs, multi-project structure, namespaced exports, `cxx_std_20`, custom test discovery framework
- Step numbering does NOT map 1:1 to v1
- Thematic overlap: system introspection (Step6↔step7), custom commands (Step7↔step8), testing (Step8↔step5), install/export (Step9↔step11)
- Steps with no v1 equivalent: Step0 (hello), Step2 (cmake language exercises), Step3 (presets), Step4-5 (vendor/OBJECT libs), Step10-11 (multi-project find_package)
- Future: create v2 OCaml translation tests (will need new AST features: FILE_SET, presets, OBJECT libs, etc.)

Fixes applied:
- `list_br` separator: `Fmt.cut` → `pp_force_newline` (reliable newlines after `@.` destroys vbox)
- step8_math, step10_math: `target_include_directories` moved to correct position

## CMake's Real AST (from vendor/cmake/Source/cmListFileCache.h)

CMake's parsed representation is minimal and entirely untyped:

```
cmListFile = vector<cmListFileFunction>

cmListFileFunction = {
  name: string,                          // e.g. "add_library"
  arguments: vector<cmListFileArgument>
}

cmListFileArgument = {
  Value: string,                         // argument text
  Delim: Unquoted | Quoted | Bracket,   // quoting style
  Line: long                             // source location
}
```

- No `var`, `target`, `value`, `item`, `cond`, or any typed structure
- Every command receives `vector<string>` and parses keywords positionally
- Keywords like `STATIC`, `PUBLIC`, `TARGET` are matched by string comparison at runtime
- Variable expansion (`${VAR}`) happens at execution time, not parse time
- `Delim` tracks whether argument was unquoted, quoted, or bracket-quoted

### Design Principle

- `lang_cmake.ml` should mirror CMake's stringly-typed, positional structure
- All type discipline (var, target, cond, etc.) belongs in `lang_yelu.ml`
- Yelu compiles down to cmake_ast by erasing types

### Topics to Study Later

- CMake's variable expansion and scope model (cmMakefile.cxx)
- Generator expressions ($<...>) — parsed separately from regular arguments
- How CMake resolves targets across subdirectories
- Policy/compatibility system

## Yelu Scope Checking — Remaining Warnings (37 total)

All false positives from the bare-string gap are eliminated. The 37 remaining warnings are legitimate cross-file / runtime-defined scope issues:

1. **Cross-file target refs** (10): `undeclared target 'MathFunctions'` — target defined in math step files, referenced in parent step files (separate compilation units)
2. **Cross-file function refs** (10): `undeclared variable 'check_cxx_source_compiles'` — `yfunction` defined later in same `ycmd_of_list` but `yapply` appears first (forward reference)
3. **Cmake-expression targets** (7): `undeclared target '${installable_libs}'` — cmake variable expansion used as target name in `yinstall_targets`; not a literal target
4. **Runtime-defined variables** (5+5): `undeclared variable 'HAVE_LOG'`/`'HAVE_EXP'` — set by `check_cxx_source_compiles` at cmake configure time, not in yelu's static env

Future solutions to explore:
- Multi-file compilation: thread env across step files (parent → child subdirectories)
- Forward-reference pass: scan for `yfunction` names before checking `yapply`
- Escape hatch: `Yc_extern_target` already exists for cross-file targets
- Runtime-defined vars: `Yc_extern_cvar` already exists for cross-file variables

## Future Directions (user stated)
1. Cover all CMake features, prove equivalence via CMake's test suite
2. Build yelu-lang parser (new surface syntax) — no rush; refine OCaml DSL (helpers + types) first until it looks like the desired surface syntax, then formalize as grammar. step*.ml files = test cases + syntax design experiments
3. May need CMake parser — check for existing OCaml implementations first, or use another language's parser
4. Apply PL techniques to reject incorrect/dangerous expressions
5. Look for modern books/projects to optimize their CMake as showcase targets
6. These are not urgent — research-paced work

## Testing
- Unit tests: `test/test-cmake/test_cmake_pp.ml` (Alcotest), run with `dune exec test/test-cmake/test_cmake_pp.exe`
- Integration tests: `make -f Makefile.cmake.mk cmake-check` (gersemi-normalized diff)
- `Fmt.sp` break hints always break at top level (no enclosing box) and in vbox — multi-arg commands produce newlines between args when printed standalone
- `Fmt.str "%a" pp ast` has no box; `Fmt.str "%a" (Fmt.vbox pp) ast` wraps in vbox — both cause Fmt.sp to break
- Future: compare at AST level (roundtrip or structural equality) rather than string/whitespace-sensitive comparison. Fmt's box model makes exact whitespace hard to predict and poorly documented.

## OCaml Gotchas
- `open Base` shadows: `result`, `prefix`, `id`, `append`, `compare`, etc. — rename in patterns
- `Fmt.prefix` is deprecated (use `Fmt.(++)`) — `prefix` field names trigger this
- Dune build: `(promote (until-clean))` on cmake executables — .exe files appear in source dir
- `Fmt.sp` / `Fmt.cut` are break *hints* — behavior depends on enclosing box type (vbox: always break, hovbox: break on overflow, hbox: never break). At top level (no box), hints always break. Poorly documented edge case.
