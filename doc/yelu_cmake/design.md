# yelu_cmake — Theory Composition Design Notes

Durable reference for the yelu_cmake theory-composition harness.
For current open work see `status.md`; for the file-by-file module
guide see `structure.md`. Update this file only when the underlying
design changes.

> **Vocabulary note (post-G).** This doc was drafted during the
> harness phase and uses the older terminology throughout. The
> substance is current, but read with this glossary in mind:
>
> | Older name (in this doc)         | Current name (in code)                     |
> | -------------------------------- | ------------------------------------------ |
> | `yelu_tiny` / "tiny core"        | `yelu_cmake` (the core module + IR)        |
> | `Yelu1` / "CMake-shaped surface" | `yelu_cmake` (the cmake-faithful language) |
> | `Yelu2` / "better Yelu theories" | `yelu_cmake_normal` (the normalized form)  |
> | `yelu_surface_cmake_<theory>`    | `yelu_cmake_<theory>` (fragment)           |
> | `yelu_theory_<theory>`           | `yelu_cmake_normal_<theory>` (fragment)    |
> | "lift" (Yelu1 → Yelu2)           | `Yelu_cmake_convert.to_normal`             |
> | "lower" (Yelu2 → Yelu1)          | `Yelu_cmake_convert.from_normal`           |
>
> A future rewrite pass can fold these in-line; for now the glossary
> keeps the design intact while pointing readers at the live names.

The next theory-composition experiment should not refactor the current
`yelu_cmake` pack first. That pack already contains CMake-specific behavior:
mutable cvars, cache quirks, lowering assumptions, parser coverage, and
wellform checks. Using it as the first testbed would mix two questions:

- Can extensible theory composition work?
- Can the current CMake pack behavior be preserved?

Start with a tiny parallel language instead.

## Direction

This is the replacement path for the earlier failed theory-splitting attempt in
`src/langs/yelu/fragments`. The old design treated CMake command families as
theories directly. That made fragments like `string` accept `T.expr` and `T.var`,
mixing three roles:

```text
pure theory:
  operations over semantic values

surface:
  source/target-shaped API, often effectful

bundle:
  composed language that closes recursion, evaluation, checking, and lowering
```

The new experiment keeps those roles separate:

```text
theory fragments:
  yelu_theory_string, yelu_theory_int, yelu_theory_bool, yelu_theory_if

CMake surface fragments:
  yelu_surface_cmake_string, yelu_surface_cmake_if

bundles:
  Yelu1 = tiny core + CMake-shaped surfaces
  Yelu2 = tiny core + better Yelu theories
```

The important claim is not that CMake itself becomes pure. The claim is that
configure-time CMake surfaces can often be lifted into better pure theories, then
lowered back through CMake surfaces when CMake output is required.

This gives two migration directions:

```text
new Yelu code can reuse the CMake backend:
  Yelu2 -> Yelu1 -> CMake

existing CMake-shaped code can be modernized:
  Yelu1 -> Yelu2 -> Yelu1 -> CMake
```

The initial target is configure-time computation and configure-time effects.
Build-relevant declarations come later because they interact with delayed
generator expressions and generated build rules.

### Fragment kinds: real theory vs compatibility surface

Not every `yelu_theory_*` module carries the same kind of semantic weight.
After landing all 14 production theories as tiny slices, two kinds of
fragment emerged — and the distinction matters for reading the theory
list and for planning post-retirement cleanup.

- **Real theory.** Value-oriented and executable inside tiny semantics.
  Eval produces meaningful results that can be tested without consulting
  cmake. Examples: `bool`, `int`, core parts of `string`, core parts of
  `list`, `if`, the build-graph parts of `target`, the frame parts of
  `store`.
- **CMake compatibility surface.** Emit-faithful shape whose semantics
  are mostly delegated to real cmake. Eval is often a stub that binds an
  output variable to a plausible value (empty string, `false`, an
  unmodified input) and trusts cmake to handle the real work. Examples:
  much of `cmake_op`, advanced `file`, `find`, `try`, advanced `string`
  (regex / timestamp / uuid / json), advanced `path`, non-target
  property scopes.

