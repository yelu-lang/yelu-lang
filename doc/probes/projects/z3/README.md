# z3 — predictor probe status

> **Project**: Z3 theorem prover
> **Source**: github.com/Z3Prover/z3 (vendored at `/home/red/code/contrib/z3-all/z3`)
> **Why this probe**: established bar #3-lite canonical corpus —
> 108 cmake files spanning project root + cmake modules + test
> harnesses. Good stress test for parse-print.

## Headline numbers (2026-06-03)

| oracle | result | notes |
|---|---|---|
| parse-print | **108/108 OK** | STRUCT=0 FORMAT=0 PARSE=0 — has held across every printer change in the bar3-lite history |
| cache matrix | not built | z3's option surface is larger and configure work is heavier; would need its own matrix harness |

## Oracles in detail

### Parse-print

```sh
bash tool/cmake_roundtrip/test_corpus.sh /home/red/code/contrib/z3-all/z3
```

Last result: `OK=108 FORMAT=0 STRUCT=0 PARSE=0`. See
[methodology/parse_print_oracle.md](../../methodology/parse_print_oracle.md).

z3 has been the **regression gate** for parser/printer changes
since the bar3-lite work landed. Every printer fix that closed an
llvm STRUCT also got smoke-checked on z3 to verify no regression.

### Cache matrix

Not yet built. Building one would mean:

1. Run `cache_vars.exe` on z3's CMakeLists to enumerate flippable
   options.
2. Build a `test_z3_matrix_smoke.ml` analogous to fmt's.
3. First-run results would surface what z3 needs vs fmt — likely
   different find_package targets (no Threads here; probably GMP,
   OCaml, .NET).

This is a candidate for the next probe-building session, per
[../../candidates.md](../../candidates.md).

## Open issues

None on parse-print. Cache-matrix is just unbuilt — not a known
predictor gap.
