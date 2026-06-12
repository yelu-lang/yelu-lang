#!/usr/bin/env python3
"""Empirical cmake deref-semantics probes — `foo` vs `${foo}` vs `"${foo}"`.

Covers the combination space from doc/cmake/var_reference_semantics.md:
  {bare, unquoted, quoted} x {scalar, list, empty} x {arg, if-truth, if-typed}
(the {conf-time, run-time} value axis is relaxed — these run cmake, so the
value is always known; the yc-side prediction is a separate, later pipeline.)

Runs small `cmake -P` programs and asserts the documented behaviour, so the
ground truth stays pinned as cmake versions roll forward. Same spirit as
test_cmake_probes.py (cache).

Usage: python3 test/test_deref_probes.py   (needs `cmake` on PATH)
"""

import subprocess, sys, tempfile, os

VALUES = {  # value-shape axis
    "scalar": "abc",
    "list":   "a;b;c",
    "empty":  "",
    "ver":    "1.5",      # for the typed (VERSION_LESS) probes
}

def cmake_set_block(var="foo"):
    lines = []
    first = True
    for name, val in VALUES.items():
        kw = "if" if first else "elseif"
        lines.append(f'  {kw}(s STREQUAL {name})')
        lines.append(f'    set({var} "{val}")')
        first = False
    lines.append("  endif()")
    return "\n".join(lines)

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
foreach(s IN ITEMS scalar list empty)
__SETBLOCK__
  report("${s}.bare" foo)
  report("${s}.unq" ${foo})
  report("${s}.q" "${foo}")
endforeach()
'''.replace("__SETBLOCK__", cmake_set_block())

# --- Probe B: condition position, untyped (truthiness) ----------------
IF_TRUTH = r'''
set(bar "ON")
foreach(s IN ITEMS scalar empty indirect onoff)
  if(s STREQUAL scalar)
    set(foo "abc")
  elseif(s STREQUAL empty)
    set(foo "")
  elseif(s STREQUAL indirect)
    set(foo "bar")
  elseif(s STREQUAL onoff)
    set(foo "ON")
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
  message("IFT|${s}|bare=${rb}|unq=${ru}|q=${rq}")
endforeach()
'''

# --- Probe D: expansion *structure* (for first-class `$` = EVarLookup) -
# Beyond the value-shape matrix: confirm the two structural cases the IR
# node must honour. Nested ${${inner}} is computed-name indirection (proves
# the operand must be an expr, not a string); mixed pre${l}post fuses at the
# boundary then splits (proves a pure $-node can't model it → deferred).
STRUCT_PROBE = r'''
function(report label)
  set(vis "")
  set(i 1)
  while(i LESS ${ARGC})
    set(vis "${vis}<${ARGV${i}}>")
    math(EXPR i "${i} + 1")
  endwhile()
  math(EXPR ra "${ARGC} - 1")
  message("STR|${label}|argc=${ra}|args=${vis}")
endfunction()
set(inner who)
set(who HELLO)
report("nested" ${${inner}})
report("nested.q" "${${inner}}")
set(l "a;b;c")
report("mixed.unq" pre${l}post)
report("mixed.q" "pre${l}post")
'''

# --- Probe E: $/quote nesting enumeration ------------------------------
# The construction space is ASYMMETRIC, not a free {$,quote}^n product:
#   * `$` nests freely inside `$` (computed name): ${x}, ${${x}}, ${${${x}}}
#   * quote wraps only the OUTERMOST arg: "${...}" / "${${...}}"
#   * a quote INSIDE ${...} is a cmake PARSE ERROR — a variable name may
#     contain text and nested ${...} but never a `"`.
# So EVarLookup's operand (for valid source) is name-text or nested
# EVarLookup, never a quoted EString. These pin that ground truth.
NEST_PROBE = r'''
function(report label)
  set(vis "")
  set(i 1)
  while(i LESS ${ARGC})
    set(vis "${vis}<${ARGV${i}}>")
    math(EXPR i "${i} + 1")
  endwhile()
  math(EXPR ra "${ARGC} - 1")
  message("NEST|${label}|argc=${ra}|args=${vis}")
