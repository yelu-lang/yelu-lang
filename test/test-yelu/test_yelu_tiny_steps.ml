open Base
let step1_bridge =
  let module Old = Yelu_langs.Lang_yelu_cmake in
  let open Yelu_langs.Lang_yelu_utils in
  let cmd : Old.yelu_stmt =
    ycmd_of_list
      (Step_common.project_preamble
       @ Step_common.cxx_standard_11
       @ [
           ylet "tut" (ytval "Tutorial");
           Step_common.configure_tutorial_header;
           add_exe ~sources:[ yfile "tutorial.cxx" ] (yvar "tut");
           include_dirs (yvar "tut")
             [ ytarget_def [ dir Yelu_langs.Lang_yelu_utils.output_root ] ];
         ])
  in
  ( "step1_bridge",
    [
      Alcotest.test_case "v1 step1 program bridges to Yelu1 and emits cmake"
        `Quick
        (fun () ->
          let yelu1 = Yelu_langs.Yelu_cmake_to_yelu1.stmt cmd in
          let cmake_text =
            Yelu_langs.Yelu_tiny_cmake_emit.emit_script yelu1
          in
          Alcotest.(check bool) "non-empty cmake output"
            true (String.length cmake_text > 0);
          Alcotest.(check bool) "contains project()" true
            (String.is_substring cmake_text ~substring:"project(Tutorial");
          Alcotest.(check bool) "contains configure_file" true
            (String.is_substring cmake_text ~substring:"configure_file(");
          (* Phase 2b — the let-binding `tut = "Tutorial"` substitutes
             through emit, so add_executable and target_include_directories
             see the literal target name "Tutorial" rather than the var
             name "tut". *)
          Alcotest.(check bool) "add_executable uses Tutorial (not tut)" true
            (String.is_substring cmake_text
               ~substring:"add_executable(Tutorial");
          Alcotest.(check bool) "target_include_directories uses Tutorial" true
            (String.is_substring cmake_text
               ~substring:"target_include_directories(Tutorial");
          (* And the let header is dropped — no spurious set(tut ...). *)
          Alcotest.(check bool) "no spurious set(tut ...)" false
            (String.is_substring cmake_text ~substring:"set(tut"));
    ] )

let step2_bridge =
  let module Old = Yelu_langs.Lang_yelu_cmake in
  let open Yelu_langs.Lang_yelu_utils in
  let cmd : Old.yelu_stmt =
    ycmd_of_list
      (Step_common.project_preamble
       @ Step_common.cxx_standard_11
       @ [
           ylet "tut" (ytval "Tutorial");
           Step_common.configure_tutorial_header;
           yc_add_subdirectory (ydir "MathFunctions");
           add_exe ~sources:[ yfile "tutorial.cxx" ] (yvar "tut");
           link_lib
             [ yvar "tut" ]
             [ ytarget_def [ ytval "MathFunctions" ] ];
           include_dirs (yvar "tut")
             [
               ytarget_def
                 [
                   dir Yelu_langs.Lang_yelu_utils.output_root;
                   dir_concat Yelu_langs.Lang_yelu_utils.source_root "MathFunctions";
                 ];
             ];
         ])
  in
  ( "step2_bridge",
    [
      Alcotest.test_case "v1 step2 root program bridges to Yelu1 and emits cmake"
        `Quick
        (fun () ->
          let yelu1 = Yelu_langs.Yelu_cmake_to_yelu1.stmt cmd in
          let cmake_text =
            Yelu_langs.Yelu_tiny_cmake_emit.emit_script yelu1
          in
          Alcotest.(check bool) "contains add_subdirectory" true
            (String.is_substring cmake_text
               ~substring:"add_subdirectory(\"${PROJECT_BINARY_DIR}/MathFunctions\")"
             || String.is_substring cmake_text
                  ~substring:"add_subdirectory(\"${PROJECT_SOURCE_DIR}/MathFunctions\")"
             || String.is_substring cmake_text
                  ~substring:"add_subdirectory(\"MathFunctions\")");
          Alcotest.(check bool) "add_executable uses Tutorial" true
            (String.is_substring cmake_text
               ~substring:"add_executable(Tutorial");
          Alcotest.(check bool) "target_link_libraries uses Tutorial" true
            (String.is_substring cmake_text
               ~substring:"target_link_libraries(Tutorial");
          Alcotest.(check bool) "links MathFunctions" true
            (String.is_substring cmake_text ~substring:"MathFunctions");
          Alcotest.(check bool) "contains source MathFunctions include" true
            (String.is_substring cmake_text
               ~substring:"${PROJECT_SOURCE_DIR}/MathFunctions");
	          Alcotest.(check bool) "no spurious set(tut ...)" false
	            (String.is_substring cmake_text ~substring:"set(tut"));
	    ] )

