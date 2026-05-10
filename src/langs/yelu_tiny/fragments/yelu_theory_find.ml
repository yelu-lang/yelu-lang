open Yelu_tiny

let name = "tiny_find"
let requires = [ "core.string" ]
let provides = [ "find.find_package" ]

type expr +=
  | EFindPackage of { package_name : string; required : bool }

let eval_case ~eval:_ env = function
  | EFindPackage { package_name; required } ->
    Some (add_find_package env { package_name; required }, VUnit)
  | _ -> None
