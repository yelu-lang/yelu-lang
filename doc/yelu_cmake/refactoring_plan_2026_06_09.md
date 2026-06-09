# yelu_cmake Refactoring Plan — 2026-06-09

Systematic audit of `src/langs/yelu/*.ml` for misplaced functions,
duplicated conversion tables, and functions that should be lifted into
shared modules.

## P0 — Quick Wins (clear-cut, low risk)

### 1. `message_mode_of_string` — duplicated in 3 files

Three different message-mode conversion tables exist across two layers:

| File | Line | Direction | Cases |
|------|------|-----------|-------|
| `yelu_cmake_utils.ml` | 202 | `string → Lang_cmake.message_mode` | 13 |
| `yelu_cmake_emit.ml` | 182 | `string → C.message_mode` | 16 |
| `yelu_cmake_from_emit.ml` | 356 | `C.message_mode → string` | 12 |

The reverse direction (`enum → string`) already has a canonical
implementation at `Lang_cmake_strings.of_message_mode` (line 64).

**Plan:**
- Pick the emit version (16 cases, most complete) as the canonical
  `string → C.message_mode` converter.
- Move it to `Lang_cmake_strings` as `of_string_message_mode` (or
  keep it in `yelu_cmake_utils.ml` and reference from both emit and
  parser).
- Delete the `yelu_cmake_utils.ml` version (13 cases, missing
  CHECK_PASS/CHECK_FAIL/DEPRECATION/NONE).
- `yelu_cmake_from_emit.ml`'s `message_mode_to_string` should use
  `Lang_cmake_strings.of_message_mode` instead of its own table.

**Impact:** 2 duplicate tables removed. Single source of truth.

### 2. `version_of_string` — duplicated in 2 files

| File | Line | Direction |
|------|------|-----------|
| `Lang_cmake_utils.ml` | 4 | `string → C.version` |
| `yelu_cmake_emit.ml` | 199 | `string → C.version` |

Both parse a version string into `C.version`. The cmake-layer one
handles `..` range syntax (e.g. `3.8...3.28` → `3.8`), while the
emit one does simple major.minor.patch parsing.

**Plan:**
- Make `yelu_cmake_emit.ml` use `Lang_cmake_utils.version_of_string`
  (or merge the `..` handling into the cmake-layer version).
- Delete the emit copy.

**Impact:** 1 duplicate removed. Consistent version parsing.

### 3. `visibility_of_expr_y1` in parser — enum recognition in parse code

`yelu_parse.ml:717` has:

```ocaml
let visibility_of_expr_y1 = function
  | EVar "PUBLIC" | EString "PUBLIC" -> Some Vis_public
  | EVar "PRIVATE" | EString "PRIVATE" -> Some Vis_private
  | EVar "INTERFACE" | EString "INTERFACE" -> Some Vis_interface
  | _ -> None
```

This is a string→visibility-enum table for the parser. The utils module
already has `vis_of_kind` (line 343: `Lang_cmake.visibility → yelu
visibility`) and `visibility_of_kind` (line 337: `Lang_cmake.visibility
→ string`).

**Plan:**
- Move `visibility_of_expr_y1` to `yelu_cmake_utils.ml` (renamed to
  `visibility_of_expr`).
- Reference it from the parser.
- Same treatment for `group_by_visibility_y1` (line 725) — this is
  parser grouping logic that uses the visibility table; keep in parser
  but have it call the shared table.

**Impact:** String→enum table lifted out of parser. Matches the
`cmake_name_of_yelu` precedent.

## P1 — Worth Doing (moderate risk, clear benefit)

### 4. String escaping — 3 implementations of the same algorithm

| File | Line | Function |
|------|------|----------|
| `yelu_emit_main.ml` | 12 | `escape` — buffer-based, handles `"` → `\"` and `\` → `\\` |
| `yelu_cmake_emit_debug.ml` | 35 | `escape_quoted` — `String.substr_replace_all`-based, same escapes |
| `lang_cmake_pp.ml` | — | `quoted()` — wraps in `"..."` and escapes internal `\` and `"` |

