(* fmt test/compile-error-test/CMakeLists.txt — whole-file emit.
   Preamble + expect_compile + run_tests functions + ~24 callsites. *)

open Yelu_langs.Yelu_cmake
open Yelu_langs.Yelu_cmake_utils

let ec ?(err = false) name code =
  let args = [ystr name; ystr code] in
  let args = if err then args @ [ystr "ERROR"] else args in
  yc_apply (ystr "expect_compile") args

let fmt_headers_str =
  "\n  #include <fmt/format.h>\n\
  \  #include <fmt/xchar.h>\n\
  \  #include <fmt/ostream.h>\n\
  \  #include <iostream>\n"

let expect_compile_fn =
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

let run_tests_fn =
  yc_function (ystr "run_tests") [] [
    yc_set (ycvar "cmake_targets") [ystr ""];
    yc_foreach_in
      ~lists:["error_test_names"]
      (ycvar "test_name")
      (yc_set (ycvar "cmake_targets")
         [ystr "\n        ${cmake_targets}\n        add_library(test-${test_name} ${test_name}.cc)\n        target_link_libraries(test-${test_name} PRIVATE fmt::fmt)\n        "]);
    yc_apply (ystr "file") [
      ystr "WRITE";
      ystr "${CMAKE_CURRENT_BINARY_DIR}/test/non_error_test.cc";
      ystr "\n    ${fmt_headers}\n    ${non_error_test_content}\n    ";
    ];
    yc_set (ycvar "cmake_targets")
      [ystr "\n      ${cmake_targets}\n      add_library(non-error-test non_error_test.cc)\n      target_link_libraries(non-error-test PRIVATE fmt::fmt)\n      "];
    yc_apply (ystr "file") [
      ystr "WRITE";
      ystr "${CMAKE_CURRENT_BINARY_DIR}/test/CMakeLists.txt";
      ystr "\n    cmake_minimum_required(VERSION 3.8...3.25)\n    project(tests CXX)\n    add_subdirectory(${FMT_DIR} fmt)\n    ${cmake_targets}\n    ";
    ];
    yc_set (ycvar "build_directory") [ystr "${CMAKE_CURRENT_BINARY_DIR}/test/build"];
    yc_apply (ystr "file") [ystr "MAKE_DIRECTORY"; ystr "${build_directory}"];
    yc_apply (ystr "execute_process") [
      ystr "COMMAND";
      ystr "${CMAKE_COMMAND}";
      ystr "-DCMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}";
      ystr "-DCMAKE_CXX_FLAGS=${CMAKE_CXX_FLAGS}";
      ystr "-DCMAKE_CXX_STANDARD=${CMAKE_CXX_STANDARD}";
      ystr "-DCMAKE_GENERATOR=${CMAKE_GENERATOR}";
      ystr "-DCMAKE_MAKE_PROGRAM=${CMAKE_MAKE_PROGRAM}";
      ystr "-DFMT_DIR=${FMT_DIR}";
      ystr "${CMAKE_CURRENT_BINARY_DIR}/test";
      ystr "WORKING_DIRECTORY"; ystr "${build_directory}";
      ystr "RESULT_VARIABLE"; ystr "result_var";
      ystr "OUTPUT_VARIABLE"; ystr "output_var";
      ystr "ERROR_VARIABLE"; ystr "output_var";
    ];
    yifthen
      (ynot (Yelu_langs.Yelu_cmake_normal_int.EIntEqual
               (EVar "result_var", ystr "0")))
      (yc_apply (ystr "message")
         [ystr "FATAL_ERROR"; ystr "Unable to configure:\n${output_var}"]);
    yc_foreach_in
      ~lists:["error_test_names"]
      (ycvar "test_name")
      (ESeq [
        yc_apply (ystr "execute_process") [
          ystr "COMMAND"; ystr "${CMAKE_COMMAND}";
          ystr "--build"; ystr "${build_directory}";
          ystr "--target"; ystr "test-${test_name}";
          ystr "WORKING_DIRECTORY"; ystr "${build_directory}";
          ystr "RESULT_VARIABLE"; ystr "result_var";
          ystr "OUTPUT_VARIABLE"; ystr "output_var";
          ystr "ERROR_QUIET";
        ];
        yifthen
          (Yelu_langs.Yelu_cmake_normal_int.EIntEqual
             (EVar "result_var", ystr "0"))
          (yc_apply (ystr "message")
             [ystr "SEND_ERROR";
              ystr "No compile error for \"${test_name}\":\n${output_var}"]);
      ]);
    yc_apply (ystr "execute_process") [
      ystr "COMMAND"; ystr "${CMAKE_COMMAND}";
      ystr "--build"; ystr "${build_directory}";
      ystr "--target"; ystr "non-error-test";
      ystr "WORKING_DIRECTORY"; ystr "${build_directory}";
      ystr "RESULT_VARIABLE"; ystr "result_var";
      ystr "OUTPUT_VARIABLE"; ystr "output_var";
      ystr "ERROR_VARIABLE"; ystr "output_var";
    ];
    yifthen
      (ynot (Yelu_langs.Yelu_cmake_normal_int.EIntEqual
               (EVar "result_var", ystr "0")))
      (yc_apply (ystr "message")
         [ystr "SEND_ERROR";
          ystr "Compile error for combined non-error test:\n${output_var}"]);
  ]