Both are legitimate — the surfaces buy bridge faithfulness and emit
coverage cheaply, and the real theories are where invariants and proofs
will eventually live. The risk is rhetorical: do not present every
`yelu_theory_*` file as equally pure or principled. `structure.md`'s
theory list carries a `Kind` column to keep this distinction visible.

Post-retirement (Y17 territory): decide which compatibility surfaces are
worth promoting to real theories — at minimum genex, plausibly find /
try / `cmake_op` subsets.

## Goal

Build a minimal experiment that proves this composition pattern:

```text
open expression syntax
effects as expressions returning unit
closed outer recursion per composed language
fragment composition
translation between composed languages
evaluation equivalence
```

The initial experiment can omit per-fragment checking. Evaluation and
equivalence are enough to validate the composition pipeline.

## Layout

The current file layout is in `structure.md`. The original prototype
sketch listed `yelu_tiny_eval.ml` as a single evaluator; that has since
split into `yelu_tiny_yelu1.ml`, `yelu_tiny_yelu2.ml`, and
`yelu_tiny_translate.ml` once the combined module passed 900 lines.

## Tiny Core

The core language should stay deliberately small.

```ocaml
type expr = ..

type value =
  | VString of string
  | VBool of bool
  | VInt of int
  | VList of value list
  | VTarget of string
  | VUnit
```

Core expression constructors:

```ocaml
type expr +=
  | EVar of string
  | EString of string
  | EBool of bool
  | EInt of int
  | EUnit
  | ESetVar of string * expr
  | ESeq of expr list
```

Runtime environment:

```ocaml
type env =
  { vars : value Map.M(String).t
  ; targets : target Map.M(String).t
  }
```

The outer composed language owns the closed recursion:

```ocaml
val eval_expr : env -> expr -> env * value
```

Because `expr` is open, every composed evaluator must have an explicit unknown
case. Unknown expression handling should fail loudly in evaluation.

## Fragment 1: CMake-Like String

Pick only a few examples from the current CMake string fragment. Model them as
effectful output-variable expressions returning `unit`, because this is the
honest shape of CMake's `string(...)` API.

```ocaml
type expr +=
  | ECmakeStringConcat of { inputs : expr list; out : string }
  | ECmakeStringToupper of { input : expr; out : string }
  | ECmakeStringReplace of {
      match_ : expr;
      replace : expr;
      input : expr;
      out : string;
    }
  | ECmakeStringLength of { input : expr; out : string }
```

CMake-like expressions update the runtime environment and return `VUnit`.

```text
ECmakeStringToupper { input = EString "abc"; out = "X" }
=> env["X"] = VString "ABC", result = VUnit
```

Do not model CMake cache behavior or configure-time variable scoping in the
first experiment.

## Fragment 2: Better String

Define the API the language should prefer.

```ocaml
type expr +=
  | EStringConcat of expr list
  | EStringUpper of expr
  | EStringReplaceAll of {
      needle : expr;
      replacement : expr;
      haystack : expr;
    }
  | EStringLen of expr
```

The names and surface model can differ from the CMake-like API, but evaluation
should target the same `value` semantics.

Saving a pure result is explicit through core `ESetVar`:

```ocaml
ESetVar ("X", EStringUpper (EString "abc"))
```

## Composed Languages

Define two composed languages:

```text
yelu1 = yelu_tiny + yelu_cmake_string
yelu2 = yelu_tiny + yelu_better_string
```

In OCaml this can be two modules with different closed evaluators:

```ocaml
module Yelu1 = struct
  let rec eval_expr env = function
    | EString s -> VString s
    | EVar x -> ...
    | ECmakeStringConcat { inputs; out } -> ...
    | _ -> failwith "unknown expr in Yelu1"
end

module Yelu2 = struct
  let rec eval_expr env = function
    | EString s -> VString s
    | EVar x -> ...
    | EStringConcat xs -> ...
    | _ -> failwith "unknown expr in Yelu2"
end
```

This is the selected strategy:

```text
open syntax locally
closed semantics per outer language
```

