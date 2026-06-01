# yelu_cmake vs yelu_cmake_normal — ecosystem comparison

A side-by-side snapshot of the two surface languages defined under
`src/langs/yelu/`. Built so you don't have to grep the fragment
directory to find out whether (e.g.) `yelu_cmake_normal` has a
parser yet.

Durable concept lives in [`design.md`](design.md); code map lives
in [`structure.md`](structure.md). This doc is the *comparison*
between the two languages — what each has, what each is missing,
and where the asymmetry comes from.

## 1. What they are

- **`yelu_cmake`** — cmake-faithful surface. One `ECmake*`
  constructor per cmake-command shape. 14 theory fragments under
  `fragments/yelu_cmake_<theory>.ml`. Mirrors the real cmake
  surface so a user reading `yelu_cmake` IR sees recognizable
  cmake-shaped calls.
- **`yelu_cmake_normal`** (ycn for short — the full name is
  unwieldy) — normalized form. 16 fragments under
  `fragments/yelu_cmake_normal_<theory>.ml`. Same 14 cmake-side
  theories *plus* `bool` and `int` as explicit theory primitives.
  Cmake-shape sugar is factored out — mutations are explicit via
  `ESetVar`; no output-var convention; subcommand zoos
  decompose into primitive operations.

Both share a single extensible-variant core (`type expr = ..` in
`yelu_cmake.ml`), then each fragment adds its own constructors
into that universe. Strictly speaking the two are subsets of the
same OCaml type — the distinction is conventional, enforced by
which fragments a translation walks.

## 2. Ecosystem tool matrix

| tool                    | yelu_cmake                                                | yelu_cmake_normal                                       |
| ----------------------- | --------------------------------------------------------- | ------------------------------------------------------- |
| concrete-syntax parser  | ✅ `yelu_parse.ml` + `yelu_lexer.ml`                       | ❌ none                                                  |
| pretty printer (text)   | ✅ via emit → `Lang_cmake_pp`                              | ❌ none                                                  |
| debug text emit         | ✅ `yelu_cmake_emit_debug.ml`                              | ❌ none                                                  |
| evaluator               | ✅ `yelu_cmake_eval.ml` + 14 fragment `eval_case`          | ✅ `yelu_cmake_normal_eval.ml` + 16 fragment `eval_case` |
| emit → `Lang_cmake.exp` | ✅ `yelu_cmake_emit.ml` (production)                       | ❌ none direct — goes via `from_normal` first            |
| convert → other         | ✅ `to_normal` (in `yelu_cmake_convert.ml`)                | ✅ `from_normal` (same file)                             |
| central ergonomic ctors | ✅ `yelu_cmake_utils.ml`                                   | ❌ none (per-fragment only)                              |
| tests                   | parser/lexer/compile/check/bridge/emit/steps (~580 cases) | `test_yelu_lift_lower.ml` (75 cases)                    |

The hard asymmetry: **ycn has neither a parser nor a text emit
path.** It's an internal IR — constructed only via OCaml ctors or
`to_normal`, evaluated, then converted back via `from_normal`
before reaching cmake text. That's intentional, but worth
naming.

## 3. Per-fragment constructor counts

Compression ratio shows why ycn isn't a renaming — it factors out
cmake-shape sugar into primitive theories. Counts via
`grep -cE "^[[:space:]]+\| E[A-Z]"` over each fragment file
(2026-05-31):

| theory    | yelu_cmake | yelu_cmake_normal |      ratio |
| --------- | ---------: | ----------------: | ---------: |
| target    |         38 |                34 |       0.89 |
| install   |         12 |                12 |       1.00 |
| if        |          2 |                 2 |       1.00 |
| test      |          4 |                 4 |       1.00 |
| try       |          6 |                 2 |       0.33 |
| dir       |         11 |                 2 |       0.18 |
| find      |         10 |                 2 |       0.20 |
| property  |         21 |                 8 |       0.38 |
| list      |         31 |                 8 |       0.26 |
| file      |         33 |                 8 |       0.24 |
| store     |         23 |                 4 |       0.17 |
| cmake_op  |         53 |                14 |       0.26 |
| string    |         65 |                12 |       0.18 |
| path      |         44 |                 4 |       0.09 |
| **bool**  |          — |                 6 | (ycn-only) |
| **int**   |          — |                12 | (ycn-only) |
| **total** |    **353** |           **134** |   **0.38** |

