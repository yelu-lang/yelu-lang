open Yelu_langs.Lang_cmake
open Yelu_langs.Lang_yelu_cmake
open Yelu_langs.Lang_yelu_utils
open Yelu_langs.Lang_yelu_compile
open Yelu_langs.Lang_cmake_pp

let _stage = stage

let pp_to_string ast = Fmt.str "%a" pp ast
let pp_vbox_to_string ast = Fmt.str "%a" (Fmt.vbox pp) ast

(* R4 bridge check. After R4-a's mechanical attrition, every program in
   this file is expected to bridge through tiny EXCEPT the 13 listed in
   [bridge_skip] — those exercise the R4-b semantic batch (block / while
   / foreach_range / break / continue / return / separate_arguments) and
   are intentionally not bridged yet; their design conversation is
   pending. CI stays green; revisit each skip when R4-b lands. *)
(* R4-b.3 closes the last semantic gap: block + return + PARENT_SCOPE
   all bridge via the env-frame stack model. bridge_skip is now empty;
   194/194 compile programs bridge through tiny. *)
let bridge_skip = []

let assert_bridge_succeeds name yelu_ast =
  if Base.List.mem bridge_skip name ~equal:Base.String.equal then ()
  else
    match Yelu_langs.Yelu_cmake_to_yelu1.stmt yelu_ast with
    | exception Yelu_langs.Yelu_cmake_to_yelu1.Bridge_error msg ->
      Alcotest.failf "%s: tiny bridge raised Bridge_error: %s" name msg
    | yelu1 ->
      let cmake_text = Yelu_langs.Yelu_tiny_cmake_emit.emit_script yelu1 in
      Alcotest.(check bool)
        (Printf.sprintf "%s: tiny bridge produced non-empty cmake" name)
        true
        (String.length cmake_text > 0)

(* Phase 1 byte-equality oracle: for every program covered by [emit_ast],
   assert that the tiny path produces byte-identical cmake text to the
   legacy path. Programs not yet covered raise [Eval_error] inside
   [emit_ast]; we catch and skip, logging coverage via a side channel.

   Tests in [oracle_skip] are *known* mismatches caused by bridge
   information loss — places where the production AST carries more
   detail than tiny's surface constructor and the round-trip cannot
   reconstruct the source form. Each entry should cite the gap; fix is
   typically a new tiny constructor that preserves the source shape.
   The skip list should shrink to empty before Phase 1 is declared done. *)
let oracle_covered = ref 0
let oracle_uncovered = ref 0

let oracle_skip = [
  (* Bridge flattens [Yc_foreach_in { loop_var; lists; items }] to a plain
     [ECmakeForeach { items = [EVar lv; …] }]. Tiny needs a dedicated
     [ECmakeForeachInList] constructor to round-trip the IN LISTS / IN ITEMS
     form. *)
  "foreach_in lists";
  "foreach_in items";
  (* Tiny surface [ECmakeTargetLinkOptions] drops the [before] flag the
     production AST carries. Add it to the surface ctor to round-trip. *)
  "target_link_options before";
]

let assert_byte_oracle name yelu_ast =
  if Base.List.mem bridge_skip name ~equal:Base.String.equal then ()
  else if Base.List.mem oracle_skip name ~equal:Base.String.equal then ()
  else
    let legacy_text =
      let cmake_ast = compile empty_env yelu_ast |> snd in
      pp_to_string cmake_ast
    in
    let tiny_attempt =
      try
        let yelu1 = Yelu_langs.Yelu_cmake_to_yelu1.stmt yelu_ast in
        Some (Yelu_langs.Yelu_tiny_cmake_emit_ast.emit_script yelu1)
      with
      | Yelu_langs.Yelu_tiny.Eval_error _ -> None
      | Yelu_langs.Yelu_cmake_to_yelu1.Bridge_error _ -> None
    in
    match tiny_attempt with
    | None -> Stdlib.incr oracle_uncovered
    | Some tiny_text ->
      Stdlib.incr oracle_covered;
      Alcotest.(check string)
        (Printf.sprintf "%s: byte-equal legacy vs tiny via AST" name)
        legacy_text tiny_text

let check name expected yelu_ast =
  Alcotest.test_case name `Quick (fun () ->
      let cmake_ast = compile empty_env yelu_ast |> snd in
      Alcotest.(check string) name expected (pp_to_string cmake_ast);
      assert_bridge_succeeds name yelu_ast;
      assert_byte_oracle name yelu_ast)

let check_vbox name expected yelu_ast =
  Alcotest.test_case name `Quick (fun () ->
      let cmake_ast = compile empty_env yelu_ast |> snd in
      Alcotest.(check string) name expected (pp_vbox_to_string cmake_ast);
      assert_bridge_succeeds name yelu_ast;
      assert_byte_oracle name yelu_ast)

(* --- Test groups --- *)

let primitives =
  ( "primitives",
    [
      check "set var" "set(FOO bar )"
        (yc_set (ycvar "FOO") [ ystr "bar" ]);
      check "set string" "set(FOO hello )"
        (yc_set (ycvar "FOO") [ ystr "hello" ]);
      check "set bool" "set(FOO ON )"
        (yc_set (ycvar "FOO") [ ybool true ]);
      check "set multiple" "set(SRCS a.cpp\nb.cpp )"
        (yc_set (ycvar "SRCS") [ yfile "a.cpp"; yfile "b.cpp" ]);
      check "set parent_scope" "set(X val PARENT_SCOPE)"
        (yc_set ~parent_scope:true (ycvar "X") [ ystr "val" ]);
    ] )