## Translation And Equivalence

Use directional translation names that match the research intent:

```ocaml
val lift_yelu1_to_yelu2 : expr -> expr
val lower_yelu2_to_yelu1 : expr -> expr
```

Core checks:

```text
lifting safety:
  eval_yelu1 e == eval_yelu2 (lift_yelu1_to_yelu2 e)

lowering safety:
  eval_yelu2 e == eval_yelu1 (lower_yelu2_to_yelu1 e)

modernization roundtrip:
  eval_yelu1 e
  ==
  eval_yelu1 (lower_yelu2_to_yelu1 (lift_yelu1_to_yelu2 e))
```

Equivalence compares both final environment and result value.

Research workflows:

```text
new language reuses old stack:
  yelu2 -> yelu1 -> emitted CMake

existing CMake-shaped code can be lifted:
  yelu1 -> yelu2 -> yelu1 -> emitted CMake
```

At first, run this at the AST/evaluator level. Later, add CMake script emission
and compare `cmake -P` output for original Yelu1 programs versus lifted/lowered
roundtrips.

Start with hand-written examples:

```ocaml
ESeq [
  ECmakeStringToupper { input = EString "b"; out = "TMP" };
  ECmakeStringConcat { inputs = [ EString "a"; EVar "TMP" ]; out = "OUT" };
  EVar "OUT";
]
```

translates to:

```ocaml
ESeq [
  ESetVar ("TMP", EStringUpper (EString "b"));
  ESetVar ("OUT", EStringConcat [ EString "a"; EVar "TMP" ]);
  EVar "OUT";
]
```

Both evaluate to final value:

```text
"aB"
```

and final environment containing:

```text
OUT = "aB"
TMP = "B"
```

After hand-written examples pass, add small generated expression cases.

## What To Omit Initially

Omit these from the first milestone:

- per-fragment type checking
- CMake lowering
- parser integration
- wellform checks
- cache/cvar semantics
- regex

The first milestone should only validate composition, evaluation, translation,
and equivalence.

## Current Prototype

The current prototype already uses one open `expr`. Effects are expressions that
return `VUnit` and thread `env`.

Implemented pieces:

- tiny core: `EVar`, literals, `EUnit`, `ESetVar`, `ESeq`
- shared store fragment: unset and variable-defined predicate
- CMake-like store fragment: real `unset` and `if(DEFINED ...)` predicate surface
- CMake-like string fragment: output-name effects returning `VUnit`
- better string fragment: pure string/int expressions
- shared bool fragment: boolean operators and string equality
- shared int fragment: integer addition/comparison
- shared list fragment: list literals, append, and length
- CMake-like list fragment: named-list effects for append, get, length, and join
- shared path fragment: filename and normal-path operations
- CMake-like path fragment: real `cmake_path` SET, GET FILENAME, and NORMAL_PATH forms
- shared target fragment: target values, executable declaration, target-exists
  predicate, target-sources mutation, target-link-libraries mutation, and
  target-include-directories mutation
- CMake-like target fragment: real `add_executable`, `target_sources`, and
  `target_link_libraries`, `target_include_directories`, plus `if(TARGET ...)`
  predicate surface
- CMake-like if fragment: statement-style `if` returning `VUnit`
- better if fragment: expression-style `if` returning the selected branch value
- `Yelu1 = tiny core + bool + cmake_if + cmake_string`
- `Yelu2 = tiny core + bool + better_if + better_string`
- lifting/lowering in both directions for simple cases
- semantic Yelu1 lift/lower roundtrip tests
- semantic equivalence tests comparing final `env` and final `value`
- tiny CMake script emitter for the Yelu1/CMake-surface subset
- CMake-backed tests under `test/test-runcmake/test_yelu_tiny_cmake.ml`
- first `yelu_cmake -> Yelu1` bridge slice under
  `src/langs/yelu_tiny/yelu_cmake_to_yelu1.ml`
- parser-fed bridge tests from existing Yelu source syntax through the old
  parser into tiny Yelu1

Current limitation:

