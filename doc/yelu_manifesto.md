# Yelu — Project Manifesto

## The motivation (twofold)

Yelu is a research vehicle with two interlocking motivations:

**1. A compositional approach to language design.** Programming languages can be
decomposed into a *control side* (binding, composition, iteration, higher-order
abstraction) and *theories* (domain-specific operations over typed namespaces).
Checking and refutation happen at distinct stages — typecheck, wellform, effect,
lower — each catching a different class of error. The core theories are
target-agnostic; each target pack (cmake, and future json, nix) instantiates them
against its own semantics.

**2. A testimony for language design in the AI era.** Yelu explores what happens
when a language is optimized for *both* human authoring and machine-driven
generation and repair — not one at the expense of the other. It spans traditional
PL problems (syntax, typechecking, typing), AI-era PL problems (agent integration,
training-time reinforcement, test-time scaling), and the engineering boundary
where models and toolchains meet. cmake is the specimen: widely used, always
painful, and maximally hostile to automated reasoning — a stress test for the
thesis.

The language targets **ai-friendliness and human-friendliness simultaneously** —
not AI-native at the cost of readability, and not human-idiomatic at the cost of
verifiability. The optimal point is where models generate confidently, verifiers
catch errors locally, and humans review and direct with clear semantics.

## The problem

Configuration languages are the least-studied tier of the programming stack,
yet they carry disproportionate operational risk. A single mistyped variable
in a Dockerfile, a wrong indentation in a k8s YAML, a misordered `set()` in
cmake — these fail late, fail silently, or produce subtly wrong artifacts
that surface only in production.

Modern configuration languages are patchwork systems. cmake is the
exemplar: three decades of accumulated layers (scripting → modules →
generator expressions → presets → policy stack) with no cleanup between
them. The result ([cmake_painpoints.md](cmake_painpoints.md)):

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
is the specimen; the thesis is general.

## The thesis

**Languages with low syntactic and semantic entropy plus strong local
verification produce better model-driven generation and repair.**

"Low entropy" is the unifying property. It decomposes into six sub-properties,
ordered by their impact on machine-driven generation and repair:

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

## Why cmake

cmake is a good specimen precisely because of its patchwork character. It is
mature and widely adopted — important enough that results transfer — yet
maximally hostile to automated reasoning. If the thesis holds here, it
likely holds for simpler config targets. If it fails, cmake's idiosyncrasies
help diagnose why.

cmake is the grounding constraint and adoption path, not the intellectual
center. The architecture generalizes.

### Connection to the broader arc

Yelu sits at the intersection of **pl4ai** (PL concepts as structural foundation
for AI problems) and **ai4pl** (AI methods applied to PL problems):

- **pl4ai**: the checking pipeline (typecheck → wellform → effect → lower) is
  a PL-style verification stack applied to AI-generated artifacts. The verifier
  doesn't care whether the author was human or model — it checks the same
  properties either way. Types, name binding, and effect constraints are
  formal interfaces that both sides must satisfy.

- **ai4pl**: the theories-as-units architecture enables AI tooling at multiple
  scales. A theory is a training unit (fine-tune on per-theory test suites),
  a prompt context (few-shot examples scoped to one theory), and a tool
  boundary (each checker is a verifier an agent can call). The compositional
  design means an agent can learn theories incrementally and compose them
  on-the-fly for novel tasks.

This connects to the broader **AI bootstrapping** arc: current AI infrastructure
(languages, frameworks, toolchains) is human-written — a bootstrap legacy, not
the end state. Yelu is a concrete experiment in what happens when a language is
designed from the start for a world where both humans and models produce and
verify code, and where the human-written artifacts (cmake test suites, OCaml
type specs) serve as the training corpus and validation oracle for the
AI-generated replacements.

## The approach

### Compositional architecture: control side + theories

```
  control side     ← target-agnostic: binding, branching, iteration, macros
    │
  theories         ← per-domain typed constructors & checkers
    │
  target AST       ← stringly-typed, mirrors real cmake
    │
  target output    ← CMakeLists.txt, verified against reference
```

