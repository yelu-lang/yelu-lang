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
open Yelu_surface_cmake_list
open Yelu_surface_cmake_path
open Yelu_surface_cmake_file
open Yelu_theory_target
open Yelu_surface_cmake_target
open Yelu_surface_cmake_dir
open Yelu_surface_cmake_test

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
  | TARGET :: IDENT name :: rest -> Some (ETarget name, rest)
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
    Some (ECmakeListAppend
            { list = cvar_name_of_y1 cvar; items = values })
  | "list_length", [ cvar ] ->
    Some (ECmakeListLength { list = cvar_name_of_y1 cvar; out })
  | "list_get", cvar :: indices when not (List.is_empty indices) ->
    Some (ECmakeListGet
            { list = cvar_name_of_y1 cvar;
              indices = List.map indices ~f:expr_to_int_y1;
              out })
  | "list_remove_item", cvar :: values ->
    Some (ECmakeListRemoveItem
            { list = cvar_name_of_y1 cvar; items = values })
  | "list_remove_duplicates", [ cvar ] ->
    Some (ECmakeListRemoveDuplicates { list = cvar_name_of_y1 cvar })
  | "list_reverse", [ cvar ] ->
    Some (ECmakeListReverse { list = cvar_name_of_y1 cvar })
  | "list_sort", [ cvar ] ->
    Some (ECmakeListSort
            { list = cvar_name_of_y1 cvar;
              order = None; compare = None; case = None })
  | "list_join", [ cvar; glue ] ->
    Some (ECmakeListJoin
            { list = cvar_name_of_y1 cvar; glue; out })
  | "list_find", [ cvar; value ] ->
    Some (ECmakeListFind
            { list = cvar_name_of_y1 cvar; value; out })
  | "list_prepend", cvar :: values ->
    Some (ECmakeListPrepend
            { list = cvar_name_of_y1 cvar; items = values })
  | "list_insert", cvar :: _ ->
    (* Legacy parser defaults index/values; preserve to match. *)
    Some (ECmakeListInsert
            { list = cvar_name_of_y1 cvar; index = 0; items = [] })
  | "list_remove_at", cvar :: _ ->
    (* Legacy parser drops the indices; preserve to match. *)
    Some (ECmakeListRemoveAt
            { list = cvar_name_of_y1 cvar; indices = [] })
  | "list_pop_back", [ cvar ] ->
    Some (ECmakeListPopBack
            { list = cvar_name_of_y1 cvar; out_vars = [] })
  | "list_pop_front", [ cvar ] ->
    Some (ECmakeListPopFront
            { list = cvar_name_of_y1 cvar; out_vars = [] })
  | "list_sublist", [ cvar; b; l ] ->
    Some (ECmakeListSublist
            { list = cvar_name_of_y1 cvar;
              begin_ = expr_to_int_y1 b;
              length = expr_to_int_y1 l;
              out })
  | "list_filter", [ cvar; regex ] ->
    let regex_s = match regex with EString s | EVar s -> s | _ -> "" in
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
  match lparen toks with
  | None -> None
  | Some ((), toks) ->
    match toks with
    | IDENT name :: rest when String.is_prefix name ~prefix:"list_" ->
      let args, kwargs, rest = collect_command_args [] [] rest in
      (match p_list_command_y1_inner name args kwargs with
       | None -> None
       | Some e ->
         (match rparen rest with
          | Some ((), rest) -> Some (e, rest)
          | None -> None))
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
  match lparen toks with
  | None -> None
  | Some ((), toks) ->
    match toks with
    | IDENT name :: rest
      when String.is_prefix name ~prefix:"path_"
        || String.equal name "get_filename_component" ->
      let args, kwargs, rest = collect_command_args [] [] rest in
      (match p_path_command_y1_inner name args kwargs with
       | None -> None
       | Some e ->
         (match rparen rest with
          | Some ((), rest) -> Some (e, rest)
          | None -> None))
    | _ -> None

(* ============================================================
   File family — file_*, configure_file. cvar args become out strings;
   file/path args stay as expressions.
   ============================================================ *)

