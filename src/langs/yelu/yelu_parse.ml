(* [tool-interface]
   node:     .yc text → yc
   op:       parse
   strategy: code
   exports:  parse_program_y1 : string → (Yelu_cmake.expr, error) result
   imports:  Yelu_lang_lexer (token stream), Yelu_cmake (IR types),
             per-theory fragment ctors
   ─────────

   Concrete-syntax parser for yelu_cmake. Produces
   [Yelu_cmake.expr] directly from token streams. The only
   production parser since E1 retired the legacy
   [Lang_yelu_parse] path.

   Current scope: broad CMake-family coverage including variable
   assignment plus control, cond, string, list, path, file,
   target, dir, test, property, find, install, cmake_op,
   function/macro/while/foreach/apply shapes.

     - `IDENT := value`              → ESetVar
     - `IDENT := v1, v2, v3`         → ESetVar (… EList …)
     - `cache IDENT := v ; 'msg'`    → ECmakeSetCache
     - `( set IDENT value... )`      → ESetVar
     - `( option IDENT value )`      → ECmakeOption
     - `( unset_cache IDENT )`       → ECmakeUnsetVarCache

   The exposed entry point [parse_program_y1] returns a single
   [Yelu_cmake.expr] for the covered syntax. Unsupported inputs
   produce [Error _]. Test coverage lives in
   [test_yelu_cmake_parse.ml] (smoke + structural assertions on
   the IR shape, plus 125 inline-golden cases frozen during E1).

   === Legacy-compatible defaults (vestigial) ===

   Several helpers in this file hard-code placeholder values that
   originally kept the pair-wise oracle byte-identical against
   the legacy parser. The oracle is gone; these defaults remain
   only because they froze into the inline goldens during E1.
   Tightening them to required-keyword or explicit-syntax forms
   should be paired with regenerating the relevant goldens.

   - [out_var_y1]              → "?" sentinel when ~out missing.
   - [cvar_name_of_y1]         → "?" sentinel for non-name positions.
   - [expr_to_int_y1]          → 0 on parse failure (math, list index).
   - [string_uuid]             → namespace="ns", name="n" placeholders
                                 when keyword args missing.
   - [string_compare] (2-arg)  → op="EQUAL" default.
   - [cmake_minimum_required]  → "3.20" version fallback.
   - [project]                 → "Project" name fallback.
   - [policy_set]              → "" id fallback.
   - find_*/install_*          → empty list defaults for unsupplied
                                 keyword args (paths, hints, etc.). *)

open Base
open Yelu_lexer
open Yelu_cmake
open Yelu_cmake_normal_bool
open Yelu_cmake_normal_int
open Yelu_cmake_store
open Yelu_cmake_string
open Yelu_cmake_list
open Yelu_cmake_path
open Yelu_cmake_file
open Yelu_cmake_normal_target
open Yelu_cmake_target
open Yelu_cmake_cmake_op
open Yelu_cmake_utils

(* ============================================================
   Combinator primitives. The structure of this parser was
   originally cloned from the legacy [Lang_yelu_parse]; module
   references below point at the historical sibling that lives
   in `src/langs/yelu_legacy/` but no longer participates in
   the build.
   ============================================================ *)

(* kw mirrors [Lang_yelu_parse.kw]: reserved-word strings map to
   dedicated tokens (LET / IF / FOREACH / FUNCTION / MACRO / etc.);
   other strings match IDENT. *)
let kw s toks =
  let expect = match s with
    | "let" -> LET | "in" -> IN | "if" -> IF | "then" -> THEN | "else" -> ELSE
    | "foreach" -> FOREACH | "function" -> FUNCTION | "fun" -> FUNCTION
    | "macro" -> MACRO
    | "while" -> WHILE | "break" -> BREAK | "continue" -> CONTINUE
    | "return" -> RETURN
    | "target" -> TARGET | "cvar" -> CVAR | "cache" -> CACHE
    | "RANGE" -> RANGE
    | _ -> EOF
  in
  match toks with
  | IDENT s' :: rest when String.equal s s' -> Some ((), rest)
  | t :: rest when Poly.equal t expect -> Some ((), rest)
  | _ -> None

let delim t toks =
  match toks with
  | t' :: rest when Poly.equal t t' -> Some ((), rest)
  | _ -> None

let lparen = delim LPAREN
let rparen = delim RPAREN
let lbrack = delim LBRACK
let rbrack = delim RBRACK
let eq_tok = delim EQ
let dotdot = delim DOTDOT

let rec str_of ?(default = "?") = function
  | ETarget s | EVar s | EString s -> s
  (* A first-class `${...}` reconstructs to its cmake text in a *name/keyword*
     slot (cache type, target name, property, …) — the same text the old
     EString "${X}" carried, so interpreters that read these slots are
     unaffected. *)
  | EVarLookup e -> "${" ^ str_of ~default e ^ "}"
  | _ -> default

(* ============================================================
   Expression parsing — currently the common literal/name subset used
   by the covered statement families.

   yelu_cmake's expression grammar is richer than what var values
   originally needed; Phase 2a has widened this helper for the direct
   parser, while preserving legacy-compatible token choices where the
   byte oracle depends on them.
   ============================================================ *)

let rec p_expr_y1 toks =
  match toks with
  | TARGET :: IDENT name :: rest -> Some (ETarget name, rest)
  | TARGET :: PATH s :: rest -> Some (ETarget s, rest)
  | TARGET :: STRING s :: rest -> Some (ETarget s, rest)
  | TARGET :: EVAL s :: rest -> Some (ETarget s, rest)
  | STRING s :: rest -> Some (EString s, rest)
  | PATH s :: rest -> Some (EString s, rest)
  | EVAL s :: rest ->
    (* $<...> → ECmakeGenex; a pure `${...}` → first-class EVarLookup
       (shared decision via [parse_var_lookup], so the CST lowering routes
       identically); mixed/literal → EString. *)
    if String.is_substring s ~substring:"$<" then
      Some (ECmakeGenex s, rest)
    else
      (match parse_var_lookup s with
       | Some e -> Some (e, rest)
       | None -> Some (EString s, rest))
  | KEYWORD s :: rest -> Some (EString s, rest)
  | BOOL b :: rest -> Some (EBool b, rest)
  | INT n :: rest -> Some (EString (Int.to_string n), rest)
  | IDENT name :: rest -> Some (EVar name, rest)
  | LPAREN :: rest ->
    (* Parenthesized expression: ( expr ). *)
    (match p_expr_y1 rest with
     | Some (e, RPAREN :: rest') -> Some (e, rest')
     | _ -> None)
  (* recursive value list `[ v, v, … ]` (mirror CST p_atom) *)
  | LBRACK :: rest ->
    let rec items acc = function
      | RBRACK :: r -> Some (EList (List.rev acc), r)
      | COMMA :: r  -> items acc r
      | toks ->
        (match p_expr_y1 toks with
         | Some (e, r) -> items (e :: acc) r
         | None -> None)
    in
    items [] rest
  (* record `{ key=v, … }` — keys bare idents, `=` (or `:`) binds *)
  | LBRACE :: rest ->
    let rec fields acc = function
      | RBRACE :: r -> Some (ERecord (List.rev acc), r)
      | COMMA :: r  -> fields acc r
      | IDENT k :: (COLON | EQ) :: r ->
        (match p_expr_y1 r with
         | Some (v, r') -> fields ((k, v) :: acc) r'
         | None -> None)
      | _ -> None
    in
    fields [] rest
  | _ -> None

(* ============================================================
   Var-family statement parsers. Each produces a Yelu_cmake.expr
   (specifically one of: ESetVar, ECmakeSetCache, ECmakeOption,
   ECmakeUnsetVarCache, ECmakeSetEnvVar, ECmakeUnsetEnvVar) without
   going through Lang_yelu_cmake AST.
   ============================================================ *)

(* Var-family dispatchers below build their IR through
   [Yelu_cmake_utils.yc_set] etc. The empty/single/list value-list
   normalization that [yc_set] does internally used to live in a
   local [pack_set_value]; removed in F refactor. *)

(* `IDENT := v1, v2, v3` or `cache IDENT := v ; 'msg'` *)
(* Forward references — populated at the bottom of the file once
   [collect_command_args] and the family `_inner` parsers are defined.
   Used by p_assign_y1's command-call sugar (`var := cmd args ~kw=v`),
   which lives before its dependencies due to call-chain order
   (p_var_stmt_y1 → p_assign_y1 happens at line 311). *)
let collect_command_args_fwd :
  (expr list -> (string * expr) list -> token list ->
   expr list * (string * expr) list * token list) ref =
  ref (fun _ _ _ -> ([], [], []))

let dispatch_command_fwd :
  (string -> expr list -> (string * expr) list -> expr option) ref =
  ref (fun _ _ _ -> None)

let fallback_to_raw_fwd :
  (string -> expr list -> token list -> expr option ->
   (expr * token list) option) ref =
  ref (fun _ _ _ _ -> None)

let p_assign_y1 toks =
  let is_cache, toks =
    match toks with
    | CACHE :: rest -> (true, rest)
    | (IDENT _ | STRING _ | EVAL _) :: WALRUS :: _ -> (false, toks)
    | _ -> (false, toks)
  in
  match toks with
  (* Low-priority `:=` — if the RHS starts with a known command name followed
     by command-shape tokens (TILDE kwarg or further positionals), parse the
     rest as a full command call, inject `~out=var`, and dispatch to the
     matching family `_inner`. This makes `var := get_property Target foo
     ~property=NAME` desugar to `get_property Target foo ~property=NAME
     ~out=var`. Single bare value (e.g. `var := foo` or empty) falls through
     to the legacy value-list path. *)
  | (IDENT s | STRING s | EVAL s) :: WALRUS :: IDENT cmd :: after_cmd
    when (not is_cache)
      && Yc_primitives.is_known_command cmd
      && (match after_cmd with
          | TILDE :: _ -> true
          | [] | SEMI :: _ | RPAREN :: _ -> false
          | _ -> true) ->
    let args, kwargs, rest =
      !collect_command_args_fwd [] [] after_cmd
    in
    let kwargs = kwargs @ [ ("out", EVar s) ] in
    !fallback_to_raw_fwd cmd args rest (!dispatch_command_fwd cmd args kwargs)
  | (IDENT s | STRING s | EVAL s) :: WALRUS :: rest ->
    let rec collect_vals ?(only_one = false) acc toks =
      match toks with
      | TILDE :: _ | (RPAREN :: _) | (SEMI :: _) | []
        when List.is_empty acc -> None
      | TILDE :: _ when not (List.is_empty acc) ->
        Some (List.rev acc, toks)
      | (RPAREN :: _) | (SEMI :: _) | [] ->
        Some (List.rev acc, toks)
      | IDENT "PARENT_SCOPE" :: _ when not (List.is_empty acc) ->
        Some (List.rev acc, toks)
      | _ ->
        (match p_expr_y1 toks with
         | Some (v, COMMA :: rest) ->
           collect_vals ~only_one (v :: acc) rest
         | Some (v, rest) ->
           if only_one then Some (List.rev (v :: acc), rest)
           else collect_vals ~only_one (v :: acc) rest
         | None ->
           if List.is_empty acc then None else Some (List.rev acc, toks))
    in
    (match collect_vals ~only_one:is_cache [] rest with
     | None -> None
     | Some (values, rest) ->
       if is_cache then
         (* `cache VAR := v ; 'msg'` — extract docstring; default ""
            and cache_type "STRING" matches legacy parse defaults.
            Kwargs ~type:TYPE and ~force after the docstring. *)
         let msg, rest =
           match rest with
           | SEMI :: STRING s :: rest' -> (s, rest')
           | SEMI :: PATH s :: rest' -> (s, rest')
           | STRING s :: SEMI :: rest' -> (s, rest')
           | STRING s :: rest' -> (s, rest')
           | PATH s :: rest' -> (s, rest')
           | _ -> ("", rest)
         in
         let rec collect_cache_kwargs cache_type force = function
           (* ~type:VALUE or ~type=VALUE *)
           | TILDE :: IDENT "type" :: (COLON | EQ) :: rest ->
             (match p_expr_y1 rest with
              | Some (v, r) ->
                let t = str_of ~default:"STRING" v in
                collect_cache_kwargs t force r
              | None -> collect_cache_kwargs cache_type force rest)
           | TILDE :: IDENT "type" :: _ :: rest ->
             collect_cache_kwargs cache_type force rest
           | TILDE :: IDENT "type" :: [] ->
             (cache_type, force, [])
           (* :TYPE keyword form: ~type:STRING was lexed as TILDE; KEYWORD "STRING" *)
           | TILDE :: KEYWORD kw :: rest
             when String.equal kw "STRING" || String.equal kw "BOOL"
               || String.equal kw "FILEPATH" || String.equal kw "PATH" ->
             collect_cache_kwargs kw force rest
           | TILDE :: IDENT "force" :: rest ->
             collect_cache_kwargs cache_type true rest
           | TILDE :: _ :: rest ->
             collect_cache_kwargs cache_type force rest
           | toks -> (cache_type, force, toks)
         in
         let cache_type_s, force, rest = collect_cache_kwargs "STRING" false rest in
         Some (Yelu_cmake_store.ECmakeSetCache
                 { name = s; values; cache_type = cache_type_s;
                   docstring = msg; force }, rest)
       else
         let parent_scope, rest =
           match rest with
           | IDENT "PARENT_SCOPE" :: r -> true, r
           | TILDE :: IDENT "parent_scope" :: r -> true, r
           | _ -> false, rest
         in
         Some (yc_set ~parent_scope s values, rest))
  | _ -> None

