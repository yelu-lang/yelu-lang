open Yelu_langs.Lang_yelu_utils
open Step_common

let cmd =
  ycmd_of_list
    [
      yc_at_var "PACKAGE_INIT";
      yc_include (dir_concat list_this "MathFunctionsTargets.cmake");
    ]

let () = print_cmake cmd
