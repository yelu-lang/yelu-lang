(** Demo: yelu → cmake text → cmake -P, mirroring variable_watch/RaiseInParentScope.cmake.
    Run: dune exec yelu/test/test-runcmake/demo_variable_watch.exe *)

open Yelu_langs.Lang_yelu_cmake
open Yelu_langs.Lang_yelu_utils
open Yelu_langs.Lang_yelu_compile
open Yelu_langs.Lang_cmake_pp
open Yelu_runner.Cmake_runner

(* Equivalent of Tests/RunCMake/variable_watch/RaiseInParentScope.cmake:
     function(watch variable access value)
       message("${variable} ${access} ${value}")
     endfunction()
     variable_watch(var watch)
     set(var "a")
     function(f)
       set(var "b" PARENT_SCOPE)
     endfunction(f)
     f()
*)
let prog =
  Ystmt_list [
    yc_function (ystr "watch") ["variable"; "access"; "value"] [
      yc_message [ "${variable} ${access} ${value}" ]
    ];
    yc_variable_watch ~command:(Some "watch") (ycvar "var");
    yc_set (ycvar "var") [ystr "a"];
    yc_function (ystr "f") [] [
      yc_set ~parent_scope:true (ycvar "var") [ystr "b"]
    ];
    yc_language_call "f" [];
  ]

let () =
  let _, cmake_ast = compile empty_env prog in
  let cmake_text =
    let buf = Buffer.create 256 in
    let ff = Format.formatter_of_buffer buf in
    Format.pp_open_vbox ff 0;
    pp ff cmake_ast;
    Format.pp_close_box ff ();
    Format.pp_print_flush ff ();
    Buffer.contents buf
  in
  Printf.printf "=== yelu compiled to cmake ===\n%s\n" cmake_text;
  let result = run_script cmake_text in
  Printf.printf "=== cmake -P output ===\n%s" result.stdout;
  Printf.printf "exit: %d\n" result.exit_code
