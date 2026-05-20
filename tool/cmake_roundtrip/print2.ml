(* cmake_roundtrip: typed mapping of Stage-1 untyped cmake AST into
   [Lang_cmake.exp], then reprint via [Lang_cmake_pp].

   Pipeline:
     stdin (Stage-1 JSON from parse.py)
       -> file_of_json     (this file)
       -> parse_cmd        (per-command Lang_cmake.exp when modeled)
       -> Lang_cmake_pp.pp (production cmake printer)
       -> untyped_emit     (verbatim fallback for un-modeled commands)
     stdout: reprinted cmake

   For each Stage-1 [Cmd], [parse_cmd] returns [Some Lang_cmake.exp]
   when the command is one of the modeled builtins, else [None]. The
   None branch routes to [untyped_emit] which constructs a real
   [Lang_cmake.Apply { name; args }] and reprints via the production
   [Lang_cmake_pp] Apply arm. This is the "generic" bucket in
   coverage tallies — correct destination for project- or
   module-defined cmake calls like z3_add_component, tablegen, the
   add_llvm_* family.

   Block shapes (if / foreach / while / function / macro / block)
   walk recursively. The body is a nested statement list reprinted
   by the same dispatcher (modeled / generic / other recursively
   apply). Block heads and tails are NOT dispatched through
   [parse_cmd] today — they're reprinted by [print_block_head] as
   raw `name(args)` text. They contribute to neither the modeled
   nor generic counts; the `other` bucket counts the block wrapper
   node itself (one per block), not its head/tail. Body commands
   inside blocks still count toward modeled / generic via
   recursive walk.

   The byte-equality oracle: tree-sitter on both source and reprint
   must extract the same (command_name, arg-list) sequence (STRUCT),
   and gersemi-normalized both sides must match modulo
   whitespace/comment layout (FORMAT). Both held at 0 across
   tutorial + z3 + llvm as of Stage 2-c. *)

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

let raw_of_arg (a : L.arg) : string =
  match a with
  | Bare s -> s
  | Quoted s -> "\"" ^ s ^ "\""
  | Bracket (level, s) ->
    let eqs = String.make level '=' in
    "[" ^ eqs ^ "[" ^ s ^ "]" ^ eqs ^ "]"

let _ = raw_of_arg  (* might be needed for fallback paths later *)

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

(* add_dependencies(<target> <dep>...) — IR carries one dep at a time *)
let parse_add_dependencies args : L.exp option =
  if not (all_bare args) then None
  else
  match args with
  | [ target; dep ] ->
    Some (Project_cmd (Add_dependencies { target; dep }))
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

(* set_target_properties(<target> PROPERTIES <k> <v> [<k> <v>]...) *)
let parse_set_target_properties args : L.exp option =
  match args with
  | target :: "PROPERTIES" :: rest when is_bare target ->
    (* Parse remaining as key/value pairs. Keys must be bare; values
       can be quoted. *)
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
               (Set_target_properties { target; properties })))
  | _ -> None

(* add_custom_target(<name> [ALL] [DEPENDS <dep>...]).
   IR has many fields; we support only the minimal form (name + optional
   ALL + optional DEPENDS list of bare deps). Bail on COMMAND, BYPRODUCTS,
   WORKING_DIRECTORY, etc. — any unknown keyword routes to generic Apply. *)
let parse_add_custom_target args : L.exp option =
  match args with
  | name :: rest when is_bare name ->
    let all, rest =
      match rest with "ALL" :: r -> true, r | _ -> false, rest
    in
    let depends =
      match rest with
      | [] -> Some []
      | "DEPENDS" :: deps when List.for_all deps ~f:is_bare -> Some deps
      | _ -> None
    in
    (match depends with
     | None -> None
     | Some depends ->
       Some (Project_cmd
               (Add_custom_target
                  { name; all;
                    commands = []; depends; byproducts = [];
                    working_directory = None; comment = None;
                    job_pool = []; job_server_aware = false;
                    verbatim = false; uses_terminal = false;
                    command_expand_list = []; sources = [] })))
  | _ -> None

(* list(<subcommand> <args>) — dispatch on subcommand *)
let parse_list args : L.exp option =
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
  else match args with
    | first :: rest_dirs
      when not (List.mem ["AFTER"; "BEFORE"; "SYSTEM"] first ~equal:String.equal) ->
      Some (Project_cmd
              (Include_directories
                 { before_or_after = Default_order;
                   system = false;
                   dir = first;
                   dirs = rest_dirs }))
    | _ -> None

(* find_program(<var> NAMES <n>...) — explicit NAMES form only.
   Printer always emits NAMES, so the bare `find_program(VAR name)`
   shape can't be typed without restructuring. Bail on HINTS/PATHS/
   PATH_SUFFIXES/DOC/etc. *)
let parse_find_var_names ctor args : L.exp option =
  if not (all_bare args) then None
  else match args with
    | var :: "NAMES" :: names when not (List.is_empty names) ->
      let required = List.mem names "REQUIRED" ~equal:String.equal in
      (* If REQUIRED is in the names list, it has to be at the end and
         we strip it. Otherwise printer reorder risk. *)
      let names, ok = match List.rev names with
        | "REQUIRED" :: rest -> List.rev rest, true
        | _ -> names, not required
      in
      if not ok || List.exists names ~f:(fun n ->
        List.mem ["HINTS";"PATHS";"PATH_SUFFIXES";"DOC";"NO_CACHE";
                  "NO_DEFAULT_PATH";"NO_PACKAGE_ROOT_PATH";"NO_CMAKE_PATH";
                  "NO_CMAKE_ENVIRONMENT_PATH";"NO_SYSTEM_ENVIRONMENT_PATH";
                  "NO_CMAKE_SYSTEM_PATH";"NO_CMAKE_INSTALL_PREFIX";
                  "REGISTRY_VIEW"] n ~equal:String.equal)
      then None
      else
        Some (ctor
                { L.var;
                  names = List.map names ~f:arg_of_raw;
                  hints = []; paths = []; path_suffixes = [];
                  doc = None;
                  required;
                  no_cache = false; no_default_path = false;
                  no_package_root_path = false; no_cmake_path = false;
                  no_cmake_environment_path = false;
                  no_system_environment_path = false;
                  no_cmake_system_path = false;
                  no_cmake_install_prefix = false })
    | _ -> None

