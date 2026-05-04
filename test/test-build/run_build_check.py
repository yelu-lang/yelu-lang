#!/usr/bin/env python3
"""Layer 3 build artifact check: build both cmake-ref and yelu projects,
assert the same set of artifacts exist and pass basic binary inspection.

Artifact checks (per artifact):
  - exists:         file is present in the build tree
  - non-empty:      file size > 0
  - binary magic:   ELF (Linux) or Mach-O (macOS) magic bytes for exe/lib targets

Uses the cmake File API reply (codemodel-v2) to discover expected artifacts
from the cmake-ref side — no hardcoded artifact names.

Usage (from tola root):
  python3 yelu/test/test-build/run_build_check.py [step_number ...]
  python3 yelu/test/test-build/run_build_check.py        # all steps

Requires: cmake + C++ compiler on PATH, dune build already done.
Exit code: 0 if all steps pass, 1 if any fail.
"""

import glob, json, os, shutil, struct, subprocess, sys, tempfile

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
# reuse assembly logic from file-api test
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "test-file-api"))
from run_file_api import assemble, STEP_FILES

TOLA = os.path.join(os.path.dirname(__file__), "..", "..", "..")
BUILD = os.path.join(TOLA, "_build", "default", "yelu", "src", "bin")


# ── Binary magic byte checks ──────────────────────────────────────────────────

ELF_MAGIC   = b"\x7fELF"
MACHO_MAGIC = {
    b"\xfe\xed\xfa\xce",  # Mach-O 32-bit
    b"\xfe\xed\xfa\xcf",  # Mach-O 64-bit
    b"\xce\xfa\xed\xfe",  # Mach-O 32-bit (reversed)
    b"\xcf\xfa\xed\xfe",  # Mach-O 64-bit (reversed)
    b"\xca\xfe\xba\xbe",  # Fat binary
}
AR_MAGIC = b"!<arch>\n"  # static library (ar format)


def check_binary_magic(path, target_type):
    """Check that the file has the expected binary magic bytes.
    Returns (ok: bool, reason: str).
    """
    with open(path, "rb") as f:
        header = f.read(8)
    if len(header) < 4:
        return False, "file too small"

    magic4 = header[:4]
    if target_type == "STATIC_LIBRARY":
        if header[:8] == AR_MAGIC:
            return True, "ar archive"
        return False, f"expected ar magic, got {header[:8]!r}"
    elif target_type in ("EXECUTABLE", "SHARED_LIBRARY", "MODULE_LIBRARY"):
        if magic4 == ELF_MAGIC:
            return True, "ELF"
        if magic4 in MACHO_MAGIC:
            return True, "Mach-O"
        return False, f"expected ELF/Mach-O magic, got {magic4!r}"
    else:
        # INTERFACE, OBJECT, UNKNOWN — no artifact to inspect
        return True, f"type {target_type} skipped"


# ── cmake build helpers ───────────────────────────────────────────────────────

def cmake_configure(src, build):
    query = os.path.join(build, ".cmake", "api", "v1", "query")
    os.makedirs(query, exist_ok=True)
    open(os.path.join(query, "codemodel-v2"), "w").close()
    r = subprocess.run(
        ["cmake", "-S", src, "-B", build],
        capture_output=True, text=True,
    )
    if r.returncode != 0:
        return False, r.stderr
    return True, None


def cmake_build(build):
    r = subprocess.run(
        ["cmake", "--build", build],
        capture_output=True, text=True,
    )
    if r.returncode != 0:
        return False, r.stderr
    return True, None


def load_artifacts(build):
    """Read codemodel File API reply, return list of (name, type, abs_path) for
    targets with real artifacts (exe, static, shared). Skips INTERFACE targets."""
    reply_dir = os.path.join(build, ".cmake", "api", "v1", "reply")
    results = []
    for f in glob.glob(os.path.join(reply_dir, "target-*.json")):
        with open(f) as fh:
            t = json.load(fh)
        ttype = t.get("type", "")
        if ttype in ("INTERFACE_LIBRARY",):
            continue
        for artifact in t.get("artifacts", []):
            rel = artifact["path"]
            results.append((t["name"], ttype, os.path.join(build, rel)))
    return results


# ── Per-artifact checks ───────────────────────────────────────────────────────

def check_artifact(name, ttype, path):
    """Run existence + magic checks. Returns list of (check, ok, detail) tuples."""
    results = []

    exists = os.path.isfile(path)
    results.append(("exists", exists, path))
    if not exists:
        return results

    size = os.path.getsize(path)
    results.append(("non-empty", size > 0, f"{size} bytes"))

    if ttype in ("EXECUTABLE", "STATIC_LIBRARY", "SHARED_LIBRARY", "MODULE_LIBRARY"):
        ok, detail = check_binary_magic(path, ttype)
        results.append(("binary-magic", ok, detail))

    return results


# ── Step runner ───────────────────────────────────────────────────────────────

def run_step(step):
    with tempfile.TemporaryDirectory(prefix=f"yelu_build_s{step}_") as tmp:
        errors = []

        # Build both sides and collect artifacts
        sides = {}
        for side in ("cmake", "yelu"):
            src  = os.path.join(tmp, f"src_{side}")
            build = os.path.join(tmp, f"build_{side}")
            os.makedirs(src)

            ok, err = assemble(step, side, src)
            if not ok:
                return False, [f"assemble {side}: {err}"]

            ok, err = cmake_configure(src, build)
            if not ok:
                return False, [f"cmake configure ({side}): {err.splitlines()[-1] if err else '?'}"]

            ok, err = cmake_build(build)
            if not ok:
                return False, [f"cmake build ({side}): {err.splitlines()[-1] if err else '?'}"]

            sides[side] = load_artifacts(build)

        # Compare artifact names between sides
        cmake_names = {(n, t) for n, t, _ in sides["cmake"]}
        yelu_names  = {(n, t) for n, t, _ in sides["yelu"]}
        only_cmake = cmake_names - yelu_names
        only_yelu  = yelu_names  - cmake_names
        if only_cmake:
            errors.append(f"artifacts only in cmake-ref: {only_cmake}")
        if only_yelu:
            errors.append(f"artifacts only in yelu: {only_yelu}")

        # Run per-artifact checks on yelu side
        for name, ttype, path in sides["yelu"]:
            for check, ok, detail in check_artifact(name, ttype, path):
                if not ok:
                    errors.append(f"{name} [{check}]: {detail}")

        return len(errors) == 0, errors


def main():
    steps = [int(a) for a in sys.argv[1:]] if len(sys.argv) > 1 else sorted(STEP_FILES)

    passed, failed, skipped = 0, 0, 0
    for step in steps:
        if step not in STEP_FILES:
            print(f"  step{step}: SKIP")
            skipped += 1
            continue
        ok, errors = run_step(step)
        if ok:
            print(f"  step{step}: PASS")
            passed += 1
        else:
            print(f"  step{step}: FAIL")
            for e in errors:
                print(f"    {e}")
            failed += 1

    print()
    print(f"Summary: {passed} passed, {failed} failed, {skipped} skipped")
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
