# cmake deref semantics — `foo` vs `${foo}` vs `"${foo}"`

> Empirically resolved against **cmake 4.3.1** (`cmake -P`), in the style of
> [`cache_semantics.md`](cache_semantics.md). Answers: how do the three
> reference forms differ, when are they equivalent, and what should yc do?
> Motivation: yc currently treats `${foo}` and `"${foo}"` as the same
> "string interpolation with a single name reference" — this doc shows that
> is sound only for scalar, non-empty values.

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

**Fix direction (investigated 2026-06-12 — needs a new IR node).** The
distinction collapses at *parse*: `${foo}` (EVAL) and `"${foo}"` (PATH)
both become `EString "${foo}"`, and `EString` emits always-quoted. The
obvious fixes do **not** work:

- map pure `${foo}` → **`EVar`**: `EVar` is a yc *compile-time binding*
  that subst-resolves at emit — `message ${bar}` then emits
  `message(STATUS "")`, **losing the deref**. So `${foo}` ≠ `EVar`.
- **`ECmakeRaw`**: emits `C.Quote` (quoted) — not unquoted.

No existing node represents an *unquoted cmake-runtime deref*. The proper
fix is a **new IR node** (e.g. `EDeref of string`) that emits `${foo}`
**verbatim + unquoted in every position** and **splits on `;` in eval**.
Blast radius: emit (all positions), eval (list-split), the cmake→yc bridge
(`from_emit.unwrap_var_ref` already detects pure `${IDENT}` — it would
build `EDeref` instead of `e_var`), and the byte-oracle goldens. Verify
with a unit test on emitted text (unquoted-in → unquoted-out) + the File-API
behavior oracle (the cache-matrix is blind to it). Medium-sized; pairs with
standing up that oracle.

## Related

- [`cache_semantics.md`](cache_semantics.md) — same empirical methodology.
- [`comparison.md`](comparison.md) — the `;`-list conflation is also noted
  there as a cmake PL property.
- [`../lang/yc_syntax_critique.md`](../lang/yc_syntax_critique.md) — string
  syntax (`'`/`"`) item #3 interacts with the quote distinction here.
