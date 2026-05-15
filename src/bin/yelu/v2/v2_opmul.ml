open Yelu_langs.Yelu_cmake_utils
open Step_common_ir

(* TutorialProject/MathFunctions/MathExtensions/OpMul/CMakeLists.txt
   OBJECT library with PRIVATE sources and INTERFACE FILE_SET HEADERS. *)
let cmd =
  ycmd_of_list [
    add_lib ~type_:Lib_object (ytval "OpMul");
    yc_target_sources_fs (ytval "OpMul") [
      ytsi_plain Private [ yfile "OpMul.cxx" ];
      ytsi_file_set_headers ~files:[ yfile "OpMul.h" ] Interface;
    ];
  ]

let () = print_cmake cmd
