# Yelu Concrete Syntax — Parser

> Status: **Implemented** (2026-05-04; renamed to `yelu_lexer.ml` /
> `yelu_parse.ml` during retirement, 2026-05-14). Two-pass architecture:
> Angstrom lexer produces `token list`, pure OCaml parser over tokens.
> Now part of the production path; integrated into `dune test` (~1,010
> unit tests pass).

## Architecture

```
input string
    │
    ▼
┌──────────────────┐
│  Angstrom lexer  │  yelu_lexer.ml  (~160 lines)
│  char → tokens   │  scannerless, whitespace + comment skipping
└──────┬───────────┘
       │ token list
       ▼
┌──────────────────┐
│  Pure OCaml      │  yelu_parse.ml  (~350 lines)
│  token parser    │  no Angstrom, no backtracking issues
└──────┬───────────┘
       │ yelu_cmake.expr AST
       ▼
   (compile / check)
```

**Why two-pass.** The original scannerless approach (Angstrom for both lexing and
parsing) hit a fundamental backtracking problem: `kw "function"` calls `ident`,
which consumes a token via `take_while1`. If the pattern match then fails (e.g.,
the next token is `"message"` not `"function"`), Angstrom's `<|>` does not
backtrack — the consumed token is lost. Subsequent alternatives in `p_stmt` see
a truncated token stream. The two-pass design eliminates this: tokens are
materialized once by the lexer, and the parser can inspect any token without
consuming it.

## Key files

| File | Lines | Purpose |
|---|---|---|
| `src/langs/yelu/yelu_lexer.ml` | ~160 | Token type, Angstrom lexer, whitespace/comment handling |
| `src/langs/yelu/yelu_parse.ml` | ~350 | Pure OCaml parser over token list, statement/expression/condition parsing |
| `test/test-yelu/test_yelu_lexer.ml` | ~80 | lexer tests |
| `test/test-yelu/test_yelu_cmake_parse.ml` | — | parser tests + pair-wise oracle vs legacy parser |

## Token type

```ocaml
type token =
  (* Reserved words — lexer maps identifiers to these *)
  | LET | IN | IF | THEN | ELSE | FOREACH | FUNCTION | MACRO
  | WHILE | BREAK | CONTINUE | RETURN | TARGET | CVAR | RANGE
  (* Value-carrying tokens *)
  | IDENT of string | PATH of string | STRING of string
  | EVAL of string | KEYWORD of string | BOOL of bool | INT of int
  (* Delimiters *)
  | LBRACE | RBRACE | LBRACK | RBRACK | LPAREN | RPAREN
  | COMMA | SEMI | COLON | DOTDOT | EQ
  | EOF
```

String kinds are distinguished by quote type:
- `"..."` double quotes → `PATH` (file paths, directories)
- `'...'` single quotes → `STRING` (plain string values)
- `${...}` or `$<...>` → `EVAL` (cmake variable/genex expansion)
- `:PUBLIC`, `:STATIC` → `KEYWORD` (colon-prefixed keywords)

## Parser design

The parser is a plain OCaml module using the type `'a parser = token list -> ('a * token list) option`.
No monadic operators — uses explicit `match` to avoid Base shadowing conflicts.

Key patterns:

```ocaml
(* Try alternatives on the SAME token list — pure, no backtracking issues *)
let p_expr toks =
  match p_target_ref toks with Some r -> Some r | None ->
  match p_cvar_ref toks with Some r -> Some r | None ->
  ...

(* Sequence: chain parsers by threading the token list *)
let p_let toks =
  match kw "let" toks with
  | None -> None
  | Some ((), toks) ->
    match p_ident toks with
    | None -> None
    | Some (name, toks) ->
      ...
```

**Mutual recursion** uses `let rec ... and ...`:

```ocaml
let rec p_stmt toks = ... p_block ... p_let ...
and p_block toks = ... p_stmt ...
and p_let toks = ...
```

`p_command` and `build_stmt` are not in the mutual recursion group — they don't
call back into statement parsers.

## Command dispatch

`build_stmt : string -> yelu_expr list -> (string * yelu_expr) list -> yelu_expr list -> yelu_stmt option`

Pattern matches on command name and args to produce the appropriate AST node.
Currently handles ~20 commands. Adding a new command is a matter of adding a
match case.

## Gotchas

### 1. Base + Angstrom = operator shadowing minefield

