````markdown
# Architecture decision: expression extensibility in yelu

## Summary

Do not treat `boolean theory` as the owner of all expressions that return `Ty_bool`.

Instead:

- Each theory owns its own expression-level operations.
- An operation may return `Ty_bool`, `Ty_string`, `Ty_int`, `Ty_path`, etc.
- `Ty_bool` is a result type, not an ownership boundary.
- `if` should accept `yelu_expr`, and the typechecker should verify that the expression has type `Ty_bool`.
- The final pack-level language owns the closed recursive `yelu_expr` type.
- Individual theories should define small parameterized expression fragments, usually of the form `'expr t`.

This means:

```ocaml
Yif : { cond : yelu_expr; then_ : yelu_stmt; else_ : yelu_stmt option }
````

not:

```ocaml
Yif : { cond : yelu_cond; ... }
```

The old `yelu_cond` type should either disappear or be reduced to a real bool/logical operation fragment.

## Important distinction

The existing alias:

```ocaml
type expr = yelu_expr
```

inside the final pack does not implement open recursion.

It only lets statement fragments consume the final expression type through `T.expr`.

For example:

```ocaml
module Make_list_op (T : LANG_TYPES) = struct
  type yelu_list_stmt =
    | Ylist_append of { cvar : T.var; values : T.expr list }
end
```

After pack instantiation, `T.expr` becomes `yelu_expr`.

So `T.expr` is useful plumbing for statement fragments, but it does not allow fragments to contribute new constructors to `yelu_expr`.

In short:

```text
T.expr lets fragments consume the final expression type.
T.expr does not let fragments extend the final expression type.
```

## Recommended model

Use parameterized expression fragments for theory-owned operations.

For example:

```ocaml
module Lang_yelu_bool_expr = struct
  type 'expr t =
    | Not of 'expr
    | And of 'expr * 'expr
    | Or of 'expr * 'expr
end
```

```ocaml
module Lang_yelu_int_expr = struct
  type 'expr t =
    | Equal of 'expr * 'expr
    | Less of 'expr * 'expr
    | Less_equal of 'expr * 'expr
    | Greater of 'expr * 'expr
    | Greater_equal of 'expr * 'expr
