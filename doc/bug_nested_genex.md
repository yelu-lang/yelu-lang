# Bug: Nested `$<...>` generator expressions not supported by lexer

## Symptom

```
$<IF:$<CONFIG:Debug>,debug,release>
```

Lexes as `EVAL "$<IF:$<CONFIG:Debug>"` (truncated at first `>`) instead of
`EVAL "$<IF:$<CONFIG:Debug>,debug,release>"`. The remaining characters
`,debug,release>` are left as unconsumed input, causing downstream parse errors.

## Current lexer code

File: `src/langs/yelu/lang_yelu_lexer.ml`, the `eval_lit` parser:

```ocaml
let eval_lit =
  let not_brace c = not (Char.equal c '}') in
  let not_angle c = not (Char.equal c '>') in
  token (
    char '$' *> (
      (char '{' *> take_while not_brace <* char '}'
       >>| fun s -> EVAL ("${" ^ s ^ "}"))
      <|>
      (char '<' *> take_while not_angle <* char '>'
       >>| fun s -> EVAL ("$<" ^ s ^ ">"))
    ))
```

The problem: `take_while not_angle` consumes every character that isn't `>`.
For `$<IF:$<CONFIG:Debug>,debug,release>`, it stops at the first `>` (after
`Debug`), producing `EVAL "$<IF:$<CONFIG:Debug>"`. This is correct for
non-nested genex like `$<CONFIG>` but wrong for nested ones.

`${VAR}` doesn't have this problem because cmake variable expansion doesn't
nest — `${...}` always matches the first `}`.

## Required algorithm: bracket counting

Instead of `take_while not_angle`, the lexer needs to track nesting depth.
After `$<`, scan forward counting `<` and `>`:

```ocaml
let eval_genex =
  char '$' *> char '<' *>
  let rec scan depth acc =
    peek_char >>= function
    | None -> fail "unterminated genex"
    | Some '<' -> advance 1 *> scan (depth + 1) (acc ^ "<")
    | Some '>' when depth = 0 -> return (EVAL ("$<" ^ acc ^ ">"))
    | Some '>' -> advance 1 *> scan (depth - 1) (acc ^ ">")
    | Some c -> advance 1 *> scan depth (acc ^ String.of_char c)
  in
  token (scan 0 "")
```

This increments depth on `<`, decrements on `>`, and stops only when depth
reaches 0. For `$<IF:$<CONFIG:Debug>,debug,release>`:

```
$<   → depth=0, start scan
I    → acc="I"
F    → acc="IF"
:    → acc="IF:"
$<   → depth=1, acc="IF:$<"
C    → acc="IF:$<C"
...
g    → acc="IF:$<CONFIG:Debug"
>    → depth=0, acc="IF:$<CONFIG:Debug>"    ← NOT done (still scanning)
,    → acc="IF:$<CONFIG:Debug>,"
...
e    → acc="IF:$<CONFIG:Debug>,debug,release"
>    → depth=0, DONE → EVAL "$<IF:$<CONFIG:Debug>,debug,release>"
```

## Why this wasn't done yet

The original lexer was written for simple cases (`$<CONFIG>`, `$<TARGET_FILE:tgt>`).
Nested genex (`$<IF:...>`, `$<AND:...>`, `$<NOT:...>`) were deferred because
the parser was the priority. The fix is a ~15-line change in the lexer that
has zero impact on the rest of the codebase, since the `EVAL` token
representation doesn't change — only the lexer's ability to correctly
tokenize nested expressions changes.

## Scope of change

- File: `src/langs/yelu/lang_yelu_lexer.ml`
- Function: `eval_lit` (~lines 120-132)
- Replace: `take_while not_angle` with a depth-counting scan
- `${...}` branch unchanged (no nesting in cmake variables)
- No parser, typechecker, compiler, or wellform changes needed

## Fix applied (2026-05-07)

Algorithm: bracket-counting on `$<` / `>` pairs, not bare `<`. Key details:

1. Both `${...}` and `$<...>` branches must share the same `char '$'` consumer
   inside a single `token`. Otherwise Angstrom `<|>` can't backtrack past the `$`.

2. `Buffer.clear` must be called inside `return () >>=` — otherwise it runs at
   module init time, not parse time, and stale data from previous calls corrupts
   subsequent lexes.

