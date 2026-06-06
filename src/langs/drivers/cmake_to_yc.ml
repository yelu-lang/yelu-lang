(* ─── Pipeline: cmake text → yc ─────────────────
   cmake text → Cmake_text_driver.parse_to_json_cst → JSON string
   JSON string → (caller parses with Yojson)
   JSON CST → Cmake_ast_driver.parse_json_cst → cmake AST stmt list
   cmake AST → Yc_driver.parse_cmake → yc

   Note: Yojson is not a dependency of yelu_langs.
   Callers (e.g., yelu.ml, tests) parse the JSON string
   before passing it to parse_json_to_stmts.
   ─────────────────────────────────────────────── *)

(* cmake text file → JSON string (via parse.py) *)
let file_to_json = Cmake_text_driver.parse_to_json_cst

(* JSON CST (already parsed) → cmake AST stmt list *)
let json_to_stmts = Cmake_ast_driver.parse_json_cst

(* cmake AST exp → yc expr *)
let ast_to_yc = Cmake_ast_driver.to_yc
