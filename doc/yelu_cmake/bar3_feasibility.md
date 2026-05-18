# Bar #3 feasibility — z3 / llvm and yelu_cmake

Survey of what it would take to validate `yelu_cmake` against
real-world cmake projects (the Bar #3 milestone from the
manifesto). Grounded in
`/home/red/code/contrib/z3-all/z3` and
`/home/red/code/contrib/llvm-all/llvm-project/llvm` as snapshots
of the targets.

Two distinct shapes of claim are surveyed:

| Claim | Verifies | Effort |
| --- | --- | --- |
| **Bar #3-lite — syntactic round-trip** | `Lang_cmake.exp` (the typed cmake AST) is structurally rich enough to losslessly carry a real-world cmake project's source | ~1 month with tree-sitter-cmake; ~2-3 months DIY |
| **Bar #3 — hand rewrite** | `yelu_cmake` (the typed surface) can *generate* the cmake a real-world project ships | ~weeks per small project; months for z3; quarters for llvm |

Both are useful. Bar #3-lite is the floor — if our cmake AST
can't even round-trip z3, the hand rewrite can't succeed
either. Recommendation at the bottom: do Bar #3-lite first.

## Source scale

Both projects checked at the heads currently on disk
(2026-05-15):

| | files | cmake LOC | unique commands |
| --- | ---: | ---: | ---: |
| z3 (root) | 108 (`CMakeLists.txt` + `.cmake`) | 7,919 | ~88 |
| llvm/llvm subtree only | 596 | 27,795 | 243 |

llvm-project is much larger if Clang / MLIR / etc. are added.
The `llvm/llvm` subtree is the natural minimum scope.

## Bar #3-lite results (Stage 1 + Stage 2, 2026-05-15)

Stage 1 (untyped) and Stage 2 (typed via `Lang_cmake.exp`)
round-trip results, both via the `tool/cmake_roundtrip/`
pipeline. Per-file results are categorized by
`test_corpus.sh` into four buckets:

- **OK** — structural AND gersemi-diff pass
- **FORMAT** — structural pass, gersemi-diff fail (formatting)
- **STRUCT** — structural fail (real parser/printer/IR bug)
- **PARSE** — tree-sitter or our reader fail

| corpus | files | OK | FORMAT | STRUCT | PARSE |
| --- | ---: | ---: | ---: | ---: | ---: |
| tutorial step outputs | 25 | 25 | 0 | **0** | 0 |
| z3 | 108 | 14 | 94 | **0** | 0 |
| llvm/llvm | 596 | 47 | 549 | **0** | 0 |

**Structural pass = 100% across all three corpora.** The
`(command_name, arg list)` sequence tree-sitter extracts from
the original matches the sequence extracted from our reprinted
output, for every file. AST + parser + printer capture every
command yelu's parser+printer round-trip touches, with no
command lost and no arg misclassified.

**FORMAT** failures (94/108 z3, 549/596 llvm) measure
cosmetic byte-equivalence under gersemi-default formatting,
not content equivalence. Three contributing causes:

1. **Multi-line vs single-line wrap choice.** Gersemi
   preserves the source's multi-line layout when args exceed
   `--line-length` (default 80) OR when an arg list contains
   inline comments. Our reprinter always emits single-line.
   So a source like:

   ```cmake
   set(MY_LIST
       FOO
       BAR
       BAZ
   )
   ```

   round-trips through us as `set(MY_LIST FOO BAR BAZ)` and
   gersemi keeps both forms (multi-line vs single-line) on
   their respective sides — diff fires.

2. **Comments inside argument lists.** Our parser drops
   `line_comment` and `bracket_comment` nodes inside
   `argument_list`. Even with `--line-length 999`, gersemi
   keeps the call multi-line when inline comments are
   present in source, because the comments occupy lines.
   Our reprint without those comments collapses to single
   line.

3. **Gersemi `Warning:` lines.** When gersemi sees a user-
   defined function (no builtin registry hit) it prints a
   warning to stderr referencing either the file path or
   `<stdin>`. The harness filters these out so the diff is
   content-only.

The Stage 1-b options to close FORMAT are:

| approach | cost | gives |
| --- | --- | --- |
| Preserve comments-inside-args in our AST | per-arg union type extension + printer arms | true byte-perfect round-trip |
| Match gersemi's wrap heuristic in our printer | ~100 lines tracking byte length | prettier output; doesn't address comments |
| Pre-strip comments before gersemi on both sides | need a real cmake comment stripper | gersemi-diff stops being comment-sensitive |
| Accept FORMAT measures cosmetic equivalence | zero | clear claim: STRUCT is the content oracle |

