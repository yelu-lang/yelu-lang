(* Stage 2: typed mapping of Stage-1 untyped cmake AST into
   [Lang_cmake.exp], then reprint via [Lang_cmake_pp].

   Pipeline:
     stdin (Stage-1 JSON)
       -> Stage1.file_of_json    (existing)
       -> typed_map               (per-command Lang_cmake.exp where possible)
       -> Lang_cmake_pp.pp        (existing emitter) for typed commands
       -> Stage-1 text fallback   for un-implemented commands

   For each Stage-1 `Cmd`, we try `parse_cmd` which returns
   `Some Lang_cmake.exp` if the command is in our typed coverage,
   else `None`. Blocks (`if`/`foreach`/`while`/`function`/`macro`/
   `block`) currently fall through to Stage-1 emission (their head /
   body / tail are emitted as separate text chunks); typed
   block mapping is a Stage 2-b expansion.

   The goal is the same byte-equality oracle as Stage 1: after
   gersemi normalization on both sides, output == input. *)

open Base
module L = Yelu_langs.Lang_cmake
module Pp = Yelu_langs.Lang_cmake_pp

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
    (* match [=*[...]=*] *)
    let rec count_eq i =
      if i < n && Char.equal s.[i] '=' then count_eq (i + 1) else i - 1
    in
    let eq_count = count_eq 1 - 0 in
    if eq_count >= 0 && eq_count < n - 1
       && Char.equal s.[eq_count + 1] '['
       && Char.equal s.[n - eq_count - 2] ']'
       && Char.equal s.[n - 1] ']'
    then
      let body_pos = eq_count + 2 in
      let body_len = n - 2 * (eq_count + 2) in
      Bracket (String.sub s ~pos:body_pos ~len:body_len)
    else
      Bare s
  else
    Bare s

let raw_of_arg (a : L.arg) : string =
  match a with
  | Bare s -> s
  | Quoted s -> "\"" ^ s ^ "\""
  | Bracket s -> "[==[" ^ s ^ "]==]"

let _ = raw_of_arg  (* might be needed for fallback paths later *)

(* Treat an arg as a plain string for slots that take [string] /
   [var] / [target] / [file] etc. Strips outer quoting / brackets. *)
let str_of_raw (s : string) : string =
  match arg_of_raw s with
  | Bare s | Quoted s | Bracket s -> s

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

(* cmake_minimum_required(VERSION <min>[...<max>]) *)
let parse_cmake_minimum_required args : L.exp option =
  if not (all_bare args) then None
  else
  match args with
  | [ "VERSION"; v ] ->
    let min_s, max_s =
      match String.substr_index v ~pattern:"..." with
      | None -> (v, None)
      | Some i ->
        let lo = String.sub v ~pos:0 ~len:i in
        let hi = String.sub v ~pos:(i + 3) ~len:(String.length v - i - 3) in
        (lo, Some hi)
    in
    (match version_of_string_opt min_s with
     | None -> None
     | Some min ->
       let max =
         match max_s with
         | None -> Some None
         | Some s ->
           (match version_of_string_opt s with
            | None -> None | Some v -> Some (Some v))
       in
       (match max with
        | None -> None
        | Some max ->
          Some (Cmake_cmd (Cmake_minimum_required { min; max }))))
  | _ -> None

(* project(<name> [VERSION <v>] [LANGUAGES <langs>]) *)
let parse_project args : L.exp option =
  (* All slots map to [string]; bail on any quoting. *)
  if not (all_bare args) then None
  else
  let rec split_keywords acc_name version langs = function
    | [] -> Some (acc_name, version, List.rev langs)
    | "VERSION" :: v :: rest -> split_keywords acc_name (Some v) langs rest
    | "LANGUAGES" :: rest ->
      let langs = List.rev_append (List.rev rest) langs in
      Some (acc_name, version, List.rev langs)
    | "DESCRIPTION" :: _ :: rest | "HOMEPAGE_URL" :: _ :: rest ->
      split_keywords acc_name version langs rest
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

(* set(<var> <value>... [PARENT_SCOPE]) — only the simple form. *)
let parse_set args : L.exp option =
  match args with
  | var :: rest when not (String.is_prefix var ~prefix:"\"") ->
    let parent_scope, values =
      match List.rev rest with
      | "PARENT_SCOPE" :: rev_rest -> true, List.rev rev_rest
      | _ -> false, rest
    in
    Some (Set { var = str_of_raw var;
                values = List.map values ~f:arg_of_raw;
                parent_scope })
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

(* add_executable(<name> <sources>...) — only the regular form; aliases
   and imported go through a separate ctor. name/sources are typed
   [string]; bail if any arg is quoted to preserve source form. *)
let parse_add_executable args : L.exp option =
  if not (all_bare args) then None
  else
  match args with
  | name :: sources when not (List.is_empty sources) ->
    if List.exists sources ~f:(fun s ->
        List.mem [ "ALIAS"; "IMPORTED" ] s ~equal:String.equal)
    then None
    else
      Some (Project_cmd
              (Add_executable
                 { name; options = []; sources }))
  | _ -> None

