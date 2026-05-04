open Yelu_langs.Lang_yelu_utils
open Step_common

(* TutorialProject/MathFunctions/MathExtensions/CMakeLists.txt *)
let cmd =
  ycmd_of_list [
    yc_add_subdirectory (ydir "OpAdd");
    yc_add_subdirectory (ydir "OpMul");
    yc_add_subdirectory (ydir "OpSub");
  ]

let () = print_cmake cmd
