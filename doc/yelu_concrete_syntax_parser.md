# Yelu Concrete Syntax — Parser Framework

> Status: **Deferred, not started.** Preferred library recorded (Angstrom)
> for when we do begin, but the parser is not on the critical path.

## Why deferred

The AST-level work is where yelu's semantic substance lives: typed
namespaces, grouped variants, compositional helpers, staging. That work
is valid and self-contained without a concrete syntax.

The OCaml embedded DSL is itself already a surface syntax:

```ocaml
ycmd_of_list [
  add_exe (ytval "Tutorial");
  link_lib [ ytval "Tutorial" ]
    [ ytarget_def ~kind:Private [ ytval "MathFunctions" ] ];
]
```

It's not Python-like, but it's typed, regular, and composable. The LLM
evaluation research question ("does yelu's regularity improve first-pass
correctness vs raw CMake?") can be run on the embedded form — a parser
is not a prerequisite.

**Parser-AST coupling is a real maintenance tax.** Every AST refactor
(like the 11-group restructuring of 125 constructors) would propagate
into grammar rules, test fixtures, lexer keywords, and any tree-sitter
sibling. Building the parser before the AST stabilizes means paying the
tax twice.

## When to actually start

Build the parser when at least one of these becomes true:

1. We want a surface form specifically for **human authors who aren't
   OCaml programmers** (e.g. config engineers writing cmake-pack files).
2. We want a surface form the **LLM evaluation** requires — e.g. to
   compare a Python-like syntax against the embedded form as distinct
   variables.
3. The **AST has stabilized** — no more group-level or namespace-level
   refactors for 3+ months.
4. We need **editor tooling** (LSP, syntax highlighting) that presupposes
   a text-based grammar.

Until then, the embedded DSL is sufficient.

## Preferred library: Angstrom

The analysis below is recorded so we don't repeat it when we do start.

## Context

Yelu currently exists only as an OCaml embedded DSL — step files write
`ycmd_of_list [ add_exe ...; link_lib ... ]` directly in OCaml. A separate
Python-like concrete syntax is planned. The parser framework choice shapes
how compositional and iteration-friendly the development is, and how easily
LLMs (including the ones writing the code) can contribute.

## Requirements

1. **Compositional**: yelu-core grammar should be stable; language packs
   (cmake today, json/yaml/nix future) should extend it. Grammar expressed
   as values that can be combined per pack.
2. **AST-quality output**: yelu's AST is richly typed (typed namespaces,
   grouped variants). The parser should build it directly, not a CST we
   then walk.
3. **Iteration-friendly**: surface syntax is empirical; we'll tune
   repeatedly. No LR conflict-debugging sessions, no JS → C → OCaml
   pipeline.
4. **Claude-writable**: rich docs and/or large training-data footprint so
   the LLM writing the parser code has good examples to draw on.
5. Not a priority: raw parsing speed. yelu programs are CMakeLists-sized.
6. Explicitly rejected: handwriting the parser from scratch (GPT's
   recommendation). Maintenance burden is real, and we'd rather depend on
   a library.

## Options considered

### Menhir (OCaml-native LR(1))
- Most alive, richest documentation (INRIA-maintained; used by the OCaml
  compiler and Coq), largest training-data footprint.
- Grammar lives in `.mly` files. Composition is weak — the manual calls it
  "weak modularity": partial grammars join into one before analysis.
  Parametric rules help a little but don't support value-level composition
  across modules.
- LR(1) conflicts slow early syntax iteration.
- Best fit once the grammar is stable.

### Tree-sitter
- Purpose-built for editor tooling: incremental parse, error recovery,
  highlighting. OCaml bindings exist (Feb 2026 release).
- Grammar is in a JS DSL compiled to C; output is a CST, not your typed
  AST. Double the work if AST construction is the goal.
- Monolithic per-language grammar; no sub-grammar composition.
- **Right endpoint for editor support**, wrong primary frontend.

### Parser combinators (Angstrom, Opal, others)
- Grammar is OCaml values. Combinators compose as functions.
- `let yelu_core = ... in let cmake_pack = yelu_core <|> cmake_keywords`
  is the natural pack-extension pattern.
