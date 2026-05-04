open Yelu_langs.Lang_cmake_utils
open Yelu_langs.Lang_cmake_pp

(* TutorialProject/MathFunctions/MathExtensions/OpMul/CMakeLists.txt *)
let () =
  let ast = cmd_of_list [
    add_library "OpMul" ~type_:"OBJECT";
    target_sources_fs "OpMul" [
      ts_plain "PRIVATE" [ str_ "OpMul.cxx" ];
      file_set_headers ~files:["OpMul.h"] "INTERFACE";
    ];
  ] in
  Fmt.pr "%a@." (Fmt.vbox pp) ast
