open Yelu_langs.Yelu_cmake_utils
open Yelu_langs.Lang_cmake
open Step_common_ir

(* cmake Tests/CMakeOnly/ProjectInclude/CMakeLists.txt
   Also used for ProjectIncludeAny (identical content, different -D flags). *)

let cmd =
  ycmd_of_list
    [ yc_project ~languages:[ Lang_none ] "ProjectInclude";
      yifthen
        (ynot (ytruthy (ycstr "AUTO_INCLUDE")))
        (yc_message ~mode:Mm_fatal_error [ "include file not found" ]);
    ]

let () = print_cmake cmd
