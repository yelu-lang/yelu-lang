(* Phase 2a — parser-direct-to-Yelu1, var family.

   Pilot for the eventual replacement of [Lang_yelu_parse.parse_program]
   (which builds the production [Lang_yelu_cmake] AST) with a parser
   that builds [Yelu_tiny.expr] (Yelu1 IR) directly.

   This module is parallel to [Lang_yelu_parse] — it shares the lexer
   (`Lang_yelu_lexer.token_list`) but constructs Yelu1 nodes during
   parsing instead of going through the legacy yelu_cmake AST. Per the
   retirement plan, family-by-family the new parser absorbs each
   statement family from the legacy parser; when all families are
   covered, the legacy parser retires.

   Pilot scope: variable assignment statements.

     - `IDENT := value`              → ESetVar
     - `IDENT := v1, v2, v3`         → ESetVar (… EList …)
     - `cache IDENT := v ; 'msg'`    → ECmakeSetCache
     - `( set IDENT value... )`      → ESetVar
     - `( option IDENT value )`      → ECmakeOption
     - `( unset_cache IDENT )`       → ECmakeUnsetVarCache

   The exposed entry point [parse_program_y1] returns a single
   [Yelu_tiny.expr] for a single var-family statement; non-var inputs
   produce [Error _]. The pair-wise oracle in
   [test_yelu_cmake_parse.ml] compares this against the legacy path
   ([Lang_yelu_parse.parse_program] → [Yelu_cmake_to_yelu1.stmt] →
   [Yelu_tiny_cmake_emit_ast.emit_script]) at the cmake-text level.

   Helpers are duplicated from [Lang_yelu_parse] rather than imported,
   to keep the migration unit self-contained and to make the eventual
   retirement of the legacy parser straightforward. *)

open Base
open Lang_yelu_lexer
open Yelu_tiny
open Yelu_theory_list
open Yelu_surface_cmake_store
open Yelu_surface_cmake_string

(* ============================================================
   Combinator primitives — duplicated from Lang_yelu_parse.
   ============================================================ *)

let kw s toks =
  match toks with
  | KEYWORD k :: rest when String.equal k s -> Some ((), rest)
  | IDENT k :: rest when String.equal k s -> Some ((), rest)
  | _ -> None

let delim t toks =
  match toks with
  | t' :: rest when Poly.equal t t' -> Some ((), rest)
  | _ -> None

let lparen = delim LPAREN
let rparen = delim RPAREN

(* ============================================================
   Expression parsing — minimal subset for var-family values.

   yelu_cmake's expression grammar is richer than what var values
   actually use; for the pilot we cover the literal forms plus a
   bare-identifier deref. Add more cases as needed by later families.
   ============================================================ *)

let p_expr_y1 toks =
  match toks with
  | STRING s :: rest -> Some (EString s, rest)
  | PATH s :: rest -> Some (EString s, rest)
  | EVAL s :: rest ->
    (* Match the bridge's Ycs_eval-to-Yelu1 rule: $<...> → ECmakeGenex,
       everything else (including ${...}) → EString. *)
    if String.is_substring s ~substring:"$<" then
      Some (ECmakeGenex s, rest)
    else
      Some (EString s, rest)
  | KEYWORD s :: rest -> Some (EString s, rest)
  | BOOL b :: rest -> Some (EBool b, rest)
  | INT n :: rest -> Some (EString (Int.to_string n), rest)
  | IDENT name :: rest -> Some (EVar name, rest)
  | _ -> None

(* ============================================================
   Var-family statement parsers. Each produces a Yelu_tiny.expr
   (specifically one of: ESetVar, ECmakeSetCache, ECmakeOption,
   ECmakeUnsetVarCache, ECmakeSetEnvVar, ECmakeUnsetEnvVar) without
   going through Lang_yelu_cmake AST.
   ============================================================ *)

(* Match the legacy var_statement bridge: a single value becomes the
   value expr directly; multiple values become an EList; empty becomes
   EString "". *)
