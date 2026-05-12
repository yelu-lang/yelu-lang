open Yelu_langs.Yelu_cmake_utils
open Step_common_ir

let cmd =
  ycmd_of_list
    [
      yc_set (ycvar "CTEST_PROJECT_NAME") [ ystr "CMakeTutorial" ];
      yc_set (ycvar "CTEST_NIGHTLY_START_TIME") [ ystr "00:00:00 EST" ];
      yc_set (ycvar "CTEST_DROP_METHOD") [ ystr "http" ];
      yc_set (ycvar "CTEST_DROP_SITE") [ ystr "my.cdash.org" ];
      yc_set (ycvar "CTEST_DROP_LOCATION")
        [ ystr "/submit.php?project=CMakeTutorial" ];
      yc_set (ycvar "CTEST_DROP_SITE_CDASH") [ ystr "TRUE" ];
    ]

let () = print_cmake cmd