let basic_callsites = [
  ec "check" "";
  ec ~err:true "check-error" "compilation_error";
  ec "wide-character-narrow-format-string" "fmt::format(L\"{}\", L'a');";
  ec ~err:true "wide-character-narrow-format-string-error" "fmt::format(\"{}\", L'a');";
  ec "wide-string-narrow-format-string" "fmt::format(L\"{}\", L\"foo\");";
  ec ~err:true "wide-string-narrow-format-string-error" "fmt::format(\"{}\", L\"foo\");";
  ec "narrow-string-wide-format-string" "fmt::format(L\"{}\", L\"foo\");";
  ec ~err:true "narrow-string-wide-format-string-error" "fmt::format(L\"{}\", \"foo\");";
  ec "cast-to-string"
    "\n  struct S {\n    operator std::string() const { return std::string(); }\n  };\n  fmt::format(\"{}\", std::string(S()));\n  ";
  ec ~err:true "cast-to-string-error"
    "\n  struct S {\n    operator std::string() const { return std::string(); }\n  };\n  fmt::format(\"{}\", S());\n  ";
  ec "format-function"
    "\n  void (*f)();\n  fmt::format(\"{}\", fmt::ptr(f));\n  ";
  ec ~err:true "format-function-error"
    "\n  void (*f)();\n  fmt::format(\"{}\", f);\n  ";
  ec ~err:true "format-lots-of-arguments-with-unformattable"
    "\n  struct E {};\n  fmt::format(\"\", 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, E());\n  ";
  ec ~err:true "format-lots-of-arguments-with-function"
    "\n  void (*f)();\n  fmt::format(\"\", 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, f);\n  ";
]

let cxx20_callsites = [
  ec "format-string-number-spec"
    "\n    #ifdef FMT_HAS_CONSTEVAL\n      fmt::format(\"{:d}\", 42);\n    #endif\n    ";
  ec ~err:true "format-string-number-spec-error"
    "\n    #ifdef FMT_HAS_CONSTEVAL\n      fmt::format(\"{:d}\", \"I am not a number\");\n    #else\n      #error\n    #endif\n    ";
  ec ~err:true "print-string-number-spec-error"
    "\n    #ifdef FMT_HAS_CONSTEVAL\n      fmt::print(\"{:d}\", \"I am not a number\");\n    #else\n      #error\n    #endif\n    ";
  ec ~err:true "print-stream-string-number-spec-error"
    "\n  #ifdef FMT_HAS_CONSTEVAL\n    fmt::print(std::cout, \"{:d}\", \"I am not a number\");\n  #else\n    #error\n  #endif\n    ";
  ec ~err:true "format-string-embedded-nul-error"
    "\n    #if FMT_USE_CONSTEVAL\n      fmt::format(\"a\\0{}\");\n    #else\n      #error\n    #endif\n    ";
  ec "format-string-name"
    "\n    #if defined(FMT_HAS_CONSTEVAL) && FMT_USE_NONTYPE_TEMPLATE_ARGS\n      using namespace fmt::literals;\n      fmt::print(\"{foo}\", \"foo\"_a=42);\n    #endif\n    ";
  ec ~err:true "format-string-name-error"
    "\n    #if defined(FMT_HAS_CONSTEVAL) && FMT_USE_NONTYPE_TEMPLATE_ARGS\n      using namespace fmt::literals;\n      fmt::print(\"{foo}\", \"bar\"_a=42);\n    #else\n      #error\n    #endif\n    ";
]

let helpers = ESeq (
  [
    yc_apply (ystr "cmake_minimum_required") [ystr "VERSION"; ystr "3.8...3.25"];
    yc_apply (ystr "project") [ystr "compile-error-test"; ystr "CXX"];
    yc_set (ycvar "fmt_headers") [ystr fmt_headers_str];
    yc_set (ycvar "error_test_names") [ystr ""];
    yc_set (ycvar "non_error_test_content") [ystr ""];
    expect_compile_fn;
    run_tests_fn;
  ]
  @ basic_callsites
  @ [
    yifthen
      (Yelu_langs.Yelu_cmake_string.ECmakeVersionGreaterEqual
         (EVar "CMAKE_CXX_STANDARD", ystr "20"))
      (ESeq cxx20_callsites);
    yc_apply (ystr "run_tests") [];
  ]
)

let () = Yelu_langs.Yelu_emit_main.print helpers
