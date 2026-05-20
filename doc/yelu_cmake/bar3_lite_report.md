# Bar #3-lite — syntactic cmake round-trip (audit report)

> **Status (2026-05-19).** Shipped through Stage 2-c. STRUCT=0 /
> FORMAT=0 across tutorial (25/25), z3 (108/108), llvm (596/596).
> Audit-ready: this document is self-contained for both progress
> and code-quality reviewers.
>
> Companion documents:
> [`bar3_lite_audit_kit.md`](bar3_lite_audit_kit.md) — per-parser
> contract sheet + paste-ready audit-prompt template + reproducer
> recipe;
> [`bar3_feasibility.md`](bar3_feasibility.md) — feasibility study
> and historical stage-by-stage results;
> [`status.md`](status.md) — living tracker;
> [`../../tool/cmake_roundtrip/README.md`](../../tool/cmake_roundtrip/README.md)
> — tool-level quickstart.

## 1. Claim and counter-claim

**Claim.** The production yelu cmake IR (`Lang_cmake.exp`) together
with its printer (`Lang_cmake_pp`) is **structurally faithful to
real-world cmake**. Given any source file from the corpora below,
parsing through tree-sitter-cmake and reprinting via the IR
produces text from which tree-sitter re-extracts the same
`(command_name, arg-list)` sequence as the source.

**Counter-claim we do NOT make.** This is a *syntactic* claim,
not a *semantic* one. The harness does not run cmake. It does
not assert that the reprinted file produces the same configure
output, the same build graph, the same generator-expression
expansion, or the same File API JSON as the source. Those
behavior-level claims would require running real cmake builds
across the corpora — a separate (more expensive) oracle. The
goal of this stage is to prove the IR shape is rich enough to
carry every command-call shape real projects use, before
investing in behavior-level oracles.

## 2. Oracles

Per-file verdict produced by [`test_corpus.sh`](../../tool/cmake_roundtrip/test_corpus.sh):

- **STRUCT** — extract `(name, args)` tuples from source and from
  reprint, both via tree-sitter-cmake. STRUCT passes when the
  two sequences match exactly. This is the load-bearing oracle —
  it is purely a function of `Lang_cmake.exp` expressiveness +
  `Lang_cmake_pp` correctness.
- **FORMAT** — gersemi-normalize both sides (`--line-length 99999`,
  comments stripped via tree-sitter on the source side because
  our parser drops inline-argument comments), then whitespace-
  collapse the result and string-compare. FORMAT is a softer
  oracle: it claims content equivalence modulo cosmetic layout.

Per-file outcome buckets:

| bucket | meaning |
| --- | --- |
| OK | STRUCT pass AND FORMAT pass |
| FORMAT | STRUCT pass, FORMAT fail (cosmetic) |
| STRUCT | STRUCT fail (real parser/printer/IR bug) |
| PARSE | tree-sitter or our JSON reader fail |

What an OK verdict **guarantees**:

- Every command in the source is present in the reprint, in
  order, with the same name and the same number of arguments.
- Every argument carries the same textual content (modulo
  whitespace inside argument lists and modulo comments inside
  argument lists; see § 6).

What an OK verdict does **NOT** guarantee:

- That cmake-the-binary will execute the reprint identically to
  the source. (See § 1.)
- That comments inside argument lists are preserved. The IR
  doesn't carry them; the oracle compensates by stripping them
  on both sides. See § 6.

## 3. Results

```
tutorial step outputs : 25/25  OK   modeled=165   generic=25    other=23
z3                    : 108/108 OK  modeled=1057  generic=706   other=1711
llvm/llvm             : 596/596 OK  modeled=3573  generic=2609  other=4029
```

All three corpora: **STRUCT=0, FORMAT=0**.

Definitions (no ratio is reported — see § 5):

- **modeled** — command mapped to a dedicated `Lang_cmake.exp`
  constructor (`Add_executable`, `Target_link_libraries`,
  `Find_package`, …).
- **generic** — command constructed as `Lang_cmake.Apply { name;
  args }` and reprinted via the production `Lang_cmake_pp` Apply
  arm.
