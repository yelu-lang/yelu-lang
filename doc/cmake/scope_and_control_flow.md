# cmake Scope & Control Flow Semantics

> Verified against cmake 4.3.1 with **26 probe scripts** run via `cmake -P`.
> Probes preserved at `/tmp/block_return_probes/p1_*.cmake` … `p26_*.cmake`.
>
> Covers: `block()` / `function()` / `macro()` (variable scope), `return()`
> with `PROPAGATE`, `set(PARENT_SCOPE)`, `break()` / `continue()` (control
> flow), and the cmake-specific hybrid binding model.
>
> Purpose: pin the exact semantic model for tiny's eval *before* writing
> the implementation. The 2026-05-10 foreach incident motivated this
> style: when a construct touches scope, binding, or control flow,
> surface the design (with probe-verified reference behavior) before
> coding. See `.claude/memory/feedback_ask_on_semantic_design.md`.

## TL;DR — the shallow-binding model

Both `block()` and `function()` open a **frame** with its own variable map,
and **frames are snapshot-based**: on entry, the parent's variables are
*copied* into the frame's view. Reads inside the frame consult the local
map first; if not found, fall through to the *snapshot* (not the live
parent).

| Write form | Where it lands | Visible to … |
| --- | --- | --- |
| `set(X v)` inside a frame | Local map | Reads inside the same frame |
| `set(X v PARENT_SCOPE)` | Parent's actual map | Caller, **not** the writing frame's local reads |
| `block(PROPAGATE x …) … endblock` | Parent's actual map (at endblock) | Caller, after block exits |
| `return(PROPAGATE x …)` (CMP0140 NEW) | Caller of function's actual map | Caller, after function returns |

The asymmetry between "writes to parent" and "reads from snapshot" is the
single non-obvious cmake-ism. Without this, you can't explain why
`set(X v PARENT_SCOPE)` followed by `message(${X})` inside the same frame
still reads the snapshot value.

## Decision tree

### Variable read inside a frame `F`

```
${X} inside frame F
├── F's local map has X? ──── YES → return local value
└── NO → return F's snapshot-of-parent value at frame entry
         (snapshot is NEVER updated mid-frame by PARENT_SCOPE/PROPAGATE
          writes from inside F or its children)
```

### Variable write inside a frame `F`

```
set(X v) inside F
├── PARENT_SCOPE flag absent → write v to F's local map
└── PARENT_SCOPE flag present → write v to F.parent's local map
                                F's own snapshot/local for X is unchanged

unset(X) inside F
├── default → remove X from F's local map (parent's value remains)
├── PARENT_SCOPE → remove X from F.parent's local map

block(PROPAGATE x y) … endblock at exit of F
├── For each named var v in {x, y}:
│   ├── F's local map has v defined? ──── YES → write F.local[v] to F.parent.local
│   └── NO (never set / explicitly unset in F)?
│       ├── F's local map shows v as "unset" (P4) → unset v in F.parent
│       └── v never touched in F (P3)            → leave F.parent's v alone

return(PROPAGATE x y) inside function F
├── Unwinds through any enclosing blocks/loops/ifs up to the function boundary
├── For each named var v in {x, y}:
│   ├── Treats the same way as block(PROPAGATE) — value at the return site
│   │   is what gets lifted, or unset is propagated
```

### Control flow: `return()` / `break()` / `continue()` reach upward

```
return()      → unwinds to the enclosing function() frame; if none, exits the script
break()       → unwinds to the enclosing foreach/while loop; error if none
continue()    → unwinds the current loop iteration; error if none
```

`block()` is **not** a return target — `return()` inside a block inside a
function exits the function, not the block (P11). On the unwind path the
block-level PROPAGATE list is **skipped** (P22): only the `return()`'s
own PROPAGATE list takes effect at the function-frame exit.

### `function()` normal-fallthrough (no explicit `return`)

When a function body falls through to `endfunction()` without `return()`:

- No implicit PROPAGATE happens. Any var the function changed *locally*
  is dropped with the frame.
