(* cmake_name_index: build a corpus-level name→def-site index.

   Walks every CMakeLists.txt / *.cmake under a corpus root, runs
   cmake_to_json.py on each, and extracts every function(<name> ...) and
   macro(<name> ...) definition. Emits TSV lines to stdout:

     <name>\t<file-relative-to-corpus>\t<function|macro>

   Use the harness env var `CORPUS_INDEX_FILE=<path>` (set by
   cmake_roundtrip_oracle.sh after running this binary once per corpus) so
   cmake_reprint.exe can tag Apply calls as `resolved` (name is a project-
   defined function/macro) vs `external` (truly unknown).

   This is Class A Phase 1 from doc/yelu_cmake/bar3_lite.md § 6 —
   informational accounting only; no semantic dispatch happens.
   The reprint output is unchanged whether the index is loaded or
   not; only the coverage tally splits the generic bucket more
   informatively.

   Note: this binary reuses cmake_to_json.py via subprocess — the same way
   cmake_roundtrip_oracle.sh does. Keeping the project pass in OCaml so the
   data structure (and future name lookup) can be reused by the
   yelu_cmake interpreter when it lands. *)

open Base

(* ============================================================
   Duplicate the Stage-1 JSON reader from cmake_reprint.ml. (Could share
   via a library; for now copy-paste — small footprint, the harness
   is a prototype.)
   ============================================================ *)

type cmd = { name : string [@warning "-69"]; args : string list }

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
   Definition collection
   ============================================================ *)

(* `function(<name> <params>...)` and `macro(<name> <params>...)`
   define a callable named <name>. cmake names are case-insensitive
   at call time, but the spec is that the table is keyed by the
   declared name verbatim; we lowercase on lookup, not on insert,
   to preserve the source form for diagnostics. *)
let collect_defs ~file stmts =
  let defs = ref [] in
  let rec walk = function
    | Cmd _ -> ()
    | Block { block_type; head; body; clauses; _ } ->
      (match block_type with
       | "function" | "macro" ->
         (match head.args with
          | name :: _ -> defs := (name, file, block_type) :: !defs
          | [] -> ())
       | _ -> ());
      List.iter body ~f:walk;
      List.iter clauses ~f:(fun (_, b) -> List.iter b ~f:walk)
    | Raw _ | Unknown _ -> ()
  in
  List.iter stmts ~f:walk;
  List.rev !defs

(* ============================================================
   Corpus walk
   ============================================================ *)

(* Subprocess: run cmake_to_json.py on a file and read the JSON. Returns
   the AST or None if cmake_to_json.py fails. *)
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

(* Recursively find CMakeLists.txt / *.cmake under a root. cmake
   is case-sensitive for file names on POSIX; we follow suit. *)
let rec walk_dir dir acc =
  match Stdlib.Sys.readdir dir with
  | exception _ -> acc
  | entries ->
    Array.fold entries ~init:acc ~f:(fun acc entry ->
      let p = Stdlib.Filename.concat dir entry in
      match (Unix.lstat p).st_kind with
      | exception _ -> acc
      | Unix.S_DIR -> walk_dir p acc
      | Unix.S_REG ->
        if String.equal entry "CMakeLists.txt"
           || (Stdlib.Filename.check_suffix entry ".cmake"
               && not (Stdlib.Filename.check_suffix entry ".cmake.in"))
        then p :: acc
        else acc
      | _ -> acc)

let () =
  let corpus =
    if Array.length (Sys.get_argv ()) < 2
    then (Stdlib.prerr_endline "usage: cmake_name_index <corpus_dir>"; Stdlib.exit 1)
    else (Sys.get_argv ()).(1)
  in
  let parse_py =
    Stdlib.Filename.concat (Stdlib.Filename.dirname (Sys.get_argv ()).(0)) "cmake_to_json.py"
  in
  let parse_py =
    if Stdlib.Sys.file_exists parse_py then parse_py
    else "tool/cmake_text/cmake_to_json.py"
  in
  let files = walk_dir corpus [] in
  List.iter files ~f:(fun file ->
    match parse_file ~parse_py file with
    | None -> ()
    | Some stmts ->
      let defs = collect_defs ~file stmts in
      List.iter defs ~f:(fun (name, f, kind) ->
        (* Emit relative path so the index is portable across
           machines. Falls back to absolute if the prefix doesn't
           match (e.g. corpus given as a symlink target). *)
        let rel =
          if String.is_prefix f ~prefix:(corpus ^ "/")
          then String.drop_prefix f (String.length corpus + 1)
          else f
        in
        Stdlib.Printf.printf "%s\t%s\t%s\n" name rel kind))
