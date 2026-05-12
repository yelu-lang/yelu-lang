open Yelu_langs.Yelu_cmake_ir_utils
open Step_common_ir

let cmd =
  ycmd_of_list
    [
      yc_include (yfile "release/CPackConfig.cmake");
      yc_set (ycvar "CPACK_INSTALL_CMAKE_PROJECTS")
        [ ystr "debug;Tutorial;ALL;/"; ystr "release;Tutorial;ALL;/" ];
    ]

let () = print_cmake cmd