let conditions =
  ( "conditions",
    [
      check "if cond_var"
        "if (USE_MYMATH)\n  set(X 1 )\nendif()\n"
        (yifthen (ytruthy (ycstr "USE_MYMATH"))
           (yc_set (ycvar "X") [ ystr "1" ]));
      check "if with else"
        "if (USE_MYMATH)\n  set(X 1 )\nelse()\n  set(X 0 )\nendif()\n"
        (yif (ytruthy (ycstr "USE_MYMATH"))
           (yc_set (ycvar "X") [ ystr "1" ])
           (yc_set (ycvar "X") [ ystr "0" ]));
      check "if and"
        "if (( HAVE_LOG AND HAVE_EXP ))\n  \nendif()\n"
        (yifthen
           (yand (ytruthy (ycstr "HAVE_LOG")) (ytruthy (ycstr "HAVE_EXP")))
           (Ystmt_list []));
      check "is_target"
        "if (TARGET SqrtLibrary)\n  \nendif()\n"
        (yifthen (yis_target (ytval "SqrtLibrary")) (Ystmt_list []));
      check "is_defined"
        "if (DEFINED MY_VAR)\n  \nendif()\n"
        (yifthen (yis_defined (ycstr "MY_VAR")) (Ystmt_list []));
    ] )

let targets =
  ( "targets",
    [
      check "add_library"
        "add_library(MathFunctions  MathFunctions.cxx)"
        (add_lib ~sources:[ yfile "MathFunctions.cxx" ] (ytval "MathFunctions"));
      check "add_library interface"
        "add_library(flags INTERFACE )"
        (add_lib ~type_:Lib_interface (ytval "flags"));
      check "add_executable"
        "add_executable(Tutorial tutorial.cxx)"
        (add_exe ~sources:[ yfile "tutorial.cxx" ] (ytval "Tutorial"));
      check "target_link_libraries"
        "target_link_libraries(Tutorial PUBLIC MathFunctions)"
        (link_lib [ ytval "Tutorial" ]
           [ ytarget_def [ ytval "MathFunctions" ] ]);
      check "target_compile_definitions"
        "target_compile_definitions(MathFunctions PRIVATE USE_MYMATH)"
        (compile_defs (ytval "MathFunctions")
           [ ytarget_def ~kind:Private [ ykeyword "USE_MYMATH" ] ]);
      check "target_include_directories"
        "target_include_directories(Tutorial PUBLIC \"${PROJECT_BINARY_DIR}\")"
        (include_dirs (ytval "Tutorial")
           [ ytarget_def [ ystr_eval "${PROJECT_BINARY_DIR}" ] ]);
    ] )

let project_level =
  ( "project_level",
    [
      check "cmake_minimum_required"
        "cmake_minimum_required(VERSION 3.20)"
        (yc_minimum_required_s "3.20.");
      check "project"
        "project(Tutorial VERSION 1.0)"
        (yc_project ~version:(Yelu_langs.Lang_cmake_utils.version_of_string "1.0.") "Tutorial");
      check "project no version"
        "project(MyApp )"
        (yc_project "MyApp");
      check "configure_file"
        "configure_file(TutorialConfig.h.in TutorialConfig.h)"
        (gen_file ~input:(yfile "TutorialConfig.h.in") (yfile "TutorialConfig.h"));
      check "add_subdirectory"
        "add_subdirectory(MathFunctions)"
        (yc_add_subdirectory (ydir "MathFunctions"));
    ] )

let composition =
  ( "composition",
    [
      check_vbox "exp_list two stmts"
        "set(X 1 )\nset(Y 2 )"
        (ycmd_of_list
           [ yc_set (ycvar "X") [ ystr "1" ]; yc_set (ycvar "Y") [ ystr "2" ] ]);
    ] )

let let_bindings =
  ( "let_bindings",
    [
      check "ylet basic"
        "add_executable(Tutorial tutorial.cxx)"
        (ycmd_of_list
           [
             ylet "tut" (ytval "Tutorial");
             add_exe ~sources:[ yfile "tutorial.cxx" ] (yvar "tut");
           ]);
      check_vbox "ylet reuse"
        "add_library(mylib  src.cxx)\ntarget_link_libraries(mylib PUBLIC dep)"
        (ycmd_of_list
           [
             ylet "lib" (ytval "mylib");
             add_lib ~sources:[ yfile "src.cxx" ] (yvar "lib");
             link_lib [ yvar "lib" ]
               [ ytarget_def [ ystr "dep" ] ];
           ]);
      check "ylet chain"
        "add_executable(App main.cxx)"
        (ycmd_of_list
           [
             ylet "name" (ytval "App");
             ylet "alias" (yvar "name");
             add_exe ~sources:[ yfile "main.cxx" ] (yvar "alias");
           ]);
      check "ylet in target list"
        "target_link_libraries(main PUBLIC mylib)"
        (ycmd_of_list
           [
             ylet "t" (ytval "main");
             ylet "l" (ytval "mylib");
             link_lib [ yvar "t" ]
               [ ytarget_def [ yvar "l" ] ];
           ]);
      check "ylet bare string in target pos"
        "add_executable(App main.cxx)"
        (ycmd_of_list
           [
             ylet "name" (ystr "App");
             add_exe ~sources:[ yfile "main.cxx" ] (yvar "name");
           ]);
    ] )

let iteration =
  ( "iteration",
    [
      check "foreach items no body"
        "foreach(x a b)\nendforeach()"
        (yc_foreach ~items:[ ystr "a"; ystr "b" ] (ycvar "x") (Ystmt_list []));
      check "foreach items with body"
        "foreach(x a b)\n  set(FOO bar )\nendforeach()"
        (yc_foreach ~items:[ ystr "a"; ystr "b" ] (ycvar "x")
           (yc_set (ycvar "FOO") [ ystr "bar" ]));
      check "foreach_range stop only"
        "foreach(i RANGE 10)\nendforeach()"
        (yc_foreach_range ~stop:10 (ycvar "i") (Ystmt_list []));
      check "foreach_range start stop"
        "foreach(i RANGE  0 10)\nendforeach()"
        (yc_foreach_range ~start:0 ~stop:10 (ycvar "i") (Ystmt_list []));
      check "foreach_in lists"
        "foreach(f IN LISTS MY_LIST)\nendforeach()"
        (yc_foreach_in ~lists:[ ycvar "MY_LIST" ] (ycvar "f") (Ystmt_list []));
      check "foreach_in items"
        "foreach(f IN ITEMS a b)\nendforeach()"
        (yc_foreach_in ~items:[ ystr "a"; ystr "b" ] (ycvar "f") (Ystmt_list []));
    ] )

