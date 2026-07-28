# cmake_policy — Review, Design, and PL Framing

## What is cmake_policy?

cmake has 215 numbered policies (CMP0000–CMP0213 in cmake 4.3). Each policy
encodes a single behavioral change that cmake made at some version. Every policy
has exactly two states:

| State        | Meaning                                                              |
| ------------ | -------------------------------------------------------------------- |
| `OLD`        | Backward-compatible behavior (pre-change); often buggy or surprising |
| `NEW`        | Correct/modern behavior; the direction cmake is moving               |
| `""` (unset) | cmake may warn; in practice behaves like OLD                         |

The four cmake_policy commands:

```cmake
cmake_policy(VERSION <min>[...<max>])    # set all policies up to <min> as NEW
cmake_policy(SET CMP<NNNN> <NEW|OLD>)   # override one policy explicitly
cmake_policy(GET CMP<NNNN> <var>)       # query current state into <var>
cmake_policy(PUSH) / cmake_policy(POP)  # save/restore the policy stack
```

`cmake_minimum_required(VERSION x.y)` is equivalent to `cmake_policy(VERSION x.y)`:
it sets every policy introduced at or before version x.y to `NEW`. This is the
normal way to opt in — explicit `SET` calls are for exceptional overrides.

---

## Interim handling pattern (pre-Y11)

> Everything below the next divider is the **full Y11 design** (semantic
> modeling of the policy stack). This section is the **operational pattern we use
> now**, before Y11 — how policy is handled in probes and faithful translation.
> It is deliberately small: for faithful emit, yelu does **not** need to *model*
> policy semantics, only *preserve* the call so real cmake applies it.

### Two contexts (don't conflate them)

- **Faithful translation (probes).** The policy call is *in the source*; yelu's
  job is only to **emit it back** so real cmake applies it. This is yc's faithful-
  erasure role — no semantics, no stack modeling. The matrix runs *real* cmake on
  yelu's output, so a preserved `cmake_policy(...)` just works.
- **yelu-authored programs (the blocked tests below).** Here yelu must *decide*
  to emit a policy the user didn't write (CMP0140 for `return(PROPAGATE)`, etc.).
  That is the compiler-responsibility problem Y11 solves and is **deferred**.

The probe/translation case is the one that matters now, and it's nearly free.

### Two facts to be clear about

- **Default policy state is version-gated, not "all on."** A policy with no
  setting behaves as `OLD` and cmake *warns*. `cmake_minimum_required(VERSION x.y)`
  (or `cmake_policy(VERSION x.y)`) sets every policy introduced **at or before**
  x.y to `NEW`; policies newer than the declared version stay unset (OLD + warn)
  until explicitly `SET`. So "what's NEW by default" is exactly what the project's
  declared minimum version covers.
- **yelu has no policy interpreter — it translates only.** Every `policy_*`
  command evaluates to a no-op (`VUnit`) in `yelu_cmake_eval`; yelu never models
  the policy stack or a policy's behavioral effect. It emits the `cmake_policy(...)`
  text and **real cmake** (which the matrix and every build run) does the
  interpreting. This is deliberate faithful erasure; the interpreter is the Y11
  semantic model, deferred.

### Surface coverage — the whole family is now first-class (2026-07-27)

Every `cmake_policy(...)` form has an explicit yc command; **no `yc_raw` is
needed for policy**. Emit is faithful (verified end-to-end):

| cmake form                           | yc surface                         | → emits                                                                         |
| ------------------------------------ | ---------------------------------- | ------------------------------------------------------------------------------- |
| `cmake_policy(SET CMP#### NEW\|OLD)` | `policy_set CMP#### [NEW\|OLD]`    | `cmake_policy(SET CMP#### NEW\|OLD)` — NEW/OLD now honoured (was hardcoded NEW) |
| `cmake_policy(VERSION min[...max])`  | `policy_version 'min[...max]'`     | `cmake_policy(VERSION min[...max])`                                             |
| `cmake_policy(GET CMP#### var)`      | `policy_get CMP#### var`           | `cmake_policy(GET CMP#### var)`                                                 |
| `cmake_policy(PUSH)` / `(POP)`       | `policy_push` / `policy_pop`       | `cmake_policy(PUSH)` / `(POP)`                                                  |
| `if(POLICY CMP####)`                 | if-predicate (`ECmakePolicyCheck`) | `if(POLICY CMP####)`                                                            |