- **other** — one per block wrapper node
  (`if_condition`/`foreach_loop`/`while_loop`/`function_def`/
  `macro_def`/`block_def`) + one per raw passthrough chunk
  (`.cmake.in` templates the tree-sitter grammar mis-lexes) + one
  per tree-sitter ERROR fragment. Block **heads and tails** are
  NOT in any bucket today — they're reprinted by
  `print_block_head` as raw `name(args)` text without dispatch.
  Body commands inside blocks recurse and contribute to
  modeled/generic normally.

### 3.1 Running locally

```sh
# If using the project-local Python tool env, put it first so
# python3 can import tree_sitter / tree_sitter_cmake and gersemi is found.
export PATH=/home/red/.venvs/default/bin:$PATH

# Build
dune build tool/cmake_roundtrip/print2.exe

# Run on a corpus (corpus_root must contain CMakeLists.txt / *.cmake)
bash tool/cmake_roundtrip/test_corpus.sh /path/to/corpus

# Use a gersemi on $PATH instead of the hardcoded default
GERSEMI=gersemi bash tool/cmake_roundtrip/test_corpus.sh /path/to/corpus

# Reproduce the three audit corpora (adjust paths to your checkouts)
bash tool/cmake_roundtrip/test_corpus.sh \
  /home/red/code/contrib/cmake-all/cmake/Tests/Tutorial
bash tool/cmake_roundtrip/test_corpus.sh /home/red/code/contrib/z3-all/z3
bash tool/cmake_roundtrip/test_corpus.sh \
  /home/red/code/contrib/llvm-all/llvm-project/llvm    # 5–10 min

# Single-file invocation (round-trip text on stdout)
python3 tool/cmake_roundtrip/parse.py path/to/CMakeLists.txt \
  | _build/default/tool/cmake_roundtrip/print2.exe

# Single-file coverage (modeled/generic/other on stderr)
python3 tool/cmake_roundtrip/parse.py path/to/CMakeLists.txt \
  | STAGE2_COVERAGE=1 _build/default/tool/cmake_roundtrip/print2.exe \
    >/dev/null
# → [stage2] modeled=N generic=N other=N
```

The harness exits with status 2 (before processing any file) if
`gersemi` or `print2.exe` is missing — without those pre-flight
checks a broken formatter could produce empty output on both
sides and the FORMAT oracle would pass spuriously.

### 3.2 What the harness does per file

```
for each .cmake / CMakeLists.txt under corpus_root:

  ┌─ 1. parse ─────────────────────────────────────────────────┐
  │  python3 parse.py file.cmake                               │
  │    → tree-sitter-cmake CST → JSON on stdout                │
  │  empty stdout → verdict PARSE, count, next file            │
  └────────────────────────────────────────────────────────────┘
  ┌─ 2. typed reprint ─────────────────────────────────────────┐
  │  echo $json | STAGE2_COVERAGE=1 print2.exe                 │
  │    → reprinted cmake on stdout                             │
  │    → [stage2] modeled=N generic=N other=N on stderr        │
  │  accumulate modeled/generic/other totals                   │
  └────────────────────────────────────────────────────────────┘
  ┌─ 3. STRUCT oracle ─────────────────────────────────────────┐
  │  ref_struct = extract_struct < file.cmake                  │
  │  got_struct = extract_struct < $reprint                    │
  │  ref ≠ got → verdict STRUCT, next file                     │
  │                                                            │
  │  extract_struct walks tree-sitter and emits one line per   │
  │  command of the form `name(a1 a2 ...)`. The comparison is  │
  │  exact string match over concatenated lines.               │
  └────────────────────────────────────────────────────────────┘
  ┌─ 4. FORMAT oracle ─────────────────────────────────────────┐
  │  ref = strip_comments < file.cmake | gersemi | normalize   │
  │  got = $reprint                    | gersemi | normalize   │
  │  ref = got → verdict OK; else verdict FORMAT               │
  │                                                            │
  │  normalize() = drop Warning:/path/<stdin>/comment lines    │
  │              + tr -s whitespace + strip space around parens│
  └────────────────────────────────────────────────────────────┘
```

The STRUCT oracle is the load-bearing claim (purely a function of
`Lang_cmake.exp` expressiveness + `Lang_cmake_pp` correctness).
The FORMAT oracle is informational — gersemi preserves the user's
multi-line vs single-line wrap choice independently of
`--line-length`, so a true byte-equality oracle would need to
match the source's layout. `normalize()` permits content
equivalence modulo whitespace.

