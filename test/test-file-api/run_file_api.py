#!/usr/bin/env python3
"""File API equivalence test: cmake step*.exe (reference) vs yelu step*.exe (under test).

For each step, assembles two cmake project directories — one from the cmake
reference executables, one from the yelu executables — then compares their
cmake File API output (codemodel-v2 + cache-v2).

Usage (from tola root):
  python3 yelu/test/test-file-api/run_file_api.py [step_number ...]
  python3 yelu/test/test-file-api/run_file_api.py        # all steps

Requires: cmake >= 3.14 on PATH, dune build already done.

Exit code: 0 if all steps pass, 1 if any fail.
"""

import os, shutil, subprocess, sys, tempfile

TOLA = os.environ.get("TOLA") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..")
FIXTURES = os.path.join(TOLA, "yelu", "test", "fixtures", "tutorial")
CMP = os.path.join(TOLA, "yelu", "test", "cmake_file_api_cmp.py")
# Both cmake and yelu step exes are promoted to their source directories.
BUILD = os.path.join(TOLA, "yelu", "src", "bin")


def exe(subdir, name):
    """Path to a dune-built executable."""
    return os.path.join(BUILD, subdir, name + ".exe")


def run_exe(path):
    """Run an executable and return its stdout, or None if it doesn't exist."""
    if not os.path.isfile(path):
        return None
    r = subprocess.run([path], capture_output=True, text=True)
    if r.returncode != 0:
        return None
    return r.stdout


def write(dest_dir, rel_path, content):
    """Write content to rel_path inside dest_dir, creating dirs as needed."""
    path = os.path.join(dest_dir, rel_path)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(content)


# Step manifest: for each step, list (exe_subdir, exe_name, output_rel_path).
# cmake/ and yelu/ subdirs are tried in parallel.
# Fallbacks: step8 root = step7, step9-12 math = step8_math, etc.

STEP_FILES = {
    1:  [("cmake", "step1", "CMakeLists.txt"),
         ("yelu",  "step1", "CMakeLists.txt")],
    2:  [("cmake", "step2",      "CMakeLists.txt"),
         ("cmake", "step2_math", "MathFunctions/CMakeLists.txt"),
         ("yelu",  "step2",      "CMakeLists.txt"),
         ("yelu",  "step2_math", "MathFunctions/CMakeLists.txt")],
    3:  [("cmake", "step3",      "CMakeLists.txt"),
         ("cmake", "step3_math", "MathFunctions/CMakeLists.txt"),
         ("yelu",  "step3",      "CMakeLists.txt"),
         ("yelu",  "step3_math", "MathFunctions/CMakeLists.txt")],
    4:  [("cmake", "step4",      "CMakeLists.txt"),
         ("cmake", "step4_math", "MathFunctions/CMakeLists.txt"),
         ("yelu",  "step4",      "CMakeLists.txt"),
         ("yelu",  "step4_math", "MathFunctions/CMakeLists.txt")],
    5:  [("cmake", "step5",      "CMakeLists.txt"),
         ("cmake", "step5_math", "MathFunctions/CMakeLists.txt"),
         ("yelu",  "step5",      "CMakeLists.txt"),
         ("yelu",  "step5_math", "MathFunctions/CMakeLists.txt")],
    6:  [("cmake", "step6",      "CMakeLists.txt"),
         ("cmake", "step6_math", "MathFunctions/CMakeLists.txt"),
         ("cmake", "step6_ctest","CTestConfig.cmake"),
         ("yelu",  "step6",      "CMakeLists.txt"),
         ("yelu",  "step6_math", "MathFunctions/CMakeLists.txt"),
         ("yelu",  "step6_ctest","CTestConfig.cmake")],
    7:  [("cmake", "step7",      "CMakeLists.txt"),
         ("cmake", "step7_math", "MathFunctions/CMakeLists.txt"),
         ("yelu",  "step7",      "CMakeLists.txt"),
         ("yelu",  "step7_math", "MathFunctions/CMakeLists.txt")],
    # step8 root reuses step7 (identical in reference)
    8:  [("cmake", "step7",      "CMakeLists.txt"),
         ("cmake", "step8_math", "MathFunctions/CMakeLists.txt"),
         ("cmake", "step8_table","MathFunctions/MakeTable.cmake"),
         ("yelu",  "step7",      "CMakeLists.txt"),
         ("yelu",  "step8_math", "MathFunctions/CMakeLists.txt"),
         ("yelu",  "step8_table","MathFunctions/MakeTable.cmake")],
    9:  [("cmake", "step9",      "CMakeLists.txt"),
         ("cmake", "step8_math", "MathFunctions/CMakeLists.txt"),
         ("cmake", "step8_table","MathFunctions/MakeTable.cmake"),
         ("yelu",  "step9",      "CMakeLists.txt"),
         ("yelu",  "step8_math", "MathFunctions/CMakeLists.txt"),
         ("yelu",  "step8_table","MathFunctions/MakeTable.cmake")],
    10: [("cmake", "step10",     "CMakeLists.txt"),
         ("cmake", "step10_math","MathFunctions/CMakeLists.txt"),
         ("cmake", "step8_table","MathFunctions/MakeTable.cmake"),
         ("yelu",  "step10",     "CMakeLists.txt"),
         ("yelu",  "step10_math","MathFunctions/CMakeLists.txt"),
         ("yelu",  "step8_table","MathFunctions/MakeTable.cmake")],
    11: [("cmake", "step11",      "CMakeLists.txt"),
         ("cmake", "step11_math", "MathFunctions/CMakeLists.txt"),
         ("cmake", "step11_config","Config.cmake.in"),
         ("cmake", "step8_table", "MathFunctions/MakeTable.cmake"),
         ("yelu",  "step11",      "CMakeLists.txt"),
         ("yelu",  "step11_math", "MathFunctions/CMakeLists.txt"),
         ("yelu",  "step11_config","Config.cmake.in"),
         ("yelu",  "step8_table", "MathFunctions/MakeTable.cmake")],
    12: [("cmake", "step12",       "CMakeLists.txt"),
         ("cmake", "step11_math",  "MathFunctions/CMakeLists.txt"),
         ("cmake", "step11_config","Config.cmake.in"),
         ("cmake", "step12_multi", "MultiCPackConfig.cmake"),
         ("cmake", "step8_table",  "MathFunctions/MakeTable.cmake"),
         ("yelu",  "step12",       "CMakeLists.txt"),
         ("yelu",  "step11_math",  "MathFunctions/CMakeLists.txt"),
         ("yelu",  "step11_config","Config.cmake.in"),
         ("yelu",  "step12_multi", "MultiCPackConfig.cmake"),
         ("yelu",  "step8_table",  "MathFunctions/MakeTable.cmake")],
}

