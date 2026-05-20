# Bar #3-lite audit kit — per-parser contracts + audit prompt

> Companion to [`bar3_lite_report.md`](bar3_lite_report.md). The report
> establishes the claim, oracle, and current results; this document is
> the surface a reviewer attacks the **per-parser contracts**.
>
> **Scope.** 30 cmake builtins modeled in
> [`tool/cmake_roundtrip/print2.ml`](../../tool/cmake_roundtrip/print2.ml),
> dispatched in `parse_cmd` (some via shared helpers like
> `parse_find_var_names` which backs both `find_program` and
> `find_path`). Each parser maps a Stage-1 untyped command into a
> `Lang_cmake.exp` constructor, then `Lang_cmake_pp` reprints.
>
> A parser is correct iff:
>
> 1. **STRUCT preservation** — every accept-set input round-trips
>    such that tree-sitter re-extracts the same `(name, args)`
>    sequence; every bail-set input takes the generic
>    `Lang_cmake.Apply` path and preserves the sequence.
> 2. **Typed-IR classification** — for accept-set inputs, the
>    chosen `Lang_cmake.exp` constructor and field assignments
>    actually correspond to what the source meant. **STRUCT can
>    pass while typed meaning is misclassified** (e.g. an option
>    keyword dumped into the sources list of `Add_executable`).
>    This is the major audit lesson — see the Appendix at the end
>    of this document for the concrete examples (2026-05-20 review)
>    that motivated the dual axis.

## 1. How to use this kit

Three artifacts together support a structured audit:

1. **This document** — per-parser contract sheet (§ 5) and the
   prompt template (§ 3) for delegating to a reviewer (LLM or human).
2. The **report** [`bar3_lite_report.md`](bar3_lite_report.md) for
   claim-level material the reviewer needs as background.
3. The **single-file reproducer recipe** (§ 4) so any finding can
   be pinned with a one-line cmake snippet.

The intended audit workflow:

```
read prompt (§ 3) → pick parsers (or all) → for each:
  - read the contract row (§ 5)
  - read the parser source at the cited line
  - read the IR ctor at the cited line
  - read the printer arm at the cited line
  - construct accept-set inputs → check round-trip via reproducer
  - construct bail-set inputs   → check generic fallback via reproducer
  - report findings as (parser, severity, reproducer-snippet)
```

## 2. Vocabulary

- **Accept set.** Inputs the parser maps to `Some Lang_cmake.exp e`.
  Each must satisfy: `tree_sitter(print(e)) = tree_sitter(input)` at
  the command/arg sequence level (STRUCT oracle), AND the chosen
  `e` correctly classifies the source semantics (typed-IR check —
  no keyword tokens dropped into the wrong field, no silently
  discarded sub-clauses).
- **Bail set.** Inputs the parser returns `None` on. Each must
  satisfy: the generic fallback (`Lang_cmake.Apply { name; args }`
  emitted via the production `Lang_cmake_pp` Apply arm) is
  **STRUCT-faithful** — tree-sitter re-extracts the same
  `(name, args)` sequence. It is **not** byte-faithful: the
  production printer may choose a multi-line layout for some
  argument lists.
- **Accept-set hole.** An input in the accept set whose typed path
  loses information or reorders args — i.e. the parser should have
  bailed but didn't. Severity: **major** (the STRUCT oracle could
  miss this on the corpus but a hand-crafted test exposes it).
- **Bail-set overreach.** An input in the bail set that *could*
  safely have been typed but wasn't. Severity: **minor** —
  byte-faithful via Apply, but unnecessarily generic.
- **IR-side gap.** A field the IR has but the printer drops, or a
  shape cmake supports but the IR doesn't model. Severity:
  **major** if it forces a parser to bail on a common shape.

## 3. Audit prompt template (paste-ready)

Use this verbatim when delegating to an LLM auditor. Replace `<…>`
placeholders with the scope of work.

> **Task.** Audit the per-parser correctness of cmake builtins
> modeled in `tool/cmake_roundtrip/print2.ml`. For each parser
> listed in [`bar3_lite_audit_kit.md`](doc/yelu_cmake/bar3_lite_audit_kit.md)
> § 5 within scope `<all | parsers X, Y, Z | lines L1..L2>`, do the
> following:
>
> 1. Read the parser source at the cited `print2.ml` line.
> 2. Read the IR constructor at the cited `lang_cmake.ml` line.
> 3. Read the printer arm at the cited `lang_cmake_pp.ml` line.
> 4. For each *accept-set* shape listed in the contract row, verify
>    that the printer's emit for the resulting `Lang_cmake.exp` value
>    would re-extract (via tree-sitter) the same `(name, args)`
>    sequence as the input. Flag any accept-set hole — i.e. a typed
>    path that drops/reorders information.
> 5. For each *bail-set* condition, verify the parser actually
>    returns `None` on a representative input. Flag any bail-set
>    overreach — a condition that could safely be typed.
> 6. Identify *IR-side gaps* not yet flagged in the contract row.
>
> **Report format.** Per finding:
>
> ```
> parser: parse_<name>
> severity: major | minor
> kind: accept-set-hole | bail-set-overreach | ir-gap
> reproducer:
>   <cmake snippet, single line preferred>
> expected: round-trip via <modeled|generic> path
> actual:   <what the harness produces, demonstrating the bug>
> suggested fix:
>   <one-line code-level direction, no patches needed>
> ```
>
> **Background.** [`bar3_lite_report.md`](doc/yelu_cmake/bar3_lite_report.md)
> describes the round-trip oracle, the modeled/generic/other coverage
> tally, and the deliberate scope limits. Read § 2 (oracles) and § 5
> (scope) before scoring severity. The STRUCT oracle is load-bearing;
> FORMAT is informational.
>
> **Reproducer.** Use the single-file recipe in
> [`bar3_lite_audit_kit.md`](doc/yelu_cmake/bar3_lite_audit_kit.md) § 4
> to confirm any finding before reporting.

