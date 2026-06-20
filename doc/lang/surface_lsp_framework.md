# Surface syntax + LSP — design exploration (yc-first)

> **Status (2026-06-09): exploration, no implementation.** Captures the
> design decision-map for giving `yc` (`yelu_cmake`) a higher-fidelity
> surface and a language server, with an eye to later reusing the same
> framework for `ycn` and other yelu packs. Scope is deliberately
> **yc-first**: solidify the library / span / deployment / testing
> choices on one language before generalizing. Sibling topic to the
> behavior-level oracle — see "Two halves" below.

## 0. Framing — the two halves of "is yelu a real language"

- **Behavior-level oracle** → *dynamic* semantics: runtime output ≡ cmake,
  proven via the File API. Feeds off the driver's `eval`.
  (See [`../yelu_cmake/status.md`](../yelu_cmake/status.md) "Open work".)
- **Surface + LSP + ecosystem-semantic** (this doc) → *static* semantics:
  types, "beliefs", and the authoring experience. Feeds off the driver's
  `check`.

Both are **driver ops** over the same uniform interface
([`../yelu_cmake/driver.md`](../yelu_cmake/driver.md)), which is why "a
framework for the yelu languages" and "the driver motivation" are the
same bet. The driver is the abstraction boundary the LSP plugs into.

## 1. The reuse split — semantics reuses, the parser is the work

The honest assessment of "reuse the existing OCaml codebase":

| Component | LSP-ready? | Notes |
|---|---|---|
| `eval` (`yelu_cmake_eval`) | ✅ reuse | already consumes the position-free `expr` |
| `check` (type/wellform) | ⚠️ stubbed | unstub → diagnostics + hover source |
| `convert` (to/from normal) | ✅ reuse | |
| driver op interface | ✅ reuse | the LSP's plug point |
| lexer (`yelu_lexer`) | ✅ reuse | |
| `Fmt`-based printing infra | ✅ reuse | model: `lang_cmake_pp` |
| **parser (`yelu_parse`)** | ❌ **new design** | see below |

`parse_program_y1 : string → (Yelu_cmake.expr, error) result` discards
**all source positions** — `Yelu_cmake.expr` carries no `loc`, and the
Angstrom parser captures no spans. Every semantic consumer is fine with
that; an LSP is not. The front-end needs three things the current parser
lacks: **source spans**, **error recovery**, and a **printer** (the
`print_ye` stub). So ~70% reuses (the semantic half, via the driver);
the parser is where the design effort lives.

## 2. Industry context — do real languages keep two parsers?

Short answer: **two parsers is common, and it's driven by genuine IDE
requirements, not merely legacy.** Compiler parsers and editor parsers
have different jobs:

| | batch / compiler parser | editor / IDE parser |
|---|---|---|
| input assumption | mostly-correct | constantly-broken (mid-edit) |
| error handling | fail fast | recover, produce partial tree |
| fidelity | drops trivia (comments/ws) | full-fidelity (lossless) |
| spans | coarse / optional | precise, every node |
| reparse | whole file | incremental |

How real languages landed:

- **C# / Roslyn** — *one* parser. A full-fidelity "red-green" tree
  (immutable green nodes + a red overlay carrying parents + absolute
  positions) serves compiler **and** IDE. The gold standard for "one
  parser done right."
- **TypeScript** — *one* parser. The compiler's parser is full-fidelity
  and error-recovering; `tsc` and the language service share it.
- **Rust** — *two*, deliberately. `rustc` has its AST parser;
  `rust-analyzer` re-implemented a lossless syntax tree (`rowan`,
  Roslyn-inspired) because the compiler's parser wasn't built for
  recovery/incrementality. Convergence ("librarification") is a
  long-running goal, not yet done.
- **Go** — effectively *two*: the compiler's internal parser (tuned for
  speed) vs the stdlib `go/parser` (position-tracking, comment-preserving)
  that `gopls` and most tooling use.
