# CMake Pain Points — and How Yelu Addresses Them

This document records specific cmake design decisions that are hostile to
static analysis, LLM synthesis, and human reasoning, alongside the yelu
design choices that address each one.

The goal is not to criticize cmake — it is a remarkably capable tool that
evolved organically over 20+ years. The goal is to identify the *properties*
that make it hard to work with, and use those as design constraints for yelu.

---

## 1. Variable Names and Values Are the Same Type

**The cmake problem.**
In cmake, a variable name and a variable value are both plain strings.
The distinction is purely positional — determined by where in a command the
argument appears, not by any syntactic marker on the argument itself.

```cmake
set(myvar hello)         # "myvar" is a variable name (write target)
set(other ${myvar})      # "${myvar}" is a value (read expansion)
list(APPEND mylist ${x}) # "mylist" is an identifier; "${x}" is a value
foreach(i IN ZIP_LISTS a b) # "a", "b" are variable names read by cmake
```

A reader (human or LLM) must know each command's argument schema to
distinguish identifiers from values. There is no local syntactic cue. An LLM
generating cmake must memorize per-command conventions rather than inferring
from the argument itself. Mistakes are silent: passing a variable *value*
where a variable *name* is expected does not error — cmake just uses the
string as-is.

**What yelu does — implemented.**
Yelu introduces `yelu_cvar` as a distinct type for cmake variable names.
All command arguments that are variable *identifiers* — whether written to
(output positions) or read by name (e.g., list-variable inputs) — take
`yelu_cvar`. All arguments that are *values* take `yarg`.

```ocaml
yc_set        : yelu_cvar -> yarg list -> yelu_exp
yc_foreach_zip: yelu_cvar list -> yelu_cvar list -> yelu_exp -> yelu_exp
yc_string_uuid: ... -> yelu_cvar -> yelu_exp   (* out is an identifier *)
```

A caller who passes a value (`yarg`) where an identifier (`yelu_cvar`) is
expected gets a compile-time type error. The distinction that cmake makes
implicit and per-command is made explicit and uniform across all yelu APIs.

This was a deliberate design refactor: prior to 2026-04-17, output positions
used `out : string` and mutation targets used `cvar : yarg` — both too weak
to enforce the identifier/value distinction. The refactor changed all such
positions to `yelu_cvar` uniformly across `lang_yelu.ml`, `lang_yelu_compile.ml`,
`lang_yelu_utils.ml`, and all call sites. The surface API now uses `ycvar "x"`
for identifiers and `ystr "v"` / `ycref "x"` for values — locally distinguishable
without consulting command documentation.

**Note on cmake namespaces.**
cmake has at least nine independent named-entity namespaces (Variable, Target,
Cache, Env, Command/Macro/Function, Module, Test, Export set, Property).
`yelu_cvar` covers the Variable namespace; `Ytarget` covers the Target
namespace. The others are either expressed as strings or not yet represented.
See §7 for the full namespace inventory and design direction.

---

## 2. Implicit List Splitting on Semicolons

**The cmake problem.**
cmake's fundamental data type is a string. Lists are strings where elements
are separated by semicolons. This means a string like `"a;b;c"` is silently
interpreted as a three-element list in list contexts. Forgetting to quote
`"${myvar}"` when the variable might contain semicolons causes silent
argument splitting.

```cmake
set(myvar "a;b;c")
message(STATUS ${myvar})    # prints three separate args: "a" "b" "c"
message(STATUS "${myvar}")  # prints the single string "a;b;c"
```

This is perhaps cmake's most notorious footgun. The rule "always quote variable
references" is widely repeated but frequently forgotten, and the failures are
silent (wrong behavior, no error).

**What yelu does (partial).**
Yelu's `Ycs_string` strings that contain whitespace or special characters are
automatically emitted as `Quoted` args by the compiler. This prevents the
most common whitespace-splitting issue. Full list-vs-string distinction is a
future design problem (Tier 5+): yelu does not yet have a typed `list` vs
`string` distinction at the yelu-AST level.

---

## 3. Output Variables Are Named by the Caller, Not the Command

**The cmake problem.**
cmake commands that produce output require the caller to supply the *name*
of the variable to write into. This is necessary because cmake has no
return values — output is communicated through the variable namespace.
But it means every call site carries an identifier that is purely a
plumbing detail, not part of the computation.

```cmake
string(LENGTH "${mystr}" len_var)   # "len_var" is caller-chosen plumbing
math(EXPR result "${a} + ${b}")     # "result" is caller-chosen plumbing
```

This is a consequence of cmake's design, not a bug. But it means:
- LLMs generating cmake must track variable names across steps
- Humans must invent names for intermediate results
- The computation and the plumbing are interleaved

