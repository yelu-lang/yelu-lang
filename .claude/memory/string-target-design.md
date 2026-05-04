# Strings and Targets: cmake internals → yelu design

## How cmake handles strings vs targets

### Parse time: everything is strings

CMake's parsed representation (`cmListFileCache.h`) is entirely untyped:
```
cmListFileFunction = { name: string, arguments: vector<{Value: string, Delim: enum}> }
```
Every command receives `vector<string>`. Keywords (`STATIC`, `PUBLIC`, `TARGET`) are matched by string comparison at runtime. Variable expansion (`${VAR}`) happens at execution time.

### Execution time: typed C++ objects behind the strings

When cmake evaluates `add_library(foo STATIC foo.cxx)`, it creates a `cmTarget` object with:
- `cmStateEnums::TargetType` enum (STATIC_LIBRARY, SHARED_LIBRARY, EXECUTABLE, INTERFACE_LIBRARY, ...)
- `cmTarget::impl` with typed fields: sources, link libraries, compile definitions, etc.
- Stored in `cmMakefile::Targets` map (string name → cmTarget pointer)

**Targets are ONLY created explicitly** by: `add_executable`, `add_library`, `add_custom_target`. Directories and files never implicitly become targets.

### Generation time: strings resolved to target pointers

The generation phase resolves string references to typed objects:
- `cmGeneratorTarget::ResolveLinkItem()` — looks up string in global target map, returns `cmLinkItem` with either a `Target` pointer or a `String` fallback (for external/system libraries)
- `cmComputeTargetDepends` — builds dependency DAG using Tarjan's SCC, operates on `cmGeneratorTarget*` pointers
- LINK_LIBRARIES property stores raw strings at parse time; generation resolves them

### File API: direct serializer of internal state

The File API (`cmFileAPICodemodel.cxx`) is NOT a reconstructor. It directly calls:
- `target->GetType()` → serializes the enum
- `target->GetLinkImplementationLibraries()` → already-computed typed results
- `target->GetTargetDirectDepends()` → typed dependency graph

This confirms: cmake's internal model IS typed. The CMakeLists.txt syntax is the bottleneck that erases types.

### String taxonomy in cmake

What a "string" can actually be in cmake context:

| Role            | Example                               | Created by                 | cmake internal type    |
| --------------- | ------------------------------------- | -------------------------- | ---------------------- |
| Target name     | `MathFunctions`                       | add_library/add_executable | cmTarget*              |
| File path       | `tutorial.cxx`, `TutorialConfig.h.in` | implicit (source)          | cmSourceFile*          |
| Directory path  | `MathFunctions` (in add_subdirectory) | implicit                   | string                 |
| Variable name   | `CMAKE_CXX_STANDARD`                  | set()                      | cmMakefile::Definition |
| Property key    | `PASS_REGULAR_EXPRESSION`             | set_tests_properties       | string                 |
| Plain value     | `11`, `ON`                            | set()                      | string                 |
| Generator expr  | `$<BUILD_INTERFACE:...>`              | inline                     | parsed at gen time     |
| Export set name | `MathFunctionsTargets`                | install(EXPORT)            | cmExportSet*           |
| cmake module    | `CTest`, `CPack`                      | include()                  | file path (resolved)   |

All collapsed to `string` in CMakeLists.txt.

---

## Current yelu state (after Yarg_bare split)

```ocaml
type yelu_cvar = Ycvar of string      (* cmake runtime variable name *)
type yelu_target = Ytarget of string   (* target name *)
type yelu_var = Yvar of string         (* compile-time variable *)

type yarg =
  | Yarg_cvar of yelu_cvar    (* variable name: CMAKE_CXX_STANDARD *)
  | Yarg_target of yelu_target (* target name: MathFunctions *)
  | Yarg_file of string        (* file path: tutorial.cxx *)
  | Yarg_dir of string         (* directory path: bin, include *)
  | Yarg_str of string         (* plain value: "11", test names *)
  | Yarg_raw of string         (* cmake expression, passed through *)
  | Yarg_bool of bool          (* ON/OFF *)
  | Yarg_var of yelu_var       (* compile-time variable ref *)
```

