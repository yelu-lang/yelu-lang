open Base
open Yelu_tiny

let name = "tiny_cmake_file"
let requires = [ "core.string"; "path" ]
let provides = [ "file.write"; "file.read"; "file.exists" ]

type expr +=
  | ECmakeFileWrite of { path : expr; content : expr list }
  | ECmakeFileRead of { path : expr; out : string }
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
  | _ -> None
