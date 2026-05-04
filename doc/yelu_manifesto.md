# Yelu — Project Manifesto

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

## The approach

### Two-layer architecture

```
  yelu (core)     ← language-agnostic: bindings, composition, types
    │
  cmake-pack       ← target-specific: cmake abstractions, namespace types
    │
  cmake AST        ← stringly-typed, mirrors real cmake
    │
  CMakeLists.txt   ← output, verified against reference
```

The core is a collection of **theories** — each `Make_*_op` / `Make_*_check`
functor pair defines typed constructors and type-checking rules for one
cmake command family (target, variable, string, path, install, test, …).
Theories compose via a shared `LANG_TYPES` substrate; the cmake-pack is
the integration point. Future packs (json, nix) reuse the core with their
own statement types and theories.

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
- **281 unit tests** (70 cmake PP + 194 yelu compile + 17 yelu type check)
- **108 equivalence/semantic checks** (35 structural + 12 CMakeOnly + 61 RunCMake)
- **12 end-to-end tutorial steps** (generate → configure → build → run)
- **72 step generators** (36 cmake + 36 yelu) covering tutorials and test suites
- **No CI**, **no concrete parser**, **no name binding pass** — these are the
  nearest gaps

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
