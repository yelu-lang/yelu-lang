#!/bin/bash
# Per-file test harness for cmake_roundtrip across an arbitrary corpus.
# Usage: ./test_corpus.sh <corpus_root>
#
# Prints one line per file with verdict:
#   OK     <relpath>                   <typed>/<generic>/<other>
#   FORMAT <relpath>  (struct-eq but gersemi-diff)
#   STRUCT <relpath>  (parse->reprint loses commands or misreorders)
#   PARSE  <relpath>  (tree-sitter or our reader fails)
#
# At the end, summary line + category counts. Designed to be diffed
# across commits to track progress.

set -uo pipefail

if [ $# -lt 1 ]; then
  echo "usage: $0 <corpus_root> [parse.py path] [print2.exe path]"
  exit 1
fi

corpus="$1"
parse_py="${2:-$(dirname "$0")/parse.py}"
yelu_root="${YELU_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
print2="${3:-$yelu_root/_build/default/tool/cmake_roundtrip/print2.exe}"
gersemi="${GERSEMI:-/home/red/.venvs/default/bin/gersemi}"
strip_comments="${STRIP_COMMENTS:-$(dirname "$0")/strip_comments.py}"
# Pre-strip comments via tree-sitter on both sides before gersemi.
# Our parser already drops comments inside argument lists, so
# gersemi-on-the-reprint sees comment-free args. Stripping the
# source side too makes gersemi's wrap decisions consistent: no
# more multi-line layouts driven by inline comments only present
# in the source. This is the cleanest way to make FORMAT measure
# content equivalence (modulo wrap heuristic) rather than
# comment-driven layout drift. See bar3_feasibility.md.
#
# Whether yelu_cmake / yelu_cmake_normal should carry comments
# as AST metadata is a separate, deferred question — for the
# oracle we strip; for future tooling we may revisit.
gersemi_args="${GERSEMI_ARGS:---line-length 99999}"

# Pre-flight: gersemi must be available and executable. Without this
# guard, a missing or broken gersemi produces empty output on both
# the reference and the generated path, and the FORMAT oracle would
# pass spuriously (empty == empty) on every file.
if ! [ -x "$gersemi" ] && ! command -v "$gersemi" >/dev/null 2>&1; then
  echo "FATAL: gersemi not found or not executable at: $gersemi" >&2
  echo "  Override with: GERSEMI=/path/to/gersemi $0 $*" >&2
  exit 2
fi
if ! "$gersemi" --version >/dev/null 2>&1; then
  echo "FATAL: gersemi at $gersemi failed --version probe" >&2
  exit 2
fi

# Pre-flight: print2.exe must be built.
if ! [ -x "$print2" ]; then
  echo "FATAL: print2.exe not found at: $print2" >&2
  echo "  Run: dune build tool/cmake_roundtrip/print2.exe" >&2
  exit 2
fi

ok=0; format=0; struct=0; parse=0
modeled_total=0; stdlib_total=0; resolved_total=0; generic_total=0; other_total=0

# Two-tier name index (Class A Phase 1 from doc/yelu_cmake/bar3_lite.md
# § 6). project_index.exe walks any directory and emits
# `<name>\t<file>\t<function|macro>` lines for every function/macro
# def. We build two indices and pass both to print2.exe:
#
#   CORPUS_INDEX_FILE        — defs found in the corpus root
#                              -> `resolved` bucket
#   CMAKE_STDLIB_INDEX_FILE  — defs found in cmake's Modules/ tree
#                              -> `stdlib` bucket
#
# print2.exe splits the un-typed Apply tally as
#   resolved > stdlib > generic
# (project-first, like Python's sys.path). Reprint output is
# unchanged whether indices are loaded or not — this is purely
# accounting.
#
# Both indices are cached under /tmp. The corpus index keys off
# the corpus path; the stdlib index keys off the Modules dir path
# (which encodes the cmake version, e.g. /usr/share/cmake-4.3).
#
# Env knobs:
#   NO_CORPUS_INDEX=1     — skip corpus index (resolved bucket = 0)
#   NO_CMAKE_STDLIB=1     — skip cmake stdlib index (stdlib bucket = 0)
#   REBUILD_CORPUS_INDEX=1 — force rebuild corpus index
#   REBUILD_CMAKE_STDLIB=1 — force rebuild stdlib index
#   CMAKE_STDLIB_ROOT=...  — override Modules dir detection
project_index_exe="${yelu_root}/_build/default/tool/cmake_roundtrip/project_index.exe"

# Prepare the cmake-stdlib name index. Probes cmake for its
# CMAKE_ROOT (so we pick up whatever version is currently active —
# e.g. 4.3.1 on this machine, but 3.x on older installs), then runs
# project_index.exe over Modules/. The index is cached per
# Modules-dir path. Echoes the cache file path on stdout; empty
# string on failure.
prepare_cmake_stdlib_index() {
  if [ -n "${NO_CMAKE_STDLIB:-}" ] || [ ! -x "$project_index_exe" ]; then
    return
  fi
  # 1. Locate cmake's Modules dir.
  local modules_dir=""
  if [ -n "${CMAKE_STDLIB_ROOT:-}" ]; then
    modules_dir="${CMAKE_STDLIB_ROOT}"
  else
    # Ask cmake itself: a one-line cmake -P script prints CMAKE_ROOT.
    # cmake puts CMAKE_ROOT in every cmake-script context.
    local cmake_root
    cmake_root=$(printf 'message("${CMAKE_ROOT}")\n' \
      | cmake -P /dev/stdin 2>&1 | tail -1)
    if [ -n "$cmake_root" ] && [ -d "$cmake_root/Modules" ]; then
      modules_dir="$cmake_root/Modules"
    else
      # Fallbacks for systems where cmake -P /dev/stdin is wonky.
      for d in /usr/share/cmake-4.3/Modules /usr/share/cmake/Modules; do
        if [ -d "$d" ]; then modules_dir="$d"; break; fi
      done
    fi
  fi
  if [ -z "$modules_dir" ] || [ ! -d "$modules_dir" ]; then
    return
  fi
  # 2. Key the cache by the resolved Modules dir (encodes cmake version).
  local stdlib_key
  stdlib_key=$(printf '%s' "$modules_dir" | sha256sum | cut -d' ' -f1)
  local stdlib_file="/tmp/bar3lite_stdlib_${stdlib_key}.tsv"
  if [ ! -f "$stdlib_file" ] || [ -n "${REBUILD_CMAKE_STDLIB:-}" ]; then
    "$project_index_exe" "$modules_dir" > "$stdlib_file" 2>/dev/null || true
  fi
  echo "$stdlib_file"
}

if [ -z "${NO_CORPUS_INDEX:-}" ] && [ -x "$project_index_exe" ]; then
  corpus_abs_for_idx=$(cd "$corpus" && pwd)
  idx_key=$(printf '%s' "$corpus_abs_for_idx" | sha256sum | cut -d' ' -f1)
  CORPUS_INDEX_FILE="/tmp/bar3lite_index_${idx_key}.tsv"
  if [ ! -f "$CORPUS_INDEX_FILE" ] || [ -n "${REBUILD_CORPUS_INDEX:-}" ]; then
    "$project_index_exe" "$corpus_abs_for_idx" > "$CORPUS_INDEX_FILE" \
      2>/dev/null || true
  fi
  export CORPUS_INDEX_FILE
fi

CMAKE_STDLIB_INDEX_FILE=$(prepare_cmake_stdlib_index)
if [ -n "$CMAKE_STDLIB_INDEX_FILE" ]; then
  export CMAKE_STDLIB_INDEX_FILE
fi

# Extract (command, args) tuples from a cmake source via tree-sitter.
# Output: one line per command of the form `name(a1 a2 ...)`.
extract_struct() {
  python3 -c "
import sys, tree_sitter_cmake, tree_sitter
lang = tree_sitter.Language(tree_sitter_cmake.language())
parser = tree_sitter.Parser(lang)
src = sys.stdin.buffer.read()
tree = parser.parse(src)
BLOCKS = ('if_condition','foreach_loop','while_loop','function_def','macro_def','block_def')
HEADS = ('if_command','elseif_command','else_command','endif_command',
         'foreach_command','endforeach_command','while_command','endwhile_command',
         'function_command','endfunction_command','macro_command','endmacro_command',
         'block_command','endblock_command')
HEADWORDS = ('if','elseif','else','endif','foreach','endforeach','while','endwhile',
             'function','endfunction','macro','endmacro','block','endblock')
def cmd(node):
    # Match parse.py's parse_command_head shape: block heads/tails
    # (e.g. endforeach(x)) can expose `argument` children directly on
    # the command node rather than wrapped in argument_list. Collect
    # both shapes so the oracle doesn't silently drop args.
    name=None; args=[]
    for cc in node.children:
        if cc.type=='identifier' or (cc.type in HEADWORDS and name is None):
            name=src[cc.start_byte:cc.end_byte].decode('utf-8')
        elif cc.type=='argument_list':
            for arg in cc.children:
                if arg.type=='argument':
                    args.append(src[arg.start_byte:arg.end_byte].decode('utf-8'))
        elif cc.type=='argument':
            args.append(src[cc.start_byte:cc.end_byte].decode('utf-8'))
    return (name or '?') + '(' + ' '.join(args) + ')'
def walk(node):
    out=[]
    for c in node.children:
        if c.type=='normal_command' or c.type in HEADS:
            out.append(cmd(c))
        elif c.type in BLOCKS or c.type=='body':
            out.extend(walk(c))
    return out
for line in walk(tree.root_node):
    print(line)
"
}

while IFS= read -r f; do
  rel=${f#$corpus/}
  json=$(python3 "$parse_py" "$f" 2>/dev/null)
  if [ -z "$json" ]; then
    echo "PARSE  $rel"
    parse=$((parse+1))
    continue
  fi

  # Stage 2: emit + coverage tally.
  # `modeled` = command mapped to a typed Lang_cmake.exp ctor.
  # `generic` = flowed through Apply (preserved verbatim, no IR shape).
  # `other`   = control-flow heads, raw passthrough, tree-sitter errors.
  # We deliberately do NOT report a modeled / (modeled+generic) ratio.
  # Many generic calls (z3_add_component, tablegen, add_llvm_*, CheckXxx)
  # are project/module-defined cmake functions that are correctly never
  # "typed" by Lang_cmake.exp — the ratio conflates "we haven't modeled
  # this builtin yet" with "this is user-defined and should stay
  # generic". Raw counts are the honest indicator.
  stage2=$(echo "$json" | STAGE2_COVERAGE=1 "$print2" 2>/tmp/_cov_$$.tmp)
  t=$(grep -oE "modeled=[0-9]+" /tmp/_cov_$$.tmp | head -1 | cut -d= -f2); t=${t:-0}
  s=$(grep -oE "stdlib=[0-9]+" /tmp/_cov_$$.tmp | head -1 | cut -d= -f2); s=${s:-0}
  r=$(grep -oE "resolved=[0-9]+" /tmp/_cov_$$.tmp | head -1 | cut -d= -f2); r=${r:-0}
  g=$(grep -oE "generic=[0-9]+" /tmp/_cov_$$.tmp | head -1 | cut -d= -f2); g=${g:-0}
  o=$(grep -oE "other=[0-9]+" /tmp/_cov_$$.tmp | head -1 | cut -d= -f2); o=${o:-0}
  modeled_total=$((modeled_total + t))
  stdlib_total=$((stdlib_total + s))
  resolved_total=$((resolved_total + r))
  generic_total=$((generic_total + g))
  other_total=$((other_total + o))

  # Structural oracle: command sequence must match
  ref_struct=$(extract_struct < "$f" 2>/dev/null)
  got_struct=$(echo "$stage2" | extract_struct 2>/dev/null)
  if [ "$ref_struct" != "$got_struct" ]; then
    echo "STRUCT $rel"
    struct=$((struct+1))
    continue
  fi

  # gersemi-diff oracle. Pre-strip cmake comments on both sides
  # via tree-sitter (since our parser drops them) and gersemi-
  # normalize. Then collapse all whitespace runs to a single space
  # for comparison — gersemi preserves the user's multi-line vs
  # single-line argument-list choice regardless of --line-length,
  # so we can't byte-compare; whitespace normalization gives
  # content equivalence modulo layout. Also strip the
  # stderr-style "Warning: unknown command" header that gersemi
  # prints with different file paths.
  normalize() {
    grep -v "^Warning:" \
      | grep -v "^/" \
      | grep -v "^<stdin>" \
      | grep -v "^[[:space:]]*#" \
      | tr -s '[:space:]' ' ' \
      | sed 's/^ //; s/ $//; s/ )/)/g; s/( /(/g'
  }
  ref=$(python3 "$strip_comments" "$f" 2>/dev/null \
        | "$gersemi" $gersemi_args - 2>/dev/null | normalize)
  got=$(echo "$stage2" | "$gersemi" $gersemi_args - 2>/dev/null | normalize)
  # Per-file slot shape:
  #   t/s/r/g/o  when either index is loaded (5-bucket)
  #   t/g/o      when neither is loaded (legacy 3-bucket)
  if [ -n "${CORPUS_INDEX_FILE:-}" ] || [ -n "${CMAKE_STDLIB_INDEX_FILE:-}" ]; then
    slot="$t/$s/$r/$g/$o"
  else
    slot="$t/$g/$o"
  fi
  if [ "$ref" = "$got" ]; then
    echo "OK     $rel  $slot"
    ok=$((ok+1))
  else
    echo "FORMAT $rel  $slot"
    format=$((format+1))
  fi
done < <(
  # FILTER_PATTERN, if set, narrows the corpus to files matching the
  # pattern (grep -E semantics). Useful during development on a single
  # command — e.g. FILTER_PATTERN='file *\( *COPY' to test only files
  # using `file(COPY ...)`. Without it, the full corpus is processed.
  #
  # We cache the find result per-corpus under /tmp keyed by the
  # absolute corpus path's sha256. Find takes ~130ms even on llvm so
  # caching is a small win in absolute terms, but it's useful when
  # iterating on the same corpus repeatedly (e.g. one FILTER_PATTERN
  # per dev cycle). Set NO_CORPUS_CACHE=1 to bypass.
  corpus_abs=$(cd "$corpus" && pwd)
  cache_key=$(printf '%s' "$corpus_abs" | sha256sum | cut -d' ' -f1)
  cache_file="/tmp/bar3lite_files_${cache_key}.txt"
  if [ -z "${NO_CORPUS_CACHE:-}" ] && [ -f "$cache_file" ]; then
    : # use cached file list
  else
    find "$corpus" \( -name CMakeLists.txt -o -name "*.cmake" \) -type f \
      2>/dev/null > "$cache_file"
  fi
  if [ -n "${FILTER_PATTERN:-}" ]; then
    xargs grep -lE "$FILTER_PATTERN" 2>/dev/null < "$cache_file"
  else
    cat "$cache_file"
  fi
)

rm -f /tmp/_cov_$$.tmp

total=$((ok+format+struct+parse))
echo "===="
echo "TOTAL: $total"
echo "  OK     $ok    (structural pass AND gersemi-diff pass)"
echo "  FORMAT $format    (structural pass, gersemi-diff fail)"
echo "  STRUCT $struct    (structural fail — real parser/printer bug)"
echo "  PARSE  $parse    (tree-sitter or reader fail)"
if [ -n "${CORPUS_INDEX_FILE:-}" ] || [ -n "${CMAKE_STDLIB_INDEX_FILE:-}" ]; then
  echo "Stage 2 cmds: modeled=$modeled_total stdlib=$stdlib_total resolved=$resolved_total generic=$generic_total other=$other_total"
else
  echo "Stage 2 cmds: modeled=$modeled_total generic=$generic_total other=$other_total"
fi
# Provenance: print which indices were consumed (and how many names).
if [ -n "${CMAKE_STDLIB_INDEX_FILE:-}" ] && [ -f "$CMAKE_STDLIB_INDEX_FILE" ]; then
  stdlib_n=$(wc -l < "$CMAKE_STDLIB_INDEX_FILE" 2>/dev/null || echo "?")
  echo "  cmake-stdlib index: $CMAKE_STDLIB_INDEX_FILE ($stdlib_n entries)"
fi
if [ -n "${CORPUS_INDEX_FILE:-}" ] && [ -f "$CORPUS_INDEX_FILE" ]; then
  corpus_n=$(wc -l < "$CORPUS_INDEX_FILE" 2>/dev/null || echo "?")
  echo "  corpus index:       $CORPUS_INDEX_FILE ($corpus_n entries)"
fi