let loop_control =
  ( "loop_control",
    [
      check "while empty body"
        "while(FLAG)\n  \nendwhile()"
        (yc_while (ytruthy (ycstr "FLAG")) (Ystmt_list []));
      check "break" "break()" yc_break;
      check "continue" "continue()" yc_continue;
      check "return empty" "return()" (yc_return ());
      check "return propagate"
        "return(PROPAGATE FOO\nBAR )"
        (yc_return ~propogate_vars:[ "FOO"; "BAR" ] ());
    ] )

let list_ops =
  ( "list_ops",
    [
      check "list_length"
        "list(LENGTH MY_LIST OUT)\n"
        (yc_list_length (ycvar "MY_LIST") (ycvar "OUT"));
      check "list_get"
        "list(GET MY_LIST 0 OUT)\n"
        (yc_list_get ~indices:[ 0 ] (ycvar "MY_LIST") (ycvar "OUT"));
      check "list_remove_item"
        "list(REMOVE_ITEM MY_LIST a b)\n"
        (yc_list_remove_item (ycvar "MY_LIST") [ ystr "a"; ystr "b" ]);
      check "list_remove_duplicates"
        "list(REMOVE_DUPLICATES MY_LIST)\n"
        (yc_list_remove_duplicates (ycvar "MY_LIST"));
      check "list_reverse"
        "list(REVERSE MY_LIST)\n"
        (yc_list_reverse (ycvar "MY_LIST"));
      check "list_sort default"
        "list(SORT MY_LIST)\n"
        (yc_list_sort (ycvar "MY_LIST"));
      check "list_filter include"
        "list(FILTER MY_LIST INCLUDE REGEX \".*\\.h\")\n"
        (yc_list_filter Lf_include ".*\\.h" (ycvar "MY_LIST"));
      check "list_join"
        "list(JOIN MY_LIST , OUT)\n"
        (yc_list_join (ycvar "MY_LIST") (ystr ",") (ycvar "OUT"));
      check "list_sublist"
        "list(SUBLIST MY_LIST 1 2 OUT)\n"
        (yc_list_sublist (ycvar "MY_LIST") 1 2 (ycvar "OUT"));
      check "list_find"
        "list(FIND MY_LIST val OUT)\n"
        (yc_list_find (ycvar "MY_LIST") (ystr "val") (ycvar "OUT"));
      check "list_prepend"
        "list(PREPEND MY_LIST a b)\n"
        (yc_list_prepend (ycvar "MY_LIST") [ ystr "a"; ystr "b" ]);
      check "list_insert"
        "list(INSERT MY_LIST 0 x)\n"
        (yc_list_insert (ycvar "MY_LIST") 0 [ ystr "x" ]);
      check "list_remove_at"
        "list(REMOVE_AT MY_LIST 0 2)\n"
        (yc_list_remove_at (ycvar "MY_LIST") [ 0; 2 ]);
      check "list_pop_back no out"
        "list(POP_BACK MY_LIST)\n"
        (yc_list_pop_back (ycvar "MY_LIST"));
      check "list_pop_front with out"
        "list(POP_FRONT MY_LIST X)\n"
        (yc_list_pop_front ~out_vars:[ (ycvar "X") ] (ycvar "MY_LIST"));
    ] )

