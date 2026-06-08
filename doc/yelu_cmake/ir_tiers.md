# IR Fidelity Tiers — typed, meta, raw, apply

yelu's IR represents cmake commands at four levels of fidelity. Each
tier is explicit about what it knows and what it can check.

## The four tiers

| Tier | IR constructor | Parser syntax | What it expresses | Checkable at parse time? |
|---|---|---|---|---|
| 1 | Typed constructors (`ECmakeAddExecutable`, `ECmakeTargetLinkLibraries`, …) | `add_exe Target foo …`, `link_lib Target bar :PUBLIC …` | Static cmake commands with known field types | ✅ Full type checking, visibility enum, wellform name binding |
| 2 | `ECmakeLanguageCall` | `cmake_call fn args` | cmake's native metaprogramming (`cmake_language(CALL …)`) | ⚠️ String args only; no static structure |
| 3 | `ECmakeRaw` | `yc_raw <expr>` | Known cmake primitive with dynamic/untypable args; verbatim cmake text | ⚠️ Wellform flags as tainted; text opaque to checker |
| 4 | `ECmakeApply` | Any unknown IDENT-headed call | Project-defined cmake functions, user macros, commands not yet typed | ⚠️ Wellform checks for primitive shadowing only |

## Tier 1 — typed IR

Every cmake builtin with a yc API has a typed IR constructor. Fields are
statically known at parse time — target names, visibility keywords, source
file paths. The parser matches command names against family dispatchers
and populates typed constructors.

```ocaml
(* yc syntax *)
add_exe Target myapp "main.cc" "util.cc"
link_lib Target myapp :PUBLIC mylib
set_property Target myapp PROPERTY OUTPUT_NAME "myapp"

(* IR produced *)
ECmakeAddExecutable { name = ETarget "myapp"; sources = [EString "main.cc"; …] }
ECmakeTargetLinkLibraries { target = ETarget "myapp"; visibility = "PUBLIC"; … }
ECmakeSetProperty { targets = [ETarget "myapp"]; properties = [("OUTPUT_NAME", …)] }
```

**When to use**: always, unless the command has dynamic values not resolvable
at parse time.

## Tier 2 — cmake metaprogramming (`cmake_lang`)

cmake's `cmake_language(CALL …)` provides native dynamic dispatch. yelu
exposes it as `cmake_call fn args`. Arguments are strings with no static
structure — the function is resolved at cmake configure-time.

```ocaml
(* yc syntax *)
cmake_call my_func "arg1" "${dynamic_arg}"

(* IR produced *)
ECmakeLanguageCall { cmd = EString "my_func"; args = [EString "arg1"; …] }
```

**When to use**: cmake functions dispatched at configure-time via
`cmake_language(CALL …)`.

## Tier 3 — raw escape (`yc_raw`)

For cmake primitives whose arguments contain dynamic values not
representable in the typed IR. The parser recognizes the command name
(so it's known to be a primitive, not an unknown call) but cannot type
the arguments.

The parser reconstructs cmake text from the parsed args and wraps it in
`ECmakeRaw`. The emit path dumps the text verbatim via `C.Quote`.

```ocaml
(* yc syntax — visibility is dynamic (${kind} from a cmake function parameter) *)
target_link_libraries Target ${name} ${kind} "mylib"

(* IR produced — command name is known, but visibility is dynamic *)
ECmakeRaw "target_link_libraries(${name} ${kind} mylib)"
```

`yc_raw` can also be used explicitly for verbatim cmake:
```ocaml
yc_raw PUBLIC    (* emits: PUBLIC *)
yc_raw ${kind}   (* emits: ${kind} *)
```

**When to use**: a known cmake primitive has dynamic values (variable
references, generator expressions) that the typed IR can't capture as
static fields.

**Wellform**: flags each `ECmakeRaw` site as `Raw_cmake_escape`. The
content is opaque to all checkers.

## Tier 4 — apply (`yc_apply`)

Catch-all for commands not recognized as cmake builtins — project-defined
functions, user macros, modules like `CheckCXXCompilerFlag`. Arguments are
preserved verbatim.

```ocaml
(* yc syntax — add_fmt_test is a project-defined cmake function *)
add_fmt_test NAME mytest HEADER_ONLY

(* IR produced *)
ECmakeApply { name = EString "add_fmt_test"; args = [EString "NAME"; …] }
```

**When to use**: project-defined functions and cmake module calls.

**Wellform**: checks that `name` does not shadow a known typed primitive.
`yc_apply (ystr "add_executable")` is rejected — use `add_exe` instead.

## Choosing a tier

```
Is the command a cmake builtin?
  ├─ No  → Tier 4 (yc_apply)
  └─ Yes → Are all arguments statically typable?
            ├─ Yes → Tier 1 (typed IR)
            └─ No  → Are dynamic values meta-programming?
                      ├─ Yes → Tier 2 (cmake_lang) or Tier 3 (yc_raw)
                      └─ No  → Tier 3 (yc_raw)
```

## Parser fallback flow

```
source.yc
  → lex → tokens
  → p_stmt → matches command name against family dispatchers
    ├─ name not in any family → p_generic_command_y1 → ECmakeApply (Tier 4)
    ├─ name in family, args match typed pattern → typed IR (Tier 1)
    └─ name in family, args don't match → args_to_cmake_text → ECmakeRaw (Tier 3)
```

## String-as-enum fields (planned)

Several IR fields currently use `string` where a finite-domain variant
would be more precise:

| Field | Domain | Status |
|---|---|---|
| `visibility` | PUBLIC \| PRIVATE \| INTERFACE | ✅ `type visibility = Vis_public \| Vis_private \| Vis_interface` (`yelu_cmake.ml`) |
| `mode` | STATUS \| WARNING \| FATAL_ERROR \| … | ✅ `message_mode` variant + `message_mode_of_string` (`yelu_cmake_utils.ml`) |
| `compatibility` | AnyNewerVersion \| SameMajorVersion \| … | Use `compatibility` (already in cmake AST) |
| `cache_type` | STRING \| BOOL \| PATH \| FILEPATH | Define variant or use cmake AST type |

The cmake AST (`Lang_cmake`) already has typed enums for most of these.
The yc IR should define its own variants and convert at the emit boundary.
Dynamic values (`${kind}`) in these positions fall back to `yc_raw` (Tier 3).

## Related

- [`driver.md`](driver.md) — pipelines graph and driver modules
- [`../../doc/cmake/painpoints.md`](../../doc/cmake/painpoints.md) — cmake pain points
- [`../../src/langs/yelu/yc_primitives.ml`](../../src/langs/yelu/yc_primitives.ml) — command name registry
- [`../../src/langs/yelu/yc_wellform.ml`](../../src/langs/yelu/yc_wellform.ml) — wellform checks