let step2_math_bridge =
  let module Old = Yelu_langs.Lang_yelu_cmake in
  let open Yelu_langs.Lang_yelu_utils in
  let cmd : Old.yelu_stmt =
    ycmd_of_list
      [
        ylet "math" (ytval "MathFunctions");
        ylet "sqrt" (ytval "SqrtLibrary");
        ylet "use_mymath" (ycstr "USE_MYMATH");
        add_lib ~sources:[ yfile "MathFunctions.cxx" ] (yvar "math");
        yc_option ~value:(ybool true)
          ~msg:"Use tutorial provided math implementation" (ycvar "USE_MYMATH");
        yifthen
          (ytruthy (yvar "use_mymath"))
          (ycmd_of_list
             [
               compile_defs (yvar "math")
                 [ ytarget_def ~kind:Private [ ykeyword "USE_MYMATH" ] ];
               add_lib ~type_:Lib_static
                 ~sources:[ yfile "mysqrt.cxx" ]
                 (yvar "sqrt");
               link_lib
                 [ yvar "math" ]
                 [ ytarget_def ~kind:Private [ yvar "sqrt" ] ];
             ]);
      ]
  in
  ( "step2_math_bridge",
    [
      Alcotest.test_case "v1 step2 math program bridges to Yelu1 and emits cmake"
        `Quick
        (fun () ->
          let yelu1 = Yelu_langs.Yelu_cmake_to_yelu1.stmt cmd in
          let cmake_text =
            Yelu_langs.Yelu_tiny_cmake_emit.emit_script yelu1
          in
          Alcotest.(check bool) "contains MathFunctions library" true
            (String.is_substring cmake_text
               ~substring:"add_library(MathFunctions");
          Alcotest.(check bool) "contains option" true
            (String.is_substring cmake_text
               ~substring:
                 "option(USE_MYMATH \"Use tutorial provided math implementation\" ON)");
          Alcotest.(check bool) "contains USE_MYMATH condition" true
            (String.is_substring cmake_text ~substring:"if(");
          Alcotest.(check bool) "contains compile definition" true
            (String.is_substring cmake_text
               ~substring:"target_compile_definitions(MathFunctions PRIVATE");
          Alcotest.(check bool) "contains SqrtLibrary" true
            (String.is_substring cmake_text ~substring:"SqrtLibrary");
          Alcotest.(check bool) "no spurious set(math ...)" false
            (String.is_substring cmake_text ~substring:"set(math"));
	    ] )

let step3_bridge =
  let module Old = Yelu_langs.Lang_yelu_cmake in
  let open Yelu_langs.Lang_yelu_utils in
  let cmd : Old.yelu_stmt =
    ycmd_of_list
      (Step_common.project_preamble
       @ [
           ylet "tut" (ytval "Tutorial");
           ylet "flags" (ytval "tutorial_compiler_flags");
         ]
       @ Step_common.compiler_flags_lib
       @ Step_common.cxx_standard_11
       @ [
           Step_common.configure_tutorial_header;
           yc_add_subdirectory (ydir "MathFunctions");
           add_exe ~sources:[ yfile "tutorial.cxx" ] (yvar "tut");
           link_lib
             [ yvar "tut" ]
             [ ytarget_def [ ytval "MathFunctions"; yvar "flags" ] ];
           include_dirs (yvar "tut")
             [ ytarget_def [ dir Yelu_langs.Lang_yelu_utils.output_root ] ];
         ])
  in
  ( "step3_bridge",
    [
      Alcotest.test_case "v1 step3 root program bridges to Yelu1 and emits cmake"
        `Quick
        (fun () ->
          let yelu1 = Yelu_langs.Yelu_cmake_to_yelu1.stmt cmd in
          let cmake_text =
            Yelu_langs.Yelu_tiny_cmake_emit.emit_script yelu1
          in
          Alcotest.(check bool) "contains compiler flags interface library" true
            (String.is_substring cmake_text
               ~substring:"add_library(tutorial_compiler_flags INTERFACE");
          Alcotest.(check bool) "contains compile features" true
            (String.is_substring cmake_text
               ~substring:
                 "target_compile_features(tutorial_compiler_flags INTERFACE cxx_std_11)");
          Alcotest.(check bool) "target_link_libraries uses flags" true
            (String.is_substring cmake_text
               ~substring:"target_link_libraries(Tutorial");
          Alcotest.(check bool) "mentions compiler flags target" true
            (String.is_substring cmake_text ~substring:"tutorial_compiler_flags");
    )
    ] )

