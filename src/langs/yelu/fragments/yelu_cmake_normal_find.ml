open Base
open Yelu_cmake

let name = "tiny_find"
let requires = [ "core.string" ]
let provides = [ "find.find_package" ]

type expr +=
  | EFindPackage of { package_name : string; required : bool }

(* MUST stay in sync with yelu_cmake_find.ml's assumed_found_packages.
   The yc ↔ ycn translation roundtrip test (test_yelu_lift_lower.ml)
   asserts identical env on both sides — if this list and its yc-side
   twin drift, find_package tests will fail at "translation preserves
   env" pointing here. See that module for the rationale. *)
let assumed_found_packages = [ "Threads" ]

let eval_case ~eval:_ env = function
  | EFindPackage { package_name; required } ->
    let env = add_find_package env { package_name; required } in
    let env =
      if List.mem assumed_found_packages package_name ~equal:String.equal
      then
        let key = "FIND_PACKAGE_MESSAGE_DETAILS_" ^ package_name in
        set_cache_var env ~key ~data:(VString "[TRUE][v()]")
      else env
    in
    Some (env, VUnit)
  | _ -> None
