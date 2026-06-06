# ycn concrete syntax — design notes

> **Status**: design discussion, no implementation. Captures the
> question "what would a `.yn` / `.ycn` parser look like?" — the
> conversation that prompted this doc is logged inline as
> motivation. Not a finished proposal.

## 0. Where things stand today (2026-06-05)

There is **no concrete-syntax parser for `yelu_cmake_normal`**.

- `yelu_cmake` (yc) has [`yelu_parse.ml`](../../src/langs/yelu/yelu_parse.ml)
  + the `parse_program_y1` entry point, consumed for `.yc` files
  in [`probes/fmt/`](../../probes/fmt) and elsewhere.
- `yelu_cmake_normal` (ycn) has no parser. Every ycn program in
  the repo is hand-built in OCaml using fragment constructors.

The lift_lower test corpus is the natural design substrate:

| file | shape |
|---|---|
| [`test/test-yelu/test_yelu_lift_lower.ml`](../../test/test-yelu/test_yelu_lift_lower.ml) | 65 paired yc↔ycn tests across all 14 theories + bool + int |
| [`test/test-yelu/test_yelu_dual_eval.ml`](../../test/test-yelu/test_yelu_dual_eval.ml) | dual evaluator (same program through both eval paths) |
| [`test/test-yelu/test_yelu_function.ml`](../../test/test-yelu/test_yelu_function.ml) | F2 dynamic-scope, ycn side |
| [`test/test-yelu/test_yelu_cache.ml`](../../test/test-yelu/test_yelu_cache.ml) | one ycn-side cache test |

Together: **>65 hand-written ycn programs** ready to use as
acceptance tests for any proposed concrete syntax. Pick the
grammar, lower these tests to it, ratchet the parser until all
parse to the same OCaml AST.

## 1. What ycn surface needs to express that yc's doesn't

Three deltas from [`cmake_vs_normal.md`](cmake_vs_normal.md) drive
the syntax design:

### 1.a `ESetVar` is primitive — no command-side-effect sugar

In yc, side-effecting commands write to an output variable as part
of the command's structure:

```ocaml
(* yc *)
ECmakeStringConcat { inputs = [...]; out = "OUT" }
```

In ycn that's two steps: the operation is a pure expression, then
explicit assignment:

```ocaml
(* ycn *)
ESetVar ("OUT", EStringConcat { inputs = [...] })
```

(The fragment constructors in `yelu_cmake_normal_string.ml` may
still carry an `out` field for ergonomics today, but the *intent*
of the normal form is "compute, then assign." Concrete syntax
should reflect that intent — the assignment is the statement, the
computation is the expression.)

### 1.b bool / int as first-class expressions

ycn has `bool` and `int` theory fragments that yc lacks
([`fragments/yelu_cmake_normal_bool.ml`](../../src/langs/yelu/fragments/yelu_cmake_normal_bool.ml),
[`fragments/yelu_cmake_normal_int.ml`](../../src/langs/yelu/fragments/yelu_cmake_normal_int.ml)).
These let conditions and arithmetic compose as expressions
instead of cmake-command shapes:

```ocaml
(* ycn *)
EAnd (EVar "FMT_PEDANTIC", ENot (EVar "BROKEN_LTO"))
EIntLess (EVar "v", ELit (VInt 5))
```

In yc the same logic is buried inside `ECmakeIfStmt { cond; ... }`
where `cond` is a cmake-cond-token list shape — no compositional
arithmetic / boolean algebra at the surface.

### 1.c Subcommand zoos decompose

`list(APPEND XS a b)`, `list(LENGTH XS LEN)`, `list(GET XS 1 OUT)`
are one cmake command with three subcommands. ycn pulls these
apart so each is a single primitive — easier to optimize, easier
to reason about. Syntax should encode each subcommand as its own
operation, not via a `list(SUBCMD …)` dispatch shape.

## 2. Five examples (lift_lower, sketched as concrete)

Each example shows the existing ycn OCaml AST and a strawman
concrete syntax. Strawman A leans Rust/OCaml-ish; strawman B
keeps the parenthesized-block flavor of `.yc` for consistency.

### 2.1 Concat literals (lift_lower:35)

OCaml:

```ocaml
ESeq [
  ECmakeStringConcat { inputs = [EString "a"; EString "b"; EString "c"]; out = "OUT" };
  EVar "OUT";
]
```

Strawman A:

```
OUT = concat("a", "b", "c");
OUT
```

Strawman B:

```
(
  OUT := concat "a" "b" "c"
  OUT
)
```

### 2.2 Toupper nested in concat (lift_lower:42)

OCaml:

```ocaml
ESeq [
  ECmakeStringToupper { input = EString "b"; out = "TMP" };
  ECmakeStringConcat { inputs = [EString "a"; EVar "TMP"]; out = "OUT" };
  EVar "OUT";
]
```

Strawman A:

```
TMP = toupper("b");
OUT = concat("a", TMP);
OUT
```

The toupper-then-concat pattern is the canonical motivation for ycn
syntax: in yc you'd write a `string(TOUPPER b TMP)` then a
`string(CONCAT a ${TMP} OUT)`. ycn lets you express the same as a
pipeline of pure expressions, and a future optimizer can see
through the temporary.

### 2.3 If chooses then branch (lift_lower:73)

OCaml:

```ocaml
ESeq [
  ECmakeIfStmt {
    cond = ECmakeStringEqual (EString "a", EString "a");
    then_ = ECmakeStringToupper { input = EString "ok"; out = "OUT" };
    else_ = Some (ECmakeStringToupper { input = EString "bad"; out = "OUT" });
  };
  EVar "OUT";
]
```

Strawman A:

```
if "a" == "a" {
  OUT = toupper("ok");
} else {
  OUT = toupper("bad");
}
OUT
```

