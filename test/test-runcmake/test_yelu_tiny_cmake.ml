open Yelu_langs.Yelu_tiny
open Yelu_langs.Yelu_theory_store
open Yelu_langs.Yelu_theory_bool
open Yelu_langs.Yelu_theory_int
open Yelu_langs.Yelu_theory_list
open Yelu_langs.Yelu_theory_path
open Yelu_langs.Yelu_theory_file
open Yelu_langs.Yelu_theory_target
open Yelu_langs.Yelu_theory_install
open Yelu_langs.Yelu_theory_string
open Yelu_langs.Yelu_theory_if
open Yelu_langs.Yelu_surface_cmake_list
open Yelu_langs.Yelu_surface_cmake_path
open Yelu_langs.Yelu_surface_cmake_string
open Yelu_langs.Yelu_surface_cmake_if
open Yelu_langs.Yelu_tiny_eval
open Yelu_langs.Yelu_tiny_cmake_emit
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
  check_same_cmake_output name expr (lower_yelu2_to_yelu1 (lift_yelu1_to_yelu2 expr))

let check_yelu2_lowering_cmake name expr =
  Alcotest.test_case name `Quick (fun () ->
    let cmake_text = emit_script (lower_yelu2_to_yelu1 expr) in
    let result = run_script cmake_text in
    check_exit 0 result;
    Alcotest.(check string) "stdout" "" result.stdout;
    Alcotest.(check string) "stderr" "RESULT=YES\n" result.stderr)

let check_yelu2_lowering_configure ?(files = [ "main.c", "int main(void) { return 0; }\n" ]) name expr =
  Alcotest.test_case name `Quick (fun () ->
    let cmake_text = emit_script (lower_yelu2_to_yelu1 expr) in
    let result =
      run_configure ~languages:[ "C" ] ~files cmake_text
    in
    check_exit 0 result.run;
    check_stderr_matches "RESULT=YES" result.run)

let check_yelu2_custom_target_build name expr ~target ~pattern =
  Alcotest.test_case name `Quick (fun () ->
    let cmake_text = emit_script (lower_yelu2_to_yelu1 expr) in
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
    let cmake_text = emit_script (lower_yelu2_to_yelu1 expr) in
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
    let yelu_cmake = emit_script (lower_yelu2_to_yelu1 expr) in
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
          ECmakeListGet { list = "XS"; index = EInt 1; out = "ITEM" };
          EVar "ITEM";
        ]);
      check_yelu1_roundtrip_cmake "path effects"
        (ESeq [
          ECmakePathSet { path = "P"; input = EString "a/./b/../c"; normalize = false };
          ECmakePathNormalPath { path = "P"; out = None };
          EVar "P";
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
          ETargetAddSources { target = ETarget "app"; visibility = "PRIVATE"; sources = [ EString "extra.c" ] };
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
          ETargetLinkLibraries { target = ETarget "app"; visibility = "PRIVATE"; items = [ EString "m" ] };
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
          ETargetIncludeDirectories { target = ETarget "app"; visibility = "PRIVATE"; dirs = [ EString "include" ] };
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
          ETargetAddSources { target = ETarget "app"; visibility = "PRIVATE"; sources = [ EString "extra.c" ] };
          ETargetLinkLibraries
            { target = ETarget "app"; visibility = "PRIVATE"; items = [ EString "core"; EString "m" ] };
          ETargetIncludeDirectories { target = ETarget "app"; visibility = "PRIVATE"; dirs = [ EString "include" ] };
          ETargetCompileDefinitions
            { target = ETarget "app"; visibility = "PRIVATE"; definitions = [ EString "USE_FEATURE" ] };
          ETargetCompileOptions
            { target = ETarget "app"; visibility = "PRIVATE"; options_ = [ EString "-Wall" ] };
          ETargetLinkOptions
            { target = ETarget "app"; visibility = "PRIVATE"; options_ = [ EString "-Wl,--as-needed" ] };
          ETargetLinkDirectories
            { target = ETarget "app"; visibility = "PRIVATE"; dirs = [ EString "/opt/lib" ] };
        ]);
      check_yelu2_custom_target_build "custom target command runs"
        (ECustomTarget
           {
             name = "yelu_hello";
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
              name = "yelu_consume";
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
