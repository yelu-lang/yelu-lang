open Base
open Yelu_cmake

type expr +=
  | EPathFilename of expr
  | EPathNormalize of expr

let filename path =
  let path = String.rstrip path ~drop:(Char.equal '/') in
  match String.rsplit2 path ~on:'/' with
  | Some (_, name) -> name
  | None -> path

let normalize path =
  let absolute = String.is_prefix path ~prefix:"/" in
  let parts =
    path
    |> String.split ~on:'/'
    |> List.filter ~f:(fun part ->
      not (String.is_empty part || String.equal part "."))
  in
  let normalized =
    List.fold parts ~init:[] ~f:(fun acc part ->
      match part, acc with
      | "..", _ :: rest -> rest
      | "..", [] when absolute -> []
      | _ -> part :: acc)
    |> List.rev
  in
  let body = String.concat ~sep:"/" normalized in
  if absolute then "/" ^ body else body

let eval_path ~eval env expr =
  let env, value = eval env expr in
  env, expect_string value

let eval_case ~eval env = function
  | EPathFilename expr ->
    let env, path = eval_path ~eval env expr in
    Some (env, VString (filename path))
  | EPathNormalize expr ->
    let env, path = eval_path ~eval env expr in
    Some (env, VString (normalize path))
  | _ -> None