- Translating nested pure string expressions back to CMake-like string effects
  requires temp hoisting. Current reverse examples use explicit `ESetVar`
  temporaries; automatic temp generation is a later pass.
- The first production bridge is deliberately partial. It covers only a narrow
  old `yelu_cmake` subset: simple string operations, simple variable set,
  `Ylet`, `Yif`, statement lists, list/path slices, and the first target
  declaration/source slices. Unsupported old CMake/Yelu behavior fails loudly
  instead of pretending to preserve semantics.

## Next Theory Plan

Add theories in an order that tests different composition pressure without
becoming full CMake too quickly.

Short-term priority is configure-time coverage. Build graph and build-time
surfaces are intentionally later.

1. Store theory

   Started. `EVar`, `ESetVar`, and `ESeq` still live in the tiny core, but the
   first explicit store-theory slice now covers mutation beyond assignment:

   ```ocaml
   EUnsetVar of string
   EVarDefined of string
   ```

   CMake-shaped surface:

   ```ocaml
   ECmakeUnsetVar of string
   ECmakeVarDefined of string
   ```

   Current bridge coverage includes old `Yexpr_is_defined`. The old production
   variable statement AST does not currently have a dedicated normal-variable
   `unset(NAME)` constructor. Normal unset-like behavior is encoded there as
   `Yvar_set` with an empty value list, while dedicated unset constructors exist
   only for cache/env (`Yvar_unset_cache`, `Yvar_unset_env`). Tiny Yelu keeps
   normal unset explicit with `EUnsetVar`/`ECmakeUnsetVar`; cache/env are
   intentionally postponed. The existing cache behavior report is
   `doc/cmake/cache_semantics.md`.

2. Bool / condition theory

   Implemented as a shared fragment plus paired `if` fragments.

   Shared bool operations:

   ```ocaml
   ENot of expr
   EAnd of expr * expr
   EOr of expr * expr
   ```

   String equality belongs to the string fragments because it projects operands
   through string semantics and returns a bool:

   ```ocaml
   ECmakeStringEqual of expr * expr
   EStringEqual of expr * expr
   ```

   CMake-shaped if:

   ```ocaml
   ECmakeIfStmt of { cond : expr; then_ : expr; else_ : expr option }
   ```

   Yelu-shaped if:

   ```ocaml
   EIfExpr of { cond : expr; then_ : expr; else_ : expr }
   ```

   Runtime semantics currently uses only the chosen branch env/value. A later
   checking/proof layer may still need branch joins for static analysis.

3. Int theory

   Implemented as a shared theory. String length already returns `VInt`;
   arithmetic and comparisons make this explicit rather than treating int as a
   passive primitive.

   Operations:

   ```ocaml
   EIntAdd of expr * expr
   EIntLess of expr * expr
   EIntEqual of expr * expr
   ```

4. List theory

   Started as a shared pure theory. It is useful for string concat/join and
   later generated tests. `EStringJoin` is a string/list bridge owned by the
   string theory, because it returns a string.

   Operations:

   ```ocaml
   EList of expr list
   EListAppend of expr * expr
   EListGet of expr * expr
   EListLength of expr
   ```

   String/list bridge:

   ```ocaml
   EStringJoin of { sep : expr; items : expr }
   ```

   CMake-shaped list surface:

   ```ocaml
   ECmakeListAppend of { list : string; items : expr list }
   ECmakeListGet of { list : string; index : expr; out : string }
   ECmakeListLength of { list : string; out : string }
   ECmakeListJoin of { list : string; glue : expr; out : string }
   ```

