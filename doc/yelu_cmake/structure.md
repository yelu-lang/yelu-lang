# yelu_cmake — Module Structure

Code-anchored guide to `src/langs/yelu/`. For the *why* see
`design.md`; for current open work see `status.md`.

The project hosts two distinct cmake-domain languages:

- **`yelu_cmake`** — CMake-command-faithful compatibility form. The
  workhorse: what step files build, what the parser produces, what
  emits to text. Bare-name modules (`Yelu_cmake`, `Yelu_cmake_eval`,
  `Yelu_cmake_emit`, …) belong to it.
- **`yelu_cmake_normal`** — normalized/reorganized form of the same
  cmake-domain language. Modules carry the `_normal` infix
  (`Yelu_cmake_normal_eval`, fragment files
  `yelu_cmake_normal_<theory>.ml`).

Translation between the two lives in `Yelu_cmake_convert`
(`to_normal` / `from_normal`).

## Top-level files

```
src/langs/yelu/
├── yelu_cmake.ml                core types (expr) + env + frame stack + helpers
├── yelu_cmake_eval.ml           yelu_cmake evaluator           (cmake-faithful)
├── yelu_cmake_normal_eval.ml    yelu_cmake_normal evaluator    (normalized form)
├── yelu_cmake_convert.ml        to_normal / from_normal + public eval API
├── yelu_cmake_emit.ml           yelu_cmake.expr → Lang_cmake.exp (PRODUCTION)
├── yelu_cmake_emit_debug.ml     yelu_cmake.expr → cmake text     (DIAGNOSTIC)
├── yelu_cmake_utils.ml          ergonomic ctors for yelu_cmake.expr
├── yelu_parse.ml                concrete syntax → yelu_cmake.expr
├── yelu_lexer.ml                shared tokens (used by both parsers)
└── fragments/                   per-theory modules (see below)
```

The legacy-to-yelu_cmake bridge lives in
`src/langs/yelu_legacy/yelu_cmake_legacy_bridge.ml`. The new code
in `src/langs/yelu/` does not import it; it remains callable from
the byte oracle in `test_yelu_compile.ml` and the pair-wise oracle
in `test_yelu_cmake_parse.ml`.

### `yelu_cmake.ml`

Open `expr` type (`type expr = ..`); shared values (`VString`,
`VBool`, `VInt`, `VUnit`, `VTarget`, …); the `env` record; helpers
used by every fragment.

The env carries four conceptually distinct kinds of state (kept flat
for eval simplicity, grouped by comment):

| Group               | Fields                                                                                                    |
| ------------------- | --------------------------------------------------------------------------------------------------------- |
| Configure script    | `frames` (stack of `{ locals; parent_snapshot; touched }`), `files`                                       |
| Declarations / logs | `project`, `cmake_min_version`, `messages`, `subdirectories`, `includes`, `find_packages`, `try_compiles` |
| Build / test graph  | `targets`, `custom_targets`, `custom_commands`, `target_properties`, `testing_enabled`, `tests`           |
| Install             | `install_rules`                                                                                           |

The frame stack models cmake's hybrid lexical-feel-with-dynamic-back-door
scope: snapshots on push, plus a `touched` set to distinguish "never
modified" from "explicitly unset" for `block(PROPAGATE)` and
`return(PROPAGATE)`. Three control-flow exceptions live here:
`Break_loop`, `Continue_loop`, `Return_function { env_at_return;
propagated }`. See `../cmake/scope_and_control_flow.md`.

Currently both languages share this same `expr` extensible type via
`type expr += ...`. Splitting it into two distinct types (per language)
is queued as a post-retirement cleanup — see status.md item 7.

### `yelu_cmake_eval.ml` / `yelu_cmake_normal_eval.ml`

Each is a small `eval_expr env expr` driver that dispatches to the
appropriate fragment's `eval_case`. `Yelu_cmake_eval` calls the
`Yelu_cmake_<theory>` fragments; `Yelu_cmake_normal_eval` calls the
`Yelu_cmake_normal_<theory>` fragments. The split exists because the
original combined evaluator passed 900 lines and mixed four concerns.
Both end on the same shared cases (literals, `ELet`, control flow),
with a final `fail "unknown ..."` for unmatched constructors.

