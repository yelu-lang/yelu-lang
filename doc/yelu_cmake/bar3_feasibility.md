# Bar #3 feasibility — z3 / llvm in yelu_cmake

Survey of what it would take to rewrite z3 and llvm's CMake
builds in `yelu_cmake` and prove structural equivalence with the
originals (the Bar #3 milestone from the manifesto). Grounded in
the actual contents of `/home/red/code/contrib/z3-all/z3` and
`/home/red/code/contrib/llvm-all/llvm-project/llvm`.

## What "translate" means here

Two valid framings:

| Framing | Approach | Where it lands |
| --- | --- | --- |
| **Mechanical translation** | Write a CMake-source → yelu_cmake source translator. | Out of scope. Requires a real CMake parser (we have an emitter only) and would not capture semantics like macro expansion or property propagation. |
| **Hand rewrite, structural equivalence** | Read the original CMakeLists, write the equivalent OCaml using `Yelu_cmake_utils`, emit, diff against the original (text or behavior). | What the manifesto means. The rest of this doc assumes this framing. |

"Structural equivalence" can mean two different verification
shapes:

- **Text-level**: emitted cmake is byte-identical (up to
  formatting) to the original. Strong claim; requires preserving
  the original DSL (`z3_add_component`, `add_llvm_library`, etc.)
  as yelu_cmake `function()` calls — not replacing with OCaml
  helpers.
- **Behavior-level**: emitted cmake configures + builds with
  identical output to the original. Weaker claim; allows
  refactoring the DSL out of cmake into OCaml.

The text-level claim is the manifesto target. The behavior-level
claim is more achievable and still scientifically interesting.

## Source scale

Both projects checked at the heads currently on disk
(2026-05-15):

| | files | cmake LOC | unique commands |
| --- | ---: | ---: | ---: |
| z3 (root) | 89 `CMakeLists.txt` + 111 `.cmake` | 7,919 | ~88 |
| llvm/llvm subtree only | 596 | 27,795 | 243 |

llvm-project is much larger if Clang / MLIR / etc. are added.
The `llvm/llvm` subtree is the natural minimum scope.

## yelu_cmake coverage matrix

Cross-referencing the unique cmake commands used by each project
against the 14 yelu_cmake theories. Categories:

- **Covered** — yelu_cmake_utils helper exists, IR ctor exists,
  emit_ast produces valid cmake.
- **Partial** — helper exists but with documented gaps (see
  `status.md` "Known IR shape gaps") or signature differences.
- **Missing — modelable** — no IR ctor today, but the surface is
  straightforward to add.
- **Missing — hard** — adding the surface is its own substantial
  feature; the project depends on it in a non-trivial way.

### z3

| Category | Count | Sample |
| --- | ---: | --- |
| Covered | ~50 | `add_library`, `add_executable`, `set`, `if`, `foreach`, `function`, `macro`, `message`, `option`, `include`, `add_subdirectory`, `target_link_libraries`, `target_include_directories`, `target_compile_definitions`, `target_compile_options`, `set_target_properties`, `set_property`, `get_property`, `get_target_property`, `install`, `find_package`, `find_library`, `find_path`, `find_program`, `file (READ/STRIP)`, `string`, `list`, `add_custom_command`, `add_custom_target`, `add_dependencies`, `configure_file`, `mark_as_advanced`, `unset`, `return`, `cmake_minimum_required`, `project`, `execute_process` |
| Partial | ~10 | `target_link_libraries` multi-target; `set_property(GLOBAL APPEND PROPERTY ...)`; `define_property` (helper exists, scopes incomplete); `add_custom_command(TARGET ...)` — failwith today |
| Missing — modelable | ~15 | `cmake_parse_arguments` (1 use in z3 itself + transitively via z3's macros); `cmake_push_check_state` / `cmake_pop_check_state`; `cmake_dependent_option`; `check_c_compiler_flag` / `check_cxx_compiler_flag`; `check_symbol_exists` / `check_cxx_symbol_exists`; `check_function_exists`; `check_include_file`; `check_library_exists`; `check_c_source_compiles`; `try_run`; `write_basic_package_version_file`; `configure_package_config_file`; `find_package_handle_standard_args`; `pkg_check_pkgconfig` |
| Missing — hard | ~5 | `add_jar` / `install_jar` (Java bindings); `find_ocamlfind_package` (OCaml bindings); `find_python_module`; custom git-describe helpers (`get_git_head_hash`, `get_git_head_describe`); `detect_target_architecture` |

**z3-specific DSL** (built on top of the above):
- `z3_add_component` (70 uses) — wraps `add_library` + dependency
  tracking via global properties + tactic / module registration.
- `z3_add_component_dependencies_to_target` (transitive
  dependency walk).
- `z3_expand_dependencies` (DAG closure via global properties).
- `z3_add_cxx_flag` (compiler-flag-presence check + add).
- `z3_add_gparams_register_modules_rule`,
  `z3_add_install_tactic_rule`,
  `z3_add_memory_initializer_rule` — code-generation custom
  commands feeding the source list.
- `z3_append_linker_flag_list_to_target`.

These DSL functions are all written in cmake's own `function()`
mechanism. **Text-level structural equivalence requires
preserving them as yelu_cmake `yc_function(...)` definitions**;
behavior-level equivalence can replace them with OCaml-side
helpers that emit the same target / property mutations.

### llvm

| Category | Count | Sample |
| --- | ---: | --- |
| Covered | ~70 | Same baseline as z3 plus more cond / list / string ops |
| Partial | ~15 | Same as z3 plus several `target_*` arrangements that use the multi-target / multi-visibility shapes |
| Missing — modelable | ~25 | `cmake_parse_arguments` (39 uses, frequent), `check_c_source_compiles`, `check_cxx_source_compiles`, `try_run`, `try_compile` extended forms, `add_compile_options`, `add_link_options`, `include_directories` (deprecated but used), `link_directories`, `link_libraries` (deprecated but used) |
| Missing — hard | ~35 | `tablegen` / `add_public_tablegen_target` (the LLVM TableGen integration — 379 + 68 uses); LLVM's CMake build-time scripting via `cmake -P`; multi-config generator handling; the host-tool / cross-compile dance; multi-target arch detection |

**llvm DSL** (300+ DSL-call sites):
- `add_llvm_component_library` (204 uses) — full component
  declaration.
- `add_llvm_library`, `add_llvm_tool`, `add_llvm_unittest`,
  `add_llvm_target`, `add_llvm_example`, `add_llvm_tool_symlink`
  (270+ uses combined).
- `tablegen` / `add_public_tablegen_target` — driver for the
  TableGen tool that LLVM uses to generate C++ from `.td` source
  files. Configure-time code generation; without TableGen, you
  cannot build LLVM.

## Specific blockers

### Shared by both

1. **`cmake_parse_arguments`** — the OCaml-native answer is
   "OCaml functions have kwargs natively." But the projects use
   this from within cmake `function()`s. Text-level equivalence
   requires modeling it in yelu_cmake (could be a Yelu1 ctor
   that emits the call directly).
2. **Cross-theory generator expressions** — both projects use
   `$<BUILD_INTERFACE:...>`, `$<INSTALL_INTERFACE:...>`,
   `$<TARGET_PROPERTY:...>` etc. extensively. Today these flow
   through yelu_cmake as opaque `EString`s via `Ycs_eval`. That
   is sufficient for emission but means yelu_cmake cannot
   reason about them (and Y17 cannot type them).
3. **Subdirectory scope isolation** — yelu_cmake records
   `add_subdirectory` but does not enforce var / target scope
   isolation. z3 has 89 subdirectories; llvm has hundreds. The
   emitted cmake works because real cmake provides the
   scoping, but yelu_cmake's own eval / typecheck cannot
   reason across the boundary.
4. **Custom `Find*.cmake` modules** — both ship their own. The
   `find_package` flow currently calls into yelu_cmake's
   modeled find primitives but doesn't execute a custom
   `Find*.cmake` module's logic. For text-level equivalence,
   these modules need to be rewritten in yelu_cmake too.
5. **Global property mutation** (`set_property(GLOBAL APPEND
   PROPERTY ...)`) — used by both for component / dependency
   bookkeeping. yelu_cmake's property scope coverage is
   currently target-only; expanding to global / source / test
   / cache is on the deferred list.

### LLVM-specific

6. **TableGen** — fundamental to LLVM's build. Either model it
   as a yelu_cmake-aware code generator (significant), or treat
   the `.td` → `.inc.h` step as an opaque `add_custom_command`
   and lose any structural understanding.

## Recommended path

A staged approach, starting much smaller than z3 / llvm:

### Stage 0 — Identify candidates with z3-shaped complexity but smaller scope

Goal: a target where the full hand-rewrite fits in 1–2 weeks
and produces a meaningful claim. Suggested candidates (in
increasing order of difficulty):

- **fmt** (libfmt) — ~10 cmake files, well-modularized, no
  custom DSL beyond standard `target_*` helpers. Doable in
  ~2 days.
- **catch2** — similar size, similar shape. Header-only library
  so the build is mostly install rules + tests.
- **rapidjson** — small, header-only, very simple cmake.

Pick one of these as the **proof-of-concept**: end-to-end
hand rewrite, text-level diff, behavior-level verification by
configuring + building.

### Stage 1 — z3 partial (Stage 0 → z3 root only)

After Stage 0, attempt z3's **root `CMakeLists.txt`** and the
top-level component declarations, leaving the per-component
`src/<component>/CMakeLists.txt` files in their original form.
This requires:

- Modeling z3's 7 custom DSL functions in yelu_cmake `yc_function`
- Filling the ~15 "missing — modelable" gaps (`check_*`,
  `cmake_parse_arguments`, version helpers)
- Confirming the partial gaps (multi-target, global properties)
  don't bite

Estimate: 2–4 weeks. Produces a real Bar-#3-shaped artifact for
a project that's non-trivial but not enormous.

### Stage 2 — z3 full

Translate every component. Requires the per-component DSL calls
to round-trip through yelu_cmake function definitions.
Realistic estimate: 1–2 months once Stage 1 is solid.

### Stage 3 — LLVM exploratory

Pick a subset (e.g., `llvm/lib/Support`) and attempt the
rewrite, primarily to surface what TableGen and the
`add_llvm_*` macro family need from yelu_cmake. Likely to
generate a longer follow-up TODO list than a finished
translation.

## What yelu_cmake would gain from doing this

Beyond the manifesto claim:

- **Real-world IR shape feedback** — the current IR was
  designed against the CMake tutorial + RunCMake corpus. Real
  projects use cmake idioms the corpus does not exercise (deep
  property propagation, generator expressions in install
  rules, multi-target link_lib, find_package modules with
  components).
- **Forced honesty on gaps** — the "Known IR shape gaps" list
  is currently passive (tests that document the stubs, but no
  caller demanding the fix). Real-project translation surfaces
  which gaps actually matter.
- **Bench for Y17** — typing rules can be exercised against
  real cmake projects; the failure modes ("this type system
  can't express what z3's DSL needs") are more informative
  than synthetic examples.

## What yelu_cmake would NOT gain from doing this prematurely

- It is **not a substitute** for the structural cleanup items
  in `status.md`. Splitting `cmake_op`, moving emit / convert
  arms to fragments, the theory split (`yelu_theory/plan.md`),
  Y17 typing — none of these are blocked by Bar #3, and Bar #3
  benefits from each being in place first.
- It is **not a CI-able test**. Behavior-level equivalence runs
  real builds; days of CI time. Manifesto-shaped, not
  regression-shaped.

## Recommendation

Don't attempt z3 or llvm directly. Start with **fmt** or
**catch2** as Stage 0. The point of those targets is to
calibrate: how long does a hand rewrite of a 1k-line cmake
build actually take, and which gaps surface first? Those
numbers will determine whether z3 (Stage 1) is a 2-week or
2-month project.

If Stage 0 succeeds and the gaps are small, jump to z3 root
(Stage 1). LLVM (Stage 3) should wait for Y17 to land — the
DSL complexity makes the typing surface the load-bearing
question, not the IR coverage.

## Open questions

- **Which fmt / catch2 / rapidjson?** Pick the version pinned
  in a real project we care about, not latest, so the cmake
  is one we'd actually want to drop yelu output into.
- **Verification strategy** — what counts as "structural
  equivalence" in practice? Text-diff after gersemi
  normalization? Compare the generated build graph
  (`cmake --graphviz`)? Configure + build + compare artifact
  hashes? Pick one before starting Stage 0.
- **DSL preservation vs OCaml-side helpers** — text-level
  equivalence requires DSL preservation (e.g., emit a
  `z3_add_component` cmake function). Decide whether the
  research claim needs text-level, or whether behavior-level
  is enough.
