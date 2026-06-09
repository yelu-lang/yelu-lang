(* [tool-interface]
   node:     cmake text → cmake AST (via JSON CST intermediary)
   op:       parse
   strategy: code (walks JSON CST; the lexer is tool:tree-sitter)
   exports:  file_of_json : Yojson.Safe.t → Lang_cmake.exp
   imports:  Lang_cmake (target AST), per-command parsers (~50)
   ─────────

   Cmake text → Lang_cmake.exp via Stage-1 untyped AST.

   This module is the canonical "cmake text parser" for yelu. It
   was extracted from tool/cmake_text/print2.ml — the
   Bar #3-lite oracle's typed-dispatch core — into a library so
   that other consumers (the from_emit bridge for yc-eval, future
   analysis passes, more tools) can ingest cmake without copying
   the dispatcher.

   Pipeline this module covers (steps 1 → 3 of the smoke
   pipeline in doc/yelu_cmake/cache_plan.md / fmt_probe_report):

     cmake text → parse.py → Stage-1 JSON CST
       → file_of_json  (this module)
         → Stage-1 untyped AST (cmd / stmt)
           → parse_cmd  (this module)
             → Lang_cmake.exp option
                Some _ : modeled command (typed Lang_cmake ctor)
                None   : unmodeled — caller wraps in Apply for
                         round-trip or EUnit no-op for eval

   The "Stage-1 untyped AST" is shared with project_index.ml and
   cache_vars.ml (each previously kept its own copy as a
   prototype convenience). Those tools should ideally migrate to
   importing from here too; left for a follow-up.

   Bar #3-lite oracle invariants (STRUCT=0 / FORMAT=0 across
   tutorial + z3 + llvm) depend on this module's per-command
   parsers matching cmake source faithfully. Changes that affect
   parse_cmd's output for any modeled command MUST be validated
   against the round-trip oracle:
     bash tool/cmake_text/test_corpus.sh \\
       /home/red/code/contrib/z3-all/z3
   should still show 108/108 OK. *)

open Base
module L = Lang_cmake


(* ============================================================
   Stage-1 AST + JSON reader (duplicated from print.ml to keep
   the prototype standalone; will share once stable).
   ============================================================ *)

type cmd = {
  name : string;
  args : string list;
}

type stmt =
  | Cmd of cmd
  | Block of {
      block_type : string;
      head : cmd;
      body : stmt list;
      clauses : (cmd * stmt list) list;
      tail : cmd;
    }
  | Raw of string
  | Unknown of { ts_type : string; text : string }

let json_string_field obj key =
  match List.Assoc.find obj key ~equal:String.equal with
  | Some (`String s) -> s
  | _ -> failwith (Printf.sprintf "missing string field %s" key)

let json_list_field obj key =
  match List.Assoc.find obj key ~equal:String.equal with
  | Some (`List xs) -> xs
  | _ -> failwith (Printf.sprintf "missing list field %s" key)

let rec cmd_of_json = function
  | `Assoc obj ->
    {
      name = json_string_field obj "name";
      args = json_list_field obj "args"
             |> List.map ~f:(function
                  | `String s -> s
                  | _ -> failwith "arg must be string");
    }
  | _ -> failwith "cmd_of_json: expected object"

and stmt_of_json = function
  | `Assoc obj as j ->
    (match json_string_field obj "kind" with
     | "cmd" -> Cmd (cmd_of_json j)
     | "block" ->
       let block_type = json_string_field obj "block_type" in
       let head =
         match List.Assoc.find obj "head" ~equal:String.equal with
         | Some h -> cmd_of_json h | None -> failwith "block: missing head"
       in
       let body = List.map (json_list_field obj "body") ~f:stmt_of_json in
       let clauses =
         List.map (json_list_field obj "clauses") ~f:(function
           | `Assoc cobj ->
             let head =
               match List.Assoc.find cobj "head" ~equal:String.equal with
               | Some h -> cmd_of_json h | None -> failwith "clause: head"
             in
             let body =
               List.map (json_list_field cobj "body") ~f:stmt_of_json
             in
             (head, body)
           | _ -> failwith "clause: expected object")
       in
       let tail =
         match List.Assoc.find obj "tail" ~equal:String.equal with
         | Some t -> cmd_of_json t | None -> failwith "block: tail"
       in
       Block { block_type; head; body; clauses; tail }
     | "raw" -> Raw (json_string_field obj "text")
     | "unknown" ->
       Unknown {
         ts_type = json_string_field obj "type";
         text = json_string_field obj "text";
       }
     | other -> failwith (Printf.sprintf "unknown kind %s" other))
  | _ -> failwith "stmt_of_json: expected object"

let file_of_json = function
  | `Assoc obj ->
    (match List.Assoc.find obj "kind" ~equal:String.equal with
     | Some (`String "source_file") -> ()
     | _ -> failwith "file_of_json: expected kind=source_file");
    List.map (json_list_field obj "stmts") ~f:stmt_of_json
  | _ -> failwith "file_of_json: expected object"

(* ============================================================
   Arg coercion: raw source text -> Lang_cmake.arg
   ============================================================ *)

(* tree-sitter preserves the original quoting form. We map to:
   - "..."        -> Quoted (inner contents)
   - [==[...]==]  -> Bracket (inner contents)
   - bare         -> Bare (literal text) *)