let step3_math_bridge =
  let module Old = Yelu_langs.Lang_yelu_cmake in
  let open Yelu_langs.Lang_yelu_utils in
  let cmd : Old.yelu_stmt =
    ycmd_of_list
      [
        ylet "flags" (ytval "tutorial_compiler_flags");
        ylet "math" (ytval "MathFunctions");
        ylet "sqrt" (ytval "SqrtLibrary");
        ylet "use_mymath" (ycstr "USE_MYMATH");
        yc_extern_target "tutorial_compiler_flags";
        add_lib ~sources:[ yfile "MathFunctions.cxx" ] (yvar "math");
        include_dirs (yvar "math")
          [ ytarget_def ~kind:Interface [ ydir "${CMAKE_CURRENT_SOURCE_DIR}" ] ];
        yc_option ~value:(ybool true)
          ~msg:"Use tutorial provided math implementation" (ycvar "USE_MYMATH");
        yifthen (ytruthy (yvar "use_mymath"))
          (ycmd_of_list
             [
               compile_defs (yvar "math")
                 [ ytarget_def ~kind:Private [ ykeyword "USE_MYMATH" ] ];
               add_lib ~type_:Lib_static ~sources:[ yfile "mysqrt.cxx" ]
                 (yvar "sqrt");
               link_lib [ yvar "sqrt" ]
                 [ ytarget_def ~kind:Public [ yvar "flags" ] ];
               link_lib [ yvar "math" ]
                 [ ytarget_def ~kind:Private [ yvar "sqrt" ] ];
             ]);
        link_lib [ yvar "math" ]
          [ ytarget_def ~kind:Public [ yvar "flags" ] ];
      ]
  in
  ( "step3_math_bridge",
    [
      Alcotest.test_case "v1 step3 math program bridges to Yelu1 and emits cmake"
        `Quick
        (fun () ->
          let yelu1 = Yelu_langs.Yelu_cmake_to_yelu1.stmt cmd in
          let cmake_text =
            Yelu_langs.Yelu_tiny_cmake_emit.emit_script yelu1
          in
          Alcotest.(check bool) "contains MathFunctions include dirs" true
            (String.is_substring cmake_text
               ~substring:"target_include_directories(MathFunctions INTERFACE");
          Alcotest.(check bool) "SqrtLibrary links flags" true
            (String.is_substring cmake_text
               ~substring:"target_link_libraries(SqrtLibrary");
          Alcotest.(check bool) "MathFunctions links flags" true
            (String.is_substring cmake_text
               ~substring:"target_link_libraries(MathFunctions PUBLIC");
          Alcotest.(check bool) "mentions compiler flags target" true
            (String.is_substring cmake_text ~substring:"tutorial_compiler_flags");
    )
    ] )

let step4_bridge =
  let module Old = Yelu_langs.Lang_yelu_cmake in
  let open Yelu_langs.Lang_yelu_utils in
  let cmd : Old.yelu_stmt =
    ycmd_of_list
      (Step_common.project_preamble
       @ [
           ylet "tut" (ytval "Tutorial");
           ylet "flags" (ytval "tutorial_compiler_flags");
         ]
       @ Step_common.compiler_flags_lib
       @ Step_common.compiler_warning_options
       @ [
           Step_common.configure_tutorial_header;
           yc_add_subdirectory (ydir "MathFunctions");
           add_exe ~sources:[ yfile "tutorial.cxx" ] (yvar "tut");
           link_lib [ yvar "tut" ]
             [ ytarget_def [ ytval "MathFunctions"; yvar "flags" ] ];
           include_dirs (yvar "tut")
             [ ytarget_def [ dir Yelu_langs.Lang_yelu_utils.output_root ] ];
         ])
  in
  ( "step4_bridge",
    [
      Alcotest.test_case "v1 step4 root program bridges to Yelu1 and emits cmake"
        `Quick
        (fun () ->
          let yelu1 = Yelu_langs.Yelu_cmake_to_yelu1.stmt cmd in
          let cmake_text =
            Yelu_langs.Yelu_tiny_cmake_emit.emit_script yelu1
          in
          Alcotest.(check bool) "contains gcc-like detector var" true
            (String.is_substring cmake_text ~substring:"set(gcc_like_cxx");
          Alcotest.(check bool) "contains msvc detector var" true
            (String.is_substring cmake_text ~substring:"set(msvc_cxx");
          Alcotest.(check bool) "contains target compile options" true
            (String.is_substring cmake_text
               ~substring:"target_compile_options(tutorial_compiler_flags INTERFACE");
          Alcotest.(check bool) "contains BUILD_INTERFACE generator expression" true
            (String.is_substring cmake_text ~substring:"BUILD_INTERFACE");
    )
    ] )

