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

| cell | options | check | consume | needs |
|---|---|---|---|---|
| `core-lib` | all optional targets OFF, `BUILD_SHARED_LIBS=ON` | **byte-identical** | `consume_fmt.sh` | just a C++ compiler |

More cells (per option × {ON,OFF}, mirroring the configure-time matrix) can be
added by dropping entries into `cells`. A cell whose *reference* build fails
(missing dep) is **SKIPPED**, not failed — there is no baseline to compare.

### Consume / check script (`check_script`)

A cell is a **group**: its config drives *both* the vanilla-cmake and yelu-cmake
builds, and it can carry a shared **consume declaration** — what depends on the
build output and how it's exercised. The proper form is a lightweight dep/consume
manifest; for now it's hacked as a **script** (`check_script`, relative to this
dir). The *same* script runs against each side's build, and the harness compares
its `(exit, stdout)` — identical ⇒ the two builds are equivalent from a
downstream consumer's view.

The script gets the build dir as `argv[1]`, with `BE_BLD` (build tree — the
`libfoo.so` + dev symlinks) and `BE_SRC` (configured source tree — headers) in
the env. It runs against the *live* build tree (the strict mode snapshots only
final artifacts, but a consumer needs the symlinks and headers too).

`consume_fmt.sh` compiles a tiny program against the freshly-built `libfmt`,
links it (`-lfmt`), runs it, and prints a deterministic payload — proving the
library isn't just byte-identical on disk but *usable and identical in behavior*
when actually linked. Same output on both sides ⇒ equivalent.

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