### `yelu_cmake_convert.ml`

Public API: `eval_yelu_cmake_expr`, `eval_yelu_cmake_normal_expr`,
`to_normal`, `from_normal`. The two conversion functions are
constructor-by-constructor isomorphisms — most cases are mechanical
(rename `ECmakeFoo` → `EFoo`) but a few (e.g. cmake `ECmakeOption` →
normal `ESetVar`) do real shape change.

### `yelu_cmake_emit.ml` (production emitter)

`emit_ast e` lowers a `yelu_cmake.expr` to `Lang_cmake.exp` (the
cmake syntax AST); `emit_script e` runs `Lang_cmake_pp.pp` to
produce text. This is the production path for every step binary and
every test that needs cmake text output.

Four erasure helpers carry the real complexity:

- `arg : expr → Lang_cmake.arg` — Bare/Quoted/Bracket selection
  matches legacy compile's policy: quote when cmake would otherwise
  mis-tokenize (empty / whitespace / `$<...>` / `${...}` / `\\`).
- `target_arg : expr → string` — target / cvar / file-name positions,
  unquoted by cmake convention.
- `cond_tokens : bool expr → string list` — cmake's
  `cond = string list`. `EVar` in cond position renders as the bare
  name (cmake's `if(FOO)` auto-derefs identifiers), distinct from
  arg-position `${name}`. AND/OR always wraps in `(...)` tokens.
- `ELet` substitution — threaded via a `subst : expr Map.M(String).t`
  through every erasure; the let header is dropped from output, and
  `EVar` references that match the env get substituted.

Verified by the byte-equality oracle in `test_yelu_compile.ml`: for
all 194 production-AST test programs, `legacy_compile → pp` and
`bridge → emit_ast → pp` produce byte-identical text.

### `yelu_cmake_emit_debug.ml` (diagnostic aid)

Older direct-text emitter. Not on the production path; kept callable
as a diagnostic aid for human inspection of yelu_cmake output without
going through the cmake AST, and as a regression target for the
step-level tests (`test_yelu_steps`, `test_yelu_emit_debug`,
`test_yelu_cmake` in test-runcmake) that were written against its
specific format conventions (always-quote, trailing newline).

Same substitution-env architecture as `emit_ast`; output goes to a
text-string list via `Fmt.str` instead of constructing a typed AST.

### `yelu_cmake_utils.ml`

Ergonomic AST constructors for `yelu_cmake.expr`. ~70 helpers
mirroring the surface of `Lang_yelu_utils` in `yelu_legacy/` but
returning `expr` directly. Step files import this to build the
production AST; the parser builds the same AST directly in its
dispatchers.

The helper module reuses `Lang_cmake_strings.of_*` for cmake
enum→string conversion (`message_mode`, `supported_lang`,
`compatibility`, etc.). Long-tail post-retirement cleanup is item F
in retirement_plan: have the parser call these helpers too, so the
project has one source of truth for "what does this command shape
become in the IR".

### `yelu_parse.ml`

Concrete-syntax parser (Angstrom-based) that consumes the shared
`Yelu_lexer` tokens and produces `yelu_cmake.expr` directly. Covers
all 12 cmake command families with per-family dispatchers
(`p_var_stmt_y1`, `p_target_command_y1`, `p_string_command_y1`, …).

The pair-wise oracle in `test_yelu_cmake_parse.ml` asserts that
`source → Yelu_parse → emit_ast` produces byte-identical text vs
`source → Lang_yelu_parse → Yelu_cmake_legacy_bridge → emit_ast`
across 125 covered cases. Four legacy-parser bugs surfaced but
deferred — see status.md.

### `yelu_lexer.ml`

Lexer / tokenization shared by both parsers. Historically named
`Lang_yelu_lexer` (and re-relocated in items E-lite and G); the
module is now in `src/langs/yelu/` since it's shared infrastructure
that survives any future legacy deletion. The legacy parser in
`yelu_legacy/lang_yelu_parse.ml` imports `Yelu_lexer` from here
(legacy depending on new is the legitimate direction).

## Fragments

```
src/langs/yelu/fragments/
├── yelu_cmake_<theory>.ml             yelu_cmake ctors  (15 files)
└── yelu_cmake_normal_<theory>.ml      yelu_cmake_normal ctors  (15 files)
```

For each domain there is *usually* a matched pair: the
`yelu_cmake_normal` fragment defines a value-oriented set of
constructors; the `yelu_cmake` fragment defines the cmake-shaped
equivalents (often with output-variable side effects).
`yelu_cmake_convert.ml` maps between them. A few asymmetries by
design:

- `yelu_cmake_normal_bool` / `yelu_cmake_normal_int` — pure, shared
  between both languages; no matched cmake-side module because
  cmake's bool / int ops *are* the pure ops.
- `yelu_cmake_if` — cmake-only statement-if shape; the normal-side
  uses the core `EIf` expression form.

Note: theories like `bool`, `int`, `string`, `list`, `store` are
general-purpose, not cmake-specific. They live under the
`yelu_cmake_normal_` prefix because the historical fragment bundle
didn't distinguish. Splitting general from cmake-specific is queued
as post-retirement cleanup item 6.

### Theory list

`Kind` distinguishes a real theory (value-oriented, eval is
meaningful) from a cmake compatibility surface (emit-faithful, eval
delegates to real cmake). `Mixed` = real for the common ops, compat
for the long tail. See `design.md`'s "Fragment kinds" section.

| Theory     | Kind   | yelu_cmake (lines) | yelu_cmake_normal (lines) | Notes                                                                                                     |
| ---------- | ------ | -----------------: | ------------------------: | --------------------------------------------------------------------------------------------------------- |
| `bool`     | real   |                  — |                        37 | shared: and / or / not                                                                                    |
| `int`      | real   |                  — |                        45 | shared: add / less / equal                                                                                |
| `if`       | real   |                 31 |                        23 | cmake statement-if vs normal expression-if                                                                |
| `store`    | real   |                 81 |                        11 | var set / unset / PARENT_SCOPE / option; cache / env deferred                                             |
| `target`   | real   |                181 |                       275 | add_executable, add_library, target_* visibility-aware                                                    |
| `install`  | real   |                105 |                       102 | install(TARGETS / FILES / EXPORT) + package-config writer                                                 |
| `test`     | real   |                 19 |                        19 | enable_testing, add_test                                                                                  |
| `dir`      | real   |                 31 |                        15 | add_subdirectory + dir-level include/compile/link commands; scope isolation deferred                      |
| `string`   | mixed  |                224 |                        61 | core (concat/replace/length/equal): real; regex / timestamp / uuid / json: emit-faithful stubs            |
| `list`     | mixed  |                105 |                        31 | core (append/get/length/join/sort): real; advanced transforms: emit-faithful                              |
| `path`     | mixed  |                130 |                        44 | core (set / normalize / get-filename): real; native/cmake conversion + many subcommands: emit-faithful    |
| `file`     | mixed  |                131 |                        41 | in-memory fs for write / read / exists: real; glob / copy / many fs ops: emit-faithful                    |
| `property` | mixed  |                 80 |                        47 | target-property: real; global / source / test / directory scopes: emit-faithful                           |
| `cmake_op` | compat |                390 |                       103 | project / message / math / include / function / macro / block / while / foreach / execute_process — broad surface bucket |
| `find`     | compat |                 37 |                        13 | find_package / library / path / program / file — eval is placeholder; real semantics depend on host       |
| `try`      | compat |                 60 |                        20 | try_compile + try_run — eval stubs result; real probe runs only when emitted cmake script runs            |

Shared theories (`bool`, `int` — no yelu_cmake counterpart) are used
directly by both evaluators.

### Fragment shape

Every fragment file follows the same skeleton:

```ocaml
open Base
open Yelu_cmake
(* open Yelu_cmake_normal_<...> if it builds on another theory *)

type expr +=
  | ECmakeFoo of { ... }       (* yelu_cmake side *)
  | EFoo of { ... }            (* yelu_cmake_normal side *)

let eval_case ~eval env = function
  | ECmakeFoo { ... } ->
      (* compute new env + return value *)
      Some (env', VUnit)
  | _ -> None                  (* let the next fragment try *)
```

The `~eval` parameter is the recursive evaluator passed in by
`Yelu_cmake_eval` / `Yelu_cmake_normal_eval`. The `Some / None` shape
lets each fragment claim only the constructors it owns; the driver
tries fragments in a fixed order until one matches.

## Adding a constructor — the 5-step recipe

For a new cmake command `cmake_thing(arg1 arg2 OUT out)`:

1. **yelu_cmake fragment** in `fragments/yelu_cmake_<theory>.ml`:
   add `ECmakeThing of { arg1 : expr; arg2 : expr; out : string }`
   plus an `eval_case` arm.
2. **yelu_cmake_normal fragment** in
   `fragments/yelu_cmake_normal_<theory>.ml`: add
   `EThing of { ... }` plus its `eval_case` arm (often a thin
   re-shape of the cmake-side eval).
3. **Legacy bridge** (only if production tests construct this
   constructor) in `yelu_legacy/yelu_cmake_legacy_bridge.ml`: add a
   match arm under the appropriate `Y<theory>_*` group producing
   `ECmakeThing { ... }` from the legacy AST.
4. **Emit** in `yelu_cmake_emit.ml`: add a match arm producing the
   corresponding `Lang_cmake.exp` value. The byte-equality oracle in
   `test_yelu_compile.ml` will immediately verify it matches legacy
   compile output. Optionally also add a match arm to
   `yelu_cmake_emit_debug.ml` if step tests need to see the value.
5. **Convert** in `yelu_cmake_convert.ml`: one arm in `to_normal`
   (`ECmakeThing → EThing`) and one in `from_normal`
   (`EThing → ECmakeThing`).

Then add at least one test in `test/test-yelu/test_yelu_*.ml` and,
if the construct interacts with cmake's runtime semantics, one
cmake-backed test in `test/test-runcmake/test_yelu_cmake.ml`.

For pure-passthrough constructors (no real eval semantics — emit and
hope cmake handles it) the eval case can return `Some (env, VUnit)`;
mark the case with a comment noting the deferral.

## Tests

```
test/test-yelu/
├── yelu_test_helpers.ml            shared assertions / fixtures
├── test_yelu_lift_lower.ml         yelu_cmake ↔ yelu_cmake_normal roundtrip   (65)
├── test_yelu_bridge.ml             legacy AST → yelu_cmake.expr               (43)
├── test_yelu_steps.ml              tutorial v1 step1–12 + extras              (19)
├── test_yelu_emit.ml               yelu_cmake.expr → Lang_cmake.exp           (—)
├── test_yelu_emit_debug.ml         yelu_cmake.expr → cmake text (direct)      (3)
├── test_yelu_function.ml           F2 dynamic-scope function                  (14)
├── test_yelu_foreach.ml            foreach scope + loop variants               (5)
└── test_yelu_block_return.ml       block / return / PARENT_SCOPE              (26 probes)
```

```
test/test-runcmake/
├── test_yelu_cmake.ml              yelu_cmake → real cmake configure          (40)
└── test_runcmake_yelu.ml           stdout-equiv against reference             (50)
```

Parser tests (`test/test-yelu/test_yelu_cmake_parse.ml`, 295 incl.
125 pair-wise oracle cases) and compile tests
(`test/test-yelu/test_yelu_compile.ml`, 194) both verify byte-
identical text against the legacy compile output.

## Cross-references

- `design.md` — the *why* behind the two-language model, theory
  invariants, let-binding architecture, F2 function semantics.
- `retirement_plan.md` — record of how we got here + remaining
  retirement items (F, final E) + post-retirement design queue.
- `status.md` — living tracker for current work.
- `../worklog/worklog_2026_05.md` — chronological history of the
  harness (uses older "Yelu1 / Yelu2 / yelu_tiny" vocabulary; left
  as historical record).
- `../cmake/scope_and_control_flow.md` — frame-stack design, 26
  probes.
- `../cmake/cache_semantics.md` — cache namespace deferred behavior.