let step5_bridge =
  let module Old = Yelu_langs.Lang_yelu_cmake in
  let open Yelu_langs.Lang_yelu_utils in
  let cmd : Old.yelu_stmt =
    ycmd_of_list
      (Step_common.project_preamble
       @ [
           ylet "tut" (ytval "Tutorial");
           ylet "flags" (ytval "tutorial_compiler_flags");
           ylet "do_test" (ycstr "do_test");
         ]
       @ Step_common.compiler_flags_lib
       @ Step_common.compiler_warning_options
       @ [
           Step_common.configure_tutorial_header;
           yc_add_subdirectory (ydir "MathFunctions");
           add_exe ~sources:[ yfile "tutorial.cxx" ] (yvar "tut");
           link_lib [ yvar "tut" ]
             [ ytarget_def [ ytval "MathFunctions"; yvar "flags" ] ];
           include_dirs (yvar "tut")
             [ ytarget_def [ dir Yelu_langs.Lang_yelu_utils.output_root ] ];
         ]
       @ Step_common.install_tutorial
       @ Step_common.test_suite ~ctest:false)
  in
  ( "step5_bridge",
    [
      Alcotest.test_case "v1 step5 root program bridges to Yelu1 and emits cmake"
        `Quick
        (fun () ->
          let yelu1 = Yelu_langs.Yelu_cmake_to_yelu1.stmt cmd in
          let cmake_text =
            Yelu_langs.Yelu_tiny_cmake_emit.emit_script yelu1
          in
          Alcotest.(check bool) "contains install target rule" true
            (String.is_substring cmake_text ~substring:"install(TARGETS Tutorial");
          Alcotest.(check bool) "contains enable_testing" true
            (String.is_substring cmake_text ~substring:"enable_testing()");
          Alcotest.(check bool) "contains do_test function" true
            (String.is_substring cmake_text ~substring:"function(do_test");
          Alcotest.(check bool) "contains do_test application" true
            (String.is_substring cmake_text ~substring:"do_test(");
    )
    ] )

let step5_math_bridge =
  let module Old = Yelu_langs.Lang_yelu_cmake in
  let open Yelu_langs.Lang_yelu_utils in
  let cmd : Old.yelu_stmt =
    ycmd_of_list
      ([
         ylet "flags" (ytval "tutorial_compiler_flags");
         ylet "math" (ytval "MathFunctions");
         ylet "sqrt" (ytval "SqrtLibrary");
         ylet "inst_libs" (ycstr "installable_libs");
         ylet "use_mymath" (ycstr "USE_MYMATH");
         yc_extern_target "tutorial_compiler_flags";
         add_lib ~sources:[ yfile "MathFunctions.cxx" ] (yvar "math");
         include_dirs (yvar "math")
           [ ytarget_def ~kind:Interface [ ydir "${CMAKE_CURRENT_SOURCE_DIR}" ] ];
         yc_option ~value:(ybool true)
           ~msg:"Use tutorial provided math implementation" (ycvar "USE_MYMATH");
         yifthen (ytruthy (yvar "use_mymath"))
           (ycmd_of_list
              [
                compile_defs (yvar "math")
                  [ ytarget_def ~kind:Private [ ykeyword "USE_MYMATH" ] ];
                add_lib ~type_:Lib_static ~sources:[ yfile "mysqrt.cxx" ]
                  (yvar "sqrt");
                link_lib [ yvar "sqrt" ]
                  [ ytarget_def ~kind:Public [ yvar "flags" ] ];
                link_lib [ yvar "math" ]
                  [ ytarget_def ~kind:Private [ yvar "sqrt" ] ];
              ]);
         link_lib [ yvar "math" ]
           [ ytarget_def ~kind:Public [ yvar "flags" ] ];
       ]
       @ Step_common.math_install_libs ())
  in
  ( "step5_math_bridge",
    [
      Alcotest.test_case "v1 step5 math program bridges to Yelu1 and emits cmake"
        `Quick
        (fun () ->
          let yelu1 = Yelu_langs.Yelu_cmake_to_yelu1.stmt cmd in
          let cmake_text =
            Yelu_langs.Yelu_tiny_cmake_emit.emit_script yelu1
          in
          Alcotest.(check bool) "contains installable_libs set" true
            (String.is_substring cmake_text ~substring:"set(installable_libs");
          Alcotest.(check bool) "contains guarded list append" true
            (String.is_substring cmake_text ~substring:"list(APPEND installable_libs");
          Alcotest.(check bool) "contains library install rule" true
            (String.is_substring cmake_text ~substring:"install(TARGETS ${installable_libs}");
          Alcotest.(check bool) "contains header install rule" true
            (String.is_substring cmake_text ~substring:"install(FILES \"MathFunctions.h\"");
    )
    ] )

