# Yelu — Project Manifesto

Yelu is a research vehicle organized in layers. Each layer answers a question
and builds on the one below it.

## Layer 1 — The specimen: cmake

**What concrete problem does this address?**

Configuration languages are the least-studied tier of the programming stack,
yet they carry disproportionate operational risk. A single mistyped variable
in a Dockerfile, a wrong indentation in a k8s YAML, a misordered `set()` in
cmake — these fail late, fail silently, or produce subtly wrong artifacts
that surface only in production.

Modern configuration languages are patchwork systems. cmake is the exemplar:
three decades of accumulated layers (scripting → modules → generator
expressions → presets → policy stack) with no cleanup between them. The
result ([cmake/painpoints.md](cmake/painpoints.md)):

- **Irregular syntax**: commands and keywords are both bare strings,
  indistinguishable to the parser
- **Implicit namespace collisions**: variables, targets, cache, and
  properties shadow each other silently
- **Late errors**: a typo in a variable name silently produces `""`; the
  fault surfaces three calls later
- **Accumulated workarounds**: CMP* policies coexist old and new behavior
  forever

cmake is not uniquely bad — it is uniquely *honest*. The same patchwork
pattern recurs across Dockerfile, Terraform HCL, k8s YAML, and Nix. cmake
is the specimen; the thesis is general. It is mature and widely adopted
(important enough that results transfer) yet maximally hostile to automated
reasoning (a stress test for the claims). If the thesis holds here, it
likely holds for simpler config targets. If it fails, cmake's idiosyncrasies
help diagnose why.

## Layer 2 — The architecture: control side + theories

**How is yelu built?**

The language separates a **universal control side** from target-specific
**theories**.

```
  control side     ← target-agnostic: binding, branching, iteration, macros
    │
  theories         ← per-domain typed constructors & checkers
    │
  target AST       ← stringly-typed, mirrors real cmake
    │
  target output    ← CMakeLists.txt, verified against reference
```

**The control side** — `Ylet`, `Yif`, `Ystmt_list`, `Yc_foreach`,
`Yc_function`, `Yc_macro` — provides binding, branching, iteration, and
macro-programming uniformly across all target packs. It is target-agnostic:
a future json-pack or nix-pack reuses the same control side.

**The theories** are 14 `Make_*_op` / `Make_*_check` functor pairs, each
defining typed constructors and checking rules for one cmake command family
(target, variable, string, path, install, test, …). Theories compose over a
shared `LANG_TYPES` substrate; the cmake-pack is the integration point where
all 14 are instantiated against cmake semantics.

**Compositional checking** decomposes verification into distinct passes:

| Stage       | What it checks                                       | Status          |
| ----------- | ---------------------------------------------------- | --------------- |
| `typecheck` | Expression types: bool where string expected         | 14 theories     |
| `wellform`  | Name binding: all references resolve to declarations | done            |
| `effect`    | Execution-mode constraints: what's valid where       | next            |
| `lower`     | Structural validity during AST → cmake emission      | partial         |
| `configure` | cmake itself validates the output                    | RunCMake compat |

Type checking is per-theory and per-statement (each theory's `Make_*_check`
functor operates independently). Well-formedness is cross-theory and
whole-program. The stages compose without a monolithic type checker.

**Equivalence oracle.** Every yelu program is verified against a reference
cmake implementation via structural equivalence: the yelu compiler output
must match the reference `CMakeLists.txt` (modulo canonical formatting).
The suite covers 108 checks (35 structural + 12 CMakeOnly + 61 RunCMake),
12 end-to-end tutorial steps, and File API codemodel-v2 JSON diff.

**Current state.** Two-language model (`yelu_cmake` /
`yelu_cmake_normal`) with 14 cmake-faithful + 16 normalized
theory fragments; ~1,010 unit tests; concrete-syntax parser
shipped; Bar #3-lite syntactic round-trip on z3 + llvm shipped
(STRUCT=0 / FORMAT=0 across 729 files). No CI. See
[project_overview.md](project_overview.md) for the full audit.

## Layer 3 — The thesis: low entropy

**What does yelu claim?**

**Languages with low syntactic and semantic entropy plus strong local
verification produce better model-driven generation and repair.**

"Low entropy" is the unifying property — minimize surface diversity so
there's one way to say a thing, few hidden defaults, few overloaded names,
few stringly-typed dispatch points. It decomposes into six sub-properties,
ordered by impact on machine-driven generation and repair:

1. **Closed-world names and typed slots** — no silent shadowing across
   namespaces. A name lives in exactly one namespace; the compiler knows
   which one.
2. **Local, structured failure** — faults surface at their origin with
   precise diagnostics, not three calls later as `""`.
