(* ─── Pipeline: cmake → yc ──────────────────────
   cmake text → Cmake_driver.parse_text_to_json → JSON string
   JSON string → (caller parses with Yojson)
   JSON CST → Cmake_driver.parse_json_to_stmts → cmake AST stmt list
   cmake AST → Cmake_driver.compile_to_yc → yc

   Note: Yojson is not a dependency of yelu_langs.
   Callers (e.g., yelu.ml, tests) parse the JSON string.
   ─────────────────────────────────────────────── *)

(* cmake text file → JSON string (via cmake_to_json.py) *)
let file_to_json = Cmake_driver.parse_text_to_json

(* JSON CST → cmake AST stmt list *)
let json_to_stmts = Cmake_driver.parse_json_to_stmts

(* cmake AST → yc *)
let ast_to_yc = Cmake_driver.compile_to_yc
