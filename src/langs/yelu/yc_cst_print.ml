(* yc_cst_print — print yc_cst back to canonical .yc text (M1.3, the
   formatter / print_ye).

   Naive fixed pretty-print: one statement per line, blocks indented two
   spaces, no line-width wrapping (an explicit Doc IR / width knob is a
   later refinement — see surface_lsp_framework.md § Formatter). Generic
   over the uniform command + the bespoke forms; correctness is measured
   at the emit level by the round-trip oracle
   (emit(lower(parse(print cst))) == emit(lower cst)), not exact text.

   Comment placement (the program-level span side-list) lands in M1.3b. *)

open Base
module Cst = Yc_cst

(* escape backslash and double-quote for a "..."-path literal *)
let esc_double s =
  String.concat_map s ~f:(function
    | '\\' -> "\\\\"
    | '"' -> "\\\""
    | c -> String.of_char c)

(* Canonical string literal. yc's `'…'` and `"…"` both lower to the same
   EString (cmake has no char type — they are *not* char-vs-string), so the
   quote is pure surface and safe to normalise. Prefer single quotes (raw, no
   escaping); fall back to double quotes (with `\"` / `\\` escaping) only when
   the content contains a `'`. This is the Python / Prettier rule — it
   minimises escaping (single-quoted strings hold `"` raw). *)
let pr_string b s =
  if String.exists s ~f:(Char.equal '\'')
  then (Buffer.add_char b '"'; Buffer.add_string b (esc_double s); Buffer.add_char b '"')
  else (Buffer.add_char b '\''; Buffer.add_string b s; Buffer.add_char b '\'')

(* A name is safe to print bare iff it is an eval (`${…}` / `$<…>`) or a
   plain identifier; anything else (e.g. `fmt::fmt-c`, which would re-lex
   as two colons) must be double-quoted to round-trip. *)
let is_bare_name n =
  (not (String.is_empty n))
  && (String.is_prefix n ~prefix:"$"
      || String.for_all n ~f:(fun c ->
           Char.is_alphanum c || Char.equal c '_' || Char.equal c '-'))

(* Brace-elision: `${foo}` with a plain-identifier name prints as the lighter
   `$foo`. Charset must match the lexer's `$foo` sugar rule (is_ident_start /
   is_ident_cont) so the round-trip is stable; nested / genex / odd-char names
   keep the braces. *)
let elide_eval_braces s =
  let n = String.length s in
  if n >= 4 && Char.equal s.[0] '$' && Char.equal s.[1] '{'
     && Char.equal s.[n - 1] '}'
  then
    let inner = String.sub s ~pos:2 ~len:(n - 3) in
    let is_start c = Char.is_alpha c || Char.equal c '_' in
    let is_cont c = Char.is_alphanum c || Char.equal c '_' || Char.equal c '-' in
    if (not (String.is_empty inner)) && is_start inner.[0]
       && String.for_all inner ~f:is_cont
    then Some inner else None
  else None

(* Print a name string, eliding `${ident}` → `$ident` where safe; otherwise
   defer to [otherwise] (literal / quoted form). Used for the name/target
   slots (assignment LHS, target-first, A_target) so the lighter form is
   uniform with value-position evals. *)
let pr_name_or b s ~otherwise =
  match elide_eval_braces s with
  | Some nm -> Buffer.add_char b '$'; Buffer.add_string b nm
  | None -> otherwise ()

let rec pr_atom b (a : Cst.atom) =
  match a with
  | A_name n ->
    (* An enum value carried as a bare name (e.g. the `~type:STRING` value,
       which the parser stores as A_name) canonicalizes to leading-cap, same
       as a standalone constructor. Surface-only: the internal value is the
       uppercase cmake form, so emit is unchanged. *)
    if Yelu_lexer.is_known_constr n
    then Buffer.add_string b (String.capitalize (String.lowercase n))
    else Buffer.add_string b n
  | A_string s -> pr_string b s
  | A_path s -> pr_string b s
  | A_eval s ->
    (match elide_eval_braces s with
     | Some name -> Buffer.add_char b '$'; Buffer.add_string b name
     | None -> Buffer.add_string b s)
  | A_bool true -> Buffer.add_string b "ON"
  | A_bool false -> Buffer.add_string b "OFF"
  | A_int n -> Buffer.add_string b (Int.to_string n)
  (* Enum constructor: canonicalize a *recognized* `:KEYWORD` to the leading-cap
     spelling (`:PRIVATE` → `Private`). Gate on the same set the lexer uses so
     the round-trip is consistent; an unmigrated keyword keeps the colon form.
     See casing_design.md. *)
  | A_keyword s ->
    if Yelu_lexer.is_known_constr s
    then Buffer.add_string b (String.capitalize (String.lowercase s))
    else (Buffer.add_char b ':'; Buffer.add_string b s)
  | A_target n ->
    Buffer.add_string b "target ";
    pr_name_or b n ~otherwise:(fun () ->
      if is_bare_name n then Buffer.add_string b n
      else (Buffer.add_char b '"'; Buffer.add_string b (esc_double n); Buffer.add_char b '"'))
  | A_paren a -> Buffer.add_string b "( "; pr_atom b a; Buffer.add_string b " )"

