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

(* ── Conditions (mirror p_cond_atom_y1 / p_cond_y1) ──
   Prefix operators are uniform `op atom*`; only not / and / or / paren /
   target are structural. The per-op typed mapping is a lowering concern. *)
let cond_unary_ops = [ "defined"; "exists"; "is_dir"; "is_abs" ]
let cond_binary_ops =
  [ "str_eq"; "eq"; "lt"; "gt";
    "ver_lt"; "ver_gt"; "ver_eq"; "ver_ge"; "ver_le"; "list_in" ]

let rec p_cond_atom (ls : ls) : (cond * ls) option =
  match ls with
  | (IDENT "not", _) :: rest ->
    (match p_cond_atom rest with Some (c, r) -> Some (C_not c, r) | None -> None)
  | (TARGET, _) :: rest ->
    (match p_atom rest with Some (a, r) -> Some (C_target a, r) | None -> None)
  | (IDENT "match", _) :: rest ->
    (match p_atom rest with
     | Some (e, (STRING s, _) :: r) -> Some (C_app ("match", [ e; A_string s ]), r)
     | Some (e, (PATH s, _) :: r)   -> Some (C_app ("match", [ e; A_path s ]), r)
     | _ -> None)
  | (IDENT "policy", _) :: (IDENT id, _) :: rest ->
    Some (C_app ("policy", [ A_name id ]), rest)
  | (IDENT op, _) :: rest when List.mem cond_binary_ops op ~equal:String.equal ->
    (match p_atom rest with
     | Some (a, r) ->
       (match p_atom r with
        | Some (b, r') -> Some (C_app (op, [ a; b ]), r')
        | None -> None)
     | None -> None)
  | (IDENT op, _) :: rest when List.mem cond_unary_ops op ~equal:String.equal ->
    (match p_atom rest with Some (a, r) -> Some (C_app (op, [ a ]), r) | None -> None)
  | (LPAREN, _) :: rest ->
    (match p_cond rest with
     | Some (c, (RPAREN, _) :: r) -> Some (C_paren c, r)
     | _ -> None)
  | _ ->
    (match p_atom ls with Some (a, r) -> Some (C_expr a, r) | None -> None)