- **OCaml / Merlin** — a middle path: Merlin reuses the compiler grammar
  but with an **error-recovering** variant, rather than a wholly separate
  parser.

**Takeaway for yelu:** the way to *avoid* the two-parser trap is to make
the single parser full-fidelity + recovering *from the start* — exactly
what Roslyn/TS did and what `yelu_parse` (young, ~2.1 k lines, one
language) can still choose. Retrofitting that onto a mature batch parser
is what forces the split; we are early enough not to inherit that debt.
This is the rationale for decision **§3.2(c)** below.

## 3. Decision map (yc-first)

### 3.1 LSP server library → `linol`

`linol` (Simon Cruanes) is purpose-built for "I have a language, give me
a server": it owns the JSON-RPC event loop, document sync, and capability
registration; you implement callbacks that call `Yc_driver` ops. It sits
on `lsp` / `jsonrpc` (the ocaml-lsp-server / Merlin team's packages,
well-maintained) which you could also use raw at the cost of more
boilerplate. Recommendation: `linol`; write almost no protocol code of
our own.

### 3.2 Source positions — the central choice

- **(a) located AST** — wrap every node `{ node; loc }`. Cleanest, but
  touches every fragment *and* every `eval`/`check` match arm. Expensive
  against the extensible variant.
- **(b) side table** — keep `expr` position-free; parser emits a parallel
  `node-id → span` map. Cheap, but AST/table can drift out of sync.
- **(c) CST / AST split** — parser produces a **full-fidelity located
  CST**; lower it to the position-free `expr` for `eval`/`check`.

**Recommendation: (c).** It is the Roslyn/TS "one full-fidelity front
parser" path, and it keeps the position-free `expr` *byte-identical* so
the matrix/oracle/behavior pipeline is untouched. Cost: one lowering
step (CST → expr). Payoff: the semantic half never moves, and the CST is
the natural home for trivia (comments) the formatter must preserve.

### 3.3 Error recovery → statement-level (v1)

Angstrom recovers poorly, but yc is a statement sequence. Parse
statement-by-statement so one broken statement yields a diagnostic + a
hole, not a dead file — cheap, reuses existing per-statement combinators,
and gives the LSP a usable partial tree while editing (the common case).
Token-level recovery (tree-sitter / menhir-incremental) is a later
question, not a v1 blocker.

### 3.4 Printer → reuse `Fmt`, close `print_ye`

Same machinery as `lang_cmake_pp`. Closing the `print_ye` stub hands us
the LSP formatter **and** a `parse ∘ print ≡ id` round-trip oracle (same
discipline as lift_lower and the cache work). Parse↔print symmetry is the
single best forcing function for validating the CST design on one theory.

### 3.5 Syntax highlighting → TextMate baseline + LSP semantic tokens

VS Code highlighting is layered, and the layers are *complementary*, not
alternatives:

1. **TextMate grammar** (`.tmLanguage.json`) — regex, client-side, no
   server, instant. The "LSP-less style." Every VS Code language ships
   one. Coarse (regex can't truly parse) but always-on, including before
   the server starts and during reparse.
2. **`language-configuration.json`** — brackets, comments, auto-close,
   indentation. Also server-less. Cheap basic editing.
3. **LSP semantic tokens** (`textDocument/semanticTokens`) — the server
   colors based on *real* analysis, layered on top of TextMate to refine
   what regex can't know.
4. **tree-sitter** — declarative grammar → incremental parse tree;
   client-side, no LSP needed for coloring. Used by Zed / Neovim / GitHub;
   VS Code adopting for some built-ins. An option if we want accurate
   highlighting without routing through the LSP.

**Is the LSP-less (TextMate-only) style good?** It is good for what it
is — instant coloring + basic editing for a few hours' work — but it is a
**complement, not a substitute**: it gives *nothing* semantic (no
diagnostics, hover, go-to-def, completion, rename). For a language whose
value proposition *is* the semantic layer (types, beliefs), TextMate-only
undersells it. The right setup is **both**: a TextMate grammar for the
instant baseline (great for demos, cheap, throwaway-able) *and* the LSP
for everything semantic.

Note: yelu's `tc_name` namespaces (cache var vs normal var vs target vs
…) are a case where **semantic-token** highlighting is genuinely valuable
— regex/TextMate cannot tell a cache var from a normal var, but the LSP
can color them differently. So highlighting is not just decoration here;
it surfaces a real yelu distinction.

