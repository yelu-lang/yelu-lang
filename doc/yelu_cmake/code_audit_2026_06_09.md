# yelu_cmake Code Audit — 2026-06-09

This audit focuses on the current `.yc -> yelu_cmake -> Lang_cmake.exp ->
CMake text` path, the fmt probe, and the code touched by the recent parser,
IR, emit, and driver work.

## Scope

Reviewed areas:

- `src/langs/yelu/yelu_parse.ml`
- `src/langs/yelu/yelu_lexer.ml`
- `src/langs/yelu/yelu_cmake_emit.ml`
- `src/langs/yelu/yelu_cmake_utils.ml`
- `src/langs/yelu/yc_wellform.ml`
- `src/bin/yelu/yelu.ml`
- `src/langs/cmake/lang_cmake_pp.ml`
- `test/test-yelu/*`
- `test/test-runcmake/*`
- `probes/fmt/*`

Verification run:

```sh
eval $(opam env) && dune test
eval $(opam env) && dune exec src/bin/yelu/yelu.exe -- matrix probes/fmt
```

Result:

- fmt matrix passed: `24/24 cells passed`.
- full `dune test` was not green in this checkout.

## Findings

### 1. Target kwarg-list syntax drops payloads

Severity: major

`collect_command_args` accepts `~public:[...]`, `~private:[...]`, and
`~interface:[...]`, but it skips the list payload and records only a boolean
marker:

- `src/langs/yelu/yelu_parse.ml:313`

The target parser then reads positional visibility groups, not those kwarg
payloads. This means accepted syntax can silently erase content.

Example:

```yc
( compile_feats Target Tutorial ~public:[cxx_std_11] )
```

currently emits:

```cmake
target_compile_features(Tutorial )
```

The existing tests only assert parse/emit survival for this shape:

- `test/test-yelu/test_yelu_cmake_parse.ml:184`
- `test/test-yelu/test_yelu_cmake_parse.ml:359`

The fmt migration avoids this by using positional `:PUBLIC`, so the 24-cell
fmt matrix still passes.

Recommended fix: either fully plumb kwarg-list visibility payloads into target
groups or reject that syntax until implemented. Add emit-level tests that assert
the items survive.

### 2. `--project` override is applied inconsistently

Severity: major

`cmd_hybrid` computes an overridden `source_dir`, but later still uses
`m.source_dir` in important places:

- `src/bin/yelu/yelu.ml:414`
- `src/bin/yelu/yelu.ml:466`
- `src/bin/yelu/yelu.ml:482`
- `src/bin/yelu/yelu.ml:484`

That can make the reference configure/file reads use one tree while worktree
creation and cache normalization use another.

Recommended fix: after resolving `source_dir`, use that value consistently for
all source-tree operations in `cmd_hybrid`.

### 3. `merge_flags` behavior contradicts its comment

Severity: major

The comment says command-line `-D` should win over manifest flags, but the
implementation keeps manifest flags and filters out duplicate command-line keys:

- `src/bin/yelu/yelu.ml:405`

Current fmt has no manifest `cmake_flags`, so this is latent. It will matter for
future probes.

Recommended fix: build a map keyed by the `-D` name and let command-line flags
overwrite manifest entries.

### 4. Raw fallback reconstructs CMake text lossy

Severity: major

Parser fallback uses `args_to_cmake_text`, which serializes `EString s` as bare
`s` without quoting:

- `src/langs/yelu/yelu_parse.ml:383`
- `src/langs/yelu/yelu_parse.ml:407`

Many parser families fall back this way when they recognize the command family
but cannot parse the specific shape:

- `src/langs/yelu/yelu_parse.ml:521`
- `src/langs/yelu/yelu_parse.ml:1198`

This can change argument tokenization. For example, an unsupported command with
`"a b"` can become `cmd(a b)` instead of `cmd("a b")`.

Recommended fix: raw fallback should preserve source text, or construct
`Lang_cmake` args and use `Lang_cmake_pp` quoting rules. Do not hand-roll CMake
text from lossy `expr`s.

### 5. Full `dune test` is not green

Severity: major

Observed failures:

- vendored LLVM cram directories are picked up by dune and fail because they do
  not contain `run.t`.
- CMake PP `include optional` expected a trailing space.
- lexer escaped-string tests appear stale relative to `Sexp.to_string` escaping.
- cache snapshot lookup cannot find `tool/cmake_text/cmake_reserved.tsv` from
  the dune test working directory.
- `ylet chain` emits `add_executable(name main.cxx)` instead of
  `add_executable(App main.cxx)`.

The `ylet` issue is semantic:

- `src/langs/yelu/yelu_cmake_utils.ml:124`
- `test/test-yelu/test_yelu_compile.ml:149`

`ylet` demotes `EVar n` to `EString n`, so chained aliases bind to the literal
name instead of recursively resolving a prior binding.

Recommended fix: restore a green test baseline before scaling to z3/llvm.

## Architecture Notes

The 3-layer shape is good:

```text
.yc -> yelu_cmake -> Lang_cmake.exp -> CMake text
```

The fmt matrix is strong evidence that the approach works for a realistic
configure/cache slice. The claim should remain precise: it proves
configure-time cache equivalence for the exercised cells, not build graph,
install, test execution, or full typed-theory coverage.

Keep these surfaces counted separately:

- typed/modeled constructors;
- `yc_apply` generic calls;
- `raw_cmake` escapes.

`yc_apply` is a useful compatibility layer, but it is not equivalent to typed
theory coverage. `raw_cmake` is correctly documented as an opaque escape.

## Recommended Order

1. Fix `~public:[...]` payload loss and add precise emit tests.
2. Fix `--project` override and `merge_flags`.
3. Restore `dune test` to green or exclude vendor LLVM cram files.
4. Replace lossy raw fallback reconstruction.
5. Split `yelu_parse.ml` by command family before adding another large parser
   batch.
6. Keep fmt matrix as the end-to-end oracle, but add smaller unit tests for
   each newly modeled parser/emit path.