let step6_bridge =
  let module Old = Yelu_langs.Lang_yelu_cmake in
  let open Yelu_langs.Lang_yelu_utils in
  let cmd : Old.yelu_stmt =
    ycmd_of_list
      (Step_common.project_preamble
       @ [
           ylet "tut" (ytval "Tutorial");
           ylet "flags" (ytval "tutorial_compiler_flags");
           ylet "do_test" (ycstr "do_test");
         ]
       @ Step_common.compiler_flags_lib
       @ Step_common.compiler_warning_options
       @ [
           Step_common.configure_tutorial_header;
           yc_add_subdirectory (ydir "MathFunctions");
           add_exe ~sources:[ yfile "tutorial.cxx" ] (yvar "tut");
           link_lib [ yvar "tut" ]
             [ ytarget_def [ ytval "MathFunctions"; yvar "flags" ] ];
           include_dirs (yvar "tut")
             [ ytarget_def [ dir Yelu_langs.Lang_yelu_utils.output_root ] ];
         ]
       @ Step_common.install_tutorial
       @ Step_common.test_suite ~ctest:true)
  in
  ( "step6_bridge",
    [
      Alcotest.test_case "v1 step6 root program bridges to Yelu1 and emits cmake"
        `Quick
        (fun () ->
          let yelu1 = Yelu_langs.Yelu_cmake_to_yelu1.stmt cmd in
          let cmake_text =
            Yelu_langs.Yelu_tiny_cmake_emit.emit_script yelu1
          in
          Alcotest.(check bool) "step6 uses include(CTest) instead of enable_testing()"
            true
            (String.is_substring cmake_text ~substring:"include(\"CTest\")");
          Alcotest.(check bool) "no enable_testing() in step6"
            false
            (String.is_substring cmake_text ~substring:"enable_testing()");
          Alcotest.(check bool) "step6 still installs Tutorial"
            true
            (String.is_substring cmake_text ~substring:"install(TARGETS Tutorial");
    )
    ] )

let step6_ctest_bridge =
  let module Old = Yelu_langs.Lang_yelu_cmake in
  let open Yelu_langs.Lang_yelu_utils in
  let cmd : Old.yelu_stmt =
    ycmd_of_list
      [
        yc_set (ycvar "CTEST_PROJECT_NAME") [ ystr "CMakeTutorial" ];
        yc_set (ycvar "CTEST_NIGHTLY_START_TIME") [ ystr "00:00:00 EST" ];
        yc_set (ycvar "CTEST_DROP_METHOD") [ ystr "http" ];
        yc_set (ycvar "CTEST_DROP_SITE") [ ystr "my.cdash.org" ];
        yc_set (ycvar "CTEST_DROP_LOCATION")
          [ ystr "/submit.php?project=CMakeTutorial" ];
        yc_set (ycvar "CTEST_DROP_SITE_CDASH") [ ystr "TRUE" ];
      ]
  in
  ( "step6_ctest_bridge",
    [
      Alcotest.test_case "v1 step6_ctest config bridges to Yelu1 and emits cmake"
        `Quick
        (fun () ->
          let yelu1 = Yelu_langs.Yelu_cmake_to_yelu1.stmt cmd in
          let cmake_text =
            Yelu_langs.Yelu_tiny_cmake_emit.emit_script yelu1
          in
          Alcotest.(check bool) "contains CTEST_PROJECT_NAME"
            true
            (String.is_substring cmake_text ~substring:"set(CTEST_PROJECT_NAME");
          Alcotest.(check bool) "contains CTEST_DROP_SITE"
            true
            (String.is_substring cmake_text ~substring:"set(CTEST_DROP_SITE");
    )
    ] )

let () =
  Alcotest.run "yelu_tiny_steps"
    [
      step1_bridge;
      step2_bridge;
      step2_math_bridge;
      step3_bridge;
      step3_math_bridge;
      step4_bridge;
      step5_bridge;
      step5_math_bridge;
      step6_bridge;
      step6_ctest_bridge;
    ]
