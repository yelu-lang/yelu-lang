# yelu_cmake Code Quality Review — 2026-06-09

This review is separate from the correctness audit. It focuses on maintainability
risks before scaling from fmt to z3/llvm: duplication, unnecessary abstraction,
undocumented escapes, nested control flow, one-use helpers, and boundary leaks.

## Summary

The system has reached a useful shape, but the code now has several growth
symptoms:

- a few very large central files carry too many responsibilities;
- compatibility escape hatches are real and useful, but not uniformly typed or
  measured;
- parser recovery sometimes preserves adoption velocity at the cost of silent
  semantic weakening;
- the CLI driver mixes product behavior, probe orchestration, shell execution,
  cache normalization, and logging in one module.

None of this invalidates the yelu_cmake direction. It means the next scaling
phase should budget cleanup alongside new coverage.

## Large Files Carrying Too Many Roles

### Parser

`src/langs/yelu/yelu_parse.ml` is roughly 2.1k lines. It contains:

- token-level helpers;
- expression parsing;
- command argument collection;
- per-family command parsing;
- family dispatch;
- raw fallback text reconstruction;
- legacy-compatible defaults;
- top-level program parsing.

The file is readable locally, but hard to audit globally. The dispatcher at
`p_stmt_inner_y1` is intentionally ordered, so adding a parser can accidentally
change later behavior.

Recommendation:

- split by command family:
  - `yelu_parse_core.ml`
  - `yelu_parse_target.ml`
  - `yelu_parse_install.ml`
  - `yelu_parse_property.ml`
  - etc.
- keep one small dispatcher module that documents ordering constraints;
- move fallback/raw policy to one shared module.

This should happen before z3/llvm parser widening, not after.

### Emit

`src/langs/yelu/yelu_cmake_emit.ml` is roughly 1.3k lines. It mixes:

- substitution/let erasure;
- expression-to-arg policies;
- enum string conversion;
- per-fragment emission;
- placeholder/default synthesis for known gaps;
- an unsafe fallback using `Obj.repr` near the tail.

Recommendation:

- split the emitter by fragment family in the same direction as parser split;
- centralize string/enum conversion tables;
- remove or quarantine the `Obj.repr` diagnostic path behind a debug-only helper.

### CLI Driver

`src/bin/yelu/yelu.ml` is roughly 600 lines and does too much:

- file I/O helpers;
- shell subprocess management;
- `.ml` and `.yc` compilation;
- manifest loading and auto-discovery;
- splice logic;
- git worktree creation;
- CMake configure;
- cache stripping/diff/classification;
- matrix orchestration;
- CLI argument parsing.

Recommendation:

- move reusable logic into library modules under `src/langs/drivers/` or
  `src/runner/`;
- keep `src/bin/yelu/yelu.ml` as thin argument parsing and reporting;
- represent subprocess commands as argv arrays where possible, not shell strings.

## Escape Hatches Need a Registry

There are three different compatibility/escape mechanisms:

1. `ECmakeApply` / `yc_apply` for generic CMake or project macro calls.
2. `ECmakeRaw` / `yc_raw` for verbatim CMake text.
3. parser-family fallback to `ECmakeRaw` when a known command shape is not
   modeled.

These have different risk levels, but today they are mostly tracked by comments
and convention.

Recommendation:

- create an escape registry in docs and/or code:
  - escape kind;
  - source location;
  - reason;
  - whether it preserves syntax only or semantics;
  - whether it is exercised by matrix/build tests.
- make `ECmakeRaw` carry `{ text; reason; origin }` instead of only `string`
  once the constructor churn is acceptable.
- separate "intentional raw escape" from "parser failed and recovered as raw".

This matters because "fully migrated" should not mean "fully typed".

## Parser Recovery Is Too Forgiving in Some Places

The parser header documents several legacy-compatible defaults:

- missing output variable becomes `"?"`;
- failed int parse becomes `0`;
- missing version becomes `"3.20"`;
- missing project name becomes `"Project"`;
- missing install/find fields become empty lists.

Those defaults are useful during migration, but they are dangerous if treated as
normal language semantics.

Recommendation:

- introduce an explicit parser mode:
  - `Loose_compat` for migration and old goldens;
  - `Strict` for `.yc` authored code.
- in strict mode, missing required fields should be parse errors, not sentinel
  values.

## Duplicated Command Parsing Patterns

Many command-family parsers repeat the same pattern:

```ocaml
let args, kwargs, rest = collect_command_args [] [] rest in
match p_family_inner name args kwargs with
| None -> Some (ECmakeRaw (args_to_cmake_text name args), rest)
| Some e -> Some (e, rest)
```

This duplication is not just style: every repeated fallback currently shares the
same lossy raw reconstruction bug.

Recommendation:

- add a shared `parse_family_or_raw` helper;
- make that helper receive enough original token/source information to preserve
  raw text correctly;
- attach family name and fallback reason for diagnostics.

## Shell String Subprocesses Are a Probe Risk

The driver uses `Unix.open_process_in` with composed shell strings. Examples
include `realpath`, `mkdir -p`, `git worktree`, `rm -rf`, `cmake`, `grep`,
`sed`, and recursive invocation of the yelu executable.

This is acceptable for a local probe prototype, but not a robust project
interface.

Recommendation:

- use `Unix.create_process`/argv-style helpers for `cmake`, `git`, and self
  invocation;
- implement cache filtering in OCaml instead of `grep | sed | sort`;
- reserve shell pipelines for throwaway diagnostics.

## One-Use Helpers and Accidental Abstractions

There are small helpers that are fine individually but collectively blur the
layer boundary:

- `cmake_name_of_yelu` in the parser maps yelu aliases to CMake names for raw
  fallback. This is not really parsing; it is emit policy.
- `expr_to_cmake_text` is a mini-printer in the parser. This duplicates
  `Lang_cmake_pp` responsibilities and loses quoting.
- `message_mode_of_string` exists in both utils/emit-style places.
- many `yc_*` helpers in `yelu_cmake_utils.ml` are thin wrappers around
  constructors, while some are stubs or semantic weakenings.

Recommendation:

- keep constructor helpers, but mark stubs with a type-level or naming
  convention, e.g. `unsupported_*` or `unsafe_*`;
- move alias/name conversion into a shared table module;
- ban mini-printers outside the CMake pretty-printer layer.

## Testing Shape

The test suite has impressive breadth, but some tests are smoke tests:

```ocaml
assert_parses "..." source
```

This proves parser acceptance and emitter non-crash, not semantic preservation.
The `~public:[...]` payload loss was hidden by this pattern.

Recommendation:

- keep smoke tiers for breadth;
- for every syntax that carries payloads, add one precise test that asserts the
  emitted CMake text or IR fields;
- add negative tests for strict-mode parser errors once strict mode exists;
- add regression tests for each escape/fallback class.

## Priority Punch List

1. Restore green `dune test`.
2. Fix known semantic regressions from the correctness audit.
3. Split `yelu_parse.ml` by family.
4. Replace parser-side raw text reconstruction with a canonical raw-preserving
   path.
5. Move driver internals out of the CLI module.
6. Create an escape registry and keep `yc_apply` / `raw_cmake` counts visible.
7. Introduce strict parser mode before using `.yc` as the primary authored
   surface for more projects.
