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

(* step7 root is structurally identical to step6 root in our generators
   (see [diff src/bin/yelu/v1/step6.ml step7.ml] — empty). The bridge test
   exists to pin the contract: future divergence in the helpers should
   surface here, not in step6_bridge. *)
let step7_bridge =
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
  ( "step7_bridge",
    [
      Alcotest.test_case "v1 step7 root program bridges to Yelu1 and emits cmake"
        `Quick
        (fun () ->
          let yelu1 = Yelu_langs.Yelu_cmake_to_yelu1.stmt cmd in
          let cmake_text =
            Yelu_langs.Yelu_tiny_cmake_emit.emit_script yelu1
          in
          Alcotest.(check bool) "step7 uses include(CTest)" true
            (String.is_substring cmake_text ~substring:"include(\"CTest\")");
          Alcotest.(check bool) "step7 still installs Tutorial" true
            (String.is_substring cmake_text ~substring:"install(TARGETS Tutorial"))
    ] )

(* step7_math exercises the new include() + apply pieces that step6_math
   does not: math_check_cxx_features inserts [include(CheckCXXSourceCompiles)]
   followed by [check_cxx_source_compiles(...)] calls. The apply name comes
   in as [yvar "check_cxx"], let-bound to "check_cxx_source_compiles" — so
   this also pins the bridge's expr-preserving treatment of apply names
   (no command_name short-circuit) and the lenient surface ECmakeApply
   semantics (the function body lives in the included module, not in env). *)
let step7_math_bridge =
  let module Old = Yelu_langs.Lang_yelu_cmake in
  let open Yelu_langs.Lang_yelu_utils in
  let cmd : Old.yelu_stmt =
    ycmd_of_list
      ([
         ylet "flags" (ytval "tutorial_compiler_flags");
         ylet "math" (ytval "MathFunctions");
         ylet "sqrt" (ytval "SqrtLibrary");
         ylet "check_cxx" (ycstr "check_cxx_source_compiles");
         ylet "inst_libs" (ycstr "installable_libs");
         ylet "have_log" (ycstr "HAVE_LOG");
         ylet "have_exp" (ycstr "HAVE_EXP");
         ylet "use_mymath" (ycstr "USE_MYMATH");
         yc_extern_target "tutorial_compiler_flags";
         add_lib ~sources:[ yfile "MathFunctions.cxx" ] (yvar "math");
         include_dirs (yvar "math")
           [ ytarget_def ~kind:Interface [ ydir "${CMAKE_CURRENT_SOURCE_DIR}" ] ];
         yc_option ~value:(ybool true)
           ~msg:"Use tutorial provided math implementation" (ycvar "USE_MYMATH");
         yifthen (ytruthy (yvar "use_mymath"))
           (ycmd_of_list
              ([
                 compile_defs (yvar "math")
                   [ ytarget_def ~kind:Private [ ykeyword "USE_MYMATH" ] ];
                 add_lib ~type_:Lib_static ~sources:[ yfile "mysqrt.cxx" ]
                   (yvar "sqrt");
                 link_lib [ yvar "sqrt" ]
                   [ ytarget_def ~kind:Public [ yvar "flags" ] ];
               ]
              @ Step_common.math_check_cxx_features
              @ [
                  link_lib [ yvar "math" ]
                    [ ytarget_def ~kind:Private [ yvar "sqrt" ] ];
                ]));
         link_lib [ yvar "math" ]
           [ ytarget_def ~kind:Public [ yvar "flags" ] ];
       ]
      @ Step_common.math_install_libs ())
  in
  ( "step7_math_bridge",
    [
      Alcotest.test_case "v1 step7 MathFunctions bridges, including check_cxx apply"
        `Quick
        (fun () ->
          let yelu1 = Yelu_langs.Yelu_cmake_to_yelu1.stmt cmd in
          let cmake_text =
            Yelu_langs.Yelu_tiny_cmake_emit.emit_script yelu1
          in
          Alcotest.(check bool) "include(CheckCXXSourceCompiles) emitted" true
            (String.is_substring cmake_text
               ~substring:"include(\"CheckCXXSourceCompiles\")");
          (* The let binding check_cxx = "check_cxx_source_compiles" must
             substitute through emit so the apply name is the cmake module
             function, not the let-var name. *)
          Alcotest.(check bool) "apply lowered to check_cxx_source_compiles(..)"
            true
            (String.is_substring cmake_text
               ~substring:"check_cxx_source_compiles(");
          Alcotest.(check bool) "no stray check_cxx( as a bare command" false
            (String.is_substring cmake_text ~substring:"check_cxx(");
          Alcotest.(check bool) "still emits the math target setup" true
            (String.is_substring cmake_text
               ~substring:"add_library(MathFunctions"))
    ] )

(* step8_table introduces the OUTPUT form of [add_custom_command]: a build
   rule that produces [outputs] by running [commands], with optional
   [DEPENDS]. The bridge already supports this via [Ytgt_add_custom_command]
   (vs the deferred TARGET-form sibling [Ytgt_add_custom_command_target]). *)