Three implementations of `escape_cmake_string : string → string`.
The pp version was recently fixed (commit `9041558`) to handle `\`
escaping; the other two may have the same fix independently.

**Plan:**
- Add `Lang_cmake_strings.escape_quoted : string → string` as the
  canonical implementation.
- Have `yelu_emit_main.escape`, `yelu_cmake_emit_debug.escape_quoted`,
  and `lang_cmake_pp.quoted` all delegate to it.
- `yelu_emit_main.escape` becomes a one-line call to
  `Lang_cmake_strings.escape_quoted`.

**Impact:** 3→1 for string escaping. Fixes applied once, everywhere.

### 5. `bool_literal_of_string` — isolated in `yelu_cmake_from_emit.ml`

`yelu_cmake_from_emit.ml:220` has a case-insensitive cmake bool-literal
recognition table (`TRUE/ON/YES/Y/1 → true`, `FALSE/OFF/NO/N/0/IGNORE/
NOTFOUND → false`). Related to `yelu_cmake.expect_bool` (line 844)
which does the same at eval time for `VString` values.

**Plan:**
- Move `bool_literal_of_string` to `yelu_cmake.ml` (next to
  `expect_bool`), rename to `bool_of_string_opt` for consistency.
- Reference from `yelu_cmake_from_emit.ml`.
- Future (Y17): unify with eval-side `expect_bool` so there's one
  place that decides what strings are truthy.

**Impact:** Bool recognition table accessible outside the from_emit
bridge. Single source of truth for parse-time bool recognition.

### 6. Enum→string tables in `yelu_cmake_utils.ml` that could live in `Lang_cmake_strings`

`yelu_cmake_utils.ml` has several small enum→string tables:

| Function | Line | Maps |
|----------|------|------|
| `library_type_name` | 349 | `Lang_cmake.library_type → string` |
| `yc_include_guard` scope | 228 | `Lang_cmake.include_guard_scope → string` |

The cmake layer already has `Lang_cmake_strings` as the canonical
home for `of_*` enum→string converters. These two tables are the same
pattern.

**Plan:**
- Move `library_type_name` to `Lang_cmake_strings.of_library_type`.
- Inline the `yc_include_guard` scope mapping into
  `Lang_cmake_strings.of_include_guard_scope`.
- Reference from utils.

**Impact:** All cmake-enum→string converters live in one module.

## P2 — Design Discussion (higher effort, needs planning)

### 7. Parser family dispatch split (`yelu_parse.ml`, ~2121 lines)

Currently one file with 12 family parsers + dispatch + helpers. The
code quality review recommended splitting by family. This is a
significant refactor — the families share helper functions (`str_of`,
`collect_command_args`, `split_by_keywords`, `fallback_to_raw`) and
mutually recursive dispatch.

**Approach options:**
- A. Extract per-family `.ml` files, keep shared helpers in a
  `yelu_parse_util.ml`.
- B. Keep the file whole but group sections with clear banner comments
  and a table of contents.
- C. Wait until parser stabilizes (z3/llvm probes done, strict mode
  designed) before splitting.

**Recommendation:** Option C — defer. The parser is still growing
and the split would add friction to each new command family.

### 8. CLI driver split (`yelu.ml`, ~600 lines)

The code quality review recommended moving reusable logic into library
modules. This is independent of the yelu language layer — it's about
the CLI binary. Consider when the driver gains more subcommands.

**Recommendation:** Defer until the driver grows another ~200 lines
or gains a second major subcommand.

### 9. Escape registry

Track every `ECmakeRaw` / `ECmakeApply` / raw fallback site with
reason, location, and test coverage. The code quality review
recommended this for scaling to z3/llvm.

**Recommendation:** Start as a markdown file in `doc/yelu_cmake/`,
not code. Code-level tracking (adding `reason` fields to constructors)
should wait for Y17 typing redesign.

## Not Actionable (already clean or inherent)

- **`yc_primitives.ml`** — well-designed single source of truth for
  command names and reserved identifiers. No changes needed.
- **`yelu_cmake_convert.ml`** (1820 lines) — `to_normal` / `from_normal`
  are one large mutually-recursive function pair. Splitting would
  create ordering dependencies; the current structure is idiomatic
  for this kind of syntactic rewrite.
- **`yelu_cmake_eval.ml` + `yelu_cmake_normal_eval.ml`** — the
  cascading `match` through `eval_case` fragments is verbose but
  mechanically regular. No misplaced functions.
- **`yc_wellform.ml`** — self-contained pure walk. Clean.
- **`yelu_lexer.ml`** — clean, single concern.
- **`yelu_cmake.ml`** (890 lines) — IR type definitions + core
  functions (`expect_bool`, `substitute`). Reasonable cohesion.

## Summary

| Priority | Items | Files touched | Lines changed (est.) |
|----------|-------|---------------|---------------------|
| P0 | #1–3 (message_mode, version, visibility) | 4–5 | ~80 removed, ~40 added |
| P1 | #4–6 (escaping, bool_literal, enum tables) | 5–6 | ~50 removed, ~30 added |
| P2 | #7–9 (parser split, driver split, escape registry) | — | design only |

**Recommended order:** P0 items first (all three are independent and
can be done in one session), then P1 items one at a time.
