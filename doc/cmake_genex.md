# Yelu Genex Design Notes

## Current State

The `yelu_genex` type in `lang_yelu.ml` covers ~15 operators:

| Constructor | Genex |
|---|---|
| `Yge_config s` | `$<CONFIG:s>` |
| `Yge_not g` | `$<NOT:g>` |
| `Yge_and gs` | `$<AND:g1,g2,...>` |
| `Yge_or gs` | `$<OR:g1,g2,...>` |
| `Yge_if (c,t,f)` | `$<IF:c,t,f>` |
| `Yge_bool s` | `$<BOOL:s>` |
| `Yge_target_file t` | `$<TARGET_FILE:t>` |
| `Yge_target_file_dir t` | `$<TARGET_FILE_DIR:t>` |
| `Yge_target_property (t,p)` | `$<TARGET_PROPERTY:t,p>` |
| `Yge_install_interface g` | `$<INSTALL_INTERFACE:g>` |
| `Yge_build_interface g` | `$<BUILD_INTERFACE:g>` |
| `Yge_strequal (a,b)` | `$<STREQUAL:a,b>` |
| `Yge_lower_case g` | `$<LOWER_CASE:g>` |
| `Yge_upper_case g` | `$<UPPER_CASE:g>` |
| `Yge_compile_language l` | `$<COMPILE_LANGUAGE:l>` |
| `Yge_platform_id id` | `$<PLATFORM_ID:id>` |
| `Yge_raw s` | `$<s>` — escape hatch, user supplies full inner content |

`yge : yelu_genex -> yarg` serializes via `genex_to_string` → `Ycs_val` → bare cmake string.
`ystr_raw s` is the coarser escape: any cmake text passed through as `Bare s`.

## Gap Analysis — `Tests/GeneratorExpression/`

`Tests/GeneratorExpression/CMakeLists.txt` (504 lines) is cmake's own genex regression
suite: 5 `add_custom_target(check-partN ALL COMMAND cmake -P check-partN.cmake ...)` blocks,
each passing ~20–80 genex expressions as `-Dvar=$<...>` arguments, verified by external
`check-partN.cmake` assertion scripts.

Operators used in the test that are absent from the typed DSL:

| Missing | Example | Note |
|---|---|---|
| `$<0:x>` / `$<1:x>` | `$<0:nothing>` | degenerate literal-bool condition |
| `$<IN_LIST:a,list>` | `$<IN_LIST:a,a$<SEMICOLON>b>` | |
| `$<ANGLE-R>`, `$<COMMA>`, `$<SEMICOLON>`, `$<QUOTE>` | `$<ANGLE-R>` | escape genex |
| `$<JOIN:list,sep>` | `$<JOIN:$<TARGET_OBJECTS:o>,\n>` | |
| `$<LIST:FILTER/SORT/APPEND,...>` | `$<LIST:FILTER,src,INCLUDE,.*\.c$>` | cmake 3.17+ |
| `$<TARGET_NAME:tgt>` | `$<TARGET_NAME:tgt,ok>` | |
| `$<TARGET_OBJECTS:tgt>` | `$<TARGET_OBJECTS:objlib>` | |
| `file(GENERATE OUTPUT ... CONTENT ...)` | — | not in yelu API |

Additional infra blockers: 5 external `check-partN.cmake` runtime assertion scripts +
`CMP0044/` subdir — all would need `~files` entries.

`Yge_raw` can spell any missing operator today, but degrades the test to "can yelu emit
opaque strings" — no static checking, no typed structure. Not a meaningful exercise.

## Key Insight — Escape Genex Are a Symptom of Flat Syntax

`$<COMMA>`, `$<ANGLE-R>`, `$<SEMICOLON>`, `$<QUOTE>` exist solely because cmake genex
is a flat string language: commas separate arguments, `>` closes the expression, `;` is
a list separator, and `"` interacts with quoting. In a typed genex tree these characters
appear structurally in the tree and the serializer handles escaping at emit time — the
user never writes `$<COMMA>`. This is the cleanest argument for a typed DSL: it
eliminates an entire class of operator that exists only to work around the syntax.

## Design Direction

A full typed genex layer should:

1. **Add missing common operators**: `Yge_join`, `Yge_in_list`, `Yge_target_objects`,
   `Yge_target_name`, `Yge_list` (cmake 3.17+ list manipulation genex).

2. **Eliminate escape genex structurally**: commas, `>`, `;`, and `"` inside a
   `yelu_genex` tree node are structural data — the `genex_to_string` serializer emits
   `$<COMMA>` / `$<ANGLE-R>` / `$<SEMICOLON>` / `$<QUOTE>` automatically when those
   characters appear in string leaves. The user never writes them explicitly.

3. **Handle `$<0:x>` / `$<1:x>`**: these are `Yge_if (Yge_raw "0", x, Yge_raw "")` and
   `Yge_if (Yge_raw "1", x, Yge_raw "")` — not worth dedicated constructors. Or collapse
   into `Yge_cond of bool * yelu_genex`.

4. **Add `file(GENERATE ...)`**: a new `Yc_file_generate` node. Genex are only evaluated
   at build time, so `file(GENERATE)` content is the primary use-site for `$<JOIN:...>`,
   `$<TARGET_OBJECTS:...>`, etc.

5. **Retain `Yge_raw`** as a forward-compatibility escape for operators not yet in the
   typed layer.

## Status

`Tests/GeneratorExpression/` is skipped as a build test. Rationale: the test's value
is exhaustive coverage of cmake's genex evaluator, which doesn't map to what the yelu
typed DSL demonstrates. The right trigger for implementing the typed genex layer is when
a real yelu program (e.g., an OBJECT library or multi-config build) needs `JOIN`,
`TARGET_OBJECTS`, or `file(GENERATE)` — not when coverage metrics call for it.