3. Only `$<` increments depth (not bare `<`). cmake genex nesting delimiter is `$<`.

Final code in `src/langs/yelu/lang_yelu_lexer.ml`:

```ocaml
let eval_lit =
  let not_brace c = not (Char.equal c '}') in
  let buf = Buffer.create 64 in
  let rec scan depth =
    peek_char >>= function
    | None -> fail "unterminated generator expression"
    | Some '>' when depth = 0 ->
        advance 1 *> return (EVAL ("$<" ^ Buffer.contents buf ^ ">"))
    | Some '>' ->
        advance 1 *> (Buffer.add_char buf '>'; scan (depth - 1))
    | Some '$' ->
        advance 1 *> peek_char >>= (function
          | Some '<' -> advance 1 *> (Buffer.add_string buf "$<"; scan (depth + 1))
          | _ -> Buffer.add_char buf '$'; scan depth)
    | Some c ->
        advance 1 *> (Buffer.add_char buf c; scan depth)
  in
  token (
    char '$' *> (
      (char '{' *> take_while not_brace <* char '}'
       >>| fun s -> EVAL ("${" ^ s ^ "}"))
      <|>
      (char '<' *> return () >>= fun () -> Buffer.clear buf; scan 0)
    ))
```

Tests: 4 new lexer tests (simple genex, nested, double-nested, ${VAR} unchanged),
2 new parser tests (nested genex in compile_opts, TARGET_FILE in message).
23 lexer tests, 167 parser tests, 513 total.

===

你的 diagnosis 是对的：**`take_while not_angle` 一定会在第一个 `>` 停，所以不可能支持嵌套 `$<...>`。**
这个确实应该在 lexer 层修，因为 token 仍然是一个 `EVAL of string`，parser 不需要知道 genex 内部结构。

不过你给的 bracket-counting 算法有一个小风险：**它在任何 `<` 上增加深度，而 CMake generator expression 的嵌套起点其实是 `$<`，不是裸 `<`。**

也就是说，最好不要写成：

```ocaml
| Some '<' -> scan (depth + 1) ...
```

而是只在看到 **`$<`** 时进入更深一层。否则如果 genex 参数里未来出现普通 `<`，lexer 会错误地把它当作嵌套 genex 起点。

更稳的逻辑是：

```text
已经消费外层 "$<"
depth = 0

扫描内部字符：
- 遇到 "$<"：depth += 1，并把 "$<" 写入 acc
- 遇到 ">" 且 depth = 0：结束外层 genex
- 遇到 ">" 且 depth > 0：depth -= 1，并把 ">" 写入 acc
- 其他字符：普通写入 acc
```

你的例子：

```text
$<IF:$<CONFIG:Debug>,debug,release>
```

应该得到：

```ocaml
EVAL "$<IF:$<CONFIG:Debug>,debug,release>"
```

而不是：

```ocaml
EVAL "$<IF:$<CONFIG:Debug>"
```

## 我建议的 Angstrom 写法

不要用字符串反复 `acc ^ ...`，那是 O(n²)。虽然 genex 很短时没事，但 lexer 里还是建议用 `Buffer`。

大概可以这样写：

```ocaml
open Angstrom

let eval_genex =
  char '$' *> char '<' *>
  let buf = Buffer.create 64 in
  let rec scan depth =
    peek_char >>= function
    | None ->
        fail "unterminated generator expression"

    | Some '>' when depth = 0 ->
        advance 1
        *> return (EVAL ("$<" ^ Buffer.contents buf ^ ">"))

    | Some '>' ->
        advance 1
        *> (Buffer.add_char buf '>';
            scan (depth - 1))

    | Some '$' ->
        peek_string 2 >>= fun s ->
        if String.equal s "$<" then
          advance 2
          *> (Buffer.add_string buf "$<";
              scan (depth + 1))
        else
          advance 1
          *> (Buffer.add_char buf '$';
              scan depth)

    | Some c ->
        advance 1
        *> (Buffer.add_char buf c;
            scan depth)
  in
  scan 0
```

然后 `eval_lit` 变成：