### 3.6 Deployment → stdio binary + thin VS Code client

A standalone `yelu-lsp` executable over **stdio** (dune/opam build), and
a ~50-line TypeScript VS Code extension that launches it + ships the
TextMate grammar + `language-configuration.json`. We are already in VS
Code, so the client is trivial. Later: bundle the binary into the
extension for distribution.

**Shipped (M1.5a/M1.5c, 2026-06-10).** Concrete deployment, verified
working in-editor:

- Server: [`src/bin/yelu_lsp/`](../../src/bin/yelu_lsp/) — a `linol-lwt`
  server over stdio (`linol`/`lsp`/`jsonrpc` 1.26 via the yojson-3 linol
  fork pinned at `/home/red/code/contrib/linol`). Built with
  `dune build src/bin/yelu_lsp/`.
- Client: [`editors/vscode/yc/extension.js`](../../editors/vscode/yc/)
  (plain CommonJS, not TS) using `vscode-languageclient` — spawns the
  server and resolves its path from the `yc.server.path` setting, else
  `<workspace>/_build/default/src/bin/yelu_lsp/yelu_lsp.exe`.
- Deploy locally: `dune build src/bin/yelu_lsp/` →
  `code --install-extension <yc-x.y.z.vsix>` → Reload Window. Open a
  `.yc`: diagnostics in the Problems panel; *Format Document* and
  `"[yc]": {"editor.formatOnSave": true}` route through the server's
  `textDocument/formatting` (the `Yc_driver.format` / `yelu fmt` engine),
  fail-safe (parse error → no edits). Full steps + settings in the
  extension [README](../../editors/vscode/yc/README.md) § "Language server".

### 3.7 Testing → at the driver-op level, with Alcotest