Strawman B:

```
(
  if str_eq "a" "a" then (
    OUT := toupper "ok"
  ) else (
    OUT := toupper "bad"
  )
  OUT
)
```

### 2.4 List append + length + join (lift_lower:97)

OCaml:

```ocaml
ESeq [
  ESetVar ("XS", EList []);
  ECmakeListAppend { list = "XS"; items = [EString "a"; EString "b"] };
  ECmakeListGet { list = "XS"; indices = [1]; out = "ITEM" };
  ECmakeListLength { list = "XS"; out = "LEN" };
  ECmakeListJoin { list = "XS"; glue = EString "-"; out = "OUT" };
  EVar "OUT";
]
```

Strawman A:

```
XS = [];
list_append(XS, "a", "b");
ITEM = list_get(XS, 1);
LEN = list_length(XS);
OUT = list_join(XS, "-");
OUT
```

Subcommand zoo decomposition is visible: every `list(SUBCMD …)`
becomes its own primitive call. No `list(APPEND xs …)` dispatch.

### 2.5 Path filename + normalize (lift_lower:115)

OCaml:

```ocaml
ESeq [
  ECmakePathSet { path = "P"; input = EString "/usr/local/bin/cmake"; normalize = false };
  ECmakePathGetFilename { path = "P"; out = "FILENAME" };
  ECmakePathSet { path = "Q"; input = EString "a/./b/../c"; normalize = false };
  ECmakePathNormalPath { path = "Q"; out = Some "NORMAL" };
  EVar "NORMAL";
]
```

Strawman A:

```
P = path("/usr/local/bin/cmake");
FILENAME = path_filename(P);
Q = path("a/./b/../c");
NORMAL = path_normal(Q);
NORMAL
```

The `path`/`target`/`cvar` newtypes from
[`yelu_cmake.ml`](../../src/langs/yelu/yelu_cmake.ml) (`tc_name`)
could surface as type-tagged constructors or stay implicit.

## 3. Open design questions

Listed without resolution — each is worth a separate discussion.

### 3.a Curly braces vs parens

`.yc` chose parens (`p_block_y1` matches `LPAREN ... RPAREN`).
ycn could go either way. Strawman A's `{ ... }` reads more
familiar to Rust/C/JS users; strawman B's `( ... )` keeps the
ecosystem self-consistent — one parser convention across both
languages.

Argument for parens: lower cognitive switching cost. yc and ycn
already share a single AST core; sharing block delimiters extends
the consistency.

Argument for braces: ycn is structurally further from cmake than
yc is — the visual distinction may help readers know which
language they're reading.

### 3.b Assignment operator

`X = expr` reads as imperative assignment. `X := expr` makes the
mutation more visible. `let X = expr in body` makes scope
explicit but is more verbose. yc's `.yc` chose `:=` for set and
`let ... in` for lexical binding (in pilot examples, anyway —
this is also a question for yc maturity).

ycn's `ESetVar` is global mutation, not lexical binding. So `=`
or `:=` are the natural fits; `let` would mislead.

### 3.c Expression-shaped vs statement-shaped operations

yc's `ECmakeStringConcat { inputs; out }` is statement-shaped:
the operation is the statement; it has a baked-in target name.

ycn's intended form is expression-shaped: `concat(...)` returns a
value; `OUT = concat(...)` makes it a statement. Side-effect-free
ops (string ops, int ops, list reads) are clean.

Side-effecting ops are harder: `file(WRITE …)` has no return
value; it's a statement. `execute_process` returns a result-code
AND writes captured output to an OUT var AND has side effects on
the filesystem AND can fail. Pure-expression framing strains
here. The grammar probably needs a statement vs. expression
distinction with file/process/cmake-meta commands always
statements.

### 3.d Type annotations

`tc_name` has 9 namespaces (`Ns_var`, `Ns_target`, `Ns_cache`,
…). Should the concrete syntax let you write `let p : path = …`?
Today's tests in OCaml don't carry these tags except for the
`tc_name` constructors that need them. Probably an optional
feature; default is untyped, opt-in tags help the checker.

### 3.e Generator expressions

`$<…>` cmake genex strings are first-class strings in yc (just
text). ycn might want them as parsed AST (`EGenexBuildInterface`
etc.) so analysis passes can rewrite them. If so, the concrete
syntax needs a way to write them — escape into a string-literal
sublanguage, or extend the expression grammar.

This connects to a separate Y* item ("Y6 — semantics hardest to
preserve: genex") that's open in the project TODO.

## 4. What I'd recommend before writing a parser

1. **Pick 5–10 lift_lower tests** and write the concrete syntax
   for each by hand, in two or three style candidates. Compare for
   readability.
2. **Decide the high-level style choice first** (Strawman A vs B,
   `=` vs `:=`, braces vs parens). Lock it before writing
   grammar.
3. **Define the surface as a BNF / Angstrom grammar** before
   writing parsing code. Compile against the lift_lower corpus —
   every test should be expressible.
4. **Acceptance: parse and re-emit** every lift_lower ycn program;
   the AST should be structurally equal (modulo source-trivia
   differences like comment placement) to the OCaml hand-built
   AST.

## 5. Related

- [`cmake_vs_normal.md`](cmake_vs_normal.md) — the broader yc/ycn
  comparison (this doc dives into one slice of it: surface
  syntax).
- [`design.md`](design.md) — the durable design notes for the
  yelu_cmake harness.
- [`structure.md`](structure.md) — code map; where the
  constructors live.
- [`../lang/lang_design.md`](../lang/lang_design.md) — broader
  language-design tradition this builds on.
- [`../lang/syntax_tiers.md`](../lang/syntax_tiers.md) — yc's
  concrete-syntax tier plan; same template can apply to ycn.