let step8_table_bridge =
  let module Old = Yelu_langs.Lang_yelu_cmake in
  let open Yelu_langs.Lang_yelu_utils in
  let cmd : Old.yelu_stmt =
    ycmd_of_list
      [
        yc_extern_target "tutorial_compiler_flags";
        add_exe ~sources:[ yfile "MakeTable.cxx" ] (ytval "MakeTable");
        link_lib [ ytval "MakeTable" ]
          [ ytarget_def ~kind:Private [ ytval "tutorial_compiler_flags" ] ];
        yc_add_custom_command
          ~outputs:[ yfile "${CMAKE_CURRENT_BINARY_DIR}/Table.h" ]
          ~depends:[ ystr "MakeTable" ]
          [ custom_command "MakeTable" [ "${CMAKE_CURRENT_BINARY_DIR}/Table.h" ] ];
      ]
  in
  ( "step8_table_bridge",
    [
      Alcotest.test_case "v1 step8_table MathFunctions/MakeTable bridges to Yelu1"
        `Quick
        (fun () ->
          let yelu1 = Yelu_langs.Yelu_cmake_to_yelu1.stmt cmd in
          let cmake_text =
            Yelu_langs.Yelu_tiny_cmake_emit.emit_script yelu1
          in
          Alcotest.(check bool) "emits add_executable for MakeTable" true
            (String.is_substring cmake_text
               ~substring:"add_executable(MakeTable");
          Alcotest.(check bool) "emits add_custom_command(" true
            (String.is_substring cmake_text
               ~substring:"add_custom_command(");
          Alcotest.(check bool) "emits OUTPUT clause on a continuation line" true
            (String.is_substring cmake_text ~substring:"OUTPUT");
          Alcotest.(check bool) "emits the Table.h output" true
            (String.is_substring cmake_text ~substring:"Table.h");
          Alcotest.(check bool) "emits DEPENDS MakeTable" true
            (String.is_substring cmake_text ~substring:"DEPENDS"))
    ] )

(* step8_math adds [include("MakeTable.cmake")] (Tier A) and a generated
   source ${CMAKE_CURRENT_BINARY_DIR}/Table.h passed to add_library. Both
   are existing pieces — this test confirms they compose. *)
let step8_math_bridge =
  let module Old = Yelu_langs.Lang_yelu_cmake in
  let open Yelu_langs.Lang_yelu_utils in
  let cmd : Old.yelu_stmt =
    ycmd_of_list
      ([
         ylet "flags" (ytval "tutorial_compiler_flags");
         ylet "math" (ytval "MathFunctions");
         ylet "sqrt" (ytval "SqrtLibrary");
         ylet "check_cxx" (ycstr "check_cxx_source_compiles");
         ylet "inst_libs" (ycstr "installable_libs");
         ylet "have_log" (ycstr "HAVE_LOG");
         ylet "have_exp" (ycstr "HAVE_EXP");
         ylet "use_mymath" (ycstr "USE_MYMATH");
         yc_extern_target "tutorial_compiler_flags";
         yc_include (yfile "MakeTable.cmake");
         add_lib ~sources:[ yfile "MathFunctions.cxx" ] (yvar "math");
         include_dirs (yvar "math")
           [ ytarget_def ~kind:Interface [ ydir "${CMAKE_CURRENT_SOURCE_DIR}" ] ];
         yc_option ~value:(ybool true)
           ~msg:"Use tutorial provided math implementation" (ycvar "USE_MYMATH");
         yifthen (ytruthy (yvar "use_mymath"))
           (ycmd_of_list
              ([
                 compile_defs (yvar "math")
                   [ ytarget_def ~kind:Private [ ykeyword "USE_MYMATH" ] ];
                 add_lib ~type_:Lib_static
                   ~sources:[ yfile "mysqrt.cxx";
                              yfile "${CMAKE_CURRENT_BINARY_DIR}/Table.h" ]
                   (yvar "sqrt");
                 include_dirs (yvar "sqrt")
                   [
                     ytarget_def ~kind:Private
                       [ ydir "${CMAKE_CURRENT_BINARY_DIR}" ];
                   ];
                 link_lib [ yvar "sqrt" ]
                   [ ytarget_def ~kind:Public [ yvar "flags" ] ];
               ]
              @ Step_common.math_check_cxx_features
              @ [
                  link_lib [ yvar "math" ]
                    [ ytarget_def ~kind:Private [ yvar "sqrt" ] ];
                ]));
         link_lib [ yvar "math" ]
           [ ytarget_def ~kind:Public [ yvar "flags" ] ];
       ]
      @ Step_common.math_install_libs ())
  in
  ( "step8_math_bridge",
    [
      Alcotest.test_case "v1 step8 MathFunctions bridges to Yelu1"
        `Quick
        (fun () ->
          let yelu1 = Yelu_langs.Yelu_cmake_to_yelu1.stmt cmd in
          let cmake_text =
            Yelu_langs.Yelu_tiny_cmake_emit.emit_script yelu1
          in
          Alcotest.(check bool) "emits include(MakeTable.cmake)" true
            (String.is_substring cmake_text
               ~substring:"include(\"MakeTable.cmake\")");
          Alcotest.(check bool) "Table.h appears as a source to sqrt" true
            (String.is_substring cmake_text ~substring:"Table.h");
          Alcotest.(check bool) "still emits the math target setup" true
            (String.is_substring cmake_text
               ~substring:"add_library(MathFunctions"))
    ] )

(* step9 layers [cpack_basic] (a sequence of [yc_set] + [include(CPack)] +
   [include(InstallRequiredSystemLibraries)]) on top of step6/step7. All
   pieces — Tier A include(), set-to-cache, ystr_eval — are already
   bridged; this test pins composition. *)
let step9_bridge =
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
       @ Step_common.test_suite ~ctest:true
       @ Step_common.cpack_basic)
  in
  ( "step9_bridge",
    [
      Alcotest.test_case "v1 step9 root program bridges to Yelu1 (adds cpack_basic)"
        `Quick
        (fun () ->
          let yelu1 = Yelu_langs.Yelu_cmake_to_yelu1.stmt cmd in
          let cmake_text =
            Yelu_langs.Yelu_tiny_cmake_emit.emit_script yelu1
          in
          Alcotest.(check bool) "emits include(CPack)" true
            (String.is_substring cmake_text ~substring:"include(\"CPack\")");
          Alcotest.(check bool) "emits include(InstallRequiredSystemLibraries)" true
            (String.is_substring cmake_text
               ~substring:"include(\"InstallRequiredSystemLibraries\")");
          Alcotest.(check bool) "emits CPACK_GENERATOR set" true
            (String.is_substring cmake_text ~substring:"set(CPACK_GENERATOR");
          Alcotest.(check bool) "still keeps step6 include(CTest)" true
            (String.is_substring cmake_text ~substring:"include(\"CTest\")"))
    ] )

(* step10 adds [shared_libs_output_dirs] (three more yc_set to standard
   cmake cache vars + BUILD_SHARED_LIBS option) on top of step9. *)
let step10_bridge =
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
       @ Step_common.shared_libs_output_dirs
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
       @ Step_common.test_suite ~ctest:true
       @ Step_common.cpack_basic)
  in
  ( "step10_bridge",
    [
      Alcotest.test_case "v1 step10 root program bridges (adds shared_libs_output_dirs)"
        `Quick
        (fun () ->
          let yelu1 = Yelu_langs.Yelu_cmake_to_yelu1.stmt cmd in
          let cmake_text =
            Yelu_langs.Yelu_tiny_cmake_emit.emit_script yelu1
          in
          Alcotest.(check bool) "emits CMAKE_RUNTIME_OUTPUT_DIRECTORY" true
            (String.is_substring cmake_text
               ~substring:"set(CMAKE_RUNTIME_OUTPUT_DIRECTORY");
          Alcotest.(check bool) "emits CMAKE_LIBRARY_OUTPUT_DIRECTORY" true
            (String.is_substring cmake_text
               ~substring:"set(CMAKE_LIBRARY_OUTPUT_DIRECTORY");
          Alcotest.(check bool) "emits CMAKE_ARCHIVE_OUTPUT_DIRECTORY" true
            (String.is_substring cmake_text
               ~substring:"set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY");
          Alcotest.(check bool) "emits BUILD_SHARED_LIBS option" true
            (String.is_substring cmake_text
               ~substring:"option(BUILD_SHARED_LIBS"))
    ] )

(* step11_config (one of the two files step11 generates) is the smallest
   exercise of [yc_at_var]: just [@PACKAGE_INIT@] followed by an include.
   PACKAGE_INIT itself is later substituted by [configure_package_config_file]
   running over a *.cmake.in template — at script-emit time it's plain
   text [@PACKAGE_INIT@]. *)