Do **not** test through JSON-RPC (that is `linol`'s code, not ours). Test
`parse→diagnostics`, `hover-at-position`, `format` as direct function
calls with golden / Alcotest cases — reusing the 170 parser tests +
lift_lower corpus for round-trips, plus `(node, range)` golden assertions
for spans. A handful of end-to-end protocol smoke tests can come later.

### 3.8 Grammar as a single source of truth — where it lives

The worry: adding a TextMate grammar means the "grammar of yc" now lives
in **three** places — the lexer (`yelu_lexer`), the hand-written parser
(`yelu_parse`), and the TextMate JSON — which can drift. The resolution
is to **not** try to unify all three. They need *different slices* of
grammar knowledge; only one slice is shared, and only that slice deserves
an SSOT.

**Key fact: a TextMate grammar is a *scanner*, not a parser.** It
classifies spans into scopes (keyword / string / comment / function name)
with regex; it does not build a tree. So its natural counterpart in our
codebase is the **lexical vocabulary**, *not* the parser. Split the SSOT
question accordingly:

| slice | authority | shared with TextMate? |
|---|---|---|
| token vocabulary (commands, keywords, operators, literal/comment delimiters) | `yc_primitives.ml` | **yes** — this is the SSOT to enforce |
| how tokens combine into statements (the grammar productions) | `yelu_parse.ml` (hand-written) | **no** — TextMate doesn't need it |
| coarse nesting / string-interp regexes in the `.tmLanguage.json` | the TextMate file, hand-written | n/a — approximate by nature |

**1. Vocabulary → generated SSOT (cheap, high value).**
`yc_primitives.ml` already enumerates the vocabulary — `command_names`
plus `reserved_names` (control-flow `let`/`if`/`then`/`else`/…, type
keywords `target`/`cvar`/`cache`, booleans `ON`/`OFF`, condition
operators `not`/`and`/`or`/`str_eq`/…). It is *already* the SSOT for the
words. Two moves complete it:
  - **Reorganize by lexical class → TextMate scope** (command =
    `support.function`, control = `keyword.control`, operator =
    `keyword.operator`, type = `storage.type`, bool = `constant.language`)
    instead of two flat sets.
  - **Generate** the keyword/operator/command patterns of
    `yc.tmLanguage.json` from it (a small exe / dune rule + promote).
    Adding a command then updates lexer + TextMate for free.

  > Note an *existing* drift this fixes: `yelu_lexer` hardcodes its own
  > keyword map (`"let",LET; "if",IF; "then",THEN; …`) duplicating
  > `reserved_names`. Routing the lexer's keyword recognition through
  > `yc_primitives` removes a duplication we already carry.

**2. Structure → hand-written, coarse, non-authoritative (the "relaxed"
part).** The nesting and string-interpolation regexes in the TextMate
file are hand-maintained and approximate. This is the industry norm —
TypeScript, Rust, Go all ship hand-maintained TextMate grammars separate
from their compilers and accept the drift, *because*:

**3. The parser stays the sole syntactic authority, and it still drives
highlighting — through a different channel.** With an LSP, the TextMate
grammar's accuracy matters *less*, because **semantic tokens**
(`textDocument/semanticTokens`, computed from the real parse) are layered
on top and correct it at runtime. So the authoritative grammar (the
parser) *does* feed highlighting — via semantic tokens, not via TextMate.
TextMate is only the instant / cold-start / pre-server-boot approximation.
That is why the relaxation is **correct architecture, not a compromise**:
the duplication that matters (vocabulary) is generated from one source;
the duplication that doesn't (coarse structure) is hand-written and
self-corrects the moment the LSP attaches.

**The "true SSOT" option we're declining: tree-sitter.** A tree-sitter
grammar is *one* declarative grammar that yields an incremental parser
**and** drives highlighting (via queries) — it could replace both the
hand parser and the TextMate file, a genuine single grammar for tokenizer
*and* parser. The cost: it's C/JS, the generated parser is C, and we'd
bridge its CST into OCaml (FFI or re-parse), losing the native Angstrom
parser and adding a polyglot build dependency. That is the "heavy work"
to avoid for yc-first. Worth revisiting only if the hand-parser ever
needs replacing wholesale — at which point tree-sitter buys back the
single-grammar-source we're relaxing on here.

**Concrete placement:**
- vocabulary → `src/langs/yelu/yc_primitives.ml` (enrich: lexical class →
  scope);
- generator → a small exe (e.g. under `tool/`) emitting
  `editors/vscode/syntaxes/yc.tmLanguage.json`, via dune rule + promote;
- lexer → derive keyword map from `yc_primitives` (drop the hardcoded
  copy);
- parser → unchanged, the syntactic authority; feeds highlighting via LSP
  semantic tokens.

#### Generation root — a command manifest, *not* reflection over the type

The deeper instinct is to make the **typed IR the truth** and *generate*
`yc_primitives`, the tm-grammar vocabulary, types, and constants from it.
Right direction — but mind the OCaml mechanism:

- `Yelu_cmake.expr` is an **extensible variant** (`type expr = ..`;
  fragments do `type expr += ECmakeX …`). ppx derivers
  (`ppx_deriving`, etc.) work on *closed* type declarations in one place;
  they do **not** reflect over open/extensible variants spread across 14
  fragment files. So "ppx the type → emit the primitives" fights the very
  design (extensibility + per-theory fragments) that makes the harness
  composable. Don't go there.
- Instead, make a **declarative command manifest** the generation root: a
  data table, one record per command —
  `{ surface_name; ctor; lexical_class → tm_scope; arg_types; … }` —
  ideally contributed *per fragment* (each theory owns its slice, matching
  the existing fragment structure). From the manifest you **generate**
  `yc_primitives`' vocabulary + the tm-grammar patterns (+ later: typed
  signatures the LSP semantic layer needs).
