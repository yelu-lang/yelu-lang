# yc / ycn boundary — which layer does a feature belong to?

> **Status: adopted 2026-07-16.** A triage rule for "where does this feature
> go?", promoted from three independent design threads that each reached the
> same boundary without a stated policy. Companion to
> [`../manifesto.md`](../manifesto.md) (the layer thesis) and
> [`../yelu_cmake/cmake_vs_normal.md`](../yelu_cmake/cmake_vs_normal.md)
> (what the two forms actually are).

## The rule

> **yc** = anything that **erases** to cmake with no semantic gap.
> **ycn** = anything that needs a **value or type model**.

The test, operationally:

> Can you write the emit rule without inventing a runtime representation?
> If emitting requires synthesizing an *encoding* — packing a value into a
> cmake string, generating helper code to decode it, or tracking a type at
> configure time — it belongs in ycn.

## Why not the naive rule

"yc = only what cmake has" is tempting and **wrong** — it's already falsified
by shipped yc features that cmake has no concept of:

| yc surface | cmake emit |
| --- | --- |
| `~label=value` / `~flag` | positional keyword args |
| enum constructors (`Public`, `Target`, `Cache`) | `PUBLIC` / `TARGET` / `CACHE` |
| `if c then ( … ) else ( … )` | `if()/else()/endif()` |
| `foreach x in … ( … )` | `foreach()/endforeach()` |
| `var := cmd args` (command-call sugar) | `cmd(args … out)` |
| `~properties={version=$V}` (record **literal**) | `PROPERTIES VERSION ${V}` |

None of these exist in cmake. All of them **erase**: the emitted text is exact
cmake, and the byte-equality oracle proves it. So yc is not "cmake with nicer
spelling of the same tokens" — it is *any* surface whose meaning is fully
discharged at emit time.

## Why erasability is the criterion

Because it is the property the **verification** rests on:

- the **byte-equality oracle** (`test_yelu_compile`, covered=194) compares
  emit against a reference compiler;
- the **tripled matrix** (`yelu matrix probes/fmt`) compares the emitted
  project against real cmake on cache + codemodel + ctest.

Both presuppose yc → cmake is a *transliteration*. The moment yc gains a
non-erasable feature, that becomes *compilation with semantic gaps*: the emit
rule needs a runtime representation, the oracles can no longer be
"byte-identical / structurally identical", and the strongest evidence in the
project weakens.

**yc's constraint is an asset, not a limitation.** Faithfulness is what makes
yc provable. ycn is where we're allowed to be ambitious, precisely because it
is not carrying that proof obligation.

## The precedents (this boundary was discovered, not invented)

Three separate investigations reached it independently, before any policy
existed:

| doc | conclusion |
| --- | --- |
| [`var_centric_design.md`](var_centric_design.md) | value-default reads (bare `foo` = value) — "**This belongs in ycn, not yc.** yc keeps the faithful explicit-`${}` model." The blocker is that a *generic cmake arg* is ambiguous between literal word and value; **ycn has typed slots, so the ambiguity doesn't exist.** |
| [`casing_design.md`](casing_design.md) | dotted globals (`$cmake.version`) — cosmetic in yc; "real namespacing belongs in ycn." |
| [`object_value_design.md`](object_value_design.md) §e | "yc is cmake-faithful; **ycn is the idealized algebra**… this is where the value class earns its keep at the type level." |

Note the shared shape of the argument in all three: *yc can't type the slot, ycn
can.*

## Worked example — first-class records

The motivating case, and it splits cleanly:

**Record literal as argument syntax — yc (already shipped).**
```
set_target_properties fmt ~properties={version=$V, sources=[a, b]}
  →  set_target_properties(fmt PROPERTIES VERSION ${V} SOURCES a;b)
```
The braces never survive emit; they are a *grouping notation* for a keyword
run. Extending this (shape-4 `install_targets ~library={destination=…}`) is
legitimately yc work.

**Record as a first-class value — ycn.**
```
let r = { destination = 'lib', permissions = [Read, Write] } in
install_targets $t ~library=r          -- pass it
message $r.destination                  -- project a field
```
cmake has exactly two value shapes: strings and `;`-joined lists. To make this
work in yc you would have to *synthesize* an encoding (pack the record into a
string, emit helper cmake to destructure it, keep the field types straight at
configure time). That is a value model — ycn.

**The boundary is the value flow, not the braces.** `{…}` appearing in a
command argument is surface; `{…}` bound to a name, passed, and projected is a
value.

## Applying it to the current backlog

| feature | erases? | home |
| --- | :---: | --- |
| version literal (`3.8...3.25` unquoted) | ✅ lexer-only | **yc** |
| per-mode `message_fatal` / `_warning` | ✅ alias → `~mode=` | **yc** |
| `get_property ~mode=Defined` micro-slice | ✅ | **yc** |
| shape-4 `install_targets ~library={…}` | ✅ record *literal* | **yc** |
| raw-escape unification (`yc_raw`/`ECmakeRaw`/…) | ✅ (it's about opacity) | **yc** |
| function labeled args (`fun f(~x)`) | ⚠️ via *generated* `cmake_parse_arguments` | **yc**, boundary case — see caveats |
| record as a **value** | ❌ needs encoding | **ycn** |
| entity as a **value** (Y18) | ❌ (the literal `Target foo` constructor: ✅ yc, shipped) | **split** |
| typing (Y17) | ❌ | **ycn** |
| value-default reads (var-centric A) | ❌ | **ycn** |
| var-as-typed-handle (var-centric B) | ❌ | **ycn** |
| namespaces / dotted globals | ❌ | **ycn** |

### What this resolves

- **Y18** carried an explicit "yc vs ycn placement" open question. Answered:
  surface constructor = yc (shipped via Pos2/Pos3), **value class = ycn**.
- **Y17** read ambiguously ("types on yelu_cmake") while `var_centric` said its
  ground was ycn. Answered: **typing is ycn's job**; yc gets *wellform* checks
  (name binding, reject rules), not a type system.
- The split also explains why yc's checks are all **wellform-shaped**
  (does this program have a valid cmake reading?) rather than type-shaped —
  that is the most yc can say without a value model.

## Caveats

- **This is not a freeze on yc sugar.** yc should keep gaining ergonomics
  as long as they erase. The rule constrains *kind*, not *quantity*.
- **"Erases" means deterministically and locally** — no runtime representation.
  Generated helper code is the edge: labeled `fun` args would emit a
  deterministic `cmake_parse_arguments` preamble, which is defensible (local,
  no value model), but it is the furthest yc should go. Flag such cases for
  review rather than treating them as routine.
- **ycn has no concrete syntax yet.** Today "belongs in ycn" means "blocked on
  the ycn surface" — every ycn program in the repo is hand-built OCaml
  (see [`../yelu_cmake/ycn_concrete_syntax.md`](../yelu_cmake/ycn_concrete_syntax.md)).
  That is a real cost of the discipline, and the reason ycn concrete syntax is
  the gateway to the whole ycn agenda rather than one item among many.
- **The rule triages, it doesn't design.** "ycn" is an answer about *placement*;
  the feature still needs its own design work once it lands there.