### 3.3 Reading per-file output

Each file prints one line:

```
OK     relpath  modeled/generic/other
FORMAT relpath  modeled/generic/other
STRUCT relpath
PARSE  relpath
```

The trailing `m/g/o` triple is the per-file coverage tally from
step 2 (only on OK / FORMAT lines; STRUCT and PARSE short-circuit
before the tally is informative).

Summary block at the end:

```
====
TOTAL: 596
  OK     596    (structural pass AND gersemi-diff pass)
  FORMAT 0    (structural pass, gersemi-diff fail)
  STRUCT 0    (structural fail — real parser/printer bug)
  PARSE  0    (tree-sitter or reader fail)
Stage 2 cmds: modeled=3573 generic=2609 other=4029
```

### 3.4 Debugging a single failure

**STRUCT** — IR or printer dropped, added, or reordered a
command/arg. The fastest localizer is a direct diff of the
source against the round-trip text:

```sh
f=path/to/file.cmake
diff <(cat "$f") \
     <(python3 tool/cmake_roundtrip/parse.py "$f" \
         | _build/default/tool/cmake_roundtrip/print2.exe)
```

The first diverging command is the bug locus. Every historical
STRUCT failure during this work (the five production-IR bugs in
§ 7) was found this way.

**FORMAT** — content matches, layout doesn't. Diff the
gersemi-normalized outputs:

```sh
f=path/to/file.cmake
diff <(python3 tool/cmake_roundtrip/strip_comments.py "$f" | gersemi -) \
     <(python3 tool/cmake_roundtrip/parse.py "$f" \
         | _build/default/tool/cmake_roundtrip/print2.exe \
         | gersemi -)
```

FORMAT is currently 0 across all 729 files; any new FORMAT
failure on a fresh corpus would be the first surfacing of a
gersemi normalization gap (e.g. wrap heuristic divergence,
comment-driven layout) — informative but not load-bearing.

**PARSE** — tree-sitter or the JSON reader failed. Run the parse
step in isolation and look at stderr:

```sh
python3 tool/cmake_roundtrip/parse.py path/to/file.cmake \
  >/dev/null
# inspect any stderr from tree-sitter
```

The most common PARSE-class issue is a `.cmake.in` template whose
`@VAR@` placeholders make tree-sitter mis-lex the whole file as
one bracket-argument. `parse.py` detects this (root has-error AND
every child is ERROR) and emits the file as a single `Raw` node,
which `print2.ml` reprints verbatim. So `.cmake.in` files do not
hit the PARSE bucket — they pass as OK with `other > 0`.

Targeted regression probes for the Appendix A fixes:

```sh
# Build the round-trip driver first.
export PATH=/home/red/.venvs/default/bin:$PATH
dune build tool/cmake_roundtrip/print2.exe

# 1. STRUCT extractor includes direct block-head/tail args.
#    The file should report OK, not hide `endforeach(x)`'s argument.
d=$(mktemp -d)
printf 'foreach(x a)\nendforeach(x)\n' > "$d/CMakeLists.txt"
bash tool/cmake_roundtrip/test_corpus.sh "$d"

# 2. Gersemi pre-flight check fails hard before the corpus loop.
GERSEMI=/does/not/exist bash tool/cmake_roundtrip/test_corpus.sh "$d"
# expected: FATAL ... and exit status 2

# 3. Generic calls route through Lang_cmake.Apply and count generic=1.
printf 'project(P)\nmy_project_macro("x" y)\n' > "$d/CMakeLists.txt"
python3 tool/cmake_roundtrip/parse.py "$d/CMakeLists.txt" \
  | STAGE2_COVERAGE=1 _build/default/tool/cmake_roundtrip/print2.exe \
    >/tmp/yelu_bar3_probe.cmake
# expected stderr: modeled=1 generic=1 other=0
```

## 4. Architecture

### File inventory (`tool/cmake_roundtrip/`)

