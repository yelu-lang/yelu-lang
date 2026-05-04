# Yelu Research Framing

> Status: Reference. This doc captures the research-level framing (what yelu
> is, what it's testing, how to measure, what traps to avoid) distilled from
> external review. CLAUDE.md's Design Vision is the load-bearing summary; this
> doc is the longer-form reasoning that motivates it.

## Broader context

Yelu-cmake is a **specimen within a broader pl+ai research thread** that
spans multiple project sessions (genius, ecosem). The broader thread — what
properties a meta-layer needs for AI-guided stack bootstrapping, how new
target packs compose coherently, what PL flavor the meta-layer takes — is
still in flux across those sessions and is **not closed here**. This doc
reflects only what yelu-cmake is intended to contribute to it.

The minimum concrete claim yelu-cmake must support:

> **AI can boost a single person to meaningfully enhance an existing,
> widely-used but poorly-implemented language — its ecosystem, tooling, and
> semantics — end-to-end.**

That's a modest, falsifiable demo. A working yelu-cmake with measurable
improvements in model-driven generation and repair is evidence that
one-person language enhancement under AI assistance is tractable. Stronger
claims (generalization to non-cmake targets, laws of AI-era language design,
meta-layer principles) belong to the broader thread and depend on specimens
beyond yelu-cmake.

The two framings are compatible and should be read together:

- **This doc** positions yelu-cmake within the research as a specimen and
  describes the experiments it can support.
- **The broader thread** (sessions outside this repo) is where the
  meta-layer principles get argued.

## Project statement (yelu-cmake specimen)

> Yelu is a controlled front-end for studying whether regular syntax, explicit
> namespaces, canonical forms, and local verification improve model-driven
> generation and repair for configuration languages, with cmake as the first
> target and equivalence oracle.

Two motivations, treated deliberately asymmetrically:

- **"Better cmake" is the grounding constraint**, not the intellectual center.
  cmake gives yelu a concrete target, an equivalence oracle (existing cmake
  execution), and an adoption path. Without it, the research is ungrounded.
- **Language design for machine-driven production is the research program.**
  cmake is the first specimen; the pattern is meant to generalize to other
  patchwork config targets (Dockerfile, Terraform HCL, k8s YAML, Nix).

If the two motivations conflict, the research program wins — but they usually
reinforce each other, because cmake's pathologies (irregular surface, late
errors, stringly-typed dispatch) are exactly what makes model generation
unreliable.

## Primary optimization target

**Human-plus-model production with verifier feedback**, not "LLMs as primary
users." The target workflow is:

1. Model generates a yelu program from a task description.
2. Verifier (type checker, canonicalizer, equivalence oracle) provides
   structured feedback.
3. Model repairs based on verifier output.
4. Humans review and direct.

A language optimized *only* for model consumption fails humans; a language
optimized for verifier-guided model production can still be a good language.
The distinction matters for positioning — "LLMs as users" sounds unserious;
"human+model under verification" is a defensible research object.

## Core language-level property: low entropy

The unifying property we're optimizing for is **low entropy** in names, forms,
defaults, and error locations. One way to say a thing, few hidden defaults,
few overloaded names, few stringly-typed dispatch points.

Concrete sub-properties, in priority order for machine-driven generation and
repair:

1. **Closed-world names and typed slots** — every identifier lives in a named
   typed space; no silent shadowing across namespaces (variables, targets,
   properties, cache, env are distinct).
2. **Local, structured failure** — faults surface at their origin, not three
   calls later; errors carry *why* information (declared here, required by X).
3. **Canonical surface forms** — a canonicalizer collapses equivalent programs
   into one standard form. Huge for repair: models can always normalize before
   diffing, producing stable edit targets. Ties to Y4 (e-graphs).
4. **Explicit phase boundaries** — compile / configure / build / install are
   named in the surface, not implicit. Ties to Y8 (multi-stage core).
5. **Regular grammar** — one syntactic form per concept. Unambiguous parse is
   table stakes, not a differentiator.
6. **Searchable type/schema surfaces** — type information is first-class AST
   data the model can query and enumerate against.
7. **Deterministic operational semantics** — no hidden global state, no
   evaluation-order-dependent results.

"Regularity + typed namespaces + early errors" (the earlier framing) is a
special case of low entropy. Adopting the low-entropy framing scales better
because it covers properties not on the original list (deterministic
semantics, canonicalization) that have independent evidence of helping model
generation.

## Type system stance

**GADT inside, searchable schema outside.** Two surfaces, not one:

- **Internal typed IR** — compiler-facing. Can use OCaml-level types (GADTs,
  phantom types) for compiler correctness. Invisible to the language user and
  to models consuming yelu.
- **Source-visible type/schema/contract objects** — AST-level data the model
  can see, query, complete against, and repair against. Gradual / soft typing,
  Typed-Racket style. First-class types as AST data, with optional
  enforcement.

If the model cannot see the types in the source language, in diagnostics, or
in API surfaces, they don't help generation much. If the compiler's internal
types aren't strong enough, the compiler is fragile. Both matter. See
`yelu_typed_design.md` for the design space.

