#!/usr/bin/env python3
"""Strip comments from cmake source using tree-sitter-cmake.

Reads cmake source from a file (argv[1]) or stdin, writes a
comment-free version to stdout. Used by the round-trip harness
as a preprocessor so the FORMAT oracle compares
comment-free cmake on both sides — our parser drops inline
arg-list comments, and gersemi otherwise preserves multi-line
layouts triggered by those comments.

A simple regex would mishandle:
  - bracket comments `#[==[ multi-line ]==]`
  - `#` inside quoted strings (`"a # b"`)
  - `#` inside bracket arguments

tree-sitter knows which `#` is which; we collect the byte
ranges of every comment node and excise them from the source.

The embedding question — whether yelu_cmake / yelu_cmake_normal
should carry comments as AST metadata — is separate and TBD.
For now we strip them entirely on the comparison side.
"""

import sys
import tree_sitter
import tree_sitter_cmake


COMMENT_TYPES = ('line_comment', 'bracket_comment')


def collect_comment_ranges(node, ranges):
    """Walk the CST, accumulating (start, end) byte ranges for
    every comment node we encounter."""
    if node.type in COMMENT_TYPES:
        ranges.append((node.start_byte, node.end_byte))
        return
    for child in node.children:
        collect_comment_ranges(child, ranges)


def strip(src: bytes) -> bytes:
    lang = tree_sitter.Language(tree_sitter_cmake.language())
    parser = tree_sitter.Parser(lang)
    tree = parser.parse(src)
    ranges = []
    collect_comment_ranges(tree.root_node, ranges)
    ranges.sort()
    out = bytearray()
    pos = 0
    for start, end in ranges:
        if start < pos:  # nested / overlapping; skip
            continue
        out.extend(src[pos:start])
        pos = end
    out.extend(src[pos:])
    return bytes(out)


def main():
    if len(sys.argv) > 1 and sys.argv[1] != '-':
        with open(sys.argv[1], 'rb') as f:
            src = f.read()
    else:
        src = sys.stdin.buffer.read()
    sys.stdout.buffer.write(strip(src))


if __name__ == '__main__':
    main()
