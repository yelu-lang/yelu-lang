open Base
open Yelu_tiny
open Yelu_theory_target

let name = "tiny_cmake_op"
let requires = [ "core.string" ]
let provides = [ "cmake_op.project"; "cmake_op.min_version"; "cmake_op.message" ]

type expr +=
  | EProject of { name : string; languages : string list; version : string option }
  | EMinVersion of string
  | EMessage of { mode : string; texts : expr list }
  | EFunction of { name : expr; args : string list; body : expr }
  | EApply of { name : expr; args : expr list }

let eval_case ~eval env = function
  | EProject { name; languages; version } ->
    Some (set_project env { name; languages; version }, VUnit)
  | EMinVersion version ->
    Some (set_cmake_min_version env version, VUnit)
  | EMessage { mode; texts } ->
    let env, texts = eval_string_list ~eval env texts in
    Some (add_message env mode texts, VUnit)
  | EFunction _ -> Some (env, VUnit)
  | EApply _ -> Some (env, VUnit)
  | _ -> None