Nickel is the closest precedent (gradual typing, contracts, LSP). Typed Racket
is the closest design pattern (typed+untyped modules coexisting). CUE is the
closest on "strongly typed constraint language with compact regular grammar
for tools."

## Precedents worth knowing

None of these fits yelu's exact dual motivation (front-end a messy incumbent
while explicitly studying machine-oriented language design), but each
contributes a piece:

- **Starlark** — deterministic, hermetic; restricted host language over a
  legacy/problem domain (Bazel rules). Closest *product* precedent.
- **CUE** — strongly typed constraint language. "Compact and regular grammar
  for easy analysis by automatic tools." Closest *grammar-design* precedent.
- **Dhall** — total language for configuration; type-check ⇒ finite
  evaluation. Closest *safety-guarantee* precedent.
- **Nickel** — gradual typing + contracts + LSP. Closest *type-system*
  precedent for yelu's instincts.

The gap: none of these both front-ends a messy incumbent language *and*
explicitly measures language properties for machine-driven production. That
gap is yelu's opportunity.

## Measurement strategy

Naive "prompt the model with cmake vs yelu" will mostly measure training-data
exposure. The proper setup is a paired, oracle-backed, contamination-aware
benchmark.

### Structure

1. **Task IR independent of both languages.** Define tasks in a neutral
   representation (perhaps a subset of yelu-core plus task-specific
   annotations, or a separate task spec language).
2. **Matched derivations.** From the task IR, derive identically-semantic
   cmake and yelu programs. Evaluation oracles are the same for both.
3. **Multiple regimes per task:**
   - First-pass unconstrained generation.
   - Bounded repair loop (N iterations with verifier feedback).
   - Verifier-assisted generation (constrained decoding, type-constrained
     sampling).
4. **Measure semantic success, not syntax success.** Does the generated
   program produce the required build/artifact behavior? Syntax/type pass
   rate is secondary.

### Control conditions

At minimum run these arms:

- Raw cmake, unconstrained decoding
- Raw yelu, unconstrained decoding
- cmake with identical grammar/reference-card support
- yelu with identical grammar/reference-card support
- (Optional) both under syntax- or type-constrained decoding

The grammar/reference-card arm is critical. If yelu wins only because it gets
a nicer cheatsheet, nothing is learned. The constrained-decoding arm tests
whether gains come from the language itself or from the external verifier.

### Additional control: "disciplined cmake"

Before declaring "language design improves outcomes," add an arm: cmake
written under a style guide that captures yelu's disciplines at the surface
level (explicit scope keywords, no implicit dereference, canonical naming).
If this arm captures most of yelu's gains, the lesson is about convention,
not language. Worth knowing early.

### Contamination control

Static public benchmarks are contamination-prone; LLMs have seen them.
Mitigations:

- **Dynamic task regeneration** (DyCodeEval pattern): semantically equivalent
  tasks regenerated from the task IR, so models can't recall specific
  solutions.
- **Time-consistent snapshots**: fix the evaluation environment (model
  snapshot, prompt construction, reference card) so variability is in the
  conditions being tested, not the infrastructure.
- **Prompt parity**: identical prompt construction across conditions. Prompt
  granularity alone can swing results as much as language choice.

## Traps to design against

1. **Overfitting to cmake.** If findings only replicate against cmake's
   specific pathologies, say so. Generalization to Dockerfile/HCL/YAML/Nix
   is a claim that needs validation, not assumed.
2. **Measuring the verifier, not the language.** Grammar constraints, type
   constraints, retrieval, repair loops can each move the needle
   independently. Ablate them.
3. **Prompt leakage.** Prompt construction is a first-order variable. Pin it
   across conditions.
4. **Escape-hatch rot.** If hard cases route through raw pack-specific
   strings, the typed core is decorative. Treat "can this pack-specific
   pattern be expressed typed-only?" as a passing condition for each new
   cmake feature integrated. If escape-hatch usage grows, the low-entropy
   property is slipping.
5. **Weak equivalence oracles.** If the cmake oracle is only stdout or a
   shallow structural diff, behavioral mismatches leak through. File-API
   comparison, target-property comparison, and ideally symbolic equivalence
   for the configure phase are all needed.
6. **First-pass success hiding repair failure.** Repair convergence is as
   important as first-pass correctness for the thesis. Measure both.

## Relationship to existing TODOs

The research framing ties back to the project backlog:

- **Y2, Y3, Y4** (option enumeration, Z3 symbolic equivalence, e-graphs) are
  the semantic-oracle infrastructure the measurement strategy depends on.
- **Y5** (File API as semantic oracle) is the minimum viable equivalence
  oracle beyond structural diff.
- **Y7** (cache-sensitivity annotations) and **Y8** (multi-stage core) are
  concrete consequences of the "explicit phase boundaries" low-entropy
  sub-property.
- **Y11** (policy-aware compiler/printer) and canonicalization form the
  "canonical surface forms" backbone together.
- **Y13** (persistent value primitive) is orthogonal to the research framing
  but reinforces "low-entropy yelu-core primitives" as a design direction.
