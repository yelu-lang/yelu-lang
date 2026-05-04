open Yelu_langs.Lang_yelu_utils
open Step_common

let cmd =
  ycmd_of_list
    [
      yc_include (yfile "release/CPackConfig.cmake");
      yc_set (ycvar "CPACK_INSTALL_CMAKE_PROJECTS")
        [ ystr "debug;Tutorial;ALL;/"; ystr "release;Tutorial;ALL;/" ];
    ]

let () = print_cmake cmd