- Vars only leak to the caller via writes that explicitly used
  `set(VAR v PARENT_SCOPE)` *during* the body (P14, P17). Those are
  one-shot writes to the parent's actual map; the function's local
  view never sees them (P15 / P20).

This is the asymmetry to internalize: PARENT_SCOPE is the *only* way
to escape from a function without `return(PROPAGATE …)`. PROPAGATE is
sugar for "do these PARENT_SCOPE writes at the return site."

### `macro()` has no frame at all — textual substitution

Probes P23 and P24 confirm cmake's docs: `macro()` is *not* a frame.
On call, the macro body is conceptually inlined at the call site, with
`${ARG}` / `${ARGN}` etc. being expanded textually.

Concrete consequences:

| Inside macro `M` | Cmake behavior |
| --- | --- |
| `set(X v)` | Writes to the *macro caller's* frame (the textual location of the macro call). |
| `set(X v PARENT_SCOPE)` | Writes to the *parent of the macro caller* (one frame above the textual call site). |
| `return()` | Returns from the *function that called the macro*, not from the macro. |
| Free var read | Resolves in the macro caller's scope (no shadow / snapshot of its own). |

So a macro acts as "inline this body at the call site." `function()` and
`block()` push frames; `macro()` does not. This means tiny's current
`ECmakeMacro` constructor — which just stores the body in `env.functions`
like a function and pushes-binds-evals-restores like F2 — is **incorrect
for true cmake macros**. See "Implications for current `ECmakeMacro`"
below.

## Probe enumeration (verified)

| #   | Probe                              | Question                                          | Result |
| --- | ---------------------------------- | ------------------------------------------------- | ------ |
| P1  | block, set inside, read outside    | Does `set(X v)` in block leak out? | No — `X=outer` after |
| P2  | block(PROPAGATE X)                 | Does PROPAGATE lift named var?     | Yes — X="from-block-X"; Y not propagated; Z never set |
| P3  | PROPAGATE on never-modified var    | Does PROPAGATE clear parent if var never set inside? | No — parent's existing value retained |
| P4  | PROPAGATE + unset(X) inside block  | Does PROPAGATE lift the unset?     | Yes — X becomes undefined in parent |
| P5  | nested block                       | Nesting works as expected?         | Yes — each block restores on exit |
| P6  | inner block PROPAGATE, outer block | Does PROPAGATE lift one frame or all? | One frame — outer block sees inner's PROPAGATE; top doesn't |
| P7  | inner block set(PARENT_SCOPE)      | Where does PARENT_SCOPE land?      | Enclosing block, not top |
| P8  | function + return()                | Does return exit the function?     | Yes |
| P9  | return(PROPAGATE x) (CMP0140 NEW)  | Does PROPAGATE lift x to caller?   | Yes — caller sees "from-function" |
| P10 | return inside foreach inside function | Does return exit function (not just loop)? | Yes — `function fallthrough` not printed |
| P11 | return inside block inside function| Does return exit function (not just block)? | Yes — `after block` not printed |
| P12 | return at script top               | What does return at top level do?  | Exits the script — `after top return` not printed |
| P13 | return(PROPAGATE) inside block inside function | Does PROPAGATE skip the intermediate block frame and lift to caller of function? | Yes — caller sees "from-block-in-function" |
| P14 | set(PARENT_SCOPE) inside function  | Does PARENT_SCOPE write to caller? | Yes; function's local view doesn't see the write |
| P15 | function local-write vs PARENT_SCOPE | Multi-step interaction.           | See below; confirms snapshot semantics |
| P16 | block local-write, read after exit | Block scope is true save/restore? | Yes — parent X restored to "outer-v1" |
| P17 | function, mixed local/PARENT_SCOPE | Confirm no implicit leak           | X local stays parent's; Y via PARENT_SCOPE reaches parent |
| P18 | block(PROPAGATE A B C) with mixed states | Per-var propagation: set / unchanged / unset | A propagates value; B keeps parent; C becomes undefined |
| P19 | chained PROPAGATE block-in-block   | Does PROPAGATE chain?              | Yes when both blocks PROPAGATE the same var — innermost value reaches top |
| P20 | PARENT_SCOPE + later reads in fn   | Does function see its own PARENT_SCOPE writes? | No — snapshot model |
| P21 | block inner PARENT_SCOPE + later reads | Does block see its own PARENT_SCOPE writes? | No — same snapshot model |
| P22 | return(PROPAGATE B) inside block(PROPAGATE A) inside function | Does block's PROPAGATE list run when the block is unwound by return? | No — A stays as parent's outer; only return's PROPAGATE for B reaches the caller |
| P23 | `set(X PARENT_SCOPE)` inside macro, macro called from function | Where does X land? | The function's caller (one frame above the macro's textual call site) — confirms macro = textual substitution |
| P24 | `set(Y)` (no PARENT_SCOPE) inside macro, macro called from function | Does Y leak past the function? | No — Y is written to the function frame and dropped on function exit; macro is frame-less so the function frame is the relevant target |
| P25 | macro params shadow caller's vars; restore behavior on exit | Are params bound as caller-frame vars? Restored after? | Yes to both — param `X` shadows the caller's `X`; restored on exit. Free writes inside the body leak (no frame). |
| P26 | macro `ARGN` / `ARGV` / `ARGC` / `ARGVn` | What are these bound to? | `ARGN` = semicolon-joined extras (args beyond declared params); `ARGV` = all args joined; `ARGC` = arg count; `ARGVn` = the n-th arg. All bound in the caller's frame for the macro's duration and restored on exit. |

