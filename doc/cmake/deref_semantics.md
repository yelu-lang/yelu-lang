# cmake deref semantics — `foo` vs `${foo}` vs `"${foo}"`

> Empirically resolved against **cmake 4.3.1** (`cmake -P`), in the style of
> [`cache_semantics.md`](cache_semantics.md). Answers: how do the three
> reference forms differ, when are they equivalent, and what should yc do?
> Motivation: yc currently treats `${foo}` and `"${foo}"` as the same
> "string interpolation with a single name reference" — this doc shows that
> is sound only for scalar, non-empty values.

> **Terminology.** "deref" is loose shorthand here. `${foo}` is *not* a
> dereference (no pointer / ref-cell to follow, as OCaml `!foo` / C `*p`);
> cmake has no reference type. It is **variable expansion** — substitute the
> token with the *string value* bound to `foo` (cmake's own term:
> *variable reference*). Bare `foo` is the **literal** `foo` in argument
> position — so cmake *inverts* the usual convention (bare = literal, `${}`
> = read; the opposite of Python/most languages). Nesting `${${foo}}` gives
> *computed-name indirection*, still substitution, not pointer-following.
> Two **orthogonal** axes hide under "deref": *read-vs-literal* (does the
> text contain `${…}`?) and *quoted-vs-unquoted* (does the expansion split
> on `;`?). Only the second is a representation gap — hence the IR node is
> `EUnquoted` (the quoting axis), not `EDeref`.

## Methodology

Two `cmake -P` probes, reported via `message()`. The key subtlety: the
faithful argument count is **`${ARGC}`**, *not* `list(LENGTH ARGN)` —
once args land in `ARGN` cmake re-joins them as a `;`-list, so length
can't distinguish "3 args" from "1 arg containing `;`".

**Probe A — argument position** (a function reports `${ARGC}` and each
`ARGV{i}` wrapped in `<>`):

```cmake
function(report label)
  set(vis "")
  set(i 1)
  while(i LESS ${ARGC})
    set(vis "${vis}<${ARGV${i}}>")
    math(EXPR i "${i} + 1")
  endwhile()
  message("${label}: argc=${ARGC} args=${vis}")  # argc includes the label
endfunction()
# for each foo value: report(bare foo)  report(${foo})  report("${foo}")
```

**Probe B — condition position** (`if(foo)` / `if(${foo})` / `if("${foo}")`).

Both probes are pinned as a reproducible test:
[`test/test_deref_probes.py`](../../test/test_deref_probes.py) — runs them
against the local cmake and asserts the tables below.

## Findings

### Argument position (command args, `:=` values)

| `foo` value | bare `foo` | `${foo}` (unquoted) | `"${foo}"` (quoted) |
| --- | --- | --- | --- |
| `abc` (scalar) | `<foo>` (literal) | `<abc>` | `<abc>` — **same** |
| `a;b;c` (list) | `<foo>` | **3 args** `<a><b><c>` | **1 arg** `<a;b;c>` |
| `` (empty) | `<foo>` | **0 args** (elided) | **1 empty arg** `<>` |
| `;` | `<foo>` | **0 args** | **1 arg** `<;>` |
| `a;` (trailing) | `<foo>` | **1 arg** `<a>` (trailing elided) | **1 arg** `<a;>` |

### Condition position (`if` / `while`)

| `foo` value | `if(foo)` | `if(${foo})` | `if("${foo}")` |
| --- | --- | --- | --- |
| `ON` / `1` | TRUE | TRUE | TRUE |
| `OFF` / `0` / empty | FALSE | FALSE | FALSE |
| `abc` | **TRUE** (var set) | **FALSE** (`abc` not a var/const) | **FALSE** |
| `bar` (→ `ON`) | **TRUE** | **TRUE** (`if(bar)` re-derefs) | **FALSE** (quoted, CMP0054) |

**Typed conditions** (`if(<v> VERSION_LESS …)` / `STREQUAL …`): a scalar
agrees quoted/unquoted, but an **unquoted list** operand is a **parse
error** — it splits into too many operands (`if(1 5 VERSION_LESS 2.0)`),
so a list-valued var *must* be quoted in a typed condition.

