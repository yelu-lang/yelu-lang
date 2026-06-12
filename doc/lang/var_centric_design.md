# Var-centric design — value-default reads (postponed / future)

> **Status: postponed.** A future direction explored 2026-06-12, parked
> pending a frequency study. Grew out of critique item #4 (`${X}` noise) and
> the `EVarLookup` work — see [`yc_syntax_critique.md`](yc_syntax_critique.md)
> and [`../cmake/var_reference_semantics.md`](../cmake/var_reference_semantics.md).

## The proposal

Invert cmake's convention. Today (cmake-faithful): **name is the default,
value is explicit** — bare `foo` = the literal string `"foo"`, `${foo}` =
read. Proposed: **value is the default, name is explicit** — bare `foo` =
read, `#foo` (or some sigil) = the name. This is the normal-language model:
lvalue/rvalue with auto-deref (C++ references, Python names); reflection on
the *name* is the rare explicit op. In IR terms it is the dual of
`EVarLookup`: that made *lookup* an explicit op over a name; this makes
*value* the default and `NameOf` the explicit op.

## Why it is not an obvious win

**It moves the escape, it doesn't remove it.** The `${}` noise relocates from
*reads* to *name-uses*. Net win is a frequency bet: it pays only if reads
outnumber name-uses. And in real cmake, name-uses are **not** rare:

- output parameters by name — the corpus does this: `fun join(result_var) ( …
  ${result_var} := "${result}" … )`; cmake functions have no real return values;
- target / property / cache names, `defined foo`, computed names `${${x}}`.

So you trade `${}` on every read for `#` on every name-pass, target ref, and
declaration.

## Why it cannot live in `yc`

yc is the cmake-*faithful* surface, and that is the blocker. In a
generic/variadic command arg, cmake is genuinely ambiguous between a **literal
word** and a **value** — `message(foo)` prints `"foo"`, `message(${foo})`
prints the value. That ambiguity is *why* cmake mandates `${}`. Make bare =
value and every literal word / unstructured keyword needs escaping; the noise
just relocates again. Position-disambiguation rescues only structured slots.

**ycn has no such problem.** ycn is normalized — commands are theory ops with
*typed slots*, so value-slot vs name-slot is already known; the ambiguity that
blocks yc does not exist. **Conclusion: this belongs in ycn, not yc.** yc keeps
the faithful explicit-`${}` model (critique #4 = *defend*).

## Two ideas, evaluated apart

- **(A) Syntax inversion** — bare = value, `#foo` = name. Ergonomic; debatable
  net win (frequency bet); safe only where slots are typed (ycn).
- **(B) Var-as-typed-handle** — a variable is a *declared entity*, not a
  conjurable string; name-ops live in a gated module; casual stringification
  forbidden. The strong, durable idea, independent of (A): kills typo-named
  variables, makes namespaces real, gives analysis a first-class entity.

(B) already half-exists: the legacy typed layer had `tc_name = { ns :
cmake_namespace; name : string }` with `Ns_var | Ns_target | Ns_cache | …`;
production `yelu_cmake` collapsed it to bare strings. Reviving it in ycn is
exactly the ground **Y17** (types on yelu_cmake) stands on; the wellform pass
is its first consumer.

## What to study before any code

1. **Frequency** — across the probe corpora (fmt/z3/llvm), count bare-name
   occurrences by role: *read* (`${X}`) vs *name-use* (set-LHS, target/
   property/cache name, output-param, computed name) vs *keyword*. If reads ≫
   name-uses, (A) earns its keep; if comparable, keep cmake's convention.
2. **Disambiguation coverage** — classify ycn slots into value / name /
   ambiguous. (A) is feasible exactly to the extent "ambiguous" is empty.

**Read going in:** (B) is worth doing in ycn as part of Y17 regardless (an
abstraction/soundness win, not a syntax bet); (A) is a ycn surface-syntax
choice that should wait on the frequency study, and must not touch yc.