end
```

```ocaml
module Lang_yelu_string_expr = struct
  type 'expr t =
    | Equal of 'expr * 'expr
    | Matches of { value : 'expr; regex : string }
end
```

```ocaml
module Lang_yelu_file_expr = struct
  type 'expr t =
    | Exists of 'expr
    | Is_directory of 'expr
    | Is_regular_file of 'expr
end
```

```ocaml
module Lang_yelu_var_expr = struct
  type 'expr t =
    | Is_defined of 'expr
end
```

```ocaml
module Lang_yelu_target_expr = struct
  type 'expr t =
    | Exists of 'expr
end
```

Then the final cmake pack ties the recursive knot:

```ocaml
type yelu_expr =
  | Yexpr_name of tc_name
  | Yexpr_string of yc_string
  | Yexpr_bool of bool
  | Yexpr_var of yelu_var
  | Yexpr_bool_op of yelu_expr Lang_yelu_bool_expr.t
  | Yexpr_int_op of yelu_expr Lang_yelu_int_expr.t
  | Yexpr_string_op of yelu_expr Lang_yelu_string_expr.t
  | Yexpr_file_op of yelu_expr Lang_yelu_file_expr.t
  | Yexpr_var_op of yelu_expr Lang_yelu_var_expr.t
  | Yexpr_target_op of yelu_expr Lang_yelu_target_expr.t
```

This gives the intended structure:

```text
Theory owns operation shape.
Pack owns final recursive expression type.
Typechecker assigns result types.
Control flow consumes expressions of type Ty_bool.
```

## Why this is better than putting everything in `yelu_cond`

The old model makes `yelu_cond` a dumping ground:

```ocaml
type yelu_cond =
  | Ynot of yelu_cond
  | Yand of yelu_cond * yelu_cond
  | Ystrequal of yelu_expr * yelu_expr
  | Ymatches of yelu_expr * string
  | Yis_target of yelu_expr
  | Yis_defined of yelu_expr
  | Yexists of yelu_expr
  | Yis_directory of yelu_expr
```

This mixes unrelated ownership domains:

* `not`, `and`, `or` belong to bool/logical theory.
* string equality belongs to string theory.
* regex matching belongs to regex or string theory.
* file existence belongs to file theory.
* target existence belongs to target theory.
* variable definedness belongs to var theory.

The fact that all these operations return `Ty_bool` does not mean they belong to the boolean theory.

The better model is:

```text
Bool theory:
  bool algebra, such as not/and/or

Int theory:
  int comparisons returning Ty_bool

String theory:
  string predicates returning Ty_bool

File theory:
  file predicates returning Ty_bool

Target theory:
  target predicates returning Ty_bool

Var theory:
  variable predicates returning Ty_bool
```

## Typechecking model

The expression typechecker should infer the type of `yelu_expr`.

Example:

```ocaml
let rec infer_expr env expr =
  match expr with
  | Yexpr_name name ->
      infer_name env name

  | Yexpr_string s ->
      infer_string env s

  | Yexpr_bool _ ->
      Ty_bool

  | Yexpr_var v ->
      infer_var env v

  | Yexpr_bool_op op ->
      infer_bool_op env op

  | Yexpr_int_op op ->
      infer_int_op env op

  | Yexpr_string_op op ->
      infer_string_op env op

  | Yexpr_file_op op ->
      infer_file_op env op

  | Yexpr_var_op op ->
      infer_var_op env op

  | Yexpr_target_op op ->
      infer_target_op env op

and check_expr_has_type env expr expected =
  let actual = infer_expr env expr in
  check_type_compatible ~expected ~actual
```

Bool/logical operations:

```ocaml
and infer_bool_op env op =
  match op with
  | Lang_yelu_bool_expr.Not expr ->
      check_expr_has_type env expr Ty_bool;
      Ty_bool

  | Lang_yelu_bool_expr.And (lhs, rhs)
  | Lang_yelu_bool_expr.Or (lhs, rhs) ->
      check_expr_has_type env lhs Ty_bool;
      check_expr_has_type env rhs Ty_bool;
      Ty_bool
```

Int comparisons:

```ocaml
and infer_int_op env op =
  match op with
  | Lang_yelu_int_expr.Equal (lhs, rhs)
  | Lang_yelu_int_expr.Less (lhs, rhs)
  | Lang_yelu_int_expr.Less_equal (lhs, rhs)
  | Lang_yelu_int_expr.Greater (lhs, rhs)
  | Lang_yelu_int_expr.Greater_equal (lhs, rhs) ->
      check_expr_has_type env lhs Ty_int;
      check_expr_has_type env rhs Ty_int;
      Ty_bool
```

File predicates:

```ocaml
and infer_file_op env op =
  match op with
  | Lang_yelu_file_expr.Exists path
  | Lang_yelu_file_expr.Is_directory path
  | Lang_yelu_file_expr.Is_regular_file path ->
      check_expr_has_type env path Ty_path;
      Ty_bool
```

Var predicates:

```ocaml
and infer_var_op env op =
  match op with
  | Lang_yelu_var_expr.Is_defined expr ->
      ignore (infer_expr env expr : yelu_ty);
      Ty_bool
```

Target predicates:

```ocaml
and infer_target_op env op =
  match op with
  | Lang_yelu_target_expr.Exists expr ->
      check_expr_has_type env expr Ty_target;
      Ty_bool
```

## Statement model

The top-level statement type should change from:

```ocaml
| Yif of { cond : yelu_cond; then_ : yelu_stmt; else_ : yelu_stmt option }
```

to:

```ocaml
| Yif of { cond : yelu_expr; then_ : yelu_stmt; else_ : yelu_stmt option }
```

Then the statement typechecker does:

```ocaml
| Yif { cond; then_; else_ } ->
    check_expr_has_type env cond Ty_bool;
    check_stmt env then_;
    Option.iter else_ ~f:(check_stmt env)
```

This allows all of the following to be valid conditions if they infer to `Ty_bool`:

```text
true
not x
int_less(a, b)
string_matches(name, ".*test.*")
file_exists(path)
target_exists(t)
var_is_defined(v)
```

`if` should not care which theory produced the boolean expression.

## Relationship to statement fragments

Statement fragments can keep the current functor shape:

```ocaml
module type LANG_TYPES = sig
  type var
  type expr
  type target
end
```

For example:

```ocaml
module Make_list_op (T : LANG_TYPES) = struct
  type yelu_list_stmt =
    | Ylist_append of { cvar : T.var; values : T.expr list }
    | Ylist_join of { cvar : T.var; glue : T.expr; out : T.var }
end
```

This is still useful because statement fragments need to refer to the final pack expression type.

But expression fragments do not need the full `LANG_TYPES` functor if they only need recursive expression positions. Prefer:

```ocaml
type 'expr t = ...
```

instead of:

```ocaml
module Make_expr (T : LANG_TYPES) = struct
  type t = ...
end
```

Use a functor only if the expression fragment genuinely needs multiple external language types such as `var`, `target`, or `expr`.

Even then, consider using parameters directly:

```ocaml
type ('var, 'expr, 'target) t =
  | Some_op of { var : 'var; expr : 'expr; target : 'target }
```

instead of a module functor.

## Avoid recursive modules for now

A large recursive module is not necessary.

Recursive modules can tie this knot:

```text
Types.expr = Expr.t
Expr.t contains File_expr.t
File_expr.t mentions Types.expr
```

But they add complexity in signatures, initialization safety, and error messages.

They are acceptable for small type-only knots, but they should not include parser, checker, compiler, wellform, or statement modules.

For this design, parameterized fragments are simpler:

```ocaml
type yelu_expr =
  | Yexpr_file_op of yelu_expr Lang_yelu_file_expr.t
```

This already ties the recursive knot without recursive modules.

## Migration plan

1. Introduce theory-owned expression fragment modules.

   Example:

   ```ocaml
   module Lang_yelu_file_expr = struct
     type 'expr t =
       | Exists of 'expr
       | Is_directory of 'expr
   end
   ```

2. Add corresponding slots to `yelu_expr`.

   ```ocaml
   type yelu_expr =
     | Yexpr_name of tc_name
     | Yexpr_string of yc_string
     | Yexpr_bool of bool
     | Yexpr_var of yelu_var
     | Yexpr_bool_op of yelu_expr Lang_yelu_bool_expr.t
     | Yexpr_file_op of yelu_expr Lang_yelu_file_expr.t
     | Yexpr_string_op of yelu_expr Lang_yelu_string_expr.t
     | Yexpr_var_op of yelu_expr Lang_yelu_var_expr.t
     | Yexpr_target_op of yelu_expr Lang_yelu_target_expr.t
   ```

3. Change `Yif.cond` from `yelu_cond` to `yelu_expr`.

4. Move logical operations into `Lang_yelu_bool_expr`.

   Keep only real bool algebra there:

   ```ocaml
   type 'expr t =
     | Not of 'expr
     | And of 'expr * 'expr
     | Or of 'expr * 'expr
   ```

5. Move domain predicates out of `yelu_cond`.

   Examples:

   * `Yis_defined` -> `Lang_yelu_var_expr.Is_defined`
   * `Yis_target` -> `Lang_yelu_target_expr.Exists`
   * `Yexists` -> `Lang_yelu_file_expr.Exists`
   * `Yis_directory` -> `Lang_yelu_file_expr.Is_directory`
   * `Ymatches` -> `Lang_yelu_string_expr.Matches` or regex theory
   * `Ystrequal` -> `Lang_yelu_string_expr.Equal`

6. Update typechecker so every expression operation fragment has its own inference function.

7. Update compiler and wellform passes with the same structure.

8. Keep parser normalization simple: surface syntax should directly build final `yelu_expr`.

   Avoid letting both `fragment-local AST` and `final yelu_expr` flow through the full pipeline.

## Naming guidance

Avoid names that imply all boolean-producing operations belong to boolean theory:

```ocaml
yelu_cond
yelu_bool_expr
```

Prefer theory-owned names:

```ocaml
Lang_yelu_bool_expr
Lang_yelu_int_expr
Lang_yelu_string_expr
Lang_yelu_file_expr
Lang_yelu_regex_expr
Lang_yelu_var_expr
Lang_yelu_target_expr
```

The result type can still be `Ty_bool`.

## Final decision

Use this architecture:

```text
Statements:
  Keep current functorized fragments over LANG_TYPES.

Expressions:
  Use parameterized theory-owned operation fragments.

Final pack:
  Owns the closed recursive yelu_expr type.

Boolean:
  Bool theory owns only bool algebra.
  Other theories own their own predicates and comparisons.
  Typechecker assigns Ty_bool where appropriate.

Control flow:
  Yif accepts yelu_expr.
  Typechecker checks that cond has Ty_bool.
```

This keeps the system understandable, avoids over-engineering, preserves OCaml exhaustiveness checking, avoids recursive module complexity, and leaves room for future packs such as json/nix.

```
```