### P15 (the snapshot probe)

```cmake
set(X "outer-v1")
function(do_thing)
  message("inside-before: X=${X}")     # outer-v1  ← reads snapshot
  set(X "from-function" PARENT_SCOPE)  # writes to parent
  message("inside-after: X=${X}")      # outer-v1  ← snapshot still
  set(X "local-set")                   # writes to local
  message("inside-local: X=${X}")      # local-set
endfunction()
do_thing()
message("caller: X=${X}")              # from-function
```

Inside-after reading `outer-v1` (not `from-function`) is the load-bearing
observation. The function's view of X is the snapshot-on-entry, *not* a
fallthrough lookup to the live parent. PARENT_SCOPE writes bypass the
local view.

## Proposed model for tiny

### Env shape change

Currently `env.vars : value Map.M(String).t` is a single flat map.
The change required:

```ocaml
type frame = {
  locals : value Map.M(String).t;        (* this frame's own writes *)
  parent_snapshot : value Map.M(String).t; (* copy of parent.locals
                                              ∪ parent.parent_snapshot
                                              taken at frame entry *)
}

type env = {
  ...
  frames : frame list;   (* current frame on top; root frame at bottom *)
}
```

Reads consult `(top frame).locals`, then `(top frame).parent_snapshot`,
in that order — no chain walking.

### Block eval

```text
ECmakeBlock { propagate : string list; body : expr }
  on entry:
    push new frame with parent_snapshot = merge(top.locals, top.parent_snapshot)
                        locals          = empty
  eval body in pushed frame
  on exit:
    pop frame
    for each name in propagate:
      if popped.locals.has(name):
        top.locals[name] := popped.locals[name]
      elif popped.locals shows name as "explicitly unset":
        top.locals.remove(name)
      else:
        leave top alone
```

### Function eval

Same frame mechanic as block. Params are bound as initial locals.
PROPAGATE on return uses the same merge.

### Set with PARENT_SCOPE

```text
ECmakeSetParentScope { name; value }
  if there is no parent frame (we're at the root):
    fail "PARENT_SCOPE at top level" (cmake silently no-ops; we choose to fail to surface bugs)
  else:
    frames.(parent).locals[name] := value
    DO NOT touch the current frame's snapshot or locals
```

### Return eval

`ECmakeReturn { propagate : string list }` raises a new exception
`Return_function { propagate; values }` where `values` is the snapshot of
the propagate names at return site. The exception is caught by the
function-call eval, NOT by block/foreach/while bodies — those re-raise.

