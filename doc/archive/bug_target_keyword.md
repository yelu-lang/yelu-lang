# Bug: TARGET keyword token in expression position

## Context

Yelu has a two-pass parser: an Angstrom lexer produces a `token list`, then a
pure OCaml parser walks the list. The parser type is:

```ocaml
type 'a parser = token list -> ('a * token list) option
```

No monadic operators — explicit `match` only. No backtracking issues because
each alternative receives the same token list.

## The bug

These inputs fail with `parse error at LBRACE`:

```
{ if TARGET target "Foo" then { } }
{ if TARGET target "Foo" then { message 'found' } else { message 'not found' } }
let tut : target = target "Tutorial" in { }
let tut = target "Tutorial" in {
  cmake_minimum_required "3.20";
  project "Tutorial";
  add_executable tut "tutorial.cxx"
}
```

Simpler variants that DO work:

```
{ if ON then { message 'yes' } }           # bool cond — works
{ if DEFINED 'TEST' then { } else { } }    # DEFINED cond — works
{ if TARGET target "Foo" then { } }        # TARGET cond — FAILS
```

The common factor is `TARGET` (the keyword token) appearing anywhere in the
parsed expression. When the condition is `ON` or `DEFINED`, parsing succeeds.
When it's `TARGET target "Foo"`, it fails at the `LBRACE` after `then`.

## Token stream (correct)

For `{ if TARGET target "Foo" then { } }`, the lexer produces:

```
0: LBRACE
1: IF
2: TARGET           (* TARGET keyword from if-condition *)
3: TARGET           (* "target" reserved word mapped to TARGET *)
4: PATH "Foo"       (* "Foo" double-quoted *)
5: THEN             (* "then" reserved word *)
6: LBRACE            (* then-body { *)
7: RBRACE            (* then-body } *)
8: RBRACE            (* outer } *)
```

Note: the lexer maps `target` (lowercase identifier) to the `TARGET` keyword
token via a reserved-words table. So `TARGET target "Foo"` becomes two
consecutive `TARGET` tokens, followed by `PATH "Foo"`.

## Parser trace (expected — should work but fails)

`p_if` calls `p_cond`, which calls `p_cond_first`:

```ocaml
let p_cond_first toks =
  match toks with
  | TARGET :: rest ->
    map (fun e -> Yis_target e) p_expr rest      (* line A *)
  | IDENT s :: rest when String.equal s "DEFINED" ->
    map (fun e -> Yis_defined e) p_expr rest
  | _ ->
    map (fun e -> Ytruthy e) p_expr toks
```

Line A matches: `toks = [TARGET, TARGET, PATH "Foo", THEN, ...]`. The first
`TARGET` is consumed. `rest = [TARGET, PATH "Foo", THEN, ...]`.

Then `p_expr rest` is called. `p_expr` tries `p_target_ref` first:

```ocaml
let p_target_ref toks =
  match kw "target" toks with
  | Some ((), r) -> map (fun s -> Yexpr_name { ns = Ns_target; name = s }) p_path_s r
  | None -> None
```

`kw "target" [TARGET, PATH "Foo", THEN, ...]`:

```ocaml
let kw s toks =
  let expect = match s with "target" -> TARGET | ... in
  match toks with
  | IDENT s' :: rest when String.equal s s' -> Some ((), rest)   (* line B *)
  | t :: rest when Poly.equal t expect -> Some ((), rest)         (* line C *)
  | _ -> None
```

Line B fails: first token is `TARGET`, not `IDENT`.  
Line C should match: `t = TARGET`, `expect = TARGET`, `Poly.equal TARGET TARGET`
is `true`. Should return `Some ((), [PATH "Foo", THEN, ...])`.

Then `p_path_s` matches `PATH "Foo"`, `p_target_ref` returns `Yexpr_name ...`.

Then `p_cond_first` wraps it: `Yis_target (Yexpr_name ...)`.

Then `p_cond` returns `Some (Yis_target ..., [THEN, LBRACE, RBRACE, RBRACE])`.

Then `p_if` calls `kw "then"`.

Then `p_block` calls `lbrace`. This should match `LBRACE`.

**But the parser reports `parse error at LBRACE` at the top level.**
This means `p_stmt` eventually returns `None` and the next unconsumed token is
`LBRACE`. But `p_block` should handle `LBRACE` (via `delim LBRACE`).

## What's been ruled out

- `Poly.equal TARGET TARGET` returns `true` (verified — same token passed to
  `kw "target"` matches via `Opt`ion correctly).
- Token stream is correct (lexer 15/15 tests pass, token dump shown above).
- `p_block` handles `LBRACE` correctly in isolation (test `empty block` passes).
- The two-pass architecture eliminates Angstrom backtracking issues (each
  alternative in `p_stmt` receives the SAME `toks` — no consumed-token loss).
- `kw "then"` matches `THEN` correctly (test `if simple` passes with `THEN`).

## Suspect

Something in the call chain `p_cond_first → p_expr → p_target_ref → kw "target"`
causes the returned remaining token list to be incorrect, or the `Some`/`None`
nesting in `p_cond` loses the token position.

## Relevant files

- `src/langs/yelu/lang_yelu_lexer.ml` — token type, lexer
- `src/langs/yelu/lang_yelu_parse.ml` — parser (~350 lines)
  - `p_cond_first` around line 80
  - `p_cond` around line 90
  - `p_if` around line 210
  - `p_block` around line 190
  - `p_stmt` around line 310
- `test/test-yelu/test_yelu_parse.ml` — parser tests (failing cases commented out)
- `doc/lang/concrete_syntax_parser.md` — architecture and gotchas doc
