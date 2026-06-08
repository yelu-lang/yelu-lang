(* Tiny lift/lower roundtrip equivalence tests with real cmake. Uses
   [Yelu_cmake_emit_debug] (direct text emit, demoted to diagnostic
   aid in Phase 1.5) intentionally — this suite checks that
   [to_normal |> from_normal] produces cmake whose
   stdout matches the original, an evaluator-correctness check that
   does not require routing through the production AST emit path.
   Production-path runtime equivalence lives in [test_runcmake_yelu]. *)
open Yelu_langs.Yelu_cmake
open Yelu_langs.Yelu_cmake_normal_store
open Yelu_langs.Yelu_cmake_normal_bool
open Yelu_langs.Yelu_cmake_normal_int
open Yelu_langs.Yelu_cmake_normal_list
open Yelu_langs.Yelu_cmake_normal_path
open Yelu_langs.Yelu_cmake_normal_file
open Yelu_langs.Yelu_cmake_normal_target
open Yelu_langs.Yelu_cmake_normal_install
open Yelu_langs.Yelu_cmake_normal_string
open Yelu_langs.Yelu_cmake_normal_if
open Yelu_langs.Yelu_cmake_normal_dir
open Yelu_langs.Yelu_cmake_normal_test
open Yelu_langs.Yelu_cmake_normal_property
open Yelu_langs.Yelu_cmake_normal_find
open Yelu_langs.Yelu_cmake_normal_try
open Yelu_langs.Yelu_cmake_list
open Yelu_langs.Yelu_cmake_path
open Yelu_langs.Yelu_cmake_string
open Yelu_langs.Yelu_cmake_if
open Yelu_langs.Yelu_cmake_cmake_op
open Yelu_langs.Yelu_cmake_convert
open Yelu_langs.Yelu_cmake_emit_debug
open Yelu_runner.Cmake_runner

let check_same_cmake_output name left right =
  Alcotest.test_case name `Quick (fun () ->
    let left_text = emit_script left in
    let right_text = emit_script right in
    let left_result = run_script left_text in
    let right_result = run_script right_text in
    check_exit 0 left_result;
    check_exit 0 right_result;
    Alcotest.(check string) "stdout" left_result.stdout right_result.stdout;
    Alcotest.(check string) "stderr" left_result.stderr right_result.stderr)

let check_yelu1_roundtrip_cmake name expr =
  check_same_cmake_output name expr (from_normal (to_normal expr))

let check_yelu2_lowering_cmake name expr =
  Alcotest.test_case name `Quick (fun () ->
    let cmake_text = emit_script (from_normal expr) in
    let result = run_script cmake_text in
    check_exit 0 result;
    Alcotest.(check string) "stdout" "" result.stdout;
    Alcotest.(check string) "stderr" "RESULT=YES\n" result.stderr)

let check_yelu2_lowering_configure
    ?(files = [ "main.c", "int main(void) { return 0; }\n" ])
    ?(languages = [ "C" ])
    name expr =
  Alcotest.test_case name `Quick (fun () ->
    let cmake_text = emit_script (from_normal expr) in
    let result =
      run_configure ~languages ~files cmake_text
    in
    check_exit 0 result.run;
    check_stderr_matches "RESULT=YES" result.run)

let check_yelu2_custom_target_build name expr ~target ~pattern =
  Alcotest.test_case name `Quick (fun () ->
    let cmake_text = emit_script (from_normal expr) in
    let project = configure_project cmake_text in
    match
      check_exit 0 project.configure.run;
      let build = run_build_target project target in
      check_exit 0 build;
      let output = build.stdout ^ build.stderr in
      let re = Re.Posix.compile_pat pattern in
      if not (Re.execp re output) then
        Alcotest.failf "build output did not match %S\ngot:\n%s" pattern output
    with
    | () -> cleanup_configured_project project
    | exception exn ->
      cleanup_configured_project project;
      raise exn)

let check_yelu2_install name expr ~expected =
  Alcotest.test_case name `Quick (fun () ->
    let cmake_text = emit_script (from_normal expr) in
    let project =
      configure_project
        ~languages:[ "C" ]
        ~files:
          [
            "main.c", "int main(void) { return 0; }\n";
            "include/app.h", "#pragma once\n";
          ]
        cmake_text
    in
    let prefix = Filename.temp_file "yelu_install_" "" in
    Sys.remove prefix;
    Unix.mkdir prefix 0o700;
    match
      check_exit 0 project.configure.run;
      check_exit 0 (run_build_target project "app");
      check_exit 0 (run_install ~prefix project);
      let manifest = install_manifest project in
      check_install_manifest_under_prefix ~prefix manifest;
      List.iter
        (fun rel ->
          let path = Filename.concat prefix rel in
          if not (Sys.file_exists path) then
            Alcotest.failf "expected installed file %S to exist" path)
        expected
    with
    | () ->
      cleanup_configured_project project;
      remove_tree prefix
    | exception exn ->
      cleanup_configured_project project;
      remove_tree prefix;
      raise exn)

let cmake_project text =
  "cmake_minimum_required(VERSION 3.20)\nproject(_yelu_test C)\n" ^ text

let check_yelu2_file_api_equiv ?(files = [ "main.c", "int main(void) { return 0; }\n" ]) name ~reference expr =
  Alcotest.test_case name `Quick (fun () ->
    let yelu_cmake = emit_script (from_normal expr) in
    let result = compare_file_api ~files (cmake_project reference) (cmake_project yelu_cmake) in
    check_exit 0 result)

