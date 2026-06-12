#!/usr/bin/env python3
"""Empirical cmake deref-semantics probes — `foo` vs `${foo}` vs `"${foo}"`.

Runs small `cmake -P` programs and asserts the documented behaviour from
doc/cmake/deref_semantics.md, so the ground truth stays pinned as cmake
versions roll forward. Same spirit as test_cmake_probes.py (cache).

Usage: python3 test/test_deref_probes.py   (needs `cmake` on PATH)
"""

import re, subprocess, sys, tempfile, os

# --- Probe A: argument position (true ${ARGC} + per-arg <…>) -----------
ARG_PROBE = r'''
function(report label)
  set(vis "")
  set(i 1)
  while(i LESS ${ARGC})
    set(vis "${vis}<${ARGV${i}}>")
    math(EXPR i "${i} + 1")
  endwhile()
  math(EXPR ra "${ARGC} - 1")
  message("ARG|${label}|argc=${ra}|args=${vis}")
endfunction()
foreach(s IN ITEMS scalar list empty spaces semi trailing)
  if(s STREQUAL scalar)
    set(foo "abc")
  elseif(s STREQUAL list)
    set(foo "a;b;c")
  elseif(s STREQUAL empty)
    set(foo "")
  elseif(s STREQUAL spaces)
    set(foo "a b")
  elseif(s STREQUAL semi)
    set(foo ";")
  elseif(s STREQUAL trailing)
    set(foo "a;")
  endif()
  report("${s}.bare" foo)
  report("${s}.unq" ${foo})
  report("${s}.q" "${foo}")
endforeach()
'''

# --- Probe B: condition position --------------------------------------
IF_PROBE = r'''
set(bar "ON")
foreach(s IN ITEMS on word indirect)
  if(s STREQUAL on)
    set(foo "ON")
  elseif(s STREQUAL word)
    set(foo "abc")
  elseif(s STREQUAL indirect)
    set(foo "bar")
  endif()
  if(foo)
    set(rb T)
  else()
    set(rb F)
  endif()
  if(${foo})
    set(ru T)
  else()
    set(ru F)
  endif()
  if("${foo}")
    set(rq T)
  else()
    set(rq F)
  endif()
  message("IF|${s}|bare=${rb}|unq=${ru}|q=${rq}")
endforeach()
'''


def run(script):
    with tempfile.NamedTemporaryFile("w", suffix=".cmake", delete=False) as f:
        f.write(script)
        path = f.name
    try:
        r = subprocess.run(["cmake", "-P", path], capture_output=True, text=True)
        if r.returncode != 0:
            raise SystemExit("cmake failed:\n" + r.stderr)
        # cmake message() goes to stderr in -P mode
        return r.stderr + r.stdout
    finally:
        os.unlink(path)


def parse(out, tag):
    d = {}
    for line in out.splitlines():
        line = line.strip()
        if line.startswith(tag + "|"):
            parts = line.split("|")
            d[parts[1]] = parts[2:]
    return d


def main():
    failures = []

    def check(name, cond):
        print(("ok   " if cond else "FAIL ") + name)
        if not cond:
            failures.append(name)

    a = parse(run(ARG_PROBE), "ARG")
    # scalar: ${foo} == "${foo}" (1 arg each)
    check("scalar: unq==q (1 arg)",
          a["scalar.unq"] == ["argc=1", "args=<abc>"] and
          a["scalar.q"] == ["argc=1", "args=<abc>"])
    # list: unquoted splits to 3, quoted is 1
    check("list: unq=3 args",  a["list.unq"] == ["argc=3", "args=<a><b><c>"])
    check("list: q=1 arg",     a["list.q"]   == ["argc=1", "args=<a;b;c>"])
    # empty: unquoted elided (0), quoted one empty arg (1)
    check("empty: unq=0 args", a["empty.unq"] == ["argc=0", "args="])
    check("empty: q=1 arg",    a["empty.q"]   == ["argc=1", "args=<>"])
    # bare is always the literal "foo"
    check("bare: literal foo", a["scalar.bare"] == ["argc=1", "args=<foo>"])

    b = parse(run(IF_PROBE), "IF")
    # booleans agree; non-bool diverges
    check("if ON: all true",   b["on"] == ["bare=T", "unq=T", "q=T"])
    check("if abc: bare T, deref F",
          b["word"] == ["bare=T", "unq=F", "q=F"])
    check("if indirect: bare T, unq T (re-deref), q F",
          b["indirect"] == ["bare=T", "unq=T", "q=F"])

    if failures:
        print(f"\n{len(failures)} probe(s) DIVERGED from doc/cmake/deref_semantics.md")
        sys.exit(1)
    print("\nall deref probes match the documented semantics")


if __name__ == "__main__":
    main()
