open Yelu_langs.Yelu_cmake_ir_utils
open Step_common_ir

(* TutorialProject/MathFunctions/MathExtensions/CMakeLists.txt *)
let cmd =
  ycmd_of_list [
    yc_add_subdirectory (ydir "OpAdd");
    yc_add_subdirectory (ydir "OpMul");
    yc_add_subdirectory (ydir "OpSub");
  ]

let () = print_cmake cmd
