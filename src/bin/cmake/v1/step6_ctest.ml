open Yelu_langs.Lang_cmake_utils
open Yelu_langs.Lang_cmake_pp

let cmd =
  cmd_of_list
    [
      set "CTEST_PROJECT_NAME" [ quote "CMakeTutorial" ];
      set "CTEST_NIGHTLY_START_TIME" [ quote "00:00:00 EST" ];
      set "CTEST_DROP_METHOD" [ quote "http" ];
      set "CTEST_DROP_SITE" [ quote "my.cdash.org" ];
      set "CTEST_DROP_LOCATION"
        [ quote "/submit.php?project=CMakeTutorial" ];
      set "CTEST_DROP_SITE_CDASH" [ str_ "TRUE" ];
    ]

let () = Fmt.pr "%a" (Fmt.vbox pp) cmd
