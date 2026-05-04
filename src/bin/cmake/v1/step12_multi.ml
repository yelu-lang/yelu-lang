open Yelu_langs.Lang_cmake_utils
open Yelu_langs.Lang_cmake_pp

let cmd =
  cmd_of_list
    [
      include_ (quote "release/CPackConfig.cmake");
      set "CPACK_INSTALL_CMAKE_PROJECTS"
        [ quote "debug;Tutorial;ALL;/"; quote "release;Tutorial;ALL;/" ];
    ]

let () = Fmt.pr "%a" (Fmt.vbox pp) cmd
