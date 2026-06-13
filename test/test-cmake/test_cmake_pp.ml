open Yelu_langs.Lang_cmake
open Yelu_langs.Lang_cmake_utils
open Yelu_langs.Lang_cmake_pp

(* Print a single AST node to string (no trailing newline) *)
let pp_to_string ast = Fmt.str "%a" pp ast

(* Print via vbox (for Exp_list / multi-statement) *)
let pp_vbox_to_string ast = Fmt.str "%a" (Fmt.vbox pp) ast

let check name expected ast =
  Alcotest.test_case name `Quick (fun () ->
      Alcotest.(check string) name expected (pp_to_string ast))

let check_vbox name expected ast =
  Alcotest.test_case name `Quick (fun () ->
      Alcotest.(check string) name expected (pp_vbox_to_string ast))

(* --- Test groups --- *)

let primitives =
  ( "primitives",
    [
      check "set var" "set(FOO bar )" (set "FOO" [ str_ "bar" ]);
      check "set quoted"
        "set(FOO \"hello\" )"
        (set "FOO" [ quote "hello" ]);
      check "set quoted with embedded double-quote"
        "set(FOO \"call \\\"hello\\\"\" )"
        (set "FOO" [ quote "call \"hello\"" ]);
      check "set quoted with backslash"
        "set(FOO \"C:\\\\foo\\\\bar\" )"
        (set "FOO" [ quote "C:\\foo\\bar" ]);
      check "set quoted mixed escapes"
        "set(FOO \"a\\\\b\\\"c\" )"
        (set "FOO" [ quote "a\\b\"c" ]);
      check "set quoted multi-line"
        "set(FOO \"line1\nline2\" )"
        (set "FOO" [ quote "line1\nline2" ]);
      check "set bool"
        "set(FOO ON )"
        (set "FOO" [ bool_ true ]);
      (* Fmt.sp break hints break at top level (no enclosing box);
         in vbox context (real usage), these also break onto separate lines *)
      check "set multiple"
        "set(SRCS a.cpp\nb.cpp )"
        (set "SRCS" [ str_ "a.cpp"; str_ "b.cpp" ]);
      check "set parent_scope"
        "set(X val PARENT_SCOPE)"
        (set ~parent_scope:true "X" [ str_ "val" ]);
      check "include"
        "include(CheckCXXSourceCompiles)"
        (include_ (str_ "CheckCXXSourceCompiles"));
      check "include optional"
        "include(foo OPTIONAL)"
        (include_ ~optional:true (str_ "foo"));
    ] )

let conditions =
  ( "conditions",
    [
      check "if cond_var"
        "if (USE_MYMATH)\n  set(X 1 )\nendif()\n"
        (ifthen [ "USE_MYMATH" ] (set "X" [ str_ "1" ]));
      check "if with else"
        "if (USE_MYMATH)\n  set(X 1 )\nelse()\n  set(X 0 )\nendif()\n"
        (if_ [ "USE_MYMATH" ]
           (set "X" [ str_ "1" ])
           (set "X" [ str_ "0" ]));
      check "if and"
        "if (HAVE_LOG AND HAVE_EXP)\n  break()\nendif()\n"
        (ifthen [ "HAVE_LOG"; "AND"; "HAVE_EXP" ] Break);
      check "if not"
        "if (NOT DEFINED)\n  break()\nendif()\n"
        (ifthen [ "NOT"; "DEFINED" ] Break);
      check "if or"
        "if (A OR B)\n  break()\nendif()\n"
        (ifthen [ "A"; "OR"; "B" ] Break);
      check "is_target"
        "if (TARGET SqrtLibrary)\n  break()\nendif()\n"
        (ifthen [ "TARGET"; "SqrtLibrary" ] Break);
      check "is_defined"
        "if (DEFINED MY_VAR)\n  break()\nendif()\n"
        (ifthen [ "DEFINED"; "MY_VAR" ] Break);
      check "in_list"
        "if (x IN_LIST mylist)\n  break()\nendif()\n"
        (ifthen [ "x"; "IN_LIST"; "mylist" ] Break);
    ] )

