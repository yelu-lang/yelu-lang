#!/usr/bin/env python3
"""Compare two cmake projects via cmake file API.

Usage:
  cmake_file_api_cmp.py <proj_a> <proj_b>
      Both are complete cmake project directories (with CMakeLists.txt + sources).

  cmake_file_api_cmp.py <source_dir> <cmake_a> <cmake_b>
      Single-file mode: one source dir, two CMakeLists.txt files to swap in.

Uses one shared build dir (reused sequentially) so all paths in the
JSON output are identical — no normalization needed.

Exit code 0 if semantically equivalent, 1 if different.
"""
import json, glob, os, shutil, subprocess, sys, tempfile


def run_cmake(source_dir, build_dir):
    """Run cmake on source_dir into build_dir (build_dir must not exist)."""
    query = os.path.join(build_dir, ".cmake", "api", "v1", "query")
    os.makedirs(query, exist_ok=True)
    open(os.path.join(query, "codemodel-v2"), "w").close()
    open(os.path.join(query, "cache-v2"), "w").close()
    r = subprocess.run(
        ["cmake", "-S", source_dir, "-B", build_dir],
        capture_output=True, text=True,
    )
    if r.returncode != 0:
        print(f"cmake failed:", file=sys.stderr)
        print(r.stderr, file=sys.stderr)
        sys.exit(2)


def strip_unstable(obj):
    """Strip fields that vary between runs but don't affect semantic equivalence.

    Stripped:
      jsonFile, backtrace, backtraceGraph — cmake internal bookkeeping
      id — target/directory IDs contain cmake-internal content hashes that
            change whenever CMakeLists.txt content changes, even if the
            resulting project structure is identical
    """
    if isinstance(obj, dict):
        return {
            k: strip_unstable(v)
            for k, v in obj.items()
            if k not in ("jsonFile", "backtrace", "backtraceGraph", "id")
        }
    if isinstance(obj, list):
        return [strip_unstable(v) for v in obj]
    return obj


def load_replies(build_dir):
    reply_dir = os.path.join(build_dir, ".cmake", "api", "v1", "reply")
    results = {}
    for pattern in ["codemodel-v2", "cache-v2", "target-*"]:
        files = glob.glob(os.path.join(reply_dir, f"{pattern}*.json"))
        for f in files:
            basename = os.path.basename(f)
            key = basename.rsplit("-", 1)[0]
            with open(f) as fh:
                results[key] = strip_unstable(json.load(fh))
    return results


def copy_tree_no_cmake(source, dest):
    """Copy directory tree, skipping CMakeLists.txt files."""
    for root, dirs, files in os.walk(source):
        rel = os.path.relpath(root, source)
        dst = os.path.join(dest, rel) if rel != "." else dest
        os.makedirs(dst, exist_ok=True)
        for f in files:
            if f != "CMakeLists.txt":
                shutil.copy2(os.path.join(root, f), os.path.join(dst, f))


def copy_cmake_files(source, dest):
    """Copy only CMakeLists.txt files, preserving directory structure."""
    for root, dirs, files in os.walk(source):
        for f in files:
            if f == "CMakeLists.txt":
                rel = os.path.relpath(root, source)
                dst_dir = os.path.join(dest, rel) if rel != "." else dest
                os.makedirs(dst_dir, exist_ok=True)
                shutil.copy2(os.path.join(root, f), os.path.join(dst_dir, f))


def compare(replies_a, replies_b):
    """Compare two reply dicts. Returns True if equivalent."""
    all_equal = True
    for key in sorted(set(list(replies_a.keys()) + list(replies_b.keys()))):
        if key not in replies_a:
            print(f"  {key}: only in B")
            all_equal = False
        elif key not in replies_b:
            print(f"  {key}: only in A")
            all_equal = False
        elif replies_a[key] == replies_b[key]:
            print(f"  {key}: IDENTICAL")
        else:
            print(f"  {key}: DIFFER")
            all_equal = False
    return all_equal


def main():
    if len(sys.argv) == 3:
        # Directory mode: two complete project directories
        proj_a, proj_b = sys.argv[1], sys.argv[2]
        with tempfile.TemporaryDirectory(prefix="cmake_cmp_") as tmpdir:
            src = os.path.join(tmpdir, "src")
            build = os.path.join(tmpdir, "build")

            # A: copy sources (no cmake) + cmake files from proj_a
            copy_tree_no_cmake(proj_a, src)
            copy_cmake_files(proj_a, src)
            run_cmake(src, build)
            replies_a = load_replies(build)

            # B: swap in cmake files from proj_b (same source tree)
            shutil.rmtree(build)
            # Remove old CMakeLists.txt, copy new ones
            for root, dirs, files in os.walk(src):
                for f in files:
                    if f == "CMakeLists.txt":
                        os.remove(os.path.join(root, f))
            copy_cmake_files(proj_b, src)
            run_cmake(src, build)
            replies_b = load_replies(build)

            eq = compare(replies_a, replies_b)

    elif len(sys.argv) == 4:
        # Single-file mode: source_dir + two CMakeLists.txt files
        source_dir, cmake_a, cmake_b = sys.argv[1], sys.argv[2], sys.argv[3]
        with tempfile.TemporaryDirectory(prefix="cmake_cmp_") as tmpdir:
            src = os.path.join(tmpdir, "src")
            build = os.path.join(tmpdir, "build")
            os.makedirs(src)
            for f in os.listdir(source_dir):
                p = os.path.join(source_dir, f)
                if os.path.isfile(p) and f != "CMakeLists.txt":
                    shutil.copy2(p, src)

            # A
            shutil.copy2(cmake_a, os.path.join(src, "CMakeLists.txt"))
            run_cmake(src, build)
            replies_a = load_replies(build)

            # B
            shutil.rmtree(build)
            shutil.copy2(cmake_b, os.path.join(src, "CMakeLists.txt"))
            run_cmake(src, build)
            replies_b = load_replies(build)

            eq = compare(replies_a, replies_b)
    else:
        print(__doc__)
        sys.exit(1)

    if eq:
        print("Result: EQUIVALENT")
        sys.exit(0)
    else:
        print("Result: DIFFERENT")
        sys.exit(1)


if __name__ == "__main__":
    main()
