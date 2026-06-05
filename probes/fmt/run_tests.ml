(* fmt test/compile-error-test/CMakeLists.txt — run_tests().
   foreach IN LISTS, file(WRITE), execute_process, conditional message. *)

open Yelu_langs.Yelu_cmake
open Yelu_langs.Yelu_cmake_utils

(* Build the cmake_targets string by iterating over error_test_names *)
let build_cmake_targets =
  yc_foreach_in
    ~lists:["error_test_names"]
    (ycvar "test_name")
    (yc_set (ycvar "cmake_targets")
       [ystr "\n        ${cmake_targets}\n        add_library(test-${test_name} ${test_name}.cc)\n        target_link_libraries(test-${test_name} PRIVATE fmt::fmt)\n        "])

let write_non_error_test =
  yc_apply (ystr "file")
    [ystr "WRITE";
     ystr "${CMAKE_CURRENT_BINARY_DIR}/test/non_error_test.cc";
     ystr "\n    ${fmt_headers}\n    ${non_error_test_content}\n    "]

let append_non_error_target =
  yc_set (ycvar "cmake_targets")
    [ystr "\n      ${cmake_targets}\n      add_library(non-error-test non_error_test.cc)\n      target_link_libraries(non-error-test PRIVATE fmt::fmt)\n      "]

let write_cmakelists =
  yc_apply (ystr "file")
    [ystr "WRITE";
     ystr "${CMAKE_CURRENT_BINARY_DIR}/test/CMakeLists.txt";
     ystr "\n    cmake_minimum_required(VERSION 3.8...3.25)\n    project(tests CXX)\n    add_subdirectory(${FMT_DIR} fmt)\n    ${cmake_targets}\n    "]

let configure_subproject =
  ESeq [
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
  ]

let build_error_tests =
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
    ])

let build_non_error =
  ESeq [
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

let helpers =
  yc_function (ystr "run_tests") [] [
    yc_set (ycvar "cmake_targets") [ystr ""];
    build_cmake_targets;
    write_non_error_test;
    append_non_error_target;
    write_cmakelists;
    configure_subproject;
    build_error_tests;
    build_non_error;
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