let p_file_command_y1_inner name args kwargs =
  let out = out_var_y1 kwargs in
  match name, args with
  | "configure_file", [ input; output ] ->
    Some (ECmakeConfigureFile { input; output })
  | "file_read", [ file ] ->
    Some (ECmakeFileReadFull
            { path = file; out; offset = None; limit = None; hex = false })
  | "file_write", file :: content ->
    Some (ECmakeFileWrite { path = file; content })
  | "file_glob", patterns ->
    Some (ECmakeFileGlob
            { out; recurse = false; relative = None;
              configure_depends = false; patterns })
  | "file_copy", [ input; output ] ->
    Some (ECmakeFileCopy
            { input; output; result = None; only_if_different = false })
  | "file_rename", [ old_; new_ ] ->
    Some (ECmakeFileRename { old_; new_; result = None; no_replace = false })
  | "file_remove", files ->
    Some (ECmakeFileRemove { files; recurse = false })
  | "file_real_path", [ path ] ->
    Some (ECmakeFileRealPath
            { out; path; base_dir = None; expand_tilde = false })
  | "file_size", [ file ] ->
    Some (ECmakeFileSize { out; path = file })
  | "file_timestamp", [ file ] ->
    Some (ECmakeFileTimestamp
            { out; path = file; format = None; utc = false })
  | "file_make_directory", [ dir ] ->
    Some (ECmakeFileMakeDirectory { dirs = [ dir ] })
  | "file_touch", files ->
    Some (ECmakeFileTouch { files; nocreate = false })
  | "file_strings", [ file ] ->
    Some (ECmakeFileStrings
            { out; path = file; regex = None; encoding = None;
              limit_count = None })
  | "file_read_symlink", [ link ] ->
    Some (ECmakeFileReadSymlink { out; link })
  | _ -> None

let p_file_command_y1 toks =
  match lparen toks with
  | None -> None
  | Some ((), toks) ->
    match toks with
    | IDENT name :: rest
      when String.is_prefix name ~prefix:"file_"
        || String.equal name "configure_file" ->
      let args, kwargs, rest = collect_command_args [] [] rest in
      (match p_file_command_y1_inner name args kwargs with
       | None -> None
       | Some e ->
         (match rparen rest with
          | Some ((), rest) -> Some (e, rest)
          | None -> None))
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

(* Detect a visibility-keyword expr; matches both bare-IDENT forms
   (EVar "PUBLIC") and string-quoted forms (EString "PUBLIC"). *)
let visibility_of_expr_y1 = function
  | EVar "PUBLIC" | EString "PUBLIC" -> Some "PUBLIC"
  | EVar "PRIVATE" | EString "PRIVATE" -> Some "PRIVATE"
  | EVar "INTERFACE" | EString "INTERFACE" -> Some "INTERFACE"
  | _ -> None

