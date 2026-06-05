(* fmt support/cmake/FindSetEnv.cmake — whole-file emit.
   find_program with PATHS + if + execute_process. *)

open Yelu_langs.Yelu_cmake
open Yelu_langs.Yelu_cmake_utils

let helpers = ESeq [
  yc_apply (ystr "find_program") [
    ystr "WINSDK_SETENV";
    ystr "NAMES"; ystr "SetEnv.cmd";
    ystr "PATHS";
    ystr "[HKEY_LOCAL_MACHINE\\\\SOFTWARE\\\\Microsoft\\\\Microsoft SDKs\\\\Windows;CurrentInstallFolder]/bin";
  ];
  yifthen
    (Yelu_langs.Yelu_cmake_normal_bool.EAnd
       (EVar "WINSDK_SETENV", EVar "PRINT_PATH"))
    (yc_apply (ystr "execute_process") [
       ystr "COMMAND"; EVar "CMAKE_COMMAND";
       ystr "-E"; ystr "echo"; ystr "${WINSDK_SETENV}";
     ]);
]

let () = Yelu_langs.Yelu_emit_main.print helpers