# Steps that need TutorialConfig.h.in in the root (step8 root = step7.exe which has configure_file)
NEEDS_CONFIG_HIN = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12}
# Steps that need C++ source stubs (cmake 3.28+ validates source existence at configure time)
NEEDS_TUTORIAL_SRC  = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12}
NEEDS_MATHFUNC_SRC  = {2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12}
NEEDS_MAKETABLE_SRC = {8, 9, 10, 11, 12}
# Steps that include CPack (needs License.txt)
NEEDS_LICENSE       = {9, 10, 11, 12}


def copy_fixture(src_rel, dest_dir, dest_rel=None):
    src = os.path.join(FIXTURES, src_rel)
    dst = os.path.join(dest_dir, dest_rel or src_rel)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.copy(src, dst)


def assemble(step, side, dest_dir):
    """Write all cmake files for one side ('cmake' or 'yelu') into dest_dir."""
    for (subdir, exe_name, rel_path) in STEP_FILES[step]:
        if subdir != side:
            continue
        content = run_exe(exe(subdir, exe_name))
        if content is None:
            return False, f"missing executable: {subdir}/{exe_name}"
        write(dest_dir, rel_path, content)
    # Fixtures
    if step in NEEDS_CONFIG_HIN:
        copy_fixture("TutorialConfig.h.in", dest_dir)
    if step in NEEDS_TUTORIAL_SRC:
        copy_fixture("tutorial.cxx", dest_dir)
    if step in NEEDS_MATHFUNC_SRC:
        copy_fixture("MathFunctions/MathFunctions.cxx", dest_dir)
        copy_fixture("MathFunctions/mysqrt.cxx", dest_dir)
    if step in NEEDS_MAKETABLE_SRC:
        copy_fixture("MathFunctions/MakeTable.cxx", dest_dir)
    if step in NEEDS_LICENSE:
        copy_fixture("License.txt", dest_dir)
    return True, None


def run_step(step):
    with tempfile.TemporaryDirectory(prefix=f"yelu_fapi_s{step}_") as tmp:
        cmake_dir = os.path.join(tmp, "cmake")
        yelu_dir  = os.path.join(tmp, "yelu")
        os.makedirs(cmake_dir)
        os.makedirs(yelu_dir)

        ok, err = assemble(step, "cmake", cmake_dir)
        if not ok:
            return False, f"assemble cmake: {err}"
        ok, err = assemble(step, "yelu", yelu_dir)
        if not ok:
            return False, f"assemble yelu: {err}"

        r = subprocess.run(
            ["python3", CMP, cmake_dir, yelu_dir],
            capture_output=True, text=True,
        )
        output = r.stdout + r.stderr
        return r.returncode == 0, output


def main():
    steps = [int(a) for a in sys.argv[1:]] if len(sys.argv) > 1 else sorted(STEP_FILES)

    passed, failed, skipped = 0, 0, 0
    for step in steps:
        if step not in STEP_FILES:
            print(f"  step{step}: SKIP (not defined)")
            skipped += 1
            continue
        ok, output = run_step(step)
        if ok:
            print(f"  step{step}: PASS")
            passed += 1
        else:
            print(f"  step{step}: FAIL")
            for line in output.splitlines():
                print(f"    {line}")
            failed += 1

    print()
    print(f"Summary: {passed} passed, {failed} failed, {skipped} skipped")
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
