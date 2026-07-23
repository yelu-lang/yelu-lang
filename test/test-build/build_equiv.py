#!/usr/bin/env python3
"""Build-equivalence checker — does the build produced from yelu-emitted cmake
match the build produced from reference cmake, at the *artifact*, *symbol*, and
*runtime-behavior* levels?

This is the level above the configure-time matrix oracle: the matrix proves the
emitted cmake *configures* the same; this proves it *builds* and *runs* the same.
It is what caught the SHARED/MODULE library-type emit bug (configure-clean,
build-broken).

## Non-determinism

You cannot demand byte-identity: compilers embed build paths, timestamps, and
hash-ordered tables, so even the *same* source built twice can differ. So the
checker (a) leans on comparisons that are inherently deterministic — the set of
exported symbols and the runtime behavior — and (b) runs a **control build** (the
reference built a second time, in a different path) to measure the compiler's own
noise floor. A byte difference is only a *finding* when the control is
byte-identical (compiler was reproducible here) yet yelu still differs.

## Layers (strict → tolerant)

  1. artifact set  — the relative paths of build outputs must match   [strict]
  2. symbol set    — `nm -D --defined-only` per artifact, as a set     [strict]
  3. runtime       — run each executable, diff exit code + stdout      [strict]
  4. bytes         — sha256 / size; reported, only *failed* when the   [control-gated]
                     control build was byte-identical but yelu was not

## Fixture layout  (test/fixtures/build_equiv/<name>/)

Two kinds of fixture:

**Self-contained** — sources live in the fixture dir:

  CMakeLists.txt   the reference (raw cmake)
  main.yc          the yelu source (compiled to the yelu-side cmake)
  <sources>        C/C++ shared by both sides
  check.json       optional: { "run": { "<exe-basename>": ["argv", ...] } }

**External source tree** — build a real vendored project (e.g. fmt) both ways.
A `fixture.json` selects this mode; the reference cmake comes from the tree
itself (pristine from git, to dodge working-tree contamination), the yelu cmake
from compiling a `.yc` elsewhere in the repo:

  fixture.json     { "source_tree": "vendor/fmt",          # copied as the build base
                     "yc": "probes/fmt/main.yc",           # compiled → root CMakeLists.txt
                     "configure_args": ["-DBUILD_SHARED_LIBS=ON", ...],
                     "ref_from_git": true,                 # ref CMakeLists = git HEAD (default true)
                     "run": { "<exe>": [argv] } }          # optional
  <overlay files>  optional: extra files laid over the tree copy

If `source_tree` is absent from disk (vendored trees are external and Linux-only)
the fixture is SKIPPED, not failed.

## Usage  (from repo root, after `dune build`)

  python3 test/test-build/build_equiv.py            # all fixtures
  python3 test/test-build/build_equiv.py hello      # one fixture by name

Requires cmake + a C/C++ compiler + nm on PATH. Exit 0 iff every strict layer
passes for every fixture.
"""

import glob, hashlib, json, os, shutil, subprocess, sys, tempfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
FIXTURES = os.path.join(ROOT, "test", "fixtures", "build_equiv")
# yelu.exe from the dune build tree (standalone layout: _build/default/src/bin)
YELU = os.path.join(ROOT, "_build", "default", "src", "bin", "yelu", "yelu.exe")

RESET, RED, GRN, YEL, DIM = "\x1b[0m", "\x1b[31m", "\x1b[32m", "\x1b[33m", "\x1b[2m"


def run(cmd, cwd=None):
    p = subprocess.run(cmd, cwd=cwd, stdout=subprocess.PIPE,
                       stderr=subprocess.STDOUT, text=True)
    return p.returncode, p.stdout


def yelu_compile(yc_path):
    if not os.path.exists(YELU):
        sys.exit(f"{RED}yelu.exe not found at {YELU} — run `dune build` first{RESET}")
    # Capture stdout ONLY: yelu prints by-design warnings (raw-cmake escapes,
    # unknown-command notices) to stderr — merging them into stdout would splice
    # `[yelu][...]` text into the emitted CMakeLists and break the cmake parse.
    p = subprocess.run([YELU, "compile", yc_path], stdout=subprocess.PIPE,
                       stderr=subprocess.PIPE, text=True)
    if p.returncode != 0:
        raise RuntimeError(f"yelu compile failed:\n{p.stdout}{p.stderr}")
    return p.stdout


