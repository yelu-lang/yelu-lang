(* cmake_cache_scan: enumerate every user-settable cmake cache var declared
   in a project.

   Walks every CMakeLists.txt / *.cmake under a project root and
   extracts:
   - option(NAME "help" [default])         -> Option (BOOL, default ON/OFF)
   - set(NAME … CACHE TYPE "help" [FORCE]) -> Cache typed

   Emits TSV to stdout, one decl per line:

     <name>\t<kind>\t<default>\t<help>\t<file>\t<conditional>

   Where:
     <kind>        = OPTION | BOOL | STRING | PATH | FILEPATH | INTERNAL
     <default>     = literal value, or empty if not specified, or
                     a ${VAR} reference (kept verbatim — eval-time)
     <help>        = the doc string, with tabs/newlines stripped
     <file>        = path relative to project root
     <conditional> = "top" if at top level, "<headname>" if inside
                     a block (if / foreach / function / etc.)

   Consumers:
   - Build a -D matrix for an oracle test: every OPTION row →
     ON/OFF flips; every BOOL CACHE row → ON/OFF; STRING CACHE
     rows → use declared default + one alternative.
   - Cross-check against `cmake -B <build> -LAH` after a configure
     run to spot static-vs-dynamic divergence (e.g., options gated
     by a condition the static walker traversed but real cmake
     skipped).

   This is the static side of the path-2 cache-var enumeration
   discussed in the parent session. Dynamic side is `cmake -LAH`.

   Note: reuses cmake_to_json.py via subprocess. Stage-1 AST shape is
   copied from cmake_reprint.ml / cmake_name_index.ml. *)

open Base

(* ============================================================
   Stage-1 AST / JSON reader (copy-paste from cmake_name_index.ml).
   ============================================================ *)

type cmd = { name : string; args : string list }

type stmt =
  | Cmd of cmd
  | Block of {
      block_type : string;
      head : cmd;
      body : stmt list;
      clauses : (cmd * stmt list) list;
      tail : cmd;
    }
  | Raw of string [@warning "-37"]
  | Unknown of { ts_type : string; text : string } [@warning "-37"]

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
   Argument helpers
   ============================================================ *)

(* tree-sitter preserves quoting on args. Strip outer quotes for
   string-typed slots (help, default literal). *)
let unquote s =
  let n = String.length s in
  if n >= 2 && Char.equal s.[0] '"' && Char.equal s.[n - 1] '"' then
    String.sub s ~pos:1 ~len:(n - 2)
  else s

(* Replace tabs / newlines with spaces so the value is TSV-safe. *)
let tsv_safe s =
  String.map s ~f:(fun c ->
    if Char.equal c '\t' || Char.equal c '\n' || Char.equal c '\r'
    then ' ' else c)

(* ============================================================
   Decl extraction
   ============================================================ *)

type kind =
  | Option_
  | Cache of string  (* BOOL | STRING | PATH | FILEPATH | INTERNAL *)

let kind_to_string = function
  | Option_ -> "OPTION"
  | Cache t -> t

type decl = {
  name : string;
  kind : kind;
  default : string;
  help : string;
  file : string;
  conditional : string;
}

(* option(NAME "help" [default])
   default defaults to OFF if not provided. *)
let parse_option args =
  match args with
  | [ name ] -> Some { name; kind = Option_; default = "OFF"; help = ""; file = ""; conditional = "" }
  | [ name; help ] ->
    Some { name; kind = Option_; default = "OFF"; help = unquote help; file = ""; conditional = "" }
  | [ name; help; default ] ->
    Some { name; kind = Option_; default; help = unquote help; file = ""; conditional = "" }
  | _ -> None  (* malformed *)

(* set(NAME value... CACHE TYPE "help" [FORCE])
   The CACHE keyword marker is what distinguishes this from a
   normal set. After CACHE comes <TYPE> then <"docstring"> then
   maybe FORCE. *)
let parse_set_cache args =
  let rec find_cache_pos i = function
    | [] -> None
    | "CACHE" :: rest -> Some (i, rest)
    | _ :: rest -> find_cache_pos (i + 1) rest
  in
  match args with
  | name :: rest ->
    (match find_cache_pos 0 rest with
     | None -> None  (* not a cache set *)
     | Some (vpos, after_cache) ->
       let values = List.take rest vpos in
       let default = String.concat ~sep:" " values in
       (match after_cache with
        | t :: help :: _ ->
          Some { name; kind = Cache t; default;
                 help = unquote help; file = ""; conditional = "" }
        | t :: [] ->
          Some { name; kind = Cache t; default; help = "";
                 file = ""; conditional = "" }
        | [] -> None))
  | [] -> None

