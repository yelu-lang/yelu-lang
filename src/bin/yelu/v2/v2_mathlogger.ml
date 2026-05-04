open Yelu_langs.Lang_yelu_cmake
open Yelu_langs.Lang_yelu_utils
open Step_common

(* TutorialProject/MathFunctions/MathLogger/CMakeLists.txt
   INTERFACE library with an empty FILE_SET HEADERS (no FILES listed). *)
let cmd =
  ycmd_of_list [
    add_lib ~type_:Lib_interface (ytval "MathLogger");
    yc_target_sources_fs (ytval "MathLogger") [
      ytsi_file_set_headers Interface;
    ];
  ]

let () = print_cmake cmd