let control_flow =
  ( "control_flow",
    [
      check "break" "break()" Break;
      check "continue" "continue()" Continue;
      check "return empty" "return()" (Return { propogate_vars = [] });
      check "return propagate"
        "return(PROPAGATE X\nY )"
        (Return { propogate_vars = [ "X"; "Y" ] });
      check "while"
        "while(X)\n  break()\nendwhile()"
        (While { cond = [ "X" ]; commands = Break });
      check "foreach empty"
        "foreach(item)\nendforeach()"
        (Foreach { loop_var = "item"; items = []; commands = Exp_list [] });
      check "foreach items"
        "foreach(x a b c)\n  break()\nendforeach()"
        (Foreach
           {
             loop_var = "x";
             items = [ str_ "a"; str_ "b"; str_ "c" ];
             commands = Break;
           });
      check "foreach_range"
        "foreach(i RANGE  0 10)\nendforeach()"
        (Foreach_range
           {
             loop_var = "i";
             start = Some "0";
             stop = "10";
             step = None;
             commands = Exp_list [];
           });
      check "foreach_in lists"
        "foreach(f IN LISTS FILES)\nendforeach()"
        (Foreach_in
           {
             loop_var = "f";
             lists = [ "FILES" ];
             items = [];
             commands = Exp_list [];
           });
      check "foreach_in items"
        "foreach(f IN ITEMS a b)\n  break()\nendforeach()"
        (Foreach_in
           {
             loop_var = "f";
             lists = [];
             items = [ str_ "a"; str_ "b" ];
             commands = Break;
           });
    ] )

let functions_macros =
  ( "functions_macros",
    [
      check "function"
        "function(do_test target arg\nresult)\n  break()\nendfunction()\n"
        (function_ "do_test" [ "target"; "arg"; "result" ] [ Break ]);
      check "apply"
        "do_test(Tutorial 4\n\"4 is 2\")\n"
        (apply "do_test"
           [ str_ "Tutorial"; str_ "4"; quote "4 is 2" ]);
      check "macro"
        "macro(my_macro A\nB)\n  break()\nendmacro()\n"
        (Macro
           {
             name = "my_macro";
             args = [ "A"; "B" ];
             commands = Break;
           });
      check "list_append"
        "list(APPEND my_list a b)\n"
        (list_append "my_list" [ str_ "a"; str_ "b" ]);
      check "list_prepend"
        "list(PREPEND my_list x)\n"
        (list_prepend "my_list" [ str_ "x" ]);
      check "list_length"
        "list(LENGTH my_list out)\n"
        (list_length "my_list" "out");
      check "list_get"
        "list(GET my_list 0 2 out)\n"
        (list_get "my_list" [ 0; 2 ] "out");
      check "list_remove_duplicates"
        "list(REMOVE_DUPLICATES my_list)\n"
        (list_remove_duplicates "my_list");
      check "list_reverse"
        "list(REVERSE my_list)\n"
        (list_reverse "my_list");
      check "list_sort"
        "list(SORT my_list ORDER ASCENDING COMPARE STRING)\n"
        (list_sort ~order:Ls_ascending ~compare:Ls_string "my_list");
      check "list_join"
        "list(JOIN my_list \";\" out)\n"
        (list_join "my_list" (quote ";") "out");
      check "list_filter include"
        "list(FILTER my_list INCLUDE REGEX \".*\\.h\")\n"
        (list_filter "my_list" Lf_include ".*\\.h");
      check "string_toupper"
        "string(TOUPPER hello OUT)"
        (string_toupper (str_ "hello") "OUT");
      check "string_tolower"
        "string(TOLOWER HELLO out)"
        (string_tolower (str_ "HELLO") "out");
      check "string_length"
        "string(LENGTH hello out)"
        (string_length (str_ "hello") "out");
      check "string_strip"
        "string(STRIP \" hi \" out)"
        (string_strip (quote " hi ") "out");
      check "string_concat"
        "string(CONCAT out a b c)"
        (string_concat "out" [ str_ "a"; str_ "b"; str_ "c" ]);
      check "string_replace"
        "string(REPLACE foo bar out src)"
        (string_replace (str_ "foo") (str_ "bar") "out" [ str_ "src" ]);
      check "string_regex_match"
        "string(REGEX MATCH \"[0-9]+\" out src)"
        (string_regex_match "[0-9]+" "out" [ str_ "src" ]);
      check "string_regex_quote"
        "string(REGEX QUOTE out a.b+c)"
        (string_regex_quote "out" [ str_ "a.b+c" ]);
    ] )

let targets =
  ( "targets",
    [
      check "add_library"
        "add_library(MathFunctions  MathFunctions.cxx)"
        (add_library "MathFunctions" ~sources:[ "MathFunctions.cxx" ]);
      check "add_library static"
        "add_library(SqrtLibrary STATIC mysqrt.cxx)"
        (add_library "SqrtLibrary" ~type_:"STATIC"
           ~sources:[ "mysqrt.cxx" ]);
      check "add_library interface"
        "add_library(flags INTERFACE )"
        (add_library "flags" ~type_:"INTERFACE");
      check "add_executable"
        "add_executable(Tutorial tutorial.cxx)"
        (add_executable ~sources:[ "tutorial.cxx" ] "Tutorial");
      check "target_link_libraries"
        "target_link_libraries(Tutorial PUBLIC MathFunctions)"
        (target_link_libraries [ "Tutorial" ]
           [ target_def [ str_ "MathFunctions" ] ]);
      check "target_link_libraries private"
        "target_link_libraries(MathFunctions PRIVATE SqrtLibrary)"
        (target_link_libraries [ "MathFunctions" ]
           [ target_def ~kind:"PRIVATE" [ str_ "SqrtLibrary" ] ]);
      check "target_compile_definitions"
        "target_compile_definitions(MathFunctions PRIVATE \"USE_MYMATH\")"
        (target_compile_definitions "MathFunctions"
           [ target_def ~kind:"PRIVATE" [ quote "USE_MYMATH" ] ]);
      check "target_include_directories"
        "target_include_directories(Tutorial PUBLIC \"${PROJECT_BINARY_DIR}\")"
        (target_include_directories "Tutorial"
           [ target_def [ quote "${PROJECT_BINARY_DIR}" ] ]);
      check "target_compile_features"
        "target_compile_features(flags INTERFACE cxx_std_11)"
        (target_compile_features "flags"
           [ target_feature ~kind:"INTERFACE" "cxx_std_11" ]);
    ] )