Reading: cmake's `string(...)` family has 65 distinct ctors
(every `REGEX`/`SUBSTRING`/`TOUPPER`/`TIMESTAMP`/`COMPARE` is its
own shape). The normal form lowers them to 12 primitive
string operations + `ESetVar` for the output. Same pattern at
`path` (44 → 4) and `store` (23 → 4) — almost an order of
magnitude in some theories.

`bool` and `int` are ycn-only because the cmake surface folds
them into command sugar: `option(var help ON)` doesn't carry a
separate `EBool true` constructor in cmake-shape, but ycn
makes the boolean explicit.

## 4. Tests

`test/test-yelu/test_yelu_lift_lower.ml` is the only test file
that exercises ycn directly. 75 cases. The file name retains
pre-rename "lift_lower" vocab (see
[`yelu_cmake_convert.ml:22-23`](../../src/langs/yelu/yelu_cmake_convert.ml#L22)
for explicit debt acknowledgement). Each case exercises both:

- **Convert roundtrip** — `from_normal ∘ to_normal` preserves
  observable cmake emission.
- **Eval equivalence** — running the ycn evaluator on the
  `to_normal` result produces the same value/env as the
  yelu_cmake evaluator on the original.

No other test file touches ycn. If a future refactor breaks ycn,
only `lift_lower` will catch it.

## 5. Gaps on the ycn side

In priority order — none of these block current work, all become
load-bearing once Y17 / the behavior-level oracle lands.

1. **Direct ycn → cmake-text emit.** Today: ycn → `from_normal`
   → yelu_cmake → `yelu_cmake_emit` → `Lang_cmake.exp` →
   `Lang_cmake_pp`. A direct path lets optimizer passes write
   to ycn and skip the back-conversion. ~14 small per-fragment
   emit modules. Pairs with post-retirement cleanup item #3
   (distribute emit per-fragment instead of central registry).
2. **Central ergonomic ctors** (`yelu_cmake_normal_utils.ml`).
   Cmake side has `yelu_cmake_utils.ml` for clean
   `Yelu_cmake_utils.yc_set_var ~name ~value` style; ycn
   callers spell out `Yelu_cmake_normal_store.ESetVar { … }`
   directly. Cosmetic but reduces test noise.
3. **A debug pretty printer** for ycn. When a `lift_lower` test
   fails the diff is OCaml `%sexp_of` dumps. A small
   `Yelu_cmake_normal_pp` would aid debugging without committing
   to a surface syntax.
4. **Concrete syntax / parser.** No current user writes ycn
   directly — programs are written in cmake-shape yelu and
   reach ycn via `to_normal`. If ycn ever becomes a
   user-facing language (e.g. for staged macros), this is
   needed. Not on any current critical path.

## 6. Where ycn becomes load-bearing

ycn is currently a clean substrate waiting for the passes that
will operate on it:

- **Y17 — types on yelu_cmake.** Namespace separation, explicit
  `ESetVar`, and the smaller surface area make typing rules
  easier to state on ycn than on cmake-shape sugar. See
  [`status.md`](status.md) "Y17 — types on yelu_cmake".
- **Behavior-level oracle / "prove optimized ≡ original".**
  Optimization passes rewrite ycn; the from_normal → emit →
  cmake configure → File API JSON chain is the verification
  harness. See [`status.md`](status.md) "Behavior-level oracle".
- **Y15 — binding feature library.** ycn's explicit `ESetVar`
  vs `ELet` makes it the natural substrate for exploring
  lexical / global, immutable / mutable, expression / statement
  binding axes per pack.

## 7. Naming history

The two languages were originally called `Yelu1` (cmake-shape)
and `Yelu2` (normal). Commit `ad6deb8` (2026-05) renamed them
in source and most docs to `yelu_cmake` / `yelu_cmake_normal`.
Residual debt:

- `test/test-yelu/test_yelu_lift_lower.ml` — file name retains
  pre-rename "lift_lower" vocab.
- A few `CLAUDE.md` and worklog references survive in
  historical sections (worklog is intentional — chronological
  record).

If brevity matters in conversation, **ycn** is a working
shorthand for `yelu_cmake_normal`.
