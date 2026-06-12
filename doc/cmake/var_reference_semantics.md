# cmake variable references — `foo` vs `${foo}` vs `"${foo}"`

> Empirically resolved against **cmake 4.3.1** (`cmake -P`), in the style of
> [`cache_semantics.md`](cache_semantics.md). Answers: how do the three
> reference forms differ, when are they equivalent, and what should yc do?
> Motivation: yc currently treats `${foo}` and `"${foo}"` as the same
> "string interpolation with a single name reference" — this doc shows that
> is sound only for scalar, non-empty values.

## Model — `$` is expansion, `"…"` is quote, and quoting is compositional

"deref" is the wrong word; the precise model has two **primitive operations**
and one **wrapper**, and they compose.

- **`$` — variable expansion**, a map `name (bare string) → value`. This shape
  is rare in ordinary languages: there, a bare identifier *is* the lookup.
  cmake inverts it — **bare `foo` is the literal string `"foo"`**, and you
  must write `$` to read. Two ways to read `$`: (a) *metaprogramming* — the
  name is data, and a computed name can be looked up (`${${foo}}` is "look up
  the variable whose name is the value of `foo`"); (b) an **explicit global
  dict** `string → value` with `$` as its lookup operator. cmake is (b) at
  runtime with the (a) flavor that the key may itself be computed. It is *not*
  a dereference — there is no ref cell to follow (cf. OCaml `!foo`, C `*p`).
- **`"…"` — quote / string construction**: turn text into one string value,
  *keeping `;` literal* (so the result is one argument, never split).
- **String interpolation is compositional, not a primitive.** `"${foo}"` is
  **not** a standalone form to case on — it is `quote(interpolate(…))`, and
  the interpolation can hold *any* number of expansions and literal text:
  `"${foo} -- ${bar}"`. So the IR must store the *content* as interpolated
  text and treat **quoting as a separate wrapper**, never match the exact
  shape `${IDENT}` as a unit (that "primitive" reading can't represent
  `"${foo} -- ${bar}"`, and it is the trap yc fell into — see below).

So the three surface forms decompose as: bare `foo` = literal text; `${foo}`
= *unquoted* interpolated text (splits on `;`); `"${foo}"` = *quoted*
interpolated text (one arg). The only thing the production IR dropped is the
**quoted/unquoted wrapper bit** — the interpolated content was always carried
as a string. (The first sketch added an `EUnquoted` sibling for exactly this
bit; the implemented design instead makes `$` first-class as `EVarLookup` and
lets quoting fall out — see the plan below. Either way the axis being restored
is *quoting*, not a `${IDENT}` primitive.)

### Nesting is asymmetric — `$` nests, quote is outermost-only

The construction space is **not** a free `{$, quote}^n` product (probe-pinned
in `test_deref_probes.py`):

- **`$` nests freely inside `$`** (computed name): `${${foo}}`, `${${${a}}}`
  all resolve (3-layer → `HELLO`).
- **quote wraps only the outermost argument**: `"${${foo}}"` is fine.
- **a quote *inside* `${…}` is a cmake parse error** — `${"${foo}"}` /
  `if(${"${foo}"})` → *Invalid character (`"`) in a variable name*. A variable
  name may contain text and nested `${…}` but never a `"`.

```
varref  ::= "${" name "}"      name ::= ( char | varref )*     ← no quotes
quoted  ::= "\"" ( char | varref )* "\""                       ← quote outside only
```

**IR consequence:** `EVarLookup of expr` is *looser* than cmake. Restricted to
valid source, the operand can only be the name text (`EString`) or a nested
`EVarLookup` — **never a quoted `EString`**. The extra slack in the type is
unreachable from a parser, not a representable cmake construction.

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

## Status of `$` in the IR today (2026-06-12)

`$` is **not** first-class. A cmake `${foo}` is represented two ways, neither
an expansion operator:

- **`EVar of string`** ([`yelu_cmake.ml:874`](../../src/langs/yelu/yelu_cmake.ml#L874))
  is yc's *compile-time* `let`/`function` binding, **overloaded** to also mean
  "cmake deref": an unresolved metavar emits `${name}`
  ([`emit:62`](../../src/langs/yelu/yelu_cmake_emit.ml#L62)). Operand is a bare
  `string`, so it *cannot* express `${${x}}`; it eval-resolves through the
  *binding* env, not the cmake var env — which is exactly why
  `${foo}`→`EVar` blew up `message ${bar}` (runtime expansion run through the
  compile-time namespace).
- **`EString "${foo}"`** — a verbatim blob (what the parser/CST actually
  produce: `A_eval s → EString s`); eval calls `substitute`, emit quotes it
  because it contains `${`.

`EVar` is doing **three** jobs at once — let-binding, bare identifier
(`PUBLIC`), and cmake deref. `from_emit` then collapses both `${x}` forms
back to `e_var`, losing the quote. The fix is to give `$` its own node and
let `EVar` go back to meaning only "yc binding".

## Plan — make `$` first-class as `EVarLookup of expr`

> **Implemented (2026-06-12).** `EVarLookup of expr` shipped across all layers
> below. Author intent is now preserved: unquoted `${X}` emits `${X}`
> (splits), quoted `"${X}"` emits `"${X}"`. Verified: 655 unit tests, fmt
> matrix **24/24** (real cmake), v1 structural checks, deref probes.
> Two follow-ons the change forced:
> - **Consumer audit.** Introducing the node silently broke `| _ -> default`
>   catch-alls that read name/keyword slots (cache-type, target visibility,
>   property names). Fixed by routing them through `str_of`, which now also
>   handles `EVarLookup` (and `ETarget`). The compiler can't flag these —
>   the fmt matrix did. This is the cost of a non-exhaustive open variant.
> - **Latent printer bug surfaced.** `install(EXPORT … DESTINATION ${d}NAMESPACE …)`
>   — the cmake pretty-printer glued the destination to the next keyword
>   (`%a%a`). The closing `"` of the old `"${d}"` had masked it; unquoted, the
>   keyword got swallowed → configure error. Fixed the separator in the
>   `Install_export` / `Install_directory` printers (this also recovered a
>   previously-failing v2 structural case).

**Root cause — a missing operation, not cmake's dynamics.** cmake's `$` is a
primitive `name → value` lookup; yc never had a node for it, so it leaked
into `EVar` (the binding) and `EString` (a blob). The fix adds the operation.

**`EVarLookup of expr`** — the `$` operator. The operand is an **expr**
(not a string) precisely so the *computed-name* case composes:
`${${inner}}` → `EVarLookup (EVarLookup (EString "inner"))` (cmake resolves
it — probe-confirmed `HELLO`). Naming: `EVarLookup` over `EDeref` (not a
deref) / `EExpand` (fine too); it *is* a keyed-dict lookup.

**Quoting falls out, no separate node needed.** Per the model above, quote =
to-string. So:

| surface | IR | emits | splits? |
| --- | --- | --- | --- |
| `${foo}` (unquoted) | `EVarLookup (EString "foo")` | `${foo}` bare | yes |
| `"${foo}"` (quoted) | `EString "${foo}"` (a *string value*) | `"${foo}"` | no |
| `${${x}}` | nested `EVarLookup` | `${${x}}` bare | yes |

`EVarLookup` is the unquoted/list form (the one with interesting semantics);
the quoted form is "just a string", so `EString` already models it. No
`EUnquoted`, no `EQuoted`. (This supersedes the earlier `EUnquoted`-blob
sketch — first-class `$` is the cleaner cut the discussion converged on.)

**Deferred corner — mixed unquoted text.** `pre${l}post` with a list value
fuses at the boundary *then* splits (`<prea><b><cpost>`, probe-confirmed) —
that needs the surrounding literal text, i.e. *structured* interpolation,
which first-class `$` deliberately does **not** add. Until then mixed
unquoted stays an `EString` blob (emitted quoted = a known minor unsoundness,
same class as the other deferred `from_emit` corners). Pure `${foo}` — the
common, important case (fmt's `${PEDANTIC_COMPILE_FLAGS}`) — is covered.

**Layer-by-layer changes:**

| layer | change |
| --- | --- |
| `yelu_cmake.ml` (expr) | add `EVarLookup of expr` |
| `yc_cst_lower.lower_atom` | `A_eval s`: if pure `${…}` (no surrounding text), parse to `EVarLookup` (nested for `${${…}}`); `$<…>` → `ECmakeGenex` (unchanged); mixed → `EString` (deferred). `A_path`/`A_string` → `EString` (quoted, unchanged) |
| `yelu_parse.p_expr_y1` | same: `EVAL s` pure → `EVarLookup`, mixed → `EString` |
| `yelu_cmake_emit` | `EVarLookup e` → `C.Bare ("${" ^ render e ^ "}")` (unquoted) in arg; cond/target render `${…}` per existing convention; `EString` unchanged (quoted) |
| `yelu_cmake_eval` | `EVarLookup e`: eval `e` to a name, `find_var`; undefined → `""`; **list-splitting deferred** (relaxed axis) — note it |
| `yelu_cmake_from_emit.arg_to_expr` | `C.Bare "${X}"` → `EVarLookup`; `C.Quoted "${X}"` → `EString` (preserve the quote). Retire `unwrap_var_ref → e_var` (the primitive trap: conflates expansion with the binding namespace) |
| `yelu_cmake_utils` | `yvar`/`ycstr` (`= EVar`) and the `EVar n → EString n` demotion: audit so cmake reads route to `EVarLookup`, leaving `EVar` for genuine bindings only |
| byte-oracle goldens | review/regen cases where an unquoted-source `$` flips `"${X}"` → `${X}` |
| CST / printer | unchanged (already carries the `A_eval`/`A_string` distinction) |

**Coverage test additions** (`test/test_deref_probes.py`, cmake ground
truth): a *structure* probe set beyond the value-shape matrix — **nested**
`${${inner}}` (computed-name resolves) and **mixed** `pre${l}post` (boundary
fuse + split, 3 args, vs quoted = 1). These pin what `EVarLookup` must honor
and why mixed-unquoted is deferred.

**Verification:** emit-text unit test (`EVarLookup`→unquoted `${X}`,
`EString`→quoted); emit-bridge stays green (change legacy + CST together);
byte-oracle goldens reviewed; fmt matrix 24/24 (scalar-safe); the cmake
probes as ground truth. Full list-splitting-reaches-the-build verification →
the deferred File-API behavior oracle (the cache-matrix is blind to it — this
is its first client).

## Related

- [`cache_semantics.md`](cache_semantics.md) — same empirical methodology.
- [`comparison.md`](comparison.md) — the `;`-list conflation is also noted
  there as a cmake PL property.
- [`../lang/yc_syntax_critique.md`](../lang/yc_syntax_critique.md) — string
  syntax (`'`/`"`) item #3 interacts with the quote distinction here.
