# Hybrid yelu-cmake — adoption strategy

> **Purpose.** Documents the framing and concrete shapes for "use
> yelu where it helps, leave cmake as-is everywhere else." A more
> tractable version of Y16 (manifesto-level scaling test) that
> doesn't require rewriting whole projects.

## Framing

cmake is the assembly language of the build world. Like JavaScript
on the web — universal, deeply entrenched, deeply ugly in places,
but with a runtime everyone trusts. **We treat it that way: don't
try to replace it everywhere, generate it where useful, leave the
rest alone.**

This shifts Y16 ("rewrite z3/llvm/torch in yelu, prove structural
equivalence") from an all-or-nothing project rewrite into a
gradual, per-file or per-function migration. Like TypeScript →
JavaScript: any file can stay JS forever; any file you choose to
rewrite as TS compiles down to interop-compatible JS. Adoption
cost = "rewrite one thing at a time, the rest keeps working."

We explicitly **do not** want yelu *embedded inside* cmake source.
Mixed-mode `# @ye-begin … # @ye-end` comment blocks inside
`CMakeLists.txt` are out of scope — they fragment both languages,
require a special preprocessor, and make tooling hostile to both
sides. cmake is the target, not the host.

## Two supported shapes

### Shape B — side-by-side files

```
project/
├── CMakeLists.txt         hand-written cmake (unchanged)
│      include(helpers.cmake)
├── helpers.yc             ← yelu source for the helpers
└── helpers.cmake          ← generated from helpers.yc (codegen)
```

The cmake side stays as-is; one or more helper files migrate from
`.cmake` to `.yc`. The `.cmake` artifacts are regenerated when the
`.yc` source changes (Make/dune/ninja rule). Both files can be
checked in so consumers without yelu still build — the generated
`.cmake` is the authoritative input to cmake.

Closest analog: **protobuf**. The `.proto` file is the source; the
generated `.pb.h` / `.pb.cc` are committed (or regenerated at
build) and consumed by code that doesn't know protoc exists.

### Shape C — whole-file replacement with `raw_cmake` escape

```
project/
├── project.yc             ← yelu source, declares the whole project
└── CMakeLists.txt         ← generated from project.yc
```

`project.yc` describes the entire build using yelu constructs.
Bits not worth rewriting (or that yelu doesn't model yet) live in
`raw_cmake("…")` escape forms:

```ocaml
(* inside project.yc *)
yelu_cmake_project "fmt" ~version:"11.0.2" ~languages:[ "CXX" ];
raw_cmake {|
  # Things we haven't ported yet; verbatim cmake stays here.
  set(FMT_USE_CMAKE_MODULES FALSE)
  if (CMAKE_VERSION VERSION_GREATER_EQUAL 3.28 …)
    …
  endif ()
|};
yc_option "FMT_DOC" "Generate the doc target."
  (e_var "FMT_MASTER_PROJECT");
…
```

This is closer to the original Y16 rewrite framing but with a
relief valve. The escape lets you start with `raw_cmake` being
the entire file and migrate outward one section at a time. At
each step the emitted `CMakeLists.txt` is structurally identical
to the original modulo your rewrites.

### Which shape when

- **Shape B** is the right starting point. Lower stakes — touch
  one helper file, leave the project structure intact. Easier to
  PR upstream to a real project (just adding two files).
- **Shape C** is for when the whole-project rewrite makes sense
  (a new project starting fresh, or a deep migration we control
  end-to-end).

Both produce cmake; both work with the existing `_out/<proj>/`
matrix oracle.

## Why the architecture supports this

The cmake AST (`Lang_cmake.exp`) is the lingua franca:

```
                            +-----------------+
              hand-written  | CMakeLists.txt  |
              cmake source  +--------+--------+
                                     |
                              parse.py
                                     |
                                     v
+------------+              +-----------------+              +-----------+
| helpers.yc |  Yelu_parse  | yelu_cmake.expr | Yelu_cmake_  |  Lang_    |
| project.yc | ───────────► |  / yelu_cmake_  | emit (+ con- | cmake.exp |
|            |              |  normal.expr    | vert)        | (AST)     |
+------------+              +-----------------+              +-----+-----+
                                                                   |
                                                                   |
                                              +--------------------+----+
                                              |                    |    |
                                       Lang_cmake_pp           (future emit)
                                              |              ninja_emit_pp  …
                                              v                    v    v
                                       +-------------+      +-----------+
                                       |CMakeLists.  |      | build.ninja
                                       |txt (gen'd)  |      | Makefile  |
                                       +------+------+      +-----+-----+
                                              |                   |
                                       real cmake               ninja
                                              |                   |
                                              v                   v
                                       CMakeCache.txt          build/
```

Two things matter:

1. **Yelu emits TO the cmake AST, not to cmake text directly.**
   Once you have `Lang_cmake.exp`, the pretty-printer produces
   cmake text. Same AST → same text every time, regardless of
   whether the AST came from cmake source or yelu source.
2. **The AST is portable across backends.** A future
   `ninja_emit_pp` over the same `Lang_cmake.exp` would produce a
   ninja file. Hybrid yelu+cmake projects can flow through any
   backend without source changes. This is the deepest claim of
   the strategy: when we rewrite a portion in yelu, we're not
   commiting to cmake forever; we're commiting to the AST.

## What this means for Y16

Original framing (from
[`project_overview.md`](../project_overview.md)):

> Bar #3 — real-world cmake hand-rewrites (z3 / llvm / torch).
> Not started; the manifesto-level "does this scale" test.

This was an all-or-nothing claim. Hybrid Y16 splits it into a
per-rewrite verification chain:

| step | what's tested | scale |
|---|---|---|
| 1 | One fmt helper as `.yc`. Generated `.cmake` is byte-identical (or matrix-cache-identical) to the original. | hours |
| 2 | All fmt helpers as `.yc`. fmt's `CMakeLists.txt` includes them; matrix oracle (real-vs-real-with-generated-helpers) shows zero divergence. | days |
| 3 | Some fmt subdir (test/, support/cmake/) as Shape C. raw_cmake escape covers what we don't model. Matrix passes. | weeks |
| 4 | All of fmt in Shape C. raw_cmake usage is minimized; whatever we couldn't avoid is documented in [`status.md`](status.md). | weeks to months |
| 5 | z3 / llvm / torch at step 4. The original Y16 claim, now reachable via composition. | months |

Each step is **independently verifiable** by the existing matrix
oracle: we already diff real cmake on the original source against
something else. The hybrid output is just another "something
else." No new oracle infrastructure needed.

## What's needed to land a pilot

Everything except the build-system integration is already in
place:

- **`.yc` parser** — `src/langs/yelu/yelu_parse.ml` (Angstrom +
  pure OCaml, 12 cmake command families covered, ~170 unit
  tests). Partial coverage; expand as the pilot exposes gaps.
- **`yelu_cmake.expr` → cmake text** — `Yelu_cmake_emit` +
  `Lang_cmake_pp`. Production path. 100% bar #3-lite passing on
  z3 / llvm / fmt.
- **CLI** — a 30-line wrapper around the above:
  `ycn compile helpers.yc > helpers.cmake`. Trivial.
- **Build integration** — a Makefile/dune rule that regenerates
  `.cmake` if `.yc` is newer. Project-specific; not yelu's
  responsibility.
- **Matrix oracle for hybrid sources** — already works. Point
  `vendor/fmt-hybrid/` at a fmt clone with the `.yc`-generated
  `helpers.cmake` checked in. Run the matrix smoke. Diff against
  pure-cmake fmt baseline.

What's **not** needed for the pilot:

- Y17 typing pass (the hybrid strategy doesn't depend on types)
- ycn → ninja or ycn → make emit modules (cmake stays the
  backend for now; the AST is portable so this is a parallel
  effort)
- `project.yc` full-project lowering (Shape C is later; Shape B
  is the pilot)
- Whole-project hand rewrites (the manifesto Y16 claim follows
  from step-by-step composition, not from a heroic upfront
  rewrite)

## Tradeoffs and risks

- **Two-file maintenance burden — manageable.** Shape B has both
  `.yc` and a generated `.cmake`. Our policy:
  - **Local experiments**: generated `.cmake` is regenerated each
    run, lives under `_out/<proj>/`, never committed. Source of
    truth is the `.yc`.
  - **Future / shipping**: regenerated-at-build (bazel-style), with
    a CI check that the generated output matches a fresh
    `ycn compile`. The protobuf "commit both" convention is
    explicitly NOT what we want — we don't ship `.yc` to upstream
    projects.
- **Not pushing `.yc` to real-world upstream projects.** Out of
  scope. Our adoption story is internal: `.yc` lives in our tree,
  generated `.cmake` plugs into the project's build. Means we have
  no maintainer buy-in problem and no "two source-of-truth files
  in someone else's repo" problem.
- **`raw_cmake` becomes a crutch.** Shape C's escape hatch lets
  you punt indefinitely. A discipline: count `raw_cmake` blocks
  per project; track them in `status.md`; aim for monotonic
  reduction.
- **Backend-independence is a future claim.** Today we only emit
  cmake. The "we could emit ninja" story is true architecturally
  but not yet exercised. Worth being honest in advance: the
  ninja/make emit modules are a separate project.

## Relationship to existing pieces

- [`io_architecture.md`](io_architecture.md) — the I/O-free
  library / impure runner split that makes the hybrid strategy
  composable. Generators are pure functions of `.yc` input; the
  build system handles the I/O.
- [`../worklog/worklog_2026_06.md`](../worklog/worklog_2026_06.md)
  (§ "Cache namespace") — the `-D` cmd-line input pathway that hybrid
  projects need to handle the same way pure cmake projects do.
- [`status.md`](status.md) — where the "deferred" items live.
  Hybrid pilot work would be tracked here once a step lands.
- [`../../probes/cache_matrix.md`](../../probes/cache_matrix.md) —
  the oracle that proves a hybrid output is equivalent to the
  pure-cmake reference. No changes needed to the matrix
  infrastructure to support hybrid inputs.

## Pilot decisions (2026-06-04)

The three open questions from the original doc draft, now
resolved:

1. **Migration order: small to large.** Step 1 is the smallest
   meaningful helper — `set_verbose` in fmt (~5 lines, fmt-local,
   no find_program / no try_compile). After that, move outward:
   bigger helpers (`add_module_library`, `add_doc_target`), then
   full subdirs, then whole projects.

2. **Generated `.cmake` is regenerated, not committed.** Local
   experiments leave nothing in git — the `.yc` is the source of
   truth, the `.cmake` lands in `_out/<proj>/` and is rebuilt
   each run. When/if shipping comes up, the regenerated-at-build
   pattern stays (with a CI check that the generated output
   matches `ycn compile`).

3. **`.yc` files live in `probes/<proj>/`.** Per-project folder
   under the existing `probes/` cluster — keeps each project as
   one thing in the tree. Build outputs already external (under
   `_out/`), so adding `.yc` source here doesn't conflict. The
   `ycn` CLI accepts a `--source-dir` (or similar) flag so it can
   serve any probe directory.

```
probes/fmt/
├── README.md            (existing — probe status + project spec)
├── migration_status.md  (existing — full-project hybrid status report)
└── set_verbose.yc       ← pilot's first .yc file

_out/fmt/
├── matrix/<cell>/real/  (existing matrix oracle output)
└── hybrid/              ← future: generated .cmake artifacts
    └── set_verbose.cmake
```

## Pilot path

With the decisions above, the pilot is a small, sequenced piece
of work. Not yet started; tracked here so the next session can
pick it up cleanly.

**Step 1.a — text-level pilot.** Smallest possible test of the
codegen path.

- Write `probes/fmt/set_verbose.yc` reproducing fmt's
  `set_verbose` helper (~5 lines of cmake).
- Build the `ycn compile` CLI: takes `.yc` input, emits `.cmake`
  text via the existing `Yelu_parse` → `yelu_cmake.expr` →
  `Yelu_cmake_emit` → `Lang_cmake_pp` chain. ~30 LOC wrapper.
- Assert byte-equivalence to fmt's original `set_verbose` block
  (after `gersemi` normalization or similar).

Output: confirms one helper round-trips. Cost: a few hours.

**Step 1.b — build-level pilot.** Same helper, but proves the
generated `.cmake` produces equivalent build behavior.

- Take fmt's `CMakeLists.txt`. Splice out the original
  `set_verbose` block; replace with `include(set_verbose.cmake)`.
  Generated file is the output of Step 1.a.
- Run the existing matrix oracle on this hybrid source.
- Assert: real-only / mismatched / pred-only all still zero,
  median matched unchanged from 20.

Output: proves one helper rewrite is build-equivalent. ✓
Landed via the universal `yelu hybrid` driver
(src/bin/yelu/yelu.ml + probes/fmt/main.json).

**Step 2+.** Expand outward. Each subsequent helper adds at most
one new fragment to `yelu_parse.ml` (if needed) and one new
entry to the project's main.json. Whole-fmt is a composition
of steps, not a new project.