let arg_of_raw (s : string) : L.arg =
  let n = String.length s in
  if n >= 2 && Char.equal s.[0] '"' && Char.equal s.[n - 1] '"' then
    Quoted (String.sub s ~pos:1 ~len:(n - 2))
  else if n >= 4 && Char.equal s.[0] '[' then
    (* match [=*[...]=*] — `level` = number of `=` between the outer
       [ and the inner [. *)
    let rec count_eq i =
      if i < n && Char.equal s.[i] '=' then count_eq (i + 1) else i - 1
    in
    let level = count_eq 1 in
    if level >= 0 && level < n - 1
       && Char.equal s.[level + 1] '['
       && Char.equal s.[n - level - 2] ']'
       && Char.equal s.[n - 1] ']'
    then
      let body_pos = level + 2 in
      let body_len = n - 2 * (level + 2) in
      Bracket (level, String.sub s ~pos:body_pos ~len:body_len)
    else
      Bare s
  else
    Bare s

(* Treat an arg as a plain string for slots that take [string] /
   [var] / [target] / [file] etc. Strips outer quoting / brackets. *)
let str_of_raw (s : string) : string =
  match arg_of_raw s with
  | Bare s | Quoted s | Bracket (_, s) -> s

(* True iff the raw arg has no quoting / bracket framing. Typed
   parsers that map to IR `string` slots (versus `arg`) lose the
   quoting information, so they must bail to [Apply] if any of
   their consumed args are quoted/bracketed. *)
let is_bare (s : string) : bool =
  match arg_of_raw s with Bare _ -> true | _ -> false

let all_bare = List.for_all ~f:is_bare

(* ============================================================
   Per-command typed mappers
   ============================================================ *)

(* Parse a cmake version like "3.20" into {major; minor; patch}.
   Returns None on anything that isn't dot-separated integers (e.g.,
   variable refs like ${Z3_VERSION_FROM_FILE}). *)
let version_of_string_opt s : L.version option =
  try
    let parts = String.split s ~on:'.' in
    match parts with
    | [ maj ] -> Some { major = Int.of_string maj; minor = 0; patch = "" }
    | [ maj; min ] ->
      Some { major = Int.of_string maj; minor = Int.of_string min; patch = "" }
    | maj :: min :: rest ->
      Some { major = Int.of_string maj;
             minor = Int.of_string min;
             patch = String.concat ~sep:"." rest }
    | [] -> None
  with _ -> None

(* cmake_minimum_required(VERSION <min>[...<max>]).
   Range form `<min>...<max>` is now modeled — the printer was
   updated 2026-05-25 to emit both bounds when max = Some _. Bail
   only on non-numeric versions or unrecognized shapes. *)
let parse_cmake_minimum_required args : L.exp option =
  if not (all_bare args) then None
  else
  match args with
  | [ "VERSION"; v ] ->
    let min_s, max_s =
      match String.substr_index v ~pattern:"..." with
      | None -> v, None
      | Some i ->
        let lo = String.sub v ~pos:0 ~len:i in
        let hi = String.sub v ~pos:(i + 3) ~len:(String.length v - i - 3) in
        lo, Some hi
    in
    (match version_of_string_opt min_s with
     | None -> None
     | Some min ->
       let max_v =
         match max_s with
         | None -> Some None
         | Some s ->
           (match version_of_string_opt s with
            | None -> None
            | Some v -> Some (Some v))
       in
       (match max_v with
        | None -> None
        | Some max ->
          Some (Cmake_cmd (Cmake_minimum_required { min; max }))))
  | _ -> None

(* project(<name> [VERSION <v>] [LANGUAGES <langs>]).
   The IR also carries DESCRIPTION / HOMEPAGE_URL, but the printer
   always quotes them (`pp_string_quoted`). Since `arg_of_raw` would
   classify a bare token as `Bare` and a quoted token as `Quoted`,
   re-emitting a source `DESCRIPTION desc` as `DESCRIPTION "desc"`
   would change the argument shape under STRUCT extraction. Bail
   on any DESCRIPTION / HOMEPAGE_URL until the printer is fixed. *)
let parse_project args : L.exp option =
  if not (all_bare args) then None
  else if List.exists args ~f:(fun a ->
    String.equal a "DESCRIPTION" || String.equal a "HOMEPAGE_URL")
  then None
  else
  let rec split_keywords acc_name version langs = function
    | [] -> Some (acc_name, version, langs)
    | "VERSION" :: v :: rest -> split_keywords acc_name (Some v) langs rest
    | "LANGUAGES" :: rest ->
      (* All remaining tokens are languages, in source order. *)
      Some (acc_name, version, rest)
    | name :: rest when String.is_empty acc_name ->
      split_keywords name version langs rest
    | _ -> None
  in
  match split_keywords "" None [] args with
  | Some (name, version_str, langs) when not (String.is_empty name) ->
    let version_parsed =
      match version_str with
      | None -> Some None
      | Some s ->
        (match version_of_string_opt s with
         | None -> None       (* version like ${VAR} — bail to Apply *)
         | Some v -> Some (Some v))
    in
    (match version_parsed with
     | None -> None
     | Some version ->
       Some (Project_cmd
               (Project
                  { name; version;
                    description = None; homepage_url = None;
                    languages = langs })))
  | _ -> None

(* set(<var> <value>... [PARENT_SCOPE]) — plain form.
   set(<var> <value>... CACHE <type> "<doc>" [FORCE]) — cache form.

   The CACHE form routes to L.Set_cache so eval populates
   env.cache_vars correctly (per cache_semantics.md). For the
   round-trip oracle, Lang_cmake_pp's Set_cache emit produces
   identical text to the plain Set arm — Bar #3-lite holds.

   Discovered via the fmt include-loader smoke (2026-06-02):
   fmt has `set(FMT_DEBUG_POSTFIX d CACHE STRING "Debug library
   postfix.")` which was being parsed as plain Set and writing
   to normal vars only — yc-eval's predicted cache missed it. *)
let parse_set args : L.exp option =
  match args with
  | var :: rest when not (String.is_prefix var ~prefix:"\"") ->
    let rec find_cache_idx i = function
      | [] -> None
      | "CACHE" :: tail -> Some (i, tail)
      | _ :: tail -> find_cache_idx (i + 1) tail
    in
    (match find_cache_idx 0 rest with
     | Some (i, after_cache) ->
       let values = List.take rest i in
       (match after_cache with
        | type_s :: doc_s :: rest_after ->
          (* cache_type is now a raw string (was enum, changed
             2026-06-03). The static path (type_s = "STRING"/etc.)
             and the dynamic path (type_s = "${type}") both go
             through verbatim — the source text round-trips
             byte-identically via Lang_cmake_pp, and eval can
             substitute dynamic types if needed at write time.
             This closes fmt's set_verbose() pattern that used to
             bail at parse time. *)
          let force = List.mem rest_after "FORCE" ~equal:String.equal in
          Some (Set_cache {
            var = str_of_raw var;
            values = List.map values ~f:arg_of_raw;
            cache_type = type_s;
            docstring = str_of_raw doc_s;
            force;
          })
        | _ -> None)
     | None ->
       let parent_scope, values =
         match List.rev rest with
         | "PARENT_SCOPE" :: rev_rest -> true, List.rev rev_rest
         | _ -> false, rest
       in
       Some (Set { var = str_of_raw var;
                   values = List.map values ~f:arg_of_raw;
                   parent_scope }))
  | _ -> None

let message_mode_of_first_arg = function
  | "FATAL_ERROR" -> Some L.Mm_fatal_error
  | "SEND_ERROR" -> Some Mm_send_error
  | "WARNING" -> Some Mm_warning
  | "AUTHOR_WARNING" -> Some Mm_author_warning
  | "DEPRECATION" -> Some Mm_deprecation
  | "NOTICE" -> Some Mm_notice
  | "STATUS" -> Some Mm_status
  | "VERBOSE" -> Some Mm_verbose
  | "DEBUG" -> Some Mm_debug
  | "TRACE" -> Some Mm_trace
  | "CHECK_START" -> Some Mm_check_start
  | "CHECK_PASS" -> Some Mm_check_pass
  | "CHECK_FAIL" -> Some Mm_check_fail
  | _ -> None

(* message([mode] <text>...).
   Lang_cmake_pp's Message printer ALWAYS quotes texts (`pp_string_quoted`),
   so a typed parse only round-trips when every text arg was originally
   quoted in source. Bail otherwise. *)
let parse_message args : L.exp option =
  match args with
  | [] -> None
  | first :: rest ->
    let mode, texts =
      match message_mode_of_first_arg first with
      | Some m -> m, rest
      | None -> Mm_none, args
    in
    let is_quoted s = match arg_of_raw s with Quoted _ -> true | _ -> false in
    if not (List.for_all texts ~f:is_quoted) then None
    else
      Some (Message { mode; texts = List.map texts ~f:str_of_raw })

(* configure_file(<input> <output> [COPYONLY] [...flags]).
   input/output are typed [path] (string); Lang_cmake_pp emits them
   bare. Bail if source had them quoted, or if it carried NEWLINE_STYLE
   (which the parser doesn't yet read). *)
let parse_configure_file args : L.exp option =
  if not (all_bare args) then None
  else if List.exists args ~f:(String.equal "NEWLINE_STYLE") then None
  else
  let bool_of_flag flag rest = List.exists rest ~f:(String.equal flag) in
  match args with
  | [ input; output ] ->
    Some (Cmake_cmd
            (Configure_file
               { input; output;
                 permission_level = None; permissions = [];
                 copy_only = None; escape_quotes = None;
                 only = None; newline_style = None }))
  | input :: output :: rest ->
    Some (Cmake_cmd
            (Configure_file
               { input; output;
                 permission_level = None; permissions = [];
                 copy_only = (if bool_of_flag "COPYONLY" rest then Some true else None);
                 escape_quotes = (if bool_of_flag "ESCAPE_QUOTES" rest then Some true else None);
                 only = (if bool_of_flag "@ONLY" rest then Some true else None);
                 newline_style = None }))
  | _ -> None

(* add_executable — four shapes:
   1. add_executable(<name> [WIN32] [MACOSX_BUNDLE] [EXCLUDE_FROM_ALL] <src>...)
      → Add_executable { options; sources }
   2. add_executable(<name> IMPORTED [GLOBAL])
      → Add_executable_imported
   3. add_executable(<name> ALIAS <target>)
      → Add_executable_alias
   Options updated 2026-05-29 to populate the IR's [options] field
   (previously bailed on WIN32/MACOSX_BUNDLE/EXCLUDE_FROM_ALL). *)
let parse_add_executable args : L.exp option =
  if not (all_bare args) then None
  else
  match args with
  | [ name; "IMPORTED" ] ->
    Some (Project_cmd (Add_executable_imported { name; global = false }))
  | [ name; "IMPORTED"; "GLOBAL" ] ->
    Some (Project_cmd (Add_executable_imported { name; global = true }))
  | [ name; "ALIAS"; target ] ->
    Some (Project_cmd (Add_executable_alias { name; target }))
  | name :: rest ->
    (* Consume contiguous option keywords in source order — they're
       printer-emitted positionally, so source order is preserved
       in the [options] list. *)
    let rec take_opts acc = function
      | "WIN32" :: r -> take_opts (L.Ae_win32 :: acc) r
      | "MACOSX_BUNDLE" :: r -> take_opts (L.Ae_macos_bundle :: acc) r
      | "EXCLUDE_FROM_ALL" :: r -> take_opts (L.Ae_exclude_from_all :: acc) r
      | rest -> List.rev acc, rest
    in
    let options, sources = take_opts [] rest in
    if List.is_empty sources then None
    else if List.exists sources ~f:(fun s ->
      List.mem ["WIN32"; "MACOSX_BUNDLE"; "EXCLUDE_FROM_ALL";
                "ALIAS"; "IMPORTED"; "GLOBAL"]
        s ~equal:String.equal)
    then None  (* misplaced keyword among sources — bail *)
    else
      Some (Project_cmd
              (Add_executable { name; options; sources }))
  | _ -> None

(* add_library — five shapes:
   1. add_library(<name> [STATIC|SHARED|MODULE|UNKNOWN] [EXCLUDE_FROM_ALL] <src>...)
      → Add_library
   2. add_library(<name> OBJECT <src>...)
      → Add_library_object
   3. add_library(<name> INTERFACE)
      → Add_library_interface
   4. add_library(<name> [<type>] IMPORTED [GLOBAL])
      → Add_library_imported
   5. add_library(<name> ALIAS <target>)
      → Add_library_alias *)
let library_types = [ "STATIC"; "SHARED"; "MODULE"; "UNKNOWN" ]

let parse_add_library args : L.exp option =
  if not (all_bare args) then None
  else
  match args with
  | [ name; "INTERFACE" ] ->
    Some (Project_cmd (Add_library_interface { name }))
  | [ name; "ALIAS"; target ] ->
    Some (Project_cmd (Add_library_alias { name; target }))
  | [ name; "IMPORTED" ] ->
    Some (Project_cmd (Add_library_imported
                         { name; lib_type = None; global = false }))
  | [ name; "IMPORTED"; "GLOBAL" ] ->
    Some (Project_cmd (Add_library_imported
                         { name; lib_type = None; global = true }))
  | [ name; t; "IMPORTED" ]
    when List.mem library_types t ~equal:String.equal
         || String.equal t "OBJECT"
         || String.equal t "INTERFACE" ->
    Some (Project_cmd (Add_library_imported
                         { name; lib_type = Some t; global = false }))
  | [ name; t; "IMPORTED"; "GLOBAL" ]
    when List.mem library_types t ~equal:String.equal
         || String.equal t "OBJECT"
         || String.equal t "INTERFACE" ->
    Some (Project_cmd (Add_library_imported
                         { name; lib_type = Some t; global = true }))
  | name :: "OBJECT" :: sources when not (List.is_empty sources) ->
    Some (Project_cmd (Add_library_object { name; sources }))
  | name :: rest ->
    if List.exists rest ~f:(fun s ->
        List.mem [ "ALIAS"; "IMPORTED" ] s ~equal:String.equal)
    then None
    else
      let type_, after_type =
        match rest with
        | t :: rest' when List.mem library_types t ~equal:String.equal ->
          Some t, rest'
        | _ -> None, rest
      in
      let exclude, sources =
        match after_type with
        | "EXCLUDE_FROM_ALL" :: rest' -> true, rest'
        | _ -> false, after_type
      in
      Some (Project_cmd
              (Add_library
                 { name; type_; exclude_from_all = exclude; sources }))
  | _ -> None

(* Group args by visibility keyword. Default group "PRIVATE" (cmake
   default for target_* without explicit keyword). *)
let group_by_visibility args : L.items_with_kind list =
  let is_kind = function
    | "PUBLIC" | "PRIVATE" | "INTERFACE" -> true
    | _ -> false
  in
  let rec loop current_kind current_acc groups = function
    | [] ->
      let groups =
        if List.is_empty current_acc then groups
        else { L.kind = current_kind; items = List.rev current_acc } :: groups
      in
      List.rev groups
    | k :: rest when is_kind k ->
      let groups =
        if List.is_empty current_acc then groups
        else { L.kind = current_kind; items = List.rev current_acc } :: groups
      in
      loop k [] groups rest
    | x :: rest -> loop current_kind (arg_of_raw x :: current_acc) groups rest
  in
  loop "PRIVATE" [] [] args

(* target_link_libraries(<target> <items>...).
   Bail if no visibility keyword present (cmake's "plain" legacy
   form); Lang_cmake_pp's pp_args_with_kind always emits the kind
   string, so a defaulted PRIVATE would inject a keyword the source
   didn't have. *)
let has_visibility_keyword args =
  List.exists args ~f:(fun s ->
    match s with "PUBLIC" | "PRIVATE" | "INTERFACE" -> true | _ -> false)

let parse_target_link_libraries args : L.exp option =
  match args with
  | target :: items when not (List.is_empty items) ->
    if not (has_visibility_keyword items) then None
    else
      Some (Project_cmd
              (Target_link_libraries
                 { targets = [ str_of_raw target ];
                   items = group_by_visibility items }))
  | _ -> None

(* target_compile_definitions(<target> <items>...).
   Same plain-form bail as target_link_libraries. *)
let parse_target_compile_definitions args : L.exp option =
  match args with
  | target :: items when not (List.is_empty items) ->
    if not (has_visibility_keyword items) then None
    else
      Some (Project_cmd
              (Target_compile_definitions
                 { target = str_of_raw target;
                   items = group_by_visibility items }))
  | _ -> None

(* target_compile_options(<target> [BEFORE] <items>...). *)
let parse_target_compile_options args : L.exp option =
  match args with
  | target :: rest when not (List.is_empty rest) ->
    let before, items =
      match rest with
      | "BEFORE" :: rest' -> true, rest'
      | _ -> false, rest
    in
    if List.is_empty items || not (has_visibility_keyword items) then None
    else
      Some (Project_cmd
              (Target_compile_options
                 { target = str_of_raw target;
                   before;
                   items = group_by_visibility items }))
  | _ -> None

(* target_compile_features(<target> <kind> <features>...).
   Features are typed [string]; bail on quoting. *)
let parse_target_compile_features args : L.exp option =
  if not (all_bare args) then None
  else
  let is_kind = function
    | "PUBLIC" | "PRIVATE" | "INTERFACE" -> true
    | _ -> false
  in
  match args with
  | target :: rest ->
    let rec loop current_kind acc = function
      | [] -> List.rev acc
      | k :: rest' when is_kind k -> loop k acc rest'
      | f :: rest' ->
        loop current_kind ({ L.kind = current_kind; feature = f } :: acc) rest'
    in
    let features = loop "PRIVATE" [] rest in
    if List.is_empty features then None
    else
      Some (Project_cmd (Target_compile_features { target; features }))
  | _ -> None

(* option(<var> <help_text> [ON|OFF]). help_text is always quoted
   in Lang_cmake_pp's output; bail if source had it bare. *)
let parse_option args : L.exp option =
  let help_quoted s = match arg_of_raw s with Quoted _ -> true | _ -> false in
  match args with
  | [ var; help ] when is_bare var && help_quoted help ->
    Some (Option
            { var;
              help_text = [ str_of_raw help ];
              value = Bool false })
  | [ var; help; v ] when is_bare var && help_quoted help && is_bare v ->
    Some (Option
            { var;
              help_text = [ str_of_raw help ];
              value = Var_exp v })
  | _ -> None

(* include(<file> [OPTIONAL] [RESULT_VARIABLE <var>] [NO_POLICY_SCOPE]) *)
let parse_include args : L.exp option =
  match args with
  | file :: rest ->
    let optional = List.exists rest ~f:(String.equal "OPTIONAL") in
    let rec find_result_var = function
      | "RESULT_VARIABLE" :: v :: _ -> Some (str_of_raw v)
      | _ :: rest' -> find_result_var rest'
      | [] -> None
    in
    let result_var = find_result_var rest in
    let no_policy_scope =
      List.exists rest ~f:(String.equal "NO_POLICY_SCOPE")
    in
    Some (Include
            { file = arg_of_raw file;
              optional;
              result_var;
              no_policy_scope })
  | _ -> None

(* add_subdirectory(<source_dir> [<binary_dir>] [EXCLUDE_FROM_ALL] [SYSTEM]).
   source_dir/binary_dir are typed [directory] (string); bail on quoting. *)
let parse_add_subdirectory args : L.exp option =
  if not (all_bare args) then None
  else
  let extract_flags args =
    let exclude = List.exists args ~f:(String.equal "EXCLUDE_FROM_ALL") in
    let system = List.exists args ~f:(String.equal "SYSTEM") in
    let dirs = List.filter args ~f:(fun s ->
        not (String.equal s "EXCLUDE_FROM_ALL" || String.equal s "SYSTEM")) in
    exclude, system, dirs
  in
  let exclude, system, dirs = extract_flags args in
  match dirs with
  | [ source_dir ] ->
    Some (Project_cmd
            (Add_subdirectory
               { source_dir; binary_dir = None;
                 exclude_from_all = exclude; system }))
  | [ source_dir; binary_dir ] ->
    Some (Project_cmd
            (Add_subdirectory
               { source_dir; binary_dir = Some binary_dir;
                 exclude_from_all = exclude; system }))
  | _ -> None

(* target_include_directories(<target> [SYSTEM] [BEFORE|AFTER] <items>...) *)
let parse_target_include_directories args : L.exp option =
  let take_flags = function
    | "SYSTEM" :: rest -> Some true, rest
    | rest -> None, rest
  in
  let take_before_after = function
    | "BEFORE" :: rest -> Some L.Before, rest
    | "AFTER" :: rest -> Some L.After, rest
    | rest -> None, rest
  in
  match args with
  | target :: rest ->
    let system, rest = take_flags rest in
    let before_or_after, rest = take_before_after rest in
    (match rest with
     | [] -> None
     | _ ->
       if not (has_visibility_keyword rest) then None
       else
         Some (Project_cmd
                 (Target_include_directories
                    { target = str_of_raw target;
                      system;
                      before_or_after;
                      items = group_by_visibility rest })))
  | _ -> None

(* ============================================================
   Stage 2-b — extra builtins (mechanical typed parsers).
   Each follows the "bail on lossy / unknown shape" discipline:
   route to Apply rather than emit lossy typed output.
   ============================================================ *)

(* unset(<var> [CACHE | PARENT_SCOPE]) *)
let parse_unset args : L.exp option =
  if not (all_bare args) then None
  else
  match args with
  | [ var ] -> Some (Unset { var; cache = false; parent_scope = false })
  | [ var; "CACHE" ] -> Some (Unset { var; cache = true; parent_scope = false })
  | [ var; "PARENT_SCOPE" ] -> Some (Unset { var; cache = false; parent_scope = true })
  | _ -> None

(* add_dependencies(<target> <dep>...) — IR widened 2026-05-25 to carry
   a [deps : depend list]; the printer emits all of them space-separated. *)
let parse_add_dependencies args : L.exp option =
  if not (all_bare args) then None
  else
  match args with
  | target :: deps when not (List.is_empty deps) ->
    Some (Project_cmd (Add_dependencies { target; deps }))
  | _ -> None

(* find_package(<name> [VERSION] [EXACT] [QUIET] [REQUIRED] [CONFIG]
                [COMPONENTS <c>...] [OPTIONAL_COMPONENTS <c>...]) *)
let parse_find_package args : L.exp option =
  if not (all_bare args) then None
  else
  match args with
  | name :: rest ->
    let exact = ref false in
    let quiet = ref false in
    let config_mode = ref false in
    let required = ref false in
    let version = ref None in
    let components = ref [] in
    let optional_components = ref [] in
    let mode : [`Top | `Components | `Optional] ref = ref `Top in
    let ok = ref true in
    (* Once COMPONENTS / OPTIONAL_COMPONENTS has been opened, a top-level
       keyword like REQUIRED would force reordering on reprint (printer
       emits flags before COMPONENTS). Bail in that case. *)
    let bail_if_after_components () =
      if not (Poly.equal !mode `Top) then ok := false
    in
    List.iter rest ~f:(fun a ->
      if not !ok then ()
      else match a with
        | "EXACT" -> bail_if_after_components (); exact := true
        | "QUIET" -> bail_if_after_components (); quiet := true
        | "REQUIRED" -> bail_if_after_components (); required := true
        | "CONFIG" | "NO_MODULE" -> bail_if_after_components (); config_mode := true
        | "MODULE" -> bail_if_after_components (); config_mode := false
        | "COMPONENTS" -> mode := `Components
        | "OPTIONAL_COMPONENTS" -> mode := `Optional
        | "GLOBAL" | "BYPASS_PROVIDER" | "NO_POLICY_SCOPE"
        | "NO_DEFAULT_PATH" | "NO_PACKAGE_ROOT_PATH" | "NO_CMAKE_PATH"
        | "NO_CMAKE_ENVIRONMENT_PATH" | "NO_SYSTEM_ENVIRONMENT_PATH"
        | "NO_CMAKE_PACKAGE_REGISTRY" | "NO_CMAKE_BUILDS_PATH"
        | "NO_CMAKE_SYSTEM_PATH" | "NO_CMAKE_SYSTEM_PACKAGE_REGISTRY"
        | "CMAKE_FIND_ROOT_PATH_BOTH" | "ONLY_CMAKE_FIND_ROOT_PATH"
        | "NO_CMAKE_FIND_ROOT_PATH" | "REGISTRY_VIEW"
        | "HINTS" | "PATHS" | "PATH_SUFFIXES" | "NAMES" ->
          (* These keywords introduce sub-lists we don't model;
             bail to Apply. *)
          ok := false
        | v when Poly.equal !mode `Top && Option.is_none !version ->
          version := Some v
        | v when Poly.equal !mode `Components ->
          components := v :: !components
        | v when Poly.equal !mode `Optional ->
          optional_components := v :: !optional_components
        | _ -> ok := false);
    if not !ok then None
    else
      Some (Find_package
              { name;
                version = !version;
                exact = !exact;
                quiet = !quiet;
                config_mode = !config_mode;
                required = !required;
                components = List.rev !components;
                optional_components = List.rev !optional_components })
  | _ -> None

(* get_filename_component(<var> <filename> <mode> [CACHE]) *)
let parse_get_filename_component args : L.exp option =
  if not (all_bare args) then None
  else
  let valid_modes = [
    "DIRECTORY"; "NAME"; "EXT"; "NAME_WE";
    "LAST_EXT"; "NAME_WLE"; "PATH"; "ABSOLUTE"; "REALPATH"; "PROGRAM";
  ] in
  match args with
  | [ var; filename; mode ] when List.mem valid_modes mode ~equal:String.equal ->
    Some (Get_filename_component { var; filename; mode; cache = false })
  | [ var; filename; mode; "CACHE" ] when List.mem valid_modes mode ~equal:String.equal ->
    Some (Get_filename_component { var; filename; mode; cache = true })
  | _ -> None

(* set_target_properties(<target>... PROPERTIES <k> <v> [<k> <v>]...)
   IR widened 2026-05-25 to carry [targets : target list]; cmake allows
   one or more target names before PROPERTIES. *)
let parse_set_target_properties args : L.exp option =
  let rec split_at_properties acc = function
    | [] -> None
    | "PROPERTIES" :: rest -> Some (List.rev acc, rest)
    | t :: rest when is_bare t -> split_at_properties (t :: acc) rest
    | _ -> None
  in
  match split_at_properties [] args with
  | None -> None
  | Some (targets, rest) when not (List.is_empty targets) ->
    let rec pairs acc = function
      | [] -> Some (List.rev acc)
      | k :: v :: rest when is_bare k ->
        pairs ({ L.prop = k; value = arg_of_raw v } :: acc) rest
      | _ -> None
    in
    (match pairs [] rest with
     | None -> None
     | Some properties ->
       Some (Project_cmd
               (Set_target_properties { targets; properties })))
  | _ -> None

(* add_custom_target(<name> [ALL] [DEPENDS <dep>...]).
   Expanded 2026-05-29 (Tier 4) to handle COMMAND blocks, BYPRODUCTS,
   WORKING_DIRECTORY, COMMENT, VERBATIM, USES_TERMINAL, SOURCES. Bails
   on JOB_POOL / JOB_SERVER_AWARE / COMMAND_EXPAND_LISTS (IR has them
   but the printer drops them via `_`). *)
let parse_add_custom_target args : L.exp option =
  let is_top_kw = function
    | "ALL" | "COMMAND" | "DEPENDS" | "BYPRODUCTS"
    | "WORKING_DIRECTORY" | "COMMENT"
    | "JOB_POOL" | "JOB_SERVER_AWARE"
    | "VERBATIM" | "USES_TERMINAL"
    | "COMMAND_EXPAND_LISTS" | "SOURCES" -> true
    | _ -> false
  in
  let bail_kw = function
    | "JOB_POOL" | "JOB_SERVER_AWARE" | "COMMAND_EXPAND_LISTS" -> true
    | _ -> false
  in
  match args with
  | name :: rest when is_bare name ->
    let all = ref false in
    let commands = ref [] in
    let depends = ref [] in
    let byproducts = ref [] in
    let working_directory = ref None in
    let comment = ref None in
    let verbatim = ref false in
    let uses_terminal = ref false in
    let sources = ref [] in
    let ok = ref true in
    (* Printer canonical order: ALL, COMMAND..., DEPENDS, WORKING_DIRECTORY,
       COMMENT, VERBATIM, USES_TERMINAL, SOURCES. (BYPRODUCTS not in
       printer arm; treated as bail to be safe — printer would drop.) *)
    let kw_rank = function
      | "ALL" -> 0
      | "COMMAND" -> 1
      | "DEPENDS" -> 2
      | "BYPRODUCTS" -> 3      (* IR has it but printer drops *)
      | "WORKING_DIRECTORY" -> 4
      | "COMMENT" -> 5
      | "VERBATIM" -> 6
      | "USES_TERMINAL" -> 7
      | "SOURCES" -> 8
      | _ -> 99
    in
    let last_rank = ref (-1) in
    let check_order kw =
      let r = kw_rank kw in
      if String.equal kw "COMMAND" then
        (if !last_rank > 1 then false
         else (last_rank := 1; true))
      else if r <= !last_rank then false
      else (last_rank := r; true)
    in
    let take_until_kw rest =
      let rec loop acc = function
        | [] -> List.rev acc, []
        | t :: _ as r when is_top_kw t -> List.rev acc, r
        | t :: r -> loop (t :: acc) r
      in
      loop [] rest
    in
    let rec go = function
      | [] -> ()
      | _ when not !ok -> ()
      | kw :: _ when bail_kw kw -> ok := false
      | "BYPRODUCTS" :: _ -> ok := false  (* printer drops BYPRODUCTS *)
      | kw :: _ when not (check_order kw) -> ok := false
      | "ALL" :: r -> all := true; go r
      | "COMMAND" :: r ->
        let cmd_args, r = take_until_kw r in
        (match cmd_args with
         | prog :: args' ->
           commands := { L.command = prog; args = args' } :: !commands;
           go r
         | _ -> ok := false)
      | "DEPENDS" :: r ->
        let ds, r = take_until_kw r in
        if List.is_empty ds then ok := false
        else (depends := ds; go r)
      | "WORKING_DIRECTORY" :: d :: r when not (is_top_kw d) ->
        working_directory := Some d; go r
      | "COMMENT" :: c :: r when not (is_top_kw c) ->
        (match arg_of_raw c with
         | Quoted s -> comment := Some s; go r
         | _ -> ok := false)
      | "VERBATIM" :: r -> verbatim := true; go r
      | "USES_TERMINAL" :: r -> uses_terminal := true; go r
      | "SOURCES" :: r ->
        let ss, r = take_until_kw r in
        if List.is_empty ss then ok := false
        else (sources := ss; go r)
      | _ -> ok := false
    in
    go rest;
    if not !ok then None
    else
      Some (Project_cmd
              (Add_custom_target
                 { name; all = !all;
                   commands = List.rev !commands;
                   depends = !depends;
                   byproducts = !byproducts;
                   working_directory = !working_directory;
                   comment = !comment;
                   job_pool = []; job_server_aware = false;
                   verbatim = !verbatim;
                   uses_terminal = !uses_terminal;
                   command_expand_list = [];
                   sources = !sources }))
  | _ -> None

(* list(<subcommand> <args>) — dispatch on subcommand *)
let parse_list args : L.exp option =
  let all_ints xs = List.for_all xs ~f:(fun s -> Option.is_some (Int.of_string_opt s)) in
  let to_ints xs = List.map xs ~f:Int.of_string in
  (* FILTER and TRANSFORM accept quoted regex / value args; can't
     gate the whole parser on all_bare. Handle them explicitly first,
     then fall back to the bare-args subcommands below. *)
  let try_quoted_arg_subcommands = match args with
    | [ "FILTER"; var; mode_s; "REGEX"; regex_arg ] when is_bare var ->
      let mode = match mode_s with
        | "INCLUDE" -> Some L.Lf_include
        | "EXCLUDE" -> Some Lf_exclude
        | _ -> None
      in
      (match mode, arg_of_raw regex_arg with
       | Some mode, Quoted re ->
         Some (L.List_cmd (Lc_filter { var; mode; regex = re }))
       | _ -> None)
    | "TRANSFORM" :: var :: rest when is_bare var ->
      (* Action consumes 0-2 args; then optional selector (1-3 args);
         then optional OUTPUT_VARIABLE <v>. *)
      let parse_action = function
        | "TOUPPER" :: r -> Some (L.Lta_toupper, r)
        | "TOLOWER" :: r -> Some (Lta_tolower, r)
        | "STRIP" :: r -> Some (Lta_strip, r)
        | "GENEX_STRIP" :: r -> Some (Lta_genex_strip, r)
        | "APPEND" :: v :: r -> Some (Lta_append (arg_of_raw v), r)
        | "PREPEND" :: v :: r -> Some (Lta_prepend (arg_of_raw v), r)
        | "REPLACE" :: m :: rep :: r ->
          (match arg_of_raw m, arg_of_raw rep with
           | Quoted ms, Quoted rs ->
             Some (Lta_replace { match_regex = ms; replace = rs }, r)
           | _ -> None)
        | _ -> None
      in
      (match parse_action rest with
       | None -> None
       | Some (action, rest) ->
         let parse_selector = function
           | "AT" :: r ->
             let rec take_ints acc = function
               | [] -> Some (List.rev acc, [])
               | t :: _ as rest when not (Option.is_some (Int.of_string_opt t)) ->
                 Some (List.rev acc, rest)
               | t :: r -> take_ints (Int.of_string t :: acc) r
             in
             (match take_ints [] r with
              | Some (idxs, r) when not (List.is_empty idxs) ->
                Some (Some (L.Lts_at idxs), r)
              | _ -> None)
           | "FOR" :: start_s :: stop_s :: r ->
             (match Int.of_string_opt start_s, Int.of_string_opt stop_s with
              | Some start, Some stop ->
                (match r with
                 | step_s :: rr when Option.is_some (Int.of_string_opt step_s) ->
                   Some (Some (L.Lts_for
                                 { start; stop;
                                   step = Some (Int.of_string step_s) }), rr)
                 | _ ->
                   Some (Some (L.Lts_for { start; stop; step = None }), r))
              | _ -> None)
           | "REGEX" :: re :: r ->
             (match arg_of_raw re with
              | Quoted s -> Some (Some (L.Lts_regex s), r)
              | _ -> None)
           | r -> Some (None, r)  (* no selector *)
         in
         (match parse_selector rest with
          | None -> None
          | Some (selector, rest) ->
            let output, rest = match rest with
              | "OUTPUT_VARIABLE" :: v :: r when is_bare v -> Some v, r
              | _ -> None, rest
            in
            if not (List.is_empty rest) then None
            else
              Some (L.List_cmd
                      (Lc_transform { var; action; selector; output }))))
    | _ -> None
  in
  match try_quoted_arg_subcommands with
  | Some _ -> try_quoted_arg_subcommands
  | None ->
  if not (all_bare args) then None
  else
  match args with
  | [ "LENGTH"; var; out ] ->
    Some (List_cmd (Lc_length { var; out }))
  | [ "REVERSE"; var ] ->
    Some (List_cmd (Lc_reverse { var }))
  | [ "REMOVE_DUPLICATES"; var ] ->
    Some (List_cmd (Lc_remove_duplicates { var }))
  | "APPEND" :: var :: values when not (List.is_empty values) ->
    Some (List_cmd
            (Lc_append { var; values = List.map values ~f:arg_of_raw }))
  | "PREPEND" :: var :: values when not (List.is_empty values) ->
    Some (List_cmd
            (Lc_prepend { var; values = List.map values ~f:arg_of_raw }))
  | "REMOVE_ITEM" :: var :: values when not (List.is_empty values) ->
    Some (List_cmd
            (Lc_remove_item { var; values = List.map values ~f:arg_of_raw }))
  | "FIND" :: [ var; value; out ] ->
    Some (List_cmd
            (Lc_find { var; value = arg_of_raw value; out }))
  | "JOIN" :: [ var; glue; out ] ->
    Some (List_cmd
            (Lc_join { var; glue = arg_of_raw glue; out }))
  (* list(GET <var> <index>... <out>) — middle args are integer indices,
     last is the output variable. *)
  | "GET" :: var :: rest when List.length rest >= 2 ->
    (match List.split_n rest (List.length rest - 1) with
     | indices_str, [ out ] when all_ints indices_str ->
       Some (List_cmd
               (Lc_get { var; indices = to_ints indices_str; out }))
     | _ -> None)
  (* list(SUBLIST <var> <begin> <length> <out>) *)
  | [ "SUBLIST"; var; b; l; out ] ->
    (match Int.of_string_opt b, Int.of_string_opt l with
     | Some begin_, Some length ->
       Some (List_cmd (Lc_sublist { var; begin_; length; out }))
     | _ -> None)
  (* list(INSERT <var> <index> <value>...) *)
  | "INSERT" :: var :: index :: values when not (List.is_empty values) ->
    (match Int.of_string_opt index with
     | Some i ->
       Some (List_cmd
               (Lc_insert { var; index = i;
                            values = List.map values ~f:arg_of_raw }))
     | None -> None)
  (* list(REMOVE_AT <var> <index>...) *)
  | "REMOVE_AT" :: var :: indices when not (List.is_empty indices)
                                       && all_ints indices ->
    Some (List_cmd
            (Lc_remove_at { var; indices = to_ints indices }))
  (* list(POP_BACK <var> [<out_var>...]) *)
  | "POP_BACK" :: var :: out_vars ->
    Some (List_cmd (Lc_pop_back { var; out_vars }))
  (* list(POP_FRONT <var> [<out_var>...]) *)
  | "POP_FRONT" :: var :: out_vars ->
    Some (List_cmd (Lc_pop_front { var; out_vars }))
  (* list(SORT <var> [ORDER <order>] [COMPARE <cmp>] [CASE <case>]) *)
  | "SORT" :: var :: rest ->
    let order = ref None in
    let compare = ref None in
    let case = ref None in
    let ok = ref true in
    let rec go = function
      | [] -> ()
      | "ORDER" :: o :: r when Option.is_none !order ->
        (match o with
         | "ASCENDING" -> order := Some L.Ls_ascending; go r
         | "DESCENDING" -> order := Some Ls_descending; go r
         | _ -> ok := false)
      | "COMPARE" :: c :: r when Option.is_none !compare ->
        (match c with
         | "STRING" -> compare := Some L.Ls_string; go r
         | "FILE_BASENAME" -> compare := Some Ls_file_basename; go r
         | "NATURAL" -> compare := Some Ls_natural; go r
         | _ -> ok := false)
      | "CASE" :: c :: r when Option.is_none !case ->
        (match c with
         | "SENSITIVE" -> case := Some L.Ls_sensitive; go r
         | "INSENSITIVE" -> case := Some Ls_insensitive; go r
         | _ -> ok := false)
      | _ -> ok := false
    in
    go rest;
    if not !ok then None
    else Some (List_cmd
                 (Lc_sort { var; order = !order;
                            compare = !compare; case = !case }))
  | _ -> None

(* string(<subcommand> <args>) — common subcommands only *)
let parse_string args : L.exp option =
  match args with
  | [ "TOUPPER"; s; out ] when is_bare out ->
    Some (String_cmd (Sc_toupper { string = arg_of_raw s; out }))
  | [ "TOLOWER"; s; out ] when is_bare out ->
    Some (String_cmd (Sc_tolower { string = arg_of_raw s; out }))
  | [ "LENGTH"; s; out ] when is_bare out ->
    Some (String_cmd (Sc_length { string = arg_of_raw s; out }))
  | [ "STRIP"; s; out ] when is_bare out ->
    Some (String_cmd (Sc_strip { string = arg_of_raw s; out }))
  | "CONCAT" :: out :: inputs when is_bare out && not (List.is_empty inputs) ->
    Some (String_cmd
            (Sc_concat { out; inputs = List.map inputs ~f:arg_of_raw }))
  | "APPEND" :: var :: inputs when is_bare var && not (List.is_empty inputs) ->
    Some (String_cmd
            (Sc_append { var; inputs = List.map inputs ~f:arg_of_raw }))
  | "PREPEND" :: var :: prefix :: rest when is_bare var ->
    Some (String_cmd
            (Sc_prepend { var; prefix = arg_of_raw prefix;
                          inputs = List.map rest ~f:arg_of_raw }))
  | "REPLACE" :: m :: r :: out :: inputs when is_bare out ->
    Some (String_cmd
            (Sc_replace
               { match_string = arg_of_raw m;
                 replace_string = arg_of_raw r;
                 out;
                 inputs = List.map inputs ~f:arg_of_raw }))
  (* string(FIND <string> <substring> <out> [REVERSE]) *)
  | [ "FIND"; s; sub; out ] when is_bare out ->
    Some (String_cmd
            (Sc_find { string = arg_of_raw s;
                       substring = arg_of_raw sub;
                       out; reverse = false }))
  | [ "FIND"; s; sub; out; "REVERSE" ] when is_bare out ->
    Some (String_cmd
            (Sc_find { string = arg_of_raw s;
                       substring = arg_of_raw sub;
                       out; reverse = true }))
  (* string(SUBSTRING <string> <begin> <length> <out>) — length is int or -1. *)
  | [ "SUBSTRING"; s; b; l; out ] when is_bare out ->
    (match Int.of_string_opt b, Int.of_string_opt l with
     | Some begin_, Some length when length = -1 ->
       Some (String_cmd
               (Sc_substring { string = arg_of_raw s; begin_;
                               length = None; out }))
     | Some begin_, Some length ->
       Some (String_cmd
               (Sc_substring { string = arg_of_raw s; begin_;
                               length = Some length; out }))
     | _ -> None)
  (* string(COMPARE <op> <s1> <s2> <out>) *)
  | [ "COMPARE"; op; s1; s2; out ] when is_bare out ->
    let op = match op with
      | "LESS" -> Some L.Sco_less
      | "GREATER" -> Some Sco_greater
      | "EQUAL" -> Some Sco_equal
      | "NOTEQUAL" -> Some Sco_notequal
      | "LESS_EQUAL" -> Some Sco_less_equal
      | "GREATER_EQUAL" -> Some Sco_greater_equal
      | _ -> None
    in
    (match op with
     | Some op ->
       Some (String_cmd
               (Sc_compare { op;
                             string1 = arg_of_raw s1;
                             string2 = arg_of_raw s2;
                             out }))
     | None -> None)
  (* string(MAKE_C_IDENTIFIER <string> <out>) *)
  | [ "MAKE_C_IDENTIFIER"; s; out ] when is_bare out ->
    Some (String_cmd
            (Sc_make_c_identifier { string = arg_of_raw s; out }))
  (* string(HEX <string> <out>) *)
  | [ "HEX"; s; out ] when is_bare out ->
    Some (String_cmd (Sc_hex { string = arg_of_raw s; out }))
  (* string(GENEX_STRIP <string> <out>) *)
  | [ "GENEX_STRIP"; s; out ] when is_bare out ->
    Some (String_cmd
            (Sc_genex_strip { string = arg_of_raw s; out }))
  (* string(JOIN <glue> <out> <input>...) *)
  | "JOIN" :: glue :: out :: inputs when is_bare out ->
    Some (String_cmd
            (Sc_join { glue = arg_of_raw glue; out;
                       inputs = List.map inputs ~f:arg_of_raw }))
  (* string(TIMESTAMP <out> [<format>] [UTC]) — format must be quoted. *)
  | "TIMESTAMP" :: out :: rest when is_bare out ->
    let format = ref None in
    let utc = ref false in
    let ok = ref true in
    let rec go = function
      | [] -> ()
      | "UTC" :: r when not !utc -> utc := true; go r
      | f :: r when Option.is_none !format ->
        (match arg_of_raw f with
         | Quoted s -> format := Some s; go r
         | _ -> ok := false)
      | _ -> ok := false
    in
    go rest;
    if not !ok then None
    else Some (String_cmd
                 (Sc_timestamp { out; format = !format; utc = !utc }))
  (* string(REGEX MATCH/MATCHALL/REPLACE/QUOTE ...) *)
  | "REGEX" :: "MATCH" :: regex :: out :: inputs when is_bare out ->
    (match arg_of_raw regex with
     | Quoted re ->
       Some (String_cmd
               (Sc_regex (Sr_match { regex = re; out;
                                     inputs = List.map inputs ~f:arg_of_raw })))
     | _ -> None)
  | "REGEX" :: "MATCHALL" :: regex :: out :: inputs when is_bare out ->
    (match arg_of_raw regex with
     | Quoted re ->
       Some (String_cmd
               (Sc_regex (Sr_matchall { regex = re; out;
                                        inputs = List.map inputs ~f:arg_of_raw })))
     | _ -> None)
  | "REGEX" :: "REPLACE" :: regex :: replace :: out :: inputs when is_bare out ->
    (match arg_of_raw regex with
     | Quoted re ->
       Some (String_cmd
               (Sc_regex (Sr_replace
                            { regex = re;
                              replace = arg_of_raw replace;
                              out;
                              inputs = List.map inputs ~f:arg_of_raw })))
     | _ -> None)
  | _ -> None

(* ============================================================
   Stage 2-c — more builtins. Same bail-on-lossy discipline.

   Deliberately NOT typed in this stage (printer is lossy or
   shape complexity outweighs the typed-coverage win):
     - set_property / get_property — printer drops most IR fields
     - execute_process — multi-line shape, hard to invert safely
     - file — too many subcommand IRs; pick a few easy ones only

   These flow through generic Apply, preserving the call byte-faithfully.
   ============================================================ *)

(* return() | return(PROPAGATE <var>...) *)
let parse_return args : L.exp option =
  if not (all_bare args) then None
  else match args with
    | [] -> Some (Return { propogate_vars = [] })
    | "PROPAGATE" :: vars when not (List.is_empty vars) ->
      Some (Return { propogate_vars = vars })
    | _ -> None

(* include_directories([AFTER|BEFORE] [SYSTEM] <dir>...).
   Printer emits `include_directories(<ba><sys> dir dirs)` with
   [ba]/[sys] keywords or empty. We only accept the no-keyword form
   to dodge tree-sitter argument re-ordering and avoid emitting the
   leading-empty-space shape on extra keywords. *)
let parse_include_directories args : L.exp option =
  if not (all_bare args) then None
  else
  (* Consume optional [AFTER|BEFORE] prefix, then optional SYSTEM. cmake
     spec puts both at the front, matching the printer's emission order. *)
  let before_or_after, args =
    match args with
    | "BEFORE" :: r -> L.Before, r
    | "AFTER" :: r -> L.After, r
    | _ -> L.Default_order, args
  in
  let system, args =
    match args with
    | "SYSTEM" :: r -> true, r
    | _ -> false, args
  in
  match args with
  | first :: rest_dirs
    when not (List.mem ["AFTER"; "BEFORE"; "SYSTEM"] first ~equal:String.equal) ->
    Some (Project_cmd
            (Include_directories
               { before_or_after; system; dir = first; dirs = rest_dirs }))
  | _ -> None

(* find_program(<var> NAMES <n>...) or find_program(<var> <name>).
   IR distinguishes the two surface forms via [short_form] (added
   2026-05-25). HINTS/PATHS/PATH_SUFFIXES/DOC/etc. still bail. *)
let parse_find_var_names ctor args : L.exp option =
  let reserved =
    ["NAMES";"HINTS";"PATHS";"PATH_SUFFIXES";"DOC";"NO_CACHE";
     "NO_DEFAULT_PATH";"NO_PACKAGE_ROOT_PATH";"NO_CMAKE_PATH";
     "NO_CMAKE_ENVIRONMENT_PATH";"NO_SYSTEM_ENVIRONMENT_PATH";
     "NO_CMAKE_SYSTEM_PATH";"NO_CMAKE_INSTALL_PREFIX";
     "REGISTRY_VIEW";"REQUIRED"]
  in
  let mk var names short_form ~hints ~paths ~path_suffixes ~doc ~required
      ~no_cache ~no_default_path ~no_package_root_path ~no_cmake_path
      ~no_cmake_environment_path ~no_system_environment_path
      ~no_cmake_system_path ~no_cmake_install_prefix =
    Some (ctor
            { L.var;
              names = List.map names ~f:arg_of_raw;
              short_form;
              hints = List.map hints ~f:arg_of_raw;
              paths = List.map paths ~f:arg_of_raw;
              path_suffixes;
              doc;
              required;
              no_cache; no_default_path;
              no_package_root_path; no_cmake_path;
              no_cmake_environment_path;
              no_system_environment_path;
              no_cmake_system_path;
              no_cmake_install_prefix })
  in
  (* Group keyword-prefixed sections. Returns (positional_prefix, groups)
     where positional_prefix is what comes before the first reserved kw,
     and groups is [(kw, args_until_next_kw); ...]. *)
  let split_keyword_groups tokens =
    let is_kw t = List.mem reserved t ~equal:String.equal in
    let rec gather_prefix acc = function
      | [] -> List.rev acc, []
      | t :: rest when is_kw t -> List.rev acc, t :: rest
      | t :: rest -> gather_prefix (t :: acc) rest
    in
    let rec gather_groups = function
      | [] -> []
      | kw :: rest ->
        let body, tail = gather_prefix [] rest in
        (kw, body) :: gather_groups tail
    in
    let prefix, kw_tail = gather_prefix [] tokens in
    prefix, gather_groups kw_tail
  in
  match args with
  | var :: rest ->
    let prefix, groups = split_keyword_groups rest in
    (* Positional name(s): either a single bare name (short form) OR
       NAMES n1 n2 ... (long form). *)
    let names_opt, short_form =
      match prefix, List.find groups ~f:(fun (k, _) -> String.equal k "NAMES") with
      | [ name ], None -> Some [name], true
      | [], Some (_, names) when not (List.is_empty names) -> Some names, false
      | _ -> None, false
    in
    (match names_opt with
     | None -> None
     | Some names ->
       let find_group kw =
         List.find_map groups ~f:(fun (k, v) ->
           if String.equal k kw then Some v else None)
       in
       let hints = Option.value (find_group "HINTS") ~default:[] in
       let paths = Option.value (find_group "PATHS") ~default:[] in
       let path_suffixes = Option.value (find_group "PATH_SUFFIXES") ~default:[] in
       let doc =
         Option.bind (find_group "DOC") ~f:List.hd
         |> Option.map ~f:str_of_raw
       in
       let has_kw kw =
         List.exists groups ~f:(fun (k, _) -> String.equal k kw)
       in
       (* Refuse on any NO_* search-modifier — the printer always
          emits these AFTER PATH_SUFFIXES, but cmake source freely
          interleaves them between NAMES/HINTS/PATHS. Reordering
          breaks the bar3-lite STRUCT byte-equality oracle. Falling
          back to Apply preserves the source token order verbatim.
          REQUIRED is fine: cmake convention always puts it last
          anyway. *)
       let no_kws =
         ["NO_CACHE"; "NO_DEFAULT_PATH"; "NO_PACKAGE_ROOT_PATH";
          "NO_CMAKE_PATH"; "NO_CMAKE_ENVIRONMENT_PATH";
          "NO_SYSTEM_ENVIRONMENT_PATH"; "NO_CMAKE_SYSTEM_PATH";
          "NO_CMAKE_INSTALL_PREFIX"]
       in
       if List.exists no_kws ~f:has_kw then None
       else
       let required = has_kw "REQUIRED" in
       mk var names short_form ~hints ~paths ~path_suffixes ~doc
         ~required ~no_cache:false ~no_default_path:false
         ~no_package_root_path:false
         ~no_cmake_path:false ~no_cmake_environment_path:false
         ~no_system_environment_path:false ~no_cmake_system_path:false
         ~no_cmake_install_prefix:false)
  | _ -> None

let parse_find_program args = parse_find_var_names (fun a -> L.Find_program a) args
let parse_find_path args = parse_find_var_names (fun a -> L.Find_path a) args

(* try_compile(<resultVar> [<bindir>]
               SOURCES src1 [src2 ...]
               [COMPILE_DEFINITIONS ...] [LINK_LIBRARIES ...]
               [LINK_OPTIONS ...] [OUTPUT_VARIABLE outvar]
               [NO_CACHE] [C_STANDARD n] [CXX_STANDARD n])

   Only the new keyword-style signature is parsed. The legacy
   try_compile(<resultVar> <bindir> <srcfile> ...) form is left to
   the Apply fallback — fmt and modern cmake projects use the new
   form. result_var (first positional arg) is the only required
   piece; everything else is optional groups. *)
let parse_try_compile args : L.exp option =
  let kws =
    [ "SOURCES"; "COMPILE_DEFINITIONS"; "LINK_LIBRARIES"; "LINK_OPTIONS";
      "CMAKE_FLAGS"; "OUTPUT_VARIABLE"; "COPY_FILE"; "COPY_FILE_ERROR";
      "C_STANDARD"; "CXX_STANDARD"; "C_STANDARD_REQUIRED";
      "CXX_STANDARD_REQUIRED"; "C_EXTENSIONS"; "CXX_EXTENSIONS";
      "OBJC_STANDARD"; "OBJCXX_STANDARD";
      "PROJECT"; "TARGET"; "SOURCE_FROM_CONTENT"; "SOURCE_FROM_VAR";
      "SOURCE_FROM_FILE"; "LOG_DESCRIPTION"; "NO_CACHE";
      "NO_LOG"; "WORKING_DIRECTORY" ]
  in
  let is_kw t = List.mem kws t ~equal:String.equal in
  let split_groups tokens =
    let rec gather acc = function
      | [] -> List.rev acc, []
      | t :: rest when is_kw t -> List.rev acc, t :: rest
      | t :: rest -> gather (t :: acc) rest
    in
    let rec groups = function
      | [] -> []
      | kw :: rest ->
        let body, tail = gather [] rest in
        (kw, body) :: groups tail
    in
    let prefix, kw_tail = gather [] tokens in
    prefix, groups kw_tail
  in
  match args with
  | result_var :: rest ->
    let prefix, groups = split_groups rest in
    (* prefix is whatever non-keyword tokens followed result_var.
       In the new signature this is the optional [<bindir>] — at
       most one positional arg. More than one means a malformed or
       legacy call; bail to Apply. *)
    let bindir_opt =
      match prefix with
      | [] -> Some None
      | [ b ] -> Some (Some (arg_of_raw b))
      | _ -> None
    in
    (match bindir_opt with
     | None -> None
     | Some bindir ->
       let find_group kw =
         List.find_map groups ~f:(fun (k, v) ->
           if String.equal k kw then Some v else None)
       in
       let group_args kw =
         Option.value (find_group kw) ~default:[]
         |> List.map ~f:arg_of_raw
       in
       let sources = group_args "SOURCES" in
       let compile_definitions = group_args "COMPILE_DEFINITIONS" in
       let link_libraries = group_args "LINK_LIBRARIES" in
       let link_options = group_args "LINK_OPTIONS" in
       let cmake_flags = group_args "CMAKE_FLAGS" in
       let output_variable =
         Option.bind (find_group "OUTPUT_VARIABLE") ~f:List.hd
       in
       let no_cache = List.exists groups ~f:(fun (k, _) ->
         String.equal k "NO_CACHE") in
       let c_standard =
         Option.bind (find_group "C_STANDARD") ~f:List.hd
       in
       let cxx_standard =
         Option.bind (find_group "CXX_STANDARD") ~f:List.hd
       in
       Some (L.Project_cmd (L.Try_compile
         { tc_result_var = result_var;
           tc_bindir = bindir;
           tc_sources = sources;
           tc_compile_definitions = compile_definitions;
           tc_link_libraries = link_libraries;
           tc_link_options = link_options;
           tc_cmake_flags = cmake_flags;
           tc_output_variable = output_variable;
           tc_copy_file = None;
           tc_no_cache = no_cache;
           tc_c_standard = c_standard;
           tc_cxx_standard = cxx_standard })))
  | _ -> None

(* add_custom_command(TARGET <t> PRE_BUILD|PRE_LINK|POST_BUILD COMMAND <prog> <args>...)
   The TARGET form (Add_custom_command_target). Bail on COMMENT/VERBATIM/
   USES_TERMINAL keywords and on multiple COMMAND blocks. *)
let parse_add_custom_command args : L.exp option =
  match args with
  | "TARGET" :: target :: when_s :: "COMMAND" :: rest
    when is_bare target
         && List.mem ["PRE_BUILD"; "PRE_LINK"; "POST_BUILD"]
              when_s ~equal:String.equal ->
    (* All of rest must be plain args with no further COMMAND or trailing
       keywords. *)
    if List.exists rest ~f:(fun a ->
      List.mem ["COMMAND"; "COMMENT"; "VERBATIM"; "USES_TERMINAL"]
        a ~equal:String.equal)
    then None
    else (match rest with
      | [] -> None
      | prog :: cmd_args when is_bare prog && List.for_all cmd_args ~f:is_bare ->
        let when_ = match when_s with
          | "PRE_BUILD" -> L.Cw_pre_build
          | "PRE_LINK" -> L.Cw_pre_link
          | _ -> L.Cw_post_build
        in
        Some (Project_cmd
                (Add_custom_command_target
                   { target; when_;
                     commands = [ { command = prog; args = cmd_args } ];
                     comment = None;
                     verbatim = false; uses_terminal = false }))
      | _ -> None)
  | _ -> None

(* file(<subcommand> <args>) — pick safe forms. Bail on subcommands with
   keyword-heavy IR (READ/STRINGS/COPY/DOWNLOAD/UPLOAD/LOCK/etc.) *)
let parse_file args : L.exp option =
  match args with
  | "WRITE" :: file :: content when not (List.is_empty content) ->
    Some (File_write { file = arg_of_raw file; append = false;
                       content = List.map content ~f:arg_of_raw })
  | "APPEND" :: file :: content when not (List.is_empty content) ->
    Some (File_write { file = arg_of_raw file; append = true;
                       content = List.map content ~f:arg_of_raw })
  | "MAKE_DIRECTORY" :: dirs when not (List.is_empty dirs) ->
    Some (File_make_directory { dirs = List.map dirs ~f:arg_of_raw })
  | "REMOVE" :: files when not (List.is_empty files) ->
    Some (File_remove { files = List.map files ~f:arg_of_raw; recurse = false })
  | "REMOVE_RECURSE" :: files when not (List.is_empty files) ->
    Some (File_remove { files = List.map files ~f:arg_of_raw; recurse = true })
  | "TOUCH" :: files when not (List.is_empty files) ->
    Some (File_touch { files = List.map files ~f:arg_of_raw; nocreate = false })
  | "TOUCH_NOCREATE" :: files when not (List.is_empty files) ->
    Some (File_touch { files = List.map files ~f:arg_of_raw; nocreate = true })
  | "GLOB" :: var :: patterns
    when is_bare var
         && List.for_all patterns ~f:(fun p ->
              not (List.mem ["CONFIGURE_DEPENDS"; "RELATIVE"; "LIST_DIRECTORIES";
                             "FOLLOW_SYMLINKS"] p ~equal:String.equal)) ->
    Some (File_glob { var; recurse = false;
                      relative = None; configure_depends = false;
                      patterns = List.map patterns ~f:arg_of_raw })
  | "GLOB_RECURSE" :: var :: patterns
    when is_bare var
         && List.for_all patterns ~f:(fun p ->
              not (List.mem ["CONFIGURE_DEPENDS"; "RELATIVE"; "LIST_DIRECTORIES";
                             "FOLLOW_SYMLINKS"] p ~equal:String.equal)) ->
    Some (File_glob { var; recurse = true;
                      relative = None; configure_depends = false;
                      patterns = List.map patterns ~f:arg_of_raw })
  (* file(READ <file> <var> [OFFSET <n>] [LIMIT <n>] [HEX]) — IR fields
     and printer agree on `file`-before-`var`. *)
  | "READ" :: file :: var :: rest when is_bare var ->
    let offset = ref None in
    let limit = ref None in
    let hex = ref false in
    let ok = ref true in
    let rec go = function
      | [] -> ()
      | "OFFSET" :: n :: r ->
        (match Int.of_string_opt n with
         | Some i when Option.is_none !offset -> offset := Some i; go r
         | _ -> ok := false)
      | "LIMIT" :: n :: r ->
        (match Int.of_string_opt n with
         | Some i when Option.is_none !limit -> limit := Some i; go r
         | _ -> ok := false)
      | "HEX" :: r when not !hex -> hex := true; go r
      | _ -> ok := false
    in
    go rest;
    if not !ok then None
    else Some (File_read { var; file = arg_of_raw file;
                           offset = !offset; limit = !limit; hex = !hex })
  (* file(RELATIVE_PATH <var> <base> <file>) *)
  | [ "RELATIVE_PATH"; var; base; file ] when is_bare var ->
    Some (File_relative_path { var; base; file })
  (* file(RENAME <old> <new> [RESULT <v>] [NO_REPLACE]) *)
  | "RENAME" :: old_ :: new_ :: rest ->
    let result = ref None in
    let no_replace = ref false in
    let ok = ref true in
    let rec go = function
      | [] -> ()
      | "RESULT" :: v :: r when is_bare v && Option.is_none !result ->
        result := Some v; go r
      | "NO_REPLACE" :: r when not !no_replace -> no_replace := true; go r
      | _ -> ok := false
    in
    go rest;
    if not !ok then None
    else Some (File_rename { old_ = arg_of_raw old_;
                             new_ = arg_of_raw new_;
                             result = !result;
                             no_replace = !no_replace })
  (* file(COPY_FILE <input> <output> [RESULT <v>] [ONLY_IF_DIFFERENT]) *)
  | "COPY_FILE" :: input :: output :: rest ->
    let result = ref None in
    let only_if_different = ref false in
    let ok = ref true in
    let rec go = function
      | [] -> ()
      | "RESULT" :: v :: r when is_bare v && Option.is_none !result ->
        result := Some v; go r
      | "ONLY_IF_DIFFERENT" :: r when not !only_if_different ->
        only_if_different := true; go r
      | _ -> ok := false
    in
    go rest;
    if not !ok then None
    else Some (File_copy_file { input = arg_of_raw input;
                                output = arg_of_raw output;
                                result = !result;
                                only_if_different = !only_if_different })
  (* file(REAL_PATH <path> <var> [BASE_DIRECTORY <dir>] [EXPAND_TILDE]) *)
  | "REAL_PATH" :: path :: var :: rest when is_bare var ->
    let base_dir = ref None in
    let expand_tilde = ref false in
    let ok = ref true in
    let rec go = function
      | [] -> ()
      | "BASE_DIRECTORY" :: d :: r when Option.is_none !base_dir ->
        base_dir := Some (arg_of_raw d); go r
      | "EXPAND_TILDE" :: r when not !expand_tilde ->
        expand_tilde := true; go r
      | _ -> ok := false
    in
    go rest;
    if not !ok then None
    else Some (File_real_path { var; path = arg_of_raw path;
                                base_dir = !base_dir;
                                expand_tilde = !expand_tilde })
  (* file(SIZE <file> <var>) *)
  | [ "SIZE"; file; var ] when is_bare var ->
    Some (File_size { var; file = arg_of_raw file })
  (* file(READ_SYMLINK <link> <var>) *)
  | [ "READ_SYMLINK"; link; var ] when is_bare var ->
    Some (File_read_symlink { var; link = arg_of_raw link })
  (* file(TIMESTAMP <file> <var> [<format>] [UTC]).
     Format must be quoted in source (printer emits quoted). *)
  | "TIMESTAMP" :: file :: var :: rest when is_bare var ->
    let format = ref None in
    let utc = ref false in
    let ok = ref true in
    let rec go = function
      | [] -> ()
      | "UTC" :: r when not !utc -> utc := true; go r
      | f :: r when Option.is_none !format ->
        (match arg_of_raw f with
         | Quoted s -> format := Some s; go r
         | _ -> ok := false)
      | _ -> ok := false
    in
    go rest;
    if not !ok then None
    else Some (File_timestamp { var; file = arg_of_raw file;
                                format = !format; utc = !utc })
  (* file(STRINGS <file> <var> [REGEX <r>] [ENCODING <e>] [LIMIT_COUNT <n>]).
     Printer emits the three keywords in this fixed order; source must
     match or we bail (same kind of rank-based check as execute_process).
     Bails on the other keywords (LENGTH_MAXIMUM, NEWLINE_CONSUME, etc.)
     that the IR doesn't carry. *)
  | "STRINGS" :: file :: var :: rest when is_bare var ->
    let regex = ref None in
    let encoding = ref None in
    let limit_count = ref None in
    let ok = ref true in
    let last_rank = ref (-1) in
    let unmodeled = ["LENGTH_MAXIMUM"; "LENGTH_MINIMUM"; "LIMIT_INPUT";
                     "LIMIT_OUTPUT"; "NEWLINE_CONSUME"; "NO_HEX_CONVERSION";
                     "ECHO_OUTPUT_VARIABLE"] in
    let kw_rank = function
      | "REGEX" -> 0 | "ENCODING" -> 1 | "LIMIT_COUNT" -> 2
      | _ -> 99
    in
    let check_order kw =
      let r = kw_rank kw in
      if r < !last_rank then false
      else (last_rank := r; true)
    in
    let rec go = function
      | [] -> ()
      | kw :: _ when List.mem unmodeled kw ~equal:String.equal -> ok := false
      | kw :: _ when not (check_order kw) -> ok := false
      | "REGEX" :: r :: rest_args ->
        (* printer emits %S (quoted), so source must be quoted. *)
        (match arg_of_raw r with
         | Quoted s when Option.is_none !regex -> regex := Some s; go rest_args
         | _ -> ok := false)
      | "ENCODING" :: e :: r when is_bare e && Option.is_none !encoding ->
        encoding := Some e; go r
      | "LIMIT_COUNT" :: n :: r ->
        (match Int.of_string_opt n with
         | Some i when Option.is_none !limit_count -> limit_count := Some i; go r
         | _ -> ok := false)
      | _ -> ok := false
    in
    go rest;
    if not !ok then None
    else Some (File_strings { var; file = arg_of_raw file;
                              regex = !regex; encoding = !encoding;
                              limit_count = !limit_count })
  | _ -> None

(* set_property(<SCOPE> [APPEND] [APPEND_STRING] PROPERTY <name> [<value>...]).
   SCOPE is one of GLOBAL / DIRECTORY [<dir>] / TARGET <t>... /
   SOURCE <src>... [DIRECTORY <dir>...] [TARGET_DIRECTORY <t>...] /
   INSTALL <f>... / TEST <test>... [DIRECTORY <dir>...] / CACHE <e>...

   IR + printer redesigned 2026-05-29 to surface scope as a sum type. *)

(* execute_process(COMMAND <cmd1> [<args>...]
                    [COMMAND <cmd2> [<args>...]]...
                    [WORKING_DIRECTORY <dir>] [TIMEOUT <s>]
                    [RESULT_VARIABLE <v>] [OUTPUT_VARIABLE <v>]
                    [ERROR_VARIABLE <v>] [INPUT_FILE <f>]
                    [OUTPUT_FILE <f>] [ERROR_FILE <f>]
                    [OUTPUT_QUIET] [ERROR_QUIET]
                    [OUTPUT_STRIP_TRAILING_WHITESPACE]
                    [ERROR_STRIP_TRAILING_WHITESPACE]
                    [COMMAND_ERROR_IS_FATAL <ANY|LAST|NONE>]).

   Bails on the unmodeled keywords RESULTS_VARIABLE / COMMAND_ECHO /
   ENCODING / ECHO_OUTPUT_VARIABLE / ECHO_ERROR_VARIABLE — IR doesn't
   carry them. *)
let parse_execute_process args : L.exp option =
  let is_top_kw = function
    | "COMMAND" | "WORKING_DIRECTORY" | "TIMEOUT"
    | "RESULT_VARIABLE" | "OUTPUT_VARIABLE" | "ERROR_VARIABLE"
    | "INPUT_FILE" | "OUTPUT_FILE" | "ERROR_FILE"
    | "OUTPUT_QUIET" | "ERROR_QUIET"
    | "OUTPUT_STRIP_TRAILING_WHITESPACE"
    | "ERROR_STRIP_TRAILING_WHITESPACE"
    | "COMMAND_ERROR_IS_FATAL"
    | "RESULTS_VARIABLE" | "COMMAND_ECHO" | "ENCODING"
    | "ECHO_OUTPUT_VARIABLE" | "ECHO_ERROR_VARIABLE" -> true
    | _ -> false
  in
  let bail_kw = function
    | "RESULTS_VARIABLE" | "COMMAND_ECHO" | "ENCODING"
    | "ECHO_OUTPUT_VARIABLE" | "ECHO_ERROR_VARIABLE" -> true
    | _ -> false
  in
  (* Printer-canonical keyword order (see Execute_process arm in
     lang_cmake_pp.ml). Source must follow this order or the typed
     reprint will rearrange args, breaking STRUCT. Multiple COMMAND
     blocks share rank 0; the rest of the keywords follow in fixed
     positions. *)
  let kw_rank = function
    | "COMMAND" -> 0
    | "WORKING_DIRECTORY" -> 1
    | "TIMEOUT" -> 2
    | "RESULT_VARIABLE" -> 3
    | "OUTPUT_VARIABLE" -> 4
    | "ERROR_VARIABLE" -> 5
    | "INPUT_FILE" -> 6
    | "OUTPUT_FILE" -> 7
    | "ERROR_FILE" -> 8
    | "OUTPUT_QUIET" -> 9
    | "ERROR_QUIET" -> 10
    | "OUTPUT_STRIP_TRAILING_WHITESPACE" -> 11
    | "ERROR_STRIP_TRAILING_WHITESPACE" -> 12
    | "COMMAND_ERROR_IS_FATAL" -> 13
    | _ -> 99
  in
  let last_rank = ref (-1) in
  let check_order kw =
    let r = kw_rank kw in
    (* COMMAND can repeat; everything else strictly non-decreasing. *)
    if String.equal kw "COMMAND" then
      (if !last_rank > 0 then false
       else (last_rank := 0; true))
    else if r < !last_rank then false
    else (last_rank := r; true)
  in
  let commands = ref [] in
  let working_directory = ref None in
  let timeout = ref None in
  let result_variable = ref None in
  let output_variable = ref None in
  let error_variable = ref None in
  let input_file = ref None in
  let output_file = ref None in
  let error_file = ref None in
  let output_quiet = ref false in
  let error_quiet = ref false in
  let output_strip = ref false in
  let error_strip = ref false in
  let command_error_is_fatal = ref None in
  let ok = ref true in
  let take_until_kw rest =
    let rec loop acc = function
      | [] -> List.rev acc, []
      | t :: _ as r when is_top_kw t -> List.rev acc, r
      | t :: r -> loop (t :: acc) r
    in
    loop [] rest
  in
  let rec go = function
    | [] -> ()
    | kw :: _ when not !ok ->
      ignore kw
    | kw :: _ when bail_kw kw -> ok := false
    | kw :: _ when not (check_order kw) -> ok := false
    | "COMMAND" :: r ->
      let cmd, r = take_until_kw r in
      if List.is_empty cmd then ok := false
      else (commands := cmd :: !commands; go r)
    | "WORKING_DIRECTORY" :: d :: r when not (is_top_kw d) ->
      working_directory := Some (arg_of_raw d); go r
    | "TIMEOUT" :: t :: r when not (is_top_kw t) ->
      (match Float.of_string_opt t with
       | Some f -> timeout := Some f; go r
       | None -> ok := false)
    | "RESULT_VARIABLE" :: v :: r when is_bare v ->
      result_variable := Some v; go r
    | "OUTPUT_VARIABLE" :: v :: r when is_bare v ->
      output_variable := Some v; go r
    | "ERROR_VARIABLE" :: v :: r when is_bare v ->
      error_variable := Some v; go r
    | "INPUT_FILE" :: f :: r when not (is_top_kw f) ->
      input_file := Some (arg_of_raw f); go r
    | "OUTPUT_FILE" :: f :: r when not (is_top_kw f) ->
      output_file := Some (arg_of_raw f); go r
    | "ERROR_FILE" :: f :: r when not (is_top_kw f) ->
      error_file := Some (arg_of_raw f); go r
    | "OUTPUT_QUIET" :: r -> output_quiet := true; go r
    | "ERROR_QUIET" :: r -> error_quiet := true; go r
    | "OUTPUT_STRIP_TRAILING_WHITESPACE" :: r ->
      output_strip := true; go r
    | "ERROR_STRIP_TRAILING_WHITESPACE" :: r ->
      error_strip := true; go r
    | "COMMAND_ERROR_IS_FATAL" :: m :: r
      when List.mem ["ANY"; "LAST"; "NONE"] m ~equal:String.equal ->
      command_error_is_fatal := Some m; go r
    | _ -> ok := false
  in
  go args;
  if not !ok || List.is_empty !commands then None
  else
    Some (Execute_process
            { commands = List.rev !commands
                         |> List.map ~f:(List.map ~f:arg_of_raw);
              working_directory = !working_directory;
              timeout = !timeout;
              result_variable = !result_variable;
              output_variable = !output_variable;
              error_variable = !error_variable;
              input_file = !input_file;
              output_file = !output_file;
              error_file = !error_file;
              output_quiet = !output_quiet;
              error_quiet = !error_quiet;
              output_strip_trailing_whitespace = !output_strip;
              error_strip_trailing_whitespace = !error_strip;
              command_error_is_fatal = !command_error_is_fatal })

(* get_property(<var> <SCOPE> PROPERTY <name> [SET|DEFINED|BRIEF_DOCS|FULL_DOCS]).
   Single-valued scope (TARGET <t>, SOURCE <src>, etc.); paired with the
   redesign at lang_cmake.ml `get_property_scope`. *)
let parse_get_property args : L.exp option =
  if not (all_bare args) then None
  else
  match args with
  | var :: rest ->
    let parse_scope = function
      | "GLOBAL" :: r -> Some (L.Gps_global, r)
      | "VARIABLE" :: r -> Some (L.Gps_variable, r)
      | "DIRECTORY" :: r ->
        let dir, r = match r with
          | d :: rr when not (String.equal d "PROPERTY") -> Some d, rr
          | _ -> None, r
        in
        Some (L.Gps_directory dir, r)
      | "TARGET" :: t :: r -> Some (L.Gps_target t, r)
      | "INSTALL" :: f :: r -> Some (L.Gps_install f, r)
      | "TEST" :: t :: r ->
        let directory, r = match r with
          | "DIRECTORY" :: d :: rr -> Some d, rr
          | _ -> None, r
        in
        Some (L.Gps_test { test = t; directory }, r)
      | "CACHE" :: e :: r -> Some (L.Gps_cache e, r)
      | "SOURCE" :: s :: r ->
        let directory, target_directory, r = match r with
          | "DIRECTORY" :: d :: rr -> Some d, None, rr
          | "TARGET_DIRECTORY" :: t :: rr -> None, Some t, rr
          | _ -> None, None, r
        in
        Some (L.Gps_source { source = s; directory; target_directory }, r)
      | _ -> None
    in
    (match parse_scope rest with
     | None -> None
     | Some (scope, rest) ->
       (match rest with
        | "PROPERTY" :: property :: mode_args ->
          let mode = match mode_args with
            | [] -> Some L.Gpm_value
            | [ "SET" ] -> Some L.Gpm_set
            | [ "DEFINED" ] -> Some L.Gpm_defined
            | [ "BRIEF_DOCS" ] -> Some L.Gpm_brief_docs
            | [ "FULL_DOCS" ] -> Some L.Gpm_full_docs
            | _ -> None
          in
          (match mode with
           | None -> None
           | Some mode ->
             Some (Get_property { var; scope; property_name = property; mode }))
        | _ -> None))
  | _ -> None

let parse_set_property args : L.exp option =
  if not (all_bare args) then None
  else
  (* Helper: split sub-arglist on inner keyword [stop_kw] (used inside
     SOURCE/TEST sub-clauses), returning prefix and suffix. *)
  let rec split_at kws = function
    | [] -> [], []
    | t :: rest when List.mem kws t ~equal:String.equal -> [], t :: rest
    | t :: rest ->
      let a, b = split_at kws rest in t :: a, b
  in
  (* Consume the scope clause from the head of [args]. Returns
     (scope, remaining_args) on success. *)
  let parse_scope = function
    | "GLOBAL" :: rest -> Some (L.Sps_global, rest)
    | "DIRECTORY" :: rest ->
      let dir, rest =
        match rest with
        | d :: r when not (List.mem ["APPEND"; "APPEND_STRING"; "PROPERTY"]
                             d ~equal:String.equal) ->
          Some d, r
        | _ -> None, rest
      in
      Some (L.Sps_directory dir, rest)
    | "TARGET" :: rest ->
      let targets, rest =
        split_at ["APPEND"; "APPEND_STRING"; "PROPERTY"] rest
      in
      if List.is_empty targets then None
      else Some (L.Sps_target targets, rest)
    | "SOURCE" :: rest ->
      let sources, rest =
        split_at ["DIRECTORY"; "TARGET_DIRECTORY";
                  "APPEND"; "APPEND_STRING"; "PROPERTY"] rest
      in
      if List.is_empty sources then None
      else
        let directories, rest =
          match rest with
          | "DIRECTORY" :: r ->
            let ds, r =
              split_at ["TARGET_DIRECTORY";
                        "APPEND"; "APPEND_STRING"; "PROPERTY"] r
            in
            ds, r
          | _ -> [], rest
        in
        let target_directories, rest =
          match rest with
          | "TARGET_DIRECTORY" :: r ->
            let ts, r =
              split_at ["APPEND"; "APPEND_STRING"; "PROPERTY"] r
            in
            ts, r
          | _ -> [], rest
        in
        Some (L.Sps_source { sources; directories; target_directories }, rest)
    | "INSTALL" :: rest ->
      let files, rest =
        split_at ["APPEND"; "APPEND_STRING"; "PROPERTY"] rest
      in
      if List.is_empty files then None
      else Some (L.Sps_install files, rest)
    | "TEST" :: rest ->
      let tests, rest =
        split_at ["DIRECTORY"; "APPEND"; "APPEND_STRING"; "PROPERTY"] rest
      in
      if List.is_empty tests then None
      else
        let directories, rest =
          match rest with
          | "DIRECTORY" :: r ->
            let ds, r = split_at ["APPEND"; "APPEND_STRING"; "PROPERTY"] r in
            ds, r
          | _ -> [], rest
        in
        Some (L.Sps_test { tests; directories }, rest)
    | "CACHE" :: _ ->
      (* cache_entry IR is the placeholder type Cache_entry with no
         per-entry data — round-tripping via Apply preserves the source
         exactly, which is the safer option until cache_entry carries
         names. *)
      None
    | _ -> None
  in
  match parse_scope args with
  | None -> None
  | Some (scope, rest) ->
    let append, rest = match rest with
      | "APPEND" :: r -> true, r | _ -> false, rest
    in
    let append_string, rest = match rest with
      | "APPEND_STRING" :: r -> true, r | _ -> false, rest
    in
    (match rest with
     | "PROPERTY" :: property :: values ->
       Some (Set_property
               { scope; append; append_string;
                 property;
                 values = List.map values ~f:arg_of_raw })
     | _ -> None)

(* install(TARGETS <t>... [EXPORT <name>] DESTINATION <d>) — simple form *)
let parse_install args : L.exp option =
  match args with
  | "TARGETS" :: rest ->
    (* Targets, optional EXPORT, then DESTINATION. *)
    let rec take_targets acc = function
      | [] -> None
      | t :: r when is_bare t
                    && not (List.mem ["EXPORT";"DESTINATION";"COMPONENT";
                                      "RENAME";"PERMISSIONS";"OPTIONAL";
                                      "NAMELINK_SKIP";"NAMELINK_ONLY";
                                      "INCLUDES";"ARCHIVE";"LIBRARY";"RUNTIME";
                                      "OBJECTS";"FRAMEWORK";"BUNDLE";"PUBLIC_HEADER";
                                      "PRIVATE_HEADER";"RESOURCE";"FILE_SET";"CXX_MODULES_BMI"]
                            t ~equal:String.equal) ->
        take_targets (t :: acc) r
      | r -> Some (List.rev acc, r)
    in
    (match take_targets [] rest with
     | Some (targets, rest) when not (List.is_empty targets) ->
       let export, rest =
         match rest with
         | "EXPORT" :: e :: r when is_bare e -> Some e, r
         | _ -> None, rest
       in
       (* Parse a sequence of per-kind artifact clauses, then an optional
          top-level DESTINATION. Per-kind sub-options (PERMISSIONS,
          COMPONENT, etc.) cause bail until the IR carries them. *)
       let kind_of = function
         | "ARCHIVE" -> Some L.Iak_archive
         | "LIBRARY" -> Some Iak_library
         | "RUNTIME" -> Some Iak_runtime
         | "OBJECTS" -> Some Iak_objects
         | "FRAMEWORK" -> Some Iak_framework
         | "BUNDLE" -> Some Iak_bundle
         | "PUBLIC_HEADER" -> Some Iak_public_header
         | "PRIVATE_HEADER" -> Some Iak_private_header
         | "RESOURCE" -> Some Iak_resource
         | "CXX_MODULES_BMI" -> Some Iak_cxx_modules_bmi
         | _ -> None
       in
       let rec take_clauses acc rest =
         match rest with
         | [] -> Some (List.rev acc, None, [])
         | "DESTINATION" :: d :: r ->
           (* Top-level DESTINATION; should be terminal. *)
           Some (List.rev acc, Some (arg_of_raw d), r)
         | "FILE_SET" :: name :: "DESTINATION" :: d :: r when is_bare name ->
           take_clauses
             ({ L.kind = Iak_file_set name;
                destination = Some (arg_of_raw d) } :: acc) r
         | "FILE_SET" :: name :: r when is_bare name ->
           take_clauses
             ({ L.kind = Iak_file_set name; destination = None } :: acc) r
         | kw :: "DESTINATION" :: d :: r ->
           (match kind_of kw with
            | Some k ->
              take_clauses
                ({ L.kind = k; destination = Some (arg_of_raw d) } :: acc) r
            | None -> None)
         | kw :: r ->
           (match kind_of kw with
            | Some k ->
              take_clauses
                ({ L.kind = k; destination = None } :: acc) r
            | None -> None)
       in
       (match take_clauses [] rest with
        | Some (artifact_clauses, top_dest, []) ->
          (* Need at least one of: top-level DESTINATION, any
             artifact-clause with DESTINATION. *)
          let has_any_dest =
            Option.is_some top_dest
            || List.exists artifact_clauses
                 ~f:(fun c -> Option.is_some c.destination)
          in
          if not has_any_dest then None
          else
            Some (Project_cmd
                    (Install_targets
                       { targets;
                         destination = top_dest;
                         artifact_clauses;
                         component = None; rename = None; export;
                         permissions = [] }))
        | _ -> None)
     | _ -> None)
  | "FILES" :: rest ->
    let rec take_files acc = function
      | [] -> None
      | f :: r when not (List.mem ["DESTINATION";"COMPONENT";"RENAME";
                                   "PERMISSIONS";"OPTIONAL";"CONFIGURATIONS"]
                           f ~equal:String.equal) ->
        take_files (f :: acc) r
      | r -> Some (List.rev acc, r)
    in
    (match take_files [] rest with
     | Some (files, [ "DESTINATION"; dest ]) when not (List.is_empty files) ->
       Some (Project_cmd
               (Install_files
                  { files = List.map files ~f:arg_of_raw;
                    destination = arg_of_raw dest;
                    component = None; rename = None;
                    permissions = [] }))
     | _ -> None)
  | _ -> None

(* ============================================================
   Dispatch
   ============================================================ *)

let parse_cmd (c : cmd) : L.exp option =
  (* cmake commands are case-insensitive *at runtime*, but the
     typed-then-reprint cycle always emits the lowercase canonical
     form, so `SET(...)` would round-trip as `set(...)`. Bail for
     anything not already lowercase; those flow through Apply and
     preserve the source casing. *)
  let name = c.name in
  if not (String.equal name (String.lowercase name)) then None
  else
  match name with
  | "cmake_minimum_required" -> parse_cmake_minimum_required c.args
  | "project" -> parse_project c.args
  | "set" -> parse_set c.args
  | "message" -> parse_message c.args
  | "configure_file" -> parse_configure_file c.args
  | "add_executable" -> parse_add_executable c.args
  | "add_library" -> parse_add_library c.args
  | "target_link_libraries" -> parse_target_link_libraries c.args
  | "target_include_directories" -> parse_target_include_directories c.args
  | "target_compile_definitions" -> parse_target_compile_definitions c.args
  | "target_compile_options" -> parse_target_compile_options c.args
  | "target_compile_features" -> parse_target_compile_features c.args
  | "option" -> parse_option c.args
  | "include" -> parse_include c.args
  | "add_subdirectory" -> parse_add_subdirectory c.args
  (* Stage 2-b *)
  | "unset" -> parse_unset c.args
  | "add_dependencies" -> parse_add_dependencies c.args
  | "find_package" -> parse_find_package c.args
  | "try_compile" -> parse_try_compile c.args
  | "get_filename_component" -> parse_get_filename_component c.args
  | "set_target_properties" -> parse_set_target_properties c.args
  | "add_custom_target" -> parse_add_custom_target c.args
  | "list" -> parse_list c.args
  | "string" -> parse_string c.args
  (* Stage 2-c *)
  | "return" -> parse_return c.args
  | "include_directories" -> parse_include_directories c.args
  | "find_program" -> parse_find_program c.args
  | "find_path" -> parse_find_path c.args
  | "install" -> parse_install c.args
  | "add_custom_command" -> parse_add_custom_command c.args
  | "file" -> parse_file c.args
  (* Tier 2 *)
  | "set_property" -> parse_set_property c.args
  | "get_property" -> parse_get_property c.args
  | "execute_process" -> parse_execute_process c.args
  | _ -> None