| file | LOC | role |
| --- | ---: | --- |
| [`parse.py`](../../tool/cmake_roundtrip/parse.py) | 214 | tree-sitter-cmake → JSON CST. Adjacent-arg concatenation, ERROR-root passthrough, block recognition. |
| [`print2.ml`](../../tool/cmake_roundtrip/print2.ml) | 1,168 | JSON reader + 32 per-command typed parsers + dispatch + emit + driver. |
| [`strip_comments.py`](../../tool/cmake_roundtrip/strip_comments.py) | 70 | tree-sitter–based comment stripper used by the FORMAT oracle preprocessor. |
| [`test_corpus.sh`](../../tool/cmake_roundtrip/test_corpus.sh) | 157 | Harness: per-file STRUCT + FORMAT oracles + summary. |
| [`README.md`](../../tool/cmake_roundtrip/README.md) | 124 | Tool-level quickstart + current results. |
| `dune` | 8 | Builds `print2.exe` (deps: `base`, `yojson`, `yelu_langs`). |

### Modules touched in production (`src/langs/cmake/`)

The round-trip exercises the production cmake IR end to end.
Five real bugs in the production code were surfaced and fixed by
this work (see § 7); the touched files are:

- [`lang_cmake.ml`](../../src/langs/cmake/lang_cmake.ml) —
  widened `arg.Bracket of string` → `Bracket of int * string`
  to preserve bracket-quote level; fixed
  `Include.no_policy_scope : scope option` → `bool`.
- [`lang_cmake_pp.ml`](../../src/langs/cmake/lang_cmake_pp.ml) —
  fixed `Configure_file` cross-swapped flags
  (`@ONLY` ↔ `ESCAPE_QUOTES`); fixed `Include.result_var` to
  emit the `RESULT_VARIABLE` keyword; rewrote `pp_arg.Bracket`
  to emit verbatim without surrounding newlines.

### Data flow

```
input.cmake
  └─ parse.py        — tree-sitter → CST JSON
       └─ print2.ml
            ├─ file_of_json           JSON → Stage-1 untyped AST
            ├─ parse_cmd dispatch     Stage-1 Cmd → Lang_cmake.exp option
            │     ├─ Some e          → Lang_cmake_pp.pp e               (modeled)
            │     └─ None            → Lang_cmake.Apply{name;args}
            │                            → Lang_cmake_pp Apply arm      (generic)
            ├─ block walker           recursive descent into body /
            │                          clauses (heads / tails emitted
            │                          raw by print_block_head)
            └─ raw / unknown          verbatim passthrough
  └─ stdout: reprinted cmake
```

The dispatcher [`parse_cmd`](../../tool/cmake_roundtrip/print2.ml)
is a single match expression on lowercased command names, with
32 currently-modeled branches and a catch-all routing to `None`
(→ generic Apply via the production printer). Each per-command
parser follows the same discipline:

- **Bail-to-Apply on lossy shape.** If the input would not
  round-trip cleanly through the production printer (keyword
  reordering, quoted-arg loss, multi-line vs single-line
  collapse), return `None`. The fallback constructs a real
  `Lang_cmake.Apply` value and emits via the production printer,
  preserving the call byte-faithfully.

### Modeled commands (32)

| group | commands |
| --- | --- |
| project/build | `cmake_minimum_required`, `project`, `add_subdirectory`, `include` |
| variables/conditions | `set`, `unset`, `option`, `return` |
| messages | `message` |
| files | `configure_file`, `file` (`WRITE`/`APPEND`/`MAKE_DIRECTORY`/`REMOVE`/`REMOVE_RECURSE`/`TOUCH`/`TOUCH_NOCREATE`/`GLOB`/`GLOB_RECURSE`), `get_filename_component` |
| targets | `add_executable`, `add_library`, `target_link_libraries`, `target_include_directories`, `target_compile_definitions`, `target_compile_options`, `target_compile_features`, `set_target_properties`, `add_dependencies`, `add_custom_target`, `add_custom_command` (TARGET form), `include_directories` |
| find | `find_package`, `find_program` (NAMES form), `find_path` (NAMES form) |
| install | `install` (TARGETS/FILES with DESTINATION) |
| list/string | `list` (`LENGTH`/`REVERSE`/`REMOVE_DUPLICATES`/`APPEND`/`PREPEND`/`REMOVE_ITEM`/`FIND`/`JOIN`), `string` (`TOUPPER`/`TOLOWER`/`LENGTH`/`STRIP`/`CONCAT`/`APPEND`/`PREPEND`/`REPLACE`) |

## 5. Scope and intentional limits

### Class A: project- and module-defined cmake functions (DEFERRED)

