open Yelu_langs.Lang_yelu_cmake
open Yelu_langs.Yelu_cmake_utils
open Step_common_ir

(* TutorialProject/MathFunctions/MathExtensions/OpSub/CMakeLists.txt
   OBJECT library with PRIVATE sources and INTERFACE FILE_SET HEADERS. *)
let cmd =
  ycmd_of_list [
    add_lib ~type_:Lib_object (ytval "OpSub");
    yc_target_sources_fs (ytval "OpSub") [
      ytsi_plain Private [ yfile "OpSub.cxx" ];
      ytsi_file_set_headers ~files:[ yfile "OpSub.h" ] Interface;
    ];
  ]

let () = print_cmake cmd
