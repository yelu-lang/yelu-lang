(* fmt test/CMakeLists.txt — add_fmt_test(name) helper.
   cmake_parse_arguments + if/elseif/else + target ops + add_test. *)

open Yelu_langs.Yelu_cmake
open Yelu_langs.Yelu_cmake_utils

let helpers =
  yc_function (ystr "add_fmt_test") ["name"] [
    yc_apply (ystr "cmake_parse_arguments")
      [ystr "ADD_FMT_TEST"; ystr "HEADER_ONLY;MODULE"; ystr ""; ystr "";
       EVar "ARGN"];

    yc_set (ycvar "sources") [ystr "${name}.cc"; EVar "ADD_FMT_TEST_UNPARSED_ARGUMENTS"];

    (* if HEADER_ONLY elseif MODULE else endif chain *)
    Yelu_langs.Yelu_cmake_if.ECmakeIfStmt {
      cond = EVar "ADD_FMT_TEST_HEADER_ONLY";
      then_ = ESeq [
        yc_set (ycvar "sources")
          [EVar "sources"; EVar "TEST_MAIN_SRC"; ystr "../src/os.cc"];
        yc_set (ycvar "libs") [ystr "gtest"; ystr "fmt-header-only"];
        yifthen
          (Yelu_langs.Yelu_cmake_string.ECmakeMatches
             { expr_ = EVar "CMAKE_CXX_COMPILER_ID"; regex = "Clang" })
          (yc_set (ycvar "PEDANTIC_COMPILE_FLAGS")
             [EVar "PEDANTIC_COMPILE_FLAGS"; ystr "-Wno-weak-vtables"]);
      ];
      else_ = Some (Yelu_langs.Yelu_cmake_if.ECmakeIfStmt {
        cond = EVar "ADD_FMT_TEST_MODULE";
        then_ = yc_set (ycvar "libs") [ystr "test-main"; ystr "fmt-module"];
        else_ = Some (yc_set (ycvar "libs") [ystr "test-main"; ystr "fmt"]);
      });
    };

    yc_apply (ystr "add_executable") [EVar "name"; EVar "sources"];
    yc_apply (ystr "target_link_libraries") [EVar "name"; EVar "libs"];

    (* if (ADD_FMT_TEST_HEADER_ONLY AND NOT FMT_UNICODE) *)
    yifthen
      (Yelu_langs.Yelu_cmake_normal_bool.EAnd
         (EVar "ADD_FMT_TEST_HEADER_ONLY",
          ynot (EVar "FMT_UNICODE")))
      (yc_apply (ystr "target_compile_definitions")
         [EVar "name"; ystr "PUBLIC"; ystr "FMT_UNICODE=0"]);

    yifthen (EVar "FMT_PEDANTIC")
      (yc_apply (ystr "target_compile_options")
         [EVar "name"; ystr "PRIVATE"; EVar "PEDANTIC_COMPILE_FLAGS"]);
    yifthen (EVar "FMT_WERROR")
      (yc_apply (ystr "target_compile_options")
         [EVar "name"; ystr "PRIVATE"; EVar "WERROR_FLAG"]);

    yc_apply (ystr "add_test")
      [ystr "NAME"; EVar "name"; ystr "COMMAND"; EVar "name"];
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