- Edit-build-try iteration; no conflict debugging, no codegen.
- Semantic actions build the typed AST directly.
- Slower than LR but irrelevant at yelu scale.
- **Angstrom specifics**: fast, non-backtracking by default (explicit
  `<?>`/`commit` for alternatives → predictable behavior). Designed for
  binary/network formats but widely used for text. Last release September
  2024 — stale but not abandoned; library is small and well-understood,
  fork risk is low. Widely used in the OCaml ecosystem (lots of example
  code for reference).

### Pacomb
- First-class grammars as OCaml values, PPX syntax, left-recursion
  handling, self-extensible grammars. Conceptually the best fit for
  yelu's core+pack model.
- Drawback: niche. Thin documentation and small community — less
  material to draw on when writing code.

### Parseff (2026)
- New direct-style OCaml 5.3+ combinator library with typed errors and
  label-based diagnostics. Closest OCaml answer to Rust's Chumsky.
- Drawback: very new. No proven track record, thin docs, small community.
- Worth watching; not worth betting on yet.

### Earley / dypgen
- Handle any CFG, including ambiguous ones. `dypgen` supports dynamic
  grammar extension at runtime.
- Earley's last release is 2020 (stale). `dypgen` was refreshed in 2025.
- Overkill for yelu — the design goal is regular syntax with explicit
  namespaces, which doesn't need GLR-shaped flexibility.

### Handwritten token parser + Pratt (GPT's recommendation)
- ~300–500 LOC, total control, direct AST construction, zero dependency
  risk.
- Rejected per project preference: we'd rather depend on a library than
  maintain a parser ourselves.

## Why Angstrom

The honest tradeoff matrix:

|            | Alive?      | Rich docs | Claude-friendly | Compositional       |
|------------|-------------|-----------|-----------------|---------------------|
| Menhir     | very        | very      | very            | **weak** (top priority) |
| Angstrom   | stale-ish   | moderate  | strong          | strong              |
| Pacomb     | moderate    | thin      | thin            | **very strong**     |
| Parseff    | brand new   | too new   | ~none           | strong              |

Angstrom is the only option that doesn't force us to sacrifice either
compositionality (yelu's ethos) or the ability to generate good parser
code via LLM (adequate docs + strong ecosystem footprint). The 2-year
staleness is a tolerable risk — the library is small, well-designed,
and has enough ecosystem usage that forking would be straightforward
if ever needed.

Menhir would win on docs and maintenance alone, but compositionality is
the project's stated top priority — and Menhir's weakest axis is exactly
that.

Pacomb is the better conceptual fit but has too thin a community and
documentation base for LLM-written code to draw on reliably.

## Architecture plan (when we start)

Confirmed patterns regardless of which library:

- **Lexer first**: emit tokens with spans (`NEWLINE`, `INDENT`, `DEDENT` if
  layout-sensitive, keywords, identifiers, literals, punctuation). If the
  surface is Python-like, layout belongs in the lexer, not the parser.
- **Core parser**: statements, blocks, declarations, typed expressions.
- **Pack extension interface**: explicit hook points
  (`parse_pack_stmt`, `parse_pack_decl`, `parse_pack_atom`) + keyword
  registration. Don't let packs inject syntax arbitrarily everywhere.
- **Pratt parsing for expressions**: precedence is local and extensible.
  Avoid threading operator tables through a generator-style grammar.
- **Every AST node carries a span**: enables later error reporting and
  LSP.
- **Language facts centralized**: keyword list, operator precedences,
  delimiters as data. Shared by the primary parser and (later) a
  tree-sitter grammar so they don't drift.

## Future phases

1. **Phase 1 (implementation)** — Angstrom-based parser, grammar as OCaml
   values organized by pack.
2. **Phase 2 (if needed)** — migrate to Menhir if a specific reason
   emerges (perf, exhaustive conflict checking). This is a rewrite, not
   a swap — plan for it honestly. Unlikely to be needed at yelu scale.
3. **Phase 3 (editor support)** — hand-write a tree-sitter grammar as a
   sibling artifact. Share language facts (keywords, precedences) with
   the primary parser so they stay consistent. Don't try to derive one
   from the other automatically.

## Open questions (deferred to implementation time)

- Error recovery strategy (Chumsky-style synchronize-on-token is
  portable; Angstrom doesn't have it out of the box).
- Incremental reparse for editors (Angstrom doesn't support; accept full
  reparse for small files, or defer to tree-sitter for editor path).
- Layout sensitivity details — if we go Python-like, exactly which
  constructs require indentation vs. braces.