## Lattice (argument position)

How the three forms relate, by the cmake arguments they produce — read like
a coercion lattice (the two deref forms *coincide* for a scalar value, and
*diverge* otherwise):

```
                       ${foo}                      "${foo}"
              (list view: 0 .. N args;        (scalar view: always
               splits on ';', drops             exactly 1 arg = the
               empty elements)                   raw value, ';' kept)
                    \                                   /
                     \        foo is SCALAR            /
                      \    (no ';', non-empty)        /
                       \________ ${foo} ≡ "${foo}" __/
                                  (the only collapse)

                                  ▲ diverge below ▲
                 foo = "a;b;c"  : ${foo} → 3 args ⟂ "${foo}" → 1 arg
                 foo = "" / ";" : ${foo} → 0 args ⟂ "${foo}" → 1 arg

      bare  foo  :  the literal text "foo" — NOT in this lattice in
                    argument position. It enters only inside if()/while(),
                    where cmake auto-dereferences it (→ rule 3 below).
```

Mnemonic: `"${foo}"` is the *value*; `${foo}` is the *value spread as a
list*. Equal exactly when the list has one non-empty element.

## Equivalence rules

1. **bare `foo` is the literal `foo`** in argument position — *never* a
   deref. It only dereferences in `if`/`while` (cmake's auto-deref
   footgun). So `foo` and `${foo}` are unrelated in argument position.
2. **`${foo}` ≡ `"${foo}"` ⇔ the value has no `;` and is non-empty.**
   Otherwise they differ in:
   - **arity** — unquoted `${foo}` splits on `;` (→ N args); quoted is one arg;
   - **empty-elision** — unquoted empty/all-`;` contributes 0 args; quoted
     contributes one (possibly empty) arg; unquoted drops trailing/empty
     list elements, quoted preserves them.
3. **In conditions** all three agree only for canonical booleans
   (`ON/OFF/1/0`) and empty. For any other value: `if(foo)` tests "is the
   variable set & truthy", `if(${foo})` tests the *value* as a condition
   (which may re-dereference), `if("${foo}")` tests the value as a literal
   string (true only for a true-constant).

## Implications for yc + proposed rules / warnings

yc makes the deref **explicit** (`${X}` vs name `X`), which already avoids
the `if()` auto-deref footgun (rule 3) — a real correctness win, keep it.
The open issue is rule 2: yc collapsing `${foo}` and `"${foo}"`.

**Proposed (not yet implemented):**

- **R1 — scalar equivalence.** Treat `${foo}` ≡ `"${foo}"` *only* when foo
  is provably scalar (literal scalar value, or a var known non-list and
  non-empty). This is a normalization the formatter could apply safely.
- **R2 — list/empty divergence is significant.** When foo may be a list or
  empty, the two forms are **not** interchangeable. yc must preserve the
  quote on emit (it changes cmake arity). If yc currently emits one form
  for both, that is an **unsoundness** for list/empty-valued variables —
  flag and fix.
- **W1 — wellformedness warning.** In a *single-value* slot (e.g. the RHS
  of a scalar `:=`, a docstring, a single-path arg), warn on unquoted
  `${foo}` where foo may be a list: "unquoted `${foo}` splits on `;`; did
  you mean `"${foo}"`?" Symmetrically, warn on `"${foo}"` in a *list* slot
  if a list was intended.
- **W2 — bare-name-in-condition warning.** A bare name where a condition is
  expected would auto-deref in cmake; yc's grammar already forces explicit
  operators/`${}`, so this is mostly structural — keep enforcing it.

**Confirmed gap (2026-06-12).** yc does **not** preserve the distinction —
it emits *both* forms **quoted**:

```
FOO := ${bar}                        => set(FOO "${bar}" )
FOO := "${bar}"                      => set(FOO "${bar}" )
compile_opts fmt :PRIVATE ${flags}   => target_compile_options(fmt PRIVATE "${flags}")
compile_opts fmt :PRIVATE "${flags}" => target_compile_options(fmt PRIVATE "${flags}")
```