**What yelu addresses (future).**
The compile-time `Ylet` binding in yelu is a step toward separating
computation from plumbing: a yelu program can bind intermediate results
to compile-time names without those names leaking into the cmake output.
Full expression composition (where yelu commands return values that can be
nested directly) is a Tier 5+ language design goal.

---

## 4. `if()` Boolean Semantics Require Policy CMP0012

**The cmake problem.**
In cmake without `cmake_policy(SET CMP0012 NEW)`, the strings `ON`, `YES`,
`TRUE`, `1` are *not* treated as boolean true in `if()` conditions. They
evaluate as false because cmake's old behavior treats unrecognized strings
as variable names, and those variables are undefined (empty = false).
The new behavior (CMP0012 NEW) is correct and expected, but it is not the
default in script mode (`cmake -P`).

```cmake
set(eq ON)
if(${eq})            # evaluates FALSE without CMP0012 NEW
if(${eq} STREQUAL "ON")  # works correctly regardless of policy
```

This surprises everyone the first time. LLMs trained on cmake snippets that
assume modern policy behavior generate subtly broken code when run in older
or script contexts.

**What yelu does.**
Yelu's `Ytruthy` condition is safe for non-boolean strings (empty/non-empty
check). For cmake commands that return `ON`/`OFF` (e.g., `string(JSON EQUAL
...)`), the correct test is `Ystrequal (ycref "var", ystr "ON")` — an
explicit string comparison that works under any policy. Yelu never generates
bare `if(${var})` for boolean-valued cmake variables; it always uses an
explicit comparison. Future work (Y11): emit `cmake_policy(SET CMP0012 NEW)`
automatically when `Ytruthy` is used on a cmake variable.

---

## 5. ERROR_VARIABLE Convention: NOTFOUND Means Success

**The cmake problem.**
cmake commands that accept `ERROR_VARIABLE` set the variable to an error
message on failure. On *success*, they set it to `NOTFOUND` — not to empty
string. This is consistent with cmake's `find_*` convention (where
`VAR-NOTFOUND` means "not found"), but it is counterintuitive: a check for
"no error" must compare against `NOTFOUND`, not `""`.

```cmake
string(JSON result ERROR_VARIABLE err GET "${json}" key)
if(NOT err STREQUAL "NOTFOUND")   # correct success check
  message(FATAL_ERROR "error: ${err}")
endif()
```

Most developers expect `""` to mean success. The cmake docs do not
prominently document this behavior, and it is easy to get backwards.

**What yelu does (future).**
Yelu wraps `ERROR_VARIABLE` commands with a cleaner API. A future design
could return a result type (success/failure) rather than exposing the raw
error variable convention to callers, hiding the NOTFOUND/error-message
distinction entirely.

---

## 6. `string(JSON SET ...)` Value Must Be a JSON Literal

**The cmake problem.**
`string(JSON ... SET json path value)` requires `value` to be a valid JSON
literal — a number (`42`), a JSON-quoted string (`"\"hello\""`), a boolean
(`true`/`false`), or `null`. Passing a plain cmake string like `hello`
fails silently (returns `NOTFOUND`). The cmake docs describe this but it is
easy to miss: the mental model of "pass a cmake string" is wrong here.

```cmake
string(JSON r SET [=[{"x":1}]=] y hello)       # fails — not a JSON literal
string(JSON r SET [=[{"x":1}]=] y [=["hello"]=]) # works — JSON string literal
string(JSON r SET [=[{"x":1}]=] y 42)           # works — JSON number
```

**What yelu does (future).**
A typed `yelu_json_value` type (distinct from `yarg`) for the `value`
argument of `yc_string_json_set` would prevent passing a plain string.
Currently the API accepts `yarg` and relies on the caller to pass an
appropriate JSON literal via `ystr_raw`.

---

## 7. Unnamed Named-Entity Namespaces

**The cmake problem.**
cmake has at least nine independent named-entity namespaces that a reader
must track mentally, yet the language provides no syntactic marker to
indicate which namespace an identifier belongs to:

| Namespace                  | cmake syntax examples                                            | What the name denotes                |
| -------------------------- | ---------------------------------------------------------------- | ------------------------------------ |
| Variable                   | `set(FOO val)`, `${FOO}`                                         | a mutable variable slot              |
| Target                     | `add_library(mylib ...)`, `if(TARGET mylib)`                     | a build target object                |
| Cache                      | `set(FOO val CACHE STRING "")`, `-DFOO=val`                      | a persistent cache entry             |
| Env                        | `$ENV{PATH}`, `set(ENV{HOME} ...)`                               | an environment variable              |
| Command / Macro / Function | `cmake_language(CALL myproc)`, `include(GNUInstallDirs)`         | a callable procedure                 |
| Module                     | `include(FetchContent)`, `find_package(Boost)`                   | a loadable cmake module              |
| Test                       | `add_test(NAME mytest ...)`, `set_tests_properties(mytest ...)`  | a registered test case               |
| Export set                 | `install(TARGETS ... EXPORT MyTargets)`                          | a named install manifest group       |
| Property                   | `get_property(val TARGET t PROPERTY INTERFACE_COMPILE_FEATURES)` | a target/source/global attribute key |

