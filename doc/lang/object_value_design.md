# Y18 — First-class object value (cmake entity)

> Status: design TODO, no implementation. Captured 2026-06-14 after the
> Pos3 prototype landed (`yelu_parse.ml`'s parser-local `cmake_entity` +
> `p_cmake_entity` group, wired into `set_property` scope dispatch). The
> Pos3 work was deliberately narrow — a typed value scoped to the parser
> — so this doc collects the questions a real value class needs to answer
> before we promote.

## Today (Pos3 prototype, 2026-06-13/14)

Parser-local typed value in [`src/langs/yelu/yelu_parse.ml`](../../src/langs/yelu/yelu_parse.ml):

```ocaml
type cmake_entity =
  | Ent_target of expr
  | Ent_source of expr
  | Ent_cache of expr
  | Ent_test of expr
  | Ent_install of expr
  | Ent_directory of expr option
  | Ent_global
```

Reader: `p_cmake_entity : expr list -> (cmake_entity * expr list) option`
recognizes `Target foo` / `Source 'main.c'` / `Cache FOO` / etc. at the
front of an argument list. Lowering: `entity_to_sps` translates to the
matching `Yelu_cmake_property.set_property_scope` variant. Only consumer
today: `set_property`. The entity is not an `expr`; it does not flow
through let-bindings, function args, or other value-carrying contexts.

The prototype proves the surface ergonomics. The value-class promotion
is a separate decision the questions below have to settle.

## Open design questions

### a. Operations — what can you do with an object?

Possible operations per entity-kind (cmake-grounded):

| Kind      | Operations                                                                 |
| --------- | -------------------------------------------------------------------------- |
| Target    | `set_property`, `get_property`, `set_target_properties`, `add_dependencies`, `link_lib`, `target_*` (sources/include/compile/link), `install_targets`, `add_test` |
| Source    | `set_property` (compile flags), `set_source_files_properties`, `target_sources` |
| Cache     | `set_property`, `get_property`, `set_target_properties` (limited), `unset` |
| Test      | `set_property`, `get_property`, `set_test_properties`, `enable_testing`    |
| Install   | `set_property` (rarely used)                                               |
| Directory | `set_property`, `get_property`, `add_subdirectory`, `add_compile_*`        |
| Global    | `set_property`, `get_property`                                             |

Two surface forms to choose between:

**Function-form** (today): `set_property Target foo ~property=[…]`.
Uniform with the rest of yc. Currently shipping.

**Object-method form**: `target_foo.set_property(~property=[…])`. The
user flagged this as the long-term direction. Open sub-questions:

- Is `.` an arity-extension of the function call (`x.f y` ≡ `f x y`),
  or a member access (`x.f` looks up `f` in `x`)? The first is far
  cheaper to implement and is the standard "Uniform Function Call
  Syntax" trick (D, Nim, Rust's method calls, Crystal). It also reads
  consistently with cmake calls (`set_property(target_foo …)` already).
- If `x.f y` ≡ `f x y`, then **any** `f` that takes an entity-typed
  arg in its first position is callable via `.`. Cheap, uniform, no
  per-kind method tables.

### b. Value flow — let-bind, args, iterands

Can you write:

```
let t = Target foo in
t.set_property(~property=[ LINK_LIBRARIES 'bar' ]);
t.add_dependencies(other_target)
```

Pros: makes "this thing is a target, do several operations on it"
expressible without re-naming `foo` everywhere. Mirrors how a build
script would actually use such an abstraction.

What's needed:

- Entity becomes an `expr` (extensible-variant addition in yc fragments).
- `let` accepts it as a binding payload (already does; expressions are
  the universal payload).
- `function` / `fun` params accept the type (already do).
- `foreach` iterand — would need a `foreach t in [Target a, Target b]`
  surface, which requires the list-of-entities case (see (f) below).

### c. Eval semantics — when does `Target foo` reduce?

cmake targets are configure-time entities. `Target foo` written before
`foo` is declared is a forward reference. Options:

- **Lazy**: `Target foo` is a thunk; only resolved when an operation on
  it is performed. Matches cmake's actual behavior (you can `link_lib
  Target foo` before `add_exe foo … `; cmake resolves at generate time).
  Simplest semantically.
- **Eager with declaration check**: at the binding site, verify `foo` is
  a declared target. Closer to a typed value. But cmake's
  forward-reference idiom makes this too strict.
- **Two flavors**: `Target foo` (asserted) vs `?Target foo` (optional /
  may-not-exist) — explicit forward-ref form.

Likely answer: lazy by default; wellform pass (current name-binding
work) catches the never-declared case. Same discipline as today's `Y9`
wellform check, just lifted from "string-name-references-string-name"
to "entity-references-entity".

### d. Wellform integration

Today the wellform pass walks the whole program collecting target/cvar
declarations and references. With entities as a typed value:

- Declarations are kind-tagged at construction (`add_exe foo` declares
  `Target foo`; `cache FOO := …` declares `Cache FOO`).
- References are kind-tagged at the use site (the entity ctor records
  the kind).
- Cross-theory references stop being a one-off cross-pass — every
  reference is already a kinded entity.

This subsumes most of [`Y9` (cross-theory name binding)](../yelu_cmake/structure.md)
and makes the [`Y14` reserved-word check](casing_design.md#reserved-word-shadowing--hard-reject-y14)
trivial (Y14 already shipped at the constructor level; entities are the
runtime parallel).

### e. yc vs ycn — where does the value class live

- **yc surface**: leading-cap constructor (today). Pos2 / Pos3 already
  in place via `Yelu_lexer.constr_names`.
- **yc IR**: depends. The Pos3 prototype is parser-local. Promoting to
  yc IR makes entities flow as `expr`. Costs a new fragment (a fresh
  `expr +=` ctor); pays back when ≥2 commands use it (get_property is
  the second, install/test families are the third).
- **ycn**: this is where the value class earns its keep at the type
  level. yc is cmake-faithful; ycn is the idealized algebra. A typed
  `Entity { kind; name }` lets ycn passes reason about identity without
  re-discriminating per command, and is the natural foundation for
  later analyses (alias detection, dependency closure, install-set
  reachability).

Likely answer: **yc surface** (already done via Pos2), **yc IR** (when
the second command lands — i.e. now, with get_property), **ycn typed
value** (when ycn gets concrete syntax / typed analyses).

### f. Multi-entity calls

cmake allows `set_property(TARGET t1 t2 t3 …)`. Two representations:

- **List-of-entities**: `[Target t1; Target t2; Target t3]` — but the
  list is homogeneous-in-kind here (all targets), so the kind is
  redundant per element.
- **Single multi-name entity**: `Target [t1; t2; t3]` — kind once,
  names as a list. Closer to cmake's actual shape.

Today the Pos3 prototype picks single-name entities and folds extra
positionals from the body head as same-kind extras (cf.
`entity_to_sps` collapsing `e :: head` into `Sps_target (e :: head)`).
That works but is implicit — the user can't *write* `Target [t1, t2]`.

Likely answer: support both shapes — `Target foo` (single) and
`Target [a, b, c]` (list). The IR uses a single-or-list-of-names
representation. Surface dispatches.

### g. The entity vs the name

`${foo}` is the cmake variable read producing the string `"foo"` (or
whatever `${foo}` resolves to). `Target foo` is the typed reference to
*the target named foo*. They coexist:

- `link_lib Target ${name}` — variable resolution, then target lookup
- `link_lib Target foo` — direct target lookup
- `link_lib ${foo}` — fall-through to cmake's stringly-typed name path

Question: should `Target foo` and `Target ${foo}` be distinct? cmake
treats both as "the target named (whatever foo resolves to)" — no
difference at configure time. yc could either flatten (always-deref the
name) or preserve the literal-vs-deref distinction. Today the entity
just carries an `expr` as the name; both flow.

## Adjacent tracks

- **Object-method `.` syntax** — pure surface; UFCS desugar; no IR
  change. Cheap once we want it.
- **Record literal `{k=v, …}`** — separate parking lot (Lane shape-3
  in [yc_syntax_critique.md](yc_syntax_critique.md)). Records and
  entities will compose for things like
  `Target foo.properties = {COMPILE_FLAGS='-O2', LINK_LIBRARIES=['fmt']}`.
- **Lifetime / scope of entities** — when does `Target foo` go out of
  scope? cmake's answer is "configure-time global, lasts forever".
  ycn might want narrower lifetimes for hypothetical analyses.

## Decisions to make in order

1. Should entities flow as `expr` in yc IR? (yes if get_property uses
   them; we're about to find out)
2. Do we adopt UFCS `x.f y` ≡ `f x y` for the future object-method
   surface? (cheap; can wait until first user)
3. Single-name vs list-name representation — pick one (probably
   list-with-singleton-shorthand).
4. Forward-reference semantics — lazy (probably) with wellform catch.
5. Promote `cmake_entity` to a yc fragment — when, and what fragment
   name (`yelu_cmake_entity.ml`?).