let step11_config_bridge =
  let module Old = Yelu_langs.Lang_yelu_cmake in
  let open Yelu_langs.Lang_yelu_utils in
  let cmd : Old.yelu_stmt =
    ycmd_of_list
      [
        yc_at_var "PACKAGE_INIT";
        yc_include
          (dir_concat Yelu_langs.Lang_yelu_utils.list_this
             "MathFunctionsTargets.cmake");
      ]
  in
  ( "step11_config_bridge",
    [
      Alcotest.test_case "v1 step11_config bridges yc_at_var and include"
        `Quick
        (fun () ->
          let yelu1 = Yelu_langs.Yelu_cmake_to_yelu1.stmt cmd in
          let cmake_text =
            Yelu_langs.Yelu_tiny_cmake_emit.emit_script yelu1
          in
          Alcotest.(check bool) "contains literal @PACKAGE_INIT@" true
            (String.is_substring cmake_text ~substring:"@PACKAGE_INIT@");
          Alcotest.(check bool) "contains include of MathFunctionsTargets.cmake"
            true
            (String.is_substring cmake_text
               ~substring:"MathFunctionsTargets.cmake"))
    ] )

(* step11 root composes the package-config family on top of step10:
   install(EXPORT), include(CMakePackageConfigHelpers),
   configure_package_config_file, write_basic_package_version_file,
   install(FILES ...), a second install(EXPORT), and an export(EXPORT).
   All four constructs are Tier F additions. *)
let step11_bridge =
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
       @ Step_common.shared_libs_output_dirs
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
       @ Step_common.test_suite ~ctest:true
       @ Step_common.cpack_basic
       @ [
           yc_install_export
             ~file:(yfile "MathFunctionsTargets.cmake")
             (ystr "MathFunctionsTargets")
             (ydir "lib/cmake/MathFunctions");
           yc_include (yfile "CMakePackageConfigHelpers");
           yc_configure_package_config_file ~no_set_and_check_macro:true
             ~no_check_required_components_macro:true
             (ydir "lib/cmake/MathFunctions")
             (yfile "${CMAKE_CURRENT_SOURCE_DIR}/Config.cmake.in")
             (dir_concat Yelu_langs.Lang_yelu_utils.output_this
                "MathFunctionsConfig.cmake");
           yc_write_basic_package_version_file
             ~compatibility:Yelu_langs.Lang_cmake.Any_newer_version
             ~version:(ystr_eval
                         "${Tutorial_VERSION_MAJOR}.${Tutorial_VERSION_MINOR}")
             (dir_concat Yelu_langs.Lang_yelu_utils.output_this
                "MathFunctionsConfigVersion.cmake");
           yc_install_files
             [
               yfile "${CMAKE_CURRENT_BINARY_DIR}/MathFunctionsConfig.cmake";
               yfile "${CMAKE_CURRENT_BINARY_DIR}/MathFunctionsConfigVersion.cmake";
             ]
             (ydir "lib/cmake/MathFunctions");
           yc_install_export
             ~file:(yfile "MathFunctionsTargets.cmake")
             (ystr "MathFunctionsTargets")
             (ydir "lib/cmake/MathFunctions");
           yc_export_export (ystr "MathFunctionsTargets")
             ~file:(dir_concat Yelu_langs.Lang_yelu_utils.output_this
                      "MathFunctionsTargets.cmake");
         ])
  in
  ( "step11_bridge",
    [
      Alcotest.test_case "v1 step11 root bridges package-config family"
        `Quick
        (fun () ->
          let yelu1 = Yelu_langs.Yelu_cmake_to_yelu1.stmt cmd in
          let cmake_text =
            Yelu_langs.Yelu_tiny_cmake_emit.emit_script yelu1
          in
          Alcotest.(check bool) "emits install(EXPORT MathFunctionsTargets ...)" true
            (String.is_substring cmake_text
               ~substring:"install(EXPORT \"MathFunctionsTargets\"");
          Alcotest.(check bool) "emits include(CMakePackageConfigHelpers)" true
            (String.is_substring cmake_text
               ~substring:"include(\"CMakePackageConfigHelpers\")");
          Alcotest.(check bool) "emits configure_package_config_file(" true
            (String.is_substring cmake_text
               ~substring:"configure_package_config_file(");
          Alcotest.(check bool) "emits NO_SET_AND_CHECK_MACRO" true
            (String.is_substring cmake_text
               ~substring:"NO_SET_AND_CHECK_MACRO");
          Alcotest.(check bool) "emits write_basic_package_version_file(" true
            (String.is_substring cmake_text
               ~substring:"write_basic_package_version_file(");
          Alcotest.(check bool) "emits COMPATIBILITY AnyNewerVersion" true
            (String.is_substring cmake_text
               ~substring:"COMPATIBILITY AnyNewerVersion");
          Alcotest.(check bool) "emits export(EXPORT MathFunctionsTargets ...)" true
            (String.is_substring cmake_text
               ~substring:"export(EXPORT \"MathFunctionsTargets\""))
    ] )

(* step12 adds set_target_properties(DEBUG_POSTFIX) and an extra
   CMAKE_DEBUG_POSTFIX set on top of step11. Same package-config family. *)
let step12_bridge =
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
       @ Step_common.shared_libs_output_dirs
       @ [ yc_set (ycvar "CMAKE_DEBUG_POSTFIX") [ ystr "d" ] ]
       @ Step_common.compiler_flags_lib
       @ Step_common.compiler_warning_options
       @ [
           Step_common.configure_tutorial_header;
           yc_add_subdirectory (ydir "MathFunctions");
           add_exe ~sources:[ yfile "tutorial.cxx" ] (yvar "tut");
           yc_set_target_properties (yvar "tut")
             [ ("DEBUG_POSTFIX", ystr "${CMAKE_DEBUG_POSTFIX}") ];
           link_lib [ yvar "tut" ]
             [ ytarget_def [ ytval "MathFunctions"; yvar "flags" ] ];
           include_dirs (yvar "tut")
             [ ytarget_def [ dir Yelu_langs.Lang_yelu_utils.output_root ] ];
         ]
       @ Step_common.install_tutorial
       @ Step_common.test_suite ~ctest:true
       @ Step_common.cpack_basic
       @ [
           yc_install_export
             ~file:(yfile "MathFunctionsTargets.cmake")
             (ystr "MathFunctionsTargets")
             (ydir "lib/cmake/MathFunctions");
           yc_include (yfile "CMakePackageConfigHelpers");
           yc_configure_package_config_file ~no_set_and_check_macro:true
             ~no_check_required_components_macro:true
             (ydir "lib/cmake/MathFunctions")
             (yfile "${CMAKE_CURRENT_SOURCE_DIR}/Config.cmake.in")
             (dir_concat Yelu_langs.Lang_yelu_utils.output_this
                "MathFunctionsConfig.cmake");
           yc_write_basic_package_version_file
             ~compatibility:Yelu_langs.Lang_cmake.Same_major_version
             ~version:(ystr_eval
                         "${Tutorial_VERSION_MAJOR}.${Tutorial_VERSION_MINOR}")
             (dir_concat Yelu_langs.Lang_yelu_utils.output_this
                "MathFunctionsConfigVersion.cmake");
           yc_install_files
             [
               yfile "${CMAKE_CURRENT_BINARY_DIR}/MathFunctionsConfig.cmake";
               yfile "${CMAKE_CURRENT_BINARY_DIR}/MathFunctionsConfigVersion.cmake";
             ]
             (ydir "lib/cmake/MathFunctions");
           yc_install_export
             ~file:(yfile "MathFunctionsTargets.cmake")
             (ystr "MathFunctionsTargets")
             (ydir "lib/cmake/MathFunctions");
           yc_export_export (ystr "MathFunctionsTargets")
             ~file:(dir_concat Yelu_langs.Lang_yelu_utils.output_this
                      "MathFunctionsTargets.cmake");
         ])
  in
  ( "step12_bridge",
    [
      Alcotest.test_case "v1 step12 root bridges (adds DEBUG_POSTFIX)"
        `Quick
        (fun () ->
          let yelu1 = Yelu_langs.Yelu_cmake_to_yelu1.stmt cmd in
          let cmake_text =
            Yelu_langs.Yelu_tiny_cmake_emit.emit_script yelu1
          in
          Alcotest.(check bool) "emits set(CMAKE_DEBUG_POSTFIX " true
            (String.is_substring cmake_text
               ~substring:"set(CMAKE_DEBUG_POSTFIX");
          Alcotest.(check bool) "emits set_target_properties DEBUG_POSTFIX" true
            (String.is_substring cmake_text ~substring:"DEBUG_POSTFIX");
          Alcotest.(check bool) "emits SameMajorVersion compatibility" true
            (String.is_substring cmake_text ~substring:"SameMajorVersion"))
    ] )

(* R1a — back-fill the v1 math sub-step files. Most of these compose
   already-bridged constructs; their value is pinning that the bridge
   handles each step's specific shape (different option flags,
   different sources, different set_target_properties / genex
   strings, etc.). *)

let step4_math_bridge =
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
       ])
  in
  ( "step4_math_bridge",
    [
      Alcotest.test_case "v1 step4 math program bridges to Yelu1"
        `Quick
        (fun () ->
          let yelu1 = Yelu_langs.Yelu_cmake_to_yelu1.stmt cmd in
          let cmake_text =
            Yelu_langs.Yelu_tiny_cmake_emit.emit_script yelu1
          in
          Alcotest.(check bool) "emits add_library(MathFunctions" true
            (String.is_substring cmake_text
               ~substring:"add_library(MathFunctions");
          Alcotest.(check bool) "emits option(USE_MYMATH" true
            (String.is_substring cmake_text ~substring:"option(USE_MYMATH"))
    ] )