endfunction()
set(a b)
set(b c)
set(c HELLO)
report("L1" ${c})
report("L2" ${${b}})
report("L3" ${${${a}}})
report("L3q" "${${${a}}}")
'''

# --- Probe C: condition position, typed (VERSION_LESS) ----------------
# Run each (value x form) in isolation so an unquoted-list operand — which
# splits into too many if() operands and is a *parse error* — doesn't abort
# the others. Returns "T" / "F" / "ERR".
def eval_if(setup, cond):
    script = (setup + "\n" +
              f'if({cond})\n  message("R|T")\nelse()\n  message("R|F")\nendif()\n')
    rc, out = run(script)
    if rc != 0:
        return "ERR"
    for line in out.splitlines():
        if line.strip().startswith("R|"):
            return line.strip().split("|", 1)[1]
    return "?"


def run(script):
    with tempfile.NamedTemporaryFile("w", suffix=".cmake", delete=False) as f:
        f.write(script)
        path = f.name
    try:
        r = subprocess.run(["cmake", "-P", path], capture_output=True, text=True)
        # parse errors (e.g. if(a b)) are themselves a documented result;
        # return rc so callers can note "errors" if needed.
        return (r.returncode, r.stderr + r.stdout)
    finally:
        os.unlink(path)


def parse(out, tag):
    d = {}
    for line in out.splitlines():
        line = line.strip()
        if line.startswith(tag + "|"):
            p = line.split("|")
            d[p[1]] = p[2:]
    return d


def main():
    failures = []

    def check(name, cond):
        print(("ok   " if cond else "FAIL ") + name)
        if not cond:
            failures.append(name)

    _, out = run(ARG_PROBE)
    a = parse(out, "ARG")
    # scalar: unquoted == quoted == 1 arg; bare is literal
    check("arg/scalar: unq==q (1)", a["scalar.unq"] == ["argc=1", "args=<abc>"]
          and a["scalar.q"] == ["argc=1", "args=<abc>"])
    check("arg/scalar: bare literal", a["scalar.bare"] == ["argc=1", "args=<foo>"])
    # list: unquoted splits (3), quoted is one (the divergence)
    check("arg/list: unq=3", a["list.unq"] == ["argc=3", "args=<a><b><c>"])
    check("arg/list: q=1",   a["list.q"]   == ["argc=1", "args=<a;b;c>"])
    # empty: unquoted elided (0), quoted one empty arg (1)
    check("arg/empty: unq=0", a["empty.unq"] == ["argc=0", "args="])
    check("arg/empty: q=1",   a["empty.q"]   == ["argc=1", "args=<>"])

    _, out = run(IF_TRUTH)
    b = parse(out, "IFT")
    check("if-truth/onoff: all T", b["onoff"] == ["bare=T", "unq=T", "q=T"])
    check("if-truth/empty: all F", b["empty"] == ["bare=F", "unq=F", "q=F"])
    # non-bool word: bare derefs (T), ${}/"${}" evaluate the value (F)
    check("if-truth/scalar(abc): bare=T deref=F",
          b["scalar"] == ["bare=T", "unq=F", "q=F"])
    # indirection: bare T, unquoted re-derefs (T), quoted is a string (F)
    check("if-truth/indirect: bare=T unq=T q=F",
          b["indirect"] == ["bare=T", "unq=T", "q=F"])

    # typed compare (VERSION_LESS), each isolated
    ver = 'set(foo "1.5")'
    lst = 'set(foo "1;5")'
    check("if-typed/ver: unq==q (T)",
          eval_if(ver, '${foo} VERSION_LESS "2.0"') == "T" and
          eval_if(ver, '"${foo}" VERSION_LESS "2.0"') == "T")
    # the key non-scalar typed result: unquoted list operand is a PARSE
    # ERROR (splits into too many operands); quoted is one operand (valid).
    check("if-typed/list: unquoted=ERR",
          eval_if(lst, '${foo} VERSION_LESS "2.0"') == "ERR")
    check("if-typed/list: quoted is valid (not ERR)",
          eval_if(lst, '"${foo}" VERSION_LESS "2.0"') in ("T", "F"))

    # expansion structure (first-class `$` = EVarLookup must honour these)
    _, out = run(STRUCT_PROBE)
    d = parse(out, "STR")
    # nested ${${inner}}: computed name resolves (operand is an expr)
    check("struct/nested: ${${inner}} resolves",
          d["nested"] == ["argc=1", "args=<HELLO>"])
    check("struct/nested.q: same when quoted",
          d["nested.q"] == ["argc=1", "args=<HELLO>"])
    # mixed pre${l}post (l=a;b;c): boundary fuse THEN split → 3 args
    check("struct/mixed.unq: fuse+split (3)",
          d["mixed.unq"] == ["argc=3", "args=<prea><b><cpost>"])
    check("struct/mixed.q: one arg",
          d["mixed.q"] == ["argc=1", "args=<prea;b;cpost>"])

    # $/quote nesting enumeration
    _, out = run(NEST_PROBE)
    e = parse(out, "NEST")
    # positives: $ nests to any depth; outer quote keeps it one arg
    check("nest/L1: ${c}", e["L1"] == ["argc=1", "args=<HELLO>"])
    check("nest/L2: ${${b}}", e["L2"] == ["argc=1", "args=<HELLO>"])
    check("nest/L3: ${${${a}}}", e["L3"] == ["argc=1", "args=<HELLO>"])
    check("nest/L3q: \"${${${a}}}\" (1 arg)",
          e["L3q"] == ["argc=1", "args=<HELLO>"])
    # negatives: a quote INSIDE ${...} is a parse error, arg + if positions
    rc_arg, _ = run('set(c HELLO)\nmessage(${"${c}"})\n')
    check("nest/quote-in-dollar (arg): parse ERROR", rc_arg != 0)
    check("nest/quote-in-dollar (if): parse ERROR",
          eval_if('set(c 1)', '${"${c}"}') == "ERR")

    if failures:
        print(f"\n{len(failures)} probe(s) DIVERGED from doc/cmake/var_reference_semantics.md")
        sys.exit(1)
    print("\nall deref probes match the documented semantics")


if __name__ == "__main__":
    main()