(* Left-associative and / or over cond atoms. *)
and p_cond (ls : ls) : (cond * ls) option =
  match p_cond_atom ls with
  | None -> None
  | Some (c1, rest) ->
    let rec loop acc toks =
      match toks with
      | (IDENT "and", _) :: r ->
        (match p_cond_atom r with
         | Some (c, r') -> loop (C_and (acc, c)) r'
         | None -> Some (acc, toks))
      | (IDENT "or", _) :: r ->
        (match p_cond_atom r with
         | Some (c, r') -> loop (C_or (acc, c)) r'
         | None -> Some (acc, toks))
      | _ -> Some (acc, toks)
    in
    loop c1 rest

(* ── Assignment `:=` (mirror p_assign_y1) ──
   The one multi-field bespoke form: optional `cache`, comma-separated
   value list, `~type:`/`~force` kwargs, docstring after `;`, PARENT_SCOPE. *)
let p_assign (ls : ls) : (stmt_node * ls) option =
  let cache, ls0 = match ls with (CACHE, _) :: r -> (true, r) | _ -> (false, ls) in
  match ls0 with
  | ((IDENT name | STRING name | EVAL name), _) :: (WALRUS, _) :: rest ->
    let rec collect_vals ~only_one acc toks =
      match toks with
      | (TILDE, _) :: _ when not (List.is_empty acc) -> (List.rev acc, toks)
      | ((RPAREN, _) :: _ | (SEMI, _) :: _ | []) -> (List.rev acc, toks)
      | (IDENT "PARENT_SCOPE", _) :: _ when not (List.is_empty acc) ->
        (List.rev acc, toks)
      | _ ->
        (match p_atom toks with
         | Some (v, (COMMA, _) :: r) -> collect_vals ~only_one (v :: acc) r
         | Some (v, r) ->
           if only_one then (List.rev (v :: acc), r)
           else collect_vals ~only_one (v :: acc) r
         | None -> (List.rev acc, toks))
    in
    let values, rest = collect_vals ~only_one:cache [] rest in
    if cache then begin
      let docstring, rest =
        match rest with
        | (SEMI, _) :: (STRING s, _) :: r -> (Some s, r)
        | (SEMI, _) :: (PATH s, _) :: r   -> (Some s, r)
        | (STRING s, _) :: (SEMI, _) :: r -> (Some s, r)
        | (STRING s, _) :: r -> (Some s, r)
        | (PATH s, _) :: r   -> (Some s, r)
        | _ -> (None, rest)
      in
      let is_type_kw kw =
        List.mem [ "STRING"; "BOOL"; "FILEPATH"; "PATH" ] kw ~equal:String.equal
      in
      let rec kwargs acc toks =
        match toks with
        | (TILDE, _) :: (IDENT "type", _) :: ((COLON | EQ), _) :: r ->
          (match p_atom r with
           | Some (v, r') -> kwargs (("type", v) :: acc) r'
           | None -> kwargs acc r)
        (* `~type:STRING` lexes as TILDE IDENT"type" KEYWORD"STRING" — the
           `:STRING` is a colon-keyword, not a COLON token. *)
        | (TILDE, _) :: (IDENT "type", _) :: (KEYWORD v, _) :: r ->
          kwargs (("type", A_name v) :: acc) r
        | (TILDE, _) :: (KEYWORD kw, _) :: r when is_type_kw kw ->
          kwargs (("type", A_name kw) :: acc) r
        | (TILDE, _) :: (IDENT "force", _) :: r ->
          kwargs (("force", A_bool true) :: acc) r
        | (TILDE, _) :: _ :: r -> kwargs acc r
        | _ -> (List.rev acc, toks)
      in
      let kws, rest = kwargs [] rest in
      Some (S_assign { cache = true; name; values; kwargs = kws;
                       docstring; parent_scope = false }, rest)
    end
    else begin
      let parent_scope, rest =
        match rest with (IDENT "PARENT_SCOPE", _) :: r -> (true, r) | _ -> (false, rest)
      in
      Some (S_assign { cache = false; name; values; kwargs = []; docstring = None;
                       parent_scope }, rest)
    end
  | _ -> None

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

(* Dispatcher. Order mirrors yelu_parse: keyword-headed control forms,
   flow, assignment (must precede the IDENT-headed command), block, then
   the uniform command. *)
let rec p_stmt (ls : ls) : (stmt * ls) option =
  let wrap node rest = Some ({ node; span = consumed_span ls rest }, rest) in
  match p_let ls      with Some (n, r) -> wrap n r | None ->
  match p_if ls       with Some (n, r) -> wrap n r | None ->
  match p_while ls    with Some (n, r) -> wrap n r | None ->
  match p_foreach ls  with Some (n, r) -> wrap n r | None ->
  match p_function ls with Some (n, r) -> wrap n r | None ->
  match p_macro ls    with Some (n, r) -> wrap n r | None ->
  match p_flow ls     with Some (n, r) -> wrap n r | None ->
  match p_assign ls   with Some (n, r) -> wrap n r | None ->
  match p_block ls    with Some (n, r) -> wrap n r | None ->
  match p_command ls  with Some (n, r) -> wrap n r | None -> None

(* `( stmt; stmt; … )` → the bare stmt list. *)
and p_block_body (ls : ls) : (block * ls) option =
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
    collect [] inner
  | _ -> None

and p_block (ls : ls) : (stmt_node * ls) option =
  match p_block_body ls with
  | Some (stmts, rest) -> Some (S_block stmts, rest)
  | None -> None

(* `let var [: type] = atom in stmt` *)
and p_let (ls : ls) : (stmt_node * ls) option =
  match ls with
  | (LET, _) :: (IDENT var, _) :: rest ->
    let ty, rest =
      match rest with
      | (COLON, _) :: (IDENT t, _) :: r -> (Some t, r)
      | (COLON, _) :: (TARGET, _) :: r  -> (Some "target", r)
      | (COLON, _) :: (CVAR, _) :: r    -> (Some "cvar", r)
      | _ -> (None, rest)
    in
    (match rest with
     | (EQ, _) :: rest ->
       (match p_atom rest with
        | Some (value, (IN, _) :: rest) ->
          (match p_stmt rest with
           | Some (body, rest) -> Some (S_let { var; ty; value; body }, rest)
           | None -> None)
        | _ -> None)
     | _ -> None)
  | _ -> None

(* `if cond then ( body ) [else ( body ) | else if …]` *)
and p_if (ls : ls) : (stmt_node * ls) option =
  match ls with
  | (IF, _) :: rest ->
    (match p_cond rest with
     | Some (cond, (THEN, _) :: rest) ->
       (match p_block_body rest with
        | Some (then_, rest) ->
          let else_, rest =
            match rest with
            | (ELSE, _) :: r ->
              (match p_block_body r with
               | Some (eb, r') -> (Some (Else_block eb), r')
               | None ->
                 (match p_if r with
                  | Some (elif, r') ->
                    (Some (Else_if { node = elif; span = consumed_span r r' }), r')
                  | None -> (None, rest)))
            | _ -> (None, rest)
          in
          Some (S_if { cond; then_; else_ }, rest)
        | None -> None)
     | _ -> None)
  | _ -> None

(* `while cond ( body )` *)
and p_while (ls : ls) : (stmt_node * ls) option =
  match ls with
  | (WHILE, _) :: rest ->
    (match p_cond rest with
     | Some (cond, rest) ->
       (match p_block_body rest with
        | Some (body, rest) -> Some (S_while { cond; body }, rest)
        | None -> None)
     | None -> None)
  | _ -> None

(* `foreach v in <RANGE n..m | LISTS ids | [ items ]> ( body )` *)
and p_foreach (ls : ls) : (stmt_node * ls) option =
  let with_body iter rest =
    match p_block_body rest with
    | Some (body, r) -> Some (S_foreach { var = (fst iter); iter = (snd iter); body }, r)
    | None -> None
  in
  match ls with
  | (FOREACH, _) :: (IDENT var, _) :: (IN, _) :: rest ->
    (match rest with
     | (RANGE, _) :: (INT start, _) :: (DOTDOT, _) :: (INT stop, _) :: rest ->
       with_body (var, F_range { start = Some start; stop }) rest
     | (IDENT "LISTS", _) :: rest ->
       let rec idents acc = function
         | (IDENT id, _) :: r -> idents (id :: acc) r
         | toks -> (List.rev acc, toks)
       in
       let lists, rest = idents [] rest in
       with_body (var, F_lists lists) rest
     | (LBRACK, _) :: rest ->
       let rec items acc = function
         | (RBRACK, _) :: r -> (List.rev acc, r)
         | (SEMI, _) :: r -> items acc r
         | toks ->
           (match p_atom toks with
            | Some (a, r) -> items (a :: acc) r
            | None -> (List.rev acc, toks))
       in
       let its, rest = items [] rest in
       with_body (var, F_items its) rest
     | _ -> None)
  | _ -> None

(* `fun/function name(params) ( body )` *)
and p_params (ls : ls) : string list * ls =
  match ls with
  | (LPAREN, _) :: r ->
    let rec loop acc = function
      | (RPAREN, _) :: r' -> (List.rev acc, r')
      | (COMMA, _) :: r'  -> loop acc r'
      | (IDENT a, _) :: r' -> loop (a :: acc) r'
      | toks -> (List.rev acc, toks)
    in
    loop [] r
  | _ -> ([], ls)

and p_function (ls : ls) : (stmt_node * ls) option =
  match ls with
  | (FUNCTION, _) :: (IDENT name, _) :: rest ->
    let params, rest = p_params rest in
    (match p_block_body rest with
     | Some (body, r) -> Some (S_function { name; params; body }, r)
     | None -> None)
  | _ -> None

and p_macro (ls : ls) : (stmt_node * ls) option =
  match ls with
  | (MACRO, _) :: (IDENT name, _) :: rest ->
    let params, rest = p_params rest in
    (match p_block_body rest with
     | Some (body, r) -> Some (S_macro { name; params; body }, r)
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