The language separates a **universal control side** from target-specific
**theories**. The control side — `Ylet`, `Yif`, `Ystmt_list`, `Yc_foreach`,
`Yc_function` — provides binding, branching, iteration, and macro-programming
uniformly across all target packs. The theories are 14 `Make_*_op` /
`Make_*_check` functor pairs, each defining typed constructors and checking
rules for one cmake command family (target, variable, string, path, install,
test, …). Theories compose over a shared `LANG_TYPES` substrate; the cmake-pack
is the integration point where all 14 are instantiated against cmake semantics.
Future packs (json, nix) reuse the same control side with their own theories.

This separation has a direct AI leverage point: each theory is a unit of
training data, a prompt context, and a tool boundary. An agent facing a novel
build task doesn't need to know "cmake" — it needs the `target` theory, the
`find` theory, the `install` theory, and the control side teaches it how to
compose them. The language becomes an on-the-fly assembly of known pieces
rather than a monolithic surface to memorize. The `CHECKER_BASE` contract is
the verifier boundary: each theory's checker is independently testable and
separately promptable.

This design is a concrete instance of the broader pattern explored in
[yelu_beyond.md](yelu_beyond.md): AI-designed language stacks converge on
"shared metalanguage, distinct object languages."

### Compositional checking

Verification is staged and compositional — each pass catches a different
class of error, earlier is cheaper:

| Stage         | What it checks                                      |
| ------------- | --------------------------------------------------- |
| `typecheck`   | Expression types: bool where string expected        |
| `wellform`    | Name binding: all references resolve to declarations|
| `effect`      | Execution-mode constraints: what's valid where      |
| `lower`       | Structural validity during AST → cmake emission     |
| `configure`   | cmake itself validates the output                   |

Type checking is per-theory and per-statement (each theory's `Make_*_check`
functor operates independently). Well-formedness is cross-theory and
whole-program (a target declared in `target` theory is referenced in
`install`/`test`/`property`). The stages compose without a monolithic
type checker.

### Equivalence as oracle

The semantic oracle is structural equivalence: a yelu program and its cmake
reference must produce identical `CMakeLists.txt` (modulo formatting) after
canonicalization. This gives us:

- **Ground truth**: does the compiler preserve semantics?
- **Regression detection**: any compiler change that alters output is caught
- **Coverage pressure**: every cmake command we claim to cover must produce
  output identical to the reference

The equivalence suite covers the cmake tutorial (v1 24 checks, v2 11 checks),
the CMakeOnly test suite (12 checks), and 61 RunCMake positive-test compat
scripts. File API codemodel-v2 JSON diff provides a second oracle at the
configure-output level.

## Current state

> See [yelu_project_overview.md](yelu_project_overview.md) for the full audit.

- **14 theories** with type checking: 10 solid, 3 partial, 1 stub (property)
- **324 unit tests** (72 cmake PP + 194 yelu compile + 58 yelu check incl. wellform)
- **108 equivalence/semantic checks** (35 structural + 12 CMakeOnly + 61 RunCMake)
- **12 end-to-end tutorial steps** (generate → configure → build → run)
- **72 step generators** (36 cmake + 36 yelu) covering tutorials and test suites
- **No CI**, **no concrete parser** — these are the nearest gaps

## What would disprove the thesis

The thesis makes falsifiable claims:

1. **Model performance**: LLMs given yelu as a target language produce
   fewer type errors, fewer silent semantic errors, and require fewer
   repair rounds than LLMs given cmake directly, on matched tasks.
   Disproved if: no significant difference in first-pass correctness or
   repair efficiency, after controlling for model capability and prompt
   structure.

2. **Verifier leverage**: a yelu type checker catches errors that cmake
   itself either catches later or misses entirely. Disproved if: the
   error classes caught by yelu's checker are a strict subset of what
   cmake itself reports at configure time, making the additional pass
   redundant.

3. **Compositionality**: the per-theory checking architecture remains
   tractable as new theories are added, without requiring cross-theory
   coordination in the type checker. Disproved if: adding a new theory
   requires modifying existing theories' checkers.

4. **Generalization**: the two-layer architecture transfers to a second
   target language (json/nix) without redesigning the core. Disproved if:
   a second pack requires changes to `LANG_TYPES`, `Make_stmt`, or the
   `checking_stage` model.

The measurement strategy ([yelu_research_framing.md](yelu_research_framing.md))
uses paired oracle-backed benchmarks with contamination-aware evaluation:
task IR independent of both languages, matched yelu and cmake derivations,
and control conditions that separate "language design" gains from "external
reference" gains.

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
