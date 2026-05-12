open Yelu_langs.Lang_yelu_cmake
open Yelu_langs.Yelu_cmake_utils
open Step_common_ir

(* TutorialProject/MathFunctions/MathExtensions/OpAdd/CMakeLists.txt
   OBJECT library with PRIVATE sources and INTERFACE FILE_SET HEADERS. *)
let cmd =
  ycmd_of_list [
    add_lib ~type_:Lib_object (ytval "OpAdd");
    yc_target_sources_fs (ytval "OpAdd") [
      ytsi_plain Private [ yfile "OpAdd.cxx" ];
      ytsi_file_set_headers ~files:[ yfile "OpAdd.h" ] Interface;
    ];
  ]

let () = print_cmake cmd
