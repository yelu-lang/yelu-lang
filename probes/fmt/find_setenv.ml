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

let () =
  let cmake_ast = Yelu_langs.Yelu_cmake_emit.emit_ast helpers in
  let buf = Buffer.create 512 in
  let ff = Format.formatter_of_buffer buf in
  Format.pp_open_vbox ff 0;
  Yelu_langs.Lang_cmake_pp.pp ff cmake_ast;
  Format.pp_close_box ff ();
  Format.pp_print_flush ff ();
  print_string (Buffer.contents buf);
  print_newline ()