let pack_set_value = function
  | [] -> EString ""
  | [ v ] -> v
  | vs -> EList vs

(* `IDENT := v1, v2, v3` or `cache IDENT := v ; 'msg'` *)
let p_assign_y1 toks =
  let is_cache, toks =
    match toks with
    | CACHE :: rest -> (true, rest)
    | IDENT _ :: WALRUS :: _ -> (false, toks)
    | _ -> (false, toks)
  in
  match toks with
  | IDENT name :: WALRUS :: rest ->
    let rec collect_vals acc toks =
      match p_expr_y1 toks with
      | Some (v, COMMA :: rest) -> collect_vals (v :: acc) rest
      | Some (v, rest) -> Some (List.rev (v :: acc), rest)
      | None -> if List.is_empty acc then None else Some (List.rev acc, toks)
    in
    (match collect_vals [] rest with
     | None -> None
     | Some (values, rest) ->
       if is_cache then
         (* `cache VAR := v ; 'msg'` — extract docstring; default ""
            and cache_type "STRING" matches legacy parse defaults. *)
         let msg, rest =
           match rest with
           | SEMI :: STRING s :: rest' -> (s, rest')
           | SEMI :: PATH s :: rest' -> (s, rest')
           | STRING s :: SEMI :: rest' -> (s, rest')
           | _ -> ("", rest)
         in
         Some
           (ECmakeSetCache
              { name; values; cache_type = "STRING"; docstring = msg;
                force = false },
            rest)
       else
         Some (ESetVar (name, pack_set_value values), rest))
  | _ -> None

(* `( set NAME value... )` plain set form. *)
let p_set_command_y1 toks =
  match lparen toks with
  | None -> None
  | Some ((), toks) ->
    match kw "set" toks with
    | None -> None
    | Some ((), toks) ->
      match toks with
      | (STRING name | PATH name | IDENT name) :: rest ->
        let rec collect_vals acc toks =
          match p_expr_y1 toks with
          | Some (v, rest) -> collect_vals (v :: acc) rest
          | None -> List.rev acc, toks
        in
        let values, rest = collect_vals [] rest in
        (match rparen rest with
         | Some ((), rest) ->
           Some (ESetVar (name, pack_set_value values), rest)
         | None -> None)
      | _ -> None

(* `( option NAME value )` *)
let p_option_command_y1 toks =
  match lparen toks with
  | None -> None
  | Some ((), toks) ->
    match kw "option" toks with
    | None -> None
    | Some ((), toks) ->
      match toks with
      | (STRING name | IDENT name) :: rest ->
        (match p_expr_y1 rest with
         | None -> None
         | Some (value, rest) ->
           (match rparen rest with
            | Some ((), rest) ->
              Some
                (ECmakeOption { name; message = ""; value }, rest)
            | None -> None))
      | _ -> None

(* `( unset_cache NAME )` *)
let p_unset_cache_command_y1 toks =
  match lparen toks with
  | None -> None
  | Some ((), toks) ->
    match kw "unset_cache" toks with
    | None -> None
    | Some ((), toks) ->
      match toks with
      | (STRING name | IDENT name) :: rest ->
        (match rparen rest with
         | Some ((), rest) -> Some (ECmakeUnsetVarCache name, rest)
         | None -> None)
      | _ -> None

let p_var_stmt_y1 toks =
  match p_assign_y1 toks with Some r -> Some r | None ->
  match p_set_command_y1 toks with Some r -> Some r | None ->
  match p_option_command_y1 toks with Some r -> Some r | None ->
  p_unset_cache_command_y1 toks

(* ============================================================
   Command + kwargs collector — duplicated from
   [Lang_yelu_parse.p_command]'s argument-loop. Collects positional
   args (as Yelu1 expr) and `~name:value` kwargs (as a name → expr
   alist) until it hits a parser-stopping token.
   ============================================================ *)