let step6_math_bridge =
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
  ( "step6_math_bridge",
    [
      Alcotest.test_case "v1 step6 math program bridges to Yelu1"
        `Quick
        (fun () ->
          let yelu1 = Yelu_langs.Yelu_cmake_to_yelu1.stmt cmd in
          let cmake_text =
            Yelu_langs.Yelu_tiny_cmake_emit.emit_script yelu1
          in
          Alcotest.(check bool) "emits add_library(MathFunctions" true
            (String.is_substring cmake_text
               ~substring:"add_library(MathFunctions"))
    ] )

(* step10_math adds POSITION_INDEPENDENT_CODE + EXPORTING_MYMATH on top
   of step8_math. *)
let step10_math_bridge =
  let module Old = Yelu_langs.Lang_yelu_cmake in
  let open Yelu_langs.Lang_yelu_utils in
  let cmd : Old.yelu_stmt =
    ycmd_of_list
      ([
         ylet "flags" (ytval "tutorial_compiler_flags");
         ylet "math" (ytval "MathFunctions");
         ylet "sqrt" (ytval "SqrtLibrary");
         ylet "check_cxx" (ycstr "check_cxx_source_compiles");
         ylet "inst_libs" (ycstr "installable_libs");
         ylet "have_log" (ycstr "HAVE_LOG");
         ylet "have_exp" (ycstr "HAVE_EXP");
         ylet "use_mymath" (ycstr "USE_MYMATH");
         yc_extern_target "tutorial_compiler_flags";
         yc_include (yfile "MakeTable.cmake");
         add_lib ~sources:[ yfile "MathFunctions.cxx" ] (yvar "math");
         include_dirs (yvar "math")
           [ ytarget_def ~kind:Interface [ ydir "${CMAKE_CURRENT_SOURCE_DIR}" ] ];
         yc_option ~value:(ybool true)
           ~msg:"Use tutorial provided math implementation" (ycvar "USE_MYMATH");
         yifthen (ytruthy (yvar "use_mymath"))
           (ycmd_of_list
              ([
                 compile_defs (yvar "math")
                   [ ytarget_def ~kind:Private [ ykeyword "USE_MYMATH" ] ];
                 add_lib ~type_:Lib_static
                   ~sources:[ yfile "mysqrt.cxx";
                              yfile "${CMAKE_CURRENT_BINARY_DIR}/Table.h" ]
                   (yvar "sqrt");
                 yc_set_target_properties (yvar "sqrt")
                   [ ("POSITION_INDEPENDENT_CODE",
                      ystr "${BUILD_SHARED_LIBS}") ];
                 include_dirs (yvar "sqrt")
                   [ ytarget_def ~kind:Private
                       [ ydir "${CMAKE_CURRENT_BINARY_DIR}" ] ];
                 link_lib [ yvar "sqrt" ]
                   [ ytarget_def ~kind:Public [ yvar "flags" ] ];
               ]
              @ Step_common.math_check_cxx_features
              @ [
                  compile_defs (yvar "math")
                    [ ytarget_def ~kind:Private
                        [ ykeyword "EXPORTING_MYMATH" ] ];
                  link_lib [ yvar "math" ]
                    [ ytarget_def ~kind:Private [ yvar "sqrt" ] ];
                ]));
         link_lib [ yvar "math" ]
           [ ytarget_def ~kind:Public [ yvar "flags" ] ];
       ]
       @ Step_common.math_install_libs ())
  in
  ( "step10_math_bridge",
    [
      Alcotest.test_case "v1 step10 math program bridges (POSITION_INDEPENDENT_CODE)"
        `Quick
        (fun () ->
          let yelu1 = Yelu_langs.Yelu_cmake_to_yelu1.stmt cmd in
          let cmake_text =
            Yelu_langs.Yelu_tiny_cmake_emit.emit_script yelu1
          in
          Alcotest.(check bool) "emits POSITION_INDEPENDENT_CODE prop" true
            (String.is_substring cmake_text
               ~substring:"POSITION_INDEPENDENT_CODE");
          Alcotest.(check bool) "emits EXPORTING_MYMATH compile def" true
            (String.is_substring cmake_text ~substring:"EXPORTING_MYMATH"))
    ] )

(* step11_math + step12_math add BUILD_INTERFACE / INSTALL_INTERFACE
   generator-expression strings (flowed as opaque cmake-eval strings via
   [ystr], i.e. [EString], so no new theory needed) and the EXPORT
   parameter to math_install_libs. *)