Namespace collisions are silent. A Variable and a Target can share a cmake
name — `set(foo val)` and `add_library(foo ...)` coexist — and cmake
silently routes each reference to its namespace based on the calling
command's argument schema. A command like `include(Name)` uses the Module
namespace; `add_test(NAME name ...)` uses the Test namespace; but both
`Name` and `name` are plain strings syntactically identical to variable
values. The only way to know which namespace an argument occupies is to
memorize each command's parameter table.

For LLMs generating cmake, this means every identifier must carry implicit
namespace disambiguation that is absent from the surface syntax — a constant
source of namespace-crossing mistakes that only surface as build errors or
silent wrong-behavior.

**What yelu does — partially implemented.**
Yelu types the two most structurally significant namespaces explicitly:
`yelu_cvar` for Variable and `yelu_target` for Target. These cover the
namespaces where name/value confusion (§1) and cross-namespace shadowing are
most common in practice.

The remaining namespaces are currently represented as strings in the yelu AST:

```ocaml
type yc_string =
  | Ycs_path    of string   (* Ty_path  — file or dir *)
  | Ycs_keyword of string   (* Ty_string — cmake keyword/flag *)
  | Ycs_name    of cmake_name  (* Ty_string — cmake name; namespace TBD *)
  | Ycs_string  of string   (* Ty_string — plain scalar value *)
  | Ycs_eval    of string   (* Ty_any   — configure-time ${VAR}/$<...> *)
```

`Ycs_name` is the current placeholder for all untyped cmake identifiers —
Module names (`include(FetchContent)`), Command names (`cmake_language(CALL
fn)`), Test names (`add_test(NAME mytest)`), Export set names, Property
keys — because their namespace is not yet represented in the type.

**Design direction.**
The intended future design is to promote namespace as type-level information
directly in `Ycs_name`, so that the namespace is statically visible at every
call site without consulting documentation:

```ocaml
(* Proposed: namespace as a separate tag in Ycs_name *)
type cmake_namespace =
  | Ns_command   (* cmake_language(CALL ...) *)
  | Ns_module    (* include(...) *)
  | Ns_test      (* add_test(NAME ...) *)
  | Ns_export    (* install(EXPORT ...) *)
  | Ns_property  (* get/set_property(... PROPERTY ...) *)
  | Ns_unknown   (* caller knows it's a name but namespace not yet tracked *)

type yc_string =
  | Ycs_path    of string
  | Ycs_keyword of string
  | Ycs_name    of cmake_namespace * cmake_name   (* namespace explicit *)
  | Ycs_string  of string
  | Ycs_eval    of string
```

Typed wrappers analogous to `yelu_cvar` and `yelu_target` (e.g., `yelu_cmd`,
`yelu_module`, `yelu_test`) are a natural follow-on once the namespace tag is
in place. At the surface level, a future type-inference pass could accept a
`Ns_unknown` name and infer its namespace from context — but for now, an
explicit namespace annotation at construction time is sufficient and less
surprising.

**Cache namespace note.**
The Cache namespace is currently conflated with Variable in `yelu_cvar`:
`Ycvar of cmake_name` covers both `set(FOO val)` (Variable) and `set(FOO val
CACHE STRING "")` (Cache). These are distinct — cache entries survive cmake
re-runs, can be overridden from the command line (`-DFOO=val`), and have
different invalidation semantics (see `cmake_policy.md` for the interaction
with `cmake_minimum_required`). Separating them is deferred; the `Ns_unknown`
tag above plays an analogous role as a reminder that the namespace is known to
be distinct but not yet typed.

---

## Summary

| Pain point                      | cmake behavior                    | Yelu response                                                                       |
| ------------------------------- | --------------------------------- | ----------------------------------------------------------------------------------- |
| Variable name vs value          | implicit by position              | `yelu_cvar` vs `yarg` distinction (§1)                                              |
| List splitting on `;`           | silent, context-dependent         | auto-quoting of `Ycs_string`; full fix is future                                    |
| Output variable plumbing        | caller-named, interleaved         | `Ylet` for compile-time bindings; expression compose is future                      |
| `if()` boolean policy           | CMP0012 NEW required              | explicit `STREQUAL "ON"` comparisons; Y11 policy preamble                           |
| `ERROR_VARIABLE` success value  | `NOTFOUND` not `""`               | future: result-type API over raw error_var                                          |
| JSON SET value type             | must be JSON literal              | future: `yelu_json_value` type                                                      |
| Unnamed named-entity namespaces | 9 namespaces, no syntactic marker | `yelu_cvar`/`yelu_target` typed; `Ycs_name` placeholder; namespace-tag design in §7 |