3. **Canonical surface forms** — a canonicalizer collapses equivalent
   programs into one, making equivalence decidable.
4. **Explicit phase boundaries** — compile / configure / build / install are
   named stages, not implicit conventions.
5. **Regular grammar** — one syntactic form per concept. Unambiguous parse
   is table stakes.
6. **Searchable type surfaces** — type information is first-class AST data
   that tools (and models) can query.

The target workflow is **human-plus-model production with verifier feedback**:
a model generates or repairs the language under verifier guidance, and a
human reviews and directs. The language is optimized for this loop — not for
unadorned model consumption, and not for unadorned human authoring.

**Falsifiability.** The thesis makes specific, testable claims:

1. **Model performance**: LLMs given yelu produce fewer type errors, fewer
   silent semantic errors, and require fewer repair rounds than LLMs given
   cmake directly, on matched tasks.
2. **Verifier leverage**: yelu's checker catches errors that cmake either
   catches later or misses entirely.
3. **Compositionality**: adding a new theory does not require modifying
   existing theories' checkers.
4. **Generalization**: a second target pack does not require redesigning
   `LANG_TYPES` or `checking_stage`.

The measurement strategy ([research/research_framing.md](research/research_framing.md))
uses paired oracle-backed benchmarks with contamination-aware evaluation.

## Layer 4 — pl à la carte: the design space

**Why is the control/theory separation general?**

The control side and the theory side are independently variable — composable
ingredients that can be mixed and matched. This is **pl à la carte**: not one
language, but a design space for assembling languages from parts.

**The control side** is a set of choices with no single right answer:

- **Evaluation model**: higher-order (functional, `let`-binding, expression-oriented)
  vs. imperative (statement sequencing, mutable state)
