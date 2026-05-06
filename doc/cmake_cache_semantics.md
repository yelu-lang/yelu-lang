# cmake Cache Semantics — Decision Tree & Enumeration

> Verified against cmake 4.3.1 with systematic enumeration (12 cases, 2 runs each).

## Decision tree

### Write path

```
set(NAME val CACHE TYPE "doc")
├── Cache entry for NAME already exists? (from previous run or -D)
│   ├── YES → NO-OP (writes nothing, returns silently)
│   └── NO  → write NAME=val to BOTH Cache AND Normal namespaces

set(NAME val)
├── Always writes NAME=val to Normal namespace

-DNAME=val
├── Always writes NAME=val to Cache namespace only

unset(NAME)
├── Removes NAME from Normal namespace only

unset(NAME CACHE)
├── Removes NAME from BOTH Cache AND Normal namespaces
```

### Read path

```
${NAME}  /  if(DEFINED NAME)
├── Normal namespace has NAME (non-empty)?
│   ├── YES → return normal value / true
│   └── NO  → Cache namespace has NAME (non-empty)?
│       ├── YES → return cache value / true  [fallback]
│       └── NO  → return "" / false

$CACHE{NAME}  /  if(DEFINED CACHE{NAME})
├── Cache namespace has NAME?
│   ├── YES → return cache value / true
│   └── NO  → return "" / false
```

### Equivalences

| A                       | ≡   | B                               | Condition |
| ----------------------- | --- | ------------------------------- | --------- |
| `option(VAR "msg" ON)`  | ≡   | `set(VAR ON CACHE BOOL "msg")`  | Always    |
| `option(VAR "msg" OFF)` | ≡   | `set(VAR OFF CACHE BOOL "msg")` | Always    |

### Cross-run persistence

```
Run 1: set(X "a" CACHE STRING "")   → X.cache="a", X.normal="a"
Run 2: set(X "b" CACHE STRING "")   → X.cache="a" (sticky!), X.normal NOT written
Run 2: ${X}                         → "" (run 1's normal is gone, cache write was no-op)
```

This is the **dual-write trap**: on first configure the cache set writes normal too;
on re-configure it writes neither. The program's behavior depends on whether a
build directory already exists.

## Enumeration results

### Set 1: Read on empty (no prior writes)

| #   | Action                         | ${VAR}  | DEFINED VAR | Verified |
| --- | ------------------------------ | ------- | ----------- | -------- |
| 1.1 | (never set)                    | `""`    | false       | ✓        |
| 1.2 | `set(VAR val)` → read          | `"val"` | true        | ✓        |
| 1.3 | `set(VAR val CACHE...)` → read | `"val"` | true        | ✓        |

### Set 2: Order matters — normal vs cache, same name

| #   | Action              | ${VAR}      | $CACHE{VAR} | Notes                                        |
| --- | ------------------- | ----------- | ----------- | -------------------------------------------- |
| 2.1 | normal then cache   | `"then_c"`  | `"then_c"`  | cache overwrites normal (dual-write)         |
| 2.2 | cache then normal   | `"then_n"`  | `"first_c"` | normal reads first; cache unchanged          |
| 2.3 | 2.1 on re-configure | `"first_n"` | `"then_c"`  | cache write is no-op; normal keeps "first_n" |

### Set 3: unset behavior

| #   | Action                       | ${VAR} | DEFINED VAR | Notes                                     |
| --- | ---------------------------- | ------ | ----------- | ----------------------------------------- |
| 3.1 | set norm+ch, unset normal    | `"c"`  | true        | normal removed, cache persists → fallback |
| 3.2 | set cache only, unset normal | `"c"`  | true        | same — cache fallback                     |
| 3.3 | set norm+ch, unset CACHE     | `""`   | false       | **both** namespaces cleared               |

### Set 4: -D command-line

| #   | Action                      | ${VAR}      | $CACHE{VAR} | Notes                              |
| --- | --------------------------- | ----------- | ----------- | ---------------------------------- |
| 4.1 | -D only, no script set      | `"cmdline"` | `"cmdline"` | cache fallback for normal read     |
| 4.2 | -D, then `set(VAR "n")`     | `"n"`       | `"cmdline"` | normal wins read; cache unchanged  |
| 4.3 | -D, `set(VAR "c" CACHE...)` | `"cmdline"` | `"cmdline"` | -D already in cache → script no-op |

## Implications for yelu theory design

### What stays together: set/get/defined

Read and write are tightly coupled by the fallback chain. Splitting `set` from
`get`/`defined` into separate theories would require each theory to understand
the other's namespace semantics. The current grouping of all three in one theory
(`lang_yelu_var.ml`) is correct — the pain point is the mixing of variable and
cache namespaces within that theory.

### What should split: variable vs cache

The current theory has six constructors across three namespaces:

| Constructor        | Namespace | After split                      |
| ------------------ | --------- | -------------------------------- |
| `Yvar_set`         | Variable  | → `var` theory                   |
| `Yvar_option`      | Cache     | → `cache` theory                 |
| `Yvar_set_cache`   | Cache     | → `cache` theory                 |
| `Yvar_unset_cache` | Cache     | → `cache` theory                 |
| `Yvar_set_env`     | Env       | → `var` theory (or `env` theory) |
| `Yvar_unset_env`   | Env       | → `var` theory (or `env` theory) |

The cache theory owns the decision tree above (first-write-wins, dual-write,
persistence across runs, -D interaction). The variable theory owns single-namespace
read/write with no persistence.

### Priority

Cache theory split is lower priority than:
1. Finishing the concrete syntax parser for the remaining cmake theories
2. The `effect` checking pass

The current theory works correctly for the covered cases; the split is a
correctness/clarity improvement, not a bug fix.