Currently we take the last position. STRUCT is the
load-bearing claim; FORMAT is informational.

### Bugs surfaced and fixed during real-world round-trip

Three real bugs in `Lang_cmake_pp` (in production, not just the
prototype) — tutorial doesn't exercise them, real-world cmake
does:

1. **`Include.no_policy_scope` was typed `scope option`** — cmake's
   `NO_POLICY_SCOPE` is a boolean flag; field type was wrong. Fixed
   to `bool`. Commit `13d813c`.
2. **`Configure_file.{@ONLY, ESCAPE_QUOTES}` flags wired to wrong
   fields** — cross-swap in the printer. Fixed in `lang_cmake_pp.ml`.
3. **`Include.result_var` printed without keyword** — emitted
   `include(file var)` instead of `include(file RESULT_VARIABLE var)`.
   Fixed in `lang_cmake_pp.ml`.

Three printer-shape fixes that round-trip surfaced:

4. **`pp_arg.Bracket` always added newlines** around content.
   Now emits verbatim. Fixed in `lang_cmake_pp.ml`.
5. **`Lang_cmake.arg.Bracket of string` lost the bracket level**
   (number of `=`). Widened to `Bracket of int * string`. Fixed
   in `lang_cmake.ml` + `lang_cmake_pp.ml` + 2 callers.

Stage-2 prototype bail-outs (the parser routes to `Apply` to
avoid lossy typed mapping):

