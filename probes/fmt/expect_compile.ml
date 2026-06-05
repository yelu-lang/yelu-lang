(* fmt test/compile-error-test/CMakeLists.txt — expect_compile.
   cmake_parse_arguments + string(MAKE_C_IDENTIFIER) + file(WRITE)
   + list(APPEND) + set PARENT_SCOPE. *)

open Yelu_langs.Yelu_cmake
open Yelu_langs.Yelu_cmake_utils

let helpers =
  yc_function (ystr "expect_compile") ["name"; "code_fragment"] [
    yc_apply (ystr "cmake_parse_arguments")
      [ystr "EXPECT_COMPILE"; ystr "ERROR"; ystr ""; ystr ""; EVar "ARGN"];
    yc_apply (ystr "string")
      [ystr "MAKE_C_IDENTIFIER"; ystr "${name}"; ystr "test_name"];

    Yelu_langs.Yelu_cmake_if.ECmakeIfStmt {
      cond = EVar "EXPECT_COMPILE_ERROR";
      then_ = ESeq [
        yc_apply (ystr "file") [
          ystr "WRITE";
          ystr "${CMAKE_CURRENT_BINARY_DIR}/test/${test_name}.cc";
          ystr "\n      ${fmt_headers}\n      void ${test_name}() {\n        ${code_fragment}\n      }\n      ";
        ];
        yc_set (ycvar "error_test_names_copy") [ystr "${error_test_names}"];
        yc_apply (ystr "list")
          [ystr "APPEND"; ystr "error_test_names_copy"; ystr "${test_name}"];
        yc_set ~parent_scope:true
          (ycvar "error_test_names") [ystr "${error_test_names_copy}"];
      ];
      else_ = Some (
        yc_set ~parent_scope:true (ycvar "non_error_test_content")
          [ystr "\n        ${non_error_test_content}\n        void ${test_name}() {\n          ${code_fragment}\n        }"]);
    };
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