let yelu1_roundtrip =
  ( "yelu1_roundtrip_cmake",
    [
      check_yelu1_roundtrip_cmake "string effects"
        (ESeq [
          ECmakeStringToupper { input = EString "abc"; out = "TMP" };
          ECmakeStringConcat { inputs = [ EVar "TMP"; EString "-x" ]; out = "OUT" };
          EVar "OUT";
        ]);
      check_yelu1_roundtrip_cmake "if and string effects"
        (ESeq [
          ECmakeIfStmt
            {
              cond = ECmakeStringEqual (EString "left", EString "right");
              then_ = ECmakeStringToupper { input = EString "bad"; out = "OUT" };
              else_ = Some (ECmakeStringToupper { input = EString "good"; out = "OUT" });
            };
          EVar "OUT";
        ]);
      check_yelu1_roundtrip_cmake "list effects"
        (ESeq [
          ECmakeListAppend { list = "XS"; items = [ EString "a"; EString "b" ] };
          ECmakeListGet { list = "XS"; indices = [ 1 ]; out = "ITEM" };
          EVar "ITEM";
        ]);
      check_yelu1_roundtrip_cmake "path effects"
        (ESeq [
          ECmakePathSet { path = "P"; input = EString "a/./b/../c"; normalize = false };
          ECmakePathNormalPath { path = "P"; out = None };
          EVar "P";
        ]);
      check_yelu1_roundtrip_cmake "cmake_op min_required and message"
        (ESeq [
          ECmakeMinimumRequired "3.20";
          ECmakeMessage { mode = "STATUS"; texts = [ EString "tiny cmake_op slice" ] };
        ]);
    ] )

let yelu2_lowering =
  ( "yelu2_lowering_cmake",
    [
      check_yelu2_lowering_cmake "if expression saved to output"
        (ESeq [
          ESetVar
            ( "OUT",
              EIfExpr
                {
                  cond = EStringEqual (EString "x", EString "x");
                  then_ = EStringUpper (EString "yes");
                  else_ = EStringUpper (EString "no");
                } );
          EVar "OUT";
        ]);
      check_yelu2_lowering_cmake "defined after unset"
        (ESeq [
          ESetVar ("X", EString "value");
          EUnsetVar "X";
          ESetVar
            ( "OUT",
              EIfExpr
                {
                  cond = EVarDefined "X";
                  then_ = EStringUpper (EString "no");
                  else_ = EStringUpper (EString "yes");
                } );
          EVar "OUT";
        ]);
      check_yelu2_lowering_cmake "int equality from string length"
        (ESeq [
          ESetVar ("LEN", EStringLen (EString "abc"));
          ESetVar
            ( "OUT",
              EIfExpr
                {
                  cond = EIntEqual (EVar "LEN", EInt 3);
                  then_ = EStringUpper (EString "yes");
                  else_ = EStringUpper (EString "no");
                } );
          EVar "OUT";
        ]);
      check_yelu2_lowering_cmake "list join in if expression"
        (ESeq [
          ESetVar ("XS", EList [ EString "a"; EString "b" ]);
          ESetVar ("JOINED", EStringJoin { sep = EString "-"; items = EVar "XS" });
          ESetVar
            ( "OUT",
              EIfExpr
                {
                  cond = EStringEqual (EVar "JOINED", EString "a-b");
                  then_ = EStringUpper (EString "yes");
                  else_ = EStringUpper (EString "no");
                } );
          EVar "OUT";
        ]);
      check_yelu2_lowering_cmake "list get in if expression"
        (ESeq [
          ESetVar ("XS", EList [ EString "no"; EString "yes" ]);
          ESetVar ("ITEM", EListGet (EVar "XS", EInt 1));
          ESetVar
            ( "OUT",
              EIfExpr
                {
                  cond = EStringEqual (EVar "ITEM", EString "yes");
                  then_ = EStringUpper (EString "yes");
                  else_ = EStringUpper (EString "no");
                } );
          EVar "OUT";
        ]);
      check_yelu2_lowering_cmake "path filename in if expression"
        (ESeq [
          ESetVar ("P", EString "/usr/local/bin/cmake");
          ESetVar ("FILENAME", EPathFilename (EVar "P"));
          ESetVar
            ( "OUT",
              EIfExpr
                {
                  cond = EStringEqual (EVar "FILENAME", EString "cmake");
                  then_ = EStringUpper (EString "yes");
                  else_ = EStringUpper (EString "no");
                } );
          EVar "OUT";
        ]);
      check_yelu2_lowering_cmake "file write read in if expression"
        (ESeq [
          EFileWrite
            {
              path = EString "${CMAKE_CURRENT_LIST_DIR}/yelu_tiny_file.txt";
              content = EString "yes";
            };
          ESetVar
            ("READ", EFileRead (EString "${CMAKE_CURRENT_LIST_DIR}/yelu_tiny_file.txt"));
          ESetVar
            ( "OUT",
              EIfExpr
                {
                  cond =
                    EAnd
                      ( EFileExists (EString "${CMAKE_CURRENT_LIST_DIR}/yelu_tiny_file.txt"),
                        EStringEqual (EVar "READ", EString "yes") );
                  then_ = EStringUpper (EString "yes");
                  else_ = EStringUpper (EString "no");
                } );
          EVar "OUT";
        ]);
      check_yelu2_lowering_cmake "ELet binding propagates through emit to cmake"
        (* Without phase-2a substitution this would emit
           [string(TOUPPER "${msg}" OUT)] with msg unset in cmake; OUT
           would be empty and stderr would not contain RESULT=YES.
           Phase-2a's env-threaded emit substitutes EVar "msg" with
           EString "yes" at emit time so cmake sees
           [string(TOUPPER "yes" OUT)] and the final message prints
           RESULT=YES. *)
        (ELet
           { var = "msg";
             value = EString "yes";
             body =
               ESeq
                 [ ESetVar ("OUT", EStringUpper (EVar "msg"));
                   EVar "OUT";
                 ] });
    ] )

