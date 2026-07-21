# Bug: `~label:value` kwarg parsed as bare `~flag` + unconsumed KEYWORD

## Root cause (FIXED)

The lexer's `colon_or_keyword` parser combines `:identifier` into a single
`KEYWORD` token. For input `~out:OUT`, the lexer produces:

```
TILDE, IDENT "out", KEYWORD "OUT"
```

NOT the expected:

```
TILDE, IDENT "out", COLON, IDENT "OUT"
```

The parser's kwargs collector never saw a `COLON` between the label and value,
so `~out:OUT` was parsed as a bare flag `~out` (with value `Yexpr_bool true`),
leaving `KEYWORD "OUT"` as an unconsumed token. This broke the `p_block` outer
match, which expected `RPAREN` but found `KEYWORD "OUT"`.

## Symptom

```
( string_toupper 'hello' ~out:OUT )     → parse error at LPAREN
( string_toupper ~out:OUT 'hello' )     → parse error at LPAREN
( string_toupper ~out:OUT )             → parse error at LPAREN
( string_concat ~out:OUT )              → parse error at LPAREN
```

These passed (because additional positional args absorbed the stray KEYWORD):

```
( string_concat ~out:OUT 'a' 'b' )      → OK
( string_join ';' ~out:OUT 'a' 'b' )    → OK
```

## Fix (1 line)

Added a case in the kwargs collector to also match the lexer-combined form:

```ocaml
(* ~label:value — lexer combined :val into KEYWORD token *)
| TILDE :: IDENT kw :: KEYWORD v :: rest ->
    collect args ((kw, Yexpr_string (Ycs_string v)) :: kwargs) rest
```

This handles `~out:OUT` when the lexer produced `[TILDE, IDENT "out", KEYWORD "OUT"]`
instead of `[TILDE, IDENT "out", COLON, IDENT "OUT"]`.

File: `src/langs/yelu/lang_yelu_parse.ml`, in the `collect` function inside `p_command`.

## What was ruled out

- Token stream was correct for the lexer's semantics (KEYWORD token was intentional)
- `build_stmt` was correct — the kwargs never reached it because the collector
  didn't consume the KEYWORD token as a labeled arg value
- `p_expr` handled bare identifiers correctly
- The pattern was not position-dependent (first, middle, or last)

## Alternative fix (deferred)

Change the lexer to not combine `:identifier` into KEYWORD when preceded by
`~label`. This would require the lexer to be context-aware (know about TILDE),
which is a bigger change. The parser-level fix is simpler and sufficient.

==

Nice catch. Your revised root cause is much more consistent with the full symptom matrix than my earlier guess about `build_stmt`.

The key observation is this:

```text
~out:OUT
```

was not tokenized as:

```ocaml
TILDE; IDENT "out"; COLON; IDENT "OUT"
```

but as:

```ocaml
TILDE; IDENT "out"; KEYWORD "OUT"
```

So the parser did exactly what its rules said:

```ocaml
| TILDE :: IDENT kw :: rest ->
    collect args ((kw, Yexpr_bool true) :: kwargs) rest
```

It consumed `~out` as a flag, then left `KEYWORD "OUT"` behind. Then the outer block parser expected `RPAREN`, saw `KEYWORD "OUT"`, failed, and the error surfaced at the outer `LPAREN`.

That also explains why these passed:

```text
( string_concat ~out:OUT 'a' 'b' )
( string_join ';' ~out:OUT 'a' 'b' )
```

The stray `KEYWORD "OUT"` got accidentally absorbed as a positional expression before the later args. So the apparent “kwarg succeeds when followed by positionals” was really “the unconsumed keyword can be swallowed by the positional-arg branch.”

Your one-line parser fix is a reasonable local patch:

```ocaml
| TILDE :: IDENT kw :: KEYWORD v :: rest ->
    collect args ((kw, Yexpr_string (Ycs_string v)) :: kwargs) rest
```

But I would be careful about one detail: **is `KEYWORD v` semantically a string, a name, or a keyword literal?**

For `~out:OUT`, I would expect `OUT` to behave more like a variable/name than a string literal, especially given your earlier note that `out_var` extracts from `Yexpr_name` and `Yexpr_var`. If `Yexpr_string (Ycs_string v)` works only because `out_var` later treats strings as output variable names, that may be okay pragmatically, but it blurs the AST meaning.

I would consider making the patch one of these instead:

```ocaml
| TILDE :: IDENT kw :: KEYWORD v :: rest ->
    collect args ((kw, Yexpr_var (Yvar v)) :: kwargs) rest
```

or:

```ocaml
| TILDE :: IDENT kw :: KEYWORD v :: rest ->
    collect args ((kw, Yexpr_name v) :: kwargs) rest
```

depending on your AST conventions.

The broader design lesson is: **`KEYWORD` is not lexical enough.** It encodes a parser-level interpretation of `:identifier`. That is fine only if `:identifier` has one meaning everywhere. Here it has at least two:

```text
:public     keyword-ish marker
~out:OUT    labeled argument separator + value
```

So long-term, I would prefer one of these designs:

### Best long-term fix

Make the lexer emit punctuation literally:

```ocaml
COLON; IDENT "OUT"
```

Then parser-specific contexts decide whether `:OUT` means a keyword, a label-value separator, or something else.

This keeps the lexer simple and makes the grammar honest.

### Acceptable middle-ground

Replace `KEYWORD of string` with a more syntactic token:

```ocaml
COLON_IDENT of string
```

Then the parser can handle both:

```ocaml
| TILDE :: IDENT kw :: COLON_IDENT v :: rest -> ...
| COLON_IDENT kw :: rest -> ...
```

This at least preserves the fact that the source contained a colon.

### Current local fix

Keep `KEYWORD`, but make every parser location that can legally see `COLON IDENT` also accept `KEYWORD`.

That is okay for now, but it creates a maintenance rule: **any future grammar form involving `:name` must remember that the lexer may have collapsed it.**

I would also add a regression test specifically for accidental absorption:

```text
( string_concat ~out:OUT )
```

That is the cleanest failing case because there are no later positionals to hide the stray token.

And I would add a token-level test that asserts the actual lexer behavior:

```text
~out:OUT
=> TILDE, IDENT "out", KEYWORD "OUT"
```

Even if you later change the lexer, that test will force you to update the parser and expectations together.

So: your diagnosis is right. The bug was not kwarg position, not command-specific `build_stmt`, and not backtracking. It was a **lexer/parser contract mismatch**, made harder to see because `option`-based parsing erased the internal failure point.