## 4. Reproducer recipe

Build once:

```sh
# The project's tree-sitter / tree-sitter-cmake / gersemi live in a
# project-local venv. Put it on PATH so `python3` can import the
# tree-sitter bindings and the harness can find gersemi.
export PATH=/home/red/.venvs/default/bin:$PATH

dune build tool/cmake_roundtrip/print2.exe
```

Round-trip a single hand-crafted snippet:

```sh
echo 'find_package(Foo COMPONENTS A REQUIRED)' \
  | python3 tool/cmake_roundtrip/parse.py - \
  | STAGE2_COVERAGE=1 _build/default/tool/cmake_roundtrip/print2.exe
# stdout: the reprinted text (the round-trip)
# stderr: [stage2] modeled=N generic=N other=N
```

Read off:

- `modeled=1` and stdout matches input shape → typed-path round-trip
  worked.
- `modeled=0 generic=1` and stdout matches input shape → bail-set
  fallback through `Lang_cmake.Apply` worked.
- stdout differs from input (commands or args dropped/reordered) →
  STRUCT failure. The parser is the bug locus iff `modeled=1`;
  otherwise the bug is in the Apply path or the IR.

Comparing exact byte differences:

```sh
diff <(echo 'find_package(Foo COMPONENTS A REQUIRED)') \
     <(echo 'find_package(Foo COMPONENTS A REQUIRED)' \
        | python3 tool/cmake_roundtrip/parse.py - \
        | _build/default/tool/cmake_roundtrip/print2.exe)
```

For an exhaustive corpus-level run before claiming "fixed":

```sh
bash tool/cmake_roundtrip/test_corpus.sh /path/to/corpus
```

## 5. Parser contract sheet

Coverage by stage (30 dispatched commands, 15 + 8 + 7):

| stage | count | parsers |
| --- | ---: | --- |
| original Stage 2 | 15 | `cmake_minimum_required`, `project`, `set`, `message`, `configure_file`, `add_executable`, `add_library`, `target_link_libraries`, `target_include_directories`, `target_compile_definitions`, `target_compile_options`, `target_compile_features`, `option`, `include`, `add_subdirectory` |
| Stage 2-b | 8 | `unset`, `add_dependencies`, `find_package`, `get_filename_component`, `set_target_properties`, `add_custom_target`, `list`, `string` |
| Stage 2-c | 7 | `return`, `include_directories`, `find_program`, `find_path`, `install`, `add_custom_command`, `file` |

(Helper functions like `parse_find_var_names` back two dispatched
commands; subcommand dispatchers like `parse_list` / `parse_string`
/ `parse_file` enumerate many cmake subcommands within a single
dispatched name.)

Conventions:

- File line numbers are as of commit `9cede13` (post-audit
  response). Use `grep -n "^let parse_<name>"` if stale.
- "lossy IR field" means the IR carries the field but the printer
  drops it; the parser must bail on inputs that would populate it.

### 5.1 cmake_minimum_required

