open Yelu_cmake

let name = "tiny_file"
let requires = [ "core.string"; "path" ]
let provides = [ "file.write"; "file.read"; "file.exists" ]

type expr +=
  | EFileWrite of { path : expr; content : expr }
  | EFileRead of expr
  | EFileExists of expr
  | EConfigureFile of { input : expr; output : expr; only : bool }

let eval_string ~eval env expr =
  let env, value = eval env expr in
  env, expect_string value

let eval_case ~eval env = function
  | EFileWrite { path; content } ->
    let env, path = eval_string ~eval env path in
    let env, content = eval_string ~eval env content in
    Some (set_file env ~path ~content, VUnit)
  | EFileRead path ->
    let env, path = eval_string ~eval env path in
    (match find_file env path with
     | Some content -> Some (env, VString content)
     | None -> fail "file does not exist in tiny fs: %S" path)
  | EFileExists path ->
    let env, path = eval_string ~eval env path in
    Some (env, VBool (file_exists env path))
  | EConfigureFile { input; output; only = _ } ->
    let env, input = eval_string ~eval env input in
    let env, output = eval_string ~eval env output in
    (* Tiny semantics: copy input content to output if available; otherwise
       record an empty placeholder. Real cmake substitutes ${var} tokens. *)
    let content =
      match find_file env input with
      | Some c -> c
      | None -> ""
    in
    Some (set_file env ~path:output ~content, VUnit)
  | _ -> None
