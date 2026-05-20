# Bar #3-lite audit kit review — 2026-05-20

This is a focused review of
[`bar3_lite_audit_kit.md`](bar3_lite_audit_kit.md) against the
current round-trip implementation in
[`tool/cmake_roundtrip/print2.ml`](../../tool/cmake_roundtrip/print2.ml).

The audit kit is useful as a per-parser review scaffold, but it is
not yet reliable as a source of truth. Several contract rows are
stale or too broad, and the kit should more clearly separate
**syntactic STRUCT preservation** from **correct typed IR
classification**.

## Findings

### 1. Parser counts are inconsistent

Severity: **major**

The kit says "32 parsers total" and lists Stage 2-c as 9 parsers,
but the visible Stage 2-c command names are:

```
return, include_directories, find_program, find_path, install,
add_custom_command, file
```

That is 7 command names. The current `parse_cmd` dispatch has 30
command-name branches. If helper parsers or subcommand parsers are
being counted, the table should say so explicitly.

## 2. `cmake_minimum_required` accepts a lossy max-version form

Severity: **major**

The contract row says max-version syntax should bail because the
printer drops `max`, but the parser currently accepts it:

```sh
export PATH=/home/red/.venvs/default/bin:$PATH
dune build tool/cmake_roundtrip/print2.exe

printf 'cmake_minimum_required(VERSION 3.20...3.28)\n' \
  | python3 tool/cmake_roundtrip/parse.py - \
  | STAGE2_COVERAGE=1 _build/default/tool/cmake_roundtrip/print2.exe
```

Observed:

```text
[stage2] modeled=1 generic=0 other=0
cmake_minimum_required(VERSION 3.20)
```

This is an accept-set hole: the typed path drops `...3.28`.

## 3. `project` drops DESCRIPTION / HOMEPAGE_URL and can reorder languages

Severity: **major**

The contract says `DESCRIPTION` and `HOMEPAGE_URL` are accepted, but
the parser does not preserve them in the typed IR. With bare values,
it also reorders languages in the observed output:

```sh
printf 'project(P DESCRIPTION desc HOMEPAGE_URL url LANGUAGES C CXX)\n' \
  | python3 tool/cmake_roundtrip/parse.py - \
  | STAGE2_COVERAGE=1 _build/default/tool/cmake_roundtrip/print2.exe
```

Observed:

```text
[stage2] modeled=1 generic=0 other=0
project(P LANGUAGES CXX C )
```

This is an accept-set hole. The parser should either preserve these
fields correctly or bail to the generic `Apply` path.

## 4. `add_executable` options are structurally preserved but typed wrong

Severity: **major**

The contract says `WIN32`, `MACOSX_BUNDLE`, and
`EXCLUDE_FROM_ALL` are accepted options. Current parsing accepts
these shapes, but because it does not parse options, those tokens
are placed in the `sources` field.

```sh
printf 'add_executable(App WIN32 main.c)\n' \
  | python3 tool/cmake_roundtrip/parse.py - \
  | STAGE2_COVERAGE=1 _build/default/tool/cmake_roundtrip/print2.exe

printf 'add_executable(App EXCLUDE_FROM_ALL main.c)\n' \
  | python3 tool/cmake_roundtrip/parse.py - \
  | STAGE2_COVERAGE=1 _build/default/tool/cmake_roundtrip/print2.exe
```

Both are `modeled=1` and structurally reprint close to the input,
but the typed IR classification is wrong. This is the key audit
lesson: STRUCT can pass while typed meaning is misclassified.

## 5. `target_link_libraries` mixed visibility groups do not bail

Severity: **medium**

The contract says mixed visibility groups bail, but current
`group_by_visibility` accepts multiple groups:

```sh
printf 'target_link_libraries(t PRIVATE a PUBLIC b)\n' \
  | python3 tool/cmake_roundtrip/parse.py - \
  | STAGE2_COVERAGE=1 _build/default/tool/cmake_roundtrip/print2.exe
```

Observed:

```text
[stage2] modeled=1 generic=0 other=0
```

The contract row should be corrected.

## 6. Reproducer commands need the project Python tool env

Severity: **medium**

In this environment, plain `python3` resolves to
`/home/red/.local/bin/python3`, which does not have
`tree_sitter` / `tree_sitter_cmake` installed. The reproducer
section should include:

```sh
export PATH=/home/red/.venvs/default/bin:$PATH
```

before invoking `python3` or `gersemi`.

## 7. "Byte-faithful Apply" is too strong

Severity: **medium**

The generic path now routes through real `Lang_cmake.Apply`, which
is good. But the production `Lang_cmake_pp` Apply arm can emit a
multi-line layout for some inputs. For example:

```sh
printf 'project(P)\nmy_project_macro("x" y)\n' \
  | python3 tool/cmake_roundtrip/parse.py - \
  | STAGE2_COVERAGE=1 _build/default/tool/cmake_roundtrip/print2.exe
```

Observed:

```text
[stage2] modeled=1 generic=1 other=0
project(P )
my_project_macro("x"
y)
```

The generic path is STRUCT-faithful for this claim, but not
byte-faithful. The kit should use "STRUCT-faithful" or
"argument-sequence faithful" instead.

## 8. Pre-commit recipe contains a destructive checkout

Severity: **nit / process risk**

The kit suggests:

```sh
git checkout main -- tool/cmake_roundtrip/print2.ml
```

That is a working-tree destructive operation. Prefer a throwaway
worktree/branch or a non-mutating baseline extraction, for example:

```sh
git show main:tool/cmake_roundtrip/print2.ml > /tmp/print2.main.ml
```

## Recommendation

Before delegating a full per-parser audit using this kit:

1. Correct the parser count/stage table.
2. Add the project-local Python tool env to all reproducer snippets.
3. Replace "byte-faithful" with "STRUCT-faithful" for the generic
   Apply path.
4. Update stale contract rows, starting with:
   `cmake_minimum_required`, `project`, `add_executable`, and
   `target_link_libraries`.
5. Explicitly add a review axis for typed IR classification, not
   just STRUCT preservation.

The most important conceptual distinction is:

> STRUCT passing proves source command/argument preservation. It
> does not by itself prove the accepted command was mapped into the
> semantically correct `Lang_cmake.exp` fields.