let step11_math_bridge =
  let module Old = Yelu_langs.Lang_yelu_cmake in
  let open Yelu_langs.Lang_yelu_utils in
  let cmd : Old.yelu_stmt =
    ycmd_of_list
      ([
         ylet "flags" (ytval "tutorial_compiler_flags");
         ylet "math" (ytval "MathFunctions");
         ylet "sqrt" (ytval "SqrtLibrary");
         ylet "check_cxx" (ycstr "check_cxx_source_compiles");
         ylet "inst_libs" (ycstr "installable_libs");
         ylet "have_log" (ycstr "HAVE_LOG");
         ylet "have_exp" (ycstr "HAVE_EXP");
         ylet "use_mymath" (ycstr "USE_MYMATH");
         yc_extern_target "tutorial_compiler_flags";
         yc_include (yfile "MakeTable.cmake");
         add_lib ~sources:[ yfile "MathFunctions.cxx" ] (yvar "math");
         include_dirs (yvar "math")
           [
             ytarget_def ~kind:Interface
               [
                 ystr "$<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}>";
                 ystr "$<INSTALL_INTERFACE:include>";
               ];
           ];
         yc_option ~value:(ybool true)
           ~msg:"Use tutorial provided math implementation" (ycvar "USE_MYMATH");
         yifthen (ytruthy (yvar "use_mymath"))
           (ycmd_of_list
              ([
                 compile_defs (yvar "math")
                   [ ytarget_def ~kind:Private [ ykeyword "USE_MYMATH" ] ];
                 add_lib ~type_:Lib_static
                   ~sources:[ yfile "mysqrt.cxx";
                              yfile "${CMAKE_CURRENT_BINARY_DIR}/Table.h" ]
                   (yvar "sqrt");
                 yc_set_target_properties (yvar "sqrt")
                   [ ("POSITION_INDEPENDENT_CODE",
                      ystr "${BUILD_SHARED_LIBS}") ];
                 include_dirs (yvar "sqrt")
                   [ ytarget_def ~kind:Private
                       [ ydir "${CMAKE_CURRENT_BINARY_DIR}" ] ];
                 link_lib [ yvar "sqrt" ]
                   [ ytarget_def ~kind:Public [ yvar "flags" ] ];
               ]
              @ Step_common.math_check_cxx_features
              @ [
                  compile_defs (yvar "math")
                    [ ytarget_def ~kind:Private
                        [ ykeyword "EXPORTING_MYMATH" ] ];
                  link_lib [ yvar "math" ]
                    [ ytarget_def ~kind:Private [ yvar "sqrt" ] ];
                ]));
         link_lib [ yvar "math" ]
           [ ytarget_def ~kind:Public [ yvar "flags" ] ];
       ]
       @ Step_common.math_install_libs ~export:(ystr "MathFunctionsTargets") ())
  in
  ( "step11_math_bridge",
    [
      Alcotest.test_case "v1 step11 math program bridges (BUILD_INTERFACE genex)"
        `Quick
        (fun () ->
          let yelu1 = Yelu_langs.Yelu_cmake_to_yelu1.stmt cmd in
          let cmake_text =
            Yelu_langs.Yelu_tiny_cmake_emit.emit_script yelu1
          in
          Alcotest.(check bool) "emits $<BUILD_INTERFACE genex" true
            (String.is_substring cmake_text ~substring:"$<BUILD_INTERFACE:");
          Alcotest.(check bool) "emits $<INSTALL_INTERFACE genex" true
            (String.is_substring cmake_text ~substring:"$<INSTALL_INTERFACE:");
          Alcotest.(check bool) "emits install with EXPORT MathFunctionsTargets" true
            (String.is_substring cmake_text
               ~substring:"EXPORT \"MathFunctionsTargets\""))
    ] )

(* step12_math is structurally identical to step11_math (only the
   parent step's root differs in DEBUG_POSTFIX). Kept as its own test
   so future divergence surfaces here. *)
let step12_math_bridge =
  let module Old = Yelu_langs.Lang_yelu_cmake in
  let open Yelu_langs.Lang_yelu_utils in
  let cmd : Old.yelu_stmt =
    ycmd_of_list
      ([
         ylet "flags" (ytval "tutorial_compiler_flags");
         ylet "math" (ytval "MathFunctions");
         ylet "sqrt" (ytval "SqrtLibrary");
         ylet "check_cxx" (ycstr "check_cxx_source_compiles");
         ylet "inst_libs" (ycstr "installable_libs");
         ylet "have_log" (ycstr "HAVE_LOG");
         ylet "have_exp" (ycstr "HAVE_EXP");
         ylet "use_mymath" (ycstr "USE_MYMATH");
         yc_extern_target "tutorial_compiler_flags";
         yc_include (yfile "MakeTable.cmake");
         add_lib ~sources:[ yfile "MathFunctions.cxx" ] (yvar "math");
         include_dirs (yvar "math")
           [
             ytarget_def ~kind:Interface
               [
                 ystr "$<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}>";
                 ystr "$<INSTALL_INTERFACE:include>";
               ];
           ];
         yc_option ~value:(ybool true)
           ~msg:"Use tutorial provided math implementation" (ycvar "USE_MYMATH");
         yifthen (ytruthy (yvar "use_mymath"))
           (ycmd_of_list
              ([
                 compile_defs (yvar "math")
                   [ ytarget_def ~kind:Private [ ykeyword "USE_MYMATH" ] ];
                 add_lib ~type_:Lib_static
                   ~sources:[ yfile "mysqrt.cxx";
                              yfile "${CMAKE_CURRENT_BINARY_DIR}/Table.h" ]
                   (yvar "sqrt");
                 yc_set_target_properties (yvar "sqrt")
                   [ ("POSITION_INDEPENDENT_CODE",
                      ystr "${BUILD_SHARED_LIBS}") ];
                 include_dirs (yvar "sqrt")
                   [ ytarget_def ~kind:Private
                       [ ydir "${CMAKE_CURRENT_BINARY_DIR}" ] ];
                 link_lib [ yvar "sqrt" ]
                   [ ytarget_def ~kind:Public [ yvar "flags" ] ];
               ]
              @ Step_common.math_check_cxx_features
              @ [
                  compile_defs (yvar "math")
                    [ ytarget_def ~kind:Private
                        [ ykeyword "EXPORTING_MYMATH" ] ];
                  link_lib [ yvar "math" ]
                    [ ytarget_def ~kind:Private [ yvar "sqrt" ] ];
                ]));
         link_lib [ yvar "math" ]
           [ ytarget_def ~kind:Public [ yvar "flags" ] ];
       ]
       @ Step_common.math_install_libs ~export:(ystr "MathFunctionsTargets") ())
  in
  ( "step12_math_bridge",
    [
      Alcotest.test_case "v1 step12 math program bridges"
        `Quick
        (fun () ->
          let yelu1 = Yelu_langs.Yelu_cmake_to_yelu1.stmt cmd in
          let cmake_text =
            Yelu_langs.Yelu_tiny_cmake_emit.emit_script yelu1
          in
          Alcotest.(check bool) "emits the math install rule" true
            (String.is_substring cmake_text
               ~substring:"install(TARGETS ${installable_libs}"))
    ] )

(* step12_multi is just include + a multi-config CPACK_INSTALL_CMAKE_PROJECTS
   set — no new constructs. *)
