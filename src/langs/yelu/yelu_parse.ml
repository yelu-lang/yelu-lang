(* Per-command argument interpretation for yc — the `_inner` library.

   **This file is no longer a parser.** Tier (b) (2026-07-16) retired the
   token-level grammar: the production path is
   `Yc_cst_parse.parse` → `Yc_cst_lower.lower_program` → `Yelu_cmake.expr`
   (`Yc_driver.parse_yc`). What survives here is the piece that path calls —
   the per-family `_inner` functions, which take an *already-parsed*
   `(positional expr list, kwarg alist)` and build the typed IR node for one
   cmake command family.

   So the contract of every export is:

     p_<family>_command_y1_inner :
       string -> expr list -> (string * expr) list -> expr option
       (command name)  (positionals)  (~kwargs)        (None = raw fallback)

   [Yc_cst_lower.lower_command] dispatches to these by name; they are the
   single source of truth for "what does this cmake command mean", shared by
   compile / fmt / LSP / the corpus gate. The `_y1` suffix is historical (Y1
   was the early-production label) and is retained only to avoid a churn-only
   rename across the dispatch table.

   Covered families: string, list, path, file, target, dir, test, property,
   find, install, try, cmake_op — plus the shared helpers they need
   ([split_by_keywords], [out_var_y1], [p_cmake_entity], [str_of],
   [target_groups_to_y1], …). Test coverage: [test_yelu_cmake_parse.ml]
   (280 per-command cases, run through the production CST path).

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
open Yelu_cmake
open Yelu_cmake_string
open Yelu_cmake_list
open Yelu_cmake_path
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

let rec str_of ?(default = "?") = function
  | ETarget s | EVar s | EString s -> s
  (* A first-class `${...}` reconstructs to its cmake text in a *name/keyword*
     slot (cache type, target name, property, …) — the same text the old
     EString "${X}" carried, so interpreters that read these slots are
     unaffected. *)
  | EVarLookup e -> "${" ^ str_of ~default e ^ "}"
  | _ -> default


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
      | EVar s -> List.mem ct_kw s ~equal:String.equal
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
      | EVar s -> List.mem cc_kw s ~equal:String.equal
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

(* ============================================================
   Test family — enable_testing, add_test.
   ============================================================ *)

let p_test_command_y1_inner name args kwargs =
  match name, args with
  | "enable_testing", [] -> Some yc_enable_testing
  | "add_test", args
    when List.exists args ~f:(function
           | EVar ("NAME" | "COMMAND" | "CONFIGURATIONS" | "WORKING_DIRECTORY"
                  | "COMMAND_EXPAND_LISTS") -> true
           | _ -> false) ->
    (* Labeled-only (Step 2 rollout, audit #3): the positional NAME/COMMAND
       form is a fatal reject — use ~name= + ~command=[cmd, args…]. The old
       section split silently DROPPED extra NAME-section positionals (the
       corpus lost `-C ${CMAKE_BUILD_TYPE}` this way, matrix-blind since
       tests aren't cache variables). *)
    Some (ECmakeRawCmd { name = cmake_name_of_yelu name; args;
                         from_positional = Some "add_test" })
  | "add_test", args ->
    (* Labeled: `~name=X ~command=[cmd, args…]` (command list flattens to
       repeated kwargs, same convention as execute_process). The bare
       `add_test <name> <command> [args…]` shorthand (no cmake keyword)
       stays. *)
    let kwarg_all key =
      List.filter_map kwargs ~f:(fun (k, v) ->
        Option.some_if (String.equal k key) v) in
    (match List.Assoc.find kwargs ~equal:String.equal "name" with
     | Some name_e ->
       (match kwarg_all "command" with
        | cmd :: rest -> Some (yc_add_test name_e cmd rest)
        | [] -> Some (yc_add_test name_e (EString "?") []))
     | None ->
       (match args with
        | name_arg :: command :: rest ->
          Some (yc_add_test name_arg command rest)
        | _ -> None))
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
            | EVar s -> List.mem kw s ~equal:String.equal
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
           | EVar s ->
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
            | EVar s -> List.mem kw s ~equal:String.equal
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
  (* NOTE (2026-07-20): the specialized property getters/setters
     (set_/get_global_property, set_/get_directory_property,
     set_test_properties, set_source_property) had NO usable .yc surface —
     the positional form rejected, no labeled form existed, and the bare
     arity emitted nothing / a literal `?` / crashed emit. They were also
     redundant: the unified entity form covers every scope
     (`set_property Global|Directory|Test|Source … ~property=[…]`,
     `get_property … ~out=`). The .yc surface is removed; their IR
     constructors stay — those have real programmatic users (step_common_ir,
     the CMakeOnly generators, runcmake tests) that build IR directly in
     OCaml. Writing one in .yc now reports "unknown command", which is
     honest. *)
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
  | "find_package", args
    when List.exists args ~f:(function
           | EVar s ->
             List.mem
               [ "REQUIRED"; "COMPONENTS"; "OPTIONAL_COMPONENTS"; "QUIET";
                 "EXACT"; "MODULE"; "CONFIG"; "NO_MODULE"; "GLOBAL";
                 "NO_POLICY_SCOPE"; "BYPASS_PROVIDER" ]
               s ~equal:String.equal
           | _ -> false) ->
    (* Labeled-only (Step 2 rollout, audit #3): a positional cmake keyword is a
       fatal reject. REQUIRED has the ~required label; COMPONENTS et al. were
       previously *silently dropped* (`find_package Foo COMPONENTS a b` emitted
       `find_package(Foo)`) — reject is strictly better than data loss; a
       ~components label can come when the IR grows components. *)
    Some (ECmakeRawCmd { name = cmake_name_of_yelu name; args;
                         from_positional = Some "find_package" })
  | "find_package", pkg :: _rest ->
    (* NOTE: a bare version positional (`find_package CUDA '9.0'`) is accepted
       and currently dropped — the IR has no version field yet (ties to the
       version-literal TODO in yc_syntax_critique.md). *)
    let required = List.Assoc.mem kwargs ~equal:String.equal "required" in
    Some (yc_find_package ~required (str_name pkg))
  | ("find_library" | "find_path" | "find_program" | "find_file"), args
    when List.exists args ~f:(function
           | EVar s ->
             List.mem
               [ "NAMES"; "PATHS"; "HINTS"; "PATH_SUFFIXES"; "DOC"; "REQUIRED";
                 "NO_CACHE"; "NO_DEFAULT_PATH"; "VALIDATOR"; "REGISTRY_VIEW" ]
               s ~equal:String.equal
           | _ -> false) ->
    (* Labeled-only: use ~name/~names/~path/~paths (or yc_raw for the rest). *)
    Some (ECmakeRawCmd { name = cmake_name_of_yelu name; args;
                         from_positional = Some name })
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
    (* Match bare [EVar] only — the positional cmake-keyword form is always a
       bare ident; a *quoted* string equal to a keyword (EString) is a literal
       operand and must NOT trigger the reject. All labeled-only reject guards
       follow this rule (audit 2026-06: fixes the quoted-literal false positive). *)
    let arg_is_kw = function
      | EVar s -> List.mem (art_kw @ opt_kw) s ~equal:String.equal
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
      | EVar s -> List.mem kw s ~equal:String.equal | _ -> false in
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
      | EVar s -> List.mem kw s ~equal:String.equal | _ -> false in
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
      | EVar s -> List.mem kw s ~equal:String.equal | _ -> false in
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
  | "export", args
    when List.exists args ~f:(function
           | EVar s ->
             List.mem [ "TARGETS"; "NAMESPACE"; "FILE" ] s ~equal:String.equal
           | _ -> false) ->
    (* Labeled-only (Step 2): the positional TARGETS/NAMESPACE/FILE form is a
       fatal reject — use ~targets=[…] / ~namespace= / ~file=. *)
    Some (ECmakeRawCmd { name = cmake_name_of_yelu name; args;
                         from_positional = Some "export" })
  | "export", args ->
    (* Two modes. TARGETS form: `~targets=[…]` (+ ~namespace / ~file), no
       leading positional. EXPORT-name form: a single positional export name
       (+ ~file). The presence of ~targets selects the TARGETS form. *)
    (match kwarg_opt ~key:"targets" with
     | Some (EList targets) ->
       let namespace = match kwarg_opt ~key:"namespace" with
         | Some (EString s | EVar s) -> Some s | _ -> None in
       let file = kwarg_opt ~key:"file" in
       Some (yc_export_targets ?namespace ?file targets)
     | _ ->
       (match args with
        | [ name_arg ] ->
          let file = kwarg_opt ~key:"file" in
          Some (yc_export_export ?file name_arg)
        | _ -> None))
  | "configure_package_config_file", args
    when List.exists args ~f:(function
           | EVar "INSTALL_DESTINATION" -> true
           | _ -> false) ->
    (* Labeled-only (Step 2): the positional INSTALL_DESTINATION form is a fatal
       reject — input/output are positional, the path is `~install_destination=`. *)
    Some (ECmakeRawCmd { name = cmake_name_of_yelu name; args;
                         from_positional = Some "configure_package_config_file" })
  | "configure_package_config_file", args ->
    let install_dest = match kwarg_opt ~key:"install_destination" with
      | Some e -> e | None -> EVar "?" in
    let input, output = match args with
      | [ i; o ] -> (i, o)
      | [ i ] -> (i, EVar "?")
      | _ -> (EVar "?", EVar "?")
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

let message_modes =
  [ "STATUS"; "FATAL_ERROR"; "SEND_ERROR"; "WARNING"; "AUTHOR_WARNING";
    "DEPRECATION"; "NOTICE"; "VERBOSE"; "DEBUG"; "TRACE";
    "CHECK_START"; "CHECK_PASS"; "CHECK_FAIL" ]

let p_cmake_op_command_y1_inner name args kwargs =
  let out = out_var_y1 kwargs in
  match name, args with
  | "cmake_minimum_required", args
    when List.exists args ~f:(function
           | EVar "VERSION" -> true | _ -> false) ->
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
  | "message", args
    when List.exists args ~f:(function
           | EVar s -> List.mem message_modes s ~equal:String.equal
           | _ -> false) ->
    (* Labeled-only (Step 2): a positional mode keyword (a bare FATAL_ERROR /
       WARNING / …) is a fatal reject — use ~mode=Fatal_error / ~mode=Warning.
       A *quoted* message text that happens to read like a mode is fine (it's an
       EString, not a bare EVar). *)
    Some (ECmakeRawCmd { name = cmake_name_of_yelu name; args;
                         from_positional = Some "message" })
  | "message", args ->
    (* mode from ~mode= (value uppercased to the cmake keyword; default STATUS);
       all positionals are message text. *)
    let mode = match List.Assoc.find kwargs ~equal:String.equal "mode" with
      | Some (EString s | EVar s) ->
        let u = String.uppercase s in
        if List.mem message_modes u ~equal:String.equal
        then message_mode_of_string u else Lang_cmake.Mm_status
      | _ -> Lang_cmake.Mm_status
    in
    let texts = List.map args ~f:(fun e -> match e with EString s -> s | _ -> "") in
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
           | EVar "OPTIONAL" -> true | _ -> false) ->
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
            | EVar s -> List.mem kw s ~equal:String.equal
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