let rec collect_command_args args kwargs toks =
  match toks with
  | TILDE :: IDENT kw :: COLON :: rest ->
    (match p_expr_y1 rest with
     | Some (v, r) -> collect_command_args args ((kw, v) :: kwargs) r
     | None -> (List.rev args, List.rev kwargs, toks))
  | TILDE :: IDENT kw :: KEYWORD v :: rest ->
    collect_command_args args ((kw, EVar v) :: kwargs) rest
  | TILDE :: IDENT kw :: rest ->
    collect_command_args args ((kw, EBool true) :: kwargs) rest
  | (RPAREN :: _) | (SEMI :: _) | [] ->
    (List.rev args, List.rev kwargs, toks)
  | _ ->
    (match p_expr_y1 toks with
     | Some (e, r) -> collect_command_args (e :: args) kwargs r
     | None -> (List.rev args, List.rev kwargs, toks))

(* Match legacy [Lang_yelu_parse.out_var] sentinel: "?" when ~out
   missing. Some parser tests omit ~out and rely on this fallback;
   the pair-wise oracle requires byte-identical text. *)
let out_var_y1 kwargs =
  match List.Assoc.find kwargs ~equal:String.equal "out" with
  | Some (EVar name) -> name
  | Some (EString name) -> name
  | _ -> "?"

(* ============================================================
   String-family statement parsers. The legacy parser dispatches a
   single [p_command] on the command name into [Ys_string (Ystr_*
   { ... })]; the bridge then maps each Ystr_* to ECmakeString*.
   Here we collapse both steps: dispatch in the new parser straight
   to ECmakeString*.

   For commands that take an integer arg (substring, repeat), the
   parser extracts the int from an EString value (since p_expr_y1
   currently converts INT to EString — matching the legacy behavior).
   ============================================================ *)

let expr_to_int_y1 e =
  match e with
  | EString s -> (try Int.of_string s with _ -> 0)
  | EInt n -> n
  | _ -> 0

let p_string_command_y1_inner name args kwargs =
  let out = out_var_y1 kwargs in
  match name, args with
  | "string_toupper", [ s ] ->
    Some (ECmakeStringToupper { input = s; out })
  | "string_tolower", [ s ] ->
    Some (ECmakeStringTolower { input = s; out })
  | "string_length", [ s ] ->
    Some (ECmakeStringLength { input = s; out })
  | "string_strip", [ s ] ->
    Some (ECmakeStringStrip { input = s; out })
  | "string_concat", inputs ->
    Some (ECmakeStringConcat { inputs; out })
  | "string_replace", [ m; r; input ] ->
    Some (ECmakeStringReplace { match_ = m; replace = r; input; out })
  | "string_regex_match", [ EString re; input ]
  | "string_regex_match", [ EVar re; input ] ->
    Some (ECmakeStringRegexMatch { regex = re; out; inputs = [ input ] })
  | "string_regex_matchall", [ EString re; input ]
  | "string_regex_matchall", [ EVar re; input ] ->
    Some (ECmakeStringRegexMatchAll { regex = re; out; inputs = [ input ] })
  | "string_regex_replace", [ EString re; repl; input ]
  | "string_regex_replace", [ EVar re; repl; input ] ->
    Some (ECmakeStringRegexReplace
            { regex = re; replace = repl; out; inputs = [ input ] })
  | "string_regex_quote", inputs ->
    Some (ECmakeStringRegexQuote { out; inputs })
  | "string_join", glue :: inputs ->
    Some (ECmakeStringJoin { glue; out; inputs })
  | "string_find", [ sub; s ] ->
    Some (ECmakeStringFind
            { string = s; substring = sub; out; reverse = false })
  | "string_timestamp", [] ->
    Some (ECmakeStringTimestamp { out; format = None; utc = false })
  | "string_hex", [ s ] ->
    Some (ECmakeStringHex { input = s; out })
  | "string_make_c_identifier", [ s ] ->
    Some (ECmakeStringMakeCIdentifier { input = s; out })
  | "string_genex_strip", [ s ] ->
    Some (ECmakeStringGenexStrip { input = s; out })
  | "string_substring", [ s; b; l ] ->
    let begin_ = expr_to_int_y1 b in
    let length = match l with
      | EString "-1" | EInt -1 -> None
      | _ -> Some (expr_to_int_y1 l)
    in
    Some (ECmakeStringSubstring { string = s; begin_; length; out })
  | "string_repeat", [ s; c ] ->
    Some (ECmakeStringRepeat { string = s; count = expr_to_int_y1 c; out })
  | "string_append", EVar cvar :: inputs
  | "string_append", EString cvar :: inputs ->
    Some (ECmakeStringAppend { cvar; inputs })
  | "string_prepend", EVar cvar :: inputs
  | "string_prepend", EString cvar :: inputs ->
    Some (ECmakeStringPrepend { cvar; inputs })
  | "string_compare", [ EString op; s1; s2 ]
  | "string_compare", [ EVar op; s1; s2 ] ->
    Some (ECmakeStringCompare { op; string1 = s1; string2 = s2; out })
  | "string_uuid", [] ->
    Some (ECmakeStringUuid
            { out; namespace = ""; name = ""; type_ = "MD5"; upper = false })
  | "string_json", op :: rest ->
    let op_name = match op with EString s | EVar s -> s | _ -> "JSON_op" in
    Some (ECmakeStringJson
            { out; error_var = None; op_name; args = rest })
  | _ -> None