let step12_multi_bridge =
  let module Old = Yelu_langs.Lang_yelu_cmake in
  let open Yelu_langs.Lang_yelu_utils in
  let cmd : Old.yelu_stmt =
    ycmd_of_list
      [
        yc_include (yfile "release/CPackConfig.cmake");
        yc_set (ycvar "CPACK_INSTALL_CMAKE_PROJECTS")
          [ ystr "debug;Tutorial;ALL;/"; ystr "release;Tutorial;ALL;/" ];
      ]
  in
  ( "step12_multi_bridge",
    [
      Alcotest.test_case "v1 step12_multi multi-config CPack bridges"
        `Quick
        (fun () ->
          let yelu1 = Yelu_langs.Yelu_cmake_to_yelu1.stmt cmd in
          let cmake_text =
            Yelu_langs.Yelu_tiny_cmake_emit.emit_script yelu1
          in
          Alcotest.(check bool) "includes the per-config CPackConfig" true
            (String.is_substring cmake_text
               ~substring:"include(\"release/CPackConfig.cmake\")");
          Alcotest.(check bool) "emits CPACK_INSTALL_CMAKE_PROJECTS set" true
            (String.is_substring cmake_text
               ~substring:"set(CPACK_INSTALL_CMAKE_PROJECTS"))
    ] )

(* R1b — v2 root step files. v2 is a different shape from v1: most
   commands are spelled as [yc_apply (yname "...") [...]] rather than
   typed [yc_*] helpers, so the lenient-apply path (Tier B) carries
   most of it. The v2 files that DO need new typed constructors (alias,
   dependencies, target_sources_fs, precompile_headers) get bridged in
   demand-order; see comments per test. *)

let v2_root_bridge =
  let module Old = Yelu_langs.Lang_yelu_cmake in
  let open Yelu_langs.Lang_yelu_utils in
  let cmd : Old.yelu_stmt =
    ycmd_of_list [
      yc_project ~version:{ major = 1; minor = 0; patch = "0" } "Tutorial";
      yc_option ~value:(ybool true)
        ~msg:"Build the Tutorial executable" (ycvar "TUTORIAL_BUILD_UTILITIES");
      yc_option ~value:(ybool false)
        ~msg:"Use std::sqrt" (ycvar "TUTORIAL_USE_STD_SQRT");
      yc_option ~value:(ybool true)
        ~msg:"Check for and use IPO support" (ycvar "TUTORIAL_ENABLE_IPO");
      yc_option ~value:(ybool true)
        ~msg:"Enable testing and build tests" (ycvar "BUILD_TESTING");
      yifthen (ytruthy (ycstr "TUTORIAL_ENABLE_IPO"))
        (ycmd_of_list [
          yc_include (yname "CheckIPOSupported");
          yc_apply (yname "check_ipo_supported")
            [ ystr_eval "RESULT"; ystr_eval "result";
              ystr_eval "OUTPUT"; ystr_eval "output" ];
          yif (ytruthy (ycstr "result"))
            (ycmd_of_list [
              yc_message ~mode:Mm_none [ "IPO is supported, enabling IPO" ];
              yc_set (ycvar "CMAKE_INTERPROCEDURAL_OPTIMIZATION") [ ybool true ];
            ])
            (yc_message ~mode:Mm_warning [ "IPO is not supported: ${output}" ]);
        ]);
      yifthen (ytruthy (ycstr "TUTORIAL_BUILD_UTILITIES"))
        (yc_add_subdirectory (ydir "Tutorial"));
      yifthen (ytruthy (ycstr "BUILD_TESTING"))
        (ycmd_of_list [
          yc_enable_testing;
          yc_add_subdirectory (ydir "Tests");
        ]);
      yc_add_subdirectory (ydir "MathFunctions");
      yc_include (yname "GNUInstallDirs");
      yc_apply (yname "install")
        [ ykeyword "TARGETS"; ytval "MathFunctions"; ytval "OpAdd"; ytval "OpMul";
          ytval "OpSub"; ytval "MathLogger"; ytval "SqrtTable";
          ykeyword "EXPORT"; yname "TutorialTargets";
          ykeyword "FILE_SET"; ykeyword "HEADERS" ];
      yc_install_export ~namespace:"Tutorial::"
        (yname "TutorialTargets")
        (ystr_eval "${CMAKE_INSTALL_LIBDIR}/cmake/Tutorial");
      yc_include (yname "CMakePackageConfigHelpers");
      yc_write_basic_package_version_file
        ~compatibility:Yelu_langs.Lang_cmake.Exact_version
        (ystr_eval "${CMAKE_CURRENT_BINARY_DIR}/TutorialConfigVersion.cmake");
      yc_install_files
        [ yfile "cmake/TutorialConfig.cmake";
          ystr_eval "${CMAKE_CURRENT_BINARY_DIR}/TutorialConfigVersion.cmake" ]
        (ystr_eval "${CMAKE_INSTALL_LIBDIR}/cmake/Tutorial");
    ]
  in
  ( "v2_root_bridge",
    [
      Alcotest.test_case "v2 root program bridges to Yelu1"
        `Quick
        (fun () ->
          let yelu1 = Yelu_langs.Yelu_cmake_to_yelu1.stmt cmd in
          let cmake_text =
            Yelu_langs.Yelu_tiny_cmake_emit.emit_script yelu1
          in
          Alcotest.(check bool) "emits project(Tutorial" true
            (String.is_substring cmake_text ~substring:"project(Tutorial");
          Alcotest.(check bool) "emits include(CheckIPOSupported)" true
            (String.is_substring cmake_text
               ~substring:"include(\"CheckIPOSupported\")");
          Alcotest.(check bool) "emits the install(TARGETS ...) apply" true
            (String.is_substring cmake_text ~substring:"install(\"TARGETS\"");
          Alcotest.(check bool) "emits install(EXPORT TutorialTargets ...)" true
            (String.is_substring cmake_text
               ~substring:"install(EXPORT \"TutorialTargets\""))
    ] )

(* v2_mathlogger / v2_opadd / v2_opmul / v2_opsub / v2_mathext / v2_tests —
   these are tiny per-target files. Bundled into one bridge test that
   walks each program through the bridge and asserts it produces
   non-empty cmake. *)

let v2_mathlogger_bridge =
  let module Old = Yelu_langs.Lang_yelu_cmake in
  let open Yelu_langs.Lang_yelu_utils in
  let cmd : Old.yelu_stmt =
    ycmd_of_list [
      add_lib (ytval "MathLogger");
      yc_target_sources_fs (ytval "MathLogger") [
        ytsi_plain Private [ yfile "MathLogger.cxx" ];
        ytsi_file_set_headers ~files:[ yfile "MathLogger.h" ] Public;
      ];
      compile_feats (ytval "MathLogger")
        [ { kind = Private; feature = "cxx_std_20" } ];
    ]
  in
  ( "v2_mathlogger_bridge",
    [
      Alcotest.test_case "v2 MathLogger bridges (target_sources_fs)"
        `Quick
        (fun () ->
          let yelu1 = Yelu_langs.Yelu_cmake_to_yelu1.stmt cmd in
          let cmake_text =
            Yelu_langs.Yelu_tiny_cmake_emit.emit_script yelu1
          in
          Alcotest.(check bool) "emits add_library(MathLogger" true
            (String.is_substring cmake_text
               ~substring:"add_library(MathLogger");
          Alcotest.(check bool) "emits FILE_SET HEADERS clause" true
            (String.is_substring cmake_text ~substring:"FILE_SET HEADERS"))
    ] )

(* v2_mathext: just 3 add_subdirectory calls. *)
let v2_mathext_bridge =
  let module Old = Yelu_langs.Lang_yelu_cmake in
  let open Yelu_langs.Lang_yelu_utils in
  let cmd : Old.yelu_stmt =
    ycmd_of_list [
      yc_add_subdirectory (ydir "OpAdd");
      yc_add_subdirectory (ydir "OpMul");
      yc_add_subdirectory (ydir "OpSub");
    ]
  in
  ( "v2_mathext_bridge",
    [
      Alcotest.test_case "v2 MathExtensions bridges (three add_subdirectory)"
        `Quick
        (fun () ->
          let yelu1 = Yelu_langs.Yelu_cmake_to_yelu1.stmt cmd in
          let cmake_text =
            Yelu_langs.Yelu_tiny_cmake_emit.emit_script yelu1
          in
          Alcotest.(check bool) "emits add_subdirectory(OpAdd" true
            (String.is_substring cmake_text
               ~substring:"add_subdirectory(\"OpAdd\""))
    ] )

