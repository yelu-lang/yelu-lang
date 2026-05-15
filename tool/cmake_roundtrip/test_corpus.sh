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

ok=0; format=0; struct=0; parse=0
typed_total=0; generic_total=0; other_total=0

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

  # Stage 2: emit + coverage tally
  stage2=$(echo "$json" | STAGE2_COVERAGE=1 "$print2" 2>/tmp/_cov_$$.tmp)
  t=$(grep -oE "typed=[0-9]+" /tmp/_cov_$$.tmp | head -1 | cut -d= -f2); t=${t:-0}
  g=$(grep -oE "generic=[0-9]+" /tmp/_cov_$$.tmp | head -1 | cut -d= -f2); g=${g:-0}
  o=$(grep -oE "other=[0-9]+" /tmp/_cov_$$.tmp | head -1 | cut -d= -f2); o=${o:-0}
  typed_total=$((typed_total + t))
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

  # gersemi-diff oracle: stricter, sensitive to formatting
  ref=$("$gersemi" "$f" 2>/dev/null | grep -v "^$")
  got=$(echo "$stage2" | "$gersemi" - 2>/dev/null | grep -v "^$")
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
echo "Stage 2 cmds: typed=$typed_total generic=$generic_total other=$other_total"
echo "  typed/(typed+generic) = $(awk "BEGIN{printf \"%.1f%%\", $typed_total*100/($typed_total+$generic_total+0.0001)}")"
