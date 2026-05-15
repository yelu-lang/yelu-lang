open Yelu_langs.Yelu_cmake_utils
open Step_common_ir

(* TutorialProject/Tutorial/CMakeLists.txt *)
let msvc_cond =
  yor (ystrequal (ycstr "CMAKE_CXX_COMPILER_ID") (ystr "MSVC")) (ystrequal (ycstr "CMAKE_CXX_COMPILER_FRONTEND_VARIANT") (ystr "MSVC"))

let gnu_clang_cond =
  yor (ystrequal (ycstr "CMAKE_CXX_COMPILER_ID") (ystr_eval "GNU")) (ytruthy (ystr_eval "${CMAKE_CXX_COMPILER_ID} MATCHES \"Clang\""))

let cmd =
  ycmd_of_list [
    add_exe (ytval "Tutorial");
    yc_target_sources_fs (ytval "Tutorial") [
      ytsi_plain Private [ yfile "Tutorial.cxx" ];
    ];
    link_lib [ ytval "Tutorial" ]
      [ ytarget_def ~kind:Private [ ytval "MathFunctions" ] ];
    compile_feats (ytval "Tutorial")
      [ { kind = Private; feature = "cxx_std_20" } ];
    yif msvc_cond
      (compile_opts (ytval "Tutorial")
        [ ytarget_def ~kind:Private [ ystr "/W3" ] ])
      (yifthen gnu_clang_cond
        (compile_opts (ytval "Tutorial")
          [ ytarget_def ~kind:Private [ ystr "-Wall" ] ]));
    yc_apply (yname "find_path")
      [ ycstr "UnpackagedIncludeFolder"; yfile "Unpackaged.h";
        ykeyword "REQUIRED"; ykeyword "PATH_SUFFIXES"; ystr "Unpackaged" ];
    include_dirs (ytval "Tutorial")
      [ ytarget_def ~kind:Private [ ycstr "UnpackagedIncludeFolder" ] ];
  ]

let () = print_cmake cmd