let yelu2_configure_lowering =
  ( "yelu2_lowering_configure",
    [
      check_yelu2_lowering_configure "target declaration and existence"
        (ESeq [
          ESetVar
            ("APP", EExecutable { name = EString "app"; sources = [ EString "main.c" ] });
          ESetVar
            ( "OUT",
              EIfExpr
                {
                  cond = ETargetExists (ETarget "app");
                  then_ = EStringUpper (EString "yes");
                  else_ = EStringUpper (EString "no");
                } );
          EVar "OUT";
        ]);
      check_yelu2_lowering_configure "target sources mutation"
        ~files:
          [
            "main.c", "int main(void) { return 0; }\n";
            "extra.c", "int extra(void) { return 0; }\n";
          ]
        (ESeq [
          ESetVar
            ("APP", EExecutable { name = EString "app"; sources = [ EString "main.c" ] });
          ETargetAddSources { target = ETarget "app"; visibility = Vis_private; sources = [ EString "extra.c" ] };
          ESetVar
            ( "OUT",
              EIfExpr
                {
                  cond = ETargetExists (ETarget "app");
                  then_ = EStringUpper (EString "yes");
                  else_ = EStringUpper (EString "no");
                } );
          EVar "OUT";
        ]);
      check_yelu2_lowering_configure "library declaration and existence"
        ~files:[ "core.c", "int core(void) { return 0; }\n" ]
        (ESeq [
          ESetVar
            ( "CORE",
              ELibrary
                { name = EString "core"; type_ = Some "STATIC"; sources = [ EString "core.c" ] } );
          ESetVar
            ( "OUT",
              EIfExpr
                {
                  cond = ETargetExists (ETarget "core");
                  then_ = EStringUpper (EString "yes");
                  else_ = EStringUpper (EString "no");
                } );
          EVar "OUT";
        ]);
      check_yelu2_lowering_configure "target link libraries mutation"
        ~files:[ "main.c", "int main(void) { return 0; }\n" ]
        (ESeq [
          ESetVar
            ("APP", EExecutable { name = EString "app"; sources = [ EString "main.c" ] });
          ETargetLinkLibraries { target = ETarget "app"; visibility = Vis_private; items = [ EString "m" ] };
          ESetVar
            ( "OUT",
              EIfExpr
                {
                  cond = ETargetExists (ETarget "app");
                  then_ = EStringUpper (EString "yes");
                  else_ = EStringUpper (EString "no");
                } );
          EVar "OUT";
        ]);
      check_yelu2_lowering_configure "target include directories mutation"
        ~files:[ "main.c", "int main(void) { return 0; }\n" ]
        (ESeq [
          ESetVar
            ("APP", EExecutable { name = EString "app"; sources = [ EString "main.c" ] });
          ETargetIncludeDirectories { target = ETarget "app"; visibility = Vis_private; dirs = [ EString "include" ] };
          ESetVar
            ( "OUT",
              EIfExpr
                {
                  cond = ETargetExists (ETarget "app");
                  then_ = EStringUpper (EString "yes");
                  else_ = EStringUpper (EString "no");
                } );
          EVar "OUT";
        ]);
      check_yelu2_lowering_configure "dir add_subdirectory enters child"
        ~files:
          [
            "main.c", "int main(void) { return 0; }\n";
            "subdir/CMakeLists.txt", "message(\"RESULT=YES\")\n";
          ]
        (EAddSubdirectory (EString "subdir"));
      check_yelu2_lowering_configure "test enable + add_test configures clean"
        (ESeq [
          EEnableTesting;
          EAddTest
            { name = EString "smoke";
              command = EString "/bin/true";
              args = [] };
          ESetVar ("OUT", EStringUpper (EString "yes"));
          EVar "OUT";
        ]);
      check_yelu2_lowering_configure "property set + get round trip"
        (ESeq [
          ESetVar
            ("APP", EExecutable { name = EString "app"; sources = [ EString "main.c" ] });
          ESetTargetProperty
            { target = EString "app";
              property = "OUTPUT_NAME";
              value = EString "YES" };
          EGetTargetProperty
            { var = "OUT"; target = EString "app"; property = "OUTPUT_NAME" };
          EVar "OUT";
        ]);
      check_yelu2_lowering_configure "find_package non-required configures clean"
        (ESeq [
          EFindPackage { package_name = "YeluTinyNoSuchPackage"; required = false };
          ESetVar ("OUT", EStringUpper (EString "yes"));
          EVar "OUT";
        ]);
      check_yelu2_lowering_configure "try_compile probes a tiny C source"
        ~files:
          [
            "main.c", "int main(void) { return 0; }\n";
            "src/probe.c", "int main(void) { return 0; }\n";
          ]
        (ESeq [
          ETryCompile
            { result_var = "HAS_C";
              sources = [ EString "${CMAKE_SOURCE_DIR}/src/probe.c" ] };
          ESetVar ("OUT", EStringUpper (EString "yes"));
          EVar "OUT";
        ]);
      check_yelu2_lowering_configure "step1 program configures via tiny bridge"
        ~files:
          [
            "tutorial.cxx",
              "int main(int argc, char**) { return argc - 1; }\n";
            "TutorialConfig.h.in", "#define TUTORIAL_VERSION_MAJOR 1\n";
          ]
        (ESeq [
          (let open Yelu_langs.Yelu_cmake_utils in
           let cmd =
             ycmd_of_list
               (Step_common_ir.project_preamble
                @ Step_common_ir.cxx_standard_11
                @ [
                    Step_common_ir.configure_tutorial_header;
                    add_exe ~sources:[ yfile "tutorial.cxx" ] (ytval "Tutorial");
                    include_dirs (ytval "Tutorial")
                      [ ytarget_def
                          [ dir Yelu_langs.Yelu_cmake_utils.output_root ] ];
                  ])
           in
          to_normal cmd);
          ESetVar ("OUT", EStringUpper (EString "yes"));
          EVar "OUT";
        ]);
      check_yelu2_lowering_configure "step2 root program configures via tiny bridge"
        ~files:
          [
            "tutorial.cxx",
              "int main(int argc, char**) { return argc - 1; }\n";
            "TutorialConfig.h.in", "#define TUTORIAL_VERSION_MAJOR 1\n";
            "MathFunctions/CMakeLists.txt",
              "add_library(MathFunctions MathFunctions.cxx)\n";
            "MathFunctions/MathFunctions.cxx",
              "int mathfunctions_dummy(void) { return 0; }\n";
          ]
        (ESeq [
          (let open Yelu_langs.Yelu_cmake_utils in
           let cmd =
             ycmd_of_list
               (Step_common_ir.project_preamble
                @ Step_common_ir.cxx_standard_11
                @ [
                    ylet "tut" (ytval "Tutorial");
                    Step_common_ir.configure_tutorial_header;
                    yc_add_subdirectory (ydir "MathFunctions");
                    add_exe ~sources:[ yfile "tutorial.cxx" ] (yvar "tut");
                    link_lib
                      [ yvar "tut" ]
                      [ ytarget_def [ ytval "MathFunctions" ] ];
                    include_dirs (yvar "tut")
                      [
                        ytarget_def
                          [
                            dir Yelu_langs.Yelu_cmake_utils.output_root;
                            dir_concat
                              Yelu_langs.Yelu_cmake_utils.source_root
                              "MathFunctions";
                          ];
                      ];
                  ])
           in
           to_normal cmd);
	          ESetVar ("OUT", EStringUpper (EString "yes"));
	          EVar "OUT";
	        ]);
      check_yelu2_lowering_configure "step2 math program configures via tiny bridge"
        ~languages:[ "CXX" ]
        ~files:
          [
            "MathFunctions.cxx",
              "double mathfunctions_dummy(double x) { return x; }\n";
            "mysqrt.cxx",
              "double mysqrt(double x) { return x; }\n";
          ]
        (ESeq [
          (let open Yelu_langs.Yelu_cmake_utils in
           let cmd =
             ycmd_of_list
               [
                 ylet "math" (ytval "MathFunctions");
                 ylet "sqrt" (ytval "SqrtLibrary");
                 ylet "use_mymath" (ycstr "USE_MYMATH");
                 add_lib ~sources:[ yfile "MathFunctions.cxx" ] (yvar "math");
                 yc_option ~value:(ybool true)
                   ~msg:"Use tutorial provided math implementation"
                   (ycvar "USE_MYMATH");
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
           to_normal cmd);
          ESetVar ("OUT", EStringUpper (EString "yes"));
          EVar "OUT";
        ]);
      check_yelu2_lowering_configure "step3 root program configures via tiny bridge"
        ~files:
          [
            "tutorial.cxx",
              "int main(int argc, char**) { return argc - 1; }\n";
            "TutorialConfig.h.in", "#define TUTORIAL_VERSION_MAJOR 1\n";
            "MathFunctions/CMakeLists.txt",
              "add_library(MathFunctions MathFunctions.cxx)\n";
            "MathFunctions/MathFunctions.cxx",
              "int mathfunctions_dummy(void) { return 0; }\n";
          ]
        (ESeq [
          (let open Yelu_langs.Yelu_cmake_utils in
           let cmd =
             ycmd_of_list
               (Step_common_ir.project_preamble
                @ [
                    ylet "tut" (ytval "Tutorial");
                    ylet "flags" (ytval "tutorial_compiler_flags");
                  ]
                @ Step_common_ir.compiler_flags_lib
                @ Step_common_ir.cxx_standard_11
                @ [
                    Step_common_ir.configure_tutorial_header;
                    yc_add_subdirectory (ydir "MathFunctions");
                    add_exe ~sources:[ yfile "tutorial.cxx" ] (yvar "tut");
                    link_lib
                      [ yvar "tut" ]
                      [ ytarget_def [ ytval "MathFunctions"; yvar "flags" ] ];
                    include_dirs (yvar "tut")
                      [ ytarget_def
                          [ dir Yelu_langs.Yelu_cmake_utils.output_root ] ];
                  ])
           in
           to_normal cmd);
          ESetVar ("OUT", EStringUpper (EString "yes"));
          EVar "OUT";
        ]);
      check_yelu2_lowering_configure "step3 math program configures via tiny bridge"
        ~languages:[ "CXX" ]
        ~files:
          [
            "MathFunctions.cxx",
              "double mathfunctions_dummy(double x) { return x; }\n";
            "mysqrt.cxx",
              "double mysqrt(double x) { return x; }\n";
          ]
        (ESeq [
          ELibrary
            {
              name = EString "tutorial_compiler_flags";
              type_ = Some "INTERFACE";
              sources = [];
            };
          (let open Yelu_langs.Yelu_cmake_utils in
           let cmd =
             ycmd_of_list
               [
                 ylet "flags" (ytval "tutorial_compiler_flags");
                 ylet "math" (ytval "MathFunctions");
                 ylet "sqrt" (ytval "SqrtLibrary");
                 ylet "use_mymath" (ycstr "USE_MYMATH");
                 yc_extern_target "tutorial_compiler_flags";
                 add_lib ~sources:[ yfile "MathFunctions.cxx" ] (yvar "math");
                 include_dirs (yvar "math")
                   [
                     ytarget_def ~kind:Interface
                       [ ydir "${CMAKE_CURRENT_SOURCE_DIR}" ];
                   ];
                 yc_option ~value:(ybool true)
                   ~msg:"Use tutorial provided math implementation"
                   (ycvar "USE_MYMATH");
                 yifthen (ytruthy (yvar "use_mymath"))
                   (ycmd_of_list
                      [
                        compile_defs (yvar "math")
                          [ ytarget_def ~kind:Private [ ykeyword "USE_MYMATH" ] ];
                        add_lib ~type_:Lib_static
                          ~sources:[ yfile "mysqrt.cxx" ]
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
           to_normal cmd);
          ESetVar ("OUT", EStringUpper (EString "yes"));
          EVar "OUT";
        ]);
      check_yelu2_lowering_configure "step4 root program configures via tiny bridge"
        ~files:
          [
            "tutorial.cxx",
              "int main(int argc, char**) { return argc - 1; }\n";
            "TutorialConfig.h.in", "#define TUTORIAL_VERSION_MAJOR 1\n";
            "MathFunctions/CMakeLists.txt",
              "add_library(MathFunctions MathFunctions.cxx)\n";
            "MathFunctions/MathFunctions.cxx",
              "int mathfunctions_dummy(void) { return 0; }\n";
          ]
        (ESeq [
          (let open Yelu_langs.Yelu_cmake_utils in
           let cmd =
             ycmd_of_list
               (Step_common_ir.project_preamble
                @ [
                    ylet "tut" (ytval "Tutorial");
                    ylet "flags" (ytval "tutorial_compiler_flags");
                  ]
                @ Step_common_ir.compiler_flags_lib
                @ Step_common_ir.compiler_warning_options
                @ [
                    Step_common_ir.configure_tutorial_header;
                    yc_add_subdirectory (ydir "MathFunctions");
                    add_exe ~sources:[ yfile "tutorial.cxx" ] (yvar "tut");
                    link_lib [ yvar "tut" ]
                      [ ytarget_def [ ytval "MathFunctions"; yvar "flags" ] ];
                    include_dirs (yvar "tut")
                      [ ytarget_def
                          [ dir Yelu_langs.Yelu_cmake_utils.output_root ] ];
                  ])
           in
           to_normal cmd);
          ESetVar ("OUT", EStringUpper (EString "yes"));
          EVar "OUT";
        ]);
      check_yelu2_lowering_configure "step5 root program configures via tiny bridge"
        ~files:
          [
            "tutorial.cxx",
              "int main(int argc, char**) { return argc - 1; }\n";
            "TutorialConfig.h.in", "#define TUTORIAL_VERSION_MAJOR 1\n";
            "MathFunctions/CMakeLists.txt",
              "add_library(MathFunctions MathFunctions.cxx)\n";
            "MathFunctions/MathFunctions.cxx",
              "int mathfunctions_dummy(void) { return 0; }\n";
          ]
        (ESeq [
          (let open Yelu_langs.Yelu_cmake_utils in
           let cmd =
             ycmd_of_list
               (Step_common_ir.project_preamble
                @ [
                    ylet "tut" (ytval "Tutorial");
                    ylet "flags" (ytval "tutorial_compiler_flags");
                    ylet "do_test" (ycstr "do_test");
                  ]
                @ Step_common_ir.compiler_flags_lib
                @ Step_common_ir.compiler_warning_options
                @ [
                    Step_common_ir.configure_tutorial_header;
                    yc_add_subdirectory (ydir "MathFunctions");
                    add_exe ~sources:[ yfile "tutorial.cxx" ] (yvar "tut");
                    link_lib [ yvar "tut" ]
                      [ ytarget_def [ ytval "MathFunctions"; yvar "flags" ] ];
                    include_dirs (yvar "tut")
                      [ ytarget_def
                          [ dir Yelu_langs.Yelu_cmake_utils.output_root ] ];
                  ]
                @ Step_common_ir.install_tutorial
                @ Step_common_ir.test_suite ~ctest:false)
           in
           to_normal cmd);
          ESetVar ("OUT", EStringUpper (EString "yes"));
          EVar "OUT";
        ]);
      check_yelu2_lowering_configure "step5 math program configures via tiny bridge"
        ~languages:[ "CXX" ]
        ~files:
          [
            "MathFunctions.cxx",
              "double mathfunctions_dummy(double x) { return x; }\n";
            "mysqrt.cxx",
              "double mysqrt(double x) { return x; }\n";
            "MathFunctions.h", "#pragma once\n";
          ]
        (ESeq [
          ELibrary
            {
              name = EString "tutorial_compiler_flags";
              type_ = Some "INTERFACE";
              sources = [];
            };
          (let open Yelu_langs.Yelu_cmake_utils in
           let cmd =
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
                    [
                      ytarget_def ~kind:Interface
                        [ ydir "${CMAKE_CURRENT_SOURCE_DIR}" ];
                    ];
                  yc_option ~value:(ybool true)
                    ~msg:"Use tutorial provided math implementation"
                    (ycvar "USE_MYMATH");
                  yifthen (ytruthy (yvar "use_mymath"))
                    (ycmd_of_list
                       [
                         compile_defs (yvar "math")
                           [ ytarget_def ~kind:Private [ ykeyword "USE_MYMATH" ] ];
                         add_lib ~type_:Lib_static
                           ~sources:[ yfile "mysqrt.cxx" ]
                           (yvar "sqrt");
                         link_lib [ yvar "sqrt" ]
                           [ ytarget_def ~kind:Public [ yvar "flags" ] ];
                         link_lib [ yvar "math" ]
                           [ ytarget_def ~kind:Private [ yvar "sqrt" ] ];
                       ]);
                  link_lib [ yvar "math" ]
                    [ ytarget_def ~kind:Public [ yvar "flags" ] ];
                ]
                @ Step_common_ir.math_install_libs ())
           in
           to_normal cmd);
          ESetVar ("OUT", EStringUpper (EString "yes"));
          EVar "OUT";
        ]);
      check_yelu2_lowering_configure "step6 root program configures via tiny bridge"
        ~files:
          [
            "tutorial.cxx",
              "int main(int argc, char**) { return argc - 1; }\n";
            "TutorialConfig.h.in", "#define TUTORIAL_VERSION_MAJOR 1\n";
            "MathFunctions/CMakeLists.txt",
              "add_library(MathFunctions MathFunctions.cxx)\n";
            "MathFunctions/MathFunctions.cxx",
              "int mathfunctions_dummy(void) { return 0; }\n";
          ]
        (ESeq [
          (let open Yelu_langs.Yelu_cmake_utils in
           let cmd =
             ycmd_of_list
               (Step_common_ir.project_preamble
                @ [
                    ylet "tut" (ytval "Tutorial");
                    ylet "flags" (ytval "tutorial_compiler_flags");
                    ylet "do_test" (ycstr "do_test");
                  ]
                @ Step_common_ir.compiler_flags_lib
                @ Step_common_ir.compiler_warning_options
                @ [
                    Step_common_ir.configure_tutorial_header;
                    yc_add_subdirectory (ydir "MathFunctions");
                    add_exe ~sources:[ yfile "tutorial.cxx" ] (yvar "tut");
                    link_lib [ yvar "tut" ]
                      [ ytarget_def [ ytval "MathFunctions"; yvar "flags" ] ];
                    include_dirs (yvar "tut")
                      [ ytarget_def
                          [ dir Yelu_langs.Yelu_cmake_utils.output_root ] ];
                  ]
                @ Step_common_ir.install_tutorial
                @ Step_common_ir.test_suite ~ctest:true)
           in
           to_normal cmd);
          ESetVar ("OUT", EStringUpper (EString "yes"));
          EVar "OUT";
        ]);
      check_yelu2_lowering_configure "step7 root program configures via tiny bridge"
        ~files:
          [
            "tutorial.cxx",
              "int main(int argc, char**) { return argc - 1; }\n";
            "TutorialConfig.h.in", "#define TUTORIAL_VERSION_MAJOR 1\n";
            "MathFunctions/CMakeLists.txt",
              "add_library(MathFunctions MathFunctions.cxx)\n";
            "MathFunctions/MathFunctions.cxx",
              "int mathfunctions_dummy(void) { return 0; }\n";
          ]
        (ESeq [
          (let open Yelu_langs.Yelu_cmake_utils in
           let cmd =
             ycmd_of_list
               (Step_common_ir.project_preamble
                @ [
                    ylet "tut" (ytval "Tutorial");
                    ylet "flags" (ytval "tutorial_compiler_flags");
                    ylet "do_test" (ycstr "do_test");
                  ]
                @ Step_common_ir.compiler_flags_lib
                @ Step_common_ir.compiler_warning_options
                @ [
                    Step_common_ir.configure_tutorial_header;
                    yc_add_subdirectory (ydir "MathFunctions");
                    add_exe ~sources:[ yfile "tutorial.cxx" ] (yvar "tut");
                    link_lib [ yvar "tut" ]
                      [ ytarget_def [ ytval "MathFunctions"; yvar "flags" ] ];
                    include_dirs (yvar "tut")
                      [ ytarget_def
                          [ dir Yelu_langs.Yelu_cmake_utils.output_root ] ];
                  ]
                @ Step_common_ir.install_tutorial
                @ Step_common_ir.test_suite ~ctest:true)
           in
           to_normal cmd);
          ESetVar ("OUT", EStringUpper (EString "yes"));
          EVar "OUT";
        ]);
      check_yelu2_lowering_configure "step10 root program configures via tiny bridge"
        ~files:
          [
            "tutorial.cxx",
              "int main(int argc, char**) { return argc - 1; }\n";
            "TutorialConfig.h.in", "#define TUTORIAL_VERSION_MAJOR 1\n";
            "License.txt", "Tutorial license\n";
            "MathFunctions/CMakeLists.txt",
              "add_library(MathFunctions MathFunctions.cxx)\n";
            "MathFunctions/MathFunctions.cxx",
              "int mathfunctions_dummy(void) { return 0; }\n";
          ]
        (ESeq [
          (let open Yelu_langs.Yelu_cmake_utils in
           let cmd =
             ycmd_of_list
               (Step_common_ir.project_preamble
                @ [
                    ylet "tut" (ytval "Tutorial");
                    ylet "flags" (ytval "tutorial_compiler_flags");
                    ylet "do_test" (ycstr "do_test");
                  ]
                @ Step_common_ir.shared_libs_output_dirs
                @ Step_common_ir.compiler_flags_lib
                @ Step_common_ir.compiler_warning_options
                @ [
                    Step_common_ir.configure_tutorial_header;
                    yc_add_subdirectory (ydir "MathFunctions");
                    add_exe ~sources:[ yfile "tutorial.cxx" ] (yvar "tut");
                    link_lib [ yvar "tut" ]
                      [ ytarget_def [ ytval "MathFunctions"; yvar "flags" ] ];
                    include_dirs (yvar "tut")
                      [ ytarget_def
                          [ dir Yelu_langs.Yelu_cmake_utils.output_root ] ];
                  ]
                @ Step_common_ir.install_tutorial
                @ Step_common_ir.test_suite ~ctest:true
                @ Step_common_ir.cpack_basic)
           in
           to_normal cmd);
          ESetVar ("OUT", EStringUpper (EString "yes"));
          EVar "OUT";
        ]);
      check_yelu2_lowering_configure "step12 root program configures via tiny bridge"
        ~files:
          [
            "tutorial.cxx",
              "int main(int argc, char**) { return argc - 1; }\n";
            "TutorialConfig.h.in", "#define TUTORIAL_VERSION_MAJOR 1\n";
            "License.txt", "Tutorial license\n";
            "Config.cmake.in",
              "@PACKAGE_INIT@\ninclude(\"${CMAKE_CURRENT_LIST_DIR}/MathFunctionsTargets.cmake\")\n";
            (* MathFunctions/CMakeLists.txt for step12 must declare the
               MathFunctionsTargets export set, since the root's
               install(EXPORT ...) below references it. *)
            "MathFunctions/CMakeLists.txt",
              "add_library(MathFunctions MathFunctions.cxx)\n\
               install(TARGETS MathFunctions EXPORT MathFunctionsTargets DESTINATION lib)\n";
            "MathFunctions/MathFunctions.cxx",
              "int mathfunctions_dummy(void) { return 0; }\n";
          ]
        (ESeq [
          (let open Yelu_langs.Yelu_cmake_utils in
           let cmd =
             ycmd_of_list
               (Step_common_ir.project_preamble
                @ [
                    ylet "tut" (ytval "Tutorial");
                    ylet "flags" (ytval "tutorial_compiler_flags");
                    ylet "do_test" (ycstr "do_test");
                  ]
                @ Step_common_ir.shared_libs_output_dirs
                @ [ yc_set (ycvar "CMAKE_DEBUG_POSTFIX") [ ystr "d" ] ]
                @ Step_common_ir.compiler_flags_lib
                @ Step_common_ir.compiler_warning_options
                @ [
                    Step_common_ir.configure_tutorial_header;
                    yc_add_subdirectory (ydir "MathFunctions");
                    add_exe ~sources:[ yfile "tutorial.cxx" ] (yvar "tut");
                    yc_set_target_properties (yvar "tut")
                      [ ("DEBUG_POSTFIX", ystr "${CMAKE_DEBUG_POSTFIX}") ];
                    link_lib [ yvar "tut" ]
                      [ ytarget_def [ ytval "MathFunctions"; yvar "flags" ] ];
                    include_dirs (yvar "tut")
                      [ ytarget_def
                          [ dir Yelu_langs.Yelu_cmake_utils.output_root ] ];
                  ]
                @ Step_common_ir.install_tutorial
                @ Step_common_ir.test_suite ~ctest:true
                @ Step_common_ir.cpack_basic
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
                      (dir_concat Yelu_langs.Yelu_cmake_utils.output_this
                         "MathFunctionsConfig.cmake");
                    yc_write_basic_package_version_file
                      ~compatibility:Yelu_langs.Lang_cmake.Same_major_version
                      ~version:(ystr_eval
                                  "${Tutorial_VERSION_MAJOR}.${Tutorial_VERSION_MINOR}")
                      (dir_concat Yelu_langs.Yelu_cmake_utils.output_this
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
                      ~file:(dir_concat Yelu_langs.Yelu_cmake_utils.output_this
                               "MathFunctionsTargets.cmake");
                  ])
           in
           to_normal cmd);
          ESetVar ("OUT", EStringUpper (EString "yes"));
          EVar "OUT";
        ]);
      (* Slim configure test for step8_table's distinguishing piece — the
         custom_command(OUTPUT ...) rule. The full v1 step8_table also
         links MakeTable against [tutorial_compiler_flags], which would
         need the upper-level target to exist; we drop that line here so
         the rule can configure standalone. *)
      check_yelu2_lowering_configure "step8_table MakeTable configures via tiny bridge"
        ~files:
          [
            "MakeTable.cxx",
              "#include <cstdio>\nint main(int, char**) { return 0; }\n";
          ]
        (ESeq [
          (let open Yelu_langs.Yelu_cmake_utils in
           let cmd =
             ycmd_of_list
               (Step_common_ir.project_preamble
                @ [
                    add_exe ~sources:[ yfile "MakeTable.cxx" ]
                      (ytval "MakeTable");
                    yc_add_custom_command
                      ~outputs:[ yfile "${CMAKE_CURRENT_BINARY_DIR}/Table.h" ]
                      ~depends:[ ystr "MakeTable" ]
                      [ custom_command "MakeTable"
                          [ "${CMAKE_CURRENT_BINARY_DIR}/Table.h" ] ];
                  ])
           in
           to_normal cmd);
          ESetVar ("OUT", EStringUpper (EString "yes"));
          EVar "OUT";
        ]);
    ] )

let yelu2_build_lowering =
  ( "yelu2_lowering_build",
    [
      check_yelu2_file_api_equiv "target graph matches reference cmake"
        ~files:
          [
            "main.c", "int main(void) { return 0; }\n";
            "extra.c", "int extra(void) { return 0; }\n";
            "core.c", "int core(void) { return 0; }\n";
          ]
        ~reference:
          {|
add_library(core STATIC "core.c")
add_executable(app "main.c")
target_sources(app PRIVATE "extra.c")
target_link_libraries(app PRIVATE "core" "m")
target_include_directories(app PRIVATE "include")
target_compile_definitions(app PRIVATE "USE_FEATURE")
target_compile_options(app PRIVATE "-Wall")
target_link_options(app PRIVATE "-Wl,--as-needed")
target_link_directories(app PRIVATE "/opt/lib")
|}
        (ESeq [
          ESetVar
            ( "CORE",
              ELibrary
                { name = EString "core"; type_ = Some "STATIC"; sources = [ EString "core.c" ] } );
          ESetVar
            ("APP", EExecutable { name = EString "app"; sources = [ EString "main.c" ] });
          ETargetAddSources { target = ETarget "app"; visibility = Vis_private; sources = [ EString "extra.c" ] };
          ETargetLinkLibraries
            { target = ETarget "app"; visibility = Vis_private; items = [ EString "core"; EString "m" ] };
          ETargetIncludeDirectories { target = ETarget "app"; visibility = Vis_private; dirs = [ EString "include" ] };
          ETargetCompileDefinitions
            { target = ETarget "app"; visibility = Vis_private; definitions = [ EString "USE_FEATURE" ] };
          ETargetCompileOptions
            { target = ETarget "app"; visibility = Vis_private; options_ = [ EString "-Wall" ] };
          ETargetLinkOptions
            { target = ETarget "app"; visibility = Vis_private; options_ = [ EString "-Wl,--as-needed" ] };
          ETargetLinkDirectories
            { target = ETarget "app"; visibility = Vis_private; dirs = [ EString "/opt/lib" ] };
        ]);
      check_yelu2_custom_target_build "custom target command runs"
        (ECustomTarget
           {
             name = EString "yelu_hello";
             all = false;
             commands =
               [
                 {
                   command = "${CMAKE_COMMAND}";
                   args = [ "-E"; "echo"; "YELU_CUSTOM_TARGET_OK" ];
                 };
               ];
             depends = [];
             comment = Some "tiny custom target";
           })
        ~target:"yelu_hello"
        ~pattern:"YELU_CUSTOM_TARGET_OK";
      check_yelu2_custom_target_build "custom command produces output for custom target"
        (ESeq [
          ECustomCommand
            {
              outputs = [ EString "yelu_generated.txt" ];
              commands =
                [
                  {
                    command = "${CMAKE_COMMAND}";
                    args = [ "-E"; "echo"; "YELU_CUSTOM_COMMAND_OK" ];
                  };
                  {
                    command = "${CMAKE_COMMAND}";
                    args = [ "-E"; "touch"; "yelu_generated.txt" ];
                  };
                ];
              depends = [];
              comment = Some "tiny custom command";
              verbatim = true;
            };
          ECustomTarget
            {
              name = EString "yelu_consume";
              all = false;
              commands = [];
              depends = [ EString "yelu_generated.txt" ];
              comment = None;
            };
        ])
        ~target:"yelu_consume"
        ~pattern:"YELU_CUSTOM_COMMAND_OK";
      check_yelu2_install "install target and header under temp prefix"
        (ESeq [
          ESetVar
            ("APP", EExecutable { name = EString "app"; sources = [ EString "main.c" ] });
          EInstallTargets
            { targets = [ ETarget "app" ]; destination = EString "bin"; export = None };
          EInstallFiles
            { files = [ EString "include/app.h" ]; destination = EString "include" };
        ])
        ~expected:[ "bin/app"; "include/app.h" ];
    ] )

let () =
  Alcotest.run "yelu_tiny_cmake"
    [ yelu1_roundtrip; yelu2_lowering; yelu2_configure_lowering; yelu2_build_lowering ]