```ocaml
let eval_lit =
  let not_brace c = not (Char.equal c '}') in
  token
    (char '$' *> (
       (char '{' *> take_while not_brace <* char '}'
        >>| fun s -> EVAL ("${" ^ s ^ "}"))
       <|>
       (char '<' *>
        let buf = Buffer.create 64 in
        let rec scan depth =
          peek_char >>= function
          | None ->
              fail "unterminated generator expression"
          | Some '>' when depth = 0 ->
              advance 1
              *> return (EVAL ("$<" ^ Buffer.contents buf ^ ">"))
          | Some '>' ->
              advance 1
              *> (Buffer.add_char buf '>';
                  scan (depth - 1))
          | Some '$' ->
              peek_string 2 >>= fun s ->
              if String.equal s "$<" then
                advance 2
                *> (Buffer.add_string buf "$<";
                    scan (depth + 1))
              else
                advance 1
                *> (Buffer.add_char buf '$';
                    scan depth)
          | Some c ->
              advance 1
              *> (Buffer.add_char buf c;
                  scan depth)
        in
        scan 0)
     ))
```

如果你不想在 `eval_lit` 里嵌这么大一块，可以拆成：

```ocaml
let cmake_var_lit = ...
let cmake_genex_lit = ...
let eval_lit = token (cmake_var_lit <|> cmake_genex_lit)
```

会更干净。

## 需要注意一个 Angstrom 细节

`peek_string 2` 在输入剩余不足 2 字符时的行为要确认一下。如果它会 fail，那在最后一个 `$` 处可能导致整个 parser fail。更保守的写法是先 `advance 1`，再看下一个字符是否 `<`，但那样要处理回填 `$`。

可以写得更安全一点：

```ocaml
| Some '$' ->
    advance 1 *>
    peek_char >>= function
    | Some '<' ->
        advance 1
        *> (Buffer.add_string buf "$<";
            scan (depth + 1))
    | _ ->
        Buffer.add_char buf '$';
        scan depth
```

这个版本不依赖 `peek_string 2`：

```ocaml
let genex_body =
  let buf = Buffer.create 64 in
  let rec scan depth =
    peek_char >>= function
    | None ->
        fail "unterminated generator expression"

    | Some '>' when depth = 0 ->
        advance 1
        *> return (EVAL ("$<" ^ Buffer.contents buf ^ ">"))

    | Some '>' ->
        advance 1
        *> (Buffer.add_char buf '>';
            scan (depth - 1))

    | Some '$' ->
        advance 1 *>
        peek_char >>= (function
          | Some '<' ->
              advance 1
              *> (Buffer.add_string buf "$<";
                  scan (depth + 1))
          | _ ->
              Buffer.add_char buf '$';
              scan depth)

    | Some c ->
        advance 1
        *> (Buffer.add_char buf c;
            scan depth)
  in
  scan 0
```

然后：

```ocaml
let eval_lit =
  let not_brace c = not (Char.equal c '}') in
  token (
    char '$' *> (
      (char '{' *> take_while not_brace <* char '}'
       >>| fun s -> EVAL ("${" ^ s ^ "}"))
      <|>
      (char '<' *> genex_body)
    ))
```

## 测试应该补这些

最少补四类：

```text
$<CONFIG:Debug>
```

期望：

```ocaml
EVAL "$<CONFIG:Debug>"
```

```text
$<IF:$<CONFIG:Debug>,debug,release>
```

期望：

```ocaml
EVAL "$<IF:$<CONFIG:Debug>,debug,release>"
```

```text
$<AND:$<CONFIG:Debug>,$<BOOL:${FOO}>>
```

期望：

```ocaml
EVAL "$<AND:$<CONFIG:Debug>,$<BOOL:${FOO}>>"
```

```text
$<IF:$<CONFIG:Debug>,debug,release
```

期望 lexer fail，错误类似：

```text
unterminated generator expression
```

另外也要测普通变量不受影响：

```text
${VAR}
```

仍然是：

```ocaml
EVAL "${VAR}"
```

## 我会怎么评价这个 fix scope

你的判断是对的：

```text
No parser, typechecker, compiler, or wellform changes needed
```

因为这不是 AST 语义问题，而是 lexer 没有正确识别一个 lexical atom。`EVAL` token 表示不变，所以后面层级不该动。