- **Location**: [`print2.ml:210`](../../tool/cmake_roundtrip/print2.ml#L210)
- **IR ctor**: [`Cmake_minimum_required` at `lang_cmake.ml:599`](../../src/langs/cmake/lang_cmake.ml#L599)
- **Printer arm**: [`lang_cmake_pp.ml:781`](../../src/langs/cmake/lang_cmake_pp.ml#L781)
- **Accepts**:
  - `cmake_minimum_required(VERSION <ver>)` with `<ver>` matching
    `MAJ[.MIN[.PATCH]]` (numeric, dot-separated, no `...` range).
- **Bails on**:
  - Non-numeric `<ver>` (e.g. `${VAR}`) — `version_of_string_opt`
    returns `None`.
  - **Range form `<min>...<max>`** — the printer drops `max`
    (`max = _` at `lang_cmake_pp.ml:781`), so a typed round-trip
    would silently lose the upper bound. **Parser now detects
    `...` in version and bails** (was previously an accept-set
    hole; fixed 2026-05-20, commit `<TBD>`).
  - Trailing `FATAL_ERROR` / other tokens — not in IR.
- **Known gaps**: IR's `max : version option` is dead from the
  printer's perspective. Either wire it up in the printer or
  remove it from the IR.

### 5.2 project

- **Location**: [`print2.ml:240`](../../tool/cmake_roundtrip/print2.ml#L240)
- **IR ctor**: [`Project` at `lang_cmake.ml:875`](../../src/langs/cmake/lang_cmake.ml#L875)
- **Printer arm**: [`lang_cmake_pp.ml:966`](../../src/langs/cmake/lang_cmake_pp.ml#L966)
- **Accepts**:
  - `project(<name>)`
  - `project(<name> [VERSION <ver>] [LANGUAGES <lang>...])`
  - VERSION must match numeric `MAJ[.MIN[.PATCH]]`.
- **Bails on**:
  - Non-numeric VERSION (e.g. `${Z3_VERSION_FROM_FILE}`).
  - **`DESCRIPTION <s>` and `HOMEPAGE_URL <s>`** — IR has these
    fields but the printer always quotes them (`pp_string_quoted`),
    so a source `DESCRIPTION desc` would re-emit as
    `DESCRIPTION "desc"` and `arg_of_raw` would classify those as
    different `arg` shapes (Bare vs Quoted). Bail until the
    printer's quoting policy is reconciled with bare-source
    inputs. (Was previously an accept-set hole that silently
    dropped both fields; fixed 2026-05-20.)
  - Unknown keyword (e.g. `META_LICENSES`).
- **Known gaps**: LANGUAGES previously round-tripped reversed
  due to a double-reverse bug in `split_keywords` — `langs` was
  built forward and then `List.rev`'d at the return. Fixed
  2026-05-20: LANGUAGES is consumed as the remaining-tokens
  list and returned in source order.

### 5.3 set

- **Location**: [`print2.ml:277`](../../tool/cmake_roundtrip/print2.ml#L277)
- **IR ctor**: [`Set` at `lang_cmake.ml:421`](../../src/langs/cmake/lang_cmake.ml#L421)
- **Printer arm**: [`lang_cmake_pp.ml:566`](../../src/langs/cmake/lang_cmake_pp.ml#L566)
- **Accepts**:
  - `set(<var> <val>...)`
  - `set(<var> <val>... PARENT_SCOPE)`
- **Bails on**:
  - `set(<var> CACHE <type> <docstring> [FORCE])` — cache form not
    handled; goes through Apply.
  - `set(ENV{<var>} <val>)` — env-var form.
- **Known gaps**: cache / env namespaces are documented as future
  work in `status.md`.

### 5.4 message

- **Location**: [`print2.ml:310`](../../tool/cmake_roundtrip/print2.ml#L310)
- **IR ctor**: [`Message` at `lang_cmake.ml:535`](../../src/langs/cmake/lang_cmake.ml#L535)
- **Printer arm**: [`lang_cmake_pp.ml:654`](../../src/langs/cmake/lang_cmake_pp.ml#L654)
- **Accepts**:
  - `message([<mode>] <text>...)` — modes:
    STATUS / WARNING / SEND_ERROR / FATAL_ERROR / AUTHOR_WARNING /
    DEPRECATION / VERBOSE / DEBUG / TRACE / NOTICE / CHECK_START /
    CHECK_PASS / CHECK_FAIL.
- **Bails on**:
  - Bare (unquoted) text args — printer always emits quoted via
    `pp_string_quoted`, which would alter the shape.
  - Mixed bare and quoted text.
- **Known gaps**: `CONFIGURE_LOG` mode goes through a separate
  `Message_config_log` ctor not currently parsed.

### 5.5 configure_file

- **Location**: [`print2.ml:328`](../../tool/cmake_roundtrip/print2.ml#L328)
- **IR ctor**: [`Configure_file` at `lang_cmake.ml:619`](../../src/langs/cmake/lang_cmake.ml#L619)
- **Printer arm**: [`lang_cmake_pp.ml:783`](../../src/langs/cmake/lang_cmake_pp.ml#L783)
- **Accepts**:
  - `configure_file(<input> <output> [COPYONLY] [ESCAPE_QUOTES]
    [@ONLY] [NEWLINE_STYLE <style>])`
  - input/output must be bare (IR's `path : string` cannot carry
    quoting).
- **Bails on**:
  - Quoted input/output — would lose quoting.
  - `NO_SOURCE_PERMISSIONS` / `USE_SOURCE_PERMISSIONS` /
    `FILE_PERMISSIONS <perms>...` — permission_level handling not
    universally wired.
- **Known gaps**: cross-swap bug between `@ONLY` and
  `ESCAPE_QUOTES` in the printer was fixed in commit `6a6295a`
  (see report § 7).

### 5.6 add_executable

- **Location**: [`print2.ml:355`](../../tool/cmake_roundtrip/print2.ml#L355)
- **IR ctor**: [`Add_executable` at `lang_cmake.ml:682`](../../src/langs/cmake/lang_cmake.ml#L682)
- **Printer arm**: [`lang_cmake_pp.ml:975`](../../src/langs/cmake/lang_cmake_pp.ml#L975)
- **Accepts**:
  - `add_executable(<name> <src>...)` — no option keywords.
- **Bails on**:
  - **`WIN32` / `MACOSX_BUNDLE` / `EXCLUDE_FROM_ALL` tokens
    anywhere in the arg list** — the IR has an `options` field
    for these but the parser does not currently populate it.
    Without bailing, these tokens would be misclassified as
    sources (typed-IR bug even though STRUCT preserves). Fixed
    2026-05-20: parser bails when any reserved keyword is
    present.
  - `add_executable(<name> IMPORTED [GLOBAL])` — separate
    `Add_executable_imported` ctor (also bailed via keyword set).
  - `add_executable(<name> ALIAS <target>)` — separate
    `Add_executable_alias` ctor (also bailed via keyword set).
- **Known gaps**: imported / alias / option forms have IR ctors
  (and `Ae_win32` / `Ae_macos_bundle` option variants) but no
  parser populates them; mechanically addable.

### 5.7 add_library

- **Location**: [`print2.ml:372`](../../tool/cmake_roundtrip/print2.ml#L372)
- **IR ctor**: [`Add_library` at `lang_cmake.ml:689`](../../src/langs/cmake/lang_cmake.ml#L689)
- **Printer arm**: [`lang_cmake_pp.ml:998`](../../src/langs/cmake/lang_cmake_pp.ml#L998)
- **Accepts**:
  - `add_library(<name> [STATIC|SHARED|MODULE] [EXCLUDE_FROM_ALL]
    <src>...)`
- **Bails on**:
  - `add_library(<name> OBJECT <src>...)` — `Add_library_object`.
  - `add_library(<name> INTERFACE)` — `Add_library_interface`.
  - `add_library(<name> ALIAS <target>)` — `Add_library_alias`.
  - `add_library(<name> IMPORTED ...)` — `Add_library_imported`.
- **Known gaps**: same pattern as add_executable.

### 5.8 target_link_libraries

- **Location**: [`print2.ml:430`](../../tool/cmake_roundtrip/print2.ml#L430)
- **IR ctor**: [`Target_link_libraries` at `lang_cmake.ml:732`](../../src/langs/cmake/lang_cmake.ml#L732)
- **Printer arm**: [`lang_cmake_pp.ml:1034`](../../src/langs/cmake/lang_cmake_pp.ml#L1034)
- **Accepts**:
  - `target_link_libraries(<target> [PRIVATE|PUBLIC|INTERFACE] <lib>...)`
    with at least one visibility keyword.
  - **Mixed visibility groups**:
    `target_link_libraries(t PRIVATE a PUBLIC b)`. The printer
    emits each group as `KIND items` in order via
    `pp_args_with_kind`, so the round-trip is STRUCT-faithful.
    (Audit-review correction: an earlier contract row claimed
    mixed groups bailed; they do not. Verified 2026-05-20.)
- **Bails on**:
  - Plain (legacy) form `target_link_libraries(<target> <lib>...)`
    without any visibility — printer always emits a kind keyword,
    so a defaulted `PRIVATE` would inject one the source didn't
    have.
- **Known gaps**: plain form is STRUCT-faithful via Apply, but
  loses typed access to the link graph.

### 5.9 target_include_directories

- **Location**: [`print2.ml:560`](../../tool/cmake_roundtrip/print2.ml#L560)
- **IR ctor**: [`Target_include_directories` at `lang_cmake.ml:721`](../../src/langs/cmake/lang_cmake.ml#L721)
- **Printer arm**: [`lang_cmake_pp.ml:1039`](../../src/langs/cmake/lang_cmake_pp.ml#L1039)
- **Accepts**:
  - `target_include_directories(<target> [SYSTEM] [BEFORE|AFTER]
    {PRIVATE|PUBLIC|INTERFACE <dir>...}+)`
- **Bails on**:
  - Missing visibility keyword (legacy plain form).
  - SYSTEM positioned after visibility (printer emits it at the
    front).

### 5.10 target_compile_definitions

- **Location**: [`print2.ml:443`](../../tool/cmake_roundtrip/print2.ml#L443)
- **IR ctor**: [`Target_compile_definitions` at `lang_cmake.ml:712`](../../src/langs/cmake/lang_cmake.ml#L712)
- **Printer arm**: [`lang_cmake_pp.ml:1018`](../../src/langs/cmake/lang_cmake_pp.ml#L1018)
- **Accepts**: `target_compile_definitions(<t> {PRIVATE|PUBLIC|INTERFACE <def>...}+)`
- **Bails on**: plain form (no visibility), `-D…` raw prefixes if
  not normalized.

### 5.11 target_compile_options

- **Location**: [`print2.ml:455`](../../tool/cmake_roundtrip/print2.ml#L455)
- **IR ctor**: same family — see lang_cmake.ml.
- **Printer arm**: [`lang_cmake_pp.ml:1028`](../../src/langs/cmake/lang_cmake_pp.ml#L1028)
- **Accepts**: `target_compile_options(<t> [BEFORE] {PRIVATE|PUBLIC|INTERFACE <opt>...}+)`
- **Bails on**: plain form; non-standard BEFORE placement.

### 5.12 target_compile_features

- **Location**: [`print2.ml:474`](../../tool/cmake_roundtrip/print2.ml#L474)
- **IR ctor**: [`Target_compile_features` at `lang_cmake.ml:707`](../../src/langs/cmake/lang_cmake.ml#L707)
- **Printer arm**: [`lang_cmake_pp.ml:1023`](../../src/langs/cmake/lang_cmake_pp.ml#L1023)
- **Accepts**: `target_compile_features(<t> {PRIVATE|PUBLIC|INTERFACE <feature>...}+)`
- **Bails on**: quoted feature args (IR uses bare `string`).

### 5.13 option

- **Location**: [`print2.ml:497`](../../tool/cmake_roundtrip/print2.ml#L497)
- **IR ctor**: [`Option` at `lang_cmake.ml:537`](../../src/langs/cmake/lang_cmake.ml#L537)
- **Printer arm**: [`lang_cmake_pp.ml:658`](../../src/langs/cmake/lang_cmake_pp.ml#L658)
- **Accepts**:
  - `option(<var> <help>)`
  - `option(<var> <help> <value>)`
  - `<help>` must be quoted; `<value>` ∈ {ON, OFF, TRUE, FALSE, …}.
- **Bails on**:
  - Bare help text — printer always quotes.
  - `Bool true` printing as `True` (workaround: route ON/OFF/TRUE/…
    as `Var_exp` instead of `Bool`; see report § 7-adjacent notes).

### 5.14 include

- **Location**: [`print2.ml:513`](../../tool/cmake_roundtrip/print2.ml#L513)
- **IR ctor**: [`Include` at `lang_cmake.ml:395`](../../src/langs/cmake/lang_cmake.ml#L395)
- **Printer arm**: [`lang_cmake_pp.ml:539`](../../src/langs/cmake/lang_cmake_pp.ml#L539)
- **Accepts**:
  - `include(<file> [OPTIONAL] [RESULT_VARIABLE <v>] [NO_POLICY_SCOPE])`
- **Bails on**:
  - Unknown trailing keywords.
- **Known gaps**: `no_policy_scope` field was wrong-typed
  (`scope option`) before commit `13d813c`; now `bool`.
  `result_var` keyword emission was fixed in `6a6295a`.

### 5.15 add_subdirectory

- **Location**: [`print2.ml:535`](../../tool/cmake_roundtrip/print2.ml#L535)
- **IR ctor**: [`Add_subdirectory` at `lang_cmake.ml:700`](../../src/langs/cmake/lang_cmake.ml#L700)
- **Printer arm**: [`lang_cmake_pp.ml:991`](../../src/langs/cmake/lang_cmake_pp.ml#L991)
- **Accepts**:
  - `add_subdirectory(<src> [<bin>] [EXCLUDE_FROM_ALL] [SYSTEM])`
- **Bails on**: quoted src/bin (IR slot is bare `directory`).

### 5.16 unset

- **Location**: [`print2.ml:594`](../../tool/cmake_roundtrip/print2.ml#L594)
- **IR ctor**: [`Unset` at `lang_cmake.ml:432`](../../src/langs/cmake/lang_cmake.ml#L432)
- **Printer arm**: [`lang_cmake_pp.ml:584`](../../src/langs/cmake/lang_cmake_pp.ml#L584)
- **Accepts**:
  - `unset(<var>)`
  - `unset(<var> CACHE)`
  - `unset(<var> PARENT_SCOPE)`
- **Bails on**:
  - `unset(ENV{<var>})` — separate `Unset_env` ctor.
  - Both `CACHE` and `PARENT_SCOPE` together (invalid in cmake
    anyway).

### 5.17 add_dependencies

- **Location**: [`print2.ml:604`](../../tool/cmake_roundtrip/print2.ml#L604)
- **IR ctor**: [`Add_dependencies` at `lang_cmake.ml:681`](../../src/langs/cmake/lang_cmake.ml#L681)
- **Printer arm**: [`lang_cmake_pp.ml:1171`](../../src/langs/cmake/lang_cmake_pp.ml#L1171)
- **Accepts**: `add_dependencies(<target> <dep>)` — exactly one dep.
- **Bails on**: multiple deps (IR carries one). **Major IR gap.**
- **Known gaps**: cmake allows `add_dependencies(t a b c)`; the
  IR's single-`dep` field is wrong. Fix path: widen
  `Add_dependencies.dep` to `deps : depend list`.

### 5.18 find_package

- **Location**: [`print2.ml:614`](../../tool/cmake_roundtrip/print2.ml#L614)
- **IR ctor**: [`Find_package` at `lang_cmake.ml:518`](../../src/langs/cmake/lang_cmake.ml#L518)
- **Printer arm**: [`lang_cmake_pp.ml:761`](../../src/langs/cmake/lang_cmake_pp.ml#L761)
- **Accepts**:
  - `find_package(<name>)`
  - `find_package(<name> <ver>)`
  - `find_package(<name> [EXACT] [QUIET] [REQUIRED] [CONFIG|MODULE|NO_MODULE])`
  - `find_package(<name> ... [COMPONENTS <c>...] [OPTIONAL_COMPONENTS <c>...])`
- **Bails on**:
  - Top-level keyword (REQUIRED/EXACT/QUIET/CONFIG/…) appearing
    **after** COMPONENTS — printer would emit it before, reordering.
  - GLOBAL / BYPASS_PROVIDER / NO_POLICY_SCOPE / NO_*_PATH /
    REGISTRY_VIEW / HINTS / PATHS / PATH_SUFFIXES / NAMES — IR
    doesn't model these sublists.
- **Known gaps**: HINTS/PATHS/NAMES are real cmake but unmodeled.

### 5.19 get_filename_component

- **Location**: [`print2.ml:676`](../../tool/cmake_roundtrip/print2.ml#L676)
- **IR ctor**: [`Get_filename_component` at `lang_cmake.ml:414`](../../src/langs/cmake/lang_cmake.ml#L414)
- **Printer arm**: [`lang_cmake_pp.ml:562`](../../src/langs/cmake/lang_cmake_pp.ml#L562)
- **Accepts**:
  - `get_filename_component(<var> <filename> <mode> [CACHE])` with
    mode ∈ {DIRECTORY, NAME, EXT, NAME_WE, LAST_EXT, NAME_WLE, PATH,
    ABSOLUTE, REALPATH, PROGRAM}.
- **Bails on**:
  - PROGRAM mode with `PROGRAM_ARGS <var>` — sub-keyword unmodeled.
  - BASE_DIR / non-standard trailers.
- **Known gaps**: PROGRAM_ARGS exists in real cmake but IR
  doesn't carry it.

### 5.20 set_target_properties

- **Location**: [`print2.ml:691`](../../tool/cmake_roundtrip/print2.ml#L691)
- **IR ctor**: [`Set_target_properties` at `lang_cmake.ml:650`](../../src/langs/cmake/lang_cmake.ml#L650)
- **Printer arm**: [`lang_cmake_pp.ml:1127`](../../src/langs/cmake/lang_cmake_pp.ml#L1127)
- **Accepts**:
  - `set_target_properties(<target> PROPERTIES <k> <v> [<k> <v>]...)`
  - Single target only; keys must be bare; values may be quoted.
- **Bails on**:
  - Multiple targets — IR uses single `target`.
  - Missing PROPERTIES keyword.
  - Odd number of k/v pairs.
- **Known gaps**: multi-target form is common in real cmake; IR
  should widen to `targets : target list`.

### 5.21 add_custom_target

- **Location**: [`print2.ml:713`](../../tool/cmake_roundtrip/print2.ml#L713)
- **IR ctor**: [`Add_custom_target` at `lang_cmake.ml:775`](../../src/langs/cmake/lang_cmake.ml#L775)
- **Printer arm**: [`lang_cmake_pp.ml:1101`](../../src/langs/cmake/lang_cmake_pp.ml#L1101)
- **Accepts**:
  - `add_custom_target(<name>)`
  - `add_custom_target(<name> ALL)`
  - `add_custom_target(<name> [ALL] DEPENDS <dep>...)` with bare deps.
- **Bails on**:
  - Any `COMMAND` / `BYPRODUCTS` / `WORKING_DIRECTORY` / `COMMENT` /
    `JOB_POOL` / `VERBATIM` / `USES_TERMINAL` / `SOURCES` keyword —
    bail-set tightened in audit response.
- **Known gaps**: COMMAND blocks are the most common real shape
  but not modeled; bails to Apply.

### 5.22 list (subcommand dispatch)

- **Location**: [`print2.ml:739`](../../tool/cmake_roundtrip/print2.ml#L739)
- **IR ctor**: [`List_cmd` at `lang_cmake.ml:531`](../../src/langs/cmake/lang_cmake.ml#L531) (dispatched to per-subcommand variants)
- **Printer arm**: `pp_list_cmd` in `lang_cmake_pp.ml`
- **Accepts**:
  - `LENGTH <var> <out>`
  - `REVERSE <var>`
  - `REMOVE_DUPLICATES <var>`
  - `APPEND|PREPEND|REMOVE_ITEM <var> <values>...`
  - `FIND <var> <value> <out>`
  - `JOIN <var> <glue> <out>`
- **Bails on**:
  - INSERT / POP_BACK / POP_FRONT / GET / SORT / SUBLIST /
    TRANSFORM / FILTER — subcommands unmodeled.
  - Quoted/bracketed `<var>` or `<out>` slots (IR uses `string`).
- **Known gaps**: SORT and TRANSFORM are common; mechanically
  addable subcommand by subcommand.

### 5.23 string (subcommand dispatch)

- **Location**: [`print2.ml:767`](../../tool/cmake_roundtrip/print2.ml#L767)
- **IR ctor**: [`String_cmd` at `lang_cmake.ml:532`](../../src/langs/cmake/lang_cmake.ml#L532)
- **Printer arm**: `pp_string_cmd` in `lang_cmake_pp.ml`
- **Accepts**:
  - `TOUPPER|TOLOWER|LENGTH|STRIP <string> <out>`
  - `CONCAT <out> <inputs>...`
  - `APPEND|PREPEND <var> <inputs>...`
  - `REPLACE <match> <replace> <out> <inputs>...`
- **Bails on**:
  - REGEX subcommands (MATCH / MATCHALL / REPLACE).
  - FIND / SUBSTRING / RANDOM / TIMESTAMP / UUID / etc.

### 5.24 return

- **Location**: [`print2.ml:809`](../../tool/cmake_roundtrip/print2.ml#L809)
- **IR ctor**: [`Return` at `lang_cmake.ml:370`](../../src/langs/cmake/lang_cmake.ml#L370)
- **Printer arm**: [`lang_cmake_pp.ml:473`](../../src/langs/cmake/lang_cmake_pp.ml#L473)
- **Accepts**:
  - `return()`
  - `return(PROPAGATE <var>...)`
- **Bails on**: anything else (e.g. literal numeric return values).

### 5.25 include_directories

- **Location**: [`print2.ml:822`](../../tool/cmake_roundtrip/print2.ml#L822)
- **IR ctor**: [`Include_directories` at `lang_cmake.ml:791`](../../src/langs/cmake/lang_cmake.ml#L791)
- **Printer arm**: [`lang_cmake_pp.ml:1176`](../../src/langs/cmake/lang_cmake_pp.ml#L1176)
- **Accepts**:
  - `include_directories(<dir1> <dir2>...)` — no keywords.
- **Bails on**:
  - `AFTER` / `BEFORE` / `SYSTEM` keywords — printer always emits
    them at front, and we don't track positioning yet.
- **Known gaps**: BEFORE/AFTER/SYSTEM are common; need printer +
  parser to agree on canonical position.

### 5.26 find_program / find_path

- **Location**: [`print2.ml:839`](../../tool/cmake_roundtrip/print2.ml#L839) (shared `parse_find_var_names`)
- **IR ctor**: `Find_program` and `Find_path`, both use
  `find_var_args` at [`lang_cmake.ml:135`](../../src/langs/cmake/lang_cmake.ml#L135)
- **Printer arm**: `pp_find_var` in `lang_cmake_pp.ml:235`
- **Accepts**:
  - `find_program(<var> NAMES <n>...)` — explicit NAMES form.
  - `find_program(<var> NAMES <n>... REQUIRED)` — REQUIRED at end.
  - Same for `find_path`.
- **Bails on**:
  - Bare `find_program(<var> <name>)` — printer always emits NAMES
    keyword, so this would round-trip as `find_program(<var> NAMES <name>)`.
  - HINTS / PATHS / PATH_SUFFIXES / DOC / NO_CACHE / NO_*_PATH /
    REGISTRY_VIEW.
- **Known gaps**: the bare form is the most common in real cmake;
  IR could special-case it.

### 5.27 install

- **Location**: [`print2.ml:946`](../../tool/cmake_roundtrip/print2.ml#L946)
- **IR ctor**: [`Install_targets` at `lang_cmake.ml:840`](../../src/langs/cmake/lang_cmake.ml#L840) and [`Install_files` at `lang_cmake.ml:849`](../../src/langs/cmake/lang_cmake.ml#L849)
- **Printer arms**: [`lang_cmake_pp.ml:1221`](../../src/langs/cmake/lang_cmake_pp.ml#L1221) and [`lang_cmake_pp.ml:1227`](../../src/langs/cmake/lang_cmake_pp.ml#L1227)
- **Accepts**:
  - `install(TARGETS <t>... [EXPORT <name>] DESTINATION <d>)`
  - `install(FILES <f>... DESTINATION <d>)`
- **Bails on**:
  - DIRECTORY / SCRIPT / CODE / EXPORT-as-standalone form.
  - COMPONENT / RENAME / PERMISSIONS / OPTIONAL on TARGETS form.
  - ARCHIVE / LIBRARY / RUNTIME / OBJECTS / FRAMEWORK / BUNDLE /
    PUBLIC_HEADER / FILE_SET sub-clauses on TARGETS.
- **Known gaps**: per-target-type DESTINATIONs (ARCHIVE/LIBRARY/
  RUNTIME) are the canonical install shape in real C++ projects.

### 5.28 add_custom_command

- **Location**: [`print2.ml:878`](../../tool/cmake_roundtrip/print2.ml#L878)
- **IR ctor**: [`Add_custom_command_target` at `lang_cmake.ml:767`](../../src/langs/cmake/lang_cmake.ml#L767) (only TARGET form is modeled; OUTPUT form is [`Add_custom_command` at `lang_cmake.ml:748`](../../src/langs/cmake/lang_cmake.ml#L748))
- **Printer arm**: [`lang_cmake_pp.ml:1090`](../../src/langs/cmake/lang_cmake_pp.ml#L1090) (TARGET); 1076 (OUTPUT)
- **Accepts**:
  - `add_custom_command(TARGET <t> {PRE_BUILD|PRE_LINK|POST_BUILD}
    COMMAND <prog> <args>...)` with bare prog and args, single
    COMMAND block, no comment/verbatim/uses_terminal.
- **Bails on**:
  - OUTPUT form — printer is complex; not currently parsed.
  - Multiple COMMAND blocks.
  - Any of COMMENT / VERBATIM / USES_TERMINAL / BYPRODUCTS /
    WORKING_DIRECTORY / DEPFILE.
- **Known gaps**: OUTPUT form is half of real usage; safe-bail
  but loses typed access to the build-edge graph.

### 5.29 file (subcommand dispatch)

- **Location**: [`print2.ml:909`](../../tool/cmake_roundtrip/print2.ml#L909)
- **IR ctors**: `File_write`, `File_touch`, `File_make_directory`,
  `File_remove`, `File_glob` — all in `lang_cmake.ml:493..515`.
- **Printer arms**: `lang_cmake_pp.ml:699..756`.
- **Accepts**:
  - `WRITE|APPEND <path> <content>...`
  - `MAKE_DIRECTORY <dir>...`
  - `REMOVE|REMOVE_RECURSE <file>...`
  - `TOUCH|TOUCH_NOCREATE <file>...`
  - `GLOB|GLOB_RECURSE <var> <patterns>...` — no
    CONFIGURE_DEPENDS / RELATIVE / LIST_DIRECTORIES /
    FOLLOW_SYMLINKS keywords in the pattern list.
- **Bails on**:
  - READ — printer puts file before var; reversed slot order.
  - STRINGS / COPY / COPY_FILE / DOWNLOAD / UPLOAD / LOCK /
    REAL_PATH / SIZE / READ_SYMLINK / TIMESTAMP / RENAME /
    RELATIVE_PATH / TO_NATIVE_PATH / TO_CMAKE_PATH.
- **Known gaps**: file subcommand family is very large; per-IR
  printer audit is needed for the bail set.

## 6. How to extend when new parsers land

When a new Stage 2-d parser is added:

1. Add a row to § 5 with parser location, IR ctor + line, printer
   arm + line, accept set, bail set, known gaps.
2. Add a regression entry under § 5.X's "Known gaps" if the new
   parser surfaced any new IR/printer bug.
3. Update the § 5 stage table at the top.
4. Bump the contract sheet's "as of commit" marker.

When an IR/printer bug is fixed downstream:

1. Locate the affected parser's § 5 row.
2. Remove the IR gap from "Known gaps" or downgrade severity.
3. Move accept-set shapes that were previously bailed into the
   newly accepted set.
4. If new round-trip behavior changes the corpus tally, also
   update `bar3_lite_report.md` § 3.

## 7. Pre-commit drive-by checks for any audit response

When acting on an audit finding:

```sh
export PATH=/home/red/.venvs/default/bin:$PATH

# 1. Reproducer must fail on main before the fix. Use a
#    non-destructive baseline extraction (do NOT `git checkout
#    main -- file` — that overwrites the working tree).
git show main:tool/cmake_roundtrip/print2.ml > /tmp/print2.main.ml
#    Optionally build the main-baseline binary in a worktree or
#    a throwaway branch if you need to run it end-to-end.
echo '<reproducer>' | python3 tool/cmake_roundtrip/parse.py - \
  | _build/default/tool/cmake_roundtrip/print2.exe
# Confirm: STRUCT or typed-IR divergence visible.

# 2. Apply the fix; reproducer should now behave correctly.

# 3. Full-corpus regression — must not increase STRUCT or PARSE.
for c in /home/red/code/contrib/cmake-all/cmake/Tests/Tutorial \
         /home/red/code/contrib/z3-all/z3 \
         /home/red/code/contrib/llvm-all/llvm-project/llvm; do
  bash tool/cmake_roundtrip/test_corpus.sh "$c" | tail -8
done

# 4. Coverage tally. A parser fix that closes an accept-set
#    hole typically MOVES shapes from `modeled` into `generic`
#    (e.g. cmake_minimum_required range form, project DESCRIPTION,
#    add_executable WIN32 — all moved from modeled to generic on
#    2026-05-20). That is a CORRECTION, not a regression. A fix
#    that closes a bail-set overreach instead moves shapes
#    from `generic` into `modeled`. Either direction is fine
#    as long as the move is documented in the contract row.
```

---

This kit is the bridge between the claim-level audit (the report)
and per-parser correctness review. As parsers are added or IR is
cleaned up, both the contract sheet here and the report's § 3 +
§ 4 should be kept in sync.

## Appendix. Audit-kit review 2026-05-20

The first external review of this kit (2026-05-20) surfaced several
real bugs and process gaps. All findings were verified empirically
and addressed before the next audit round. Summary:

| # | finding | severity | resolution |
| -: | --- | --- | --- |
| 1 | Stage table counts inconsistent (32 vs 30 dispatched; 2-c was 9 but had 7 names) | major | Stage table corrected; helper/dispatcher relationship documented in § 5 prelude |
| 2 | `cmake_minimum_required` accepted `<min>...<max>`; printer drops max (accept-set hole) | major | Parser detects `...` and bails; § 5.1 row updated |
| 3 | `project` silently dropped DESCRIPTION / HOMEPAGE_URL; LANGUAGES emitted reversed | major | Parser now bails on DESCRIPTION/HOMEPAGE_URL; LANGUAGES ordering bug (double-reverse) fixed; § 5.2 row updated |
| 4 | `add_executable` put `WIN32`/`MACOSX_BUNDLE`/`EXCLUDE_FROM_ALL` into the sources list (typed-IR misclassification under STRUCT pass) | major | Parser now bails when any reserved option keyword is present; § 5.6 row updated. **This is the canonical example of "STRUCT pass ≠ typed correctness"** and motivated the dual-axis review framing in § 1 and § 2 |
| 5 | `target_link_libraries` mixed visibility groups round-trip correctly; contract row was wrong | medium | § 5.8 row corrected — mixed groups are an accept-set member, not a bail condition |
| 6 | Reproducer commands assumed `python3` had tree-sitter installed | medium | All reproducers prefixed with `export PATH=/home/red/.venvs/default/bin:$PATH` |
| 7 | "Byte-faithful Apply" framing was too strong (production Apply printer can emit multi-line) | medium | Replaced with "STRUCT-faithful" in § 2 vocabulary and elsewhere |
| 8 | Pre-commit recipe used destructive `git checkout main -- file` | nit / process | Replaced with non-mutating `git show main:file > /tmp/...` in § 7 |

**Corpus impact of the parser tightenings.** Tutorial 25/25 OK
unchanged; z3 108/108 OK with `modeled` 1057 → 1056 / `generic`
706 → 707 (one shape moved); llvm 596/596 OK with `modeled` 3573 →
3572 / `generic` 2609 → 2610 (one shape moved). All three corpora
remain STRUCT=0 / FORMAT=0. The tiny modeled-count drops reflect
the dual-axis correction: those shapes now route through
`Lang_cmake.Apply` (STRUCT-faithful, accurate typed classification)
instead of misclassifying into the typed IR.

**The major lesson.** Until this audit, the kit conflated STRUCT
preservation with typed-IR classification. STRUCT only checks that
tree-sitter re-extracts the same `(name, args)` sequence — it does
not check that an accepted command was put in the *right*
`Lang_cmake.exp` shape. `add_executable WIN32 main.c` round-trips
STRUCT-perfectly with `WIN32` in `sources` instead of `options`;
the bug is invisible to the round-trip oracle but real for any
downstream consumer that reads the typed IR. Future audits must
score both axes explicitly.
