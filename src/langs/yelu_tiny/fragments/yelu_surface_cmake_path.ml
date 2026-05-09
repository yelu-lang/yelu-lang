open Base
open Yelu_tiny

let name = "tiny_cmake_path"
let requires = [ "core.string" ]
let provides = [ "path.set"; "path.filename"; "path.normalize" ]

type expr +=
  | ECmakePathSet of { path : string; input : expr; normalize : bool }
  | ECmakePathGetFilename of { path : string; out : string }
  | ECmakePathNormalPath of { path : string; out : string option }

let eval_string ~eval env expr =
  let env, value = eval env expr in
  env, expect_string value

let path_value env name =
  match find_var env name with
  | Some value -> expect_string value
  | None -> fail "unbound path variable %S" name

let eval_case ~eval env = function
  | ECmakePathSet { path; input; normalize = should_normalize } ->
    let env, input = eval_string ~eval env input in
    let data =
      VString (if should_normalize then Yelu_theory_path.normalize input else input)
    in
    Some (set_var env ~key:path ~data, VUnit)
  | ECmakePathGetFilename { path; out } ->
    Some
      ( set_var env ~key:out ~data:(VString (Yelu_theory_path.filename (path_value env path))),
        VUnit )
  | ECmakePathNormalPath { path; out } ->
    let normalized = VString (Yelu_theory_path.normalize (path_value env path)) in
    let key = Option.value out ~default:path in
    Some (set_var env ~key ~data:normalized, VUnit)
  | _ -> None