let install =
  ( "install",
    [
      check "install_targets"
        (* Tier 4 install per-target-type IR widening: printer rewritten
           to walk artifact_clauses; no longer emits the double-space
           the old Fmt @; pattern produced. *)
        "install(TARGETS Tutorial DESTINATION bin)"
        (install_targets [ "Tutorial" ] (str_ "bin"));
      check "install_targets COMPONENT"
        (* COMPONENT is a top-level (default-group) option, emitted before
           the per-kind clauses; previously it was silently dropped *)
        "install(TARGETS Tutorial COMPONENT Dev DESTINATION bin)"
        (install_targets ~component:"Dev" [ "Tutorial" ] (str_ "bin"));
      check "install_files"
        "install(FILES \"MathFunctions.h\" DESTINATION include)"
        (install_files [ quote "MathFunctions.h" ] (str_ "include"));
    ] )

let project_level =
  ( "project_level",
    [
      check "cmake_minimum_required"
        "cmake_minimum_required(VERSION 3.20)"
        (minimum_required_s "3.20.");
      check "project"
        "project(Tutorial VERSION 1.0)"
        (project ~version:(version_of_string "1.0.") "Tutorial");
      check "project no version"
        "project(MyApp )"
        (project "MyApp");
      check "configure_file"
        "configure_file(TutorialConfig.h.in TutorialConfig.h)"
        (configure_file ~input:"TutorialConfig.h.in" "TutorialConfig.h");
      check "add_subdirectory"
        "add_subdirectory(MathFunctions)"
        (add_subdirectory "MathFunctions");
      check "add_test"
        "add_test(NAME Runs COMMAND Tutorial 25)"
        (add_test "Runs" "Tutorial" [ "25" ]);
      check "enable_testing" "enable_testing()" enable_testing;
    ] )

let composition =
  ( "composition",
    [
      check_vbox "exp_list two stmts"
        "set(X 1 )\nset(Y 2 )"
        (cmd_of_list
           [ set "X" [ str_ "1" ]; set "Y" [ str_ "2" ] ]);
      check_vbox "minimal project"
        "cmake_minimum_required(VERSION 3.20)\n\
         project(Hello )\n\
         add_executable(Hello hello.cxx)"
        (cmd_of_list
           [
             minimum_required_s "3.20.";
             project "Hello";
             add_executable ~sources:[ "hello.cxx" ] "Hello";
           ]);
    ] )

let find_var =
  ( "find_var",
    [
      check "find_library minimal"
        "find_library(LIB)"
        (find_library "LIB");
      check "find_library names paths"
        "find_library(LIB NAMES foo PATHS /usr/lib NO_DEFAULT_PATH)"
        (find_library "LIB" ~names:[ str_ "foo" ] ~paths:[ str_ "/usr/lib" ]
           ~no_default_path:true);
      check "find_path no_cmake_environment"
        "find_path(HDR NAMES test.h NO_CMAKE_ENVIRONMENT_PATH NO_SYSTEM_ENVIRONMENT_PATH)"
        (find_path "HDR" ~names:[ str_ "test.h" ]
           ~no_cmake_environment_path:true ~no_system_environment_path:true);
      check "find_program required"
        "find_program(CC NAMES gcc clang REQUIRED)"
        (find_program "CC" ~names:[ str_ "gcc"; str_ "clang" ] ~required:true);
      check "message status"
        "message(STATUS \"hello\")"
        (message [ "hello" ]);
      check "message fatal"
        "message(FATAL_ERROR \"oops\")"
        (message ~mode:Mm_fatal_error [ "oops" ]);
      check "message none"
        "message(\"note\")"
        (message ~mode:Mm_none [ "note" ]);
    ] )

let () =
  Alcotest.run "CMake PP"
    [
      primitives;
      conditions;
      control_flow;
      functions_macros;
      targets;
      install;
      project_level;
      composition;
      find_var;
    ]
