(* Stage 1 prototype: read tree-sitter CST JSON from stdin, reprint cmake.

   Untyped AST — each command's args are raw source text (preserving
   quoting / bracket framing). Reprinting is `name(arg1 arg2 ...)`.
   Indentation handled trivially (2 spaces per nesting level); gersemi
   normalizes whitespace, so as long as we emit the right commands in
   the right order with the right args, round-trip via gersemi should
   be byte-identical. *)

open Base

(* ============================================================
   AST
   ============================================================ *)

type cmd = {
  name : string;
  args : string list;
}

type stmt =
  | Cmd of cmd
  | Block of {
      block_type : string;  (* "if" / "foreach" / "while" / "function" / "macro" / "block" *)
      head : cmd;
      body : stmt list;
      clauses : (cmd * stmt list) list;
      tail : cmd;
    }
  | Unknown of { ts_type : string; text : string }

(* ============================================================
   JSON -> AST
   ============================================================ *)

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
         | Some h -> cmd_of_json h
         | None -> failwith "block: missing head"
       in
       let body = List.map (json_list_field obj "body") ~f:stmt_of_json in
       let clauses =
         List.map (json_list_field obj "clauses") ~f:(function
           | `Assoc cobj ->
             let head =
               match List.Assoc.find cobj "head" ~equal:String.equal with
               | Some h -> cmd_of_json h
               | None -> failwith "clause: missing head"
             in
             let body =
               List.map (json_list_field cobj "body") ~f:stmt_of_json
             in
             (head, body)
           | _ -> failwith "clause: expected object")
       in
       let tail =
         match List.Assoc.find obj "tail" ~equal:String.equal with
         | Some t -> cmd_of_json t
         | None -> failwith "block: missing tail"
       in
       Block { block_type; head; body; clauses; tail }
     | "unknown" ->
       Unknown {
         ts_type = json_string_field obj "type";
         text = json_string_field obj "text";
       }
     | other -> failwith (Printf.sprintf "stmt_of_json: unknown kind %s" other))
  | _ -> failwith "stmt_of_json: expected object"

let file_of_json = function
  | `Assoc obj ->
    (match List.Assoc.find obj "kind" ~equal:String.equal with
     | Some (`String "source_file") -> ()
     | _ -> failwith "file_of_json: expected kind=source_file");
    List.map (json_list_field obj "stmts") ~f:stmt_of_json
  | _ -> failwith "file_of_json: expected object"

(* ============================================================
   AST -> cmake text
   ============================================================ *)

let print_cmd { name; args } =
  Printf.sprintf "%s(%s)" name (String.concat ~sep:" " args)

let indent depth = String.make (depth * 2) ' '

let rec print_stmt ~depth buf = function
  | Cmd c ->
    Buffer.add_string buf (indent depth);
    Buffer.add_string buf (print_cmd c);
    Buffer.add_char buf '\n'
  | Block { head; body; clauses; tail; _ } ->
    Buffer.add_string buf (indent depth);
    Buffer.add_string buf (print_cmd head);
    Buffer.add_char buf '\n';
    List.iter body ~f:(print_stmt ~depth:(depth + 1) buf);
    List.iter clauses ~f:(fun (chead, cbody) ->
      Buffer.add_string buf (indent depth);
      Buffer.add_string buf (print_cmd chead);
      Buffer.add_char buf '\n';
      List.iter cbody ~f:(print_stmt ~depth:(depth + 1) buf));
    Buffer.add_string buf (indent depth);
    Buffer.add_string buf (print_cmd tail);
    Buffer.add_char buf '\n'
  | Unknown { ts_type; text } ->
    Buffer.add_string buf (indent depth);
    Buffer.add_string buf
      (Printf.sprintf "# unknown(%s): %s\n" ts_type
         (String.substr_replace_all text ~pattern:"\n" ~with_:"\\n"))

let print_file stmts =
  let buf = Buffer.create 1024 in
  List.iter stmts ~f:(print_stmt ~depth:0 buf);
  Buffer.contents buf

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

(* Tiny JSON parser substitute: shell out to `python3 -c "import json,sys;
   json.load(sys.stdin)"` is silly. Use Yojson if available; otherwise
   parse the minimal shape ourselves. For Stage 1, depend on Yojson. *)

let () =
  let json_str = read_all_stdin () in
  let json = Yojson.Safe.from_string json_str in
  let stmts = file_of_json json in
  Stdlib.print_string (print_file stmts)
