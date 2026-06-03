open Yelu_cmake
open Yelu_cmake_normal_target

let name = "tiny_try"
let requires = [ "core.string"; "path" ]
let provides = [ "try.try_compile" ]

(* The tiny interpreter cannot actually compile. Stubs result_var
   to false (safe direction: assume the probe failed — matches real
   cmake's compile_result_unused output on this system) and mirrors
   the cmake INTERNAL cache write of "FALSE". Real compile-or-not
   is only known when the lowered cmake script runs.

   Mirrors the yc-side eval in yelu_cmake_try.ml so the
   yc → ycn translation roundtrip preserves env. *)

type expr +=
  | ETryCompile of { result_var : string; sources : expr list }

let eval_case ~eval env = function
  | ETryCompile { result_var; sources } ->
    let env, sources = eval_string_list ~eval env sources in
    let env = add_try_compile env { result_var; sources } in
    let env = set_var env ~key:result_var ~data:(VBool false) in
    let env = set_cache_var env ~key:result_var ~data:(VString "FALSE") in
    Some (env, VUnit)
  | _ -> None