Erasure: `Yarg_file/Yarg_dir/Yarg_str` → `Bare s` (same output). Semantic info for readability only.

### The remaining problem

`yelu_target = Ytarget of string` and `yelu_cvar = Ycvar of string` still wrap raw strings. But conceptually:
- A target name IS a name (a kind of string)
- A cvar name IS a name (a kind of string)
- `Yarg_file`, `Yarg_dir`, `Yarg_str` are also kinds of strings

These are parallel string classifications that don't share a common base. `Ytarget` can't express "this target was named from a file" or "this is a generated name."

---

## Proposed: yc_string as shared base type

Extract a common `yc_string` type that represents "what kind of string this is":

```ocaml
(* Base string classification — what role a string plays *)
type yc_string =
  | Ycs_file of string   (* file path *)
  | Ycs_dir of string    (* directory path *)
  | Ycs_name of string   (* identifier/name: target name, export set, test name *)
  | Ycs_val of string    (* plain value: numbers, property values *)
  | Ycs_raw of string    (* cmake expression, opaque *)
```

Then the typed wrappers build on it:

```ocaml
type yelu_cvar = Ycvar of yc_string    (* was: Ycvar of string *)
type yelu_target = Ytarget of yc_string (* was: Ytarget of string *)
```

And yarg becomes:

```ocaml
type yarg =
  | Yarg_cvar of yelu_cvar
  | Yarg_target of yelu_target
  | Yarg_string of yc_string   (* replaces Yarg_file/Yarg_dir/Yarg_str/Yarg_raw *)
  | Yarg_bool of bool
  | Yarg_var of yelu_var
```

### What this gives us

1. **Target creation is explicit and typed**: `Ytarget (Ycs_name "MathFunctions")` — target must be created with a string, which is the correct abstraction (cmake targets are explicitly created)

2. **String classification is shared**: file/dir/name/val taxonomy available everywhere, not just in yarg

3. **Simpler yarg**: 8 variants → 5 variants. The string details live in yc_string.

4. **yelu_cvar gets string semantics too**: `Ycvar (Ycs_name "CMAKE_CXX_STANDARD")` — variable names are names

### Erasure (unchanged output)

```
yc_string → string:
  Ycs_file s | Ycs_dir s | Ycs_name s | Ycs_val s → s
  Ycs_raw s → s (but Yarg_string (Ycs_raw s) erases to Quoted s in cmake arg position)
```

### Helper changes

```ocaml
(* string constructors *)
let yfile s = Yarg_string (Ycs_file s)
let ydir s = Yarg_string (Ycs_dir s)
let ystr s = Yarg_string (Ycs_val s)    (* or keep ystr → Ycs_val *)
let yraw s = Yarg_string (Ycs_raw s)

(* target/cvar: now take yc_string, but common case uses Ycs_name *)
let ytval s = Yarg_target (Ytarget (Ycs_name s))
let ycstr s = Yarg_cvar (Ycvar (Ycs_name s))
```

### What stays unclear (acceptable for now)

- Target identity is still string-based. In cmake, a target IS its name — there's no separate identity. So `Ytarget of yc_string` is faithful.
- We don't enforce "only Ycs_name in target position" — a target could theoretically have `Ycs_file` if someone creates a target named like a file. That's cmake's reality.
- The classification is for human readability, not type safety. Same as before.

### Files to modify

1. `lang_yelu.ml` — add `yc_string`, change `yelu_cvar`, `yelu_target`, simplify `yarg`
2. `lang_yelu_utils.ml` — update helpers
3. `lang_yelu_compile.ml` — update erasure: extract string from yc_string, handle Yarg_string
4. `test_yelu_compile.ml` — update test cases
5. All step files — helpers hide the change, so mostly unchanged (yfile/ydir/ystr/ytval/ycstr still work)
6. `step_common.ml` — should work as-is if helpers stay compatible