6. **`parse_target_*` injected `PRIVATE`** when source had no
   visibility keyword (cmake's "plain" legacy form).
7. **`parse_message` re-quoted bare text args** because
   `Lang_cmake_pp.Message` always quotes.
8. **`parse_configure_file` stripped quoting from path slots**
   that the IR's `path : string` cannot carry.
9. **`parse_cmake_minimum_required`/`parse_project` crashed on
   non-numeric versions** (e.g., `project(... VERSION
   ${Z3_VERSION_FROM_FILE})`).
10. **`parse_cmd` lowercased commands** so `SET(...)` would
    round-trip as `set(...)`.

Stage 2 typed mapping coverage (`Lang_cmake.exp` ctors per
command), with 15 typed parsers wired (`cmake_minimum_required`,
`project`, `set`, `message`, `configure_file`,
`add_executable`, `add_library`, `target_link_libraries`,
`target_include_directories`, `target_compile_definitions`,
`target_compile_options`, `target_compile_features`, `option`,
`include`, `add_subdirectory`):

| corpus | total cmds | typed | untyped | block/raw | typed % |
| --- | ---: | ---: | ---: | ---: | ---: |
| tutorial | 213 | 155 | 35 | 23 | **73%** |
| z3 | 2,992 | 764 | 763 | 1,465 | **50%** |
| llvm/llvm | 9,296 | 2,422 | 3,248 | 3,626 | **43%** |

The "block/raw" bucket is control-flow heads (`if`/`foreach`/
`function` markers) + raw passthrough for `.cmake.in` template
content + tree-sitter ERROR fragments.

z3 / llvm typed % is lower than tutorial because real-world
cmake uses much more diverse builtins plus heavy reliance on
cmake-module functions and project-specific DSL macros, which
correctly remain untyped (Lang_cmake.exp models cmake
builtins, not module-defined or user-defined functions).

### Untyped breakdown — z3

| category | example | count | notes |
| --- | --- | ---: | --- |
| common builtins not yet typed | `list` / `string` / `unset` / `set_target_properties` / `set_property` / `install` / `file` / `find_package` / `add_custom_*` / `add_dependencies` / `execute_process` | ~500 | each command needs a per-command argument grammar; mostly mechanical |
| cmake module functions (correctly untyped) | `check_symbol_exists` / `check_include_file` / `check_function_exists` / `cmake_parse_arguments` / `find_package_handle_standard_args` / `cmake_push_check_state` etc. | ~150 | defined in cmake modules, NOT builtins; `Lang_cmake.exp` shouldn't model |
| z3-specific user-defined functions | `z3_add_component` (×70) / `z3_add_cxx_flag` / `z3_expand_dependencies` | ~110 | declared via cmake `function()`; correctly untyped |

### Untyped breakdown — llvm/llvm

| category | example | count | notes |
| --- | --- | ---: | --- |
| common builtins not yet typed | `list` / `string` / `set_target_properties` / `set_property` / `add_dependencies` / `add_custom_target` / `file` / `get_property` / `execute_process` / `include_directories` / `install` / `find_package` / `add_compile_definitions` | ~1,400 | same shape as z3 |
| cmake module functions | `cmake_parse_arguments` / `check_symbol_exists` / `mark_as_advanced` | ~150 | same as z3 |
| **TableGen** | `tablegen` (×379) / `add_public_tablegen_target` (×68) | ~450 | LLVM-specific build tool; cmake AST cannot represent it as a builtin |
| LLVM-specific DSL | `add_llvm_component_library` (×204) / `add_llvm_tool` (×75) / `add_llvm_library` / `add_llvm_unittest` / `add_llvm_*` family + `append` (LLVM's variadic-flag helper) | ~700 | user-defined cmake functions; correctly untyped |

### Two parser/printer findings surfaced

1. **`Bool true` prints as `True` instead of `ON`** — printer
   convention vs cmake idiom. Workaround in `parse_option`:
   map `ON`/`OFF`/`TRUE`/etc. to `Var_exp`. Real fix decision
   deferred until more contexts (`if(<expr>)` etc.) have
   data — likely Stage 2-b.
2. **`Include.no_policy_scope : scope option`** — wrong-typed
   IR field. Fixed 2026-05-15 (commit 13d813c): now `bool`.
3. **Case-insensitive command dispatch** — cmake commands are
   case-insensitive; `SET`/`set`/`Set` all dispatch to the
   same builtin. Fixed in `parse_cmd` by lowercasing the name.
   Lifted z3 Stage-2 coverage from 45.1% to 50.0%.

### Adjacent argument concatenation (open)

Tree-sitter gives adjacent (no-whitespace) argument nodes as
separate `argument` children. Our reprinter inserts a space
between them. Example:

```
/p:Configuration="${DOTNET_CONFIG}"     # one cmake arg
```

is reprinted as

```
/p:Configuration= "${DOTNET_CONFIG}"    # two cmake args (semantically different)
```

Real round-trip needs to detect adjacency via byte-position
comparison (`prev.end_byte == next.start_byte`) and emit
concatenated. Open Stage 1-b item.

---

# Bar #3-lite — syntactic round-trip

The minimal scientific claim: "our typed cmake AST
(`Lang_cmake.exp`) captures real-world cmake without semantic
modeling — no variable substitution, no function invocation, no
property propagation."

```
z3's CMakeLists.txt  →  parse  →  Lang_cmake.exp  →  pretty-print  →  diff against original
```

What's missing today: yelu has a cmake *emitter* (`Lang_cmake_pp`)
and a *yelu-source* parser (`Yelu_parse`), but **no parser for
arbitrary cmake source**. That's the new piece.

## Building the parser — three options

### Option A: tree-sitter-cmake via Python (recommended starter)

[`uyha/tree-sitter-cmake`](https://github.com/uyha/tree-sitter-cmake)
is a maintained tree-sitter grammar (used by Neovim and various
editors). Tree-sitter handles all the lexer pain: bracket
arguments `[==[...]==]`, quoted vs unquoted args, escape
sequences, line continuations, BOM tolerance. The grammar
produces a concrete syntax tree (CST) distinguishing
control-flow blocks (`if_command` / `foreach_def` /
`function_def` / etc.) from `normal_command` nodes; per-command
typing is left to the consumer.

Pipeline:

```
Python:  z3.cmake  →  tree-sitter parse  →  CST  →  JSON dump  →  stdout
OCaml:   stdin     →  yojson  →  walk CST  →  Lang_cmake.exp
         then:     Lang_cmake_pp  →  text  →  gersemi normalize  →  diff
```

The Python side is ~30 lines (load grammar, parse, serialize
node tree as JSON). OCaml side reads JSON with `yojson` (already
a common dep) and walks the tree.

Pros:
- Lexer / parser is **already written and battle-tested**.
- Comments, brackets, line-continuation, all UTF-8 / BOM issues
  handled by tree-sitter.
- Iterative coverage: start with `source_file` + `normal_command`
  + a single command (`set`), get a working round-trip, then add
  commands one at a time.

Cons:
- Python build step in the test pipeline.
- The CST is *concrete* — preserves syntax, including whitespace
  and comments. Mapping it to the *typed* `Lang_cmake.exp`
  requires the per-command knowledge (the same work as any other
  parser approach, just without the lexer cost).

### Option B: ocaml-tree-sitter (pure OCaml runtime)

[`semgrep/ocaml-tree-sitter`](https://github.com/semgrep/ocaml-tree-sitter)
is the OCaml binding ecosystem for tree-sitter (semgrep uses it
for ~30 languages). It takes a tree-sitter grammar and generates
OCaml ADTs + a parser at build time.

Pros:
- Pure OCaml runtime; no Python or other interpreter at test
  time. Just a C library (libtree-sitter) and the generated
  OCaml binding.
- Type-safe CST traversal in OCaml (the generated ADT mirrors
  the tree-sitter grammar nodes).

Cons:
- Codegen step at build time (small extra dune complexity).
- Adds `libtree-sitter` + `libtree-sitter-cmake` C deps to the
  build.
- Whether the cmake grammar is in the maintained `semgrep/`
  pre-built bindings list — TBD; may need to run their codegen
  ourselves against `uyha/tree-sitter-cmake`.

### Option C: DIY parser

OCaml lexer + recursive-descent parser, no external runtime
deps.

Pros:
- No deps. Builds cleanly anywhere.
- Full control over the AST shape.

Cons:
- Reimplements what tree-sitter already does well. Bracket
  arguments in particular are tedious (`[==[...]==]` with
  arbitrary `=` count).
- ~2-3 months to match tree-sitter-cmake's robustness.

### Recommendation: A → B if it pays off

Start with **Option A** (Python + tree-sitter-cmake). Fastest
path to a working round-trip — probably **2-3 weeks** to a
useful prototype. If the prototype proves the concept and the
Python dep becomes annoying, migrate to **Option B**
(ocaml-tree-sitter) in a follow-up — the JSON-walking code that
maps CST → `Lang_cmake.exp` is mostly reusable; only the
"how do we get the CST" layer changes.

**Skip Option C.** Building a CMake parser from scratch is its
own multi-month project; not worth the time when tree-sitter
exists.

## Two verification shapes

Once the parser exists, two oracles can use it:

### Shape 1: Text round-trip (fast, hermetic)

```
input.txt --gersemi--> canonical_A
parse(input.txt) --pp--> reprint --gersemi--> canonical_B
diff canonical_A canonical_B
```

gersemi handles whitespace / quoting / line-continuation
variants, so the comparison surfaces only structural
differences. A green diff means "our typed cmake AST + printer
captures the syntactic content of z3's cmake, modulo
formatting."

Runs in milliseconds per file. Suitable for unit-test-style
coverage across z3's 200 cmake files / llvm's 596.

### Shape 2: File-API round-trip (stronger, slower)

CMake's file API writes JSON describing the build graph
(`<build>/.cmake/api/v1/reply/codemodel-v2-*.json`) after
configure. The harness exists already as `make file-api-test`
against tutorial steps.

```
real cmake configure on z3      →  file-API JSON_A
real cmake configure on (parse+print of z3)  →  file-API JSON_B
diff JSON_A JSON_B
```

Stronger than Shape 1: asserts the *cmake-perceived* structure
is identical, catching issues like:
- An argument gersemi treats as equivalent but cmake parses
  differently.
- Command-order mattering (e.g., `set` before `add_library` vs
  after).
- A printer that drops a flag, or adds an extra one cmake
  silently ignores.

Costs ~10 seconds per configure on z3 (cacheable). Run on a
subset, nightly, or as a gating check.

## What Bar #3-lite gives the project

- **No `yelu_cmake` IR involvement.** Lives entirely at the
  `Lang_cmake` layer. Decoupled from theory split, Y17, the
  `yelu_cmake` ↔ `yelu_cmake_normal` design space.
- **Coverage signal for `Lang_cmake.exp`.** The 133 commands
  were carved against the CMake tutorial corpus, much narrower
  than z3. Every parse failure on z3 surfaces a missing or
  shallow command in the cmake AST — a real-world version of
  the "Known IR shape gaps" tracking, but at the cmake-AST
  layer.
- **A cmake parser yelu doesn't have.** Y8 (multi-stage core),
  Y17 typing, and the full Bar #3 all become much easier to
  think about with a real cmake parser in hand.
- **Free baseline via gersemi.** If
  `gersemi(input) == gersemi(parse_print(input))`, you know the
  parser+printer correctly captures syntactic content.

## Risks where Bar #3-lite gets uglier

- **Comments**: tree-sitter parses them as CST nodes; you can
  either carry them through into `Lang_cmake.exp` (adds comment
  nodes; invasive) or canonicalize via gersemi (lose them in
  round-trip but pass the diff). The latter is fine for the
  research claim.
- **Bracket arguments** `[==[...]==]` are syntactically
  delimited but semantically opaque (used for embedded code
  generation, regexes). Parser preserves the literal text and
  the bracket level; printer reuses the appropriate level.
  tree-sitter handles this; the printer needs care.
- **Generator expressions** `$<...>` inside arguments: parse as
  opaque strings (matching how yelu_cmake already treats them
  as `Ycs_eval`). Pass the literal text through.
- **Per-file vs per-project round-trip.** Shape 1 is per-file —
  `include()` and `add_subdirectory()` are preserved as
  literal calls. Shape 2 (file-API) is per-project — cmake
  follows them at configure time.

---

# Bar #3 — full hand rewrite

The original manifesto claim: rewrite a project's CMakeLists in
`yelu_cmake` and prove structural equivalence with the original.

Two valid framings:

| Framing | Approach | Where it lands |
| --- | --- | --- |
| **Mechanical translation** | Write a cmake source → yelu_cmake source translator. | Out of scope — even Bar #3-lite (parse → `Lang_cmake.exp` → reprint cmake) doesn't generate *yelu_cmake* source; it round-trips the cmake AST. Producing yelu_cmake source would require modeling cmake semantics, not just syntax. |
| **Hand rewrite, structural equivalence** | Read the original cmake, write the equivalent OCaml using `Yelu_cmake_utils`, emit, diff. | What the manifesto means. |

"Structural equivalence" can mean two different verification
shapes:

- **Text-level**: emitted cmake byte-identical (up to formatting)
  to the original. Strong claim; requires preserving the original
  DSL (`z3_add_component`, `add_llvm_library`, etc.) as
  yelu_cmake `function()` calls — not replacing with OCaml
  helpers.
- **Behavior-level**: emitted cmake configures + builds with
  identical output. Weaker; allows refactoring the DSL out of
  cmake into OCaml.

The text-level claim is the manifesto target. The behavior-level
claim is more achievable and still scientifically interesting.

## yelu_cmake coverage matrix

Cross-referencing the unique cmake commands used by each project
against the 14 yelu_cmake theories. Categories:

- **Covered** — `Yelu_cmake_utils` helper exists, IR ctor
  exists, `emit_ast` produces valid cmake.
- **Partial** — helper exists with documented gaps (see
  `status.md` "Known IR shape gaps") or signature differences.
- **Missing — modelable** — no IR ctor today; surface
  straightforward to add.
- **Missing — hard** — adding the surface is its own substantial
  feature; the project depends on it non-trivially.

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
| Missing — hard | ~35 | `tablegen` / `add_public_tablegen_target` (LLVM TableGen integration — 379 + 68 uses); LLVM's CMake build-time scripting via `cmake -P`; multi-config generator handling; the host-tool / cross-compile dance; multi-target arch detection |

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

## Specific blockers (full Bar #3)

### Shared by both

1. **`cmake_parse_arguments`** — the OCaml-native answer is
   "OCaml functions have kwargs natively." But the projects use
   this from within cmake `function()`s. Text-level equivalence
   requires modeling it in yelu_cmake (could be a Yelu1 ctor
   that emits the call directly).
2. **Cross-theory generator expressions** — both projects use
   `$<BUILD_INTERFACE:...>`, `$<INSTALL_INTERFACE:...>`,
   `$<TARGET_PROPERTY:...>` etc. extensively. Today these flow
   through yelu_cmake as opaque `EString`s via `Ycs_eval`.
   Sufficient for emission but means yelu_cmake cannot reason
   about them (and Y17 cannot type them).
3. **Subdirectory scope isolation** — yelu_cmake records
   `add_subdirectory` but does not enforce var / target scope
   isolation. z3 has 89 subdirectories; llvm has hundreds. The
   emitted cmake works because real cmake provides the scoping,
   but yelu_cmake's own eval / typecheck cannot reason across
   the boundary.
4. **Custom `Find*.cmake` modules** — both ship their own. The
   `find_package` flow calls into yelu_cmake's modeled find
   primitives but doesn't execute a custom `Find*.cmake`
   module's logic. For text-level equivalence, these modules
   need to be rewritten in yelu_cmake too.
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

---

# Recommended path

Bar #3-lite first; full Bar #3 layered on top once it succeeds.

### Stage 0 — Cmake parser via tree-sitter (~2–3 weeks)

Build the parser + round-trip harness:

- Python wrapper around `tree-sitter-cmake`. Emits JSON CST to
  stdout.
- OCaml `cmake_parse_source` module. Reads JSON, walks the CST,
  produces either:
  - (Variant 1, faster) an *untyped* `Cmake_source_ast` that
    captures `(command_name, raw_args, body_block?)` — enough to
    round-trip but doesn't test `Lang_cmake.exp`.
  - (Variant 2, slower) `Lang_cmake.exp` directly — tests
    `Lang_cmake.exp` expressiveness per command.
- Pretty-printer for whichever AST shape — reuse
  `Lang_cmake_pp` for Variant 2; trivial new printer for
  Variant 1.
- Test harness:
  `gersemi(input) == gersemi(parse_print(input))` per file.

Start with Variant 1 to validate the lexer / CST walking;
upgrade to Variant 2 once round-trip is green for a corpus of
small files. The two variants share most of the code.

### Stage 1 — Run round-trip on z3 (~1–2 weeks after Stage 0)

Apply the Variant 2 round-trip to all 200 z3 cmake files. Each
parse failure or diff is a coverage gap in `Lang_cmake.exp` or
the printer; address command-by-command. Expected outcomes:

- 60–80% of z3 files round-trip cleanly on first run.
- Remaining files exercise less-covered `Lang_cmake.exp`
  commands; gap list grows the cmake AST.
- Coverage matrix becomes data-backed rather than
  estimate-based.

### Stage 1.5 — File-API round-trip on z3 (~1 week)

Add Shape 2 as a stronger oracle for z3's top-level. Catches
issues the syntactic oracle misses.

### Stage 2 — Round-trip on llvm/llvm (~1+ months)

Same parser, much wider command vocabulary. Coverage matrix
grows substantially. Bar #3-lite milestone for llvm: every
cmake file in `llvm/llvm` round-trips through `Lang_cmake.exp`.

### Stage 3 — Full Bar #3 on small targets (~1–2 months)

Don't attempt z3 or llvm hand rewrites until Bar #3-lite has
mapped the coverage. Start with **fmt / catch2 / rapidjson**
as Stage 3 calibration — 1–2k cmake LOC, no custom DSL. Pick
the version pinned in a real project we care about, not latest.

### Stage 4+ — Full Bar #3 on z3 then llvm (months to quarters)

Only attempt after Stage 1+2 establishes that the cmake AST
is rich enough, *and* Y17 typing has landed (the typing rules
will surface what's expressible in yelu_cmake).

---

## What yelu_cmake would gain from doing this

Beyond the manifesto claim:

- **Real-world IR shape feedback** — the current IR was designed
  against the CMake tutorial + RunCMake corpus. Real projects
  use cmake idioms the corpus doesn't exercise.
- **Forced honesty on gaps** — the "Known IR shape gaps" list is
  currently passive (tests that document the stubs, no caller
  demanding the fix). Real-project parsing surfaces which gaps
  actually matter.
- **Bench for Y17** — typing rules can be exercised against real
  cmake projects; failure modes are more informative than
  synthetic examples.
- **A cmake parser** — useful component independent of the
  Bar #3 claim (Y8, Y17, future tooling all benefit).

## What yelu_cmake would NOT gain from doing this prematurely

- It is **not a substitute** for the structural cleanup items in
  `status.md`. Splitting `cmake_op`, moving emit / convert arms
  to fragments, the theory split (`doc/yelu_theory/plan.md`),
  Y17 typing — none are blocked by Bar #3-lite, and Bar #3
  (hand rewrite) benefits from each being in place first.
- It is **not a CI-able test for full Bar #3**. Behavior-level
  equivalence runs real builds; days of CI time.
  Manifesto-shaped, not regression-shaped. Bar #3-lite (Shape 1
  / Shape 2) is CI-able.

## Open questions

- **Which fmt / catch2 / rapidjson version for Stage 3?** Pin
  the version a real project we care about uses, not latest.
- **Verification strategy for "structural equivalence"** —
  text-diff after gersemi normalization? Compare the generated
  build graph (`cmake --graphviz`)? File-API JSON diff? Pick
  one before starting Stage 3.
- **DSL preservation vs OCaml-side helpers** — for full Bar #3,
  text-level equivalence requires DSL preservation (emit a
  `z3_add_component` cmake function). Decide whether the
  research claim needs text-level, or whether behavior-level
  is enough.
- **tree-sitter-cmake grammar gaps** — until we actually run
  the round-trip, we don't know whether the grammar covers
  every shape z3 / llvm use. Expect to file 1–3 upstream PRs
  during Stage 0.