let string_ops =
  ( "string_ops",
    [
      check "string_toupper"
        "string(TOUPPER hello OUT)"
        (yc_string_toupper (ystr "hello") (ycvar "OUT"));
      check "string_tolower"
        "string(TOLOWER hello OUT)"
        (yc_string_tolower (ystr "hello") (ycvar "OUT"));
      check "string_length"
        "string(LENGTH hello OUT)"
        (yc_string_length (ystr "hello") (ycvar "OUT"));
      check "string_strip"
        "string(STRIP hello OUT)"
        (yc_string_strip (ystr "hello") (ycvar "OUT"));
      check "string_concat"
        "string(CONCAT OUT a b)"
        (yc_string_concat (ycvar "OUT") [ ystr "a"; ystr "b" ]);
      check "string_replace"
        "string(REPLACE foo bar OUT input)"
        (yc_string_replace (ystr "foo") (ystr "bar") (ycvar "OUT") [ ystr "input" ]);
      check "string_regex_match"
        "string(REGEX MATCH \"[0-9]+\" OUT src)"
        (yc_string_regex_match "[0-9]+" (ycvar "OUT") [ ystr "src" ]);
      check "string_regex_replace"
        "string(REGEX REPLACE \"[0-9]+\" X OUT src)"
        (yc_string_regex_replace "[0-9]+" (ystr "X") (ycvar "OUT") [ ystr "src" ]);
      check "string_regex_quote"
        "string(REGEX QUOTE OUT a.b+c)"
        (yc_string_regex_quote (ycvar "OUT") [ ystr "a.b+c" ]);
      check "string_append"
        "string(APPEND VAR a b)"
        (yc_string_append (ycvar "VAR") [ ystr "a"; ystr "b" ]);
      check "string_prepend"
        "string(PREPEND VAR pfx)"
        (yc_string_prepend (ycvar "VAR") [ ystr "pfx" ]);
      check "string_join"
        "string(JOIN , OUT a b)"
        (yc_string_join (ystr ",") (ycvar "OUT") [ ystr "a"; ystr "b" ]);
      check "string_find"
        "string(FIND hello ell OUT)"
        (yc_string_find (ystr "hello") (ystr "ell") (ycvar "OUT"));
      check "string_find reverse"
        "string(FIND hello ell OUT REVERSE)"
        (yc_string_find ~reverse:true (ystr "hello") (ystr "ell") (ycvar "OUT"));
      check "string_substring"
        "string(SUBSTRING hello 1 3 OUT)"
        (yc_string_substring (ystr "hello") 1 ~length:3 (ycvar "OUT"));
      check "string_repeat"
        "string(REPEAT abc 3 OUT)"
        (yc_string_repeat (ystr "abc") 3 (ycvar "OUT"));
      check "string_genex_strip"
        "string(GENEX_STRIP src OUT)"
        (yc_string_genex_strip (ystr "src") (ycvar "OUT"));
      check "string_compare equal"
        "string(COMPARE EQUAL a b OUT)"
        (yc_string_compare Sco_equal (ystr "a") (ystr "b") (ycvar "OUT"));
      check "string_compare less"
        "string(COMPARE LESS a b OUT)"
        (yc_string_compare Sco_less (ystr "a") (ystr "b") (ycvar "OUT"));
      check "string_make_c_identifier"
        "string(MAKE_C_IDENTIFIER hello OUT)"
        (yc_string_make_c_identifier (ystr "hello") (ycvar "OUT"));
      check "string_timestamp plain"
        "string(TIMESTAMP OUT)"
        (yc_string_timestamp (ycvar "OUT"));
      check "string_timestamp utc format"
        "string(TIMESTAMP OUT \"%Y-%m-%d\" UTC)"
        (yc_string_timestamp ~utc:true ~format:"%Y-%m-%d" (ycvar "OUT"));
    ] )

let scripting_ext =
  ( "scripting_ext",
    [
      check "get_filename_component name"
        "get_filename_component(OUT myfile.txt NAME)"
        (yc_get_filename_component ~mode:"NAME" (ycvar "OUT") (ystr "myfile.txt"));
      check "get_filename_component path"
        "get_filename_component(OUT /a/b/c.txt PATH)"
        (yc_get_filename_component ~mode:"PATH" (ycvar "OUT") (ystr "/a/b/c.txt"));
      check "include_guard directory"
        "include_guard(DIRECTORY)"
        (yc_include_guard Ig_directory);
      check "include_guard global"
        "include_guard(GLOBAL)"
        (yc_include_guard Ig_global);
      check "separate_arguments unix"
        "separate_arguments(VAR UNIX_COMMAND)"
        (yc_separate_arguments ~mode:Sa_unix_command (ycvar "VAR"));
      check "target_link_options"
        "target_link_options(mytarget PUBLIC -Wl,--gc-sections)"
        (yc_target_link_options (ytval "mytarget")
           [ ytarget_def ~kind:Public [ ystr "-Wl,--gc-sections" ] ]);
      check "target_link_options before"
        "target_link_options(mytarget BEFORE PRIVATE -flag)"
        (yc_target_link_options ~before:true (ytval "mytarget")
           [ ytarget_def ~kind:Private [ ystr "-flag" ] ]);
      check "target_sources"
        "target_sources(mytarget PRIVATE src/a.cpp)"
        (yc_target_sources (ytval "mytarget")
           [ ytarget_def ~kind:Private [ yfile "src/a.cpp" ] ]);
    ] )

let find_package_tests =
  ( "find_package",
    [
      check "find_package minimal"
        "find_package(Boost)"
        (yc_find_package "Boost");
      check "find_package version"
        "find_package(Boost 1.80)"
        (yc_find_package ~version:(Some "1.80") "Boost");
      check "find_package required exact"
        "find_package(Boost 1.80 EXACT REQUIRED)"
        (yc_find_package ~version:(Some "1.80") ~exact:true ~required:true "Boost");
      check "find_package components"
        "find_package(Boost REQUIRED COMPONENTS filesystem system)"
        (yc_find_package ~required:true ~components:["filesystem"; "system"] "Boost");
      check "find_package optional_components"
        "find_package(Boost OPTIONAL_COMPONENTS regex)"
        (yc_find_package ~optional_components:["regex"] "Boost");
      check "find_package quiet"
        "find_package(OpenSSL QUIET)"
        (yc_find_package ~quiet:true "OpenSSL");
      check "find_package config_mode"
        "find_package(Boost CONFIG)"
        (yc_find_package ~config_mode:true "Boost");
      check "find_package config_mode required components"
        "find_package(Boost CONFIG REQUIRED COMPONENTS filesystem)"
        (yc_find_package ~config_mode:true ~required:true ~components:["filesystem"] "Boost");
    ] )