```text
ECmakeForeach body / ECmakeWhile body / ECmakeBlock body:
  try eval body
  catch Break_loop / Continue_loop → handle as today
  catch Return_function _ → re-raise (block also re-raises, unwinding)

Function call eval:
  push frame
  try eval body
  catch Return_function { propagate; values } →
    pop frame, apply PROPAGATE merge using values
  pop frame normally on fallthrough
```

Block bodies catch neither Break_loop nor Return_function — they just
re-raise — but `endblock` semantics for PROPAGATE are skipped on the
unwind path (the block frame is destroyed without the PROPAGATE merge).
P13 says return(PROPAGATE x) from inside a block-in-function reaches the
caller, so the unwind must skip the block's own PROPAGATE list and use
the `return`'s propagate set.

## Test plan (must pass before R4-b.3 is closed)

For each probe P1–P21 above, write a tiny-eval test that constructs the
program directly as tiny IR (not through the bridge), runs it via
`eval_yelu1_expr`, and asserts the observable env state matches the
verified cmake output. The test file: `test/test-yelu/test_yelu_tiny_block_return.ml`.

Coverage targets:

- `block()` empty, with body, with PROPAGATE (multi-var, mixed states)
- nested blocks
- `set(PARENT_SCOPE)` inside block (one frame up)
- function + return()
- function + return(PROPAGATE)
- return through foreach/while/block
- return at top level
- function frame snapshot semantics (P15-style: read after PARENT_SCOPE)
- block frame snapshot semantics (P21-style)
- function + PARENT_SCOPE leak check (P17)

Each test exists *because* it would distinguish wrong-model implementations
(e.g. a live-view model would fail P15/P20/P21; a save-and-restore-everything
model with no PROPAGATE would fail P2/P9; an "exit innermost" return would
fail P10/P11).

## Resolved decisions (formerly open questions)

1. **`set(X v PARENT_SCOPE)` at the root frame: dedicated tiny-only error.**
   cmake silently no-ops. Tiny raises `Eval_error
   "tiny: PARENT_SCOPE at root frame (has no parent); this is a
   tiny-only diagnostic (cmake silently no-ops)"`. Rationale: surface
   accidental top-level uses that would otherwise be invisible bugs;
   the wording makes the strictness divergence explicit so users
   reading the error know it is *not* a faithful cmake error message.

2. **`return(PROPAGATE)` inside an unwinding block: verified by P22.**
   The block's own PROPAGATE list is **skipped** on unwind; only the
   `return`'s PROPAGATE list takes effect at the function-frame exit.
   The proposed model (block / loop bodies re-raise the
   `Return_function` exception unchanged, no PROPAGATE merge on the
   unwind path) matches.

3. **Function fallthrough.** Documented in the "Frame model" section
   above and in the decision tree's frame-exit branch: no implicit
   PROPAGATE; only PARENT_SCOPE writes during execution leak.

4. **`macro()`: verified by P23 / P24.** Macros are textual substitution
   with no frame. Tiny's current `ECmakeMacro` (which behaves like
   a function with save/bind/eval/restore) is incorrect; see next
   section.

### Implementation of `ECmakeMacro` (R4-b.4 — done)

Implemented as save-and-restore for params + ARG vars only, with no
frame push. On apply:

1. Save the caller's prior bindings (if any) for: each param name,
   plus `ARGN`, `ARGV`, `ARGC`, `ARGV0`, `ARGV1`, …
2. Set those names in the caller's frame:
   - param[i] → arg_strings[i] (or `""` if fewer args than params)
   - `ARGN` → semicolon-joined args beyond the declared params
   - `ARGV` → semicolon-joined all args
   - `ARGC` → arg count as a string
   - `ARGVn` → the n-th arg
3. Evaluate the body in the caller's frame (no `push_frame`).
4. Restore the saved bindings (write back, or `remove_var` for names
   that had no prior binding).