So yc always uses the quoted "one arg, no split" semantics. For a
**list-valued variable written unquoted** (e.g. fmt's
`${PEDANTIC_COMPILE_FLAGS}`), the author expects splitting (`-Wall -Wextra
…`) but yc emits `"-Wall;-Wextra;…"` (one literal arg) — wrong cmake.

**Why the matrix is blind to it:** `target_compile_options` is a *target
property*, not a cache entry — a **cache-invisible** effect (fmt flags
`FMT_PEDANTIC` as exactly that). The 24/24 cache-matrix can't see it; the
deferred **behavior-level oracle (File API codemodel-v2)** would. So this
is a real latent unsoundness, currently masked.

## Root cause + implementation plan (bring the quoted-bit back)

**Root cause — an AST flaw, not cmake's dynamics.** cmake keeps a
quoted-vs-unquoted bit on every argument; yc's *production* IR
(`Yelu_cmake.expr`) dropped it — `EString of string` is always-quoted, and
both `${foo}` (EVAL) and `"${foo}"` (PATH) collapse to it at parse. The bit
*exists* one layer out: the **CST** distinguishes `A_eval` / `A_path` /
`A_string`, and the legacy typed AST had `yc_string = Ycs_eval | Ycs_path |
…`. So `lower_atom` (CST→expr) is exactly where it's lost. The fix restores
fidelity yc had, not something beyond cmake.

**Combination coverage.** Only the **quoted/unquoted** axis is a
representation gap; the others are runtime (value shape, conf/run-time —
relaxed), structural (arg vs if — already in emit), or inferable from slot
typing (a typed target slot fixes arity). Ground truth is pinned in
[`test/test_deref_probes.py`](../../test/test_deref_probes.py).

**Representation: a sibling constructor `EUnquoted of string`** (the
"quoted=false" companion of `EString`). It holds the **verbatim** text and
emits it **unquoted** — it does *not* subst-resolve (that's what sank the
`EVar` route: `EVar` is a compile-time binding → `message ${bar}` →
`message(STATUS "")`). A flag on `EString` is cleaner in theory but
`EString of string` is pattern-matched in too many places to re-arity; a
sibling constructor is the minimal encoding of the bit.

**Layer-by-layer changes:**

| layer | change |
| --- | --- |
| `yelu_cmake.ml` (expr) | add `EUnquoted of string` |
| `yc_cst_lower.lower_atom` | `A_eval s` → `EUnquoted s` (was `EString`); `A_path`/`A_string` → `EString` (quoted); `$<…>` → `ECmakeGenex` (unchanged) |
| `yelu_parse.p_expr_y1` | `EVAL s` (non-genex) → `EUnquoted s` (was `EString`) |
| `yelu_cmake_emit` | `EUnquoted s` → `C.Bare s` (unquoted) in **every** position arm (arg / cond / value); `EString` stays quoted |
| `yelu_cmake_eval` | `EUnquoted` evals like `EString` (substitute the text); **list-splitting deferred** (the relaxed axis) — note it |
| `yelu_cmake_from_emit.arg_to_expr` | use the cmake arg's quote: `C.Bare` deref → `EUnquoted`, `C.Quoted` → `EString` (this is where the bit comes *from* cmake; today it goes through `unwrap_var_ref → e_var`) |
| byte-oracle goldens | review/regen cases where an unquoted-source deref flips `"${X}"` → `${X}` |
| CST / printer | unchanged (already carry the distinction) |

**Verification:** emit-text unit test (`EUnquoted`→unquoted, `EString`→quoted);
emit-bridge stays green (change legacy + CST together); byte-oracle goldens
reviewed; fmt matrix 24/24 (scalar-safe); the cmake probes as ground truth.
Full list-splitting-reaches-the-build verification → the deferred File-API
behavior oracle (the cache-matrix is blind to it — this is its first
client).

## Related

- [`cache_semantics.md`](cache_semantics.md) — same empirical methodology.
- [`comparison.md`](comparison.md) — the `;`-list conflation is also noted
  there as a cmake PL property.
- [`../lang/yc_syntax_critique.md`](../lang/yc_syntax_critique.md) — string
  syntax (`'`/`"`) item #3 interacts with the quote distinction here.
