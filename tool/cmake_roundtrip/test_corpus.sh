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

ok=0; format=0; struct=0; parse=0
modeled_total=0; generic_total=0; other_total=0

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
    name=None; args=[]
    for cc in node.children:
        if cc.type=='identifier' or (cc.type in HEADWORDS and name is None):
            name=src[cc.start_byte:cc.end_byte].decode('utf-8')
        elif cc.type=='argument_list':
            for arg in cc.children:
                if arg.type=='argument':
                    args.append(src[arg.start_byte:arg.end_byte].decode('utf-8'))
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
  g=$(grep -oE "generic=[0-9]+" /tmp/_cov_$$.tmp | head -1 | cut -d= -f2); g=${g:-0}
  o=$(grep -oE "other=[0-9]+" /tmp/_cov_$$.tmp | head -1 | cut -d= -f2); o=${o:-0}
  modeled_total=$((modeled_total + t))
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
  if [ "$ref" = "$got" ]; then
    echo "OK     $rel  $t/$g/$o"
    ok=$((ok+1))
  else
    echo "FORMAT $rel  $t/$g/$o"
    format=$((format+1))
  fi
done < <(find "$corpus" \( -name CMakeLists.txt -o -name "*.cmake" \) -type f 2>/dev/null)

rm -f /tmp/_cov_$$.tmp

total=$((ok+format+struct+parse))
echo "===="
echo "TOTAL: $total"
echo "  OK     $ok    (structural pass AND gersemi-diff pass)"
echo "  FORMAT $format    (structural pass, gersemi-diff fail)"
echo "  STRUCT $struct    (structural fail — real parser/printer bug)"
echo "  PARSE  $parse    (tree-sitter or reader fail)"
echo "Stage 2 cmds: modeled=$modeled_total generic=$generic_total other=$other_total"