(* v2_opadd / v2_opmul / v2_opsub are structurally identical. One test
   for OpAdd; the others would only diverge if the file generators do. *)
let v2_opadd_bridge =
  let module Old = Yelu_langs.Lang_yelu_cmake in
  let open Yelu_langs.Lang_yelu_utils in
  let cmd : Old.yelu_stmt =
    ycmd_of_list [
      add_lib ~type_:Yelu_langs.Lang_cmake.Lib_object (ytval "OpAdd");
      yc_target_sources_fs (ytval "OpAdd") [
        ytsi_plain Private [ yfile "OpAdd.cxx" ];
        ytsi_file_set_headers ~files:[ yfile "OpAdd.h" ] Interface;
      ];
    ]
  in
  ( "v2_opadd_bridge",
    [
      Alcotest.test_case "v2 OpAdd bridges (OBJECT lib + FILE_SET HEADERS)"
        `Quick
        (fun () ->
          let yelu1 = Yelu_langs.Yelu_cmake_to_yelu1.stmt cmd in
          let cmake_text =
            Yelu_langs.Yelu_tiny_cmake_emit.emit_script yelu1
          in
          Alcotest.(check bool) "emits OBJECT library" true
            (String.is_substring cmake_text
               ~substring:"add_library(OpAdd OBJECT"))
    ] )

let v2_opmul_bridge =
  let module Old = Yelu_langs.Lang_yelu_cmake in
  let open Yelu_langs.Lang_yelu_utils in
  let cmd : Old.yelu_stmt =
    ycmd_of_list [
      add_lib ~type_:Yelu_langs.Lang_cmake.Lib_object (ytval "OpMul");
      yc_target_sources_fs (ytval "OpMul") [
        ytsi_plain Private [ yfile "OpMul.cxx" ];
        ytsi_file_set_headers ~files:[ yfile "OpMul.h" ] Interface;
      ];
    ]
  in
  ( "v2_opmul_bridge",
    [ Alcotest.test_case "v2 OpMul bridges" `Quick
        (fun () ->
          let yelu1 = Yelu_langs.Yelu_cmake_to_yelu1.stmt cmd in
          let _ = Yelu_langs.Yelu_tiny_cmake_emit.emit_script yelu1 in
          ()) ] )

let v2_opsub_bridge =
  let module Old = Yelu_langs.Lang_yelu_cmake in
  let open Yelu_langs.Lang_yelu_utils in
  let cmd : Old.yelu_stmt =
    ycmd_of_list [
      add_lib ~type_:Yelu_langs.Lang_cmake.Lib_object (ytval "OpSub");
      yc_target_sources_fs (ytval "OpSub") [
        ytsi_plain Private [ yfile "OpSub.cxx" ];
        ytsi_file_set_headers ~files:[ yfile "OpSub.h" ] Interface;
      ];
    ]
  in
  ( "v2_opsub_bridge",
    [ Alcotest.test_case "v2 OpSub bridges" `Quick
        (fun () ->
          let yelu1 = Yelu_langs.Yelu_cmake_to_yelu1.stmt cmd in
          let _ = Yelu_langs.Yelu_tiny_cmake_emit.emit_script yelu1 in
          ()) ] )

(* v2_maketable: add_custom_command(OUTPUT ...) + add_custom_target +
   add_dependencies + FILE_SET HEADERS with BASE_DIRS. *)
let v2_maketable_bridge =
  let module Old = Yelu_langs.Lang_yelu_cmake in
  let open Yelu_langs.Lang_yelu_utils in
  let cmd : Old.yelu_stmt =
    ycmd_of_list [
      add_exe (ytval "MakeTable");
      yc_target_sources_fs (ytval "MakeTable") [
        ytsi_plain Private [ yfile "MakeTable.cxx" ];
      ];
      yc_add_custom_command
        ~outputs:[ yfile "SqrtTable.h" ]
        ~depends:[ ytval "MakeTable" ]
        ~verbatim:true
        [ { command = "MakeTable"; args = [ "SqrtTable.h" ] } ];
      yc_add_custom_target ~depends:[ yfile "SqrtTable.h" ] "RunMakeTable";
      add_lib ~type_:Yelu_langs.Lang_cmake.Lib_interface (ytval "SqrtTable");
      yc_target_sources_fs (ytval "SqrtTable") [
        ytsi_file_set_headers
          ~base_dirs:[ ystr_eval "${CMAKE_CURRENT_BINARY_DIR}" ]
          ~files:[ ystr_eval "${CMAKE_CURRENT_BINARY_DIR}/SqrtTable.h" ]
          Interface;
      ];
      yc_add_dependencies "SqrtTable" "RunMakeTable";
    ]
  in
  ( "v2_maketable_bridge",
    [
      Alcotest.test_case "v2 MakeTable bridges (custom_command + add_dependencies)"
        `Quick
        (fun () ->
          let yelu1 = Yelu_langs.Yelu_cmake_to_yelu1.stmt cmd in
          let cmake_text =
            Yelu_langs.Yelu_tiny_cmake_emit.emit_script yelu1
          in
          Alcotest.(check bool) "emits add_custom_target(RunMakeTable" true
            (String.is_substring cmake_text
               ~substring:"add_custom_target(RunMakeTable");
          Alcotest.(check bool) "emits add_dependencies(SqrtTable RunMakeTable)" true
            (String.is_substring cmake_text
               ~substring:"add_dependencies(SqrtTable RunMakeTable)");
          Alcotest.(check bool) "FILE_SET HEADERS with BASE_DIRS" true
            (String.is_substring cmake_text ~substring:"BASE_DIRS"))
    ] )

