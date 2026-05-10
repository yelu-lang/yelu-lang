open Base
open Yelu_tiny

let name = "tiny_cmake_file"
let requires = [ "core.string"; "path" ]
let provides = [ "file.write"; "file.read"; "file.exists" ]

type expr +=
  | ECmakeFileWrite of { path : expr; content : expr list }
  | ECmakeFileRead of { path : expr; out : string }
  | ECmakeFileExists of expr

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
  | _ -> None