- Keep the manifest and the AST as **test-locked co-truths**, not
  one-generates-the-other: an Alcotest assertion that every manifest entry
  has a constructor and every constructor a manifest entry. Drift becomes
  a failing test, which is the SSOT guarantee you actually want — and it
  sidesteps the extensible-variant reflection problem entirely.

**Layer the manifest — don't over-build it for Milestone 0.** Highlighting
needs only the *lexical* slice (`surface_name`, `lexical_class → scope`).
The typed signatures / constants the LSP and ecosystem-semantic want are a
*later* column on the same manifest. Start with the lexical slice; grow
the manifest when the semantic layer needs it.

**Expose the manifest through the driver.** The co-truth should be
first-class on the uniform interface, not an internal detail: add a driver
op (e.g. `Yc_driver.manifest` / `describe`) that *returns/prints* the
current command manifest. Consequences:
- the tm-grammar generator consumes `Yc_driver.manifest` rather than
  reaching into `yc_primitives` internals — the driver stays the boundary;
- it gives a CLI/REPL way to *see* the agreed truth (`yelu manifest`),
  which is also the most honest acknowledgement that — absent ppx over
  extensible variants — the manifest is curated, not derived;
- it slots next to `parse / print / eval / compile / check` in
  [`../yelu_cmake/driver.md`](../yelu_cmake/driver.md) as a sixth
  introspection op, applicable later to `ycn` too.

## 4. ecosystem-semantic hook

The `check` driver op is where the separate **ecosystem-semantic**
project (assign type + "beliefs" to a PL) plugs in. The LSP consumes its
output:

| LSP request | driver op | semantic source |
|---|---|---|
| didChange → diagnostics | `parse` ∘ `check` | belief violations / type errors |
| hover | `check` | type + namespace at a node |
| completion | grammar + namespace | `tc_name` namespaces |
| formatting | `print` | — |
| go-to-definition | wellform | cvar/target def-use |
| semanticTokens | `check` | namespace-driven token kinds |

**Open input:** the shape of a "belief" determines `check`'s *output*
type. If beliefs are just type errors, `check : … → diagnostic list`
suffices. If beliefs are richer (assumptions, inferred-with-confidence
facts, abstract-interpretation results the LSP renders as hover/inlay),
`check` must emit a richer fact stream, not a flat diagnostic list. This
needs pinning down before the `check` signature is frozen.

## 5. Milestones & forcing-function order

### Milestone 0 — server-less TextMate highlighter — **shipped 2026-06-10**

Independent of the parser/CST/LSP work; shipped first. Delivered:
- [`Yc_manifest`](../../src/langs/yelu/yc_manifest.ml) — the typed
  vocabulary table, test-locked to `Yc_primitives` + the lexer as a
  co-truth ([`test_yc_manifest.ml`](../../test/test-yelu/test_yc_manifest.ml));
- [`Yc_driver.manifest`](../../src/langs/drivers/yc_driver.ml) — the
  co-truth on the uniform driver interface;
- [`Yc_tmgrammar`](../../src/langs/yelu/yc_tmgrammar.ml) — vocabulary →
  `(regex, scope)` rules (escaping / longest-first / `\b`), unit-tested
  ([`test_yc_tmgrammar.ml`](../../test/test-yelu/test_yc_tmgrammar.ml));