Calls into `function()` / `macro()` bodies defined in the corpus
itself or in cmake's standard `Modules/` directory —
`z3_add_component` (×70), `tablegen` (×379), `add_llvm_*` (×~500),
`check_symbol_exists` and the `CheckXxx` family — are valid cmake
that real cmake dispatches dynamically at execution time against
a name table built from `include(...)` and `find_package(...)`.

These round-trip byte-faithfully via `Lang_cmake.Apply { name;
args }` reprinted through the production printer **today**,
contributing to the `generic` count. They are not a
modeling gap; they are correctly never modeled by
`Lang_cmake.exp`, which is by design an IR for cmake **builtins**.

A planned Phase 1 (function-name table + a `resolved` accounting
bucket) and Phase 2 (actual dynamic dispatch resolution: macro
substitution + function-scope modeling + include-graph
resolution) are **deferred**. They are scaffolding for
behavior-level analyses (semantic equivalence, type checking
across user functions, etc.) that belong in a later milestone.
See [`bar3_feasibility.md`](bar3_feasibility.md) § Class A for
the two-phase sketch.

### Why no `modeled / (modeled + generic)` ratio

Earlier stages reported "typed %" — a ratio that conflated two
different things: (a) cmake builtins we hadn't modeled in
`Lang_cmake.exp` yet, and (b) project-defined or module-defined
functions that *should not* be modeled. The ratio implicitly
treated (b) as a deficiency, which is misleading. The current
convention is to report raw counts only.

### Builtins deliberately routed to Apply (production IR is lossy)

The following cmake builtins have a dedicated `Lang_cmake.exp`
constructor but currently flow through `Apply` because the
production printer drops or reorders fields:

