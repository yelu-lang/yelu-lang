open Yelu_langs.Lang_cmake_utils
open Yelu_langs.Lang_cmake_pp

(* TutorialProject/MathFunctions/MathLogger/CMakeLists.txt
   INTERFACE library with an empty FILE_SET HEADERS (no FILES listed). *)
let () =
  let ast = cmd_of_list [
    add_library "MathLogger" ~type_:"INTERFACE";
    target_sources_fs "MathLogger" [
      file_set_headers "INTERFACE";
    ];
  ] in
  Fmt.pr "%a@." (Fmt.vbox pp) ast