- `yelu manifest` (print the TSV) + `yelu tmgrammar` (emit the JSON);
- [`editors/vscode/yc/`](../../editors/vscode/yc/) — the extension
  (`package.json`, `language-configuration.json`, generated
  `syntaxes/yc.tmLanguage.json`), with `make tmgrammar` (regen) and
  `make tmgrammar-check` (drift guard).

Verified by tokenizing `probes/fmt/main.yc` with the real VS Code
TextMate + Oniguruma engine (`editors/vscode/yc/test/tokenize.js`): every
manifest class fires correctly on real source. Install/enable steps are in
the extension [README](../../editors/vscode/yc/README.md).

Deviations from the original sketch: the generator is a CLI subcommand
(`yelu tmgrammar`), not a dune-rule + cross-dir `promote` — simpler and
deterministic; the drift guard is `make tmgrammar-check`. JSON
serialization lives in the `yelu` binary (where yojson is); the
`Yc_tmgrammar` library stays dep-free. The `ctor` (AST-link) manifest
column is present but unpopulated — see §3.8.

This validated the toolchain (extension packaging, `.tmLanguage` scopes)
and forced the lexical-SSOT work (manifest → generated vocabulary) — the
"coherent truth agreement" prerequisite — using only the lexical slice of
the manifest, with no dependency on the typed-IR truth.

### Milestone 1+ — LSP (forcing-function order)

1. **Spans in the parser** (CST, §3.2) — prerequisite for all of LSP.
2. **Close `print_ye`** (§3.4) — formatter + round-trip oracle.
3. **Statement-level recovery** (§3.3) — partial tree while editing.
4. **Generic LSP shell over `Yc_driver`** (§3.1) — diagnostics ← check,
   hover ← semantics, format ← print.
5. **Plug ecosystem-semantic into `check`** (§4) — hover types,
   diagnostics, semantic tokens.

### Formatter (`yelu fmt` / LSP formatting) — elaborates steps 1–2

The `.yc` auto-formatter is not a separate component: it *is* `print_ye`
(step 2), gated on the CST/trivia work (step 1), and later surfaced by the
LSP formatting provider (step 4) and a `yelu fmt` CLI from the *same*
engine.

**Comment syntax — decided:** `#` line comment to end of line, the one
form yc already uses; no block comments. So the trivia model stays simple:
one comment kind to retain.

**The gate (step 1):** the lexer today *discards* `#…` during
whitespace-skip, so the AST never sees comments. A formatter that drops
comments is unacceptable, so the CST work must **tokenize/retain comments
+ spans as trivia** (attached to lines/nodes) before any printing. This is
the hard prerequisite; everything below is downstream of it.

**Implementation — fixed first, no Doc IR needed (step 2):** v1 is a naive
*canonical* pretty-print of the AST/CST through OCaml's `Format` boxes at a
fixed width (80), no options — reusing the exact pattern
[`Lang_cmake_pp`](../../src/langs/cmake/lang_cmake_pp.ml) already uses for
cmake. `Format`'s box model *is* the underlying Doc/box layout algebra
(hovbox ≈ `group`, break hints ≈ `line`, margin ≈ width); it is a bit
obscure but already proven in this codebase, so v1 needs no bespoke Doc
type. An explicit Wadler/Leijen **Doc IR** (with `width` / `indent` as the
only render-time knobs) is an *optional later refinement* — worth it only
if the box model gets awkward or we want to transform layout before
rendering. *Style* configurability (break rules, alignment) is
deliberately omitted: opinionated/canonical formatting fits a low-entropy
config language (the gofmt stance). [Doc/box algebra is a flagged
revisit-for-know-how topic.]

**Testable properties (the oracle):**
- *semantics-preserving:* `parse (format x) ≡ parse x` — formatting changes
  layout only, never the AST. A round-trip oracle in the same style as
  lift_lower / the cache oracle.
- *idempotent:* `format (format x) = format x`.

These give the formatter a cheap, strong test harness from day one.

## 6. The first LSP slice — a one-theory tracer bullet

