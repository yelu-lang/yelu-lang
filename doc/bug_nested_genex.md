# Nested `$<...>` genex: a debug story

A bug report, a two-AI collaboration, and a subtle point about OCaml evaluation
semantics that both AIs got wrong at different times.

## The bug

`$<IF:$<CONFIG:Debug>,debug,release>` lexed as `EVAL "$<IF:$<CONFIG:Debug>"`
— truncated at the first `>`. The remaining characters `,debug,release>` were
unconsumed input, causing downstream parse errors.

Root cause: `take_while (fun c -> c <> '>')` can't handle nesting.

## Claude's first fix

```ocaml
(* WRONG: counts bare < as nesting delimiter *)
let rec scan depth acc =
  peek_char >>= function
  | Some '<' -> advance 1 *> scan (depth + 1) (acc ^ "<")
  | Some '>' when depth = 0 -> return (EVAL ("$<" ^ acc ^ ">"))
  | Some '>' -> advance 1 *> scan (depth - 1) (acc ^ ">")
  ...
```

## GPT catches the delimiter error

GPT: "CMake genex nesting delimiter is `$<`, not `<`. Only `$<` should increment
depth. Otherwise a bare `<` inside a genex parameter would be misread as a
nested genex."

GPT also suggested using `Buffer` instead of `acc ^ ...` (O(n²) string concat)
and moving `Buffer.create` inside the parse branch for a fresh buffer per lex.

## Claude applies GPT's suggestions, tests fail

Claude moved `Buffer.create` inside `char '<' *>`:

```ocaml
(* WRONG: let buf runs at combinator-construction time, not parse time *)
(char '<' *>
 let buf = Buffer.create 64 in
 let rec scan depth = ... in
 scan 0)
```

Tests produced garbled output: `$<CONFIGIF:$<CONFIG:Debug>,release>`. Claude
reverted, concluded "Angstrom closure capture issue," and went back to a
module-level buffer with explicit `Buffer.clear` at parse time:

```ocaml
(* WORKS, but has shared mutable state *)
let buf = Buffer.create 64 in  (* module-level, created once *)
...
(char '<' *> return () >>= fun () -> Buffer.clear buf; scan 0)
```

## GPT clarifies: `*>` vs `>>=`

GPT pointed out that Claude's earlier attempt was wrong for a different reason
than Claude thought. `char '<' *> (let buf = ... in scan 0)` evaluates the
`let` at **combinator construction time** (module init) because `*>` evaluates
its right-hand side eagerly. The fix is to use `>>=` which evaluates its
continuation at **parse time**:

```ocaml
(* CORRECT: >>= continuation runs at parse time, fresh buffer per lex *)
let genex =
  (char '<' *> return ()) >>= fun () ->
  let buf = Buffer.create 64 in
  let rec scan depth =
    peek_char >>= function
    | None -> fail "unterminated generator expression"
    | Some '>' when depth = 0 ->
        advance 1 *> return (EVAL ("$<" ^ Buffer.contents buf ^ ">"))
    | Some '>' ->
        advance 1 *> (Buffer.add_char buf '>'; scan (depth - 1))
    | Some '$' ->
        advance 1 *> peek_char >>= (function
          | Some '<' ->
              advance 1 *> (Buffer.add_string buf "$<"; scan (depth + 1))
          | _ ->
              Buffer.add_char buf '$'; scan depth)
    | Some c ->
        advance 1 *> (Buffer.add_char buf c; scan depth)
  in
  scan 0
```

## The key distinction

Angstrom combinators are ordinary OCaml values. Whether a `let` runs at
construction time or parse time is just OCaml's call-by-value semantics: does
the `let` appear inside a **function body** that the parser calls later?

| Pattern                                | `let` evaluation time                                         |
| -------------------------------------- | ------------------------------------------------------------- |
| `p *> (let x = e in q)`                | Construction time — `q` is a parser arg, evaluated eagerly    |
| `p >>= fun y -> let x = e in ...`      | Parse time — inside continuation called when `p` succeeds     |
| `p >>\| fun y -> let x = e in f x y`   | Parse time — inside mapping function called when `p` succeeds |
| `p >>\| (let x = e in fun y -> f x y)` | Construction time — the `let` is outside the function body    |

The rule: **a `let` runs at parse time iff it is inside a function that the
parser invokes during parsing.** `>>=` continuations and `>>|` mapping functions
are such functions. The right-hand side of `*>` is not — it's a parser value
that must be constructed before the combinator runs.

Both Claude and GPT initially conflated "inside a parser combinator expression"
with "runs at parse time."

## Final code

```ocaml
let eval_lit =
  let not_brace c = not (Char.equal c '}') in
  let genex =
    (char '<' *> return ()) >>= fun () ->
    let buf = Buffer.create 64 in
    let rec scan depth =
      peek_char >>= function
      | None -> fail "unterminated generator expression"
      | Some '>' when depth = 0 ->
          advance 1 *> return (EVAL ("$<" ^ Buffer.contents buf ^ ">"))
      | Some '>' ->
          advance 1 *> (Buffer.add_char buf '>'; scan (depth - 1))
      | Some '$' ->
          advance 1 *> peek_char >>= (function
            | Some '<' ->
                advance 1 *> (Buffer.add_string buf "$<"; scan (depth + 1))
            | _ ->
                Buffer.add_char buf '$'; scan depth)
      | Some c ->
          advance 1 *> (Buffer.add_char buf c; scan depth)
    in
    scan 0
  in
  token (
    char '$' *> (
      (char '{' *> take_while not_brace <* char '}'
       >>| fun s -> EVAL ("${" ^ s ^ "}"))
      <|>
      genex
    ))
```

## Tests

- Simple genex, nested, double-nested, `${VAR}` unchanged
- Bare `<` not a nesting delimiter: `$<IF:a<b,yes,no>`
- Unterminated nested genex → lexer error
- Parser-level: nested genex in `compile_opts`, `TARGET_FILE` in `message`

25 lexer, 167 parser, 515 total — all pass.
