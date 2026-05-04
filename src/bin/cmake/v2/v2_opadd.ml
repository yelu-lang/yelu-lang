open Yelu_langs.Lang_cmake_utils
open Yelu_langs.Lang_cmake_pp

(* TutorialProject/MathFunctions/MathExtensions/OpAdd/CMakeLists.txt
   OBJECT library with PRIVATE sources and INTERFACE FILE_SET HEADERS. *)
let () =
  let ast = cmd_of_list [
    add_library "OpAdd" ~type_:"OBJECT";
    target_sources_fs "OpAdd" [
      ts_plain "PRIVATE" [ str_ "OpAdd.cxx" ];
      file_set_headers ~files:["OpAdd.h"] "INTERFACE";
    ];
  ] in
  Fmt.pr "%a@." (Fmt.vbox pp) ast
