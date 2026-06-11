(* yc_cst_parse — text → yc_cst.program (M1.1, first slice).

   Consumes the lossless located token stream (Yelu_lexer.lex_located):
   comments are split into the program-level side list, and the structural
   parse runs over the comment-free spanned-token stream (pure recursive
   descent, so backtracking can't mis-attach comments).

   This slice covers atoms, the uniform command, flow keywords, and blocks.
   Control forms (if/let/while/foreach/fun/macro), assignment, and the
   condition sub-grammar follow next. The shapes mirror yelu_parse.ml; the
   per-command interpretation it does inline will move to yc_cst_lower. *)

open Base
open Yelu_lexer   (* token constructors + span fields *)
open Yc_cst

type ls = (token * span) list

(* Span of the tokens consumed from [ls] up to [rest]. *)
let consumed_span (ls : ls) (rest : ls) : span =
  let lo = match ls with (_, s) :: _ -> s.lo | [] -> 0 in
  let nconsumed = List.length ls - List.length rest in
  let hi =
    if nconsumed <= 0 then lo
    else
      match List.nth ls (nconsumed - 1) with
      | Some (_, s) -> s.hi
      | None -> lo
  in
  { lo; hi }

(* ── Atoms (mirror p_expr_y1, but token-faithful) ── *)
let rec p_atom (ls : ls) : (atom * ls) option =
  match ls with
  | (TARGET, _) :: (IDENT n, _)  :: rest -> Some (A_target n, rest)
  | (TARGET, _) :: (PATH n, _)   :: rest -> Some (A_target n, rest)
  | (TARGET, _) :: (STRING n, _) :: rest -> Some (A_target n, rest)
  | (TARGET, _) :: (EVAL n, _)   :: rest -> Some (A_target n, rest)
  | (STRING s, _)  :: rest -> Some (A_string s, rest)
  | (PATH s, _)    :: rest -> Some (A_path s, rest)
  | (EVAL s, _)    :: rest -> Some (A_eval s, rest)
  | (KEYWORD s, _) :: rest -> Some (A_keyword s, rest)
  | (BOOL b, _)    :: rest -> Some (A_bool b, rest)
  | (INT n, _)     :: rest -> Some (A_int n, rest)
  | (IDENT n, _)   :: rest -> Some (A_name n, rest)
  | (LPAREN, _)    :: rest ->
    (match p_atom rest with
     | Some (a, (RPAREN, _) :: rest') -> Some (A_paren a, rest')
     | _ -> None)
  | _ -> None

(* ── Command arguments (mirror collect_command_args) ── *)
let rec p_args (acc : arg list) (ls : ls) : arg list * ls =
  match ls with
  | (TILDE, _) :: (IDENT kw, _) :: (COLON, _) :: (LBRACK, _) :: rest ->
    let rec items acc = function
      | (RBRACK, _) :: r -> (List.rev acc, r)
      | (COMMA, _) :: r  -> items acc r
      | toks ->
        (match p_atom toks with
         | Some (a, r) -> items (a :: acc) r
         | None -> (List.rev acc, toks))
    in
    let its, rest = items [] rest in
    p_args (Kw_list (kw, its) :: acc) rest
  | (TILDE, _) :: (IDENT kw, _) :: (COLON, _) :: rest ->
    (match p_atom rest with
     | Some (a, r) -> p_args (Kw (kw, a) :: acc) r
     | None -> (List.rev acc, ls))
  | (TILDE, _) :: (IDENT kw, _) :: (KEYWORD v, _) :: rest ->
    p_args (Kw (kw, A_name v) :: acc) rest
  | (TILDE, _) :: (IDENT kw, _) :: rest ->
    p_args (Kw_flag kw :: acc) rest
  | (RPAREN, _) :: _ | (SEMI, _) :: _ | [] -> (List.rev acc, ls)
  | _ ->
    (match p_atom ls with
     | Some (a, r) -> p_args (Pos a :: acc) r
     | None -> (List.rev acc, ls))

(* ── Statement nodes ── *)
let p_flow (ls : ls) : (stmt_node * ls) option =
  match ls with
  | (BREAK, _) :: rest    -> Some (S_flow Break, rest)
  | (CONTINUE, _) :: rest -> Some (S_flow Continue, rest)
  | (RETURN, _) :: rest   -> Some (S_flow Return, rest)
  | _ -> None

(* Any IDENT-headed call. Control keywords are distinct tokens (LET, IF, …),
   so they never reach here; set/option/message/string_* are plain IDENTs
   and are handled uniformly (their family logic moves to lowering). *)
let p_command (ls : ls) : (stmt_node * ls) option =
  match ls with
  | (IDENT name, _) :: rest ->
    let args, rest = p_args [] rest in
    Some (S_command { name; args }, rest)
  | _ -> None

let rec p_stmt (ls : ls) : (stmt * ls) option =
  let wrap node rest = Some ({ node; span = consumed_span ls rest }, rest) in
  match p_flow ls with
  | Some (node, rest) -> wrap node rest
  | None ->
    match p_block ls with
    | Some (node, rest) -> wrap node rest
    | None ->
      match p_command ls with
      | Some (node, rest) -> wrap node rest
      | None -> None

and p_block (ls : ls) : (stmt_node * ls) option =
  match ls with
  | (LPAREN, _) :: inner ->
    let rec collect acc toks =
      match toks with
      | (RPAREN, _) :: r -> Some (List.rev acc, r)
      | [] -> None
      | _ ->
        (match p_stmt toks with
         | None -> None
         | Some (s, rest) ->
           let rest = match rest with (SEMI, _) :: r -> r | _ -> rest in
           collect (s :: acc) rest)
    in
    (match collect [] inner with
     | Some (stmts, rest) -> Some (S_block stmts, rest)
     | None -> None)
  | _ -> None

(* ── Program ── *)
let split_comments (located : ls) : ls * comment list =
  let toks =
    List.filter located ~f:(fun (t, _) ->
      match t with COMMENT _ -> false | _ -> true)
  in
  let comments =
    List.filter_map located ~f:(fun (t, s) ->
      match t with COMMENT text -> Some { text; span = s } | _ -> None)
  in
  (toks, comments)

let p_stmts (toks : ls) : (stmt list, string) Result.t =
  let rec go acc toks =
    let toks = match toks with (SEMI, _) :: r -> r | _ -> toks in
    match toks with
    | [] -> Ok (List.rev acc)
    | (t, _) :: _ ->
      (match p_stmt toks with
       | Some (s, rest) -> go (s :: acc) rest
       | None ->
         Error
           (Printf.sprintf "parse error at %s"
              (Sexp.to_string ([%sexp_of: token] t))))
  in
  go [] toks

let parse (input : string) : (program, string) Result.t =
  match Yelu_lexer.lex_located input with
  | Error e -> Error ("lex error: " ^ e)
  | Ok located ->
    let toks, comments = split_comments located in
    (match p_stmts toks with
     | Ok stmts -> Ok { stmts; comments }
     | Error e -> Error e)