let parse_find_program args = parse_find_var_names (fun a -> L.Find_program a) args
let parse_find_path args = parse_find_var_names (fun a -> L.Find_path a) args

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
  | _ -> None

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
       (match rest with
        | [ "DESTINATION"; dest ] ->
          Some (Project_cmd
                  (Install_targets
                     { targets;
                       destination = arg_of_raw dest;
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
  | _ -> None

(* ============================================================
   Emit: walk Stage-1 AST; typed commands -> Lang_cmake_pp;
   others -> Stage-1 raw emission.
   ============================================================ *)

let pp_exp_to_string (e : L.exp) : string =
  (* Default formatter line width is 80, which causes [Fmt.sp]
     break hints in arms like [Apply] / multi-arg builtins to wrap
     long calls across lines. For the round-trip oracle we want
     single-line output everywhere; gersemi handles the wrap
     downstream (or on the comparison side). Set both max_indent
     and margin to a large value — Format clamps margin to
     max_indent if you only set one. *)
  let buf = Buffer.create 256 in
  let ff = Stdlib.Format.formatter_of_buffer buf in
  Stdlib.Format.pp_set_geometry ff ~max_indent:999_999 ~margin:1_000_000;
  Stdlib.Format.fprintf ff "%a%!" Pp.pp e;
  Buffer.contents buf

let indent depth = String.make (depth * 2) ' '

(* Generic call-by-name. Route un-modeled commands through the real
   [Lang_cmake.Apply] constructor and the production [Lang_cmake_pp]
   Apply printer so the generic path exercises the same IR shape as
   modeled commands. [pp_exp_to_string] sets margin/max-indent high to
   avoid incidental wrapping where the printer permits it, but the
   production Apply printer may still choose a multi-line layout for
   some argument-list shapes. *)
let untyped_emit (c : cmd) : string =
  let args = List.map c.args ~f:arg_of_raw in
  pp_exp_to_string (L.Apply { name = c.name; args })

(* Block heads/tails are not currently dispatched through [parse_cmd]:
   they're free-form command records bound to a block shape, and the
   block walker reprints them as raw text. The args field is already
   the source's raw token sequence (preserved by [parse.py]), so this
   is byte-faithful — but it does mean a head like `if(FOO STREQUAL
   "bar")` is reprinted with whitespace exactly as tree-sitter laid
   it out, with no typed-IR detour. Live with this until block-head
   typing is needed; the STRUCT oracle catches any drift. *)
let print_block_head { name; args } =
  Printf.sprintf "%s(%s)" name (String.concat ~sep:" " args)

let rec emit_stmt ~depth buf = function
  | Cmd c ->
    let s =
      match parse_cmd c with
      | Some exp -> pp_exp_to_string exp
      | None -> untyped_emit c
    in
    Buffer.add_string buf (indent depth);
    Buffer.add_string buf s;
    if not (String.is_suffix s ~suffix:"\n") then Buffer.add_char buf '\n'
  | Block { head; body; clauses; tail; _ } ->
    Buffer.add_string buf (indent depth);
    Buffer.add_string buf (print_block_head head);
    Buffer.add_char buf '\n';
    List.iter body ~f:(emit_stmt ~depth:(depth + 1) buf);
    List.iter clauses ~f:(fun (chead, cbody) ->
      Buffer.add_string buf (indent depth);
      Buffer.add_string buf (print_block_head chead);
      Buffer.add_char buf '\n';
      List.iter cbody ~f:(emit_stmt ~depth:(depth + 1) buf));
    Buffer.add_string buf (indent depth);
    Buffer.add_string buf (print_block_head tail);
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

(* Coverage tally. Each top-level statement contributes as follows:
   - [Cmd] -> [modeled] if [parse_cmd] returns [Some _], else [generic].
   - [Block] -> [other] += 1 for the wrapper itself. Body and clause
     bodies recurse: contained [Cmd]s contribute to modeled/generic.
     Heads and tails are NOT counted in any bucket (they're reprinted
     by [print_block_head] without dispatch).
   - [Raw] / [Unknown] -> [other] += 1.
   Deliberately no ratio is reported: many generic calls are
   project-defined functions that are correctly never modeled by
   [Lang_cmake.exp]. A modeled / (modeled + generic) ratio would
   conflate "not yet modeled" with "shouldn't be modeled". Raw
   counts are the honest signal. *)
let count_coverage stmts =
  let modeled = ref 0 in
  let generic = ref 0 in
  let other = ref 0 in
  let rec walk = function
    | Cmd c ->
      (match parse_cmd c with
       | Some _ -> Int.incr modeled
       | None -> Int.incr generic)
    | Block { body; clauses; _ } ->
      Int.incr other;
      List.iter body ~f:walk;
      List.iter clauses ~f:(fun (_, b) -> List.iter b ~f:walk)
    | Raw _ | Unknown _ -> Int.incr other
  in
  List.iter stmts ~f:walk;
  !modeled, !generic, !other

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
     let m, g, o = count_coverage stmts in
     Stdlib.Printf.eprintf "[stage2] modeled=%d generic=%d other=%d\n" m g o
   | None -> ());
  Stdlib.print_string (emit stmts)