let genex_tests =
  ( "genex",
    [
      check "config"
        {|set(X "$<CONFIG:Debug>" )|}
        (yc_set (ycvar "X") [ yge (Yge_config "Debug") ]);
      check "not config"
        {|set(X "$<NOT:$<CONFIG:Debug>>" )|}
        (yc_set (ycvar "X") [ yge (Yge_not (Yge_config "Debug")) ]);
      check "and"
        {|set(X "$<AND:$<CONFIG:Debug>,$<COMPILE_LANGUAGE:CXX>>" )|}
        (yc_set (ycvar "X") [ yge (Yge_and [ Yge_config "Debug"; Yge_compile_language "CXX" ]) ]);
      check "if"
        {|set(X "$<IF:$<CONFIG:Debug>,ON,OFF>" )|}
        (yc_set (ycvar "X") [ yge (Yge_if (Yge_config "Debug", Yge_raw "ON", Yge_raw "OFF")) ]);
      check "target_file"
        {|set(X "$<TARGET_FILE:mylib>" )|}
        (yc_set (ycvar "X") [ yge (Yge_target_file "mylib") ]);
      check "target_file_dir"
        {|set(X "$<TARGET_FILE_DIR:myapp>" )|}
        (yc_set (ycvar "X") [ yge (Yge_target_file_dir "myapp") ]);
      check "install_interface"
        {|set(X "$<INSTALL_INTERFACE:include>" )|}
        (yc_set (ycvar "X") [ yge (Yge_install_interface (Yge_raw "include")) ]);
      check "build_interface"
        {|set(X "$<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>" )|}
        (yc_set (ycvar "X") [ yge (Yge_build_interface (Yge_raw "${CMAKE_CURRENT_SOURCE_DIR}/include")) ]);
      check "strequal"
        {|set(X "$<STREQUAL:${CMAKE_SYSTEM_NAME},Linux>" )|}
        (yc_set (ycvar "X") [ yge (Yge_strequal ("${CMAKE_SYSTEM_NAME}", "Linux")) ]);
      check "lower_case"
        {|set(X "$<LOWER_CASE:$<CONFIG>>" )|}
        (yc_set (ycvar "X") [ yge (Yge_lower_case (Yge_raw "$<CONFIG>")) ]);
      check "platform_id"
        {|set(X "$<PLATFORM_ID:Linux>" )|}
        (yc_set (ycvar "X") [ yge (Yge_platform_id "Linux") ]);
      check "target_property"
        {|set(X "$<TARGET_PROPERTY:foo,INCLUDE_DIRECTORIES>" )|}
        (yc_set (ycvar "X") [ yge (Yge_target_property ("foo", "INCLUDE_DIRECTORIES")) ]);
      check "raw escape hatch"
        {|set(X "$<GENEX_EVAL:$<TARGET_PROPERTY:COMPILE_FLAGS>>" )|}
        (yc_set (ycvar "X") [ yge (Yge_raw "$<GENEX_EVAL:$<TARGET_PROPERTY:COMPILE_FLAGS>>") ]);
    ] )

let execute_process_tests =
  ( "execute_process",
    [
      check "basic single command"
        "execute_process(\n  COMMAND git describe --tags\n  OUTPUT_VARIABLE GIT_VER\n  OUTPUT_STRIP_TRAILING_WHITESPACE)"
        (yc_execute_process ~output_variable:(Some (ycvar "GIT_VER"))
           ~output_strip_trailing_whitespace:true
           [ [ ystr "git"; ystr "describe"; ystr "--tags" ] ]);
      check "multi command"
        "execute_process(\n  COMMAND uname -s\n  COMMAND tr a-z A-Z\n  OUTPUT_VARIABLE OS_NAME)"
        (yc_execute_process ~output_variable:(Some (ycvar "OS_NAME"))
           [ [ ystr "uname"; ystr "-s" ]; [ ystr "tr"; ystr "a-z"; ystr "A-Z" ] ]);
      check "result and error"
        "execute_process(\n  COMMAND false\n  RESULT_VARIABLE RC\n  ERROR_VARIABLE ERR_MSG)"
        (yc_execute_process ~result_variable:(Some (ycvar "RC"))
           ~error_variable:(Some (ycvar "ERR_MSG"))
           [ [ ystr "false" ] ]);
      check "working_directory timeout"
        "execute_process(\n  COMMAND make\n  WORKING_DIRECTORY /tmp/build\n  TIMEOUT 30)"
        (yc_execute_process ~working_directory:(Some (ystr "/tmp/build"))
           ~timeout:(Some 30.)
           [ [ ystr "make" ] ]);
      check "quiet flags"
        "execute_process(\n  COMMAND true\n  OUTPUT_QUIET\n  ERROR_QUIET)"
        (yc_execute_process ~output_quiet:true ~error_quiet:true
           [ [ ystr "true" ] ]);
      check "command_error_is_fatal"
        "execute_process(\n  COMMAND cmake --build .\n  COMMAND_ERROR_IS_FATAL ANY)"
        (yc_execute_process ~command_error_is_fatal:(Some "ANY")
           [ [ ystr "cmake"; ystr "--build"; ystr "." ] ]);
    ] )