These are *faithful erasure* (yc preserves what the source wrote); no policy
*semantics* is modelled — see the recipe's pause caveat.

### The handling recipe

1. **Translate every policy call directly** with the matching `policy_*` command.
   No `yc_raw` for policy.
2. Never silently drop a policy call — a dropped `SET` can make a matrix cell
   diverge for a reason that looks unrelated. (The old `policy_set` OLD→NEW
   coercion was exactly this kind of silent bug; fixed 2026-07-27.)
3. **Pause only for policy *semantics*, not syntax.** The surface is complete, so
   translation never pauses. Pause (per the [probe charter](../../probes/PROBE_CHARTER.md))
   only if a project's *behavior* depends on yelu *evaluating* the policy stack
   (a `GET` result driving yelu-side control flow, PUSH/POP scoping affecting
   yelu's eval) — that is the Y11 semantic model, still deferred. The matrix runs
   real cmake, so configure-time behavior is correct regardless.

### Detection — explicit vs collect

Both, matched to context:

- **Explicit (probes — do this).** In the *learn* phase, grep the project:
  `cmake_policy(`, `if(POLICY`, and `cmake_minimum_required`. Policy is
  source-visible, so this enumerates every form up front — classify each
  covered/uncovered against the table above before writing any `.yc`. (json:
  only `SET CMP0077 NEW` → covered by `policy_set`; the `if(POLICY CMP0077)`
  guard is the one thing to verify.)
- **Collect (yelu-authored tests).** When a testcase *diverges* and a policy is
  implicated, classify it policy-related and tag it in the gap registry
  ([`lang_coverage.md`](../yelu_cmake/lang_coverage.md) § gaps — use a `policy`
  category). This is the harder Y11 case where yelu must *infer* the policy.

### Surface implementation — done (2026-07-27)

The full family shipped as explicit yc commands (the standard add-a-command
recipe — command_names + `_inner` + cmake_op-fragment ctors + emit arms + convert
+ coverage-lock cases + `dune promote`):

1. `policy_set` state is now an **expr**, not a `bool` — it carries a literal
   `NEW`/`OLD` *or* a variable (`policy_set CMP#### $STATE` → `cmake_policy(SET
   CMP#### ${STATE})`). This fixed the original hardcoded-NEW bug *and* a
   faithfulness gap: cmake accepts a variable for the policy state, which a
   `bool` could not represent (it silently coerced `$STATE` to `NEW`).
2. `policy_version` / `policy_get` / `policy_push` / `policy_pop` added → the
   `Cmake_policy_*` AST ctors. Two small AST fixes came with it: `VERSION`'s
   `max` is now `version option` (bare `VERSION min` renders), and `GET` now
   carries the CMP `id` (`Cmake_policy_get { id; var }`) so it emits
   `GET CMP#### var`.

What remains is the *semantic* model (Y11 below): evaluating the policy stack /
auto-emitting a policy for yelu-authored constructs. Faithful translation no
longer needs any of that.

### Testing a policy in a probe — worked example (copy this shape)

When a probe project enables a policy, add a test that **flips the policy and
checks the observable difference on both sides**. That proves yelu *carries* the
policy state — not just that it emitted some text. (A translate-only bug like the
old `policy_set` OLD→NEW coercion is invisible unless the two states are compared.)

The cleanest handle is a policy with a deterministic **configure-time** effect —
which is also what the probe matrix already diffs (the cache channel). Use
**CMP0077** (`option()` honors normal variables — the policy json actually sets):

```
# yc  (probes/<project>/… or a standalone cell)
cmake_minimum_required '3.13';
MY_OPT := 'ON';                 # a normal variable, set before option()
policy_set CMP0077 NEW;         # flip this NEW ↔ OLD across two cells
project pol NONE;
option MY_OPT 'demo option' OFF
```

emits faithfully and configures to an observable that **differs by policy state**
(measured, cmake 4.3):

| `policy_set CMP0077 …` | emits | `MY_OPT` in `CMakeCache.txt` |
| --- | --- | --- |
| `NEW` | `cmake_policy(SET CMP0077 NEW)` | *absent* — the normal `ON` wins |
| `OLD` | `cmake_policy(SET CMP0077 OLD)` | `MY_OPT:BOOL=OFF` — `option()` created a cache entry |

The test (a matrix cell per policy state):

1. Configure **vanilla cmake** and **yelu-emitted cmake** for each state.
2. Assert the cache observable **matches vanilla ≡ yelu** within each state
   (faithful carry), **and** **differs NEW vs OLD** (the policy is really applied,
   not silently coerced). If yelu had the OLD→NEW bug, the `OLD` cell would show
   *absent* like NEW and the "differs" assertion would fail — the test catches it.

This is the same per-cell shape as an option matrix cell; treat the policy state
as the cell axis.

#### Dynamic (build-observable) policies — toolchain-gated

For a policy whose effect is *behavioral* (a compiler/linker flag, e.g. CMP0065's
`-rdynamic` → exported symbols), the observable is toolchain-dependent — it shows
up on some toolchains and not others. We still test it, **gated on the local
toolchain**, via the `build_equiv` **`policy.json` fixture mode**
(`check_policy_fixture`):

- The fixture declares `{ "policy", "states": ["NEW","OLD"], "state_var": "STATE" }`.
  The policy state is a cmake **variable** — `cmake_policy(SET CMP#### ${STATE})`
  in `CMakeLists.txt`, `policy_set CMP#### $STATE` in `main.yc` — varied per state
  via `-DSTATE=…` (a normal `-D` cell axis, like an option). yelu carries the
  variable faithfully (a `policy_set` state is an *expr*, not a hardcoded bool),
  so one yelu compile serves every state. The harness builds the reference and
  the yelu-emitted cmake for each state and fingerprints each (artifacts + `nm`).
- **The gate is self-contained — no hard-coded toolchain knowledge.** If
  *vanilla cmake* yields an identical build across states, the toolchain doesn't
  exhibit the policy → **SKIP**. If it differs, assert **yelu == reference in
  each state** (faithful carry). This generalizes build_equiv's existing
  SKIP-on-unavailable + control-build philosophy: the reference's own
  NEW-vs-OLD difference *is* the observability signal.
- Example fixture: `test/fixtures/build_equiv/policy_cmp0065/` (it SKIPs on our
  cmake 4.3, which removed CMP0065's `OLD`; runs where the policy is settable
  both ways and the linker honors it).

Note cmake 4.x **removes the `OLD` behavior of many older policies** (setting
them to `OLD` is a hard error), so a NEW-vs-OLD behavioral test needs a
recent-enough policy — or it skips. Configure-time policies (like CMP0077 above)
are the more portable handle.

### Infra prep (what's already ready)

- **The `yc_raw` passthrough net exists** and is proven (fmt). A probe never
  crashes on an unmodeled policy form — it escapes + records.
- **What to add when policy work starts:** a `policy` category in the yc and ycn
  gap registries, so collected policy-related divergences are classified
  consistently (mirrors the emit/semantic gap registry).

---

## The Policy Stack

Policies are stored on a stack. `cmake_policy(PUSH)` saves the current state;
`cmake_policy(POP)` restores it. cmake pushes/pops automatically at:

- `include()` — a fresh push before the included file, pop after
- `add_subdirectory()` — same scope isolation
- `function()` / `macro()` definitions — the defining scope's stack is copied

The result: included modules can set policies without polluting the caller's
namespace. A module that needs `CMP0140 NEW` can `PUSH`, set it, do its work,
and `POP` — the caller is unaffected.

---

## Three Policies Blocking Yelu Tests

### CMP0124 — foreach loop-variable scoping (cmake 3.21)

| Behavior | Effect                                                                  |
| -------- | ----------------------------------------------------------------------- |
| OLD      | Loop variable always set after loop ends (to `""` if never had a value) |
| NEW      | Loop variable restored to state before loop started (set or **unset**)  |

Blocked test: `test_foreach.ml` / `test_foreach2.ml` — ZIP_LISTS loop variable
state after loop exits. With CMP0124 NEW, `unset(loop_var)` after the loop is the
correct expectation. Without it, the variable is `""`.

### CMP0140 — `return()` parameter checking (cmake 3.25)

| Behavior | Effect                                                             |
| -------- | ------------------------------------------------------------------ |
| OLD      | `return()` ignores all parameters silently                         |
| NEW      | `return(PROPAGATE var …)` is valid; unrecognized params are errors |

Blocked test: `test_return.ml` — `return(PROPAGATE MY_VAR)`. This syntax doesn't
exist under OLD. Under NEW, return propagates the listed variables to the caller's
scope, a critical feature for function-based APIs.

### CMP0186 — REGEX `^` anchor in repeated searches (cmake 4.1)

| Behavior | Effect                                                        |
| -------- | ------------------------------------------------------------- |
| OLD      | `^` re-anchors to the start of each successive match position |
| NEW      | `^` matches at most once (standard POSIX semantics)           |

```cmake
# OLD:  result = "bbbb"   (^ matches before every 'a')
# NEW:  result = "baaa"   (^ matches only at position 0)
string(REGEX REPLACE "^a" "b" result "aaaa")
```

Affects: `string(REGEX MATCHALL)`, `string(REGEX REPLACE)`,
`list(TRANSFORM REPLACE)`.

---

## PL Perspective: What cmake_policy Really Is

cmake's policy mechanism is an instance of a well-studied PL problem:
**versioned behavioral semantics** — how a language evolves without breaking
existing code.

### Analogues in other languages

| Language   | Mechanism                                 | cmake analogue                         |
| ---------- | ----------------------------------------- | -------------------------------------- |
| Rust       | `edition = "2021"` in Cargo.toml          | `cmake_minimum_required(VERSION 3.21)` |
| Python     | `from __future__ import annotations`      | `cmake_policy(SET CMPxxxx NEW)`        |
| Perl       | `use feature 'say'`                       | same                                   |
| Scala      | `-source:3.3` compiler flag               | same                                   |
| ECMAScript | `"use strict"`                            | same                                   |
| Haskell    | language pragmas (`{-# LANGUAGE ... #-}`) | same                                   |
| C          | `_POSIX_C_SOURCE`, `__STDC_VERSION__`     | same                                   |

The key distinction from most of these is cmake's **dynamic scoping** via the
policy stack — Rust editions are file-granular and compile-time; cmake policies
are runtime, per-scope, and mutable during execution.

### Two orthogonal axes

cmake_policy lives at the intersection of two axes:

```
                      ┌──────────────────────────────────────────────┐
                      │            SEMANTIC AXIS                      │
                      │  OLD (compat) ◄────────────────► NEW (correct)│
SCOPING               │                                              │
AXIS                  │  per-call-site                               │
                      │  per-include                                 │
(dynamic,             │  per-subdirectory                            │
 stack-based)         │  per-function-definition                     │
                      │  global (cmake_minimum_required)             │
                      └──────────────────────────────────────────────┘
```

Most versioned-semantics mechanisms handle only the semantic axis (pick a
version at the module/project level). cmake handles both — the stack lets
included modules opt into NEW behavior without forcing their callers to change.

### The deprecation lifecycle

cmake's documented lifecycle for every policy:

```
introduced in version N → warns if unset → behavior changes in a future version
→ OLD behavior deprecated → OLD behavior removed (never: cmake commits forever)
```

The "never removed" commitment is cmake's core promise. The result: CMP0000
(2006) is still valid in cmake 4.3. This is very different from Rust editions,
which can eventually phase out old behavior.

---

## Design Options for Yelu

There are three points in the design space, from simplest to most precise.

### Option A — Version declaration only (minimal)

```ocaml
(* User declares the minimum cmake version once at program level *)
yc_minimum_required { min = (3, 25); max = None }
```

yelu implicitly treats all policies ≤ declared version as NEW. No explicit
`cmake_policy(SET …)` in generated output. The user gets correctness as long as
their cmake version matches the declaration.

**Pro**: zero new concepts; already in yelu via `Yc_minimum_required`.  
**Con**: cannot express per-scope policy overrides; cannot test OLD vs NEW behavior.

### Option B — Per-construct policy annotations (typed)

Each yelu construct that requires a specific policy carries that requirement as
metadata. The compiler emits the correct `cmake_policy(SET …)` preamble automatically.

```ocaml
(* User writes: *)
yc_return ~propagate:["MY_VAR"] ()

(* Compiler detects CMP0140 required, auto-emits: *)
(* cmake_policy(SET CMP0140 NEW) *)
(* return(PROPAGATE MY_VAR) *)
```

The requirement is declared in the yelu construct definition, not by the user.

```ocaml
type policy_requirement =
  | Policy_req of { cmpnnnn : int; state : [`New | `Old] }

type yelu_exp =
  ...
  | Yc_return of { propogate_vars : string list; policy : policy_requirement option }
```

**Pro**: transparent to the user; errors are impossible (wrong policy → construct
doesn't type-check).  
**Con**: compiler must know version context to avoid emitting redundant `SET` calls
when `cmake_minimum_required` already covers the policy.

### Option C — Explicit policy blocks (full surface)

yelu exposes the full policy stack to users, with a typed policy enum instead of
raw `CMP0140` strings.

```ocaml
type cmake_policy =
  | Cmp0124 | Cmp0140 | Cmp0186 | ...  (* only policies yelu constructs use *)

yc_policy_push
yc_policy_set Cmp0140 `New
...
yc_policy_pop
```

**Pro**: users can write exact cmake semantics; PUSH/POP available for module authors.  
**Con**: exposes cmake's缝缝补补 surface; working against yelu's goal of hiding
cmake complexity.

---

## Recommended Approach for Yelu

**Start with Option A + selective Option B.**

- `yc_minimum_required` already handles the global case.
- For the three blocked constructs specifically:
  - `return(PROPAGATE …)` — compile `Yc_return { propogate_vars = [...] }` always
    with `cmake_policy(SET CMP0140 NEW)` prepended, as a compile-time concern.
  - `foreach` CMP0124 scoping — this only matters for test equivalence; the user
    doesn't control it, so emit `cmake_policy(SET CMP0124 NEW)` at the top of
    programs that use `Yc_foreach`.
  - CMP0186 regex — same: emit when `Yc_string_regex_*` with a `^` pattern is used.
    (Auto-detection is optional; `yc_minimum_required (4,1)` is simpler.)
- Option C (full policy stack) is for cmake-pack module authors — out of scope
  for yelu-core.

The key insight is that policies are a **compiler responsibility**, not a user
responsibility: yelu constructs that require a policy should emit it themselves.
This is the direct analogue of Rust emitting the correct edition-gated code without
the user inserting `#[feature(…)]` annotations.

---

## Implementation Notes

### Current cmake AST coverage (updated 2026-07-25)

The cmake AST already has all five ctors, and `SET` is now emit-complete:
```ocaml
| Cmake_policy_version of { min : version; max : version }
| Cmake_policy_set of { id : string; new_ : bool }   (* id = "CMP0077"; NEW/OLD *)
| Cmake_policy_get of { var : var }
| Cmake_policy_push
| Cmake_policy_pop
```

`Cmake_policy_set { id; new_ }` carries the CMP id (as string) and NEW/OLD — so
the cmake layer *already emits* `cmake_policy(SET CMP0077 NEW)` faithfully, and
the yc surface `policy_set` (in `command_names`) drives it. The remaining
surface gaps are the *other* forms (VERSION/GET/PUSH/POP → currently `yc_raw`)
and the `policy_set` OLD-coercion bug (`yelu_parse.ml:1425`) — see the interim
handling pattern near the top. `id : string` (vs the typed enum below) is the
deliberate faithful-emit choice: yc preserves the id verbatim; a typed
`cmake_policy_id` enum belongs to the Y11 semantic model.

### Typed policy enum

Rather than a raw integer, define:

```ocaml
type cmake_policy_id =
  | Cmp0124  (* foreach scoping, 3.21 *)
  | Cmp0140  (* return(PROPAGATE), 3.25 *)
  | Cmp0186  (* REGEX ^ anchor, 4.1 *)
  | Cmp_raw of int  (* escape hatch for unlisted policies *)

type cmake_policy_state = Policy_new | Policy_old

| Cmake_policy_set of { policy : cmake_policy_id; state : cmake_policy_state }
| Cmake_policy_get of { policy : cmake_policy_id; var : var }
```

### Policy version table (subset)

| Policy  | Introduced | Topic                    | Blocked yelu test                 |
| ------- | ---------- | ------------------------ | --------------------------------- |
| CMP0124 | 3.21       | foreach loop-var scoping | test_foreach.ml, test_foreach2.ml |
| CMP0140 | 3.25       | return(PROPAGATE)        | test_return.ml                    |
| CMP0186 | 4.1        | REGEX ^ anchor           | test_string2.ml                   |
| CMP0130 | 3.29       | while() condition checks | (while tests — not urgent)        |

### What to implement

1. Fix `Cmake_policy_set` in the cmake AST (`nnnn : int * state`, not `bool`).
2. Add `Yc_cmake_policy_set`, `Yc_cmake_policy_push`, `Yc_cmake_policy_pop` to
   the yelu AST.
3. In `compile` for `Yc_return { propogate_vars = _ :: _ }`, prepend
   `Cmake_policy_set { policy = Cmp0140; state = Policy_new }` to the output
   (or require the user to emit it explicitly — TBD by design choice above).
4. Unblock the three test files by adding the appropriate policy preamble.