唯一我会修正的是这句话：

```text
After $<, scan forward counting < and >
```

我会改成：

```text
After $<, scan forward counting nested $< ... > pairs.
```

这个区别小，但很重要。
**CMake genex 的嵌套 delimiter 是 `$<`，不是 `<`。**

==

这个 fix 看起来方向正确，而且比最初的 “count bare `<` / `>`” 版本稳很多。核心点我认可：

```text
nested delimiter = "$<" ... ">"
```

而不是：

```text
nested delimiter = "<" ... ">"
```

这点很重要。

不过我会指出两个需要再想一下的地方。

## 1. `Buffer` 放在 parser 闭包外，可以工作，但容易埋状态坑

你现在是：

```ocaml
let buf = Buffer.create 64 in
let rec scan depth = ...
```

然后在 `$<...>` 分支里：

```ocaml
return () >>= fun () -> Buffer.clear buf; scan 0
```

这样确实解决了“模块初始化时清空一次，而不是每次 parse 清空”的问题。

但我还是更建议把 `Buffer.create` 放进 parse-time 分支里：

```ocaml
(char '<' *>
 return () >>= fun () ->
 let buf = Buffer.create 64 in
 let rec scan depth = ... in
 scan 0)
```

原因是这个 parser value 可能被复用。现在靠 `Buffer.clear` 维持不变量，逻辑上没错，但这是一个隐式状态约定。以后如果有人改 `scan` 的失败路径、并发复用 parser、或者把 `eval_lit` 拿到增量解析场景里，外部 mutable buffer 会变得更难推理。

更纯的版本是：**每次解析一个 genex，创建一个新 buffer。**
这样不需要记住 “必须在 parse time clear”。

## 2. `char '$'` 提到共同前缀是对的，但理由可以写得更保守

你写：

> Otherwise Angstrom `<|>` can't backtrack past the `$`.

这句话我会稍微改一下。Angstrom 的 choice/backtracking 语义比很多 parser combinator 更宽松，不一定所有情况下都不能回退。但把共同前缀提出去仍然是正确工程选择，因为它：

* 避免两个分支重复消费 `$`
* 避免 backtracking 语义依赖
* 让错误位置更清楚
* 让 `${...}` 和 `$<...>` 都明确属于同一个 lexical family

所以我会把这条记录成：

```text
Both branches share the same `char '$'` consumer inside one token, so branch choice happens after `$` and does not depend on cross-branch backtracking.
```

这比 “Angstrom can’t backtrack” 更不容易被挑刺。

## 3. 还应该补一个裸 `<` 测试

既然这次明确修的是 “只在 `$<` 上加深度”，我会加一个 regression test，确保裸 `<` 不影响 nesting：

```text
$<IF:a<b,yes,no>
```

预期整个 token 是：

```ocaml
EVAL "$<IF:a<b,yes,no>"
```

如果这个例子在 CMake genex 语义里不合适，也可以换成任何含普通 `<` 字符的 payload。重点是锁住这个不变量：

```text
bare '<' is not a nesting delimiter
```

## 4. 也建议补一个 unterminated nested genex 测试

比如：

```text
$<IF:$<CONFIG:Debug>,debug,release
```

应该 lexer fail with：

```text
unterminated generator expression
```

这能确保失败路径没有把半截 token 吞掉后继续 parse。

## 5. 当前测试数很健康

```text
23 lexer tests
167 parser tests
513 total
```

这个状态挺好。尤其你补了：

* simple genex
* nested genex
* double-nested genex
* `${VAR}` unchanged
* parser-level compile opts
* parser-level `TARGET_FILE` in message

这说明修复不是只在 lexer 单测里通过，也验证了真实语法路径。

## 我会怎么总结这个 fix

这个 bug 的本质是：

```text
The lexer treated `$<...>` as a flat angle-delimited literal, but CMake generator expressions are recursively delimited by `$<` and `>`.
```

修复后的不变量是：

```text
Inside a generator expression, only `$<` increases nesting depth; `>` closes the current generator expression level; the outer token ends only when depth returns to zero.
```

我的唯一实质建议是：**把 `Buffer.create` 移到 parse-time 分支内部，消除 shared mutable parser state。** 其他部分看起来是正确的。