let file_ops =
  ( "file_ops",
    [
      check "file_glob basic"
        "file(GLOB SRCS *.cpp)"
        (yc_file_glob (ycvar "SRCS") [ ystr "*.cpp" ]);
      check "file_glob recurse"
        "file(GLOB_RECURSE SRCS src/**/*.cpp)"
        (yc_file_glob ~recurse:true (ycvar "SRCS") [ ystr "src/**/*.cpp" ]);
      check "file_glob configure_depends"
        "file(GLOB SRCS CONFIGURE_DEPENDS *.cpp)"
        (yc_file_glob ~configure_depends:true (ycvar "SRCS") [ ystr "*.cpp" ]);
      check "file_glob relative"
        "file(GLOB SRCS CONFIGURE_DEPENDS RELATIVE src *.cpp *.h)"
        (yc_file_glob ~configure_depends:true ~relative:(Some (ystr "src"))
           (ycvar "SRCS") [ ystr "*.cpp"; ystr "*.h" ]);
      (* IO *)
      check "file_read basic"
        "file(READ version.txt FILE_VER)"
        (yc_file_read (ycvar "FILE_VER") (ystr "version.txt"));
      check "file_read offset_limit_hex"
        "file(READ data.bin BUF OFFSET 4 LIMIT 16 HEX)"
        (yc_file_read ~offset:(Some 4) ~limit:(Some 16) ~hex:true
           (ycvar "BUF") (ystr "data.bin"));
      check "file_write"
        {|file(WRITE out.txt "hello world")|}
        (yc_file_write (ystr "out.txt") [ ystr "hello world" ]);
      check "file_append"
        "file(APPEND out.txt line2)"
        (yc_file_append (ystr "out.txt") [ ystr "line2" ]);
      check "file_strings basic"
        "file(STRINGS header.h VERSION_LIST)"
        (yc_file_strings (ycvar "VERSION_LIST") (ystr "header.h"));
      check "file_strings regex"
        {|file(STRINGS header.h VERSION_LIST REGEX "^#define VERSION")|}
        (yc_file_strings ~regex:(Some "^#define VERSION")
           (ycvar "VERSION_LIST") (ystr "header.h"));
      (* filesystem *)
      check "file_touch"
        "file(TOUCH a.txt b.txt)"
        (yc_file_touch [ ystr "a.txt"; ystr "b.txt" ]);
      check "file_touch_nocreate"
        "file(TOUCH_NOCREATE stamp.txt)"
        (yc_file_touch ~nocreate:true [ ystr "stamp.txt" ]);
      check "file_make_directory"
        "file(MAKE_DIRECTORY out/ gen/)"
        (yc_file_make_directory [ ystr "out/"; ystr "gen/" ]);
      check "file_rename"
        "file(RENAME old.txt new.txt)"
        (yc_file_rename (ystr "old.txt") (ystr "new.txt"));
      check "file_rename result"
        "file(RENAME old.txt new.txt RESULT REN_RESULT NO_REPLACE)"
        (yc_file_rename ~result:(Some (ycvar "REN_RESULT")) ~no_replace:true
           (ystr "old.txt") (ystr "new.txt"));
      check "file_remove"
        "file(REMOVE a.o b.o)"
        (yc_file_remove [ ystr "a.o"; ystr "b.o" ]);
      check "file_remove_recurse"
        "file(REMOVE_RECURSE _build/)"
        (yc_file_remove ~recurse:true [ ystr "_build/" ]);
      check "file_copy_file"
        "file(COPY_FILE src.txt dst.txt)"
        (yc_file_copy_file (ystr "src.txt") (ystr "dst.txt"));
      check "file_copy_file only_if_different"
        "file(COPY_FILE src.txt dst.txt ONLY_IF_DIFFERENT)"
        (yc_file_copy_file ~only_if_different:true (ystr "src.txt") (ystr "dst.txt"));
      (* path queries *)
      check "file_real_path"
        "file(REAL_PATH ./rel ABS_PATH)"
        (yc_file_real_path (ycvar "ABS_PATH") (ystr "./rel"));
      check "file_real_path expand_tilde"
        "file(REAL_PATH ~/config CFG_PATH EXPAND_TILDE)"
        (yc_file_real_path ~expand_tilde:true (ycvar "CFG_PATH") (ystr "~/config"));
      check "file_size"
        "file(SIZE lib.so LIB_SIZE)"
        (yc_file_size (ycvar "LIB_SIZE") (ystr "lib.so"));
      check "file_read_symlink"
        "file(READ_SYMLINK /usr/bin/cc CC_TARGET)"
        (yc_file_read_symlink (ycvar "CC_TARGET") (ystr "/usr/bin/cc"));
      check "file_timestamp"
        "file(TIMESTAMP CMakeLists.txt TS)"
        (yc_file_timestamp (ycvar "TS") (ystr "CMakeLists.txt"));
      check "file_timestamp format_utc"
        {|file(TIMESTAMP CMakeLists.txt TS "%Y-%m-%d" UTC)|}
        (yc_file_timestamp ~format:(Some "%Y-%m-%d") ~utc:true
           (ycvar "TS") (ystr "CMakeLists.txt"));
    ] )