- **State discipline**: stateful (cmake's `set()`, variable mutation) vs.
  stateless/pure (Nix's immutable bindings, Dhall's total evaluation)
- **Metaprogramming**: macros (textual substitution), functions (scoped evaluation),
  or neither (declarative-only)
- **Type granularity**: gradual (TypeScript-style, annotate where you want),
  mandatory (every expression typed), or structural (shape-based, no annotations)
- **First-class datatypes**: which types are built into the language core (bool,
  int, string, list, record) and which are pack-defined (target, path, version)

**The theory side** is domain-specific and mostly self-contained:

- **Self-contained theories**: string operations, list manipulation, boolean
  logic — reference only core types, need no external registry
- **Externally-determined theories**: `find_package`, property get/set,
  `try_compile` — depend on the cmake runtime, package schemas, or the
  filesystem; cannot be fully checked without external data

Any theory pairs with any control side: the string theory works with
expression-oriented binding or imperative sequencing. The target theory
composes with macros or pure functions. The checker stages compose regardless
of which control choices were made.

The current cmake-pack is **one point in this space**: expression-oriented
(`let`, `in`), stateful (cmake variables), with macros and functions, gradual
typing, and 14 domain theories. A future json-pack or nix-pack might choose a
different control surface while reusing the same theories and checker
infrastructure.

For LLM-based evaluation, the control side itself becomes an experimental
variable: does a model generate better cmake with an imperative surface or a
functional one? With macros or without? The answer may differ by task, by
model, or by training regime. pl à la carte makes these questions answerable
by experiment rather than by debate.

Each theory is also a unit of AI tooling: a training unit (fine-tune on
per-theory test suites), a prompt context (few-shot examples scoped to one
theory), and a tool boundary (each checker is a verifier an agent can call).
An agent facing a novel build task doesn't need to know "cmake" — it needs the
`target` theory, the `find` theory, the `install` theory, and the control side
teaches it how to compose them. The language becomes an on-the-fly assembly of
known pieces rather than a monolithic surface to memorize.

## Layer 5 — The AI-era argument: why now

**Why is this feasible and timely?**

AI has crossed a critical threshold: models can generate and repair cmake,
bash, YAML, Dockerfile, Terraform — the existing irregular configuration
languages. They handle the quirks, the implicit namespace collisions, the
error-at-a-distance. This has two consequences.

First, **compatibility with existing syntax is not a constraint**. We don't
need yelu to look like cmake for AI's benefit. Models that already navigate
cmake's patchwork will adapt to a clean, regular surface immediately. The
cost of learning a new syntax is near-zero for a capable model; the cost of
generating correct code in a hostile syntax is permanent.

Second, **the Rust parallel**. Rust captured market share from C/C++ on the
strength of reliability — memory safety, ownership tracking, exhaustive
matching — despite being famously harder for humans to write. AI changes the
calculus on both sides: writing Rust is not hard for a model; writing C is
not easy for a model either — they're both just token streams. The old
tradeoff collapses. We don't have to choose between "easy to write" and
"safe/correct" because AI has commoditized the writing part.

Together, these mean holistic redesign is both feasible and practical:
AI handles any surface syntax, so we optimize for the properties that
matter — local verification, composability, low entropy. The ceiling is the
language, not the model. If models produce correct cmake ~X% of the time, the
remaining errors are not model capability gaps; they are language design gaps
(silent `""`, implicit shadowing, error propagation). A better language
raises the ceiling.

## Layer 6 — The PL contribution: what we bring

**What does PL research uniquely provide?**

When engineering difficulty is no longer the bottleneck, the question becomes:
**what properties should a language have when writing difficulty is no longer
the constraint?** PL research provides the design vocabulary for answering
that question.

Type safety, effect tracking, phase separation, compositional semantics, name
binding, canonical forms — these are not implementation details. They are
design properties that determine what errors are catchable, at what stage,
with what precision, and whether the error message points to the source or to
a consequence three calls later. PL researchers know how to characterize these
properties, how to prove they hold, and how to compose them without destroying
each other.

Yelu sits at the intersection of **pl4ai** (PL concepts as structural
foundation for AI problems) and **ai4pl** (AI methods applied to PL problems):

- **pl4ai**: the checking pipeline is a PL-style verification stack applied to
  AI-generated artifacts. The verifier doesn't care whether the author was
  human or model — it checks the same properties either way.
- **ai4pl**: the theories-as-units architecture enables AI tooling at multiple
  scales, from training to prompting to agentic verification.

This connects to the broader **AI bootstrapping** arc: current AI
infrastructure (languages, frameworks, toolchains) is human-written — a
bootstrap legacy, not the end state. Yelu is a concrete experiment in what
happens when a language is designed from the start for a world where both
humans and models produce and verify code.

## Layer 7 — The trajectory: where this goes

**What's beyond cmake?**

cmake is the starting point, not the destination. The architecture generalizes
along two dimensions:

1. **Target languages**: cmake → config languages (JSON schema, YAML, TOML) →
   shell scripting → general-purpose programming. Each new target is a pack:
   a statement type, a set of theories, and a pretty-printer.

2. **Control surfaces**: the current expression-oriented surface (`let`, `in`,
   braced blocks) is one choice. A shell-oriented surface (pipes, job control),
   a declarative surface (pure bindings, no sequencing), or an imperative
   surface (assignment, loops) could target the same theories.

The endpoint is a **general PL that drives AI development and AI infrastructure
itself**: a language where models generate, verifiers check, humans direct, and
the language substrate is assembled from proven theories rather than inherited
from legacy. The human-written stack is a bootstrap legacy; the question is
what replaces it, and how.

One concrete ecosystem-scale follow-up is **yelu_c**: take C as the next
specimen after cmake, then rebuild a compact but real project such as
`llama.c` (`ds4.c`) in yelu. This would test whether the same low-entropy theory
decomposition can cover not just configuration, but a practical systems
program with memory layout, portability, compiler flags, profiling feedback,
and library packaging pressure.

## What this is not

- **Not a cmake replacement.** yelu targets cmake as output; it doesn't
  replace cmake's build orchestration, generator expressions, or platform
  abstraction.
- **Not a better template language.** yelu provides programmability and
  verification; it doesn't compete with `configure_file()` or Jinja.
- **Not a build system.** yelu has no runtime, no scheduler, no dependency
  graph. It emits text that build systems consume.
- **Not a product.** yelu is a research vehicle. The artifacts (compiler,
  checker, test suite) exist to test the thesis, not to ship to users.
- **Not AI-only.** yelu is optimized for human-plus-model production with
  verifier feedback — not for unadorned model consumption, and not for
  unadorned human authoring. The two must work together.

## Related and prior art

- **Nix** — content-addressed store, deterministic builds. Shares the
  "purity through design" philosophy; differs in being a build system
  rather than a config-language metalayer.
- **Dhall** — typed, programmable configuration language. Closest spirit
  to yelu; differs in targeting single-language config files rather than
  being a metalayer that compiles *to* existing config languages.
- **Kaitai Struct / Pkl** — typed DSLs that generate target formats.
  Relevant as "compile-to-target" precedents; differ in being schema-first
  rather than language-first.
- **Salsa / Shake** — incremental computation frameworks. Relevant to the
  persistent-value primitive (Y13) and cache-sensitivity design (Y7).
- **Tree-sitter / LSP** — demonstrate that structured editor tooling
  improves correctness for human authors. yelu extends this hypothesis
  to model-driven authoring with verifier feedback.