(* add_library(<name> [STATIC|SHARED|...] [EXCLUDE_FROM_ALL] <sources>) *)
let library_types = [ "STATIC"; "SHARED"; "MODULE"; "INTERFACE"; "OBJECT"; "UNKNOWN" ]

let parse_add_library args : L.exp option =
  if not (all_bare args) then None
  else
  match args with
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
  | _ -> None

(* ============================================================
   Emit: walk Stage-1 AST; typed commands -> Lang_cmake_pp;
   others -> Stage-1 raw emission.
   ============================================================ *)

let pp_exp_to_string (e : L.exp) : string =
  Stdlib.Format.asprintf "%a" Pp.pp e

let print_stage1_cmd { name; args } =
  Printf.sprintf "%s(%s)" name (String.concat ~sep:" " args)

let indent depth = String.make (depth * 2) ' '

(* Generic call-by-name. Used for unrecognized commands: user-defined
   functions (function(...) endfunction()), user-defined macros, and
   cmake-module functions (check_symbol_exists etc., defined by
   include(SomeModule)). [Lang_cmake.Apply] already has the exact
   shape we need; its eval is lenient about unresolved names. *)
let untyped_to_apply (c : cmd) : L.exp =
  Apply { name = c.name; args = List.map c.args ~f:arg_of_raw }

let rec emit_stmt ~depth buf = function
  | Cmd c ->
    let exp =
      match parse_cmd c with
      | Some exp -> exp
      | None -> untyped_to_apply c
    in
    Buffer.add_string buf (indent depth);
    Buffer.add_string buf (pp_exp_to_string exp);
    if not (String.is_suffix (pp_exp_to_string exp) ~suffix:"\n")
    then Buffer.add_char buf '\n'
  | Block { head; body; clauses; tail; _ } ->
    Buffer.add_string buf (indent depth);
    Buffer.add_string buf (print_stage1_cmd head);
    Buffer.add_char buf '\n';
    List.iter body ~f:(emit_stmt ~depth:(depth + 1) buf);
    List.iter clauses ~f:(fun (chead, cbody) ->
      Buffer.add_string buf (indent depth);
      Buffer.add_string buf (print_stage1_cmd chead);
      Buffer.add_char buf '\n';
      List.iter cbody ~f:(emit_stmt ~depth:(depth + 1) buf));
    Buffer.add_string buf (indent depth);
    Buffer.add_string buf (print_stage1_cmd tail);
    Buffer.add_char buf '\n'
  | Raw text ->
    Buffer.add_string buf text;
    if not (String.is_suffix text ~suffix:"\n") then Buffer.add_char buf '\n'
  | Unknown { ts_type; text } ->
    Buffer.add_string buf (indent depth);
    Buffer.add_string buf
      (Printf.sprintf "# unknown(%s): %s\n" ts_type
         (String.substr_replace_all text ~pattern:"\n" ~with_:"\\n"))

let emit stmts =
  let buf = Buffer.create 1024 in
  List.iter stmts ~f:(emit_stmt ~depth:0 buf);
  Buffer.contents buf

(* ============================================================
   Coverage report (optional, via env var)
   ============================================================ *)

(* Coverage tally. Every cmd now lands somewhere typed:
   - [typed]: a per-command Lang_cmake.exp ctor (full builtin shape)
   - [generic]: Apply { name; args } — user-defined / module-defined
                call. AST-carried, not semantically typed.
   - [other]: block heads/tails + raw passthrough + unknown CST. *)
let count_coverage stmts =
  let typed = ref 0 in
  let generic = ref 0 in
  let other = ref 0 in
  let rec walk = function
    | Cmd c ->
      (match parse_cmd c with
       | Some _ -> Int.incr typed
       | None -> Int.incr generic)
    | Block { body; clauses; _ } ->
      Int.incr other;
      List.iter body ~f:walk;
      List.iter clauses ~f:(fun (_, b) -> List.iter b ~f:walk)
    | Raw _ | Unknown _ -> Int.incr other
  in
  List.iter stmts ~f:walk;
  !typed, !generic, !other

(* ============================================================
   Driver
   ============================================================ *)

let read_all_stdin () =
  let buf = Buffer.create 4096 in
  let chunk = Bytes.create 4096 in
  let rec loop () =
    let n = Stdlib.input Stdlib.stdin chunk 0 (Bytes.length chunk) in
    if n > 0 then (Buffer.add_subbytes buf chunk ~pos:0 ~len:n; loop ())
  in
  loop ();
  Buffer.contents buf

let () =
  let json_str = read_all_stdin () in
  let json = Yojson.Safe.from_string json_str in
  let stmts = file_of_json json in
  (match Sys.getenv "STAGE2_COVERAGE" with
   | Some _ ->
     let t, g, o = count_coverage stmts in
     Stdlib.Printf.eprintf "[stage2] typed=%d generic=%d other=%d\n" t g o
   | None -> ());
  Stdlib.print_string (emit stmts)