let cmake_path_tests =
  ( "cmake_path",
    [
      (* GET *)
      check "get_filename"
        "cmake_path(GET MY_PATH FILENAME OUT)"
        (yc_path_get (ycvar "MY_PATH") Cpf_filename (ycvar "OUT"));
      check "get_stem"
        "cmake_path(GET MY_PATH STEM OUT)"
        (yc_path_get (ycvar "MY_PATH") (Cpf_stem false) (ycvar "OUT"));
      check "get_stem_last_only"
        "cmake_path(GET MY_PATH STEM LAST_ONLY OUT)"
        (yc_path_get (ycvar "MY_PATH") (Cpf_stem true) (ycvar "OUT"));
      check "get_extension"
        "cmake_path(GET MY_PATH EXTENSION OUT)"
        (yc_path_get (ycvar "MY_PATH") (Cpf_extension false) (ycvar "OUT"));
      check "get_parent_path"
        "cmake_path(GET MY_PATH PARENT_PATH OUT)"
        (yc_path_get (ycvar "MY_PATH") Cpf_parent_path (ycvar "OUT"));
      (* HAS_* *)
      check "has_extension"
        "cmake_path(HAS_EXTENSION MY_PATH OUT)"
        (yc_path_has (ycvar "MY_PATH") Cph_extension (ycvar "OUT"));
      check "has_parent_path"
        "cmake_path(HAS_PARENT_PATH MY_PATH OUT)"
        (yc_path_has (ycvar "MY_PATH") Cph_parent_path (ycvar "OUT"));
      (* IS_* *)
      check "is_absolute"
        "cmake_path(IS_ABSOLUTE MY_PATH OUT)"
        (yc_path_is_absolute (ycvar "MY_PATH") (ycvar "OUT"));
      check "is_relative"
        "cmake_path(IS_RELATIVE MY_PATH OUT)"
        (yc_path_is_relative (ycvar "MY_PATH") (ycvar "OUT"));
      check "is_prefix"
        "cmake_path(IS_PREFIX MY_PATH /usr/local OUT)"
        (yc_path_is_prefix (ycvar "MY_PATH") (ystr "/usr/local") (ycvar "OUT"));
      check "is_prefix_normalize"
        "cmake_path(IS_PREFIX MY_PATH /usr/local NORMALIZE OUT)"
        (yc_path_is_prefix ~normalize:true (ycvar "MY_PATH") (ystr "/usr/local") (ycvar "OUT"));
      (* COMPARE *)
      check "compare_equal"
        "cmake_path(COMPARE /a/b EQUAL /a/b OUT)"
        (yc_path_compare (ystr "/a/b") Cpco_equal (ystr "/a/b") (ycvar "OUT"));
      check "compare_not_equal"
        "cmake_path(COMPARE /a/b NOT_EQUAL /a/c OUT)"
        (yc_path_compare (ystr "/a/b") Cpco_not_equal (ystr "/a/c") (ycvar "OUT"));
      (* SET / APPEND *)
      check "set"
        "cmake_path(SET MY_PATH /usr/local)"
        (yc_path_set (ycvar "MY_PATH") (ystr "/usr/local"));
      check "set_normalize"
        "cmake_path(SET MY_PATH NORMALIZE /usr/../local)"
        (yc_path_set ~normalize:true (ycvar "MY_PATH") (ystr "/usr/../local"));
      check "append_no_out"
        "cmake_path(APPEND MY_PATH bin)"
        (yc_path_append (ycvar "MY_PATH") [ ystr "bin" ]);
      check "append_with_out"
        "cmake_path(APPEND MY_PATH bin OUTPUT_VARIABLE RESULT)"
        (yc_path_append ~out:(Some (ycvar "RESULT")) (ycvar "MY_PATH") [ ystr "bin" ]);
      (* Modification *)
      check "remove_filename"
        "cmake_path(REMOVE_FILENAME MY_PATH)"
        (yc_path_remove_filename (ycvar "MY_PATH"));
      check "replace_filename"
        "cmake_path(REPLACE_FILENAME MY_PATH new.txt)"
        (yc_path_replace_filename (ycvar "MY_PATH") (ystr "new.txt"));
      check "remove_extension"
        "cmake_path(REMOVE_EXTENSION MY_PATH)"
        (yc_path_remove_extension (ycvar "MY_PATH"));
      check "remove_extension_last_only"
        "cmake_path(REMOVE_EXTENSION MY_PATH LAST_ONLY)"
        (yc_path_remove_extension ~last_only:true (ycvar "MY_PATH"));
      check "replace_extension"
        "cmake_path(REPLACE_EXTENSION MY_PATH .bak)"
        (yc_path_replace_extension (ycvar "MY_PATH") (ystr ".bak"));
      (* Generation *)
      check "normal_path"
        "cmake_path(NORMAL_PATH MY_PATH)"
        (yc_path_normal_path (ycvar "MY_PATH"));
      check "normal_path_out"
        "cmake_path(NORMAL_PATH MY_PATH OUTPUT_VARIABLE RESULT)"
        (yc_path_normal_path ~out:(Some (ycvar "RESULT")) (ycvar "MY_PATH"));
      check "relative_path"
        "cmake_path(RELATIVE_PATH MY_PATH BASE_DIRECTORY /usr OUTPUT_VARIABLE RESULT)"
        (yc_path_relative_path ~base_dir:(Some (ystr "/usr")) ~out:(Some (ycvar "RESULT")) (ycvar "MY_PATH"));
      check "absolute_path"
        "cmake_path(ABSOLUTE_PATH MY_PATH NORMALIZE OUTPUT_VARIABLE RESULT)"
        (yc_path_absolute_path ~normalize:true ~out:(Some (ycvar "RESULT")) (ycvar "MY_PATH"));
      check "native_path"
        "cmake_path(NATIVE_PATH MY_PATH OUT)"
        (yc_path_native_path (ycvar "MY_PATH") (ycvar "OUT"));
      check "convert_to_cmake"
        "cmake_path(CONVERT /usr/local TO_CMAKE_PATH_LIST OUT)"
        (yc_path_convert_to_cmake (ystr "/usr/local") (ycvar "OUT"));
      check "convert_to_native"
        "cmake_path(CONVERT /usr/local TO_NATIVE_PATH_LIST OUT)"
        (yc_path_convert_to_native (ystr "/usr/local") (ycvar "OUT"));
      check "hash"
        "cmake_path(HASH MY_PATH OUT)"
        (yc_path_hash (ycvar "MY_PATH") (ycvar "OUT"));
    ] )

let cmake_language_tests =
  ( "cmake_language",
    [
      check "call_no_args"
        "cmake_language(CALL my_macro )"
        (yc_language_call "my_macro" []);
      check "call_with_args"
        "cmake_language(CALL my_macro foo\nbar)"
        (yc_language_call "my_macro" [ ystr "foo"; ystr "bar" ]);
      check "call_with_cvar"
        "cmake_language(CALL my_macro MY_VAR)"
        (yc_language_call "my_macro" [ ycstr "MY_VAR" ]);
      check "eval_code"
        {|cmake_language(EVAL CODE "message(STATUS hello)")|}
        (yc_language_eval {|message(STATUS hello)|});
      check "get_log_level"
        "cmake_language(GET_MESSAGE_LOG_LEVEL LOG_LEVEL)"
        (yc_language_get_log_level (ycvar "LOG_LEVEL"));
    ] )

let block_tests =
  ( "block",
    [
      check "empty_block"
        "block()\n  \nendblock()"
        (yc_block []);
      check "block_with_vars"
        "block(SCOPE_FOR VARIABLES)\n  \nendblock()"
        (yc_block ~scope_vars:[ ycvar "X"; ycvar "Y" ] []);
      check "block_with_propagate"
        "block(SCOPE_FOR VARIABLES PROPAGATE RESULT)\n  \nendblock()"
        (yc_block ~propagate:"RESULT" []);
      check "block_with_body"
        "block(SCOPE_FOR VARIABLES)\n  set(X hello )\nendblock()"
        (yc_block ~scope_vars:[ ycvar "X" ]
           [ yc_set (ycvar "X") [ ystr "hello" ] ]);
    ] )