Tests live in `test_yelu_tiny_block_return.ml` (P25, P26). Function
bodies remain frame-pushed (`is_macro = false` on `function_decl`);
the macro vs function branching is the only divergence at apply time.

A later cleanup is to consider eliminating macros entirely from the
yelu surface (see `.claude/memory/project_macro_elimination.md`); the
current implementation is faithful, so we have a safe baseline either
way.

## Implementation phasing

1. **R4-b.3a — frame stack refactor.** Replace `env.vars` with a frames
   list. Existing code that reads `env.vars` updates to use a `find_var`
   that walks `locals` then `parent_snapshot`. F2 function eval updates
   to push/pop frames. Reject PARENT_SCOPE-at-root with the tiny-only
   `Eval_error` message specified in resolved-decisions #1.
2. **R4-b.3b — block.** `ECmakeBlock` + bridge from `Yc_block`.
3. **R4-b.3c — PARENT_SCOPE.** Add to `Yvar_set` bridge to produce a
   distinct `ECmakeSetParentScope` rather than the current silent-drop.
4. **R4-b.3d — return + PROPAGATE.** New exception `Return_function`;
   thread the propagate values through the unwind. Block / loop bodies
   re-raise; only function-call eval catches.
5. **R4-b.3e — tests.** Port all 24 probes into `test_yelu_tiny_block_return.ml`.
6. **R4-b.4 (separate) — fix `ECmakeMacro` to be textual.** Independent
   of R4-b.3; can land before or after. Rewrites the macro evaluator
   to substitute params into the body and evaluate in the caller's
   frame, not push a new frame. Updates / removes the function-scoped
   tests that asserted the wrong semantics.

R4-b.3a is the load-bearing change. After it, b/c/d are local additions
that compose cleanly.

## What this enables

- Removes the last 6 entries from `bridge_skip` in test_yelu_compile.
- Closes R4 entirely; 194/194 programs flow through bridge → emit.
- Tiny acquires a faithful cmake variable-scope model, sufficient to
  support typecheck/wellform pass design (R7) without scope being a
  separate question.
- Sets up a non-cmake-specific frame primitive (`Make_frame` functor?)
  that future packs can reuse for lexical-scope languages.

## Design observations — cmake's binding model from a PL angle

> Working notes captured 2026-05-11 while finishing R4-b. Not yet
> integrated into `doc/yelu_lang_design.md`; revisit when discussing
> the binding-feature library (Y15).

### The shape of the frame stack

Each frame holds:

- `locals : value Map.M(String).t` — names this frame has written
- `parent_snapshot : value Map.M(String).t` — copy of the caller's
  visible variables, taken at push time
- `touched : Set.M(String).t` — names this frame has set OR unset
  (needed to distinguish `block(PROPAGATE x)` with x untouched from x
  explicitly unset — see probes P3 / P4)

Read resolution is two-level: `locals` then `parent_snapshot`. **No
chain walking.** This is what makes the frame "shallow" in the EOPL
sense: each frame is a complete, free-standing variable environment.

### Lexical vs dynamic — the curious hybrid

| Mechanism | Lexical scope (Scheme, ML) | Dynamic scope (Tcl, Emacs Lisp pre-25) | cmake (this model) |
|---|---|---|---|
| Parent link points to | **Definition** site's scope | **Call** site's scope | Call site's scope |
| Storage relationship | Shared with parent (closures via captured ref) | Shared with parent (writes visible) | **Copied** at frame push |
| Mid-call mutation of caller visible in callee? | Possible via closure cell | Yes, automatically | **No** — callee reads snapshot |
| Cross-scope writes | Returns + assignments to captured cells | Just `set`; visible up the chain | `PARENT_SCOPE` (special), `PROPAGATE` (at exit) |

cmake picked *call-site parent* (the dynamic-scope choice) but
*copy-at-push* (the lexical-scope choice for stability). Reads inside
a frame are thus lexically stable: the callee can't see the caller's
mid-call mutations. But it cuts the data-sharing channel that
dynamic-scope languages otherwise provide, which is why `PARENT_SCOPE`
and `PROPAGATE` exist as explicit back-doors.