let p_string_command_y1 toks =
  match lparen toks with
  | None -> None
  | Some ((), toks) ->
    match toks with
    | IDENT name :: rest when String.is_prefix name ~prefix:"string_" ->
      let args, kwargs, rest = collect_command_args [] [] rest in
      (match p_string_command_y1_inner name args kwargs with
       | None -> None
       | Some e ->
         (match rparen rest with
          | Some ((), rest) -> Some (e, rest)
          | None -> None))
    | _ -> None

(* Outer block: `( <stmt> ... )`. Mirrors [Lang_yelu_parse.p_block]
   semicolon-separated semantics and the single-stmt collapse. As
   Phase 2a families are migrated, the block accepts any family-
   recognized statement; non-recognized inputs make the parser fail
   (the legacy parser handles them via its full grammar). *)
let rec p_stmt_inner_y1 toks =
  match p_string_command_y1 toks with Some r -> Some r | None ->
  match p_var_stmt_y1 toks with Some r -> Some r | None ->
  p_block_y1 toks

and p_block_y1 toks =
  match lparen toks with
  | None -> None
  | Some ((), toks) ->
    let rec collect toks =
      match p_stmt_inner_y1 toks with
      | None -> Some ([], toks)
      | Some (s, rest) ->
        let rest = match rest with SEMI :: r -> r | _ -> rest in
        (match collect rest with
         | Some (ss, r) -> Some (s :: ss, r)
         | None -> None)
    in
    (match collect toks with
     | Some (stmts, RPAREN :: rest) ->
       let result = match stmts with
         | [ s ] -> s
         | _ -> ESeq stmts
       in
       Some (result, rest)
     | _ -> None)

let p_stmt_y1 = p_stmt_inner_y1

(* ============================================================
   Entry points
   ============================================================ *)

let parse_tokens_y1 toks =
  match p_stmt_y1 toks with
  | Some (e, []) -> Ok e
  | Some (_, rest) ->
    let ctx = match rest with
      | [] -> ""
      | t :: _ -> " at " ^ Sexp.to_string ([%sexp_of: token] t)
    in
    Error ("unexpected trailing tokens" ^ ctx)
  | None ->
    Error "parse error (var family only; non-var statements not yet supported)"

let parse_program_y1 input =
  match Angstrom.parse_string ~consume:All token_list input with
  | Ok toks -> parse_tokens_y1 toks
  | Error e -> Error ("lex error: " ^ e)