let try_compile_tests =
  ( "try_compile",
    [
      check "try_compile_basic"
        "try_compile(RESULT SOURCES test.c )"
        (yc_try_compile (ycvar "RESULT") [ystr "test.c"]);
      check "try_compile_with_output"
        "try_compile(RESULT SOURCES test.c  OUTPUT_VARIABLE OUT)"
        (yc_try_compile ~output_variable:(Some (ycvar "OUT")) (ycvar "RESULT") [ystr "test.c"]);
      check "try_compile_with_defs"
        "try_compile(RESULT SOURCES test.c COMPILE_DEFINITIONS -DFOO )"
        (yc_try_compile ~compile_definitions:[ystr "-DFOO"] (ycvar "RESULT") [ystr "test.c"]);
      check "try_compile_no_cache"
        "try_compile(RESULT SOURCES test.c  NO_CACHE)"
        (yc_try_compile ~no_cache:true (ycvar "RESULT") [ystr "test.c"]);
      check "try_run_basic"
        "try_run(RUN_RESULT COMPILE_RESULT SOURCES test.c )"
        (yc_try_run (ycvar "RUN_RESULT") (ycvar "COMPILE_RESULT") [ystr "test.c"]);
      check "try_run_with_outputs"
        "try_run(RUN_RESULT COMPILE_RESULT SOURCES test.c  COMPILE_OUTPUT_VARIABLE COUT RUN_OUTPUT_VARIABLE ROUT)"
        (yc_try_run
           ~compile_output_variable:(Some (ycvar "COUT"))
           ~run_output_variable:(Some (ycvar "ROUT"))
           (ycvar "RUN_RESULT") (ycvar "COMPILE_RESULT") [ystr "test.c"]);
    ] )

let target_property_tests =
  ( "target_property",
    [
      check "add_custom_target_basic"
        "add_custom_target(mytarget)"
        (yc_add_custom_target "mytarget");
      check "add_custom_target_with_command"
        "add_custom_target(gen COMMAND echo hi )"
        (yc_add_custom_target ~commands:[{ command = "echo"; args = ["hi"] }] "gen");
      check "add_custom_target_with_comment"
        "add_custom_target(gen COMMENT Building )"
        (yc_add_custom_target ~comment:(Some "Building") "gen");
      check "get_target_property_basic"
        "get_target_property(OUT mytarget MY_PROP)"
        (yc_get_target_property (ycvar "OUT") "mytarget" "MY_PROP");
    ] )

let define_property_tests =
  ( "define_property",
    [
      check "define_property_target"
        "define_property(TARGET\nPROPERTY MY_PROP)"
        (yc_define_property Dp_target "MY_PROP");
      check "define_property_global_inherited"
        "define_property(GLOBAL\nPROPERTY G_PROP\nINHERITED )"
        (yc_define_property ~inherited:true Dp_global "G_PROP");
      check "define_property_with_docs"
        "define_property(TARGET\nPROPERTY DOC_PROP BRIEF_DOCS \"a brief\"  FULL_DOCS \"a full\" )"
        (yc_define_property ~brief_docs:["a brief"] ~full_docs:["a full"] Dp_target "DOC_PROP");
      check "define_property_initialize_from"
        "define_property(TARGET\nPROPERTY INIT_PROP\nINITIALIZE_FROM_VARIABLE MY_VAR)"
        (yc_define_property ~initialize_from:(Some "MY_VAR") Dp_target "INIT_PROP");
    ] )

(* Phase 1 progress report: oracle coverage. Printed even on success so
   you can watch the covered count climb toward 194 as Phase 1.3 lands. *)
let () =
  at_exit (fun () ->
    Stdlib.Printf.eprintf
      "[emit_ast oracle] covered=%d  uncovered=%d  (%d total)\n%!"
      !oracle_covered !oracle_uncovered
      (!oracle_covered + !oracle_uncovered))

let () =
  Alcotest.run "Yelu Compile"
    [ primitives; conditions; targets; project_level; composition; let_bindings;
      iteration; loop_control; list_ops; string_ops; scripting_ext; find_package_tests;
      genex_tests; execute_process_tests; file_ops; cmake_language_tests; block_tests;
      cmake_path_tests; try_compile_tests; target_property_tests; define_property_tests;
      ( "add_dependencies",
        [ check "add_dependencies_basic"
            "add_dependencies(mytarget mydep)"
            (yc_add_dependencies "mytarget" "mydep") ] );
      ( "variable_watch",
        [ check "variable_watch_no_command"
            "variable_watch(MY_VAR)"
            (yc_variable_watch (ycvar "MY_VAR"));
          check "variable_watch_with_command"
            "variable_watch(MY_VAR my_callback)"
            (yc_variable_watch ~command:(Some "my_callback") (ycvar "MY_VAR")) ] );
      ( "target_precompile_headers",
        [ check "pch_private"
            "target_precompile_headers(foo PRIVATE <stdio.h>)"
            (yc_target_precompile_headers (ytval "foo")
               [ytarget_def ~kind:Private [yname "<stdio.h>"]]);
          check "pch_public_multi"
            "target_precompile_headers(foo PUBLIC <stdio.h>\nfoo.h)"
            (yc_target_precompile_headers (ytval "foo")
               [ytarget_def ~kind:Public [yname "<stdio.h>"; yname "foo.h"]]);
          check "pch_interface"
            "target_precompile_headers(iface INTERFACE include/bar.h)"
            (yc_target_precompile_headers (ytval "iface")
               [ytarget_def ~kind:Interface [yname "include/bar.h"]]) ] ) ]
