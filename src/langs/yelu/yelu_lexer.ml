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
  | COMMENT of string    (* # line comment; body excludes '#' and newline.
                            Trivia: only emitted by the lossless located
                            scanner, never by [token_list]. *)
  | EOF
[@@deriving equal, sexp_of]

(* Source span: byte offsets into the original input, half-open [lo, hi). *)
type span = { lo : int; hi : int } [@@deriving equal, sexp_of]

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

(* [token] no longer skips trailing trivia — the trailing [skip] moved into
   [token_list] (below). This leaves every core parser trivia-free, so the
   lossless located scanner can capture tight spans and the comments
   between tokens. [token] is kept as the identity wrapper so the per-token
   definitions read unchanged. *)
let token p = p

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

(* Enum-constructor vocabulary (uppercased cmake spelling). Grows per theory as
   the casing migration proceeds; both the lexer (a bare constructor → KEYWORD,
   uppercased, unifying with the legacy `:KEYWORD`) and yc_cst_print
   (canonicalize the KEYWORD back to leading-cap) gate on THIS set so the
   round-trip stays consistent. Slice 1 = visibility. A bare capitalized word
   NOT in the set stays an IDENT (var/target name) until its theory migrates
   (and Y14, eventually, rejects var names that shadow the set).
   See doc/lang/casing_design.md. *)
let constr_names =
  Set.of_list (module String)
    [ (* slice 1: visibility *) "PUBLIC"; "PRIVATE"; "INTERFACE";
      (* slice 2: library/cache type, fc mode, language *)
      "STATIC"; "STRING"; "NAME_WE"; "CXX" ]

let is_known_constr s = Set.mem constr_names (String.uppercase s)

let ident =
  ident_str >>| fun s ->
    match Map.find reserved s with
    | Some kw -> kw
    (* Only a *capitalized* word promotes to the constructor KEYWORD — a
       lowercase `public` is an ordinary identifier (e.g. the `~public:` kwarg
       key), not the enum. *)
    | None ->
      if String.length s >= 1 && Char.is_uppercase s.[0] && is_known_constr s
      then KEYWORD (String.uppercase s)
      else IDENT s

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
    ((take_while1 is_keyword_char >>| fun s ->
        (* A `:Constructor` value (e.g. `~type:Static`) normalizes to the
           uppercase cmake form, same as the bare `Static` — so emit is
           unchanged and the formatter is free to display it leading-cap. *)
        KEYWORD (if is_known_constr s then String.uppercase s else s))
     <|> return COLON))

(* Integer literals *)
let int_lit =
  token (
    take_while1 Char.is_digit >>| fun s -> INT (Int.of_string s))

(* Path string: double-quoted.  Supports backslash-escape for embedded
   double-quote characters; other backslash sequences stay literal. *)
let path_lit =
  let buf = Buffer.create 256 in
  token (
    char '"' *> return () >>= fun () ->
    Buffer.clear buf;
    let rec loop () =
      peek_char >>= function
      | None -> fail "unterminated path string"
      | Some '"' -> advance 1 *> return (PATH (Buffer.contents buf))
      | Some '\\' ->
        advance 1 *>
        peek_char >>= (function
          | Some '"' -> advance 1 *> (Buffer.add_char buf '"'; loop ())
          | Some '\\' -> advance 1 *> (Buffer.add_char buf '\\'; loop ())
          | Some c -> advance 1 *> (Buffer.add_char buf '\\'; Buffer.add_char buf c; loop ())
          | None -> fail "unterminated escape in path string")
      | Some c -> advance 1 *> (Buffer.add_char buf c; loop ())
    in
    loop ())

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
      <|>
      (* Brace-elision sugar: `$foo` is `${foo}` for a plain identifier
         (yc_cst_print canonicalizes back to this lighter form). Same
         charset as [ident] so the round-trip is stable; normalizes to the
         `${…}` token so the IR / emit are byte-identical. *)
      (take_while1 is_ident_start >>= fun first ->
       take_while is_ident_cont >>| fun rest -> EVAL ("${" ^ first ^ rest ^ "}"))
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
  skip () *> many (any_token <* skip ())

(* ============================================================
   Lossless located scanner (for the CST / formatter / LSP)

   Unlike [token_list], this preserves comments — as [COMMENT]
   trivia tokens — and tags every token with its source [span].
   It is the front-end the comment-preserving CST will consume;
   the existing [token_list] / parser path is unchanged.
   ============================================================ *)

(* Leading-trivia scanner: drop whitespace, emit each `#…` line comment
   as a located [COMMENT] token. cmake/yelu has no block comments, so a
   single line-comment form is all the trivia model needs. *)
let trivia_tokens : (token * span) list Angstrom.t =
  let rec go acc =
    pos >>= fun p ->
    peek_char >>= function
    | Some c when is_ws c -> advance 1 *> go acc
    | Some '#' ->
      advance 1 *> take_while not_newline >>= fun body ->
      pos >>= fun p2 ->
      go ((COMMENT body, { lo = p; hi = p2 }) :: acc)
    | _ -> return (List.rev acc)
  in
  go []

(* Tag a core token parser with its tight [span] (no trailing trivia,
   since [token] no longer skips). *)
let spanned (p : token Angstrom.t) : (token * span) Angstrom.t =
  pos >>= fun lo -> p >>= fun t -> pos >>| fun hi -> (t, { lo; hi })

(* Full lossless stream: leading trivia, then (token, following-trivia)*.
   Every token consumes ≥1 char, so [many] cannot spin. *)
let located_tokens : (token * span) list Angstrom.t =
  trivia_tokens >>= fun lead ->
  many
    (spanned any_token >>= fun tk ->
     trivia_tokens >>| fun tr -> tk :: tr)
  >>| fun rest -> lead @ List.concat rest

let lex_located (input : string) : ((token * span) list, string) Result.t =
  Angstrom.parse_string ~consume:All located_tokens input
