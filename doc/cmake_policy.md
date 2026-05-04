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

### Current cmake AST coverage

The cmake AST already has:
```ocaml
| Cmake_policy_version of { min : version; max : version }
| Cmake_policy_set of { nnnn : bool }   (* incomplete: only bool, not CMP number *)
| Cmake_policy_get of { var : var }
| Cmake_policy_push
| Cmake_policy_pop
```

`Cmake_policy_set { nnnn : bool }` is clearly incomplete — `nnnn` should be an
integer policy number and `state` should be `NEW | OLD`, not `bool`. This needs to
be fixed before exposing `cmake_policy(SET …)` in yelu.

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