The net effect: cmake gives users a function model that *feels*
lexical (predictable, scoped) but with two ergonomic concessions to
the underlying dynamic shape:

- The "parent" is the caller, not the definition site. So a function
  defined deep inside another function still gets the *current
  caller's* snapshot, not a closure over its definition context.
- `PARENT_SCOPE` writes punch through the cut. Without them, callees
  could only communicate via return values — which cmake doesn't
  have at the language level.

### Why `PARENT_SCOPE` reads "low-level"

In a true dynamic-scope language, you'd write `set X v` and the
caller sees it because the chain shares storage. No special syntax
needed — that's just how variables work. cmake severs the chain via
the snapshot, and then introduces `PARENT_SCOPE` as a labeled
write-through. Compared to dynamic scope's implicit chaining, this is
a verbose, mechanism-revealing primitive. Compared to lexical scope's
return-value channel, it's a side-effect back-door.

That's the source of the "low-level" feel: `PARENT_SCOPE` is a
storage-level instruction (write to *this specific frame*) rather
than a semantic primitive (return a value).

### `block()` as scope without function-call

`block()` is interesting because it's a *non-function* frame: a way
to introduce a fresh scope without packaging it as a callable. C and
its descendants do this with `{ ... }` blocks. cmake's `block()` is
the same idea retrofitted onto a language whose only previous scoping
mechanism was `function()`.

Once you have the frame primitive, having both `function()` (which
binds params and supports `return(PROPAGATE)`) and `block()` (which
binds nothing and supports `block(PROPAGATE …)`) is cheap. They share
the frame mechanic; they differ in what they wrap around it. In our
implementation, `ECmakeBlock` is literally the same `push_frame` /
`pop_frame` shape as the function-call branch of `ECmakeApply`, just
without the param-binding step and with the propagate list given by
the `block(PROPAGATE …)` syntax instead of the `return(PROPAGATE …)`
exception payload.

### `macro()` as the anti-frame

After all the frame mechanic, macros stand out by *not* having a
frame. They reach into the caller's locals directly, override param
names temporarily, and rely on the caller's free variables for
everything else. This is the "textual substitution" feel: as if the
body were copy-pasted at the call site.

In implementation, our macros and functions share the body shape
(`function_decl { params; body; is_macro }`) but differ in apply
strategy: functions push and pop a frame; macros save-and-restore the
param + `ARG*` bindings in the caller's frame. That's a clean
expression of the difference. The macro's "no frame" is just the
absence of the `push_frame` / `pop_frame` calls.

### Design takeaway for yelu

Yelu's `lang_yelu` already has `set` (cmake-style global mutable) and
`let` (lexical immutable). Adding `function()` and `block()` to yelu
*at the surface level* would mean importing all four cmake bindings:
snapshot-on-push, no-chain reads, `PARENT_SCOPE` writes, `PROPAGATE`
exits. That's a lot of accreted-language ergonomics to inherit.

The yelu design space leaves room for simpler choices:

- **Pure lexical functions with return values** — closer to ML.
  Eliminates `PARENT_SCOPE` and `PROPAGATE` entirely. Lower yelu →
  cmake via temp vars at the call site.
- **`let`-rec-friendly local definitions** — replaces both
  `function()` for inner helpers and `block()` for scoped temps.
  Lower to inlined cmake with mangled names.
- **First-class records / tuples for multi-value return** — covers
  the `return(PROPAGATE x y z)` use case without needing a separate
  mechanism.

The tiny `frame` primitive is general enough to support either the
cmake-faithful model (what we have now) or a cleaner yelu-side model
(future). Documenting this here so the choice surfaces explicitly
when binding-feature library work (Y15) starts.

The macro-elimination question (memory:
`project_macro_elimination.md`) sits in the same design conversation:
if yelu offers first-class records, lexical functions, and a
mechanism for "inline this body at the call site if you want
caller-frame side effects," then macros lose their last unique use
case.
