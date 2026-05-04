open Yelu_langs.Lang_cmake_utils
open Yelu_langs.Lang_cmake_pp

(* TutorialProject/MathFunctions/MathExtensions/OpSub/CMakeLists.txt *)
let () =
  let ast = cmd_of_list [
    add_library "OpSub" ~type_:"OBJECT";
    target_sources_fs "OpSub" [
      ts_plain "PRIVATE" [ str_ "OpSub.cxx" ];
      file_set_headers ~files:["OpSub.h"] "INTERFACE";
    ];
  ] in
  Fmt.pr "%a@." (Fmt.vbox pp) ast
