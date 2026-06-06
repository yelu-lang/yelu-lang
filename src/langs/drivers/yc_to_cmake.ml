open Base
(* ─── Pipeline: yc → cmake text ─────────────────
   .ye → Yc_driver.parse_ye → yc
   yc → Yc_driver.compile_to_cmake_ast → cmake AST
   cmake AST → Cmake_ast_driver.print → cmake text
   ─────────────────────────────────────────────── *)

(* Full pipeline from .ye source to cmake text *)
let compile_ye src =
  let open Result in
  Yc_driver.parse_ye src >>| fun yc ->
  let cmake_ast = Yc_driver.compile_to_cmake_ast yc in
  Cmake_ast_driver.print cmake_ast

(* yc expr → cmake text (production path) *)
let compile_yc yc =
  let cmake_ast = Yc_driver.compile_to_cmake_ast yc in
  Cmake_ast_driver.print cmake_ast