5. Path theory

   Mirrors the string experiment: pure path operations versus CMake output-var
   path commands. Path is trickier than string/list because several
   `cmake_path(...)` forms mutate a named path variable, while others write an
   `OUTPUT_VARIABLE`.

   Production status:

   - `doc/yelu_lang_coverage.md` marks `cmake_path` as covered at the
     script-pair level.
   - `test/test-runcmake/test_runcmake_yelu.ml` has inline reference-vs-Yelu
     pairs for the full current `cmake_path` surface: `ABSOLUTE_PATH`, `APPEND`,
     `APPEND_STRING`, `COMPARE`, `CONVERT`, `GET`, `HASH`, `HAS_*`,
     `IS_ABSOLUTE`, `IS_PREFIX`, `IS_RELATIVE`, `NATIVE_PATH`, `NORMAL_PATH`,
     `RELATIVE_PATH`, `REMOVE_EXTENSION`, `REMOVE_FILENAME`,
     `REPLACE_EXTENSION`, `REPLACE_FILENAME`, and `SET`.
   - Therefore the tiny path experiment should not try to prove the whole
     production CMake path surface again. Its job is to test the theory
     decomposition shape: CMake-shaped path effects in Yelu1, pure path
     expressions in Yelu2, and lift/lower preservation for a small slice.

   Confirmed first CMake-shaped slice:

   ```cmake
   cmake_path(SET P "/usr/local/bin/cmake")
   cmake_path(GET P FILENAME OUT)

   cmake_path(SET P "a/./b/../c")
   cmake_path(NORMAL_PATH P)

   cmake_path(SET P "a/./b/../c")
   cmake_path(NORMAL_PATH P OUTPUT_VARIABLE OUT)
   ```

   Direct `cmake -P` behavior:

   ```text
   GET FILENAME "/usr/local/bin/cmake" => "cmake"
   NORMAL_PATH "a/./b/../c" => "a/c"
   ```

   The tiny path experiment should begin with these exact real CMake forms and
   add CMake-backed checks immediately.

   Current tiny implementation covers this first slice.

   Pure candidate operations:

   ```ocaml
   EPathFilename of expr
   EPathNormalize of expr
   ```

   CMake-like candidate operations:

   ```ocaml
   ECmakePathSet of { path : string; input : expr; normalize : bool }
   ECmakePathGetFilename of { path : string; out : string }
   ECmakePathNormalPath of { path : string; out : string option }
   ```

   Defer `APPEND` until after this first slice because its mutating and
   output-variable variants need a clearer pure-path counterpart.

6. Target theory

   Target is the first theory that is not mostly configure-time value
   computation. It starts testing a global named namespace and build graph
   declaration.

   Split it into three layers and implement only the first layer initially.

   **Layer A: configure-time target namespace.**

   This is the right first tiny target slice. It creates target names and checks
   whether a target exists at configure time. The `TARGET name` check is a
   target-owned boolean predicate expression, not part of `if`; `if` remains the
   general conditioning theory.

   Current tiny implementation covers `add_executable` plus target existence.
   Target declarations live in `env.targets`; normal variables stay in
   `env.vars`.

   CMake-shaped surface candidates:

   ```ocaml
   ECmakeAddExecutable of { name : string; sources : expr list }
   ECmakeAddLibrary of {
     name : string;
     kind : cmake_library_kind;
     sources : expr list;
   }
   ECmakeTargetExists of string
   ```

   Better target theory candidates:

   ```ocaml
   EExecutable of { name : expr; sources : expr list }
   ELibrary of { name : expr; kind : library_kind; sources : expr list }
   ETargetExists of expr
   ```

   Minimal demo pipeline:

   ```text
   Yelu1:
     ECmakeAddExecutable { name = "app"; sources = [EString "main.c"] }
     ECmakeTargetExists "app"

   Yelu2:
     ESetVar ("APP", EExecutable { name = EString "app"; sources = [EString "main.c"] })
     ETargetExists (EVar "APP")
   ```

   The tiny evaluator uses a structured environment:

   ```ocaml
   type env =
     { vars : value Map.M(String).t
     ; targets : target Map.M(String).t
     }
   ```

   **Layer B: target property mutation.**

   Started with `target_sources`, `target_link_libraries`, and
   `target_include_directories`. This covers target-local build graph metadata
   while still avoiding generator expressions and build-time rule bodies.

   ```ocaml
   ECmakeTargetSources of { target : string; visibility : string; sources : expr list }
   ETargetAddSources of { target : expr; visibility : string; sources : expr list }
   ECmakeTargetLinkLibraries of { target : string; visibility : string; items : expr list }
   ETargetLinkLibraries of { target : expr; visibility : string; items : expr list }
   ECmakeTargetIncludeDirectories of { target : string; visibility : string; dirs : expr list }
   ETargetIncludeDirectories of { target : expr; visibility : string; dirs : expr list }
   ```

   Current implementation stores target sources, target link libraries, and
   target include directories as visibility-aware records in `env.targets`. The
   parser, bridge, evaluator, lowering, and tiny CMake emitter preserve
   `PRIVATE`/`PUBLIC`/`INTERFACE` for these slices:

   ```ocaml
   type target =
     { name : string
     ; sources : scoped_sources list
     ; ...
     }
   ```

   Later Layer B candidates:

   ```ocaml
   ECmakeTargetCompileDefinitions
   ```

   Better-theory candidates may use `ETargetAddSources`, `EWithLinkDeps`, and
   similar value-shaped graph updates instead of raw CMake command shapes.

   **Layer C: delayed target artifacts and build-time rules.**

   Postpone this layer. It includes generator expressions and commands whose
   bodies run during the build:

   ```ocaml
   ETargetFile of expr              (* $<TARGET_FILE:tgt> *)
   ETargetFileDir of expr           (* $<TARGET_FILE_DIR:tgt> *)
   ECmakeAddCustomCommand
   ECmakeAddCustomTarget
   ```

   These values are not ordinary configure-time strings or paths. They need
   delayed/build-time value modeling such as:

   ```ocaml
   VDelayed of delayed_value
   VBuildPath of build_path
   ```

   and should be tested with configure/File API/build artifact checks, not only
   `cmake -P`.