(* Walk stmts collecting decls. Tracks the enclosing block as
   [conditional] so a consumer knows the decl might be gated. *)
let collect_decls ~file stmts =
  let decls = ref [] in
  let rec walk ~conditional = function
    | Cmd { name; args } ->
      let add d = decls := { d with file; conditional } :: !decls in
      (match String.lowercase name, args with
       | "option", _ -> Option.iter (parse_option args) ~f:add
       | "set", _ -> Option.iter (parse_set_cache args) ~f:add
       | _ -> ())
    | Block { block_type; head; body; clauses; _ } ->
      let cond_label =
        if String.equal conditional "top"
        then block_type ^ "(" ^ String.concat ~sep:" " head.args ^ ")"
        else conditional ^ " > " ^ block_type
      in
      List.iter body ~f:(walk ~conditional:cond_label);
      List.iter clauses ~f:(fun (_, b) ->
        List.iter b ~f:(walk ~conditional:cond_label))
    | Raw _ | Unknown _ -> ()
  in
  List.iter stmts ~f:(walk ~conditional:"top");
  List.rev !decls

(* ============================================================
   Project walk
   ============================================================ *)

let parse_file ~parse_py path =
  let cmd =
    Printf.sprintf "python3 %s %s 2>/dev/null"
      (Stdlib.Filename.quote parse_py)
      (Stdlib.Filename.quote path)
  in
  let ic = Unix.open_process_in cmd in
  let buf = Buffer.create 4096 in
  let chunk = Bytes.create 4096 in
  (try
     while true do
       let n = Stdlib.input ic chunk 0 (Bytes.length chunk) in
       if n = 0 then raise Stdlib.End_of_file
       else Buffer.add_subbytes buf chunk ~pos:0 ~len:n
     done
   with Stdlib.End_of_file -> ());
  let _ = Unix.close_process_in ic in
  let s = Buffer.contents buf in
  if String.is_empty s then None
  else
    try Some (file_of_json (Yojson.Safe.from_string s))
    with _ -> None

let rec walk_dir dir acc =
  match Stdlib.Sys.readdir dir with
  | exception _ -> acc
  | entries ->
    Array.fold entries ~init:acc ~f:(fun acc entry ->
      let p = Stdlib.Filename.concat dir entry in
      match (Unix.lstat p).st_kind with
      | exception _ -> acc
      | Unix.S_DIR ->
        (* Skip dotdirs and common build / vendor caches *)
        if String.is_prefix entry ~prefix:"."
           || List.mem [ "build"; "_build"; "target"; "node_modules"; "vendor" ]
                entry ~equal:String.equal
        then acc
        else walk_dir p acc
      | Unix.S_REG ->
        if String.equal entry "CMakeLists.txt"
           || (Stdlib.Filename.check_suffix entry ".cmake"
               && not (Stdlib.Filename.check_suffix entry ".cmake.in"))
        then p :: acc
        else acc
      | _ -> acc)

let () =
  let project =
    if Array.length (Sys.get_argv ()) < 2
    then (Stdlib.prerr_endline "usage: cmake_cache_scan <project_dir>"; Stdlib.exit 1)
    else (Sys.get_argv ()).(1)
  in
  let parse_py =
    Stdlib.Filename.concat (Stdlib.Filename.dirname (Sys.get_argv ()).(0)) "cmake_to_json.py"
  in
  let parse_py =
    if Stdlib.Sys.file_exists parse_py then parse_py
    else "tool/cmake_text/cmake_to_json.py"
  in
  let files = walk_dir project [] in
  List.iter files ~f:(fun file ->
    match parse_file ~parse_py file with
    | None -> ()
    | Some stmts ->
      let rel =
        if String.is_prefix file ~prefix:(project ^ "/")
        then String.drop_prefix file (String.length project + 1)
        else file
      in
      let decls = collect_decls ~file:rel stmts in
      List.iter decls ~f:(fun d ->
        (* Skip templated decls inside function()/macro() bodies — the
           name is a formal parameter like ${variable}, not a real
           cache name. Detect by either: name starts with $ (variable
           ref), OR the enclosing block is a function/macro definition. *)
        let is_template =
          String.is_prefix d.name ~prefix:"$"
          || String.is_prefix d.conditional ~prefix:"function("
          || String.is_prefix d.conditional ~prefix:"macro("
        in
        if not is_template then
          Stdlib.Printf.printf "%s\t%s\t%s\t%s\t%s\t%s\n"
            d.name
            (kind_to_string d.kind)
            (tsv_safe d.default)
            (tsv_safe d.help)
            d.file
            d.conditional))