`open Base` shadows `char` (→ `Char` module), `string` (→ `String` module),
`<>` (polymorphic inequality → `int -> int -> bool`), and more. When also
`open Angstrom`, Angstrom's `char` and `string` functions shadow Base's modules.
But inside Angstrom combinator expressions, `char '{'` may still resolve
incorrectly. **The two-pass design avoids this entirely** — the lexer uses
Angstrom, the parser uses pure OCaml.

Lesson: do not write scannerless parsers with Angstrom when `open Base` is
in effect. Either don't open Base, or use the two-pass approach.

### 2. `$>` does not exist in Angstrom 0.16

`$>` is available in newer parser combinator libraries (Haskell, Rust nom) and
possibly in Angstrom ≥ 0.17. In 0.16, use `>>| fun _ -> value`.

### 3. `fix` vs `let rec` for Angstrom parsers

Angstrom parser values are not syntactic functions, so `let rec` cannot be used
to define recursive parsers. Use `fix : ('a t -> 'a t) -> 'a t` instead.
For the two-pass parser, `let rec` works fine because the parser functions are
actual OCaml functions (`token list -> ...`).

### 4. `skip_while` breaks Angstrom backtracking

Angstrom's `<|>` only backtracks if the left alternative consumed NO input.
`skip_while` always consumes input (even zero characters counts as "success and
may have consumed"). So `(skip_while f *> p) <|> q` will never try `q` if
`skip_while f` succeeds, even if `p` fails.

Fix for the lexer: use `peek_char` + `advance` to skip one character at a time,
which allows backtracking:
```ocaml
let rec skip () =
  peek_char >>= function
  | None -> return ()
  | Some c when is_ws c -> advance 1 *> skip ()
  | Some '#' -> advance 1 *> skip_while not_newline *> skip ()
  | Some _ -> return ()
```

### 5. `many_till` returns `'a list`, not `'a list * 'b`

In Angstrom 0.16, `many_till : 'a t -> _ t -> 'a list t` returns just the list,
discarding the terminator's result. This is different from some other parser
combinator libraries that return a pair.

### 6. `kw` must match both `IDENT` and keyword tokens

The lexer maps `"let"` → `LET`, `"in"` → `IN`, etc. The `kw` function must
handle both `IDENT "let"` (from user-written identifiers) and `LET` (from the
lexer's keyword mapping). The current implementation handles both cases with a
fallback `equal_token`/`Poly.equal` check.

### 7. Codex review fixes (2026-05-04)

Four issues found and fixed:

1. **Colon lexing** — `keyword_lit` consumed `:` before `take_while1` failed,
   blocking `colon_s`. Merged into single `colon_or_keyword` parser that peeks
   ahead before committing: `char ':' *> (take_while1 ... <|> return COLON)`.

2. **Command kwargs** — lexer emits `KEYWORD` token for `:msg`, but parser
   only matched `COLON :: IDENT`. Added `| KEYWORD kw :: rest` pattern.

3. **Let type annotation** — `COLON :: _` matched but `p_ident` was called
   on original `toks` (still with `COLON`). Fixed to consume `COLON` first:
   `COLON :: rest -> p_ident rest`.

4. **Trailing tokens** — entry point returned `Ok` regardless of remaining
   tokens. Now rejects with `Error "unexpected trailing tokens"`.

### 8. Known edge cases (4 remaining)

- `if TARGET target "Foo" then { }` — `TARGET` keyword token in expression
  position fails with "parse error at LBRACE". The token stream is correct,
  `p_target_ref` handles `TARGET` via `kw "target"` + `Poly.equal`, but
  something between `p_cond` and `p_block` loses the token list.
  Also affects: `let ... : target = ...`, `full step1`.

## Surface syntax (current)

Based on the OCaml-Python hybrid design:

```yelu
let tut : target = target "Tutorial" in
{
  cmake_minimum_required "3.20";
  project "Tutorial" :version "1.0" :languages [CXX];

  set CMAKE_CXX_STANDARD "11";
  set CMAKE_CXX_STANDARD_REQUIRED ON;

  add_executable tut {
    sources = ["tutorial.cxx"]
  };

  target_link_libraries tut {
    :public { math };
    :private { flags }
  };

  if ${do_test} then {
    enable_testing;
    add_test "Runs" "Tutorial" "25"
  }
}
```