7. Build-relevant surfaces

   Add after configure-time theories and target Layer A have a stable
   lift/lower/test story. These surfaces do not merely compute values; they
   declare generated build graph artifacts or build-time rules.

   Candidate surfaces:

   ```ocaml
   ECmakeAddCustomCommand
   ECmakeAddCustomTarget
   ```

   These require File API or build artifact checks rather than only `cmake -P`.
   They also need phase/taint tracking because generator expressions and custom
   command bodies may be delayed beyond configure time.

## Parser And Lowering Plan

The existing production parser and compiler:

```text
src/langs/yelu/lang_yelu_parse.ml
src/langs/yelu/lang_yelu_compile.ml
```

target the current `yelu_cmake` AST. They are useful working infrastructure, but
they should not be split immediately.

This is a strangler migration, not a rewrite. The current `yelu_cmake` stack
already has the project assets that are expensive to recreate:

```text
parser:
  src/langs/yelu/lang_yelu_parse.ml

production AST:
  src/langs/yelu/lang_yelu_cmake.ml

compiler/lowerer to CMake:
  src/langs/yelu/lang_yelu_compile.ml

compatibility tests and coverage:
  test/test-runcmake/test_runcmake_yelu.ml
  doc/yelu_lang_coverage.md
```

The part to retire is the earlier theory-splitting idea in
`src/langs/yelu/fragments`, where CMake command families were treated as
theories directly. The working parser, compiler, and compatibility tests should
remain the production baseline while the new `yelu_tiny` decomposition proves
itself.

Near-term parser strategy:

- Keep the production parser as-is for `yelu_cmake`.
- Build `yelu_tiny` programs directly in OCaml tests while the theory model is
  still moving.
- If syntax is needed soon, add a small parser only for tiny examples rather than
  decomposing the production parser.

Pragmatic bridge:

- Parse once into the current `yelu_cmake` AST.
- Add a partial `yelu_cmake -> yelu_tiny/Yelu1` converter for the subset under
  study, starting with string operations and variable/set forms.
- Use this as a hack to reuse existing syntax and examples without committing to
  a fragmented parser design.

Started bridge:

```text
src/langs/yelu_tiny/yelu_cmake_to_yelu1.ml
```

Initial supported subset:

```text
old expressions:
  string/path/keyword/eval literals, bool literals, yelu vars, cvars, targets,
  not/and/or, string equality, target-exists predicate

old statements:
  Ylet
  Ystmt_list
  Yif
  Ys_var/Yvar_set with zero or one value and no PARENT_SCOPE
  Ys_string/Ystr_concat
  Ys_string/Ystr_toupper
  Ys_string/Ystr_replace with exactly one input
  Ys_string/Ystr_length
  Ys_string/Ystr_compare EQUAL
  Ys_list/Ylist_append
  Ys_list/Ylist_get with exactly one AST index
  Ys_list/Ylist_length
  Ys_list/Ylist_join
  Ys_path/Ypath_set
  Ys_path/Ypath_get FILENAME
  Ys_path/Ypath_normal_path
  Ys_target/Ytgt_add_executable without EXCLUDE_FROM_ALL
  Ys_target/Ytgt_sources, currently flattened to target source strings
  Yexpr_is_defined
```

This is enough to connect the old production AST shape to the tiny Yelu1
composition harness without claiming broad compatibility.

Parser-fed smoke path is now covered by tests:

```text
source string
  -> Lang_yelu_parse.parse_program
  -> yelu_cmake_to_yelu1
  -> Yelu1 evaluator
```

The first parser-fed examples cover the same narrow string/control subset as the
hand-built bridge tests, plus list append/get/length/join and the first path
slice. Target Layer A is also covered with `add_exe` plus an `if target ...`
condition. The first target Layer B slice is covered with `target_sources`.

Concrete bridge workflow:

```text
source Yelu
  -> existing parser
  -> old yelu_cmake AST
  -> partial yelu_cmake_to_yelu1 bridge
  -> lift_yelu1_to_yelu2
  -> lower_yelu2_to_yelu1
  -> emit/check CMake
```

This gives the new theory work access to old examples and old parser coverage
without forcing parser decomposition before the theory boundaries are known.

Production retirement rule:

```text
for each old command family:
  old yelu_cmake command group
    -> Yelu1 surface equivalent
    -> Yelu2 pure/better theory where applicable
    -> semantic equivalence tests
    -> CMake-backed script/configure/file-api/build tests
    -> only then retire or de-emphasize the old split fragment
```

Do not delete the broad `yelu_cmake` command support simply because a tiny
surface exists. A tiny surface is a composition experiment; production retirement
requires parser/compile/test coverage at the old stack's level.

Longer-term parser options:

- One parser per composed language (`parse_yelu1`, `parse_yelu2`) if the surface
  syntax intentionally differs.
- One shared parse tree followed by elaboration into `Yelu1` or `Yelu2` if syntax
  is mostly shared but semantics/lowering differ.
- Fragment-owned parser cases only after the theory boundaries are stable. This
  has the same open-recursive-close shape as evaluation: fragments own local
  syntax cases, while the outer language owns composition and conflict handling.

Lowering strategy:

- For `yelu_tiny`, first add an evaluator and semantic tests.
- Add a tiny CMake script emitter for `cmake -P` checks. Current emitter targets
  the Yelu1/CMake-surface subset and is intentionally not a general Yelu2
  lowering path; Yelu2 should lower through `lower_yelu2_to_yelu1` first.
- Use File API checks only when tiny programs start affecting build graph
  artifacts such as targets, sources, include dirs, or compile definitions.

## CMake Phase Model

CMake commands are not all in the same semantic phase. This matters for deciding
when a pure Yelu theory can safely replace an effectful CMake command encoding.

Useful classification:

```text
pure configure-time computation:
  string, list, math, path

configure-time effects:
  var/cache, file read/write, execute_process, find_*

build graph declaration:
  target, install, test, property, dir

build-time rule creation:
  add_custom_command, add_custom_target

delayed/generate-time expressions:
  generator expressions ($<...>)
```

Important details:

- `string(...)` runs at configure time. It is not build-time computation.
- `execute_process(...)` also runs at configure time, even though it launches an
  external process.
- `add_custom_command(...)` and `add_custom_target(...)` are configure-time
  commands that create build-time rules. The command bodies they register run
  later during the build.
- Generator expressions are delayed and may be resolved at generate time or by
  the generated buildsystem depending on context.

Consequence for theory replacement:

If taint/phase analysis proves a value is configure-time ended, then it is safe
to use the better pure theory for that value:

```text
pure Yelu string op
  => compute during yelu -> cmake when operands are known
  => otherwise lower to configure-time CMake string/store effects
```

The unsafe boundary is when a value escapes into delayed or build-time contexts:

```text
generator expression
custom command body
build artifact path consumed by a generated build rule
```

For those cases, the lowering must preserve the delayed/build-time semantics
rather than eagerly folding through the pure configure-time theory.

## Verification Tracks

The tiny composition experiment has several possible confidence levels. Keep
them separate so the project can make progress without pretending that example
tests are formal proof.

| Track                               | Purpose                                                                                                         | Current Status                                                                                                    | Next Step                                                                                   |
| ----------------------------------- | --------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| Example semantic equivalence        | Check `Yelu1`, `Yelu2`, lift, lower, and roundtrip behavior in the OCaml model                                  | Started: string/store/if examples compare final `env` and `value`                                                 | Add examples as each new theory is introduced                                               |
| CMake-backed execution equivalence  | Check emitted CMake scripts with real `cmake -P`                                                                | Started: tiny Yelu1 roundtrip and Yelu2 lowering tests under `test/test-runcmake/test_yelu_tiny_cmake.ml`         | Add one CMake-backed case per new CMake surface feature                                     |
| Per-constructor coverage            | Ensure every expression constructor in a theory/surface has semantic and CMake-backed coverage where applicable | Manual only                                                                                                       | Add a small constructor coverage checklist/table before expanding too far                   |
| Generated/property testing          | Randomly generate small programs and check `eval_yelu1 e == eval_yelu2 (lift e)` and roundtrips                 | Not started                                                                                                       | Add after store/string/if semantics settle; keep generators small and typed-by-construction |
| Formal/SMT proof                    | Prove preservation for a fixed fragment rather than examples                                                    | Not started                                                                                                       | Consider after tiny core + string + bool/if + store are stable                              |
| Existing `yelu_cmake` compatibility | Broad real CMake coverage for the production pack                                                               | Existing project strength: RunCMake, CMakeOnly, File API, parser/compile tests cover much of current `yelu_cmake` | Reuse as regression oracle when migrating production fragments                              |

For the current phase, do not block theory exploration on formal proof. The
practical bar is:

```text
for every new tiny theory/surface:
  semantic examples
  lift/lower or roundtrip examples
  CMake-backed examples if the surface claims to model CMake behavior
```

The existing production `yelu_cmake` suite remains the broad compatibility
baseline. The tiny suite is a research harness for theory composition and should
grow deliberately rather than trying to immediately mirror the full CMake test
surface.

## Later Migration Direction

If the experiment works, migrate the production CMake pack gradually:

```text
closed var
closed type
open expr
closed pack semantics
```

Keep `tc_name`, `yc_string`, `yelu_var`, and `yelu_type` global until there is
real pressure to make them extensible. Expression extensibility is the first
problem worth solving; extensible types require global compatibility logic and
should be deferred.

Suggested migration order:

```text
1. Keep current yelu_cmake as the compatibility language.
2. Grow yelu_tiny as the theory-composition model.
3. Add yelu_cmake_to_yelu1 bridges one command family at a time.
4. Reuse existing RunCMake/File API/build tests as regression oracles.
5. Move production behavior only after the new theory/surface pair has equal or
   better coverage.
```

Initial bridge candidates:

```text
string:
  best first bridge; mostly configure-time, already has tiny semantic and
  CMake-backed checks

list:
  good second bridge; exposes named CMake list effects versus pure list values

cmake_path:
  useful because production already has broad script-pair coverage, but keep the
  tiny slice conservative

target Layer A:
  good for configure-mode checks, but target properties should wait for a
  structured environment with separate variable and target namespaces
```

The long-term workflow can be LLM-assisted:

- fragments own expression constructors locally
- the outer pack owns closed recursion
- tests verify every constructor is handled by evaluation/checking/lowering
- the LLM updates the mechanical cross-cutting closure when a fragment changes