def stage_and_build(cmakelists_text, sources, label):
    """Write cmakelists_text + sources into a fresh temp source tree, configure
    and build it. Returns (build_dir, ok, log). The temp path length varies per
    call, which is what makes the control build a real reproducibility probe."""
    src = tempfile.mkdtemp(prefix=f"be_{label}_src_")
    bld = tempfile.mkdtemp(prefix=f"be_{label}_bld_")
    with open(os.path.join(src, "CMakeLists.txt"), "w") as h:
        h.write(cmakelists_text)
    for rel, abspath in sources:
        dst = os.path.join(src, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copy(abspath, dst)
    rc, out = run(["cmake", "-S", src, "-B", bld])
    if rc != 0:
        return bld, False, f"configure failed:\n{out}"
    rc, out = run(["cmake", "--build", bld])
    if rc != 0:
        return bld, False, f"build failed:\n{out}"
    return bld, True, ""


def stage_tree(tree_abs, cmakelists_text, overlay, configure_args, label):
    """Copy an external source tree into a fresh temp dir, overwrite its root
    CMakeLists.txt with cmakelists_text, lay any overlay files on top, then
    configure (with configure_args) and build. Returns (build_dir, ok, log).
    Dereferences symlinks (`vendor/fmt` is one) and drops .git / build junk."""
    src = tempfile.mkdtemp(prefix=f"be_{label}_src_")
    bld = tempfile.mkdtemp(prefix=f"be_{label}_bld_")
    # cp -rL: dereference the vendor symlink; then strip VCS / stray build dirs
    rc, out = run(["cp", "-rL", tree_abs + "/.", src])
    if rc != 0:
        return bld, False, f"tree copy failed:\n{out}"
    for junk in (".git", "build", "build2", "_out"):
        shutil.rmtree(os.path.join(src, junk), ignore_errors=True)
    with open(os.path.join(src, "CMakeLists.txt"), "w") as h:
        h.write(cmakelists_text)
    for rel, abspath in overlay:
        dst = os.path.join(src, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copy(abspath, dst)
    rc, out = run(["cmake", "-S", src, "-B", bld, *configure_args])
    if rc != 0:
        return bld, False, f"configure failed:\n{out}"
    rc, out = run(["cmake", "--build", bld])
    if rc != 0:
        return bld, False, f"build failed:\n{out}"
    return bld, True, ""


# ── artifact discovery ────────────────────────────────────────────────────────

CMAKE_INTERNAL = ("CMakeFiles", "cmake_install.cmake", "CMakeCache.txt",
                  "Makefile", "build.ninja", ".cmake", ".ninja_deps",
                  ".ninja_log", "compile_commands.json")


def is_elf(path):
    try:
        with open(path, "rb") as h:
            return h.read(4) == b"\x7fELF"
    except OSError:
        return False


def classify(rel):
    base = os.path.basename(rel)
    if ".so" in base or base.endswith(".a") or base.endswith(".dylib"):
        return "lib"
    return "exe"


def artifacts(build_dir):
    """rel_path -> {kind, abs} for real build outputs (ELF / libs), skipping
    cmake internals and intermediate .o/.d files."""
    out = {}
    for dp, _, files in os.walk(build_dir):
        if any(seg in dp.split(os.sep) for seg in ("CMakeFiles",)):
            continue
        for fn in files:
            if fn.endswith((".o", ".d", ".obj", ".internal")) \
               or fn in CMAKE_INTERNAL or fn.endswith(".cmake"):
                continue
            ap = os.path.join(dp, fn)
            if not os.path.isfile(ap) or os.path.islink(ap):
                continue
            if is_elf(ap) or fn.endswith((".a", ".dylib")):
                out[os.path.relpath(ap, build_dir)] = {"kind": classify(fn), "abs": ap}
    return out


def _parse_nm(out):
    syms = set()
    for line in out.splitlines():
        line = line.strip()
        if not line or line.endswith(":"):   # blank / archive-member header (`foo.o:`)
            continue
        parts = line.split()
        if len(parts) >= 3:               # addr type name
            syms.add(parts[2])
        elif len(parts) == 2:             # (no addr) type name
            syms.add(parts[1])
    return syms


def dyn_symbols(path):
    """Exported symbol set: dynamic (`nm -D`) for shared objects / exes; for a
    static archive (no dynamic table) fall back to the external defined symbols
    (`nm --extern-only`), which is the equivalent 'what this lib exports' set."""
    rc, out = run(["nm", "-D", "--defined-only", path])
    if rc == 0:
        syms = _parse_nm(out)
        if syms:
            return syms
    if path.endswith(".a"):
        rc, out = run(["nm", "--extern-only", "--defined-only", path])
        if rc == 0:
            syms = _parse_nm(out)
            if syms:
                return syms
    return None


def sha(path):
    with open(path, "rb") as h:
        return hashlib.sha256(h.read()).hexdigest()


# ── comparison ────────────────────────────────────────────────────────────────

def compare(name, ref_bld, yelu_bld, ctrl_bld, run_spec):
    fails, notes = [], []

    def ok(msg):  print(f"  {GRN}ok{RESET}   {msg}")
    def bad(msg): print(f"  {RED}FAIL{RESET} {msg}"); fails.append(msg)
    def info(msg):print(f"  {DIM}info {msg}{RESET}"); notes.append(msg)

    ra, ya, ca = artifacts(ref_bld), artifacts(yelu_bld), artifacts(ctrl_bld)

    # Layer 1 — artifact set
    if set(ra) == set(ya):
        ok(f"artifact set ({len(ra)}): " + ", ".join(sorted(ra)))
    else:
        bad(f"artifact set differs\n       ref : {sorted(ra)}\n       yelu: {sorted(ya)}")
        return fails, notes  # nothing else is meaningful if the sets diverge

    for rel in sorted(ra):
        rp, yp = ra[rel]["abs"], ya[rel]["abs"]
        # Layer 2 — symbol set
        rs, ys = dyn_symbols(rp), dyn_symbols(yp)
        if rs is None or ys is None:
            info(f"{rel}: no dynamic symbols (static lib / stripped)")
        elif rs == ys:
            ok(f"{rel}: symbols match ({len(rs)})")
        else:
            only_ref, only_yelu = rs - ys, ys - rs
            bad(f"{rel}: symbol sets differ  ref-only={sorted(only_ref)}  yelu-only={sorted(only_yelu)}")
        # Layer 4 — bytes (control-gated)
        if rel in ca:
            r_sha, y_sha, c_sha = sha(rp), sha(yp), sha(ca[rel]["abs"])
            if r_sha == y_sha:
                ok(f"{rel}: byte-identical")
            elif r_sha == c_sha:
                # compiler was reproducible here, yet yelu differs → real diff
                bad(f"{rel}: bytes differ from reference while the control build "
                    f"was byte-identical — a genuine difference, not compiler noise")
            else:
                info(f"{rel}: bytes differ, but so does the control build "
                     f"(compiler non-deterministic here) — not a finding")

    # Layer 3 — runtime behavior
    for exe_base, argv in (run_spec or {}).items():
        r_rel = next((rel for rel in ra if os.path.basename(rel) == exe_base and ra[rel]["kind"] == "exe"), None)
        if r_rel is None:
            bad(f"run: no executable artifact named '{exe_base}'")
            continue
        r_exit, r_out = run([ra[r_rel]["abs"], *argv])
        y_exit, y_out = run([ya[r_rel]["abs"], *argv])
        if (r_exit, r_out) == (y_exit, y_out):
            ok(f"run {exe_base} {argv}: exit={r_exit}, stdout matches ({r_out.strip()!r})")
        else:
            bad(f"run {exe_base}: ref=(exit {r_exit}, {r_out!r}) yelu=(exit {y_exit}, {y_out!r})")

    return fails, notes


def git_show(tree_abs, rev_path):
    rc, out = run(["git", "-C", tree_abs, "show", rev_path])
    if rc != 0:
        raise RuntimeError(f"git show {rev_path} in {tree_abs} failed:\n{out}")
    return out


def check_external_tree(name, fdir, cfg):
    """Build a real vendored source tree from its own (pristine) cmake vs
    yelu-emitted cmake, and compare. Returns True/False, or None if skipped."""
    tree_abs = os.path.join(ROOT, cfg["source_tree"])
    if not os.path.isdir(tree_abs):
        print(f"  {YEL}SKIP{RESET} source tree {cfg['source_tree']} not present "
              f"(external / Linux-only)")
        return None
    yc = os.path.join(ROOT, cfg["yc"])
    cfg_args = cfg.get("configure_args", [])
    run_spec = cfg.get("run", {})
    overlay = [(os.path.relpath(os.path.join(dp, fn), fdir), os.path.join(dp, fn))
               for dp, _, files in os.walk(fdir) for fn in files
               if os.path.relpath(os.path.join(dp, fn), fdir) not in
                  ("fixture.json", "README.md")]

    try:
        # Reference cmake: pristine from git HEAD by default — the working tree
        # can be contaminated by a stray yelu emit (documented gotcha), which
        # would make ref==yelu trivially and hide real divergence.
        if cfg.get("ref_from_git", True):
            ref_cmake = git_show(tree_abs, "HEAD:CMakeLists.txt")
        else:
            ref_cmake = open(os.path.join(tree_abs, "CMakeLists.txt")).read()
        yelu_cmake = yelu_compile(yc)
    except RuntimeError as e:
        print(f"  {RED}FAIL{RESET} {e}")
        return False

    ref_bld,  ref_ok,  ref_log  = stage_tree(tree_abs, ref_cmake,  overlay, cfg_args, "ref")
    yelu_bld, yelu_ok, yelu_log = stage_tree(tree_abs, yelu_cmake, overlay, cfg_args, "yelu")
    ctrl_bld, ctrl_ok, _        = stage_tree(tree_abs, ref_cmake,  overlay, cfg_args, "ctrl")

    fails = []
    if not ref_ok:
        print(f"  {RED}FAIL{RESET} reference build failed:\n{ref_log}"); fails.append("ref build")
    if not yelu_ok:
        print(f"  {RED}FAIL{RESET} yelu build failed (yelu-emitted cmake):\n{yelu_log}"); fails.append("yelu build")
    if ref_ok and yelu_ok:
        f, _ = compare(name, ref_bld, yelu_bld, ctrl_bld, run_spec)
        fails += f

    for d in (ref_bld, yelu_bld, ctrl_bld):
        shutil.rmtree(d, ignore_errors=True)
    print(f"  {GRN}PASS{RESET}" if not fails else f"  {RED}{len(fails)} failure(s){RESET}")
    return not fails


def check_fixture(fdir):
    name = os.path.basename(fdir.rstrip("/"))
    print(f"\n{YEL}▶ {name}{RESET}")
    fj = os.path.join(fdir, "fixture.json")
    if os.path.exists(fj):
        return check_external_tree(name, fdir, json.load(open(fj)))
    ref_cmake = open(os.path.join(fdir, "CMakeLists.txt")).read()
    yc = os.path.join(fdir, "main.yc")
    run_spec = {}
    cj = os.path.join(fdir, "check.json")
    if os.path.exists(cj):
        run_spec = json.load(open(cj)).get("run", {})
    # shared sources = every file (recursively, preserving relative paths) except
    # the two cmake sources + check.json — so fixtures may use include/, src/, …
    skip = {"CMakeLists.txt", "main.yc", "check.json"}
    sources = []
    for dp, _, files in os.walk(fdir):
        for fn in files:
            rel = os.path.relpath(os.path.join(dp, fn), fdir)
            if rel in skip:
                continue
            sources.append((rel, os.path.join(dp, fn)))

    try:
        yelu_cmake = yelu_compile(yc)
    except RuntimeError as e:
        print(f"  {RED}FAIL{RESET} {e}")
        return False

    ref_bld,  ref_ok,  ref_log  = stage_and_build(ref_cmake,  sources, "ref")
    yelu_bld, yelu_ok, yelu_log = stage_and_build(yelu_cmake, sources, "yelu")
    ctrl_bld, ctrl_ok, _        = stage_and_build(ref_cmake,  sources, "ctrl")

    fails = []
    if not ref_ok:
        print(f"  {RED}FAIL{RESET} reference build failed:\n{ref_log}"); fails.append("ref build")
    if not yelu_ok:
        print(f"  {RED}FAIL{RESET} yelu build failed (yelu-emitted cmake):\n{yelu_log}"); fails.append("yelu build")
    if ref_ok and yelu_ok:
        f, _ = compare(name, ref_bld, yelu_bld, ctrl_bld, run_spec)
        fails += f

    for d in (ref_bld, yelu_bld, ctrl_bld):
        shutil.rmtree(d, ignore_errors=True)
    print(f"  {GRN}PASS{RESET}" if not fails else f"  {RED}{len(fails)} failure(s){RESET}")
    return not fails


def main():
    wanted = sys.argv[1:]
    dirs = sorted(glob.glob(os.path.join(FIXTURES, "*")))
    dirs = [d for d in dirs if os.path.isdir(d) and (not wanted or os.path.basename(d) in wanted)]
    if not dirs:
        sys.exit(f"no fixtures under {FIXTURES}" + (f" matching {wanted}" if wanted else ""))
    results = [check_fixture(d) for d in dirs]
    npass = sum(1 for r in results if r is True)
    nskip = sum(1 for r in results if r is None)
    nfail = sum(1 for r in results if r is False)
    ran = len(results) - nskip
    tail = f" ({nskip} skipped)" if nskip else ""
    print(f"\n{'='*50}\nbuild-equiv: {npass}/{ran} fixtures pass{tail}")
    sys.exit(0 if nfail == 0 else 1)


if __name__ == "__main__":
    main()