(* `set NAME value...` plain set form (outer `(`/`)` handled by block). *)
let p_set_command_y1 toks =
  match kw "set" toks with
  | None -> None
  | Some ((), toks) ->
    match toks with
    | (STRING name | PATH name | IDENT name) :: rest ->
      let rec collect_vals acc toks =
        match toks with
        | (RPAREN :: _) | (SEMI :: _) | [] -> List.rev acc, toks
        | IDENT "PARENT_SCOPE" :: rest' ->
          (* Trailing PARENT_SCOPE keyword — terminate value collection.
             Mirrors cmake's `set(X v PARENT_SCOPE)` shape. *)
          List.rev acc, IDENT "PARENT_SCOPE" :: rest'
        | _ ->
          (match p_expr_y1 toks with
           | Some (v, rest) -> collect_vals (v :: acc) rest
           | None -> List.rev acc, toks)
      in
      let values, rest = collect_vals [] rest in
      let parent_scope, rest =
        match rest with
        | IDENT "PARENT_SCOPE" :: r -> true, r
        | TILDE :: IDENT "parent_scope" :: r -> true, r
        | _ -> false, rest
      in
      Some (yc_set ~parent_scope name values, rest)
    | _ -> None

(* `option NAME value` *)
let p_option_command_y1 toks =
  match kw "option" toks with
  | None -> None
  | Some ((), toks) ->
    match toks with
    | (STRING name | IDENT name) :: rest ->
      (match p_expr_y1 rest with
       | None -> None
       | Some (help, rest) ->
         (match p_expr_y1 rest with
          | Some (value, rest) ->
            let msg = str_of ~default:"" help in
            Some (yc_option ~value ~msg name, rest)
          | None ->
            (* No default value — help was actually the default *)
            let value = help in
            Some (yc_option ~value ~msg:"" name, rest)))
    | _ -> None

(* `unset_cache NAME` *)
let p_unset_cache_command_y1 toks =
  match kw "unset_cache" toks with
  | None -> None
  | Some ((), toks) ->
    match toks with
    | (STRING name | IDENT name) :: rest ->
      Some (yc_unset_cache name, rest)
    | _ -> None

let p_var_stmt_y1 toks =
  match p_assign_y1 toks with Some r -> Some r | None ->
  match p_set_command_y1 toks with Some r -> Some r | None ->
  match p_option_command_y1 toks with Some r -> Some r | None ->
  p_unset_cache_command_y1 toks

(* ============================================================
   Command + kwargs collector — duplicated from
   [Lang_yelu_parse.p_command]'s argument-loop. Collects positional
   args (as yelu_cmake expr) and `~name:value` kwargs (as a name → expr
   alist) until it hits a parser-stopping token.
   ============================================================ *)

let rec collect_command_args args kwargs toks =
  match toks with
  (* `~key=[items]` — list-valued kwarg. Items flatten to N kwarg entries
     with the same key (per-command handlers recover the list via
     filter_map / find_all). Used by visibility kind-scoped groups
     (`~public=[...]`) and by value-list labels (`~property=[NAME, vals...]`
     in set_property). General mechanism; future shape-2/3 commands plug in
     without parser changes — just per-command kwarg-list extraction. *)
  | TILDE :: IDENT kw :: (COLON | EQ) :: LBRACK :: rest ->
    let rec collect_items acc = function
      | RBRACK :: r -> (List.rev acc, r)
      | COMMA :: r -> collect_items acc r
      | toks' ->
        (match p_expr_y1 toks' with
         | Some (e, r) -> collect_items (e :: acc) r
         | None -> (List.rev acc, toks'))
    in
    let items, rest = collect_items [] rest in
    (* Prepend reversed so that the final List.rev kwargs at the end of
       collection restores source order. Per-command handlers that care
       about order (e.g. property_kwarg in set_property) get [name; vals...]
       matching the [NAME, vals...] surface order. *)
    let kwargs' = List.rev_map items ~f:(fun e -> (kw, e)) in
    collect_command_args args (kwargs' @ kwargs) rest
  | TILDE :: IDENT kw0 :: rest0 ->
    (* dotted label `~library.destination=v` flattens a per-artifact record
       (shape 4); plain keys are the single-IDENT case. *)
    let rec read_key acc = function
      | DOT :: IDENT k2 :: r -> read_key (acc ^ "." ^ k2) r
      | r -> (acc, r)
    in
    let key, after = read_key kw0 rest0 in
    (match after with
     | (COLON | EQ) :: rest ->
       (match p_expr_y1 rest with
        | Some (v, r) -> collect_command_args args ((key, v) :: kwargs) r
        | None -> (List.rev args, List.rev kwargs, toks))
     | KEYWORD v :: rest ->
       collect_command_args args ((key, EVar v) :: kwargs) rest
     | rest ->
       collect_command_args args ((key, EBool true) :: kwargs) rest)
  | (RPAREN :: _) | (SEMI :: _) | [] ->
    (List.rev args, List.rev kwargs, toks)
  | _ ->
    (match p_expr_y1 toks with
     | Some (e, r) -> collect_command_args (e :: args) kwargs r
     | None -> (List.rev args, List.rev kwargs, toks))

(* ── Section splitter ───────────────────────────

   Many cmake commands use positional keywords to separate argument
   groups (add_custom_command, execute_process, set_property, ...).
   [collect_command_args] flattens everything; [split_sections] groups
   by keyword markers.

   [split_by_keywords ~keywords args] splits [args] at each keyword,
   returning a list of (keyword, items) groups.  The first element
   (before any keyword) has key "_head".  Keywords themselves are
   consumed as markers, not included in the group items. *)

let split_by_keywords ~(keywords : string list) (args : expr list)
    : (string * expr list) list =
  let is_kw = Set.mem (Set.of_list (module String) keywords) in
  let rec loop acc current_kw current_group = function
    | [] ->
      List.rev ((current_kw, List.rev current_group) :: acc)
    | e :: rest ->
      let kw = match e with
        | EVar s | EString s when is_kw s -> Some s
        | _ -> None
      in
      match kw with
      | Some kw ->
        loop ((current_kw, List.rev current_group) :: acc) kw [] rest
      | None ->
        loop acc current_kw (e :: current_group) rest
  in
  loop [] "_head" [] args

(* Shared raw-fallback: when a typed inner parser returns None, wrap the
   original args as ECmakeRawCmd so the command round-trips through the IR. *)
let fallback_to_raw name args rest = function
  | None -> Some (ECmakeRawCmd { name = cmake_name_of_yelu name; args; from_positional = None }, rest)
  | Some e -> Some (e, rest)

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
  (* Legacy-compat: 2-arg form defaults op = EQUAL (Sco_equal in
     legacy). Kept for byte-parity with the legacy parser; future
     direct-language design should drop the implicit default. *)
  | "string_compare", [ s1; s2 ] ->
    Some (ECmakeStringCompare
            { op = "EQUAL"; string1 = s1; string2 = s2; out })
  | "string_uuid", [] ->
    (* Legacy-compat defaults: the legacy parser hard-codes
       namespace = "ns" and name = "n" as placeholder values when the
       command is invoked without keyword args. Mimic the placeholders
       so the byte oracle matches; future language design replaces
       this with required keyword args. *)
    Some (ECmakeStringUuid
            { out; namespace = "ns"; name = "n"; type_ = "MD5"; upper = false })
  | "string_json", op :: rest ->
    let op_name = str_of ~default:"JSON_op" op in
    Some (ECmakeStringJson
            { out; error_var = None; op_name; args = rest })
  | _ -> None

let p_string_command_y1 toks =
  match toks with
  | IDENT name :: rest when String.is_prefix name ~prefix:"string_" ->
      let args, kwargs, rest = collect_command_args [] [] rest in
      p_string_command_y1_inner name args kwargs
      |> fallback_to_raw name args rest
    | _ -> None

(* ============================================================
   List family — mirrors [Lang_yelu_parse]'s list_* dispatch in
   p_command. cvar name extracted from the first positional arg.
   ============================================================ *)

let cvar_name_of_y1 e =
  match e with
  | EVar n -> n
  | EString n -> n
  | _ -> "?"

let p_list_command_y1_inner name args kwargs =
  let out = out_var_y1 kwargs in
  match name, args with
  | "list_append", cvar :: values ->
    Some (yc_list_append (cvar_name_of_y1 cvar) values)
  | "list_length", [ cvar ] ->
    Some (yc_list_length (cvar_name_of_y1 cvar) out)
  | "list_get", cvar :: indices when not (List.is_empty indices) ->
    Some (yc_list_get
            ~indices:(List.map indices ~f:expr_to_int_y1)
            (cvar_name_of_y1 cvar) out)
  | "list_remove_item", cvar :: values ->
    Some (yc_list_remove_item (cvar_name_of_y1 cvar) values)
  | "list_remove_duplicates", [ cvar ] ->
    Some (yc_list_remove_duplicates (cvar_name_of_y1 cvar))
  | "list_reverse", [ cvar ] ->
    Some (yc_list_reverse (cvar_name_of_y1 cvar))
  | "list_sort", [ cvar ] ->
    Some (ECmakeListSort
            { list = cvar_name_of_y1 cvar;
              order = None; compare = None; case = None })
  | "list_join", [ cvar; glue ] ->
    Some (yc_list_join (cvar_name_of_y1 cvar) glue out)
  | "list_find", [ cvar; value ] ->
    Some (yc_list_find (cvar_name_of_y1 cvar) value out)
  | "list_prepend", cvar :: values ->
    Some (yc_list_prepend (cvar_name_of_y1 cvar) values)
  | "list_insert", cvar :: _ ->
    (* Legacy parser defaults index/values; preserve to match. *)
    Some (yc_list_insert (cvar_name_of_y1 cvar) 0 [])
  | "list_remove_at", cvar :: _ ->
    (* Legacy parser drops the indices; preserve to match. *)
    Some (yc_list_remove_at (cvar_name_of_y1 cvar) [])
  | "list_pop_back", [ cvar ] ->
    Some (yc_list_pop_back (cvar_name_of_y1 cvar))
  | "list_pop_front", [ cvar ] ->
    Some (yc_list_pop_front (cvar_name_of_y1 cvar))
  | "list_sublist", [ cvar; b; l ] ->
    Some (yc_list_sublist (cvar_name_of_y1 cvar)
            (expr_to_int_y1 b) (expr_to_int_y1 l) out)
  | "list_filter", [ cvar; regex ] ->
    let regex_s = str_of ~default:"" regex in
    Some (ECmakeListFilter
            { list = cvar_name_of_y1 cvar;
              mode = "INCLUDE";
              regex = regex_s })
  | "list_transform", [ cvar ] ->
    (* Legacy parser keys action off a few kwargs and defaults to TOUPPER. *)
    let action =
      if List.Assoc.mem kwargs ~equal:String.equal "prepend" then "PREPEND"
      else "TOUPPER"
    in
    Some (ECmakeListTransform
            { list = cvar_name_of_y1 cvar;
              action; selector = None; output = None })
  | _ -> None

let p_list_command_y1 toks =
  match toks with
  | IDENT name :: rest when String.is_prefix name ~prefix:"list_" ->
      let args, kwargs, rest = collect_command_args [] [] rest in
      p_list_command_y1_inner name args kwargs
      |> fallback_to_raw name args rest
    | _ -> None

(* ============================================================
   Path family — mirrors [Lang_yelu_parse]'s path_* dispatch.
   The legacy parser hardcodes [field = Cpf_filename] for path_get
   and [field = Cph_filename] for path_has (the bridge stringifies
   them to "FILENAME" / "HAS_FILENAME"); we match those defaults
   so the pair-wise oracle stays byte-identical.
   ============================================================ *)

let p_path_command_y1_inner name args kwargs =
  let out = out_var_y1 kwargs in
  let opt_out_y1 () =
    match List.Assoc.find kwargs ~equal:String.equal "out" with
    | Some (EVar n) -> Some n
    | Some (EString n) -> Some n
    | _ -> None
  in
  match name, args with
  | "path_set", [ pv; input ] ->
    Some (ECmakePathSet
            { path = cvar_name_of_y1 pv; input; normalize = false })
  | "path_get", [ pv ] ->
    Some (ECmakePathGet
            { path = cvar_name_of_y1 pv; field = "FILENAME"; out })
  | "path_has", [ pv ] ->
    Some (ECmakePathHas
            { path = cvar_name_of_y1 pv; field = "HAS_FILENAME"; out })
  | "path_is_absolute", [ pv ] ->
    Some (ECmakePathIsAbsolute { path = cvar_name_of_y1 pv; out })
  | "path_is_relative", [ pv ] ->
    Some (ECmakePathIsRelative { path = cvar_name_of_y1 pv; out })
  | "path_is_prefix", [ pv; input ] ->
    Some (ECmakePathIsPrefix
            { path = cvar_name_of_y1 pv; input; normalize = false; out })
  | "path_compare", [ input1; input2 ] ->
    Some (ECmakePathCompare
            { input1; op = "EQUAL"; input2; out })
  | "path_append", [ pv; input ] ->
    Some (ECmakePathAppend
            { path = cvar_name_of_y1 pv; inputs = [ input ]; out = None })
  | "path_append_string", [ pv; input ] ->
    Some (ECmakePathAppendString
            { path = cvar_name_of_y1 pv; inputs = [ input ]; out = None })
  | "path_remove_filename", [ pv ] ->
    Some (ECmakePathRemoveFilename { path = cvar_name_of_y1 pv; out = None })
  | "path_replace_filename", [ pv; input ] ->
    Some (ECmakePathReplaceFilename
            { path = cvar_name_of_y1 pv; input; out = None })
  | "path_remove_extension", [ pv ] ->
    Some (ECmakePathRemoveExtension
            { path = cvar_name_of_y1 pv; last_only = false; out = None })
  | "path_replace_extension", [ pv; input ] ->
    Some (ECmakePathReplaceExtension
            { path = cvar_name_of_y1 pv; last_only = false; input;
              out = None })
  | "path_normal_path", [ pv ] ->
    Some (ECmakePathNormalPath
            { path = cvar_name_of_y1 pv; out = opt_out_y1 () })
  | "path_relative_path", [ pv ] ->
    Some (ECmakePathRelativePath
            { path = cvar_name_of_y1 pv; base_dir = None; out = None })
  | "path_absolute_path", [ pv ] ->
    Some (ECmakePathAbsolutePath
            { path = cvar_name_of_y1 pv; base_dir = None;
              normalize = false; out = None })
  | "path_native_path", [ pv ] ->
    Some (ECmakePathNativePath
            { path = cvar_name_of_y1 pv; normalize = false; out })
  | "path_convert_to_cmake", [ input ] ->
    Some (ECmakePathConvertToCmake { input; normalize = false; out })
  | "path_convert_to_native", [ input ] ->
    Some (ECmakePathConvertToNative { input; normalize = false; out })
  | "path_hash", [ pv ] ->
    Some (ECmakePathHash { path = cvar_name_of_y1 pv; out })
  | "get_filename_component", [ filename ] ->
    Some (ECmakeGetFilenameComponent
            { var = out; filename; mode = "PATH" })
  | _ -> None

let p_path_command_y1 toks =
  match toks with
  | IDENT name :: rest
      when String.is_prefix name ~prefix:"path_"
        || String.equal name "get_filename_component" ->
      let args, kwargs, rest = collect_command_args [] [] rest in
      p_path_command_y1_inner name args kwargs
      |> fallback_to_raw name args rest
    | _ -> None

(* ============================================================
   File family — file_*, configure_file. cvar args become out strings;
   file/path args stay as expressions.
   ============================================================ *)

let p_file_command_y1_inner name args kwargs =
  let out = out_var_y1 kwargs in
  match name, args with
  | "configure_file", [ input; output ] ->
    Some (yc_configure_file ~input output)
  | "configure_file", [ input; output; EString "@ONLY" ]
  | "configure_file", [ input; output; EVar "@ONLY" ] ->
    Some (yc_configure_file ~only:true ~input output)
  | "file_read", [ file ] -> Some (yc_file_read out file)
  | "file_write", file :: content -> Some (yc_file_write file content)
  | "file_glob", patterns -> Some (yc_file_glob out patterns)
  | "file_copy", [ input; output ] -> Some (yc_file_copy_file input output)
  | "file_rename", [ old_; new_ ] -> Some (yc_file_rename old_ new_)
  | "file_remove", files -> Some (yc_file_remove files)
  | "file_real_path", [ path ] -> Some (yc_file_real_path out path)
  | "file_size", [ file ] -> Some (yc_file_size out file)
  | "file_timestamp", [ file ] -> Some (yc_file_timestamp out file)
  | "file_make_directory", [ dir ] -> Some (yc_file_make_directory [ dir ])
  | "file_touch", files -> Some (yc_file_touch files)
  | "file_strings", [ file ] -> Some (yc_file_strings out file)
  | "file_read_symlink", [ link ] -> Some (yc_file_read_symlink out link)
  | _ -> None

let p_file_command_y1 toks =
  match toks with
  | IDENT name :: rest
      when String.is_prefix name ~prefix:"file_"
        || String.equal name "configure_file" ->
      let args, kwargs, rest = collect_command_args [] [] rest in
      p_file_command_y1_inner name args kwargs
      |> fallback_to_raw name args rest
    | _ -> None

(* ============================================================
   Target family — add_exe / add_lib / link_lib / include_dirs /
   compile_defs / compile_opts / compile_feats / link_opts /
   link_dirs / target_sources / aliases / imported / dependencies.

   Items are grouped by visibility keyword (PUBLIC / PRIVATE /
   INTERFACE) appearing in positional args; default group is "PLAIN".
   Multi-group commands emit ESeq of multiple ECmakeTarget* calls
   (one per visibility group) — matching the bridge's
   [target_sources_items |> List.map |> ESeq] shape.
   ============================================================ *)

(* Group a flat positional-arg list into [(visibility, items)] runs.
   Default visibility is PRIVATE. Uses [Yelu_cmake_utils.visibility_of_expr]
   for the string→enum mapping. *)
let group_by_visibility_y1 items : (visibility * expr list) list =
  let rec loop current_kind current_items groups = function
    | [] ->
      List.rev ((current_kind, List.rev current_items) :: groups)
    | item :: rest ->
      match visibility_of_expr item with
      | Some kind ->
        let groups =
          if List.is_empty current_items
          then groups
          else (current_kind, List.rev current_items) :: groups
        in
        loop kind [] groups rest
      | None ->
        loop current_kind (item :: current_items) groups rest
  in
  loop Vis_private [] [] items

(* Wrap multi-group target commands in ESeq when there's more than
   one visibility group; single-group case returns the single ctor.
   Empty-group input still produces a single PLAIN group with empty
   items (matches the bridge's invariant). *)
let target_groups_to_y1 (ctor : visibility:visibility -> expr list -> expr) items =
  let groups = group_by_visibility_y1 items in
  match List.map groups ~f:(fun (vis, its) -> ctor ~visibility:vis its) with
  | [ s ] -> s
  | ss -> ESeq ss

let p_target_command_y1_inner name args kwargs =
  let kw_str_opt key =
    List.Assoc.find kwargs ~equal:String.equal key
    |> Option.bind ~f:(function
      | EString s | EVar s -> Some s
      | EVarLookup _ as e -> Some (str_of e)
      | _ -> None)
  in
  let kw_bool key =
    List.Assoc.mem kwargs ~equal:String.equal key
  in
  let kw_all key =
    List.filter_map kwargs ~f:(fun (k, v) -> Option.some_if (String.equal k key) v)
  in
  (* Command-lines from the label forms: `~commands=[[…],[…]]` (each item an
     EList → one command-line) takes priority; else `~command=[…]` is one. *)
  let kw_commands () =
    match kw_all "commands" with
    | (_ :: _) as cmds -> List.map cmds ~f:(function EList items -> items | e -> [ e ])
    | [] -> (match kw_all "command" with [] -> [] | items -> [ items ])
  in
  (* If the first positional arg after the target is a dynamic expression
     (not a known visibility keyword), the visibility is unresolvable at
     parse time. Fall back to yc_raw instead of misinterpreting ${kind}
     as a library name. *)
  let static_visibility_keywords = [ "PUBLIC"; "PRIVATE"; "INTERFACE" ] in
  let is_dynamic_first_item = function
    | EVar v :: _ ->
      not (List.mem static_visibility_keywords v ~equal:String.equal)
    | EString s :: _ ->
      (not (List.mem static_visibility_keywords s ~equal:String.equal))
      || String.is_prefix s ~prefix:"${"
    (* A `${...}` visibility is dynamic — unresolvable at parse time, so fall
       back to yc_raw rather than misread it (this is what kept these target
       commands flat before EVarLookup existed). *)
    | EVarLookup _ :: _ -> true
    | ECmakeGenex _ :: _ -> true
    | _ -> false
  in
  let try_groups_or_raw items ctor =
    if is_dynamic_first_item items
    then Some (ECmakeRawCmd { name = cmake_name_of_yelu name; args; from_positional = None })
    else Some (target_groups_to_y1 ctor items)
  in
  (* Implicit target (syntax #1): the first positional arg of a target
     command is a target, with or without the explicit `target` tag. Coerce
     it to ETarget here so both the CST path and the legacy parser agree.
     Idempotent for an already-tagged `target fmt`; correct for literal
     (`fmt`→`fmt`) and dynamic (`${tgt}`→`${tgt}`) names. The list excludes
     add_custom_command/add_custom_target (their first arg isn't a target
     expr). *)
  let args =
    if List.mem Yc_cst.target_first_arg_commands name ~equal:String.equal then
      match args with
      | (EVar s | EString s) :: rest -> ETarget s :: rest
      | (EVarLookup _ as e) :: rest -> ETarget (str_of e) :: rest
      | a -> a
    else args
  in
  match name, args with
  | "add_exe", name_arg :: sources ->
    Some (ECmakeAddExecutable { name = name_arg; sources })
  | "add_lib", name_arg :: sources ->
    let type_ = kw_str_opt "type" in
    Some (ECmakeAddLibrary
            { name = name_arg; type_; sources })
  | ("link_lib" | "target_link_libraries"), target :: items ->
    try_groups_or_raw items
      (fun ~visibility items ->
        ECmakeTargetLinkLibraries { target; visibility; items })
  | ("include_dirs" | "target_include_directories"), target :: items ->
    let system = kw_bool "system" in
    let before = kw_bool "before" in
    try_groups_or_raw items
      (fun ~visibility items ->
        ECmakeTargetIncludeDirectories
          { target; visibility; before; system; dirs = items })
  | ("compile_defs" | "target_compile_definitions"), target :: items ->
    try_groups_or_raw items
      (fun ~visibility items ->
        ECmakeTargetCompileDefinitions
          { target; visibility; definitions = items })
  | ("compile_opts" | "target_compile_options"), target :: items ->
    let before = kw_bool "before" in
    try_groups_or_raw items
      (fun ~visibility items ->
        ECmakeTargetCompileOptions
          { target; visibility; before; options_ = items })
  | ("compile_feats" | "target_compile_features"), target :: items ->
    try_groups_or_raw items
      (fun ~visibility items ->
        ECmakeTargetCompileFeatures
          { target; visibility; features = items })
  | ("link_opts" | "target_link_options"), target :: items ->
    let before = kw_bool "before" in
    try_groups_or_raw items
      (fun ~visibility items ->
        ECmakeTargetLinkOptions
          { target; visibility; before; options_ = items })
  | ("link_dirs" | "target_link_directories"), target :: items ->
    let before = kw_bool "before" in
    try_groups_or_raw items
      (fun ~visibility items ->
        ECmakeTargetLinkDirectories
          { target; visibility; before; dirs = items })
  | "target_sources", target :: items ->
    try_groups_or_raw items
      (fun ~visibility items ->
        ECmakeTargetSources { target; visibility; sources = items })
  | "add_lib_alias", args ->
    let name_arg = match args with
      | [ e ] -> e
      | [ ETarget s | EString s | EVar s; _ ] -> EVar s
      | ETarget s :: _ | EString s :: _ | EVar s :: _ -> EVar s
      | _ -> EVar "?"
    in
    let alias_of = kw_str_opt "alias_of" in
    let name = str_of name_arg in
    let alias_of = match alias_of with Some s -> s | None -> name in
    Some (add_lib_alias ~alias_of name)
  | "add_custom_target", name_arg :: rest ->
    (* Labeled-only (Step 2): any positional cmake keyword among the args is a
       fatal reject (use `~all`/`~command`/`~depends`/`~sources`/`~comment`). *)
    let ct_kw = [ "ALL"; "COMMAND"; "DEPENDS"; "SOURCES"; "COMMENT";
                  "BYPRODUCTS"; "WORKING_DIRECTORY"; "VERBATIM"; "USES_TERMINAL";
                  "COMMAND_EXPAND_LISTS"; "JOB_POOL" ] in
    let is_kw = function
      | EVar s | EString s -> List.mem ct_kw s ~equal:String.equal
      | _ -> false in
    if List.exists rest ~f:is_kw then
      Some (ECmakeRawCmd { name = cmake_name_of_yelu name; args;
                           from_positional = Some "add_custom_target" })
    else
      let all = kw_bool "all" in
      let commands = kw_commands () in
      let cc_list =
        List.map commands ~f:(fun cmd_args ->
          match cmd_args with
          | [] -> { Lang_cmake.command = ""; args = [] }
          | cmd :: arg_args ->
            { Lang_cmake.command = (str_of ~default:"" cmd);
              args = List.map arg_args ~f:(fun e ->
                str_of ~default:"" e) })
      in
      let depends = kw_all "depends" in
      let sources = kw_all "sources" in
      let comment = kw_str_opt "comment" in
      let name = str_of name_arg in
      Some (yc_add_custom_target ~all ~commands:cc_list
              ~depends ~comment ~sources name)
  | "add_custom_command", args ->
    (* Labeled-only (Step 2): any positional cmake keyword is a fatal reject —
       use `~output`/`~command`/`~depends`/`~comment`/`~verbatim`/
       `~command_expand_lists`. *)
    let cc_kw = [ "OUTPUT"; "COMMAND"; "DEPENDS"; "COMMENT"; "VERBATIM";
                  "COMMAND_EXPAND_LISTS"; "IMPLICIT_DEPENDS"; "WORKING_DIRECTORY";
                  "MAIN_DEPENDENCY"; "BYPRODUCTS"; "JOB_POOL"; "USES_TERMINAL";
                  "APPEND"; "DEPFILE"; "TARGET"; "PRE_BUILD"; "PRE_LINK";
                  "POST_BUILD" ] in
    let is_kw = function
      | EVar s | EString s -> List.mem cc_kw s ~equal:String.equal
      | _ -> false in
    if List.exists args ~f:is_kw then
      Some (ECmakeRawCmd { name = cmake_name_of_yelu name; args;
                           from_positional = Some "add_custom_command" })
    else
      let outputs = kw_all "output" in
      let verbatim = kw_bool "verbatim" in
      let command_expand_lists = kw_bool "command_expand_lists" in
      let comment = kw_str_opt "comment" in
      let depends = kw_all "depends" in
      let commands = kw_commands () in
      let build_commands = List.map commands ~f:(fun cmd_args ->
        match cmd_args with
        | [] -> { command = ""; args = [] }
        | cmd :: arg_args ->
          { command = (str_of ~default:"" cmd);
            args = List.map arg_args ~f:(fun e ->
              str_of ~default:"" e) })
      in
      Some (ECmakeAddCustomCommand
              { outputs; commands = build_commands; depends; comment; verbatim;
                command_expand_lists })
  | _ ->
    (* Known command but args don't match typed patterns
       (e.g. dynamic visibility ${kind}). Fall back to yc_raw. *)
    Some (ECmakeRawCmd { name = cmake_name_of_yelu name; args; from_positional = None })

let p_target_command_y1 toks =
  match toks with
  | IDENT name :: rest
      when (match name with
            | "add_exe" | "add_lib" | "link_lib" | "include_dirs"
            | "target_link_libraries" | "target_include_directories"
            | "compile_defs" | "compile_opts" | "compile_feats"
            | "target_compile_definitions" | "target_compile_options"
            | "target_compile_features" | "target_link_options"
            | "target_link_directories"
            | "link_opts" | "link_dirs" | "target_sources"
            | "add_lib_alias" | "add_custom_target" | "add_custom_command" -> true
            | _ -> false) ->
      let args, kwargs, rest = collect_command_args [] [] rest in
      p_target_command_y1_inner name args kwargs
      |> fallback_to_raw name args rest
    | _ -> None

(* ============================================================
   Dir family — add_subdirectory, include_directories,
   add_compile_definitions, add_compile_options, add_link_options,
   add_definitions, link_directories.
   ============================================================ *)

let p_dir_command_y1_inner name args _kwargs =
  match name, args with
  | "add_subdirectory", dir :: _ -> Some (yc_add_subdirectory dir)
  | "include_directories", dirs -> Some (yc_include_directories dirs)
  | "add_compile_definitions", defs -> Some (yc_add_compile_definitions defs)
  | "add_compile_options", opts -> Some (yc_add_compile_options opts)
  | "add_link_options", opts -> Some (yc_add_link_options opts)
  | "add_definitions", defs -> Some (yc_add_definitions defs)
  | "link_directories", dirs -> Some (yc_link_directories dirs)
  | _ -> None

let p_dir_command_y1 toks =
  match toks with
  | IDENT name :: rest
      when (match name with
            | "add_subdirectory" | "include_directories"
            | "add_compile_definitions" | "add_compile_options"
            | "add_link_options" | "add_definitions"
            | "link_directories" -> true
            | _ -> false) ->
      let args, kwargs, rest = collect_command_args [] [] rest in
      p_dir_command_y1_inner name args kwargs
      |> fallback_to_raw name args rest
    | _ -> None

(* ============================================================
   Test family — enable_testing, add_test.
   ============================================================ *)

let p_test_command_y1_inner name args _kwargs =
  let is_name_kw = function
    | EVar "NAME" | EString "NAME" -> true
    | _ -> false
  in
  match name, args with
  | "enable_testing", [] -> Some yc_enable_testing
  | "add_test", e :: _ when is_name_kw e ->
    (* Keyword form: add_test NAME <name> COMMAND <command> [args...].
       CONFIGURATIONS / WORKING_DIRECTORY are accepted but not yet
       plumbed to the typed IR; split_by_keywords isolates them so
       the NAME/COMMAND sections parse correctly. *)
    let sections = split_by_keywords
        ~keywords:["NAME"; "COMMAND"; "CONFIGURATIONS"; "WORKING_DIRECTORY"]
        args in
    let name = match List.Assoc.find sections ~equal:String.equal "NAME" with
      | Some (n :: _) -> n | _ -> EString "?"
    in
    let command, call_args =
      match List.Assoc.find sections ~equal:String.equal "COMMAND" with
      | Some (cmd :: rest) -> (cmd, rest)
      | _ -> (EString "?", [])
    in
    Some (yc_add_test name command call_args)
  | "add_test", name_arg :: command :: rest ->
    (* Positional form: add_test <name> <command> [args...] *)
    Some (yc_add_test name_arg command rest)
  | _ -> None

let p_test_command_y1 toks =
  match toks with
  | IDENT name :: rest
      when String.equal name "enable_testing"
        || String.equal name "add_test" ->
      let args, kwargs, rest = collect_command_args [] [] rest in
      p_test_command_y1_inner name args kwargs
      |> fallback_to_raw name args rest
    | _ -> None

(* ============================================================
   Property family — get/set_target_property, set_property,
   {get,set}_{directory,global,source,tests}_property.

   Legacy parser defaults the property name to "PROP" when not
   parsed; mirror this for byte-equality.
   ============================================================ *)

(* ============================================================
   First-class cmake entity (Pos3 prototype, 2026-06-14)

   A kinded named cmake object — `Target foo`, `Source 'main.c'`,
   `Cache FOO`, `Test 'mytest'`, `Install 'lib.so'`, `Directory ['sub']`,
   `Global`. The surface form is "leading-cap constructor [+ name]"; the
   typed value is the constructor + payload.

   Today this is a parser-local type used by set_property's scope reader.
   When get_property / install / etc. start sharing it, promote to an IR
   value class (likely as an extensible-expr ctor in a new fragment) and
   give it concrete syntax for free anywhere an expr is allowed —
   enabling the future object-method form
   `target_foo.set_property(k=v, ~append)`.

   ── parsing ────────────────────────────────────────────────

   Both surface forms accepted (Pos3 sits on top of Pos2 / Lane A):

   - leading-cap KEYWORD form, via [Yelu_lexer.constr_names]:
       Source 'main.c'   → EString "SOURCE" :: EString "main.c"
       Cache FOO         → EString "CACHE"  :: EVar "FOO"
       Global            → EString "GLOBAL"
   - legacy bare ALLCAPS:
       SOURCE 'main.c'   → EVar/EString "SOURCE" :: EString "main.c"
   - first-class TARGET prototype (existing reserved-word path):
       Target foo        → ETarget "foo"

   The reader recognizes any of these and dispatches to the matching
   [cmake_entity] constructor. ============================================================ *)

type cmake_entity =
  | Ent_target of expr
  | Ent_source of expr
  | Ent_cache of expr
  | Ent_test of expr
  | Ent_install of expr
  | Ent_directory of expr option   (* DIRECTORY [<dir>] — optional name *)
  | Ent_global                     (* GLOBAL — no payload *)
  | Ent_variable                   (* VARIABLE — no payload (get_property only) *)

(* Recognize a scope keyword at args[0]. Returns the entity kind tag (as a
   first-class function consuming the rest) plus the remaining args. *)
let entity_kind_of_expr = function
  | EVar "GLOBAL"    | EString "GLOBAL"    -> Some `Global
  | EVar "DIRECTORY" | EString "DIRECTORY" -> Some `Directory
  | EVar "SOURCE"    | EString "SOURCE"    -> Some `Source
  | EVar "INSTALL"   | EString "INSTALL"   -> Some `Install
  | EVar "TEST"      | EString "TEST"      -> Some `Test
  | EVar "CACHE"     | EString "CACHE"     -> Some `Cache
  | EVar "VARIABLE"  | EString "VARIABLE"  -> Some `Variable
  | EVar "TARGET"    | EString "TARGET"    -> Some `Target_keyword
  | _ -> None

(* Read one cmake entity from the front of the args list. Returns
   [Some (entity, rest)] when the leading args form an entity, else [None].

   - `Target foo` (ETarget) — single-positional form, name carried in ctor
   - `Source 'p'` / `Cache FOO` / `Test t` / `Install f` — keyword + name
   - `Global` — no name
   - `Directory ['d']` — optional name (peek next positional; if absent,
     payload is None). The current set_property dispatch doesn't enter the
     Directory branch, so this is here for symmetry with future use sites. *)
(* In a cmake entity-NAME slot a bare identifier is the *literal* name
   (`set_property(CACHE FOO …)` — FOO is the entry name, not a var deref).
   [p_expr_y1] lowers a bare ident to [EVar], a deref position; normalize it
   to [EString] (literal) here, mirroring the [ETarget] branch's [EString].
   A `$x` (EVarLookup) stays a deref — `set_property(CACHE ${x} …)`. *)
let entity_name = function
  | EVar n -> EString n
  | e -> e

let p_cmake_entity (args : expr list) : (cmake_entity * expr list) option =
  match args with
  | ETarget name :: rest -> Some (Ent_target (EString name), rest)
  | e :: rest ->
    (match entity_kind_of_expr e with
     | None -> None
     | Some `Global       -> Some (Ent_global,                 rest)
     | Some `Variable     -> Some (Ent_variable,               rest)
     | Some `Target_keyword ->
       (match rest with
        | name :: rest' -> Some (Ent_target (entity_name name), rest')
        | []            -> None)
     | Some `Source ->
       (match rest with
        | name :: rest' -> Some (Ent_source (entity_name name), rest')
        | []            -> None)
     | Some `Cache ->
       (match rest with
        | name :: rest' -> Some (Ent_cache (entity_name name), rest')
        | []            -> None)
     | Some `Test ->
       (match rest with
        | name :: rest' -> Some (Ent_test (entity_name name), rest')
        | []            -> None)
     | Some `Install ->
       (match rest with
        | name :: rest' -> Some (Ent_install (entity_name name), rest')
        | []            -> None)
     | Some `Directory ->
       (match rest with
        | name :: rest' -> Some (Ent_directory (Some (entity_name name)), rest')
        | []            -> Some (Ent_directory None, [])))
  | [] -> None

(* Lower a cmake_entity into the set_property_scope variant. Multi-entity
   forms (`TARGET t1 t2 ...`) are not entity-readable today — for now those
   stay positional and are read by the existing split-by-keywords flow.
   This lifts the SINGLE-entity case, which covers the common forms. *)
let entity_to_sps = function
  | Ent_target e    -> Yelu_cmake_property.Sps_target [ e ]
  | Ent_source e    ->
    Yelu_cmake_property.Sps_source
      { sources = [ e ]; directories = []; target_directories = [] }
  | Ent_cache e     -> Yelu_cmake_property.Sps_cache [ e ]
  | Ent_test e      ->
    Yelu_cmake_property.Sps_test { tests = [ e ]; directories = [] }
  | Ent_install e   -> Yelu_cmake_property.Sps_install [ e ]
  | Ent_directory d -> Yelu_cmake_property.Sps_directory d
  | Ent_global      -> Yelu_cmake_property.Sps_global
  | Ent_variable    ->
    (* VARIABLE scope only exists in get_property. Caller should reject this
       at the set_property dispatch; treat as Global as a defensive fallback. *)
    Yelu_cmake_property.Sps_global

(* Mirror lowering for get_property — single-name per scope (vs set_property's
   list); plus the unique VARIABLE scope. *)
let entity_to_gps = function
  | Ent_target e     -> Some (Yelu_cmake_property.Gps_target e)
  | Ent_source e     ->
    Some (Yelu_cmake_property.Gps_source
            { source = e; directory = None; target_directory = None })
  | Ent_cache e      -> Some (Yelu_cmake_property.Gps_cache e)
  | Ent_test e       ->
    Some (Yelu_cmake_property.Gps_test { test = e; directory = None })
  | Ent_install e    -> Some (Yelu_cmake_property.Gps_install e)
  | Ent_directory d  -> Some (Yelu_cmake_property.Gps_directory d)
  | Ent_global       -> Some Yelu_cmake_property.Gps_global
  | Ent_variable     -> Some Yelu_cmake_property.Gps_variable

let p_property_command_y1_inner name args kwargs =
  let out = out_var_y1 kwargs in
  let kwarg_bool ~key = List.Assoc.mem kwargs ~equal:String.equal key in
  (* `~property=[NAME, val1, val2, ...]` arrives flattened by convert_args as
     N entries with the same key. Filtering preserves source order. Returns
     [Some (name, values)] when the kwarg is present, else None. *)
  let property_kwarg () =
    match List.filter_map kwargs ~f:(fun (k, v) ->
      if String.equal k "property" then Some v else None)
    with
    | [] -> None
    | name :: values -> Some (str_of name, values)
  in
  match name, args with
  | "get_property", args
    when (let kw = [ "PROPERTY"; "SET"; "DEFINED"; "BRIEF_DOCS"; "FULL_DOCS" ] in
          List.exists args ~f:(function
            | EVar s | EString s -> List.mem kw s ~equal:String.equal
            | _ -> false)) ->
    (* Labeled-only (Step 2): a positional PROPERTY / mode (SET/DEFINED/…)
       keyword is a fatal reject — use ~property= / ~mode= / ~out=. *)
    Some (ECmakeRawCmd { name = cmake_name_of_yelu name; args;
                         from_positional = Some "get_property" })
  | "get_property", args ->
    (* Pos3 entity-driven dispatch — parallel to set_property. The output
       var arrives via `~out=var` kwarg or as a leading positional (legacy
       form `get_property myvar Target foo PROPERTY name ...`).
       Trailing mode selector: positional `SET`/`DEFINED`/`BRIEF_DOCS`/
       `FULL_DOCS` (now leading-cap KEYWORD tokens) or `~mode=Set/Defined/...`
       kwarg. Property name from `~property=NAME` or positional PROPERTY name.
       VARIABLE is supported via [Ent_variable] (unique to get_property). *)
    let var_pos, args = match args with
      | leading :: rest
        when Option.is_none (entity_kind_of_expr leading)
          && (match leading with ETarget _ -> false | _ -> true) ->
        (* leading non-entity, non-Target → treat as the var positional *)
        Some leading, rest
      | _ -> None, args
    in
    let var = match var_pos with
      | Some e -> str_of e
      | None -> out
    in
    (match p_cmake_entity args with
     | None -> None       (* no scope keyword found → fall through to raw *)
     | Some (entity, _rest) ->
       match entity_to_gps entity with
       | None -> None
       | Some scope ->
         (* Labeled-only (Step 2): property name from `~property=NAME`, mode from
            `~mode=Set/Defined/...` (the value an enum constructor the lexer
            uppercases to a KEYWORD / EString). The positional PROPERTY / mode
            keywords are rejected upstream. *)
         let property_name =
           match property_kwarg () with Some (name, _) -> name | None -> "PROP"
         in
         let mode : Yelu_cmake_property.get_property_mode =
           match List.Assoc.find kwargs ~equal:String.equal "mode" with
           | Some (EString "SET")        -> Gpm_set
           | Some (EString "DEFINED")    -> Gpm_defined
           | Some (EString "BRIEF_DOCS") -> Gpm_brief_docs
           | Some (EString "FULL_DOCS")  -> Gpm_full_docs
           | Some (EString "VALUE")      -> Gpm_value
           | _                           -> Gpm_value
         in
         Some (Yelu_cmake_property.ECmakeGetProperty
                 { var; scope; property = property_name; mode }))
  | "get_target_property", [ var; target; property ] ->
    let var = str_of var in
    let target = str_of target in
    let property = str_of property in
    Some (yc_get_target_property var target property)
  | "get_target_property", [ tgt ] ->
    Some (yc_get_property ~target:tgt "PROP" out)
  | "set_target_properties", _ :: rest
    when List.exists rest ~f:(function
           | EVar ("PROPERTY" | "PROPERTIES")
           | EString ("PROPERTY" | "PROPERTIES") -> true | _ -> false) ->
    (* Labeled-only (Step 2): the positional PROPERTY/PROPERTIES form is a fatal
       reject — use the `~properties={…}` record. *)
    Some (ECmakeRawCmd { name = cmake_name_of_yelu name; args;
                         from_positional = Some "set_target_properties" })
  | "set_target_properties", target :: _rest ->
    (* Labeled-only (Step 2): properties from the `~properties={…}` record.
       Keys uppercase to the cmake property name; a list value `;`-joins. The
       positional PROPERTY/PROPERTIES form is rejected upstream. *)
    let record_props =
      match List.Assoc.find kwargs ~equal:String.equal "properties" with
      | Some (ERecord fields) ->
        List.map fields ~f:(fun (k, v) ->
          let value = match v with
            | EList items ->
              EString (String.concat ~sep:";" (List.map items ~f:(str_of ~default:"")))
            | _ -> v in
          (String.uppercase k, value))
      | _ -> []
    in
    Some (yc_set_target_properties target record_props)
  | "set_source_files_properties", args
    when List.exists args ~f:(function
           | EVar s | EString s ->
             List.mem [ "PROPERTIES"; "DIRECTORY"; "TARGET_DIRECTORY" ] s
               ~equal:String.equal
           | _ -> false) ->
    (* Labeled-only (Step 2): the positional PROPERTIES form is a fatal reject —
       use the `~properties={…}` record (mirrors set_target_properties). *)
    Some (ECmakeRawCmd { name = cmake_name_of_yelu name; args;
                         from_positional = Some "set_source_files_properties" })
  | "set_source_files_properties", args ->
    (* files positional, ~properties={k=v} record; keys uppercase, list `;`-joins *)
    let files = args in
    let properties =
      match List.Assoc.find kwargs ~equal:String.equal "properties" with
      | Some (ERecord fields) ->
        List.map fields ~f:(fun (k, v) ->
          let value = match v with
            | EList items ->
              EString (String.concat ~sep:";" (List.map items ~f:(str_of ~default:"")))
            | _ -> v in
          (String.uppercase k, value))
      | _ -> []
    in
    Some (yc_set_source_files_properties files properties)
  | "set_property", args
    when (let kw = [ "PROPERTY"; "APPEND"; "APPEND_STRING" ] in
          List.exists args ~f:(function
            | EVar s | EString s -> List.mem kw s ~equal:String.equal
            | _ -> false)) ->
    (* Labeled-only (Step 2): the positional PROPERTY / APPEND / APPEND_STRING
       form is a fatal reject — use ~property= / ~append / ~append_string. The
       entity scope (Target/Source/Cache/Global/Test/Install) stays positional;
       it is the enum-constructor surface, not a cmake keyword. *)
    Some (ECmakeRawCmd { name = cmake_name_of_yelu name; args;
                         from_positional = Some "set_property" })
  | "set_property", args ->
    (* Pos3-driven scope dispatch (2026-06-14). [p_cmake_entity] reads
       a leading entity (Target / Source / Cache / Global / Test / Install
       / Directory) from the args. The remaining "head" positionals from
       the body fold into the same-kind scope list (e.g. multi-target
       `TARGET t1 t2 ...` → Sps_target [t1; t2; ...]). No leading entity
       → implicit TARGET scope (the default; matches the bare
       `set_property foo PROPERTY ...` form). *)
    let scope_opt, body_args = match p_cmake_entity args with
      | Some (ent, rest) -> (Some ent, rest)
      | None -> (None, args)
    in
    (* Labeled-only (Step 2): the body positionals are all scope names (no
       keyword section to split); ~append / ~append_string flags + the
       ~property=[NAME, vals…] value-list. The positional PROPERTY/APPEND form
       is rejected upstream. *)
    let head = body_args in
    let append = kwarg_bool ~key:"append" in
    let append_string = kwarg_bool ~key:"append_string" in
    let collapse_values values =
      match values with
      | [ v ] -> v
      | _ -> EString (String.concat ~sep:";" (List.map values ~f:(fun e ->
          str_of ~default:"" e)))
    in
    let properties =
      match property_kwarg () with
      | Some (name, values) -> [(name, collapse_values values)]
      | None -> []
    in
    (* Build the scope sum from the entity (+ trailing same-kind names from
       the head, for multi-target / multi-source / multi-cache calls).
       [Ent_variable] is rejected — VARIABLE scope exists only in get_property
       per the cmake spec; using it here would be a semantic error. *)
    let scope : Yelu_cmake_property.set_property_scope option = match scope_opt with
      | Some Ent_global       -> Some Sps_global
      | Some (Ent_target e)   -> Some (Sps_target (e :: head))
      | Some (Ent_source e)   ->
        Some (Sps_source
                { sources = e :: head; directories = []; target_directories = [] })
      | Some (Ent_cache e)    -> Some (Sps_cache (e :: head))
      | Some (Ent_test e)     -> Some (Sps_test { tests = e :: head; directories = [] })
      | Some (Ent_install e)  -> Some (Sps_install (e :: head))
      | Some (Ent_directory d) -> Some (Sps_directory d)
      | Some Ent_variable     -> None       (* VARIABLE not valid in set_property *)
      | None                  -> Some (Sps_target head)    (* implicit TARGET *)
    in
    (match scope with
     | None -> None
     | Some scope ->
       Some (Yelu_cmake_property.ECmakeSetProperty
               { scope; append; append_string; properties }))
  | "get_directory_property", [] ->
    Some (yc_get_directory_property "PROP" out)
  | "set_directory_property", [] ->
    Some (yc_set_directory_property "PROP" [])
  | "set_test_properties", [ test ] ->
    Some (yc_set_tests_properties [ test ] [])
  | "set_source_property", [ file ] ->
    Some (yc_set_source_property ~property:"PROP" file [])
  | "set_global_property", [] ->
    Some (yc_set_global_property [])
  | "get_global_property", [] ->
    Some (yc_get_global_property ~property:"PROP" out)
  | _ -> None

let p_property_command_y1 toks =
  match toks with
  | IDENT name :: rest
      when (match name with
            | "get_target_property" | "set_target_properties"
            | "set_property" | "get_property"
            | "get_directory_property" | "set_directory_property"
            | "set_test_properties"
            | "set_source_property" | "set_source_files_properties"
            | "set_global_property" | "get_global_property" -> true
            | _ -> false) ->
      let args, kwargs, rest = collect_command_args [] [] rest in
      p_property_command_y1_inner name args kwargs
      |> fallback_to_raw name args rest
    | _ -> None

(* ============================================================
   Find family — find_package, find_library/path/program/file.
   Legacy parser defaults names/paths/hints lists to empty.
   ============================================================ *)

let p_find_command_y1_inner name args kwargs =
  let kwarg_list ~key =
    List.filter_map kwargs ~f:(fun (k, v) ->
      if String.equal k key then Some v else None)
  in
  let cvar_name = function
    | EVar n -> n
    | EString n -> n
    | ETarget n -> n
    | _ -> "?"
  in
  let str_name = function
    | EString s | EVar s -> s
    | _ -> ""
  in
  match name, args with
  | "find_package", pkg :: rest ->
    (* Accept positional `REQUIRED` and the canonical `~required` flag (a
       boolean kwarg, so absent from [rest]). *)
    let required =
      List.exists rest ~f:(function
        | EVar "REQUIRED" | EString "REQUIRED" -> true | _ -> false)
      || List.Assoc.mem kwargs ~equal:String.equal "required" in
    Some (yc_find_package ~required (str_name pkg))
  | "find_library", [ cvar ] ->
    let names = kwarg_list ~key:"name" @ kwarg_list ~key:"names" in
    let paths = kwarg_list ~key:"path" @ kwarg_list ~key:"paths" in
    Some (yc_find_library ~names ~paths (cvar_name cvar))
  | "find_path", [ cvar ] ->
    let names = kwarg_list ~key:"name" @ kwarg_list ~key:"names" in
    let paths = kwarg_list ~key:"path" @ kwarg_list ~key:"paths" in
    Some (yc_find_path ~names ~paths (cvar_name cvar))
  | "find_program", [ cvar ] ->
    let names = kwarg_list ~key:"name" @ kwarg_list ~key:"names" in
    let paths = kwarg_list ~key:"path" @ kwarg_list ~key:"paths" in
    Some (yc_find_program ~names ~paths (cvar_name cvar))
  | "find_file", [ cvar ] ->
    let names = kwarg_list ~key:"name" @ kwarg_list ~key:"names" in
    let paths = kwarg_list ~key:"path" @ kwarg_list ~key:"paths" in
    Some (yc_find_file ~names ~paths (cvar_name cvar))
  | _ -> None

let p_find_command_y1 toks =
  match toks with
  | IDENT name :: rest
      when String.is_prefix name ~prefix:"find_" ->
      let args, kwargs, rest = collect_command_args [] [] rest in
      p_find_command_y1_inner name args kwargs
      |> fallback_to_raw name args rest
    | _ -> None

(* ============================================================
   Install family — install_targets / install_files / install_export
   / export / configure_package_config_file /
   write_basic_package_version_file.

   For install_targets and install_files the legacy parser uses
   [record_args] (from a `{ ... }` brace form) for the targets/files
   list. Without a brace form (the common case in parser tests),
   that's empty.
   ============================================================ *)

let p_install_command_y1_inner name args kwargs =
  let kwarg_opt ~key = List.Assoc.find kwargs ~equal:String.equal key in
  let kwarg_bool ~key = List.Assoc.mem kwargs ~equal:String.equal key in
  match name, args with
  | "install_targets", args ->
    (* Labeled-only (Step 2): clauses come from dotted labels
       (`~library.destination=`) + top-level `~component=`/`~export=`/
       `~destination=`; the leading positionals are the targets. The positional
       cmake-keyword form (`LIBRARY DESTINATION …`) is NOT a yc surface — it is
       tagged as a positional reject (Yc_wellform turns it into a fatal "use
       ~label= / yc_raw" error). See painpoints.md §11. *)
    let art_kw = ["LIBRARY"; "ARCHIVE"; "RUNTIME"; "OBJECTS"; "FRAMEWORK";
                  "BUNDLE"; "PUBLIC_HEADER"; "PRIVATE_HEADER"; "RESOURCE";
                  "FILE_SET"; "CXX_MODULES_BMI"] in
    let opt_kw = ["DESTINATION"; "COMPONENT"; "EXPORT"; "PERMISSIONS";
                  "CONFIGURATIONS"; "NAMELINK_COMPONENT"] in
    let arg_is_kw = function
      | EVar s | EString s -> List.mem (art_kw @ opt_kw) s ~equal:String.equal
      | _ -> false in
    if List.exists args ~f:arg_is_kw then
      Some (ECmakeRawCmd { name = cmake_name_of_yelu "install_targets"; args;
                           from_positional = Some "install_targets" })
    else
      let as_str = function Some (EString s | EVar s) -> Some s | _ -> None in
      (* dotted-label clauses: key "library.destination" -> (LIBRARY, value) *)
      let artifact_clauses = List.filter_map kwargs ~f:(fun (key, v) ->
        match String.lsplit2 key ~on:'.' with
        | Some (kind, "destination") -> Some (String.uppercase kind, v)
        | _ -> None) in
      let component = as_str (kwarg_opt ~key:"component") in
      let export = kwarg_opt ~key:"export" in
      let destination = kwarg_opt ~key:"destination" in
      Some (yc_install_targets ?export ?component ~artifact_clauses args destination)
  | "install_files", args ->
    (* Labeled-only (Step 2): a positional DESTINATION/COMPONENT/… keyword is a
       fatal reject; the labeled `~destination=`/`~component=` form is the
       supported surface. The bare `install_files dir files…` shorthand (no
       keyword) stays for the deprecated INSTALL_FILES shape. *)
    let kw = [ "DESTINATION"; "COMPONENT"; "RENAME"; "PERMISSIONS";
               "CONFIGURATIONS"; "OPTIONAL" ] in
    let is_kw = function
      | EVar s | EString s -> List.mem kw s ~equal:String.equal | _ -> false in
    if List.exists args ~f:is_kw then
      Some (ECmakeRawCmd { name = cmake_name_of_yelu name; args;
                           from_positional = Some "install_files" })
    else if kwarg_bool ~key:"destination" || kwarg_bool ~key:"component" then
      let files = args in
      let destination = match kwarg_opt ~key:"destination" with
        | Some e -> e | None -> EString "?" in
      let component = match kwarg_opt ~key:"component" with
        | Some (EString s | EVar s) -> Some s | _ -> None in
      Some (yc_install_files ?component files destination)
    else begin
      (* Backward-compat positional: install_files dest files *)
      match args with
      | destination :: files ->
        Some (yc_install_files files destination)
      | _ -> None
    end
  | "install_export", args ->
    let kw = [ "DESTINATION"; "FILE"; "NAMESPACE"; "COMPONENT";
               "EXPORT_LINK_INTERFACE_LIBRARIES"; "PERMISSIONS";
               "CONFIGURATIONS" ] in
    let is_kw = function
      | EVar s | EString s -> List.mem kw s ~equal:String.equal | _ -> false in
    if List.exists args ~f:is_kw then
      Some (ECmakeRawCmd { name = cmake_name_of_yelu name; args;
                           from_positional = Some "install_export" })
    else if kwarg_bool ~key:"destination" || kwarg_bool ~key:"file"
            || kwarg_bool ~key:"namespace" || kwarg_bool ~key:"component" then
      let export = match args with e :: _ -> e | [] -> EVar "?" in
      let destination = match kwarg_opt ~key:"destination" with
        | Some e -> e | None -> EString "?" in
      let file = kwarg_opt ~key:"file" in
      let namespace = match kwarg_opt ~key:"namespace" with
        | Some (EString s | EVar s) -> Some s | _ -> None in
      let component = match kwarg_opt ~key:"component" with
        | Some (EString s | EVar s) -> Some s | _ -> None in
      Some (yc_install_export ?file ?namespace ?component export destination)
    else begin
      (* Backward-compat positional: install_export exp dest *)
      match args with
      | [ export; destination ] ->
        Some (yc_install_export export destination)
      | _ -> None
    end
  | "install_directory", args ->
    let kw = [ "DESTINATION"; "COMPONENT"; "OPTIONAL"; "PATTERN"; "REGEX";
               "EXCLUDE"; "PERMISSIONS"; "CONFIGURATIONS"; "FILES_MATCHING";
               "DIRECTORY_PERMISSIONS"; "FILE_PERMISSIONS" ] in
    let is_kw = function
      | EVar s | EString s -> List.mem kw s ~equal:String.equal | _ -> false in
    if List.exists args ~f:is_kw then
      Some (ECmakeRawCmd { name = cmake_name_of_yelu name; args;
                           from_positional = Some "install_directory" })
    else
      let directory = match args with e :: _ -> e | [] -> EVar "?" in
      let destination = match kwarg_opt ~key:"destination" with
        | Some e -> e | None -> EString "?" in
      let component = match kwarg_opt ~key:"component" with
        | Some (EString s | EVar s) -> Some s | _ -> None in
      let optional = kwarg_bool ~key:"optional" in
      Some (yc_install_directory ?component ~optional directory destination)
  | "export", args ->
    (* Check for keyword form: export TARGETS ... NAMESPACE ... FILE ... *)
    let has_targets = List.exists args ~f:(function
      | EVar "TARGETS" | EString "TARGETS" -> true | _ -> false)
    in
    if has_targets then
      let sections = split_by_keywords ~keywords:["TARGETS"; "NAMESPACE"; "FILE"] args in
      let targets = match List.Assoc.find sections ~equal:String.equal "TARGETS" with
        | Some items -> items | None -> []
      in
      let namespace = match List.Assoc.find sections ~equal:String.equal "NAMESPACE" with
        | Some [ EString s | EVar s ] -> Some s
        | _ -> None
      in
      let file = match List.Assoc.find sections ~equal:String.equal "FILE" with
        | Some (e :: _) -> Some e
        | _ -> None
      in
      Some (yc_export_targets ?namespace ?file targets)
    else begin match args with
      | [ name_arg ] ->
        let file = kwarg_opt ~key:"file" in
        Some (yc_export_export ?file name_arg)
      | _ -> None
    end
  | "configure_package_config_file", args ->
    let has_install_dest = List.exists args ~f:(function
      | EVar "INSTALL_DESTINATION" | EString "INSTALL_DESTINATION" -> true
      | _ -> false)
    in
    if has_install_dest then
      let sections = split_by_keywords ~keywords:["INSTALL_DESTINATION"] args in
      let positional = match List.Assoc.find sections ~equal:String.equal "_head" with
        | Some items -> items | None -> []
      in
      let input, output = match positional with
        | [ a; b ] -> (a, b)
        | [ a ] -> (a, EVar "?")
        | _ -> (EVar "?", EVar "?")
      in
      let install_dest = match List.Assoc.find sections ~equal:String.equal
                               "INSTALL_DESTINATION" with
        | Some (e :: _) -> e
        | _ -> EVar "?"
      in
      let no_set_and_check_macro = kwarg_bool ~key:"no_set_and_check_macro" in
      let no_check_required_components_macro =
        kwarg_bool ~key:"no_check_required_components_macro" in
      Some (yc_configure_package_config_file
              ~no_set_and_check_macro ~no_check_required_components_macro
              install_dest input output)
    else
      let install_dest, input, output = match args with
        | [ dest; input; output ] -> (dest, input, output)
        | [ dest; input ] -> (dest, input, EVar "?")
        | _ -> (EVar "?", EVar "?", EVar "?")
      in
      let no_set_and_check_macro = kwarg_bool ~key:"no_set_and_check_macro" in
      let no_check_required_components_macro =
        kwarg_bool ~key:"no_check_required_components_macro" in
      Some (yc_configure_package_config_file
              ~no_set_and_check_macro ~no_check_required_components_macro
              install_dest input output)
  | "write_basic_package_version_file", [ file ] ->
    let version = kwarg_opt ~key:"version" in
    let compatibility = match kwarg_opt ~key:"compatibility" with
      | Some (EString "SameMajorVersion" | EVar "SameMajorVersion") ->
        Lang_cmake.Same_major_version
      | Some (EString "SameMinorVersion" | EVar "SameMinorVersion") ->
        Lang_cmake.Same_minor_version
      | Some (EString "ExactVersion" | EVar "ExactVersion") ->
        Lang_cmake.Exact_version
      | _ -> Lang_cmake.Any_newer_version in
    Some (yc_write_basic_package_version_file
            ~compatibility ?version file)
  | _ -> None

let p_install_command_y1 toks =
  match toks with
  | IDENT name :: rest
      when (match name with
            | "install_targets" | "install_files" | "install_export"
            | "install_directory"
            | "export" | "configure_package_config_file"
            | "write_basic_package_version_file" -> true
            | _ -> false) ->
      let args, kwargs, rest = collect_command_args [] [] rest in
      p_install_command_y1_inner name args kwargs
      |> fallback_to_raw name args rest
    | _ -> None

(* ============================================================
   try family (try_compile / try_run scalar forms).

   The legacy parser only recognizes the bare command forms (no
   keyword args), mapping them to Ytry_compile / Ytry_run records with
   default-empty payloads. The bridge then folds default-payload
   Ytry_compile into [ECmakeTryCompile] (the simple ctor) and
   non-default into [ECmakeTryCompileEx]. Mirror that here.
   ============================================================ *)

let p_try_command_y1_inner name args _kwargs =
  match name, args with
  | "try_compile", [ result ] ->
    Some (yc_try_compile (cvar_name_of_y1 result) [])
  | "try_run", [ run_result; compile_result ] ->
    Some (yc_try_run (cvar_name_of_y1 run_result)
            (cvar_name_of_y1 compile_result) [])
  | _ -> None

let p_try_command_y1 toks =
  match toks with
  | IDENT name :: rest
      when (match name with
            | "try_compile" | "try_run" -> true
            | _ -> false) ->
      let args, kwargs, rest = collect_command_args [] [] rest in
      p_try_command_y1_inner name args kwargs
      |> fallback_to_raw name args rest
    | _ -> None

(* ============================================================
   cmake_op family (scalar commands; control flow deferred).
   project / cmake_minimum_required / message / math / include /
   include_guard / policy_set / enable_language / execute_process /
   separate_arguments / cmake_call / cmake_eval /
   cmake_get_log_level / at_var.

   Many of these accept STRING / PATH args that the legacy parser
   extracts directly. Tiny mostly stores them as raw strings (not
   exprs), so we extract a string from EString / EVar.
   ============================================================ *)

let p_cmake_op_command_y1_inner name args kwargs =
  let out = out_var_y1 kwargs in
  match name, args with
  | "cmake_minimum_required", args
    when List.exists args ~f:(function
           | EVar "VERSION" | EString "VERSION" -> true | _ -> false) ->
    (* Labeled-only (Step 2): the VERSION keyword carries no information (the
       version is the sole argument), so the surface is bare — the positional
       VERSION form is a fatal reject. *)
    Some (ECmakeRawCmd { name = cmake_name_of_yelu name; args;
                         from_positional = Some "cmake_minimum_required" })
  | "cmake_minimum_required", args ->
    (* bare version: the single positional arg is the version range *)
    let version = match args with
      | (EString s | EVar s) :: _ -> s
      | _ -> "3.20"
    in
    Some (ECmakeMinimumRequired version)
  | "project", [ name_e ] ->
    let s = match name_e with
      | EString s | EVar s -> s
      | _ -> "Project"
    in
    Some (ECmakeProject { name = s; languages = []; version = None })
  | "project", name_e :: langs ->
    let s = match name_e with
      | EString s | EVar s -> s
      | _ -> "Project"
    in
    let languages = List.map langs ~f:(fun e ->
      str_of ~default:"" e) in
    Some (ECmakeProject { name = s; languages; version = None })
  | "message", args ->
    let mode, texts = match args with
      | EVar m :: rest | EString m :: rest ->
        (match m with
         | "STATUS" | "FATAL_ERROR" | "SEND_ERROR"
         | "WARNING" | "AUTHOR_WARNING" | "DEPRECATION"
         | "NOTICE" | "VERBOSE" | "DEBUG" | "TRACE" ->
           (message_mode_of_string m, rest)
         | _ -> (Lang_cmake.Mm_status, args))
      | _ -> (Lang_cmake.Mm_status, args)
    in
    let texts =
      List.map texts ~f:(fun e ->
        match e with EString s -> s | _ -> "")
    in
    Some (yc_message ~mode texts)
  | "math", [ exp ] ->
    let s = match exp with EString s -> s | _ -> "" in
    Some (yc_math s out)
  | "include", [ file ] ->
    let optional =
      List.Assoc.mem kwargs ~equal:String.equal "optional"
    in
    (* Bare ident → literal module name, not variable ref.
       cmake include() takes a file/module name, never a var. *)
    let file = match file with EVar s -> EString s | e -> e in
    Some (yc_include ~optional file)
  (* Accepts bare `include_guard GLOBAL`, the no-arg form, and the
     canonical `include_guard ~global` (the flag arrives as an empty-args
     call + a `global` boolean kwarg). All map to the GLOBAL scope — the
     only include_guard scope yc currently models. *)
  | "include_guard", []
  | "include_guard", [ EVar "GLOBAL" | EString "GLOBAL" ] ->
    Some (yc_include_guard Lang_cmake.Ig_global)
  | "policy_set", id :: _ ->
    Some (yc_policy_set ~new_:true (str_of id))
  | "enable_language", args
    when List.exists args ~f:(function
           | EVar "OPTIONAL" | EString "OPTIONAL" -> true | _ -> false) ->
    (* Labeled-only (Step 2): positional OPTIONAL → fatal reject; use ~optional. *)
    Some (ECmakeRawCmd { name = cmake_name_of_yelu name; args;
                         from_positional = Some "enable_language" })
  | "enable_language", args ->
    (* languages positional, ~optional flag *)
    let optional = List.Assoc.mem kwargs ~equal:String.equal "optional" in
    let langs = List.filter_map args ~f:(function
      | EVar s | EString s -> Some s | _ -> None)
    in
    Some (ECmakeEnableLanguage { langs; optional })
  | "execute_process", args
    when (let kw = [ "COMMAND"; "WORKING_DIRECTORY"; "TIMEOUT";
                     "RESULT_VARIABLE"; "RESULTS_VARIABLE"; "OUTPUT_VARIABLE";
                     "ERROR_VARIABLE"; "INPUT_FILE"; "OUTPUT_FILE"; "ERROR_FILE";
                     "OUTPUT_QUIET"; "ERROR_QUIET"; "ENCODING"; "ECHO_OUTPUT_VARIABLE";
                     "ECHO_ERROR_VARIABLE"; "OUTPUT_STRIP_TRAILING_WHITESPACE";
                     "ERROR_STRIP_TRAILING_WHITESPACE"; "COMMAND_ERROR_IS_FATAL";
                     "COMMAND_ECHO" ] in
          List.exists args ~f:(function
            | EVar s | EString s -> List.mem kw s ~equal:String.equal
            | _ -> false)) ->
    (* Labeled-only (Step 2): a positional cmake keyword (COMMAND / *_VARIABLE /
       OUTPUT_QUIET / …) is a fatal reject — use the ~command / ~commands /
       ~working_directory / ~output_variable / … labels. *)
    Some (ECmakeRawCmd { name = cmake_name_of_yelu name; args;
                         from_positional = Some "execute_process" })
  | "execute_process", _ ->
    (* Each cmake keyword is accepted as its `~label=` form (lowercased): a
       `~command=[…]` list flattens to repeated `command` kwargs; the rest are
       scalar. `~commands=[[…],[…]]` carries multiple command-lines. *)
    let kwarg_all key =
      List.filter_map kwargs ~f:(fun (k, v) -> Option.some_if (String.equal k key) v) in
    let kwarg_opt key = List.Assoc.find kwargs ~equal:String.equal key in
    let kwarg_mem key = List.Assoc.mem kwargs ~equal:String.equal key in
    let commands =
      match kwarg_all "commands" with
      | (_ :: _) as cmds ->
        List.map cmds ~f:(function EList items -> items | e -> [ e ])
      | [] -> (match kwarg_all "command" with [] -> [] | items -> [ items ])
    in
    let str_opt key = match kwarg_opt (String.lowercase key) with
      | Some (EString s | EVar s) -> Some s | _ -> None in
    let expr_opt key = kwarg_opt (String.lowercase key) in
    let has_flag key = kwarg_mem (String.lowercase key) in
    let timeout = Option.map (expr_opt "TIMEOUT") ~f:(fun e ->
      match e with EString s -> Float.of_string s | _ -> 0.0) in
    Some (ECmakeExecuteProcess
            { commands;
              working_directory = expr_opt "WORKING_DIRECTORY";
              timeout;
              result_variable = str_opt "RESULT_VARIABLE";
              output_variable = str_opt "OUTPUT_VARIABLE";
              error_variable  = str_opt "ERROR_VARIABLE";
              input_file = expr_opt "INPUT_FILE";
              output_file = expr_opt "OUTPUT_FILE";
              error_file  = expr_opt "ERROR_FILE";
              output_quiet = has_flag "OUTPUT_QUIET";
              error_quiet  = has_flag "ERROR_QUIET";
              output_strip_trailing_whitespace =
                has_flag "OUTPUT_STRIP_TRAILING_WHITESPACE";
              error_strip_trailing_whitespace =
                has_flag "ERROR_STRIP_TRAILING_WHITESPACE";
              command_error_is_fatal =
                str_opt "COMMAND_ERROR_IS_FATAL" })
  | "separate_arguments", [ cvar ] ->
    Some (ECmakeSeparateArguments
            { var = str_of cvar; mode = "PLAIN"; input = None })
  | "cmake_call", cmd :: rest_args ->
    Some (ECmakeLanguageCall { cmd = str_of cmd; args = rest_args })
  | "cmake_eval", [ code ] ->
    Some (ECmakeLanguageEval { code = str_of code })
  | "cmake_get_log_level", [] ->
    Some (ECmakeLanguageGetLogLevel { out })
  | "yc_raw", [ e ] ->
    let s = str_of e in
    Some (ECmakeRaw s)
  | _ -> None

let p_cmake_op_command_y1 toks =
  match toks with
  | IDENT name :: rest
      when (match name with
            | "cmake_minimum_required" | "project" | "message"
            | "math" | "include" | "include_guard" | "policy_set"
            | "enable_language" | "execute_process"
            | "separate_arguments"
            | "cmake_call" | "cmake_eval" | "cmake_get_log_level"
            | "yc_raw" -> true
            | _ -> false) ->
      let args, kwargs, rest = collect_command_args [] [] rest in
      p_cmake_op_command_y1_inner name args kwargs
      |> fallback_to_raw name args rest
    | _ -> None

(* Outer block: `( <stmt> ... )`. Mirrors [Lang_yelu_parse.p_block]
   semicolon-separated semantics and the single-stmt collapse. As
   Phase 2a families are migrated, the block accepts any family-
   recognized statement; non-recognized inputs make the parser fail
   (the legacy parser handles them via its full grammar). *)
(* ============================================================
   Condition parser — mirrors [Lang_yelu_parse.p_cond] / [p_cond_atom]
   structure. Builds yelu_cmake cond expressions (ENot, EAnd, EOr,
   EIntLess/Equal/etc., ECmakeStringEqual, ECmakeVarDefined,
   ECmakeTargetExists, ECmakeMatches, ECmakeInList, ECmakeIsDirectory,
   ECmakeIsAbsolute, ECmakeFileExists, ECmakePolicyCheck) directly.
   ============================================================ *)

let rec p_cond_atom_y1 toks =
  let bin op cont rest =
    match p_expr_y1 rest with
    | Some (a, rest) ->
      (match p_expr_y1 rest with
       | Some (b, rest) -> Some (op a b, rest)
       | None -> cont)
    | None -> cont
  in
  let _ = bin in
  match toks with
  | IDENT "not" :: rest ->
    (match p_cond_atom_y1 rest with
     | Some (c, rest) -> Some (ENot c, rest)
     | None -> None)
  | TARGET :: rest ->
    (match p_expr_y1 rest with
     | Some (e, rest) ->
       let target = match e with
         | ETarget _ | EString _ -> e
         | EVar name -> ETarget name
         | _ -> ETarget "?"
       in
       Some (ECmakeTargetExists target, rest)
     | None -> None)
  | IDENT "defined" :: rest ->
    (match p_expr_y1 rest with
     | Some (e, rest) ->
       let name = match e with
         | EVar s | EString s -> s
         | _ -> "?"
       in
       Some (ECmakeVarDefined name, rest)
     | None -> None)
  | IDENT "str_eq" :: rest ->
    (match p_expr_y1 rest with
     | Some (a, rest) ->
       (match p_expr_y1 rest with
        | Some (b, rest) -> Some (ECmakeStringEqual (a, b), rest)
        | None -> None)
     | None -> None)
  | IDENT "eq" :: rest ->
    (match p_expr_y1 rest with
     | Some (a, rest) ->
       (match p_expr_y1 rest with
        | Some (b, rest) -> Some (EIntEqual (a, b), rest)
        | None -> None)
     | None -> None)
  | IDENT "lt" :: rest ->
    (match p_expr_y1 rest with
     | Some (a, rest) ->
       (match p_expr_y1 rest with
        | Some (b, rest) -> Some (EIntLess (a, b), rest)
        | None -> None)
     | None -> None)
  | IDENT "gt" :: rest ->
    (match p_expr_y1 rest with
     | Some (a, rest) ->
       (match p_expr_y1 rest with
        | Some (b, rest) -> Some (EIntGreater (a, b), rest)
        | None -> None)
     | None -> None)
  | IDENT "ver_lt" :: rest ->
    (match p_expr_y1 rest with
     | Some (a, rest) ->
       (match p_expr_y1 rest with
        | Some (b, rest) -> Some (ECmakeVersionLess (a, b), rest)
        | None -> None)
     | None -> None)
  | IDENT "ver_gt" :: rest ->
    (match p_expr_y1 rest with
     | Some (a, rest) ->
       (match p_expr_y1 rest with
        | Some (b, rest) -> Some (ECmakeVersionGreater (a, b), rest)
        | None -> None)
     | None -> None)
  | IDENT "ver_eq" :: rest ->
    (match p_expr_y1 rest with
     | Some (a, rest) ->
       (match p_expr_y1 rest with
        | Some (b, rest) -> Some (ECmakeVersionEqual (a, b), rest)
        | None -> None)
     | None -> None)
  | IDENT "ver_ge" :: rest ->
    (match p_expr_y1 rest with
     | Some (a, rest) ->
       (match p_expr_y1 rest with
        | Some (b, rest) -> Some (ECmakeVersionGreaterEqual (a, b), rest)
        | None -> None)
     | None -> None)
  | IDENT "ver_le" :: rest ->
    (match p_expr_y1 rest with
     | Some (a, rest) ->
       (match p_expr_y1 rest with
        | Some (b, rest) -> Some (ECmakeVersionLessEqual (a, b), rest)
        | None -> None)
     | None -> None)
  | IDENT "match" :: rest ->
    (match p_expr_y1 rest with
     | Some (e, rest) ->
       (match rest with
        | STRING s :: rest' -> Some (ECmakeMatches { expr_ = e; regex = s }, rest')
        | PATH s :: rest' -> Some (ECmakeMatches { expr_ = e; regex = s }, rest')
        | _ -> None)
     | None -> None)
  | IDENT "list_in" :: rest ->
    (match p_expr_y1 rest with
     | Some (item, rest) ->
       (match p_expr_y1 rest with
        | Some (list_, rest) ->
          Some (ECmakeInList { item; list_ }, rest)
        | None -> None)
     | None -> None)
  | IDENT "exists" :: rest ->
    (match p_expr_y1 rest with
     | Some (e, rest) -> Some (ECmakeFileExists e, rest)
     | None -> None)
  | IDENT "is_dir" :: rest ->
    (match p_expr_y1 rest with
     | Some (e, rest) -> Some (ECmakeIsDirectory e, rest)
     | None -> None)
  | IDENT "is_abs" :: rest ->
    (match p_expr_y1 rest with
     | Some (e, rest) -> Some (ECmakeIsAbsolute e, rest)
     | None -> None)
  | IDENT "policy" :: rest ->
    (match rest with
     | IDENT id :: rest' -> Some (ECmakePolicyCheck id, rest')
     | _ -> None)
	| LPAREN :: rest ->
	  (* Parenthesized condition: (cond and cond or ...).
	     p_expr_y1 also handles LPAREN for simple (expr), but cannot
	     handle and/or; this arm catches compound conditions. *)
	  (match p_cond_y1 rest with
	   | Some (c, RPAREN :: rest') -> Some (c, rest')
	   | _ -> None)
  | _ ->
    (* Bare expression = truthy *)
    p_expr_y1 toks

(* Top-level cond: left-associative AND / OR over cond_atoms. *)
and p_cond_y1 toks =
  match p_cond_atom_y1 toks with
  | None -> None
  | Some (c1, rest) ->
    let rec loop acc = function
      | IDENT "and" :: r ->
        (match p_cond_atom_y1 r with
         | Some (c, r') -> loop (EAnd (acc, c)) r'
         | None -> Some (acc, IDENT "and" :: r))
      | IDENT "or" :: r ->
        (match p_cond_atom_y1 r with
         | Some (c, r') -> loop (EOr (acc, c)) r'
         | None -> Some (acc, IDENT "or" :: r))
      | r -> Some (acc, r)
    in
    loop c1 rest

(* ============================================================
   Statement dispatcher with mutually-recursive control flow.

   Order matters: keyword-prefixed dispatchers (let / if / fun /
   macro / while / foreach + break/continue/return) come first;
   then family command dispatchers; then var assign; then bare
   block; then apply (catches any IDENT-headed `( ... )` call).
   ============================================================ *)

let rec p_stmt_inner_y1 toks =
  match p_let_y1 toks with Some r -> Some r | None ->
  match p_if_y1 toks with Some r -> Some r | None ->
  match p_function_y1 toks with Some r -> Some r | None ->
  match p_macro_y1 toks with Some r -> Some r | None ->
  match p_while_y1 toks with Some r -> Some r | None ->
  match p_foreach_y1 toks with Some r -> Some r | None ->
  match p_flow_y1 toks with Some r -> Some r | None ->
  match p_string_command_y1 toks with Some r -> Some r | None ->
  match p_list_command_y1 toks with Some r -> Some r | None ->
  match p_path_command_y1 toks with Some r -> Some r | None ->
  match p_file_command_y1 toks with Some r -> Some r | None ->
  match p_target_command_y1 toks with Some r -> Some r | None ->
  match p_dir_command_y1 toks with Some r -> Some r | None ->
  match p_test_command_y1 toks with Some r -> Some r | None ->
  match p_property_command_y1 toks with Some r -> Some r | None ->
  match p_find_command_y1 toks with Some r -> Some r | None ->
  match p_install_command_y1 toks with Some r -> Some r | None ->
  match p_try_command_y1 toks with Some r -> Some r | None ->
  match p_cmake_op_command_y1 toks with Some r -> Some r | None ->
  match p_var_stmt_y1 toks with Some r -> Some r | None ->
  match p_apply_y1 toks with Some r -> Some r | None ->
  match p_generic_command_y1 toks with Some r -> Some r | None ->
  p_block_y1 toks

(* `let var [: type] = expr in stmt` — yelu_cmake ELet is expression-shaped,
   matching the syntax directly (no rest-of-list awkwardness like the
   legacy sequence-shaped Ylet). *)
and p_let_y1 toks =
  match kw "let" toks with
  | None -> None
  | Some ((), toks) ->
    match toks with
    | IDENT name :: toks ->
      (* skip optional `:type` annotation *)
      let toks = match toks with
        | COLON :: IDENT _ :: r -> r
        | COLON :: TARGET :: r -> r
        | COLON :: CVAR :: r -> r
        | _ -> toks
      in
      (match eq_tok toks with
       | None -> None
       | Some ((), toks) ->
         match p_expr_y1 toks with
         | None -> None
         | Some (value, toks) ->
           match kw "in" toks with
           | None -> None
           | Some ((), toks) ->
             match p_stmt_inner_y1 toks with
             | Some (body, rest) ->
               Some (ELet { var = name; value; body }, rest)
             | None -> None)
    | _ -> None

(* `if cond then ( body ) [else ( body ) | else if ...]` *)
and p_if_y1 toks =
  match kw "if" toks with
  | None -> None
  | Some ((), toks) ->
    match p_cond_y1 toks with
    | None -> None
    | Some (cond, toks) ->
      match kw "then" toks with
      | None -> None
      | Some ((), toks) ->
        match p_block_y1 toks with
        | None -> None
        | Some (then_, toks) ->
          let else_opt =
            match kw "else" toks with
            | None -> None
            | Some ((), r) ->
              (match p_block_y1 r with
               | Some (e, r') -> Some (Some e, r')
               | None ->
                 (match p_if_y1 r with
                  | Some (e, r') -> Some (Some e, r')
                  | None -> None))
          in
          (match else_opt with
           | Some (else_, rest) ->
             Some (Yelu_cmake_if.ECmakeIfStmt { cond; then_; else_ }, rest)
           | None ->
             Some (Yelu_cmake_if.ECmakeIfStmt
                     { cond; then_; else_ = None }, toks))

(* `fun name(args) ( body )` / `function name(args) ( body )` *)
and p_function_y1 toks =
  match kw "function" toks with
  | None -> None
  | Some ((), toks) ->
    match toks with
    | IDENT name :: toks ->
      let args, toks =
        match toks with
        | LPAREN :: r ->
          let rec loop acc = function
            | RPAREN :: r' -> (List.rev acc, r')
            | COMMA :: r' -> loop acc r'
            | (IDENT a :: r') -> loop (a :: acc) r'
            | toks' -> (List.rev acc, toks')
          in
          loop [] r
        | _ -> ([], toks)
      in
      (match p_block_y1 toks with
       | Some (body, rest) ->
         Some (ECmakeFunction { name = EString name; params = args; body }, rest)
       | None -> None)
    | _ -> None

(* `macro name(args) ( body )` *)
and p_macro_y1 toks =
  match kw "macro" toks with
  | None -> None
  | Some ((), toks) ->
    match toks with
    | IDENT name :: toks ->
      let args, toks =
        match toks with
        | LPAREN :: r ->
          let rec loop acc = function
            | RPAREN :: r' -> (List.rev acc, r')
            | COMMA :: r' -> loop acc r'
            | (IDENT a :: r') -> loop (a :: acc) r'
            | toks' -> (List.rev acc, toks')
          in
          loop [] r
        | _ -> ([], toks)
      in
      (match p_block_y1 toks with
       | Some (body, rest) ->
         Some (ECmakeMacro { name = EString name; params = args; body }, rest)
       | None -> None)
    | _ -> None

(* `while cond ( body )` *)
and p_while_y1 toks =
  match kw "while" toks with
  | None -> None
  | Some ((), toks) ->
    match p_cond_y1 toks with
    | None -> None
    | Some (cond, toks) ->
      match p_block_y1 toks with
      | Some (body, rest) -> Some (ECmakeWhile { cond; body }, rest)
      | None -> None

(* `foreach var in items ( body )` plus
   `foreach var in RANGE n..m ( body )` and
   `foreach var in [ items ] ( body )`. The bare-list form uses LBRACK.
   For symmetry with the legacy parser, we also try the IN ZIP_LISTS
   shape (loop_vars × list_vars) — though it's less common. *)
and p_foreach_y1 toks =
  match kw "foreach" toks with
  | None -> None
  | Some ((), toks) ->
    match toks with
    | IDENT lv :: toks ->
      (match kw "in" toks with
       | None -> None
       | Some ((), toks) ->
         (* RANGE first *)
         match kw "RANGE" toks with
         | Some ((), r) ->
           (match r with
            | INT start :: r ->
              (match dotdot r with
               | None -> None
               | Some ((), r) ->
                 (match r with
                  | INT stop :: r ->
                    (match p_block_y1 r with
                     | Some (body, r') ->
                       Some (ECmakeForeachRange
                               { loop_var = lv;
                                 start = Some start;
                                 stop;
                                 step = None;
                                 body }, r')
                     | None -> None)
                  | _ -> None))
            | _ -> None)
         | None ->
           (* IN LISTS <ident>+ — iterate over the contents of one or
              more list variables. Surface form mirrors cmake's
              `foreach(v IN LISTS A B)`. Emits ECmakeForeachInList. *)
           match kw "LISTS" toks with
           | Some ((), r) ->
             let rec idents acc = function
               | IDENT id :: rest -> idents (id :: acc) rest
               | toks' -> (List.rev acc, toks')
             in
             let lists, r = idents [] r in
             if List.is_empty lists then None
             else
               (match p_block_y1 r with
                | Some (body, r') ->
                  Some (ECmakeForeachInList
                          { loop_var = lv; lists; items = []; body }, r')
                | None -> None)
           | None ->
           (* [ items ] bracketed list *)
           match toks with
           | LBRACK :: r ->
             let rec items_loop acc = function
               | RBRACK :: r' -> (List.rev acc, r')
               | SEMI :: r' -> items_loop acc r'
               | toks' ->
                 (match p_expr_y1 toks' with
                  | Some (e, r') -> items_loop (e :: acc) r'
                  | None -> (List.rev acc, toks'))
             in
             let items, r = items_loop [] r in
             (match p_block_y1 r with
              | Some (body, r') ->
                Some (ECmakeForeach
                        { loop_var = lv; items; body }, r')
              | None -> None)
           | _ -> None)
    | _ -> None

(* Generic command: any IDENT-headed call not matched by a family parser.
   Wraps in ECmakeApply so unknown cmake commands round-trip through the IR. *)
and p_generic_command_y1 toks =
  match toks with
  | IDENT name :: rest ->
    let args, _kwargs, rest = collect_command_args [] [] rest in
    if Yc_primitives.is_known_command name then
      Some (ECmakeRawCmd { name = cmake_name_of_yelu name; args; from_positional = None }, rest)
    else
      Some (ECmakeApply { name = EString name; args }, rest)
  | _ -> None

(* Bare flow keywords: break / continue / return. *)
and p_flow_y1 toks =
  match toks with
  | BREAK :: rest -> Some (ECmakeBreak, rest)
  | CONTINUE :: rest -> Some (ECmakeContinue, rest)
  | RETURN :: rest -> Some (ECmakeReturn { propagate_vars = [] }, rest)
  | _ -> None

(* Bare function application: `IDENT( args )` — only matches if the
   IDENT is not a known reserved command name (since those go to
   their specific dispatchers first via p_stmt_inner_y1). Has to come
   AFTER all the family dispatchers to avoid hijacking. *)
and p_apply_y1 toks =
  match toks with
  | LPAREN :: IDENT name :: LPAREN :: rest ->
    (* Form: `( name(args) )` *)
    let rec collect acc = function
      | RPAREN :: r -> Some (List.rev acc, r)
      | COMMA :: r -> collect acc r
      | toks' ->
        (match p_expr_y1 toks' with
         | Some (e, r) -> collect (e :: acc) r
         | None -> None)
    in
    (match collect [] rest with
     | Some (args, rest) ->
       (match rparen rest with
        | Some ((), rest) ->
          Some (ECmakeApply { name = EString name; args }, rest)
        | None -> None)
     | None -> None)
  | _ -> None

(* Block: `( stmt; stmt; ... )` — accepts any covered family. *)
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

(* Populate forward refs declared near p_assign_y1 — needed for the
   `var := cmd args ~kw=v` command-call sugar to reach the family
   `_inner` parsers that live further down in the file. *)
let () =
  collect_command_args_fwd := collect_command_args;
  fallback_to_raw_fwd := fallback_to_raw;
  dispatch_command_fwd := fun cmd args kwargs ->
    if String.is_prefix cmd ~prefix:"string_" then
      p_string_command_y1_inner cmd args kwargs
    else if String.is_prefix cmd ~prefix:"list_" then
      p_list_command_y1_inner cmd args kwargs
    else if String.is_prefix cmd ~prefix:"path_"
         || String.equal cmd "get_filename_component" then
      p_path_command_y1_inner cmd args kwargs
    else if String.is_prefix cmd ~prefix:"file_"
         || String.equal cmd "configure_file" then
      p_file_command_y1_inner cmd args kwargs
    else
      (* Some inners (notably target/dir/cmake_op) have a catch-all returning
         ECmakeRawCmd for any unknown command. That makes the family `_inner`
         always succeed when called out-of-family, which would shadow the
         genuine handler for other families. Strip such "fallback" Somes so
         the real handler downstream gets a chance. *)
      let drop_raw = function
        | Some (Yelu_cmake.ECmakeRawCmd _) -> None
        | other -> other
      in
      let tries = [
        (fun () -> drop_raw (p_target_command_y1_inner cmd args kwargs));
        (fun () -> drop_raw (p_dir_command_y1_inner cmd args kwargs));
        (fun () -> drop_raw (p_test_command_y1_inner cmd args kwargs));
        (fun () -> drop_raw (p_property_command_y1_inner cmd args kwargs));
        (fun () -> drop_raw (p_find_command_y1_inner cmd args kwargs));
        (fun () -> drop_raw (p_install_command_y1_inner cmd args kwargs));
        (fun () -> drop_raw (p_try_command_y1_inner cmd args kwargs));
        (fun () -> drop_raw (p_cmake_op_command_y1_inner cmd args kwargs));
      ] in
      List.find_map tries ~f:(fun f -> f ())

(* ============================================================
   Entry points
   ============================================================ *)

let parse_tokens_y1 toks =
  (* Collect multiple top-level statements separated by semicolons.
     A single statement (including a block) is returned as-is;
     multiple statements are wrapped in ESeq. *)
  let rec collect acc = function
    | [] -> Ok (match List.rev acc with [ s ] -> s | ss -> ESeq ss)
    | toks ->
      match p_stmt_y1 toks with
      | None ->
        if List.is_empty acc
        then Error "parse error (unsupported yelu_cmake direct-parser syntax)"
        else begin
          let ctx = match toks with
            | [] -> ""
            | t :: _ -> " at " ^ Sexp.to_string ([%sexp_of: token] t)
          in
          Error ("unexpected trailing tokens" ^ ctx)
        end
      | Some (s, rest) ->
        let rest = match rest with SEMI :: r -> r | _ -> rest in
        collect (s :: acc) rest
  in
  collect [] toks

let parse_program_y1 input =
  match Angstrom.parse_string ~consume:All token_list input with
  | Ok toks -> parse_tokens_y1 toks
  | Error e -> Error ("lex error: " ^ e)