| command | IR-printer issue |
| --- | --- |
| `set_property` | [`lang_cmake_pp.ml:620`](../../src/langs/cmake/lang_cmake_pp.ml#L620) — pattern uses `_` on `directory`, `sources`, `installs`, `tests`, `caches`; multi-property calls split into N statements |
| `get_property` | [`lang_cmake_pp.ml:591`](../../src/langs/cmake/lang_cmake_pp.ml#L591) — drops several IR fields |
| `execute_process` | multi-line keyword layout (`\n  COMMAND …`); safe inversion needs modeling each keyword sublist |
| `file` subcommands `READ` / `STRINGS` / `COPY*` / `DOWNLOAD` / `UPLOAD` / `LOCK` / path-query | many IR ctors with keyword-rich shapes |

These are not STRUCT failures — they are typed-coverage
opportunities that require IR-side cleanup, not parser-only
patches. Tracked in [`status.md`](status.md) under "Known IR
shape gaps" and slated to land with the Y17 typing work.

### What the FORMAT oracle does NOT prove

Gersemi preserves the user's multi-line vs single-line argument
layout regardless of `--line-length`, so a byte-identical
reprint after gersemi is impossible without matching the
source's wrap choice. The FORMAT oracle uses whitespace-
collapsed normalization to assert *content* equivalence; it
does not assert byte-for-byte equality of the gersemi-formatted
output. This is acknowledged in the oracle comment and in this
section.

## 6. Comments

Tree-sitter parses both `line_comment` and `bracket_comment`
nodes. The behavior split is:

- **Top-level comments** (between commands, at file scope or
  inside `body`) are preserved as `Raw` nodes and reprinted
  verbatim.
- **Comments inside `argument_list`** are dropped by `parse.py`
  (they are not modeled in `Lang_cmake.exp`). The FORMAT oracle
  compensates by running `strip_comments.py` on the source side
  before gersemi normalization, so the comparison is
  content-equivalent modulo dropped inline-arg comments.

Whether `yelu_cmake` / `yelu_cmake_normal` should carry comments
as AST metadata is a deferred design question separate from
this round-trip claim.

## 7. Production bugs surfaced by round-trip

Round-trip on real-world cmake (z3 and especially llvm) exposed
five bugs in the production yelu IR and printer that the
existing test suite did not catch:

| # | bug | fix commit |
| -: | --- | --- |
| 1 | `Include.no_policy_scope` typed as `scope option` (irrelevant enum); cmake's `NO_POLICY_SCOPE` is a boolean flag. | `13d813c` |
| 2 | `Configure_file` flags `@ONLY` and `ESCAPE_QUOTES` wired to the wrong fields in the printer (cross-swap). | `6a6295a` |
| 3 | `Include.result_var` printed without the `RESULT_VARIABLE` keyword. | `6a6295a` |
| 4 | `pp_arg.Bracket` added surrounding newlines around content. | `6a6295a` |
| 5 | `Lang_cmake.arg.Bracket of string` lost the bracket-quote level (`[==[…]==]` vs `[=[…]=]`). Widened to `Bracket of int * string`. | `91cb43e` |

This is the strongest single point in favor of the round-trip
work as ongoing infrastructure: it catches IR shape bugs that
the synthetic tutorial corpus does not exercise, on a real
high-quality codebase (llvm) that no other yelu test path
reaches.

## 8. Code-quality posture

Items an external code reviewer should examine.

### Strengths

- **Single-file driver, no cross-module state.**
  `print2.ml` is a flat pipeline: JSON reader → AST → dispatch →
  per-command parser → emit. No mutation, no global registries.
- **Discipline on partial coverage.** Every per-command parser
  follows the same shape: pattern-match on canonical forms,
  return `None` on anything that would force the printer to
  reorder or drop information. The `Apply` fallback then preserves
  the call byte-perfectly. This makes the "we don't yet model
  X" cases harmless instead of corrupting.
- **Real production-IR usage.** The harness uses the same
  `Lang_cmake.exp` and `Lang_cmake_pp` that drive the
  step-binary and tutorial paths. No fork of the IR; bug fixes
  flow back to production.
- **Each shipped stage is verified end-to-end** before commit
  (commit messages cite the per-corpus STRUCT/FORMAT/modeled
  numbers).
- **Documented bail-outs at the call sites that need them.**
  Per-parser comments explain *why* a particular form bails to
  Apply (e.g. `find_package` post-COMPONENTS keyword ordering,
  `add_custom_target` swallowing `COMMAND` tokens).

### Weaknesses worth flagging

- **`print2.ml` is 1,168 lines in one file.** Layout is
  sequential (JSON reader, then 32 parsers in stage order, then
  dispatch, then emit driver). Acceptable for a prototype, but
  if this becomes a long-lived tool, splitting into `parsers/`
  module and a slim driver would help.
- **No unit tests** at the `print2.ml` level. Verification is
  end-to-end through the harness against real corpora. There
  are no per-parser regression tests pinning expected
  `Lang_cmake.exp` shapes. The argument *for* this posture: the
  real corpora are larger and more diverse than any hand-written
  test could be. The argument *against*: a future IR refactor
  could silently change per-parser behavior; the harness would
  catch STRUCT drift but not subtle semantic shifts in `Apply`
  vs typed routing.
- **`parse.py` is the only Python in the project.** A Python
  dependency for the OCaml round-trip is awkward. The
  alternative is `ocaml-tree-sitter` bindings (pure OCaml
  runtime), which we considered and deferred to avoid the
  bindings-build complexity. See
  [`bar3_feasibility.md`](bar3_feasibility.md) § "Option B".
- **Corpus locations are hard-coded** in shell commands (this
  document and the README list absolute paths under
  `/home/red/code/contrib/`). Reproducing on another machine
  requires substituting paths.
- **`gersemi` binary path is hard-coded** in
  `test_corpus.sh` as `/home/red/.venvs/default/bin/gersemi`,
  with an env-var override. Should default to looking up via
  `which` for portability.

### What to verify if reading the code

A reviewer who wants to spot-check correctness should:

1. **Compare a per-command parser to the matching IR ctor and
   printer.** Pick e.g. `parse_add_custom_target`
   ([`print2.ml`](../../tool/cmake_roundtrip/print2.ml#L692))
   vs `Lang_cmake.Add_custom_target`
   ([`lang_cmake.ml`](../../src/langs/cmake/lang_cmake.ml#L775))
   vs the printer arm
   ([`lang_cmake_pp.ml`](../../src/langs/cmake/lang_cmake_pp.ml#L1101)).
   Check that the parser's accepted forms exactly match what
   the printer emits.
2. **Read `parse_cmd`'s dispatch.** Confirm that the lowercase
   guard at the top routes mixed-case command names to `None`
   (which keeps them in Apply, preserving the source casing).
3. **Read the gersemi `normalize()` function** in
   `test_corpus.sh`. The FORMAT oracle's claim is exactly what
   this function permits.
4. **Run the harness on a fresh project.** STRUCT failures
   point to a real bug in the IR or printer; FORMAT failures
   point to a normalization gap.

## 9. Commit trail

Bar #3-lite spans 13 commits (`git log --oneline --grep
"bar3-lite"`), bracketed by:

| commit | what landed |
| --- | --- |
| `730bb56` | Stage 1: untyped tree-sitter round-trip. |
| `e86d64c` | tree-sitter ERROR fallback (`.cmake.in` templates). |
| `56f01c2` | Stage 2: typed mapping through `Lang_cmake.exp`. |
| `13d813c` | Production IR fix: `Include.no_policy_scope`. |
| `c52b782` | z3 + llvm round-trip + comment preservation + case fold. |
| `46eea0c` | Typed Apply fallthrough; first batch of structural bug fixes. |
| `6a6295a` | Four production-IR bugs surfaced by llvm round-trip. |
| `91cb43e` | `Lang_cmake.arg.Bracket` widened to `int * string`. |
| `76b8360` | Doc: FORMAT vs STRUCT oracle semantics. |
| `155e8e3` | Close FORMAT bucket — 729/729 across all corpora. |
| `7c1d8a9` | Stage 2-b: 8 mechanical typed parsers. |
| `3217f9b` | Stage 2-c: 8 more typed parsers; safe Class-B builtins. |
| `5ef9eb9` | Docs + terminology: rename typed → modeled, drop ratio. |
| `b9a4c38` | Audit pass: delete dead `print.ml`, refresh README + headers. |

## 10. Deferred / open items

- **Class A semantic resolution** (function-name table + macro
  expansion + scope modeling). Scaffolding for behavior-level
  oracles. See § 5.
- **Lossy IR printers** for `set_property`, `get_property`,
  `execute_process`, and several `file` subcommands. Belongs
  with the Y17 typing work, not as parser-only patches. See
  [`status.md`](status.md) "Known IR shape gaps".
- **Comments inside argument lists.** Currently dropped, with
  the FORMAT oracle compensating by stripping comments on both
  sides. Whether to carry comments as AST metadata is deferred.
- **Behavior-level oracle.** Configure + build the corpora and
  diff the resulting File API JSON. Would catch what the
  syntactic oracle cannot. Significant engineering investment.
- **Corpus extension to torch / fmt / catch2 / spdlog.** No
  technical blocker; just a matter of cloning the source trees
  and running the harness.
- **`tablegen` round-trip semantics** (for llvm): structurally
  the call preserves, but reasoning about what tablegen *does*
  (`.td` → `.inc` generation) is out of scope of this oracle.

---

Audit feedback should be filed against this document and against
specific commits or file references. Code-quality concerns should
target the file inventory in § 4 and the weaknesses in § 8.
Progress concerns should target § 3 and the commit trail in § 9.

## Appendix A. Codex audit note — 2026-05-19

The Bar #3-lite result is a strong syntactic milestone if framed
precisely:

> Stage-1 plus modeled-command lowering can round-trip real-world
> cmake source syntax across tutorial, z3, and llvm, with modeled
> builtins exercising production `Lang_cmake` and generic commands
> preserved by raw fallback.

The current report should avoid implying that every command-call
shape is carried by `Lang_cmake.exp` alone. Modeled commands do go
through `Lang_cmake.exp` and `Lang_cmake_pp`; generic commands are
currently re-emitted directly by `untyped_emit` in `print2.ml`.
Unless generic commands are routed through a real `Lang_cmake.Apply`
or equivalent constructor, the generic bucket is best described as a
raw generic fallback rather than an `Apply` path.

Audit findings:

- **Major:** STRUCT should collect direct `argument` children on
  block heads/tails, matching `parse.py`'s `parse_command_head`.
  Without that, forms such as `endforeach(x)` can lose arguments in
  the oracle even though `parse.py` preserves them.
- **Major:** The harness should fail early if `gersemi` is missing
  or non-executable. Since both reference and generated FORMAT paths
  pipe through the same command with stderr suppressed, a broken
  formatter can otherwise produce matching empty output.
- **Medium:** The `other` bucket is counted as one per `Block`
  node, plus raw/unknown nodes. The report currently describes it as
  block heads/tails. Either the definition or the counter should be
  made consistent.
- **Medium:** `print2.ml`'s header says block heads/tails dispatch
  through `parse_cmd`, but the implementation emits them with
  `print_stage1_cmd`. Body commands dispatch; block head/tail
  commands do not.

Suggested fix order:

1. Fix the STRUCT extractor to match `parse.py` for direct block-head
   arguments.
2. Add a hard `gersemi` availability check before the corpus loop.
3. Rename "Apply fallback" to "raw generic fallback", or route generic
   calls through a real `Lang_cmake.Apply`.
4. Correct the `other` bucket definition.

After those adjustments, the report is audit-ready as a syntactic
round-trip result. Behavior-level equivalence remains a separate
milestone, as the report already states.

## Appendix B. Audit response — 2026-05-19

All four findings from Appendix A were verified against the code
and addressed. Per-corpus counts after the fixes are **unchanged**
from before (tutorial 25/25 modeled=165 generic=25 other=23; z3
108/108 modeled=1057 generic=706 other=1711; llvm 596/596
modeled=3573 generic=2609 other=4029), which directly evidences
that the audited oracle gaps did not silently mask any STRUCT
failures on these corpora.

### B1. STRUCT extractor — fixed

[`test_corpus.sh`](../../tool/cmake_roundtrip/test_corpus.sh) `extract_struct`
now collects direct `argument` children of `normal_command` and
block heads/tails alongside the `argument_list` form, mirroring
[`parse.py`](../../tool/cmake_roundtrip/parse.py)'s
`parse_command_head`. The two extractors are now shape-equivalent,
so the STRUCT oracle compares the same view tree-sitter produces.

### B2. Gersemi pre-flight check — fixed

`test_corpus.sh` now exits with `FATAL: gersemi not found …` and
status 2 before the corpus loop if `$gersemi` is not executable,
or if `$gersemi --version` fails. A parallel check enforces that
`$print2` exists. Without these guards, a missing or broken
formatter produced empty output on both sides and the FORMAT
oracle would have passed spuriously.

### B3. Generic routing through real `Lang_cmake.Apply` — fixed

`print2.ml` `untyped_emit` now constructs a real
`Lang_cmake.Apply { name; args }` value and emits via the
production `Lang_cmake_pp` Apply printer (rather than a bespoke
string concatenation). The wrapper `pp_exp_to_string` sets
`max_indent`/`margin` high to avoid incidental wrapping where the
printer permits it, but the production Apply arm may still choose a
multi-line layout in some shapes. The three corpora remain 729/729
OK, and the generic path now exercises the same IR shape and
printer as modeled commands, which makes the "Apply bucket"
framing accurate.

### B4. `other` bucket and print2.ml header — fixed

The `count_coverage` doc comment is now precise:

> `Block` → `other` += 1 for the wrapper itself. Body and clause
> bodies recurse: contained `Cmd`s contribute to modeled/generic.
> Heads and tails are NOT counted in any bucket (they're reprinted
> by `print_block_head` without dispatch).

The top-of-file header in `print2.ml` is updated to say the same
thing: heads/tails are NOT dispatched through `parse_cmd`; only
body commands recurse. The report's § 3 definitions section is
updated likewise.

### B5. Block head/tail dispatch — acknowledged, deferred

The audit's last bullet (heads/tails do not dispatch through
`parse_cmd`) is now factually documented rather than fixed:
heads/tails reprint as raw `name(args)` text via
`print_block_head`. Routing them through `parse_cmd` would not
change the current oracle result (the head args are the source's
tree-sitter tokens, already byte-faithful), but it would make the
coverage tally more honest (block heads with a modeled IR shape
would count toward `modeled`). This is a small follow-up; not
blocking the audit claim.

### Files touched by the audit response

- [`tool/cmake_roundtrip/test_corpus.sh`](../../tool/cmake_roundtrip/test_corpus.sh)
  — extract_struct fix, gersemi/print2 pre-flight checks.
- [`tool/cmake_roundtrip/print2.ml`](../../tool/cmake_roundtrip/print2.ml)
  — `untyped_emit` reroute through `Lang_cmake.Apply`,
  `print_stage1_cmd` → `print_block_head` rename, header comment
  rewrite, `count_coverage` doc-comment rewrite.
- This document — § 3 bucket definitions, § 4 data flow, § 5
  Class A wording; Appendix B added.
