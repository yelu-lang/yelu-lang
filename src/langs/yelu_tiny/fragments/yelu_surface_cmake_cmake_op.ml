open Base
open Yelu_tiny
open Yelu_theory_target

let name = "tiny_cmake_cmake_op"
let requires = [ "core.string" ]
let provides = [ "cmake_op.project"; "cmake_op.min_version"; "cmake_op.message" ]

type expr +=
  | ECmakeProject of { name : string; languages : string list; version : string option }
  | ECmakeMinimumRequired of string
  | ECmakeMessage of { mode : string; texts : expr list }
  | ECmakeFunction of { name : expr; args : string list; body : expr }
  | ECmakeApply of { name : expr; args : expr list }

let eval_case ~eval env = function
  | ECmakeProject { name; languages; version } ->
    Some (set_project env { name; languages; version }, VUnit)
  | ECmakeMinimumRequired version ->
    Some (set_cmake_min_version env version, VUnit)
  | ECmakeMessage { mode; texts } ->
    let env, texts = eval_string_list ~eval env texts in
    Some (add_message env mode texts, VUnit)
  | ECmakeFunction _ -> Some (env, VUnit)
  | ECmakeApply _ -> Some (env, VUnit)
  | _ -> None
