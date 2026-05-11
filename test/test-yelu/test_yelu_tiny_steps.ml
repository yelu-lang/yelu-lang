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
      step7_bridge;
      step7_math_bridge;
      step8_table_bridge;
      step8_math_bridge;
      step9_bridge;
      step10_bridge;
    ]
