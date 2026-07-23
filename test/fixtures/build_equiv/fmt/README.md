# build_equiv fixture: `fmt` (external source tree, per-cell matrix)

Builds the real [{fmt}](https://github.com/fmtlib/fmt) library from `vendor/fmt`
**both ways** — from fmt's own pristine `CMakeLists.txt` (git HEAD) vs. the
yelu-emitted cmake (`probes/fmt/main.yc` compiled) — plus a control build, then
compares the produced `libfmt.so` / `libfmt-c.a`. This is the build-level
counterpart to the fmt *configure-time* matrix oracle (`probes/fmt/`): the matrix
proves the emitted cmake configures identically; this proves the resulting
library is the same, down to the byte.

## Per-cell matrix

The fixture is a **matrix of cells** (`fixture.json` → `cells`). Each cell sets
its own `-D` flags (appended to `base_configure_args`) and declares how it is
checked, because coverage is cell-dependent — the core library is byte-for-byte
reproducible, but a cell that turns on `FMT_TEST` / `FMT_FUZZ` / `FMT_CUDA_TEST`
needs external toolchains and may not build at all.

| cell | options | check | needs |
|---|---|---|---|
| `core-lib` | all optional targets OFF, `BUILD_SHARED_LIBS=ON` | **byte-identical** | just a C++ compiler |

More cells (per option × {ON,OFF}, mirroring the configure-time matrix) can be
added by dropping entries into `cells`. A cell whose *reference* build fails
(missing dep) is **SKIPPED**, not failed — there is no baseline to compare.

## Checks per cell

- **artifact set** — same libraries produced
- **exported symbols** — `nm -D` on `libfmt.so`, `nm --extern-only` on
  `libfmt-c.a`; sets must be identical (the API payload)
- **bytes** — for a `strict_bytes` cell: **byte-identical** demanded. Byte
  reproducibility is achieved by building ref/yelu/control through the *same*
  source+build path in sequence (fmt's only build non-determinism is embedded
  `__FILE__` / build paths; hold them constant and the compiler is
  bit-reproducible — the control side going byte-identical proves it). A
  non-`strict_bytes` cell instead uses independent paths with control-gated
  bytes, leaning on the symbol/runtime layers.

The reference is read from `git -C vendor/fmt show HEAD:CMakeLists.txt` (not the
working tree) to dodge the documented contamination gotcha where a stray yelu
emit overwrote upstream.

**Skipped** (not failed) when `vendor/fmt` is absent — it's an external,
Linux-only working tree (a symlink to `contrib/fmt-all/fmt`).
