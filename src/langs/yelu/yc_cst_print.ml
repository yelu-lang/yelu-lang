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
    Buffer.add_char b '~'; Buffer.add_string b k; Buffer.add_char b '='; pr_atom b v
  | Kw_flag k -> Buffer.add_char b '~'; Buffer.add_string b k
  | Kw_list (k, items) ->
    Buffer.add_char b '~'; Buffer.add_string b k; Buffer.add_string b "=[ ";
    List.iter items ~f:(fun a -> pr_atom b a; Buffer.add_char b ' ');
    Buffer.add_char b ']'

(* Per-command bare-keyword flags that canonicalize to the lowercase `~flag`
   form (critique #2, the `~`-half). Command-aware on purpose: a bare `GLOBAL`
   is the `include_guard` flag here, but `${GLOBAL}` (a variable) elsewhere is
   left alone — only a *positional bare name* matching THIS command's flag set
   is rewritten. The list grows one command at a time; the parser already
   accepts the `~flag` form (it arrives as a Kw_flag → boolean kwarg). *)
let command_flags name =
  match name with
  | "include_guard" -> [ "GLOBAL" ]
  | "install_directory" -> [ "OPTIONAL" ]
  | "find_package" -> [ "REQUIRED" ]
  | "set_property" -> [ "APPEND"; "APPEND_STRING" ]
  | "execute_process" ->
    [ "OUTPUT_QUIET"; "ERROR_QUIET";
      "OUTPUT_STRIP_TRAILING_WHITESPACE"; "ERROR_STRIP_TRAILING_WHITESPACE" ]
  | _ -> []

(* Per-command value-carrying keywords that canonicalize to `~label=value`
   (critique #2 value-labels). Each entry maps the cmake keyword → the yc
   label. The keyword consumes the following positional as its value; the
   parser accepts the `~label=` kwarg form. Command-aware, grows per command. *)
let command_value_labels name =
  match name with
  | "install_directory" -> [ ("DESTINATION", "destination"); ("COMPONENT", "component") ]
  | "install_files" -> [ ("DESTINATION", "destination"); ("COMPONENT", "component") ]
  | "install_export" ->
    [ ("DESTINATION", "destination"); ("FILE", "file");
      ("NAMESPACE", "namespace"); ("COMPONENT", "component") ]
  (* get_property's PROPERTY is a single name (shape-1 — unlike set_property
     which is shape-3 (name, multi-values) and uses command_value_list_labels).
     The optional trailing mode flag (`SET`/`DEFINED`/...) stays as a positional
     enum constructor for now — future micro-slice: surface as `~mode=Defined`
     via a per-command "flag-as-kwarg-enum" rewriter. *)
  | "get_property" -> [ ("PROPERTY", "property") ]
  | "execute_process" ->
    [ ("WORKING_DIRECTORY", "working_directory"); ("TIMEOUT", "timeout");
      ("RESULT_VARIABLE", "result_variable"); ("OUTPUT_VARIABLE", "output_variable");
      ("ERROR_VARIABLE", "error_variable"); ("INPUT_FILE", "input_file");
      ("OUTPUT_FILE", "output_file"); ("ERROR_FILE", "error_file");
      ("COMMAND_ERROR_IS_FATAL", "command_error_is_fatal") ]
  | _ -> []

(* Per-command value-LIST-carrying keywords that canonicalize to
   `~label=[key, vals...]` (list-kwarg form). Used for cmake constructs where a
   keyword introduces a (key, multi-value) pair — set_property's
   `PROPERTY <name> <values...>` is the canonical case. The printer consumes
   the keyword plus the remaining trailing positionals into one Kw_list;
   the parser recovers them via List.Assoc.find_all on the kwargs.
   Future-compatible with the shape-3 record-literal landing — until then,
   the leading list element plays the "key" role. *)
let command_value_list_labels name =
  match name with
  | "set_property" -> [ ("PROPERTY", "property") ]
  | "execute_process" -> [ ("COMMAND", "command") ]
  | _ -> []

(* install_targets is nested (critique #2 shape 4): `<targets> [top-opts]
   [<KIND> DESTINATION <v>]* [trailing]`. DESTINATION is dual-role (top-level
   AND per-artifact), so the generic value-label table can't express it.
   Canonicalize each `<KIND> DESTINATION v` triple to the flat dotted label
   `~kind.destination=v`, and the top-level COMPONENT/EXPORT/DESTINATION to
   `~component=`/`~export=`/`~destination=`. The parser reads both the
   positional and dotted forms back to the same artifact_clauses (two-level
   split / dotted-kwarg in p_install_command_y1_inner), so emit is unchanged.
   Trailing positionals (the targets list, a `$INSTALL_FILE_SET` clause-var)
   print as-is. *)
let install_artifact_kinds =
  [ "LIBRARY"; "ARCHIVE"; "RUNTIME"; "OBJECTS"; "FRAMEWORK"; "BUNDLE";
    "PUBLIC_HEADER"; "PRIVATE_HEADER"; "RESOURCE"; "FILE_SET"; "CXX_MODULES_BMI" ]

let install_top_kw = [ "COMPONENT"; "EXPORT"; "DESTINATION" ]

(* Emit-safety guard. Canonicalizing to dotted labels is only emit-invariant
   when every positional is either a leading target or a clause/label value —
   i.e. nothing stray is left after the keyword region. A trailing dynamic
   clause-var (`$INSTALL_FILE_SET`, a FILE_SET clause held in a variable) is a
   positional AFTER the clauses; the positional parse absorbs/drops it while
   the dotted parse would read it as another target, so the two forms would
   emit differently. The dotted (kwarg) surface structurally can't carry a
   post-clause positional — so when one is present, leave the line positional
   (a future `~raw=`/FILE_SET-clause escape is the way to lift it). *)
let install_targets_emit_safe (args : Cst.arg list) =
  let is_art s = List.mem install_artifact_kinds s ~equal:String.equal in
  let is_top s = List.mem install_top_kw s ~equal:String.equal in
  let rec drop_targets = function
    | (Cst.Pos (A_name s | A_keyword s) :: _) as l when is_art s || is_top s -> l
    | Cst.Pos _ :: rest -> drop_targets rest
    | l -> l
  in
  let rec consume = function
    | [] -> true
    | Cst.Pos (A_name kw | A_keyword kw)
      :: Cst.Pos (A_name "DESTINATION" | A_keyword "DESTINATION")
      :: Cst.Pos _ :: rest when is_art kw -> consume rest
    | Cst.Pos (A_name kw | A_keyword kw) :: Cst.Pos _ :: rest when is_top kw -> consume rest
    | _ -> false
  in
  consume (drop_targets args)

let pr_install_targets_args b (args : Cst.arg list) =
  if not (install_targets_emit_safe args) then
    (* not safely representable as dotted labels — print positional as-is *)
    List.iter args ~f:(fun a -> Buffer.add_char b ' '; pr_arg b a)
  else
  let is_art s = List.mem install_artifact_kinds s ~equal:String.equal in
  let top_label = function
    | "COMPONENT" -> Some "component" | "EXPORT" -> Some "export"
    | "DESTINATION" -> Some "destination" | _ -> None in
  let rec go = function
    | [] -> ()
    (* per-artifact clause: KIND DESTINATION value → ~kind.destination=value *)
    | Cst.Pos (A_name kw | A_keyword kw)
      :: Cst.Pos (A_name "DESTINATION" | A_keyword "DESTINATION")
      :: Cst.Pos v :: rest
      when is_art kw ->
      Buffer.add_string b " ~"; Buffer.add_string b (String.lowercase kw);
      Buffer.add_string b ".destination="; pr_atom b v; go rest
    (* top-level value-label: COMPONENT/EXPORT/DESTINATION value → ~label=value *)
    | Cst.Pos (A_name kw | A_keyword kw) :: Cst.Pos v :: rest
      when Option.is_some (top_label kw) ->
      Buffer.add_string b " ~"; Buffer.add_string b (Option.value_exn (top_label kw));
      Buffer.add_char b '='; pr_atom b v; go rest
    (* targets / trailing clause-var: print as-is *)
    | a :: rest -> Buffer.add_char b ' '; pr_arg b a; go rest
  in
  go args

(* Print a command's argument list, command-aware: a positional bare keyword
   in the command's flag set → `~flag`; a value-keyword → `~label=<next>`
   (consuming the following positional); everything else via [pr_arg]. Each
   emitted unit gets a leading space (matching the old pr_spaced behaviour). *)
let pr_cmd_args b name (args : Cst.arg list) =
  let is_command_kw (a : Cst.arg) = match a with
    | Cst.Pos (A_name "COMMAND" | A_keyword "COMMAND") -> true | _ -> false in
  if String.equal name "install_targets" then pr_install_targets_args b args
  (* execute_process with a piped multi-COMMAND can't canonicalize: the flat
     `~command=[…]` kwarg encoding loses the per-COMMAND grouping (the parser
     would merge them), so emit would change. Leave such a line positional. *)
  else if String.equal name "execute_process"
          && List.count args ~f:is_command_kw > 1 then
    List.iter args ~f:(fun a -> Buffer.add_char b ' '; pr_arg b a)
  else
  let flags = command_flags name in
  let vlabels = command_value_labels name in
  let vlists = command_value_list_labels name in
  let is_flag s = List.mem flags s ~equal:String.equal in
  let label_of s = List.Assoc.find vlabels s ~equal:String.equal in
  let list_label_of s = List.Assoc.find vlists s ~equal:String.equal in
  (* A value-list (`~command=[…]`) runs until the next non-positional OR the
     next positional that is itself a keyword of THIS command — so a list
     followed by another keyword (execute_process: `COMMAND … OUTPUT_VARIABLE`)
     terminates correctly, while a terminal list (set_property `PROPERTY …`)
     still consumes all its trailing values. *)
  let is_cmd_kw (a : Cst.atom) = match a with
    | A_name s | A_keyword s ->
      is_flag s || Option.is_some (label_of s) || Option.is_some (list_label_of s)
    | _ -> false
  in
  let rec take_positionals acc = function
    | (Cst.Pos a) :: rest when not (is_cmd_kw a) -> take_positionals (a :: acc) rest
    | rest -> (List.rev acc, rest)
  in
  let rec go = function
    | [] -> ()
    | Cst.Pos (A_name kw | A_keyword kw) :: rest when is_flag kw ->
      Buffer.add_string b " ~"; Buffer.add_string b (String.lowercase kw); go rest
    (* Value-list label: PROPERTY <name> <val>... → ~property=[name, val...].
       Consumes the keyword + all remaining positionals (until a kwarg or end). *)
    | Cst.Pos (A_name kw | A_keyword kw) :: rest
      when Option.is_some (list_label_of kw) ->
      let l = Option.value_exn (list_label_of kw) in
      let items, rest' = take_positionals [] rest in
      Buffer.add_string b " ~"; Buffer.add_string b l; Buffer.add_string b "=[ ";
      List.iter items ~f:(fun a -> pr_atom b a; Buffer.add_char b ' ');
      Buffer.add_char b ']';
      go rest'
    | Cst.Pos (A_name kw | A_keyword kw) :: (Cst.Pos _ as v) :: rest
      when Option.is_some (label_of kw) ->
      let l = Option.value_exn (label_of kw) in
      Buffer.add_string b " ~"; Buffer.add_string b l; Buffer.add_char b '=';
      (match v with Cst.Pos a -> pr_atom b a | _ -> ());
      go rest
    | a :: rest -> Buffer.add_char b ' '; pr_arg b a; go rest
  in
  go args

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
         Buffer.add_char b ' '; pr_target_first b first; pr_cmd_args b name rest
       | [] -> ())
    else pr_cmd_args b name args
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
      Buffer.add_string b " ~"; Buffer.add_string b k; Buffer.add_char b '='; pr_atom b v);
    if parent_scope then Buffer.add_string b " ~parent_scope"
  (* `var := cmd args...` — round-trips back to the source-text form. The
     trailing `~out=var` kwarg is not emitted (it's implicit in the := LHS). *)
  | S_assign_call { cache; name; cmd_name; cmd_args } ->
    if cache then Buffer.add_string b "cache ";
    pr_name_or b name ~otherwise:(fun () -> Buffer.add_string b name);
    Buffer.add_string b " := ";
    Buffer.add_string b cmd_name;
    pr_cmd_args b cmd_name cmd_args
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