(* Group a flat positional-arg list into [(visibility, items)] runs.
   Default visibility is "PRIVATE" (matches the bridge's
   [visibility_of_kind] mapping for `Plain` — see
   yelu_cmake_to_yelu1.ml's `visibility_of_kind` helper). *)
let group_by_visibility_y1 items : (string * expr list) list =
  let rec loop current_kind current_items groups = function
    | [] ->
      List.rev ((current_kind, List.rev current_items) :: groups)
    | item :: rest ->
      match visibility_of_expr_y1 item with
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
  loop "PRIVATE" [] [] items

(* Wrap multi-group target commands in ESeq when there's more than
   one visibility group; single-group case returns the single ctor.
   Empty-group input still produces a single PLAIN group with empty
   items (matches the bridge's invariant). *)
let target_groups_to_y1 (ctor : visibility:string -> expr list -> expr) items =
  let groups = group_by_visibility_y1 items in
  match List.map groups ~f:(fun (vis, its) -> ctor ~visibility:vis its) with
  | [ s ] -> s
  | ss -> ESeq ss

let p_target_command_y1_inner name args _kwargs =
  match name, args with
  | "add_exe", name_arg :: sources ->
    Some (ECmakeAddExecutable { name = name_arg; sources })
  | "add_lib", name_arg :: sources ->
    Some (ECmakeAddLibrary
            { name = name_arg; type_ = None; sources })
  | "link_lib", target :: items ->
    Some (target_groups_to_y1
            (fun ~visibility items ->
              ECmakeTargetLinkLibraries { target; visibility; items })
            items)
  | "include_dirs", target :: items ->
    Some (target_groups_to_y1
            (fun ~visibility items ->
              ECmakeTargetIncludeDirectories
                { target; visibility; before = false; system = false;
                  dirs = items })
            items)
  | "compile_defs", target :: items ->
    Some (target_groups_to_y1
            (fun ~visibility items ->
              ECmakeTargetCompileDefinitions
                { target; visibility; definitions = items })
            items)
  | "compile_opts", target :: items ->
    Some (target_groups_to_y1
            (fun ~visibility items ->
              ECmakeTargetCompileOptions
                { target; visibility; before = false; options_ = items })
            items)
  | "link_opts", target :: items ->
    Some (target_groups_to_y1
            (fun ~visibility items ->
              ECmakeTargetLinkOptions
                { target; visibility; before = false; options_ = items })
            items)
  | "link_dirs", target :: items ->
    Some (target_groups_to_y1
            (fun ~visibility items ->
              ECmakeTargetLinkDirectories
                { target; visibility; before = false; dirs = items })
            items)
  | "target_sources", target :: items ->
    Some (target_groups_to_y1
            (fun ~visibility items ->
              ECmakeTargetSources { target; visibility; sources = items })
            items)
  | "compile_feats", [ target ] ->
    (* Legacy parses with empty features list, which the bridge wraps in
       a single Plain-visibility group. *)
    Some (ECmakeTargetCompileFeatures
            { target; visibility = "PRIVATE"; features = [] })
  | _ -> None

let p_target_command_y1 toks =
  match lparen toks with
  | None -> None
  | Some ((), toks) ->
    match toks with
    | IDENT name :: rest
      when (match name with
            | "add_exe" | "add_lib" | "link_lib" | "include_dirs"
            | "compile_defs" | "compile_opts" | "compile_feats"
            | "link_opts" | "link_dirs" | "target_sources" -> true
            | _ -> false) ->
      let args, kwargs, rest = collect_command_args [] [] rest in
      (match p_target_command_y1_inner name args kwargs with
       | None -> None
       | Some e ->
         (match rparen rest with
          | Some ((), rest) -> Some (e, rest)
          | None -> None))
    | _ -> None

(* ============================================================
   Dir family — add_subdirectory, include_directories,
   add_compile_definitions, add_compile_options, add_link_options,
   add_definitions, link_directories.
   ============================================================ *)

let p_dir_command_y1_inner name args _kwargs =
  match name, args with
  | "add_subdirectory", [ dir ] ->
    Some (ECmakeAddSubdirectory dir)
  | "include_directories", dirs ->
    Some (ECmakeIncludeDirectories { dirs; before = false; system = false })
  | "add_compile_definitions", defs ->
    Some (ECmakeAddCompileDefinitions defs)
  | "add_compile_options", opts ->
    Some (ECmakeAddCompileOptions opts)
  | "add_link_options", opts ->
    Some (ECmakeAddLinkOptions opts)
  | "add_definitions", defs ->
    Some (ECmakeAddDefinitions defs)
  | "link_directories", dirs ->
    Some (ECmakeLinkDirectories { dirs; before = false })
  | _ -> None

let p_dir_command_y1 toks =
  match lparen toks with
  | None -> None
  | Some ((), toks) ->
    match toks with
    | IDENT name :: rest
      when (match name with
            | "add_subdirectory" | "include_directories"
            | "add_compile_definitions" | "add_compile_options"
            | "add_link_options" | "add_definitions"
            | "link_directories" -> true
            | _ -> false) ->
      let args, kwargs, rest = collect_command_args [] [] rest in
      (match p_dir_command_y1_inner name args kwargs with
       | None -> None
       | Some e ->
         (match rparen rest with
          | Some ((), rest) -> Some (e, rest)
          | None -> None))
    | _ -> None

(* ============================================================
   Test family — enable_testing, add_test.
   ============================================================ *)

let p_test_command_y1_inner name args _kwargs =
  match name, args with
  | "enable_testing", [] -> Some ECmakeEnableTesting
  | "add_test", name_arg :: command :: rest ->
    Some (ECmakeAddTest { name = name_arg; command; args = rest })
  | _ -> None

let p_test_command_y1 toks =
  match lparen toks with
  | None -> None
  | Some ((), toks) ->
    match toks with
    | IDENT name :: rest
      when String.equal name "enable_testing"
        || String.equal name "add_test" ->
      let args, kwargs, rest = collect_command_args [] [] rest in
      (match p_test_command_y1_inner name args kwargs with
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
  match p_list_command_y1 toks with Some r -> Some r | None ->
  match p_path_command_y1 toks with Some r -> Some r | None ->
  match p_file_command_y1 toks with Some r -> Some r | None ->
  match p_target_command_y1 toks with Some r -> Some r | None ->
  match p_dir_command_y1 toks with Some r -> Some r | None ->
  match p_test_command_y1 toks with Some r -> Some r | None ->
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
