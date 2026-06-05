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

let () = Yelu_langs.Yelu_emit_main.print helpers
