open Base
open Yelu_cmake_ir

let name = "tiny_cmake_file"
let requires = [ "core.string"; "path" ]
let provides = [ "file.write"; "file.read"; "file.exists" ]

type expr +=
  | ECmakeFileWrite of { path : expr; content : expr list }
  | ECmakeFileWriteAppend of { path : expr; content : expr list }
  | ECmakeFileRead of { path : expr; out : string }
  | ECmakeFileReadFull of {
      path : expr;
      out : string;
      offset : int option;
      limit : int option;
      hex : bool;
    }
  | ECmakeFileExists of expr
  | ECmakeConfigureFile of { input : expr; output : expr }
  (* [file(RELATIVE_PATH <var> <base> <file>)]. Eval stub: binds var to
     [file] string (no path-relative computation in tiny). *)
  | ECmakeFileRelativePath of { var : string; base : expr; file : expr }
  (* [file(GLOB[_RECURSE] <out> [RELATIVE <relative>] [CONFIGURE_DEPENDS]
     <patterns>...)]. Eval stub: binds [out] to the empty list — actual
     directory enumeration happens at cmake configure time. *)
  | ECmakeFileGlob of {
      out : string;
      recurse : bool;
      relative : expr option;
      configure_depends : bool;
      patterns : expr list;
    }
  (* Additional file() subcommands — emit-faithful, eval-stub. *)
  | ECmakeFileStrings of {
      out : string;
      path : expr;
      regex : string option;
      encoding : string option;
      limit_count : int option;
    }
  | ECmakeFileTouch of { files : expr list; nocreate : bool }
  | ECmakeFileMakeDirectory of { dirs : expr list }
  | ECmakeFileRename of {
      old_ : expr; new_ : expr;
      result : string option; no_replace : bool
    }
  | ECmakeFileRemove of { files : expr list; recurse : bool }
  | ECmakeFileCopy of {
      input : expr; output : expr;
      result : string option; only_if_different : bool
    }
  | ECmakeFileRealPath of {
      out : string; path : expr; base_dir : expr option; expand_tilde : bool
    }
  | ECmakeFileSize of { out : string; path : expr }
  | ECmakeFileReadSymlink of { out : string; link : expr }
  | ECmakeFileTimestamp of {
      out : string; path : expr; format : string option; utc : bool
    }

let eval_string ~eval env expr =
  let env, value = eval env expr in
  env, expect_string value

let eval_strings ~eval env exprs =
  List.fold exprs ~init:(env, []) ~f:(fun (env, rev_strings) expr ->
    let env, string = eval_string ~eval env expr in
    env, string :: rev_strings)
  |> fun (env, rev_strings) -> env, List.rev rev_strings

let eval_case ~eval env = function
  | ECmakeFileWrite { path; content } ->
    let env, path = eval_string ~eval env path in
    let env, content = eval_strings ~eval env content in
    Some (set_file env ~path ~content:(String.concat content), VUnit)
  | ECmakeFileRead { path; out } ->
    let env, path = eval_string ~eval env path in
    (match find_file env path with
     | Some content -> Some (set_var env ~key:out ~data:(VString content), VUnit)
     | None -> fail "file does not exist in tiny fs: %S" path)
  | ECmakeFileExists path ->
    let env, path = eval_string ~eval env path in
    Some (env, VBool (file_exists env path))
  | ECmakeConfigureFile { input; output } ->
    let env, input = eval_string ~eval env input in
    let env, output = eval_string ~eval env output in
    let content =
      match find_file env input with
      | Some c -> c
      | None -> ""
    in
    Some (set_file env ~path:output ~content, VUnit)
  | ECmakeFileRelativePath { var; base = _; file } ->
    let env, file = eval_string ~eval env file in
    Some (set_var env ~key:var ~data:(VString file), VUnit)
  | ECmakeFileGlob { out; _ } ->
    Some (set_var env ~key:out ~data:(VString ""), VUnit)
  (* Additional file() subcommands — eval stubs. Where a result/out var
     exists, we bind it to a placeholder so callers can still read it. *)
  | ECmakeFileWriteAppend { path; content } ->
    let env, path = eval_string ~eval env path in
    let env, content = eval_strings ~eval env content in
    let existing = Option.value (find_file env path) ~default:"" in
    Some (set_file env ~path ~content:(existing ^ String.concat content), VUnit)
  | ECmakeFileReadFull { path; out; _ } ->
    let env, path = eval_string ~eval env path in
    (match find_file env path with
     | Some content ->
       Some (set_var env ~key:out ~data:(VString content), VUnit)
     | None ->
       Some (set_var env ~key:out ~data:(VString ""), VUnit))
  | ECmakeFileStrings { out; _ } ->
    Some (set_var env ~key:out ~data:(VString ""), VUnit)
  | ECmakeFileTouch _ | ECmakeFileMakeDirectory _ | ECmakeFileRemove _ ->
    Some (env, VUnit)
  | ECmakeFileRename { result; _ } | ECmakeFileCopy { result; _ } ->
    (match result with
     | Some var -> Some (set_var env ~key:var ~data:(VString "0"), VUnit)
     | None -> Some (env, VUnit))
  | ECmakeFileRealPath { out; path; _ } ->
    let env, path = eval_string ~eval env path in
    Some (set_var env ~key:out ~data:(VString path), VUnit)
  | ECmakeFileSize { out; _ } ->
    Some (set_var env ~key:out ~data:(VInt 0), VUnit)
  | ECmakeFileReadSymlink { out; link } ->
    let env, link = eval_string ~eval env link in
    Some (set_var env ~key:out ~data:(VString link), VUnit)
  | ECmakeFileTimestamp { out; _ } ->
    Some (set_var env ~key:out ~data:(VString ""), VUnit)
  | _ -> None
