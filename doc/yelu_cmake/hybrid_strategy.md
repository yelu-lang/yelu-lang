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
├── helpers.ye             ← yelu source for the helpers
└── helpers.cmake          ← generated from helpers.ye (codegen)
```

The cmake side stays as-is; one or more helper files migrate from
`.cmake` to `.ye`. The `.cmake` artifacts are regenerated when the
`.ye` source changes (Make/dune/ninja rule). Both files can be
checked in so consumers without yelu still build — the generated
`.cmake` is the authoritative input to cmake.

Closest analog: **protobuf**. The `.proto` file is the source; the
generated `.pb.h` / `.pb.cc` are committed (or regenerated at
build) and consumed by code that doesn't know protoc exists.

### Shape C — whole-file replacement with `raw_cmake` escape

```
project/
├── project.ye             ← yelu source, declares the whole project
└── CMakeLists.txt         ← generated from project.ye
```

`project.ye` describes the entire build using yelu constructs.
Bits not worth rewriting (or that yelu doesn't model yet) live in
`raw_cmake("…")` escape forms:

```ocaml
(* inside project.ye *)
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
| helpers.ye |  Yelu_parse  | yelu_cmake.expr | Yelu_cmake_  |  Lang_    |
| project.ye | ───────────► |  / yelu_cmake_  | emit (+ con- | cmake.exp |
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
| 1 | One fmt helper as `.ye`. Generated `.cmake` is byte-identical (or matrix-cache-identical) to the original. | hours |
| 2 | All fmt helpers as `.ye`. fmt's `CMakeLists.txt` includes them; matrix oracle (real-vs-real-with-generated-helpers) shows zero divergence. | days |
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

- **`.ye` parser** — `src/langs/yelu/yelu_parse.ml` (Angstrom +
  pure OCaml, 12 cmake command families covered, ~170 unit
  tests). Partial coverage; expand as the pilot exposes gaps.
- **`yelu_cmake.expr` → cmake text** — `Yelu_cmake_emit` +
  `Lang_cmake_pp`. Production path. 100% bar #3-lite passing on
  z3 / llvm / fmt.
- **CLI** — a 30-line wrapper around the above:
  `ycn compile helpers.ye > helpers.cmake`. Trivial.
- **Build integration** — a Makefile/dune rule that regenerates
  `.cmake` if `.ye` is newer. Project-specific; not yelu's
  responsibility.
- **Matrix oracle for hybrid sources** — already works. Point
  `vendor/fmt-hybrid/` at a fmt clone with the `.ye`-generated
  `helpers.cmake` checked in. Run the matrix smoke. Diff against
  pure-cmake fmt baseline.

What's **not** needed for the pilot:

- Y17 typing pass (the hybrid strategy doesn't depend on types)
- ycn → ninja or ycn → make emit modules (cmake stays the
  backend for now; the AST is portable so this is a parallel
  effort)
- `project.ye` full-project lowering (Shape C is later; Shape B
  is the pilot)
- Whole-project hand rewrites (the manifesto Y16 claim follows
  from step-by-step composition, not from a heroic upfront
  rewrite)

## Tradeoffs and risks

- **Two-file maintenance burden.** Shape B means both `.ye` and
  generated `.cmake` live in the tree. If someone edits the
  `.cmake` directly, the two drift. Mitigate with a header comment
  ("generated from foo.ye — do not edit") and a CI check that the
  `.cmake` matches `ycn compile foo.ye` output.
- **Upstream PR resistance.** Adding a `.ye` file to a real
  project (fmt, z3, llvm) requires maintainer buy-in. The
  side-by-side shape minimizes this — they can ignore the `.ye`
  and just review the generated `.cmake`. But we should not
  count on upstream adoption for the pilot; a fork is fine.
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
  composable. Generators are pure functions of `.ye` input; the
  build system handles the I/O.
- [`cache_plan.md`](cache_plan.md) — the `-D` cmd-line input
  pathway that hybrid projects need to handle the same way pure
  cmake projects do.
- [`status.md`](status.md) — where the "deferred" items live.
  Hybrid pilot work would be tracked here once a step lands.
- [`../../probes/cache_matrix.md`](../../probes/cache_matrix.md) —
  the oracle that proves a hybrid output is equivalent to the
  pure-cmake reference. No changes needed to the matrix
  infrastructure to support hybrid inputs.

## Open questions (for the pilot discussion)

1. Which fmt helper for step 1? Candidates: `set_verbose`
   (5 lines, fmt-local), `add_module_library` (~30 lines, more
   substantial), `add_doc_target` (find_program-heavy, exercises
   the find stubs).
2. Shape B's `.cmake` artifacts: committed to git, regenerated
   at build, or both? Protobuf convention is "committed";
   bazel-generated-files convention is "regenerated."
3. Where do `.ye` files for upstream-pilot projects live? In a
   fork of `vendor/fmt/`? In `probes/fmt/`? In a separate
   `probes-upstream/` directory? My instinct: `probes/fmt/`
   (the project IS one thing, regardless of source vs spec).
