---
name: Phase 2a parser-direct-to-Yelu1 — in progress
description: yelu_parse_y1.ml status and next-up control-flow batch; mimic legacy, no new syntax
type: project
---

**As of 2026-05-11.** Phase 2a builds a parallel parser (`src/langs/yelu_tiny/yelu_parse_y1.ml`) that produces Yelu1 IR directly. The legacy parser (`src/langs/yelu/lang_yelu_parse.ml`) stays untouched until all families are migrated; only then does it retire.

## What's done

11 of 12 families covered (~1,450 LOC in `yelu_parse_y1.ml`), 84 pair-wise oracle tests byte-identical against legacy. All commits this session: `f12758b`, `81a51eb`, `d036fb0`, `9f8df82`, `541405a`, `4356fa0`.

Families: var, string, list, path, file, target, dir, test, property, find, install, cmake_op-scalar.

The pair-wise oracle is `assert_parse_y1_equiv` in `test/test-yelu/test_yelu_cmake_parse.ml`. It compares
`source → Lang_yelu_parse → bridge → emit_ast → text` against
`source → Yelu_parse_y1 → emit_ast → text` and asserts byte-equal cmake.

**Why:** Verify Phase 2 design end-to-end without touching the legacy path; surface real legacy bugs.

**How to apply:** When extending `yelu_parse_y1`, the dispatcher is `p_stmt_inner_y1` — add a `p_<family>_command_y1` function and wire it into the chain. Use the `collect_command_args` helper for positional + `~name:value` kwarg shapes; use `out_var_y1` for the legacy `"?"` sentinel when `~out` is missing.

## What's next: cmake_op control flow (~250 LOC, 1 commit)

The last family. **Mimic the legacy parser; no new syntax.** Approach approved 2026-05-11.

Pieces to add to `yelu_parse_y1.ml`:

1. **`p_cond_y1`** — condition expression parser for if/while. New (separate from `p_expr_y1`). Maps ~25 cond ctors:
   - `EBool`, `ENot`, `EAnd`, `EOr`
   - `EIntLess/Equal/Greater/LessEqual/GreaterEqual` and string-comparison versions
   - `ECmakeStringEqual`, `ECmakeVersionLess/Greater/Equal/LessEqual/GreaterEqual`
   - `ECmakeVarDefined`, `ECmakeTargetExists`, `ECmakeFileExists`
   - `ECmakeMatches`, `ECmakeInList`, `ECmakeIsDirectory`, `ECmakeIsAbsolute`, `ECmakePolicyCheck`
2. **`p_let_y1`** — `let var = expr in body`. **Build `ELet { var; value; body }` directly** (expression-shaped). This is naturally cleaner than legacy's sequence-shaped `Ylet`. Win for free.
3. **`p_if_y1`** — `if cond then stmt [else stmt]` → `ECmakeIfStmt { cond; then_; else_ }`
4. **`p_function_y1` / `p_macro_y1`** — `fun name(args) ( body )` / `macro name(args) ( body )` → `ECmakeFunction` / `ECmakeMacro`. Note: lexer aliases `fun` to FUNCTION token.
5. **`p_foreach_y1`** — `foreach var in items ( body )` plus `RANGE n..m`, `IN LISTS`, `IN ZIP_LISTS` variants → `ECmakeForeach` / `ECmakeForeachRange` / `ECmakeForeachInList` / `ECmakeForeachZip`
6. **`p_while_y1`** — `while cond ( body )` → `ECmakeWhile`
7. **`p_apply_y1`** — bare-IDENT function call `name(args)` → `ECmakeApply`. Tricky because any IDENT could be a function call; needs to be tried last (or filtered to known forms).
8. **`p_block_extended_y1`** — extends current `p_block_y1` to accept all the new dispatchers (already structured for recursion via `p_stmt_inner_y1`).
9. **Flow keywords:** `Yc_break` / `Yc_continue` / `Yc_return` map to `ECmakeBreak` / `ECmakeContinue` / `ECmakeReturn`. Just keyword consumers.

Order tip: control-flow dispatchers must come *before* `p_apply_y1` in the chain since both start with IDENT.

## Legacy bugs deferred (don't replicate; omit from oracle)

- `( set NAME val )` form: cvar name coerced via fallback to `"?"` due to narrow Yexpr_string match in bridge
- `( policy_set "CMP0048" )` form: policy id only matches single-quoted Ycs_string; double-quoted (PATH) falls through to empty default
- Both: same shape — narrow Yexpr_string pattern in legacy dispatcher

## Verification

```sh
dune build
dune test                            # watch [emit_ast oracle] line: 194/194
dune build --force @test/test-runcmake/runcmake-yelu   # 50/50 pairs
```

Pair-wise oracle output: lines like `[OK] t<family>-y1` for each pair-wise test. Failures show legacy text on Expected line and new-parser text on Received.

## Notable architecture observation (deferred cleanup, not blocker)

Tiny IR has both `ECmakeFileRead` and `ECmakeFileReadFull` — both lower to the same `Lang_cmake.File_read` cmake AST. Byte oracle blind to this drift. Phase 2 cleanup item.