Once Milestone 0 ships, the first LSP step. Before committing span
representation or recovery strategy across 14
theories, drive **one theory end-to-end** — `string` is the cleanest
(pure, no cmake-meta side effects, already in lift_lower). Vertical slice:
spans on its parse → its printer → hover showing its type/namespace → a
diagnostic from deliberately-broken input → live in VS Code over `linol`.
That single slice exercises *every* hard decision (CST representation,
recovery, the LSP shell, the semantic hook, deployment, testing) at
minimal cost, and the choices it forces are exactly the ones to lock
before scaling to all theories or generalizing to `ycn`.

## 7. Open questions to resolve during exploration

- **"Beliefs"** — concrete definition (§4); drives the `check` signature.
- **CST shape** — green/red trees (Roslyn-style) vs a simpler located
  CST; how trivia (comments) are attached for the formatter.
- **Reparse granularity** — whole-file vs statement-incremental vs
  tree-sitter incremental; tied to §3.3.
- **TextMate vs tree-sitter** for the baseline highlight layer (§3.5).
- **Generalization checkpoint** — what must hold before lifting the
  framework to `ycn` / other packs (the explicit "yc-first" exit
  criterion).

## 7.5 Wellform diagnostics — what we flag, and when it's fatal

The wellform pass ([`Yc_wellform`](../../src/langs/yelu/yc_wellform.ml),
called via [`Yc_driver.wellform`](../../src/langs/drivers/yc_driver.ml)) is
how the LSP turns "your file parses but won't behave" into Problems-panel
diagnostics. Every check below surfaces through the same channel; severity
(warning vs fatal) is the only knob.

| Check | What it flags | Severity |
|---|---|---|
| `Reserved_name` | `EVar` whose name collides with a reserved keyword (`target`, `cache`, …) or a typed primitive | warning |
| `Apply_shadows_primitive` | `ECmakeApply { name = "string_concat"; … }` escapes a typed yc API (use the typed form) | warning |
| `Enum_shadow` (Y14) | `set public := …` — variable declaration shadowing an enum constructor (`Public`/`Static`/…) | **fatal** |
| `Raw_cmake_escape` | `ECmakeRaw text` — explicit `yc_raw '…'` use, surfaced so it isn't silent | warning |
| `Positional_form` (Step 2) | A labeled-only command (`install_targets`, `set_property`, …) written in cmake's positional keyword form | **fatal** |
| `Unknown_command` | A command name that's neither a typed yc primitive nor declared as `function`/`macro` in this file | see § below |

### Unknown_command — the open/closed-world rule

cmake's command set is genuinely **open**: real code introduces names via
five paths that single-file static analysis cannot see:

1. **`include(SomeModule)`** — runs the module's cmake, which may define functions/macros.
2. **`find_package(Foo)`** — same via `FooConfig.cmake`.
3. **`add_subdirectory(d)`** — runs `d/CMakeLists.txt`.
4. **`cmake_language(CALL ${cmd} args)`** / **`cmake_language(EVAL CODE …)`** — invokes a command whose name is dynamic, or runs arbitrary cmake. In yc these are `cmake_call` / `cmake_eval`.
5. **`function(${dynamic_name} …)` / `macro(${dynamic_name} …)`** — defines a command whose name is computed at runtime (non-literal name field at the typed IR level).

The wellform pass calls these "opening constructs". When the file contains
**any** opening construct, an unknown command name could plausibly come from
one of them, so the check stays at **warning** class — visible in Problems
but not blocking compilation. Suppress noisy true-positives with `yc_raw '…'`
(the explicit escape) or by defining the helper in-file.

When the file has **no** opening construct, the command set is statically
closed: every legal call is in `Yc_primitives.command_names` or declared as
`function`/`macro` in the same file. An unknown name in that world MUST be a
typo. The check escalates to **fatal** — `compile` exits 1, the LSP shows
an error squiggle, the CLI gives a "did you mean fun/function/macro?" hint.