(* v2_mathfuncs: alias library + many target_sources_fs + check_include_files. *)
let v2_mathfuncs_bridge =
  let module Old = Yelu_langs.Lang_yelu_cmake in
  let open Yelu_langs.Lang_yelu_utils in
  let cmd : Old.yelu_stmt =
    ycmd_of_list [
      add_lib (ytval "MathFunctions");
      add_lib_alias ~alias_of:"MathFunctions" "Tutorial::MathFunctions";
      yc_target_sources_fs (ytval "MathFunctions") [
        ytsi_plain Private [ yfile "MathFunctions.cxx" ];
        ytsi_file_set_headers ~files:[ yfile "MathFunctions.h" ] Public;
      ];
      link_lib [ ytval "MathFunctions" ] [
        ytarget_def ~kind:Private [ ytval "MathLogger"; ytval "SqrtTable" ];
        ytarget_def ~kind:Public [ ytval "OpAdd"; ytval "OpMul"; ytval "OpSub" ];
      ];
      compile_feats (ytval "MathFunctions")
        [ { kind = Private; feature = "cxx_std_20" } ];
      yifthen (ytruthy (ycstr "TUTORIAL_USE_STD_SQRT"))
        (compile_defs (ytval "MathFunctions")
           [ ytarget_def ~kind:Private [ ykeyword "TUTORIAL_USE_STD_SQRT" ] ]);
      yc_include (yname "CheckIncludeFiles");
      yc_apply (yname "check_include_files")
        [ yfile "emmintrin.h"; ycstr "HAS_EMMINTRIN";
          ykeyword "LANGUAGE"; ykeyword "CXX" ];
      yc_add_subdirectory (ydir "MathLogger");
      yc_add_subdirectory (ydir "MathExtensions");
      yc_add_subdirectory (ydir "MakeTable");
    ]
  in
  ( "v2_mathfuncs_bridge",
    [
      Alcotest.test_case "v2 MathFunctions bridges (alias + many target ops)"
        `Quick
        (fun () ->
          let yelu1 = Yelu_langs.Yelu_cmake_to_yelu1.stmt cmd in
          let cmake_text =
            Yelu_langs.Yelu_tiny_cmake_emit.emit_script yelu1
          in
          Alcotest.(check bool) "emits ALIAS library" true
            (String.is_substring cmake_text
               ~substring:"add_library(Tutorial::MathFunctions ALIAS MathFunctions)"))
    ] )

(* v2_simpletest: install + write_basic_package_version_file ~arch_independent. *)
let v2_simpletest_bridge =
  let module Old = Yelu_langs.Lang_yelu_cmake in
  let open Yelu_langs.Lang_yelu_utils in
  let cmd : Old.yelu_stmt =
    ycmd_of_list [
      yc_project ~version:{ major = 0; minor = 0; patch = "1" } "SimpleTest";
      add_lib ~type_:Yelu_langs.Lang_cmake.Lib_interface (ytval "SimpleTest");
      yc_target_sources_fs (ytval "SimpleTest") [
        ytsi_file_set_headers ~files:[ yfile "SimpleTest.h" ] Interface;
      ];
      compile_feats (ytval "SimpleTest")
        [ { kind = Interface; feature = "cxx_std_20" } ];
      yc_write_basic_package_version_file
        ~compatibility:Yelu_langs.Lang_cmake.Exact_version
        ~arch_independent:true
        (ystr_eval "${CMAKE_CURRENT_BINARY_DIR}/SimpleTestConfigVersion.cmake");
    ]
  in
  ( "v2_simpletest_bridge",
    [
      Alcotest.test_case "v2 SimpleTest bridges (ARCH_INDEPENDENT)"
        `Quick
        (fun () ->
          let yelu1 = Yelu_langs.Yelu_cmake_to_yelu1.stmt cmd in
          let cmake_text =
            Yelu_langs.Yelu_tiny_cmake_emit.emit_script yelu1
          in
          Alcotest.(check bool) "emits ARCH_INDEPENDENT flag" true
            (String.is_substring cmake_text ~substring:"ARCH_INDEPENDENT"))
    ] )

(* v2_tutorial_exe: yif (else branch) + compile_opts + find_path via apply. *)
let v2_tutorial_exe_bridge =
  let module Old = Yelu_langs.Lang_yelu_cmake in
  let open Yelu_langs.Lang_yelu_utils in
  let msvc_cond =
    yor (ystrequal (ycstr "CMAKE_CXX_COMPILER_ID") (ystr "MSVC"))
      (ystrequal (ycstr "CMAKE_CXX_COMPILER_FRONTEND_VARIANT") (ystr "MSVC"))
  in
  let cmd : Old.yelu_stmt =
    ycmd_of_list [
      add_exe (ytval "Tutorial");
      yc_target_sources_fs (ytval "Tutorial") [
        ytsi_plain Private [ yfile "Tutorial.cxx" ];
      ];
      link_lib [ ytval "Tutorial" ] [
        ytarget_def ~kind:Private [ ytval "MathFunctions" ];
      ];
      compile_feats (ytval "Tutorial")
        [ { kind = Private; feature = "cxx_std_20" } ];
      yifthen msvc_cond
        (compile_opts (ytval "Tutorial")
           [ ytarget_def ~kind:Private [ ystr "/W3" ] ]);
    ]
  in
  ( "v2_tutorial_exe_bridge",
    [
      Alcotest.test_case "v2 Tutorial exe bridges"
        `Quick
        (fun () ->
          let yelu1 = Yelu_langs.Yelu_cmake_to_yelu1.stmt cmd in
          let cmake_text =
            Yelu_langs.Yelu_tiny_cmake_emit.emit_script yelu1
          in
          Alcotest.(check bool) "emits add_executable(Tutorial" true
            (String.is_substring cmake_text
               ~substring:"add_executable(Tutorial"))
    ] )

(* v2_tests: find_package + apply (for simpletest_discover_tests). *)
let v2_tests_bridge =
  let module Old = Yelu_langs.Lang_yelu_cmake in
  let open Yelu_langs.Lang_yelu_utils in
  let cmd : Old.yelu_stmt =
    ycmd_of_list [
      add_exe (ytval "TestMathFunctions");
      yc_target_sources_fs (ytval "TestMathFunctions") [
        ytsi_plain Private [ yfile "TestMathFunctions.cxx" ];
      ];
      yc_find_package ~required:true "SimpleTest";
      link_lib [ ytval "TestMathFunctions" ] [
        ytarget_def ~kind:Private
          [ ytval "MathFunctions"; ytval "SimpleTest::SimpleTest" ];
      ];
      yc_apply (yname "simpletest_discover_tests") [ ytval "TestMathFunctions" ];
    ]
  in
  ( "v2_tests_bridge",
    [
      Alcotest.test_case "v2 Tests bridges"
        `Quick
        (fun () ->
          let yelu1 = Yelu_langs.Yelu_cmake_to_yelu1.stmt cmd in
          let cmake_text =
            Yelu_langs.Yelu_tiny_cmake_emit.emit_script yelu1
          in
          Alcotest.(check bool) "emits find_package(SimpleTest" true
            (String.is_substring cmake_text
               ~substring:"find_package(SimpleTest");
          Alcotest.(check bool) "emits simpletest_discover_tests apply" true
            (String.is_substring cmake_text
               ~substring:"simpletest_discover_tests("))
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
      step4_math_bridge;
      step5_bridge;
      step5_math_bridge;
      step6_bridge;
      step6_math_bridge;
      step6_ctest_bridge;
      step7_bridge;
      step7_math_bridge;
      step8_table_bridge;
      step8_math_bridge;
      step9_bridge;
      step10_bridge;
      step10_math_bridge;
      step11_config_bridge;
      step11_bridge;
      step11_math_bridge;
      step12_bridge;
      step12_math_bridge;
      step12_multi_bridge;
      v2_root_bridge;
      v2_mathlogger_bridge;
      v2_mathext_bridge;
      v2_opadd_bridge;
      v2_opmul_bridge;
      v2_opsub_bridge;
      v2_maketable_bridge;
      v2_mathfuncs_bridge;
      v2_simpletest_bridge;
      v2_tutorial_exe_bridge;
      v2_tests_bridge;
    ]
