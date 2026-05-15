#!/usr/bin/env python3
"""tree-sitter-cmake CST -> JSON for the OCaml round-trip prototype.

Reads cmake source from a file (argv[1]) or stdin and writes a JSON
tree to stdout. The format is the minimum the OCaml side needs to
reprint cmake text. Each argument carries its raw source text so the
quoting style (unquoted / quoted / bracket) is preserved.

Stage 1 goal: round-trip step1's emitted cmake (7 commands, no
control flow). Control-flow wrappers (if/foreach/while/function/
macro/block) are handled as nested nodes so the JSON tree mirrors
the cmake block structure rather than the flat token stream.
"""

import json
import sys
import tree_sitter
import tree_sitter_cmake


def get_text(node, src):
    return src[node.start_byte:node.end_byte].decode('utf-8')


def parse_argument(node, src):
    """Extract the raw source text of one argument node, preserving
    quoting / bracket framing."""
    return get_text(node, src)


def collect_args(arg_list_node, src):
    """Walk an argument_list, preserving both `argument` nodes and the
    parenthesis tokens used for grouping (cmake `if((A AND B))` shape).
    The literal `(` / `)` are kept as args so reprinting reproduces the
    original grouping."""
    out = []
    for child in arg_list_node.children:
        if child.type == 'argument':
            out.append(parse_argument(child, src))
        elif child.type in ('(', ')'):
            out.append(child.type)
    return out


def parse_normal_command(node, src):
    """A `normal_command` is: identifier '(' argument_list? ')'."""
    name = None
    args = []
    for child in node.children:
        if child.type == 'identifier':
            name = get_text(child, src)
        elif child.type == 'argument_list':
            args = collect_args(child, src)
    return {'kind': 'cmd', 'name': name, 'args': args}


def parse_command_head(node, src, expected_type):
    """The head of a control-flow block is itself a normal_command-like
    node (e.g. `if_command`, `endif_command`). Parse it the same way."""
    name = None
    args = []
    for child in node.children:
        if child.type == 'identifier' or child.type in (
            'if', 'elseif', 'else', 'endif', 'foreach', 'endforeach',
            'while', 'endwhile', 'function', 'endfunction',
            'macro', 'endmacro', 'block', 'endblock'
        ):
            # First lexeme is the command keyword.
            if name is None:
                name = get_text(child, src)
        elif child.type == 'argument_list':
            args = collect_args(child, src)
    return {'kind': 'cmd', 'name': name, 'args': args}


def parse_body(node, src):
    """A `body` node contains a flat list of statements. Same shape as
    `source_file` children."""
    return [parse_stmt(c, src) for c in node.children
            if c.type not in ('line_comment', 'bracket_comment')]


def parse_block(node, src, head_type, tail_type, mid_types=()):
    """Generic block parser: head + body + (clause_head + body)* + tail.

    tree-sitter lays bodies out as flat siblings between command nodes;
    we attach each body to the most recently seen head (initially the
    block head, then the latest mid clause)."""
    head = None
    head_body = []
    clauses = []  # list of {'head': cmd, 'body': stmt list}
    tail = None
    current_target = 'head'  # 'head' or index into clauses
    for child in node.children:
        t = child.type
        if t == head_type:
            head = parse_command_head(child, src, head_type)
            current_target = 'head'
        elif t == 'body':
            stmts = parse_body(child, src)
            if current_target == 'head':
                head_body = stmts
            else:
                clauses[current_target]['body'] = stmts
        elif t in mid_types:
            clauses.append({
                'head': parse_command_head(child, src, t),
                'body': [],
            })
            current_target = len(clauses) - 1
        elif t == tail_type:
            tail = parse_command_head(child, src, tail_type)
    return {
        'kind': 'block',
        'block_type': head_type.replace('_command', ''),
        'head': head,
        'body': head_body,
        'clauses': clauses,
        'tail': tail,
    }


def parse_stmt(node, src):
    t = node.type
    if t == 'normal_command':
        return parse_normal_command(node, src)
    if t == 'if_condition':
        # if + (elseif*) + (else?) + endif
        return parse_block(
            node, src, 'if_command', 'endif_command',
            mid_types=('elseif_command', 'else_command'),
        )
    if t == 'foreach_loop':
        return parse_block(node, src, 'foreach_command', 'endforeach_command')
    if t == 'while_loop':
        return parse_block(node, src, 'while_command', 'endwhile_command')
    if t == 'function_def':
        return parse_block(node, src, 'function_command', 'endfunction_command')
    if t == 'macro_def':
        return parse_block(node, src, 'macro_command', 'endmacro_command')
    if t == 'block_def':
        return parse_block(node, src, 'block_command', 'endblock_command')
    if t in ('line_comment', 'bracket_comment'):
        return None
    if t == 'ERROR':
        # tree-sitter couldn't parse this fragment. Preserve the raw
        # source so the round-trip is still byte-identical (modulo
        # gersemi normalization). Common case: .cmake.in templates
        # with @PACKAGE_INIT@ etc.
        return {'kind': 'raw', 'text': get_text(node, src)}
    # Recognized tree-sitter node we don't know how to handle yet.
    # Surface it as 'unknown' so the printer can flag it loudly.
    return {'kind': 'unknown', 'type': t, 'text': get_text(node, src)}


def parse_source(src):
    lang = tree_sitter.Language(tree_sitter_cmake.language())
    parser = tree_sitter.Parser(lang)
    tree = parser.parse(src)
    # If the entire root is an error (e.g., a .cmake.in template that
    # tree-sitter mis-lexes as one giant bracket_argument), fall back
    # to emitting the whole file as raw text. Gersemi handles
    # opaque-but-valid cmake text idempotently.
    root = tree.root_node
    if root.has_error and all(c.type == 'ERROR' for c in root.children):
        return {'kind': 'source_file',
                'stmts': [{'kind': 'raw', 'text': src.decode('utf-8')}]}
    stmts = [parse_stmt(c, src) for c in root.children]
    stmts = [s for s in stmts if s is not None]
    return {'kind': 'source_file', 'stmts': stmts}


def main():
    if len(sys.argv) > 1 and sys.argv[1] != '-':
        with open(sys.argv[1], 'rb') as f:
            src = f.read()
    else:
        src = sys.stdin.buffer.read()
    tree = parse_source(src)
    json.dump(tree, sys.stdout, separators=(',', ':'))
    sys.stdout.write('\n')


if __name__ == '__main__':
    main()