### Worked examples (the typo class)

These are the test cases in [`test_yc_wellform.ml`](../../test/test-yelu/test_yc_wellform.ml)
under the `unknown-command (closed/open world)` group:

```text
# Closed world (no opening construct) — typo is FATAL.
funnn join(result_var) (...)
→ yelu compile: unknown command "funnn" — no in-file function/macro by that name
   and no opening construct (include/find_package/add_subdirectory/cmake_call/
   dynamic fun-name) that would introduce one. Did you mean fun/function/macro?

# Closed world, declared in-file → silent.
fun helper(x) ( $x := 'v' ); helper 'OUT'

# Closed world, forward-ref (declared after the call) → silent.
helper 'OUT'; fun helper(x) ( $x := 'v' )
# (collect_defined_names is whole-program, so order doesn't matter.)

# Closed world, typed primitive → silent.
project 'fmt' Cxx

# Closed world, external cmake-stdlib → FATAL.
cmake_parse_arguments 'P' '' '' '' $ARGN
# Fix: either wrap in `yc_raw '…'` (preserves it as raw cmake), or add an
# `include`/`find_package` somewhere if that's what brought it in.

# Open world (include opens it) → unknown is a warning, not fatal.
include 'Helpers.cmake'; mystery_command 'x'
```

### Surfacing channels

| Path | Behaviour |
|---|---|
| `yelu compile <file>` (per-file CLI) | closed-world unknowns are fatal (`exit 1`); open-world unknowns print `[yelu][unknown-command]` to stderr |
| `yelu compile-corpus probes/fmt` (build-time gate) | Unknown_command is **silent**, even closed-world. The gate's contract is "no Positional_form / no Enum_shadow regressions"; the closed-world strictness lives in single-file `compile` instead. This preserves gate behaviour while the corpus migrates external calls to `yc_raw '…'`. |
| LSP (in-editor Problems panel) | wellform runs via `Yc_driver.wellform = Yc_wellform.check_all`, so both warning and fatal classes appear; the LSP maps severity to LSP `DiagnosticSeverity`. |

### Follow-ups (parked)

- **"Did you mean X?"** — Levenshtein distance from the unknown name against `command_names ∪ defined_names`. Cheap to add to the warning text.
- **Cmake-stdlib name index** — `tool/cmake_text/` already has a 935-callable index of cmake's `Modules/`. Loading it into a separate `cmake_stdlib_names` set in wellform would silence the legitimate-but-noisy `cmake_parse_arguments` / `check_language` / `cuda_add_executable` class without forcing `yc_raw`.
- **Cross-file collect** — for a multi-file project, walking `include`/`add_subdirectory` targets to gather their `function`/`macro` declarations would eliminate the false-positive class on real corpus projects. Today the LSP sees one file at a time.
- **Diagnostic span** — `Unknown_command` currently carries only the name. Adding the offending token's span (the located lexer infrastructure already in use for parse-error diagnostics) lets the LSP highlight the exact identifier instead of underlining the whole file.

## 8. Related

- [`../yelu_cmake/driver.md`](../yelu_cmake/driver.md) — the uniform
  per-language op interface the LSP plugs into.
- [`concrete_syntax_parser.md`](concrete_syntax_parser.md) — the
  implemented two-pass `yc` parser this builds on.
- [`../yelu_cmake/ycn_concrete_syntax.md`](../yelu_cmake/ycn_concrete_syntax.md)
  — surface-syntax design notes for `ycn`; the generalization target.
- [`lang_design.md`](lang_design.md), [`typed_design.md`](typed_design.md)
  — language-design tradition and the (retired) typed-checking design
  that Y17 / ecosystem-semantic revisit.
- [`../yelu_cmake/status.md`](../yelu_cmake/status.md) — the behavior-level
  oracle (the other half) and the forward roadmap.
