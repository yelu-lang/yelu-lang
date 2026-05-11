(* Yelu lexer — token definitions and scannerless combinators for Angstrom.
   Whitespace-insensitive (braced blocks), comments with # to end of line. *)

open Base
open Angstrom

type token =
  | LET | IN | IF | THEN | ELSE
  | FOREACH | FUNCTION | MACRO | WHILE | BREAK | CONTINUE | RETURN
  | TARGET | CVAR | CACHE | RANGE
  | IDENT of string
  | PATH of string       (* "double-quoted" *)
  | STRING of string     (* 'single-quoted' *)
  | EVAL of string       (* ${VAR} or $<GENEX> *)
  | KEYWORD of string    (* :PUBLIC *)
  | BOOL of bool         (* ON/OFF *)
  | INT of int
  | LBRACE | RBRACE | LBRACK | RBRACK | LPAREN | RPAREN
  | COMMA | SEMI | COLON | DOTDOT | EQ | WALRUS  (* := *) | TILDE  (* ~ *)
  | EOF
[@@deriving equal, sexp_of]

(* ============================================================
   Whitespace & comments
   ============================================================ *)

let is_ws c =
  Char.equal c ' ' || Char.equal c '\t' || Char.equal c '\r' || Char.equal c '\n'

let not_newline c = not (Char.equal c '\n')

let ws = skip_while is_ws

(* Character-by-character skip for backtracking safety.
   peek_char doesn't consume, so <|> can backtrack through it. *)
let rec skip () =
  peek_char >>= function
  | None -> return ()
  | Some c when is_ws c -> advance 1 *> skip ()
  | Some '#' -> advance 1 *> skip_while not_newline *> skip ()
  | Some _ -> return ()

let token p = p <* skip ()

(* ============================================================
   Identifiers & keywords
   ============================================================ *)

let is_ident_start c =
  let open Char in c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c = '_'

let is_ident_cont c =
  is_ident_start c || (let open Char in c >= '0' && c <= '9') || Char.equal c '-'

let ident_str =
  token (take_while1 is_ident_start >>= fun first ->
    take_while is_ident_cont >>| fun rest -> first ^ rest)

(* Reserved words map to keyword tokens *)
let reserved = Map.of_alist_exn (module String) [
  "let",      LET;
  "in",       IN;
  "if",       IF;
  "then",     THEN;
  "else",     ELSE;
  "foreach",  FOREACH;
  "function", FUNCTION;  "fun",      FUNCTION;
  "macro",    MACRO;
  "while",    WHILE;
  "break",    BREAK;
  "continue", CONTINUE;
  "return",   RETURN;
  "target",   TARGET;  "Target",   TARGET;
  "cache",    CACHE;
  "cvar",     CVAR;
  "RANGE",    RANGE;
]

let ident =
  ident_str >>| fun s ->
    match Map.find reserved s with
    | Some kw -> kw
    | None -> IDENT s

(* ============================================================
   Literals
   ============================================================ *)

let bool_lit =
  token (
    (string "ON"  >>| fun _ -> BOOL true)
    <|> (string "OFF" >>| fun _ -> BOOL false))

(* Keywords: :PUBLIC, :STATIC, :private *)
let is_keyword_char c =
  let open Char in
  c >= 'A' && c <= 'Z' || c >= 'a' && c <= 'z' || c >= '0' && c <= '9' || c = '_' || c = '-'

(* Colon-or-keyword: :PUBLIC -> KEYWORD, bare : -> COLON.
   Must be one parser so that a bare : can fall through to COLON
   when no keyword chars follow.  Splitting into two parsers would
   lose the colon because char ':' consumes input and Angstrom <|>
   won't backtrack past consumed input. *)
let colon_or_keyword =
  token (
    char ':' *>
    ((take_while1 is_keyword_char >>| fun s -> KEYWORD s)
     <|> return COLON))

(* Integer literals *)
let int_lit =
  token (
    take_while1 Char.is_digit >>| fun s -> INT (Int.of_string s))

(* Path string: "double-quoted" *)
let path_lit =
  let not_quote c = not (Char.equal c '"') in
  token (
    char '"' *> take_while not_quote <* char '"'
    >>| fun s -> PATH s)

(* Plain string: 'single-quoted' *)
let string_lit =
  let not_quote c = not (Char.equal c '\'') in
  token (
    char '\'' *> take_while not_quote <* char '\''
    >>| fun s -> STRING s)

(* Eval: ${VAR} or $<GENEX>
   ${...} is simple: take everything until the first }.
   $<...> may nest: $<IF:$<CONFIG:Debug>,release>.  Nesting delimiter is
   "$<" / ">", not bare "<".  Buffer created per-parse inside >>= . *)
let eval_lit =
  let not_brace c = not (Char.equal c '}') in
  let genex =
    (char '<' *> return ()) >>= fun () ->
    let buf = Buffer.create 64 in
    let rec scan depth =
      peek_char >>= function
      | None ->
          fail "unterminated generator expression"
      | Some '>' when depth = 0 ->
          advance 1 *> return (EVAL ("$<" ^ Buffer.contents buf ^ ">"))
      | Some '>' ->
          advance 1 *> (Buffer.add_char buf '>'; scan (depth - 1))
      | Some '$' ->
          advance 1 *>
          peek_char >>= (function
            | Some '<' ->
                advance 1 *> (Buffer.add_string buf "$<"; scan (depth + 1))
            | _ ->
                Buffer.add_char buf '$'; scan depth)
      | Some c ->
          advance 1 *> (Buffer.add_char buf c; scan depth)
    in
    scan 0
  in
  token (
    char '$' *> (
      (char '{' *> take_while not_brace <* char '}'
       >>| fun s -> EVAL ("${" ^ s ^ "}"))
      <|>
      genex
    ))

(* ============================================================
   Delimiters & punctuation
   ============================================================ *)

let lbrace  = token (char '{' >>| fun _ -> LBRACE)
let rbrace  = token (char '}' >>| fun _ -> RBRACE)
let lbrack  = token (char '[' >>| fun _ -> LBRACK)
let rbrack  = token (char ']' >>| fun _ -> RBRACK)
let lparen  = token (char '(' >>| fun _ -> LPAREN)
let rparen  = token (char ')' >>| fun _ -> RPAREN)
let comma   = token (char ',' >>| fun _ -> COMMA)
let semi    = token (char ';' >>| fun _ -> SEMI)
let tilde     = token (char '~' >>| fun _ -> TILDE)
let walrus     = token (string ":=" >>| fun _ -> WALRUS)
let dotdot     = token (string ".." >>| fun _ -> DOTDOT)
let eq      = token (char '=' >>| fun _ -> EQ)

(* ============================================================
   Token stream (for testing / debugging)
   ============================================================ *)

let any_token =
  choice [
    bool_lit; walrus; tilde; colon_or_keyword; eval_lit; int_lit;
    path_lit; string_lit;
    ident;
    lbrace; rbrace; lbrack; rbrack; lparen; rparen;
    comma; semi; dotdot; eq;
  ]

let token_list =
  skip () *> many any_token
