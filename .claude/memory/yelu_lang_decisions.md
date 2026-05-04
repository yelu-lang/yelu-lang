---
name: yelu core language design decisions
description: Settled design decisions for yelu-core language — type system, iteration, FP vs imperative flavor
type: project
---

Decisions agreed 2026-04-14. Do not re-open without new evidence.

**1. ZIP_LISTS / multi-var iteration → `zip` as library function**
cmake's `foreach(x y IN ZIP_LISTS l1 l2)` is expressed in yelu as:
`for (x, y) in zip(l1, l2) do ...`
`zip : list<A> -> list<B> -> list<(A, B)>` is a core library function.
No multi-var `for` syntax needed — tuple destructuring handles it.

**2. First type system: monomorphic typed lists (≤12 cases)**
No type variables yet. Fixed set: `string_list`, `file_list`, `dir_list`,
`target_list`, `name_list` — one per `yarg` variant.
Cross-use (`link_lib [a_file]`) → type error. Polymorphism deferred.

**3. FP flavor: expression-oriented core, no `return` keyword**
- Every construct is an expression; last expression is the return value.
- No `return`, no `while` in yelu-core.
- `Yc_return`, `Yc_break`, `Yc_continue` are cmake-PACK primitives — they emit
  cmake return()/break()/continue() into CMakeLists.txt. NOT core control flow.
- `for` over `list<T>` produces `list<U>` (it is `map`); side-effecting `for`
  is the case where `U = unit` (emitting cmake nodes).
- Configure-time loops use cmake-pack's `Yc_while` / `Yc_foreach`, not core `while`.

**Why:** keeps yelu-core language-agnostic and composable. cmake-specific control
flow concepts stay in the cmake-pack, not polluting the core language.