let pr_arg b (arg : Cst.arg) =
  match arg with
  | Pos a -> pr_atom b a
  | Kw (k, v) ->
    Buffer.add_char b '~'; Buffer.add_string b k; Buffer.add_char b ':'; pr_atom b v
  | Kw_flag k -> Buffer.add_char b '~'; Buffer.add_string b k
  | Kw_list (k, items) ->
    Buffer.add_char b '~'; Buffer.add_string b k; Buffer.add_string b ":[ ";
    List.iter items ~f:(fun a -> pr_atom b a; Buffer.add_char b ' ');
    Buffer.add_char b ']'

(* The first positional arg of a target command: print the target NAME
   without the `target` tag (syntax #1; lowering re-tags it). *)
let rec target_name_of (a : Cst.atom) : string =
  match a with
  | A_target n | A_name n | A_string n | A_path n | A_eval n | A_keyword n -> n
  | A_int n -> Int.to_string n
  | A_bool true -> "ON"
  | A_bool false -> "OFF"
  | A_paren a -> target_name_of a

let pr_target_first b (arg : Cst.arg) =
  match arg with
  | Pos a ->
    let n = target_name_of a in
    pr_name_or b n ~otherwise:(fun () ->
      if is_bare_name n then Buffer.add_string b n
      else (Buffer.add_char b '"'; Buffer.add_string b (esc_double n); Buffer.add_char b '"'))
  | _ -> pr_arg b arg (* first arg should be positional; defensive *)

let rec pr_cond b (c : Cst.cond) =
  match c with
  | C_app (op, args) ->
    Buffer.add_string b op;
    List.iter args ~f:(fun a -> Buffer.add_char b ' '; pr_atom b a)
  | C_not c -> Buffer.add_string b "not "; pr_cond b c
  | C_and (a, b') -> pr_cond b a; Buffer.add_string b " and "; pr_cond b b'
  | C_or (a, b') -> pr_cond b a; Buffer.add_string b " or "; pr_cond b b'
  | C_paren c -> Buffer.add_string b "( "; pr_cond b c; Buffer.add_string b " )"
  | C_target a -> Buffer.add_string b "target "; pr_atom b a
  | C_expr a -> pr_atom b a

(* space-separated list with a leading separator before each item *)
let pr_spaced b ~f items = List.iter items ~f:(fun x -> Buffer.add_char b ' '; f b x)

(* Comment placement: the program-level comments (sorted by source offset)
   are flushed at each statement boundary as the traversal advances — a
   comment lands just before the statement that follows it in source
   order, at that statement's indent (so nesting is respected, since inner
   statements are visited in source order via DFS). Single CLI use, so a
   module ref is fine; reset per print_program. *)
let pending : Yc_cst.comment list ref = ref []
let clo (c : Yc_cst.comment) = c.Yc_cst.span.Yelu_lexer.lo
let slo (s : Yc_cst.stmt) = s.Yc_cst.span.Yelu_lexer.lo

let flush_before b indent (lo : int) =
  let rec go () =
    match !pending with
    | c :: rest when clo c < lo ->
      pending := rest;
      Buffer.add_string b indent;
      Buffer.add_char b '#'; Buffer.add_string b c.Yc_cst.text; Buffer.add_char b '\n';
      go ()
    | _ -> ()
  in
  go ()

let rec pr_stmt b indent (s : Cst.stmt) =
  match s.node with
  | S_command { name; args } ->
    Buffer.add_string b name;
    if Cst.is_target_first_arg_command name then
      (match args with
       | first :: rest ->
         Buffer.add_char b ' '; pr_target_first b first; pr_spaced b ~f:pr_arg rest
       | [] -> ())
    else pr_spaced b ~f:pr_arg args
  | S_flow Break -> Buffer.add_string b "break"
  | S_flow Continue -> Buffer.add_string b "continue"
  | S_flow Return -> Buffer.add_string b "return"
  | S_block stmts -> pr_block b indent stmts
  | S_assign { cache; name; values; kwargs; docstring; parent_scope } ->
    if cache then Buffer.add_string b "cache ";
    pr_name_or b name ~otherwise:(fun () -> Buffer.add_string b name);
    Buffer.add_string b " :=";
    List.iteri values ~f:(fun i a ->
      Buffer.add_string b (if i = 0 then " " else ", "); pr_atom b a);
    Option.iter docstring ~f:(fun d ->
      Buffer.add_string b " "; pr_atom b (A_string d));
    List.iter kwargs ~f:(fun (k, v) ->
      Buffer.add_string b " ~"; Buffer.add_string b k; Buffer.add_char b ':'; pr_atom b v);
    if parent_scope then Buffer.add_string b " PARENT_SCOPE"
  | S_let { var; ty; value; body } ->
    Buffer.add_string b "let "; Buffer.add_string b var;
    Option.iter ty ~f:(fun t -> Buffer.add_string b " : "; Buffer.add_string b t);
    Buffer.add_string b " = "; pr_atom b value; Buffer.add_string b " in ";
    pr_stmt b indent body
  | S_while { cond; body } ->
    Buffer.add_string b "while "; pr_cond b cond; Buffer.add_char b ' ';
    pr_block b indent body
  | S_function { name; params; body } ->
    Buffer.add_string b "fun "; Buffer.add_string b name;
    Buffer.add_char b '('; Buffer.add_string b (String.concat ~sep:", " params);
    Buffer.add_string b ") "; pr_block b indent body
  | S_macro { name; params; body } ->
    Buffer.add_string b "macro "; Buffer.add_string b name;
    Buffer.add_char b '('; Buffer.add_string b (String.concat ~sep:", " params);
    Buffer.add_string b ") "; pr_block b indent body
  | S_if { cond; then_; else_ } ->
    Buffer.add_string b "if "; pr_cond b cond; Buffer.add_string b " then ";
    pr_block b indent then_;
    (match else_ with
     | None -> ()
     | Some (Else_block eb) -> Buffer.add_string b " else "; pr_block b indent eb
     | Some (Else_if s) -> Buffer.add_string b " else "; pr_stmt b indent s)
  | S_foreach { var; iter; body } ->
    Buffer.add_string b "foreach "; Buffer.add_string b var; Buffer.add_string b " in ";
    (match iter with
     | F_range { start; stop } ->
       Buffer.add_string b "RANGE ";
       Option.iter start ~f:(fun s -> Buffer.add_string b (Int.to_string s); Buffer.add_string b " .. ");
       Buffer.add_string b (Int.to_string stop)
     | F_lists lists -> Buffer.add_string b "LISTS "; Buffer.add_string b (String.concat ~sep:" " lists)
     | F_items items ->
       Buffer.add_char b '[';
       List.iter items ~f:(fun a -> Buffer.add_char b ' '; pr_atom b a);
       Buffer.add_string b " ]");
    Buffer.add_char b ' '; pr_block b indent body

(* `(\n  stmt;\n  stmt\n<indent>)` *)
and pr_block b indent (stmts : Cst.block) =
  match stmts with
  | [] -> Buffer.add_string b "(  )"
  | _ ->
    let inner = indent ^ "  " in
    Buffer.add_string b "(\n";
    List.iteri stmts ~f:(fun i s ->
      if i > 0 then Buffer.add_string b ";\n";
      flush_before b inner (slo s);
      Buffer.add_string b inner;
      pr_stmt b inner s);
    Buffer.add_char b '\n'; Buffer.add_string b indent; Buffer.add_char b ')'

let print_program (p : Cst.program) : string =
  let b = Buffer.create 512 in
  pending :=
    List.sort p.comments ~compare:(fun a b -> Int.compare (clo a) (clo b));
  List.iteri p.stmts ~f:(fun i s ->
    if i > 0 then Buffer.add_string b ";\n";
    flush_before b "" (slo s);
    pr_stmt b "" s);
  (* trailing comments after the last statement *)
  (match !pending with
   | [] -> ()
   | _ -> Buffer.add_char b '\n'; flush_before b "" Int.max_value);
  (* End with exactly one trailing newline (gofmt / prettier / black /
     POSIX text-file convention); collapses zero-or-many to one and stays
     idempotent. *)
  String.rstrip ~drop:(Char.equal '\n') (Buffer.contents b) ^ "\n"
