open Yelu_langs.Yelu_cmake_ir_utils
open Step_common_ir

let cmd =
  ycmd_of_list
    [
      yc_at_var "PACKAGE_INIT";
      yc_include (dir_concat list_this "MathFunctionsTargets.cmake");
    ]

let () = print_cmake cmd
