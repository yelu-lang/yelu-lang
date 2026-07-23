# build_equiv fixture: `fmt` (external source tree)

Builds the real [{fmt}](https://github.com/fmtlib/fmt) library from `vendor/fmt`
**twice** — once from fmt's own pristine `CMakeLists.txt` (git HEAD), once from
the yelu-emitted cmake (`probes/fmt/main.yc` compiled) — plus a control build,
then compares the produced `libfmt.so` / `libfmt-c.a`:

- **artifact set** — same libraries produced
- **exported symbols** — `nm -D` on `libfmt.so`, `nm --extern-only` on
  `libfmt-c.a`; the sets must be identical (this is the payload: does the
  yelu-emitted config export the same API?)
- **bytes** — control-gated (compiler non-determinism tolerated)

This is the build-level counterpart to the fmt *configure-time* matrix oracle
(`probes/fmt/`): the matrix proves the emitted cmake configures identically;
this proves the resulting library is functionally the same.

Config flips everything off but the core library (`FMT_TEST/DOC/INSTALL/... =
OFF`, `BUILD_SHARED_LIBS=ON`) so only the root `CMakeLists.txt` is exercised —
no subdirectory `.yc`s, no install/pkgconfig path. The reference is read from
`git -C vendor/fmt show HEAD:CMakeLists.txt` (not the working tree) to dodge the
documented contamination gotcha where a stray yelu emit overwrote upstream.

**Skipped** (not failed) when `vendor/fmt` is absent — it's an external,
Linux-only working tree (a symlink to `contrib/fmt-all/fmt`).
