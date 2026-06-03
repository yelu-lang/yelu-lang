open Base
open Yelu_cmake

let name = "tiny_find"
let requires = [ "core.string" ]
let provides = [ "find.find_package" ]

type expr +=
  | EFindPackage of { package_name : string; required : bool }

(* Mirrors yelu_cmake_find.ml's assumed_found_packages list so the
   yc ↔ ycn translation roundtrip preserves env. See that module for
   the rationale (Threads always-found stub for matrix prediction). *)
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
