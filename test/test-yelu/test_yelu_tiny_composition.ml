open Base
open Yelu_langs.Yelu_tiny
open Yelu_langs.Yelu_theory_store
open Yelu_langs.Yelu_surface_cmake_store
open Yelu_langs.Yelu_theory_int
open Yelu_langs.Yelu_theory_list
open Yelu_langs.Yelu_surface_cmake_list
open Yelu_langs.Yelu_surface_cmake_path
open Yelu_langs.Yelu_theory_path
open Yelu_langs.Yelu_surface_cmake_file
open Yelu_langs.Yelu_theory_file
open Yelu_langs.Yelu_surface_cmake_target
open Yelu_langs.Yelu_theory_target
open Yelu_langs.Yelu_surface_cmake_install
open Yelu_langs.Yelu_theory_install
open Yelu_langs.Yelu_surface_cmake_string
open Yelu_langs.Yelu_theory_string
open Yelu_langs.Yelu_surface_cmake_if
open Yelu_langs.Yelu_theory_if
open Yelu_langs.Yelu_surface_cmake_cmake_op
open Yelu_langs.Yelu_theory_cmake_op
open Yelu_langs.Yelu_surface_cmake_dir
open Yelu_langs.Yelu_theory_dir
open Yelu_langs.Yelu_surface_cmake_test
open Yelu_langs.Yelu_theory_test
open Yelu_langs.Yelu_surface_cmake_property
open Yelu_langs.Yelu_theory_property
open Yelu_langs.Yelu_surface_cmake_find
open Yelu_langs.Yelu_theory_find
open Yelu_langs.Yelu_surface_cmake_try
open Yelu_langs.Yelu_theory_try
open Yelu_langs.Yelu_tiny_eval

module Old = Yelu_langs.Lang_yelu_cmake

let target
      ?(kind = TargetExecutable)
      ?(sources = [])
      ?(link_libraries = [])
      ?(include_directories = [])
      ?(compile_definitions = [])
      ?(compile_options = [])
      ?(link_options = [])
      ?(link_directories = [])
      name =
  {
    name;
    kind;
    sources;
    link_libraries;
    include_directories;
    compile_definitions;
    compile_options;
    link_options;
    link_directories;
  }

let env_of_bindings
      ?(files = [])
      ?(targets = [])
      ?(custom_targets = [])
      ?(custom_commands = [])
      ?(install_rules = [])
      ?project
      ?cmake_min_version
      ?(messages = [])
      ?(subdirectories = [])
      ?(testing_enabled = false)
      ?(tests = [])
      ?(target_properties = [])
      ?(find_packages = [])
      ?(try_compiles = [])
      bindings =
  let env =
    List.fold bindings ~init:empty_env ~f:(fun env (key, data) ->
      set_var env ~key ~data)
  in
  let env =
    List.fold files ~init:env ~f:(fun env (path, content) ->
      set_file env ~path ~content)
  in
  let env = List.fold targets ~init:env ~f:set_target in
  let env = List.fold custom_targets ~init:env ~f:set_custom_target in
  let env = List.fold custom_commands ~init:env ~f:set_custom_command in
  let env = List.fold install_rules ~init:env ~f:add_install_rule in
  let env =
    Option.value_map project ~default:env ~f:(fun info -> set_project env info)
  in
  let env =
    Option.value_map cmake_min_version ~default:env ~f:(fun v -> set_cmake_min_version env v)
  in
  let env =
    List.fold messages ~init:env ~f:(fun env { mode; texts } -> add_message env mode texts)
  in
  let env = List.fold subdirectories ~init:env ~f:add_subdirectory in
  let env = if testing_enabled then enable_testing env else env in
  let env = List.fold tests ~init:env ~f:add_test in
  let env =
    List.fold target_properties ~init:env ~f:(fun env (target, property, value) ->
      set_target_property env ~target ~property ~value)
  in
  let env = List.fold find_packages ~init:env ~f:add_find_package in
  List.fold try_compiles ~init:env ~f:add_try_compile

let old_cvar name : Old.tc_name = { ns = Old.Ns_var; name }
let old_str s = Old.Yexpr_string (Old.Ycs_string s)
let old_var name = Old.Yexpr_var (Old.Yvar name)

let check_yelu_cmake_bridge_to_yelu1 name stmt ~expected_value ~expected_env =
  Alcotest.test_case name `Quick (fun () ->
    let expr = Yelu_langs.Yelu_cmake_to_yelu1.stmt stmt in
    let env, value = eval_yelu1_expr empty_env expr in
    Alcotest.(check bool) "expected value" true
      (equal_value expected_value value);
    Alcotest.(check bool) "expected env" true
      (equal_env expected_env env))

let parse_old_yelu source =
  match Yelu_langs.Lang_yelu_parse.parse_program source with
  | Ok stmt -> stmt
  | Error error -> Alcotest.failf "parse error: %s" error

let check_parsed_yelu_bridge_to_yelu1 name source ~expected_value ~expected_env =
  Alcotest.test_case name `Quick (fun () ->
    let expr =
      source
      |> parse_old_yelu
      |> Yelu_langs.Yelu_cmake_to_yelu1.stmt
    in
    let env, value = eval_yelu1_expr empty_env expr in
    Alcotest.(check bool) "expected value" true
      (equal_value expected_value value);
    Alcotest.(check bool) "expected env" true
      (equal_env expected_env env))

let check_yelu1_to_yelu2 name expr ~expected_value ~expected_env =
  Alcotest.test_case name `Quick (fun () ->
    let env = empty_env in
    let left_env, left_value = eval_yelu1_expr env expr in
    let right_env, right_value = eval_yelu2_expr env (lift_yelu1_to_yelu2 expr) in
    Alcotest.(check bool) "translation preserves value" true
      (equal_value left_value right_value);
    Alcotest.(check bool) "translation preserves env" true
      (equal_env left_env right_env);
    Alcotest.(check bool) "expected value" true
      (equal_value expected_value left_value);
    Alcotest.(check bool) "expected env" true
      (equal_env expected_env left_env))

let check_yelu2_to_yelu1 name expr ~expected_value ~expected_env =
  Alcotest.test_case name `Quick (fun () ->
    let env = empty_env in
    let left_env, left_value = eval_yelu2_expr env expr in
    let right_env, right_value = eval_yelu1_expr env (lower_yelu2_to_yelu1 expr) in
    Alcotest.(check bool) "translation preserves value" true
      (equal_value left_value right_value);
    Alcotest.(check bool) "translation preserves env" true
      (equal_env left_env right_env);
    Alcotest.(check bool) "expected value" true
      (equal_value expected_value left_value);
    Alcotest.(check bool) "expected env" true
      (equal_env expected_env left_env))

let check_yelu1_lift_lower_roundtrip name expr =
  Alcotest.test_case name `Quick (fun () ->
    let env = empty_env in
    let left_env, left_value = eval_yelu1_expr env expr in
    let lifted = lift_yelu1_to_yelu2 expr in
    let lowered = lower_yelu2_to_yelu1 lifted in
    let right_env, right_value = eval_yelu1_expr env lowered in
    Alcotest.(check bool) "roundtrip preserves value" true
      (equal_value left_value right_value);
    Alcotest.(check bool) "roundtrip preserves env" true
      (equal_env left_env right_env))

let yelu1_to_yelu2 =
  ( "yelu1_to_yelu2",
    [
      check_yelu1_to_yelu2 "concat literals"
        (ESeq [
          ECmakeStringConcat { inputs = [ EString "a"; EString "b"; EString "c" ]; out = "OUT" };
          EVar "OUT";
        ])
        ~expected_value:(VString "abc")
        ~expected_env:(env_of_bindings [ "OUT", VString "abc" ]);
      check_yelu1_to_yelu2 "upper nested in concat"
        (ESeq [
          ECmakeStringToupper { input = EString "b"; out = "TMP" };
          ECmakeStringConcat { inputs = [ EString "a"; EVar "TMP" ]; out = "OUT" };
          EVar "OUT";
        ])
        ~expected_value:(VString "aB")
        ~expected_env:(env_of_bindings [ "TMP", VString "B"; "OUT", VString "aB" ]);
      check_yelu1_to_yelu2 "replace all"
        (ECmakeStringReplace
           { match_ = EString "ll"; replace = EString "y"; input = EString "hello"; out = "OUT" })
        ~expected_value:VUnit
        ~expected_env:(env_of_bindings [ "OUT", VString "heyo" ]);
      check_yelu1_to_yelu2 "length of upper"
        (ESeq [
          ECmakeStringToupper { input = EString "abc"; out = "TMP" };
          ECmakeStringLength { input = EVar "TMP"; out = "LEN" };
          EVar "LEN";
        ])
        ~expected_value:(VInt 3)
        ~expected_env:(env_of_bindings [ "TMP", VString "ABC"; "LEN", VInt 3 ]);
      check_yelu1_to_yelu2 "store defined and unset"
        (ESeq [
          ESetVar ("X", EString "value");
          ESetVar ("BEFORE", ECmakeVarDefined "X");
          ECmakeUnsetVar "X";
          ESetVar ("AFTER", ECmakeVarDefined "X");
          EVar "AFTER";
        ])
        ~expected_value:(VBool false)
        ~expected_env:(env_of_bindings [ "BEFORE", VBool true; "AFTER", VBool false ]);
      check_yelu1_to_yelu2 "if statement chooses then branch"
        (ESeq [
          ECmakeIfStmt
            {
              cond = ECmakeStringEqual (EString "a", EString "a");
              then_ = ECmakeStringToupper { input = EString "ok"; out = "OUT" };
              else_ = Some (ECmakeStringToupper { input = EString "bad"; out = "OUT" });
            };
          EVar "OUT";
        ])
        ~expected_value:(VString "OK")
        ~expected_env:(env_of_bindings [ "OUT", VString "OK" ]);
      check_yelu1_to_yelu2 "if statement chooses else branch"
        (ESeq [
          ECmakeIfStmt
            {
              cond = ECmakeStringEqual (EString "a", EString "b");
              then_ = ECmakeStringToupper { input = EString "bad"; out = "OUT" };
              else_ = Some (ECmakeStringToupper { input = EString "ok"; out = "OUT" });
            };
          EVar "OUT";
        ])
        ~expected_value:(VString "OK")
        ~expected_env:(env_of_bindings [ "OUT", VString "OK" ]);
      check_yelu1_to_yelu2 "list append length and join"
        (ESeq [
          ESetVar ("XS", EList []);
          ECmakeListAppend { list = "XS"; items = [ EString "a"; EString "b" ] };
          ECmakeListGet { list = "XS"; index = EInt 1; out = "ITEM" };
          ECmakeListLength { list = "XS"; out = "LEN" };
          ECmakeListJoin { list = "XS"; glue = EString "-"; out = "OUT" };
          EVar "OUT";
        ])
        ~expected_value:(VString "a-b")
        ~expected_env:
          (env_of_bindings
             [
               "XS", VList [ VString "a"; VString "b" ];
               "ITEM", VString "b";
               "LEN", VInt 2;
               "OUT", VString "a-b";
             ]);
      check_yelu1_to_yelu2 "path filename and normal path"
        (ESeq [
          ECmakePathSet { path = "P"; input = EString "/usr/local/bin/cmake"; normalize = false };
          ECmakePathGetFilename { path = "P"; out = "FILENAME" };
          ECmakePathSet { path = "Q"; input = EString "a/./b/../c"; normalize = false };
          ECmakePathNormalPath { path = "Q"; out = Some "NORMAL" };
          EVar "NORMAL";
        ])
        ~expected_value:(VString "a/c")
        ~expected_env:
          (env_of_bindings
             [
               "P", VString "/usr/local/bin/cmake";
               "FILENAME", VString "cmake";
               "Q", VString "a/./b/../c";
               "NORMAL", VString "a/c";
             ]);
      check_yelu1_to_yelu2 "file write read and exists"
        (ESeq [
          ECmakeFileWrite
            { path = EString "build/generated.txt"; content = [ EString "hello"; EString " file" ] };
          ESetVar ("EXISTS", ECmakeFileExists (EString "build/generated.txt"));
          ECmakeFileRead { path = EString "build/generated.txt"; out = "OUT" };
          EVar "OUT";
        ])
        ~expected_value:(VString "hello file")
        ~expected_env:
          (env_of_bindings
             ~files:[ "build/generated.txt", "hello file" ]
             [ "EXISTS", VBool true; "OUT", VString "hello file" ]);
      check_yelu1_to_yelu2 "target declaration and existence"
        (ESeq [
          ECmakeAddExecutable { name = "app"; sources = [ EString "main.c" ] };
          ESetVar ("OUT", ECmakeTargetExists "app");
          EVar "OUT";
        ])
        ~expected_value:(VBool true)
        ~expected_env:
          (env_of_bindings ~targets:[ target "app" ] [ "OUT", VBool true ]);
      check_yelu1_to_yelu2 "library declaration"
        (ESeq [
          ECmakeAddLibrary { name = "core"; type_ = Some "STATIC"; sources = [ EString "core.c" ] };
          ESetVar ("OUT", ECmakeTargetExists "core");
          EVar "OUT";
        ])
        ~expected_value:(VBool true)
        ~expected_env:
          (env_of_bindings
             ~targets:[ target "core" ~kind:(TargetLibrary (Some "STATIC")) ]
             [ "OUT", VBool true ]);
      check_yelu1_to_yelu2 "target sources mutation"
        (ESeq [
          ECmakeAddExecutable { name = "app"; sources = [ EString "main.c" ] };
          ECmakeTargetSources { target = "app"; visibility = "PUBLIC"; sources = [ EString "extra.c" ] };
          ETarget "app";
        ])
        ~expected_value:(VTarget "app")
        ~expected_env:
          (env_of_bindings
             ~targets:
               [
                 target "app"
                   ~sources:[ { visibility = "PUBLIC"; source = "extra.c" } ];
               ]
             []);
      check_yelu1_to_yelu2 "target link libraries mutation"
        (ESeq [
          ECmakeAddExecutable { name = "app"; sources = [ EString "main.c" ] };
          ECmakeTargetLinkLibraries { target = "app"; visibility = "PRIVATE"; items = [ EString "m" ] };
          ETarget "app";
        ])
        ~expected_value:(VTarget "app")
        ~expected_env:
          (env_of_bindings
             ~targets:
               [
                 target "app"
                   ~link_libraries:[ { visibility = "PRIVATE"; item = "m" } ];
               ]
             []);
      check_yelu1_to_yelu2 "target include directories mutation"
        (ESeq [
          ECmakeAddExecutable { name = "app"; sources = [ EString "main.c" ] };
          ECmakeTargetIncludeDirectories { target = "app"; visibility = "PUBLIC"; dirs = [ EString "include" ] };
          ETarget "app";
        ])
        ~expected_value:(VTarget "app")
        ~expected_env:
          (env_of_bindings
             ~targets:
               [
                 target "app"
                   ~include_directories:[ { visibility = "PUBLIC"; dir = "include" } ];
               ]
             []);
      check_yelu1_to_yelu2 "target compile definitions mutation"
        (ESeq [
          ECmakeAddExecutable { name = "app"; sources = [ EString "main.c" ] };
          ECmakeTargetCompileDefinitions
            { target = "app"; visibility = "PRIVATE"; definitions = [ EString "USE_FEATURE" ] };
          ETarget "app";
        ])
        ~expected_value:(VTarget "app")
        ~expected_env:
          (env_of_bindings
             ~targets:
               [
                 target "app"
                   ~compile_definitions:
                     [ { visibility = "PRIVATE"; definition = "USE_FEATURE" } ];
               ]
             []);
      check_yelu1_to_yelu2 "target compile options mutation"
        (ESeq [
          ECmakeAddExecutable { name = "app"; sources = [ EString "main.c" ] };
          ECmakeTargetCompileOptions
            { target = "app"; visibility = "PRIVATE"; options_ = [ EString "-Wall" ] };
          ETarget "app";
        ])
        ~expected_value:(VTarget "app")
        ~expected_env:
          (env_of_bindings
             ~targets:
               [
                 target "app"
                   ~compile_options:
                     [ { visibility = "PRIVATE"; option_ = "-Wall" } ];
               ]
             []);
      check_yelu1_to_yelu2 "target link options mutation"
        (ESeq [
          ECmakeAddExecutable { name = "app"; sources = [ EString "main.c" ] };
          ECmakeTargetLinkOptions
            { target = "app"; visibility = "PRIVATE"; options_ = [ EString "-Wl,--as-needed" ] };
          ETarget "app";
        ])
        ~expected_value:(VTarget "app")
        ~expected_env:
          (env_of_bindings
             ~targets:
               [
                 target "app"
                   ~link_options:
                     [ { visibility = "PRIVATE"; link_option = "-Wl,--as-needed" } ];
               ]
             []);
      check_yelu1_to_yelu2 "target link directories mutation"
        (ESeq [
          ECmakeAddExecutable { name = "app"; sources = [ EString "main.c" ] };
          ECmakeTargetLinkDirectories
            { target = "app"; visibility = "PUBLIC"; dirs = [ EString "/opt/lib" ] };
          ETarget "app";
        ])
        ~expected_value:(VTarget "app")
        ~expected_env:
          (env_of_bindings
             ~targets:
               [
                 target "app"
                   ~link_directories:
                     [ { visibility = "PUBLIC"; link_directory = "/opt/lib" } ];
               ]
             []);
      check_yelu1_to_yelu2 "custom target declaration"
        (ECmakeAddCustomTarget
           {
             name = "hello";
             all = false;
             commands = [ { command = "cmake"; args = [ "-E"; "echo"; "HELLO" ] } ];
             depends = [ EString "input.txt" ];
             comment = Some "hello target";
           })
        ~expected_value:VUnit
        ~expected_env:
          (env_of_bindings
             ~custom_targets:
               [
                 {
                   name = "hello";
                   all = false;
                   commands = [ { command = "cmake"; args = [ "-E"; "echo"; "HELLO" ] } ];
                   depends = [ "input.txt" ];
                   comment = Some "hello target";
                 };
               ]
             []);
      check_yelu1_to_yelu2 "custom command declaration"
        (ECmakeAddCustomCommand
           {
             outputs = [ EString "generated.txt" ];
             commands = [ { command = "cmake"; args = [ "-E"; "touch"; "generated.txt" ] } ];
             depends = [ EString "input.txt" ];
             comment = Some "generating generated.txt";
             verbatim = true;
           })
        ~expected_value:VUnit
        ~expected_env:
          (env_of_bindings
             ~custom_commands:
               [
                 {
                   outputs = [ "generated.txt" ];
                   commands = [ { command = "cmake"; args = [ "-E"; "touch"; "generated.txt" ] } ];
                   depends = [ "input.txt" ];
                   comment = Some "generating generated.txt";
                   verbatim = true;
                 };
               ]
             []);
      check_yelu1_to_yelu2 "install targets and files declarations"
        (ESeq [
          ECmakeAddExecutable { name = "app"; sources = [ EString "main.c" ] };
          ECmakeInstallTargets
            { targets = [ "app" ]; destination = EString "bin"; export = None };
          ECmakeInstallFiles
            { files = [ EString "include/app.h" ]; destination = EString "include" };
        ])
        ~expected_value:VUnit
        ~expected_env:
          (env_of_bindings
             ~targets:[ target "app" ]
             ~install_rules:
               [
                 InstallTargets { targets = [ "app" ]; destination = "bin"; export = None };
                 InstallFiles { files = [ "include/app.h" ]; destination = "include" };
               ]
             []);
      check_yelu1_to_yelu2 "cmake_op project + minimum_required + message"
        (ESeq [
          ECmakeMinimumRequired "3.20";
          ECmakeProject { name = "demo"; languages = [ "C" ]; version = None };
          ECmakeMessage { mode = "STATUS"; texts = [ EString "hello" ] };
        ])
        ~expected_value:VUnit
        ~expected_env:
          (env_of_bindings
             ~project:{ name = "demo"; languages = [ "C" ]; version = None }
             ~cmake_min_version:"3.20"
             ~messages:[ { mode = "STATUS"; texts = [ "hello" ] } ]
             []);
      check_yelu1_to_yelu2 "dir add_subdirectory"
        (ESeq [
          ECmakeAddSubdirectory (EString "subdir_a");
          ECmakeAddSubdirectory (EString "subdir_b");
        ])
        ~expected_value:VUnit
        ~expected_env:
          (env_of_bindings
             ~subdirectories:[ "subdir_a"; "subdir_b" ]
             []);
      check_yelu1_to_yelu2 "test enable + add_test"
        (ESeq [
          ECmakeEnableTesting;
          ECmakeAddTest
            { name = EString "smoke";
              command = EString "/bin/true";
              args = [ EString "--quiet" ] };
        ])
        ~expected_value:VUnit
        ~expected_env:
          (env_of_bindings
             ~testing_enabled:true
             ~tests:[ { name = "smoke"; command = "/bin/true"; args = [ "--quiet" ] } ]
             []);
      check_yelu1_to_yelu2 "property set/get round trip"
        (ESeq [
          ECmakeAddExecutable { name = "app"; sources = [ EString "main.c" ] };
          ECmakeSetTargetProperty
            { target = "app"; property = "OUTPUT_NAME"; value = EString "myapp" };
          ECmakeGetTargetProperty
            { var = "OUT"; target = "app"; property = "OUTPUT_NAME" };
        ])
        ~expected_value:VUnit
        ~expected_env:
          (env_of_bindings
             ~targets:[ target "app" ]
             ~target_properties:[ "app", "OUTPUT_NAME", "myapp" ]
             [ "OUT", VString "myapp" ]);
      check_yelu1_to_yelu2 "ELet binds inside body and scopes out after"
        (ESeq [
          ELet { var = "x"; value = EString "hello"; body = ESetVar ("OUT", EVar "x") };
        ])
        ~expected_value:VUnit
        ~expected_env:
          (env_of_bindings
             (* `x` is gone after the let body completes. *)
             [ "OUT", VString "hello" ]);
      check_yelu1_to_yelu2 "ELet shadows an outer ESetVar binding inside body"
        (ESeq [
          ESetVar ("x", EString "outer");
          ELet { var = "x";
                 value = EString "inner";
                 body = ESetVar ("INNER_VIEW", EVar "x") };
          ESetVar ("OUTER_VIEW", EVar "x");
        ])
        ~expected_value:VUnit
        ~expected_env:
          (env_of_bindings
             [ "x", VString "outer";
               "INNER_VIEW", VString "inner";
               "OUTER_VIEW", VString "outer";
             ]);
      check_yelu1_to_yelu2 "find_package declaration"
        (ECmakeFindPackage { package_name = "Threads"; required = false })
        ~expected_value:VUnit
        ~expected_env:
          (env_of_bindings
             ~find_packages:[ { package_name = "Threads"; required = false } ]
             []);
      check_yelu1_to_yelu2 "try_compile records and stubs result_var"
        (ECmakeTryCompile
           { result_var = "HAS_C"; sources = [ EString "src/probe.c" ] })
        ~expected_value:VUnit
        ~expected_env:
          (env_of_bindings
             ~try_compiles:[ { result_var = "HAS_C"; sources = [ "src/probe.c" ] } ]
             [ "HAS_C", VBool true ]);
    ] )

let yelu2_to_yelu1 =
  ( "yelu2_to_yelu1",
    [
      check_yelu2_to_yelu1 "concat literals"
        (ESeq [
          ESetVar ("OUT", EStringConcat [ EString "x"; EString "y" ]);
          EVar "OUT";
        ])
        ~expected_value:(VString "xy")
        ~expected_env:(env_of_bindings [ "OUT", VString "xy" ]);
      check_yelu2_to_yelu1 "upper nested in replace"
        (ESeq [
          ESetVar ("TMP", EStringUpper (EString "a-b-a"));
          ESetVar
            ( "OUT",
              EStringReplaceAll
                {
                  needle = EString "A";
                  replacement = EString "z";
                  haystack = EVar "TMP";
                } );
          EVar "OUT";
        ])
        ~expected_value:(VString "z-B-z")
        ~expected_env:(env_of_bindings [ "TMP", VString "A-B-A"; "OUT", VString "z-B-z" ]);
      check_yelu2_to_yelu1 "length of concat"
        (ESeq [
          ESetVar ("TMP", EStringConcat [ EString "ab"; EString "cd" ]);
          ESetVar ("LEN", EStringLen (EVar "TMP"));
          EVar "LEN";
        ])
        ~expected_value:(VInt 4)
        ~expected_env:(env_of_bindings [ "TMP", VString "abcd"; "LEN", VInt 4 ]);
      check_yelu2_to_yelu1 "if expression saved to output"
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
        ])
        ~expected_value:(VString "YES")
        ~expected_env:(env_of_bindings [ "OUT", VString "YES" ]);
      check_yelu2_to_yelu1 "store defined and unset"
        (ESeq [
          ESetVar ("X", EString "value");
          ESetVar ("BEFORE", EVarDefined "X");
          EUnsetVar "X";
          ESetVar ("AFTER", EVarDefined "X");
          EVar "AFTER";
        ])
        ~expected_value:(VBool false)
        ~expected_env:(env_of_bindings [ "BEFORE", VBool true; "AFTER", VBool false ]);
      check_yelu2_to_yelu1 "int equality from string length"
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
        ])
        ~expected_value:(VString "YES")
        ~expected_env:(env_of_bindings [ "LEN", VInt 3; "OUT", VString "YES" ]);
      check_yelu2_to_yelu1 "list length feeds if expression"
        (ESeq [
          ESetVar ("XS", EList [ EString "a"; EString "b" ]);
          ESetVar ("LEN", EListLength (EVar "XS"));
          ESetVar
            ( "OUT",
              EIfExpr
                {
                  cond = EIntEqual (EVar "LEN", EInt 2);
                  then_ = EStringUpper (EString "yes");
                  else_ = EStringUpper (EString "no");
                } );
          EVar "OUT";
        ])
        ~expected_value:(VString "YES")
        ~expected_env:
          (env_of_bindings
             [
               "XS", VList [ VString "a"; VString "b" ];
               "LEN", VInt 2;
               "OUT", VString "YES";
             ]);
      check_yelu2_to_yelu1 "list join lowers to cmake surface"
        (ESeq [
          ESetVar ("XS", EList [ EString "a"; EString "b" ]);
          ESetVar ("OUT", EStringJoin { sep = EString "-"; items = EVar "XS" });
          EVar "OUT";
        ])
        ~expected_value:(VString "a-b")
        ~expected_env:
          (env_of_bindings
             [
               "XS", VList [ VString "a"; VString "b" ];
               "OUT", VString "a-b";
             ]);
      check_yelu2_to_yelu1 "list get lowers to cmake surface"
        (ESeq [
          ESetVar ("XS", EList [ EString "first"; EString "second" ]);
          ESetVar ("OUT", EListGet (EVar "XS", EInt 1));
          EVar "OUT";
        ])
        ~expected_value:(VString "second")
        ~expected_env:
          (env_of_bindings
             [
               "XS", VList [ VString "first"; VString "second" ];
               "OUT", VString "second";
             ]);
      check_yelu2_to_yelu1 "path normalize lowers to cmake surface"
        (ESeq [
          ESetVar ("P", EString "a/./b/../c");
          ESetVar ("OUT", EPathNormalize (EVar "P"));
          EVar "OUT";
        ])
        ~expected_value:(VString "a/c")
        ~expected_env:(env_of_bindings [ "P", VString "a/./b/../c"; "OUT", VString "a/c" ]);
      check_yelu2_to_yelu1 "path filename lowers to cmake surface"
        (ESeq [
          ESetVar ("P", EString "/usr/local/bin/cmake");
          ESetVar ("OUT", EPathFilename (EVar "P"));
          EVar "OUT";
        ])
        ~expected_value:(VString "cmake")
        ~expected_env:
          (env_of_bindings [ "P", VString "/usr/local/bin/cmake"; "OUT", VString "cmake" ]);
      check_yelu2_to_yelu1 "file write read and exists lower to cmake surface"
        (ESeq [
          EFileWrite
            { path = EString "build/generated.txt"; content = EString "hello file" };
          ESetVar ("EXISTS", EFileExists (EString "build/generated.txt"));
          ESetVar ("OUT", EFileRead (EString "build/generated.txt"));
          EVar "OUT";
        ])
        ~expected_value:(VString "hello file")
        ~expected_env:
          (env_of_bindings
             ~files:[ "build/generated.txt", "hello file" ]
             [ "EXISTS", VBool true; "OUT", VString "hello file" ]);
      check_yelu2_to_yelu1 "target declaration lowers to cmake surface"
        (ESeq [
          ESetVar
            ("APP", EExecutable { name = EString "app"; sources = [ EString "main.c" ] });
          ESetVar ("OUT", ETargetExists (ETarget "app"));
          EVar "OUT";
        ])
        ~expected_value:(VBool true)
        ~expected_env:
          (env_of_bindings
             ~targets:[ target "app" ]
             [
               "APP", VTarget "app";
               "OUT", VBool true;
             ]);
      check_yelu2_to_yelu1 "library declaration lowers to cmake surface"
        (ESeq [
          ESetVar
            ( "CORE",
              ELibrary
                { name = EString "core"; type_ = Some "STATIC"; sources = [ EString "core.c" ] } );
          ESetVar ("OUT", ETargetExists (ETarget "core"));
          EVar "OUT";
        ])
        ~expected_value:(VBool true)
        ~expected_env:
          (env_of_bindings
             ~targets:[ target "core" ~kind:(TargetLibrary (Some "STATIC")) ]
             [
               "CORE", VTarget "core";
               "OUT", VBool true;
             ]);
      check_yelu2_to_yelu1 "target sources lowers to cmake surface"
        (ESeq [
          ESetVar
            ("APP", EExecutable { name = EString "app"; sources = [ EString "main.c" ] });
          ETargetAddSources { target = ETarget "app"; visibility = "INTERFACE"; sources = [ EString "extra.c" ] };
        ])
        ~expected_value:(VTarget "app")
        ~expected_env:
          (env_of_bindings
             ~targets:
               [
                 target "app"
                   ~sources:[ { visibility = "INTERFACE"; source = "extra.c" } ];
               ]
             [
               "APP", VTarget "app";
             ]);
      check_yelu2_to_yelu1 "target link libraries lowers to cmake surface"
        (ESeq [
          ESetVar
            ("APP", EExecutable { name = EString "app"; sources = [ EString "main.c" ] });
          ETargetLinkLibraries { target = ETarget "app"; visibility = "PRIVATE"; items = [ EString "m" ] };
        ])
        ~expected_value:(VTarget "app")
        ~expected_env:
          (env_of_bindings
             ~targets:
               [
                 target "app"
                   ~link_libraries:[ { visibility = "PRIVATE"; item = "m" } ];
               ]
             [
               "APP", VTarget "app";
             ]);
      check_yelu2_to_yelu1 "target include directories lowers to cmake surface"
        (ESeq [
          ESetVar
            ("APP", EExecutable { name = EString "app"; sources = [ EString "main.c" ] });
          ETargetIncludeDirectories { target = ETarget "app"; visibility = "INTERFACE"; dirs = [ EString "iface" ] };
        ])
        ~expected_value:(VTarget "app")
        ~expected_env:
          (env_of_bindings
             ~targets:
               [
                 target "app"
                   ~include_directories:[ { visibility = "INTERFACE"; dir = "iface" } ];
               ]
             [
               "APP", VTarget "app";
             ]);
      check_yelu2_to_yelu1 "target compile definitions lowers to cmake surface"
        (ESeq [
          ESetVar
            ("APP", EExecutable { name = EString "app"; sources = [ EString "main.c" ] });
          ETargetCompileDefinitions
            { target = ETarget "app"; visibility = "PUBLIC"; definitions = [ EString "USE_FEATURE" ] };
        ])
        ~expected_value:(VTarget "app")
        ~expected_env:
          (env_of_bindings
             ~targets:
               [
                 target "app"
                   ~compile_definitions:
                     [ { visibility = "PUBLIC"; definition = "USE_FEATURE" } ];
               ]
             [
               "APP", VTarget "app";
             ]);
      check_yelu2_to_yelu1 "target compile options lowers to cmake surface"
        (ESeq [
          ESetVar
            ("APP", EExecutable { name = EString "app"; sources = [ EString "main.c" ] });
          ETargetCompileOptions
            { target = ETarget "app"; visibility = "PUBLIC"; options_ = [ EString "-O2" ] };
        ])
        ~expected_value:(VTarget "app")
        ~expected_env:
          (env_of_bindings
             ~targets:
               [
                 target "app"
                   ~compile_options:
                     [ { visibility = "PUBLIC"; option_ = "-O2" } ];
               ]
             [
               "APP", VTarget "app";
             ]);
      check_yelu2_to_yelu1 "target link options lowers to cmake surface"
        (ESeq [
          ESetVar
            ("APP", EExecutable { name = EString "app"; sources = [ EString "main.c" ] });
          ETargetLinkOptions
            { target = ETarget "app"; visibility = "PRIVATE"; options_ = [ EString "-Wl,--gc-sections" ] };
        ])
        ~expected_value:(VTarget "app")
        ~expected_env:
          (env_of_bindings
             ~targets:
               [
                 target "app"
                   ~link_options:
                     [ { visibility = "PRIVATE"; link_option = "-Wl,--gc-sections" } ];
               ]
             [
               "APP", VTarget "app";
             ]);
      check_yelu2_to_yelu1 "target link directories lowers to cmake surface"
        (ESeq [
          ESetVar
            ("APP", EExecutable { name = EString "app"; sources = [ EString "main.c" ] });
          ETargetLinkDirectories
            { target = ETarget "app"; visibility = "INTERFACE"; dirs = [ EString "/usr/local/lib" ] };
        ])
        ~expected_value:(VTarget "app")
        ~expected_env:
          (env_of_bindings
             ~targets:
               [
                 target "app"
                   ~link_directories:
                     [ { visibility = "INTERFACE"; link_directory = "/usr/local/lib" } ];
               ]
             [
               "APP", VTarget "app";
             ]);
      check_yelu2_to_yelu1 "custom target lowers to cmake surface"
        (ECustomTarget
           {
             name = "hello";
             all = false;
             commands = [ { command = "cmake"; args = [ "-E"; "echo"; "HELLO" ] } ];
             depends = [ EString "input.txt" ];
             comment = None;
           })
        ~expected_value:VUnit
        ~expected_env:
          (env_of_bindings
             ~custom_targets:
               [
                 {
                   name = "hello";
                   all = false;
                   commands = [ { command = "cmake"; args = [ "-E"; "echo"; "HELLO" ] } ];
                   depends = [ "input.txt" ];
                   comment = None;
                 };
               ]
             []);
      check_yelu2_to_yelu1 "custom command lowers to cmake surface"
        (ECustomCommand
           {
             outputs = [ EString "generated.txt" ];
             commands = [ { command = "cmake"; args = [ "-E"; "touch"; "generated.txt" ] } ];
             depends = [ EString "input.txt" ];
             comment = None;
             verbatim = true;
           })
        ~expected_value:VUnit
        ~expected_env:
          (env_of_bindings
             ~custom_commands:
               [
                 {
                   outputs = [ "generated.txt" ];
                   commands = [ { command = "cmake"; args = [ "-E"; "touch"; "generated.txt" ] } ];
                   depends = [ "input.txt" ];
                   comment = None;
                   verbatim = true;
                 };
               ]
             []);
      check_yelu2_to_yelu1 "install targets and files lower to cmake surface"
        (ESeq [
          ESetVar
            ("APP", EExecutable { name = EString "app"; sources = [ EString "main.c" ] });
          EInstallTargets
            { targets = [ ETarget "app" ]; destination = EString "bin"; export = None };
          EInstallFiles
            { files = [ EString "include/app.h" ]; destination = EString "include" };
        ])
        ~expected_value:VUnit
        ~expected_env:
          (env_of_bindings
             ~targets:[ target "app" ]
             ~install_rules:
               [
                 InstallTargets { targets = [ "app" ]; destination = "bin"; export = None };
                 InstallFiles { files = [ "include/app.h" ]; destination = "include" };
               ]
             [ "APP", VTarget "app" ]);
      check_yelu2_to_yelu1 "cmake_op project + min + message lower to cmake"
        (ESeq [
          EMinVersion "3.20";
          EProject { name = "demo"; languages = [ "C" ]; version = None };
          EMessage { mode = "STATUS"; texts = [ EString "hi" ] };
        ])
        ~expected_value:VUnit
        ~expected_env:
          (env_of_bindings
             ~project:{ name = "demo"; languages = [ "C" ]; version = None }
             ~cmake_min_version:"3.20"
             ~messages:[ { mode = "STATUS"; texts = [ "hi" ] } ]
             []);
      check_yelu2_to_yelu1 "dir add_subdirectory lower to cmake"
        (ESeq [
          EAddSubdirectory (EString "subdir_x");
          EAddSubdirectory (EString "subdir_y");
        ])
        ~expected_value:VUnit
        ~expected_env:
          (env_of_bindings
             ~subdirectories:[ "subdir_x"; "subdir_y" ]
             []);
      check_yelu2_to_yelu1 "test enable + add_test lower to cmake"
        (ESeq [
          EEnableTesting;
          EAddTest
            { name = EString "smoke";
              command = EString "/bin/true";
              args = [] };
        ])
        ~expected_value:VUnit
        ~expected_env:
          (env_of_bindings
             ~testing_enabled:true
             ~tests:[ { name = "smoke"; command = "/bin/true"; args = [] } ]
             []);
      check_yelu2_to_yelu1 "ELet lower to cmake preserves scope"
        (ELet
           { var = "x";
             value = EString "hello";
             body = ESetVar ("OUT", EVar "x") })
        ~expected_value:VUnit
        ~expected_env:(env_of_bindings [ "OUT", VString "hello" ]);
      check_yelu2_to_yelu1 "find_package lower to cmake"
        (EFindPackage { package_name = "Threads"; required = true })
        ~expected_value:VUnit
        ~expected_env:
          (env_of_bindings
             ~find_packages:[ { package_name = "Threads"; required = true } ]
             []);
      check_yelu2_to_yelu1 "try_compile lower to cmake"
        (ETryCompile
           { result_var = "HAS_C"; sources = [ EString "src/probe.c" ] })
        ~expected_value:VUnit
        ~expected_env:
          (env_of_bindings
             ~try_compiles:[ { result_var = "HAS_C"; sources = [ "src/probe.c" ] } ]
             [ "HAS_C", VBool true ]);
      check_yelu2_to_yelu1 "property set/get lower to cmake"
        (ESeq [
          ESetVar
            ("APP", EExecutable { name = EString "app"; sources = [ EString "main.c" ] });
          ESetTargetProperty
            { target = EString "app"; property = "OUTPUT_NAME"; value = EString "myapp" };
          EGetTargetProperty
            { var = "OUT"; target = "app"; property = "OUTPUT_NAME" };
        ])
        ~expected_value:VUnit
        ~expected_env:
          (env_of_bindings
             ~targets:[ target "app" ]
             ~target_properties:[ "app", "OUTPUT_NAME", "myapp" ]
             [ "APP", VTarget "app"; "OUT", VString "myapp" ]);
    ] )

let yelu1_roundtrip =
  ( "yelu1_lift_lower_roundtrip",
    [
      check_yelu1_lift_lower_roundtrip "string effects"
        (ESeq [
          ECmakeStringToupper { input = EString "abc"; out = "TMP" };
          ECmakeStringConcat { inputs = [ EVar "TMP"; EString "-x" ]; out = "OUT" };
          EVar "OUT";
        ]);
      check_yelu1_lift_lower_roundtrip "if and string effects"
        (ESeq [
          ECmakeIfStmt
            {
              cond = ECmakeStringEqual (EString "left", EString "right");
              then_ = ECmakeStringToupper { input = EString "bad"; out = "OUT" };
              else_ = Some (ECmakeStringToupper { input = EString "good"; out = "OUT" });
            };
          EVar "OUT";
        ]);
    ] )

let yelu_cmake_bridge =
  ( "yelu_cmake_to_yelu1",
    [
      check_yelu_cmake_bridge_to_yelu1 "old string subset bridges to Yelu1"
        (Old.Ystmt_list
           [
             Old.Ylet { var = Old.Yvar "msg"; value = old_str "hello" };
             Old.Ys_string
               (Old.Ystr_toupper { string = old_var "msg"; out = old_cvar "TMP" });
             Old.Ys_string
               (Old.Ystr_concat
                  {
                    out = old_cvar "OUT";
                    inputs = [ old_str "value="; Old.Yexpr_name (old_cvar "TMP") ];
                  });
             Old.Ys_var
               (Old.Yvar_set
                  {
                    cvar = old_cvar "RESULT";
                    values = [ Old.Yexpr_name (old_cvar "OUT") ];
                    parent_scope = false;
                  });
             Old.Ys_string
               (Old.Ystr_length
                  { string = Old.Yexpr_name (old_cvar "RESULT"); out = old_cvar "LEN" });
           ])
        ~expected_value:VUnit
        ~expected_env:
          (env_of_bindings
             (* `msg` is a let-binding, not a cmake set, so it's gone from
                env.vars after the body completes. *)
             [
               "TMP", VString "HELLO";
               "OUT", VString "value=HELLO";
               "RESULT", VString "value=HELLO";
               "LEN", VInt 11;
             ]);
      check_yelu_cmake_bridge_to_yelu1 "old if and string compare bridge to Yelu1"
        (Old.Yif
           {
             cond = Old.Yexpr_str_equal (old_str "a", old_str "a");
             then_ =
               Old.Ys_string
                 (Old.Ystr_replace
                    {
                      match_string = old_str "ll";
                      replace_string = old_str "y";
                      inputs = [ old_str "hello" ];
                      out = old_cvar "OUT";
                    });
             else_ =
               Some
                 (Old.Ys_string
                    (Old.Ystr_toupper { string = old_str "bad"; out = old_cvar "OUT" }));
           })
        ~expected_value:VUnit
        ~expected_env:(env_of_bindings [ "OUT", VString "heyo" ]);
      check_yelu_cmake_bridge_to_yelu1 "old defined condition bridges to Yelu1"
        (Old.Ystmt_list
           [
             Old.Ys_var
               (Old.Yvar_set
                  { cvar = old_cvar "X"; values = [ old_str "value" ]; parent_scope = false });
             Old.Yif
               {
                 cond = Old.Yexpr_is_defined { ns = Old.Ns_var; name = "X" };
                 then_ =
                   Old.Ys_string
                     (Old.Ystr_toupper { string = old_str "yes"; out = old_cvar "OUT" });
                 else_ =
                   Some
                     (Old.Ys_string
                        (Old.Ystr_toupper { string = old_str "no"; out = old_cvar "OUT" }));
               };
           ])
        ~expected_value:VUnit
        ~expected_env:(env_of_bindings [ "X", VString "value"; "OUT", VString "YES" ]);
      check_parsed_yelu_bridge_to_yelu1 "parsed old string program bridges to Yelu1"
        {|
        (
          let msg = "hello" in
          string_toupper msg ~out:TMP;
          string_concat ~out:OUT "value=" TMP;
          string_length OUT ~out:LEN
        )
        |}
        ~expected_value:VUnit
        ~expected_env:
          (env_of_bindings
             (* `msg` scoped out after the body. *)
             [
               "TMP", VString "HELLO";
               "OUT", VString "value=HELLO";
               "LEN", VInt 11;
             ]);
      check_parsed_yelu_bridge_to_yelu1 "parsed old if program bridges to Yelu1"
        {|
        (
          if str_eq "a" "b" then
            ( string_toupper "bad" ~out:OUT )
          else
            ( string_replace "ll" "y" "hello" ~out:OUT )
        )
        |}
        ~expected_value:VUnit
        ~expected_env:(env_of_bindings [ "OUT", VString "heyo" ]);
      check_parsed_yelu_bridge_to_yelu1 "parsed old defined condition bridges to Yelu1"
        {|
        (
          X := "value";
          if defined X then
            ( string_toupper "yes" ~out:OUT )
          else
            ( string_toupper "no" ~out:OUT )
        )
        |}
        ~expected_value:VUnit
        ~expected_env:(env_of_bindings [ "X", VString "value"; "OUT", VString "YES" ]);
      check_yelu_cmake_bridge_to_yelu1 "old list subset bridges to Yelu1"
        (Old.Ystmt_list
           [
             Old.Ys_list
               (Old.Ylist_append
                  { cvar = old_cvar "XS"; values = [ old_str "a"; old_str "b" ] });
             Old.Ys_list
               (Old.Ylist_get
                  { cvar = old_cvar "XS"; indices = [ 1 ]; out = old_cvar "ITEM" });
             Old.Ys_list
               (Old.Ylist_length { cvar = old_cvar "XS"; out = old_cvar "LEN" });
             Old.Ys_list
               (Old.Ylist_join
                  { cvar = old_cvar "XS"; glue = old_str "-"; out = old_cvar "OUT" });
           ])
        ~expected_value:VUnit
        ~expected_env:
          (env_of_bindings
             [
               "XS", VList [ VString "a"; VString "b" ];
               "ITEM", VString "b";
               "LEN", VInt 2;
               "OUT", VString "a-b";
             ]);
      check_parsed_yelu_bridge_to_yelu1 "parsed old list program bridges to Yelu1"
        {|
        (
          list_append XS "a" "b";
          list_get XS 1 ~out:ITEM;
          list_length XS ~out:LEN;
          list_join XS "-" ~out:OUT
        )
        |}
        ~expected_value:VUnit
        ~expected_env:
          (env_of_bindings
             [
               "XS", VList [ VString "a"; VString "b" ];
               "ITEM", VString "b";
               "LEN", VInt 2;
               "OUT", VString "a-b";
             ]);
      check_yelu_cmake_bridge_to_yelu1 "old path subset bridges to Yelu1"
        (Old.Ystmt_list
           [
             Old.Ys_path
               (Old.Ypath_set
                  {
                    path_var = old_cvar "P";
                    input = old_str "/usr/local/bin/cmake";
                    normalize = false;
                  });
             Old.Ys_path
               (Old.Ypath_get
                  {
                    path_var = old_cvar "P";
                    field = Yelu_langs.Lang_cmake.Cpf_filename;
                    out = old_cvar "FILENAME";
                  });
             Old.Ys_path
               (Old.Ypath_set
                  {
                    path_var = old_cvar "Q";
                    input = old_str "a/./b/../c";
                    normalize = false;
                  });
             Old.Ys_path
               (Old.Ypath_normal_path
                  { path_var = old_cvar "Q"; out = Some (old_cvar "NORMAL") });
           ])
        ~expected_value:VUnit
        ~expected_env:
          (env_of_bindings
             [
               "P", VString "/usr/local/bin/cmake";
               "FILENAME", VString "cmake";
               "Q", VString "a/./b/../c";
               "NORMAL", VString "a/c";
             ]);
      check_parsed_yelu_bridge_to_yelu1 "parsed old path program bridges to Yelu1"
        {|
        (
          path_set P "/usr/local/bin/cmake";
          path_get P ~out:FILENAME;
          path_set Q "a/./b/../c";
          path_normal_path Q ~out:NORMAL
        )
        |}
        ~expected_value:VUnit
        ~expected_env:
          (env_of_bindings
             [
               "P", VString "/usr/local/bin/cmake";
               "FILENAME", VString "cmake";
               "Q", VString "a/./b/../c";
               "NORMAL", VString "a/c";
             ]);
      check_yelu_cmake_bridge_to_yelu1 "old file write/read bridge to Yelu1"
        (Old.Ystmt_list
           [
             Old.Ys_file
               (Old.Yfile_write
                  {
                    file = old_str "build/generated.txt";
                    append = false;
                    content = [ old_str "hello"; old_str " file" ];
                  });
             Old.Yif
               {
                 cond = Old.Yexpr_exists (old_str "build/generated.txt");
                 then_ =
                   Old.Ys_file
                     (Old.Yfile_read
                        {
                          file = old_str "build/generated.txt";
                          out = old_cvar "OUT";
                          offset = None;
                          limit = None;
                          hex = false;
                        });
                 else_ =
                   Some
                     (Old.Ys_string
                        (Old.Ystr_toupper { string = old_str "missing"; out = old_cvar "OUT" }));
               };
           ])
        ~expected_value:VUnit
        ~expected_env:
          (env_of_bindings
             ~files:[ "build/generated.txt", "hello file" ]
             [ "OUT", VString "hello file" ]);
      check_parsed_yelu_bridge_to_yelu1 "parsed old file write/read bridge to Yelu1"
        {|
        (
          file_write "build/generated.txt" "hello" " file";
          if exists "build/generated.txt" then
            ( file_read "build/generated.txt" ~out:OUT )
          else
            ( string_toupper "missing" ~out:OUT )
        )
        |}
        ~expected_value:VUnit
        ~expected_env:
          (env_of_bindings
             ~files:[ "build/generated.txt", "hello file" ]
             [ "OUT", VString "hello file" ]);
      check_yelu_cmake_bridge_to_yelu1 "old target layer-a bridges to Yelu1"
        (Old.Ystmt_list
           [
             Old.Ys_target
               (Old.Ytgt_add_executable
                  {
                    name = Old.Yexpr_name { ns = Old.Ns_target; name = "app" };
                    exclude_from_all = false;
                    sources = [ old_str "main.c" ];
                  });
             Old.Yif
               {
                 cond = Old.Yexpr_is_target { ns = Old.Ns_target; name = "app" };
                 then_ =
                   Old.Ys_string
                     (Old.Ystr_toupper { string = old_str "yes"; out = old_cvar "OUT" });
                 else_ =
                   Some
                     (Old.Ys_string
                        (Old.Ystr_toupper { string = old_str "no"; out = old_cvar "OUT" }));
               };
           ])
        ~expected_value:VUnit
        ~expected_env:
          (env_of_bindings ~targets:[ target "app" ] [ "OUT", VString "YES" ]);
      check_parsed_yelu_bridge_to_yelu1 "parsed old target layer-a bridges to Yelu1"
        {|
        (
          add_exe Target app "main.c";
          if target Target app then
            ( string_toupper "yes" ~out:OUT )
          else
            ( string_toupper "no" ~out:OUT )
        )
        |}
        ~expected_value:VUnit
        ~expected_env:
          (env_of_bindings ~targets:[ target "app" ] [ "OUT", VString "YES" ]);
      check_yelu_cmake_bridge_to_yelu1 "old target add_library bridges to Yelu1"
        (Old.Ys_target
           (Old.Ytgt_add_library
              {
                name = Old.Yexpr_name { ns = Old.Ns_target; name = "core" };
                type_ = Some Yelu_langs.Lang_cmake.Lib_static;
                exclude_from_all = false;
                sources = [ old_str "core.c" ];
              }))
        ~expected_value:VUnit
        ~expected_env:
          (env_of_bindings
             ~targets:[ target "core" ~kind:(TargetLibrary (Some "STATIC")) ]
             []);
      check_parsed_yelu_bridge_to_yelu1 "parsed old target add_library bridges to Yelu1"
        {|
        ( add_lib Target core "core.c" )
        |}
        ~expected_value:VUnit
        ~expected_env:
          (env_of_bindings
             ~targets:[ target "core" ~kind:(TargetLibrary None) ]
             []);
      check_yelu_cmake_bridge_to_yelu1 "old target sources bridge to Yelu1"
        (Old.Ystmt_list
           [
             Old.Ys_target
               (Old.Ytgt_add_executable
                  {
                    name = Old.Yexpr_name { ns = Old.Ns_target; name = "app" };
                    exclude_from_all = false;
                    sources = [ old_str "main.c" ];
                  });
             Old.Ys_target
               (Old.Ytgt_sources
                  {
                    target = Old.Yexpr_name { ns = Old.Ns_target; name = "app" };
                    items =
                      [
                        { kind = Yelu_langs.Lang_cmake.Private; items = [ old_str "extra.c" ] };
                        { kind = Yelu_langs.Lang_cmake.Public; items = [ old_str "api.c" ] };
                      ];
                  });
           ])
        ~expected_value:VUnit
        ~expected_env:
          (env_of_bindings
             ~targets:
               [
                 target "app"
                   ~sources:
                     [
                       { visibility = "PRIVATE"; source = "extra.c" };
                       { visibility = "PUBLIC"; source = "api.c" };
                     ];
               ]
             []);
      check_parsed_yelu_bridge_to_yelu1 "parsed old target sources bridge to Yelu1"
        {|
        (
          add_exe Target app "main.c";
          target_sources Target app PRIVATE "extra.c" PUBLIC "api.c"
        )
        |}
        ~expected_value:VUnit
        ~expected_env:
          (env_of_bindings
             ~targets:
               [
                 target "app"
                   ~sources:
                     [
                       { visibility = "PRIVATE"; source = "extra.c" };
                       { visibility = "PUBLIC"; source = "api.c" };
                     ];
               ]
             []);
      check_yelu_cmake_bridge_to_yelu1 "old target link libraries bridge to Yelu1"
        (Old.Ystmt_list
           [
             Old.Ys_target
               (Old.Ytgt_add_executable
                  {
                    name = Old.Yexpr_name { ns = Old.Ns_target; name = "app" };
                    exclude_from_all = false;
                    sources = [ old_str "main.c" ];
                  });
             Old.Ys_target
               (Old.Ytgt_link_libraries
                  {
                    targets = [ Old.Yexpr_name { ns = Old.Ns_target; name = "app" } ];
                    items =
                      [
                        { kind = Yelu_langs.Lang_cmake.Private; items = [ old_str "m" ] };
                        { kind = Yelu_langs.Lang_cmake.Public; items = [ old_str "dep" ] };
                      ];
                  });
           ])
        ~expected_value:VUnit
        ~expected_env:
          (env_of_bindings
             ~targets:
               [
                 target "app"
                   ~link_libraries:
                     [
                       { visibility = "PRIVATE"; item = "m" };
                       { visibility = "PUBLIC"; item = "dep" };
                     ];
               ]
             []);
      check_parsed_yelu_bridge_to_yelu1 "parsed old target link libraries bridge to Yelu1"
        {|
        (
          add_exe Target app "main.c";
          link_lib Target app PRIVATE "m" PUBLIC "dep"
        )
        |}
        ~expected_value:VUnit
        ~expected_env:
          (env_of_bindings
             ~targets:
               [
                 target "app"
                   ~link_libraries:
                     [
                       { visibility = "PRIVATE"; item = "m" };
                       { visibility = "PUBLIC"; item = "dep" };
                     ];
               ]
             []);
      check_yelu_cmake_bridge_to_yelu1 "old target include directories bridge to Yelu1"
        (Old.Ystmt_list
           [
             Old.Ys_target
               (Old.Ytgt_add_executable
                  {
                    name = Old.Yexpr_name { ns = Old.Ns_target; name = "app" };
                    exclude_from_all = false;
                    sources = [ old_str "main.c" ];
                  });
             Old.Ys_target
               (Old.Ytgt_include_directories
                  {
                    target = Old.Yexpr_name { ns = Old.Ns_target; name = "app" };
                    before = false;
                    system = false;
                    items =
                      [
                        { kind = Yelu_langs.Lang_cmake.Private; items = [ old_str "include" ] };
                        { kind = Yelu_langs.Lang_cmake.Interface; items = [ old_str "iface" ] };
                      ];
                  });
           ])
        ~expected_value:VUnit
        ~expected_env:
          (env_of_bindings
             ~targets:
               [
                 target "app"
                   ~include_directories:
                     [
                       { visibility = "PRIVATE"; dir = "include" };
                       { visibility = "INTERFACE"; dir = "iface" };
                     ];
               ]
             []);
      check_parsed_yelu_bridge_to_yelu1 "parsed old target include directories bridge to Yelu1"
        {|
        (
          add_exe Target app "main.c";
          include_dirs Target app PRIVATE "include" INTERFACE "iface"
        )
        |}
        ~expected_value:VUnit
        ~expected_env:
          (env_of_bindings
             ~targets:
               [
                 target "app"
                   ~include_directories:
                     [
                       { visibility = "PRIVATE"; dir = "include" };
                       { visibility = "INTERFACE"; dir = "iface" };
                 ];
             ]
             []);
      check_yelu_cmake_bridge_to_yelu1 "old target compile definitions bridge to Yelu1"
        (Old.Ystmt_list
           [
             Old.Ys_target
               (Old.Ytgt_add_executable
                  {
                    name = Old.Yexpr_name { ns = Old.Ns_target; name = "app" };
                    exclude_from_all = false;
                    sources = [ old_str "main.c" ];
                  });
             Old.Ys_target
               (Old.Ytgt_compile_definitions
                  {
                    target = Old.Yexpr_name { ns = Old.Ns_target; name = "app" };
                    items =
                      [
                        { kind = Yelu_langs.Lang_cmake.Private; items = [ old_str "USE_PRIVATE" ] };
                        { kind = Yelu_langs.Lang_cmake.Public; items = [ old_str "USE_PUBLIC" ] };
                      ];
                  });
           ])
        ~expected_value:VUnit
        ~expected_env:
          (env_of_bindings
             ~targets:
               [
                 target "app"
                   ~compile_definitions:
                     [
                       { visibility = "PRIVATE"; definition = "USE_PRIVATE" };
                       { visibility = "PUBLIC"; definition = "USE_PUBLIC" };
                     ];
               ]
             []);
      check_yelu_cmake_bridge_to_yelu1 "old target compile options bridge to Yelu1"
        (Old.Ystmt_list
           [
             Old.Ys_target
               (Old.Ytgt_add_executable
                  {
                    name = Old.Yexpr_name { ns = Old.Ns_target; name = "app" };
                    exclude_from_all = false;
                    sources = [ old_str "main.c" ];
                  });
             Old.Ys_target
               (Old.Ytgt_compile_options
                  {
                    target = Old.Yexpr_name { ns = Old.Ns_target; name = "app" };
                    before = false;
                    items =
                      [
                        { kind = Yelu_langs.Lang_cmake.Private; items = [ old_str "-Wall" ] };
                        { kind = Yelu_langs.Lang_cmake.Public; items = [ old_str "-O2" ] };
                      ];
                  });
           ])
        ~expected_value:VUnit
        ~expected_env:
          (env_of_bindings
             ~targets:
               [
                 target "app"
                   ~compile_options:
                     [
                       { visibility = "PRIVATE"; option_ = "-Wall" };
                       { visibility = "PUBLIC"; option_ = "-O2" };
                     ];
               ]
             []);
      check_parsed_yelu_bridge_to_yelu1 "parsed old target compile definitions bridge to Yelu1"
        {|
        (
          add_exe Target app "main.c";
          compile_defs Target app PRIVATE "USE_PRIVATE" PUBLIC "USE_PUBLIC"
        )
        |}
        ~expected_value:VUnit
        ~expected_env:
          (env_of_bindings
             ~targets:
               [
                 target "app"
                   ~compile_definitions:
                     [
                       { visibility = "PRIVATE"; definition = "USE_PRIVATE" };
                       { visibility = "PUBLIC"; definition = "USE_PUBLIC" };
                     ];
               ]
             []);
      check_parsed_yelu_bridge_to_yelu1 "parsed old target compile options bridge to Yelu1"
        {|
        (
          add_exe Target app "main.c";
          compile_opts Target app PRIVATE "-Wall" PUBLIC "-O2"
        )
        |}
        ~expected_value:VUnit
        ~expected_env:
          (env_of_bindings
             ~targets:
               [
                 target "app"
                   ~compile_options:
                     [
                       { visibility = "PRIVATE"; option_ = "-Wall" };
                       { visibility = "PUBLIC"; option_ = "-O2" };
                     ];
               ]
             []);
      check_yelu_cmake_bridge_to_yelu1 "old target link options bridge to Yelu1"
        (Old.Ystmt_list
           [
             Old.Ys_target
               (Old.Ytgt_add_executable
                  {
                    name = Old.Yexpr_name { ns = Old.Ns_target; name = "app" };
                    exclude_from_all = false;
                    sources = [ old_str "main.c" ];
                  });
             Old.Ys_target
               (Old.Ytgt_link_options
                  {
                    target = Old.Yexpr_name { ns = Old.Ns_target; name = "app" };
                    before = false;
                    items =
                      [
                        { kind = Yelu_langs.Lang_cmake.Private; items = [ old_str "-Wl,--gc-sections" ] };
                        { kind = Yelu_langs.Lang_cmake.Public; items = [ old_str "-Wl,--as-needed" ] };
                      ];
                  });
           ])
        ~expected_value:VUnit
        ~expected_env:
          (env_of_bindings
             ~targets:
               [
                 target "app"
                   ~link_options:
                     [
                       { visibility = "PRIVATE"; link_option = "-Wl,--gc-sections" };
                       { visibility = "PUBLIC"; link_option = "-Wl,--as-needed" };
                   ];
               ]
             []);
      check_parsed_yelu_bridge_to_yelu1 "parsed old target link options bridge to Yelu1"
        {|
        (
          add_exe Target app "main.c";
          link_opts Target app PRIVATE "-Wl,--gc-sections" PUBLIC "-Wl,--as-needed"
        )
        |}
        ~expected_value:VUnit
        ~expected_env:
          (env_of_bindings
             ~targets:
               [
                 target "app"
                   ~link_options:
                     [
                       { visibility = "PRIVATE"; link_option = "-Wl,--gc-sections" };
                       { visibility = "PUBLIC"; link_option = "-Wl,--as-needed" };
                     ];
               ]
             []);
      check_yelu_cmake_bridge_to_yelu1 "old target link directories bridge to Yelu1"
        (Old.Ystmt_list
           [
             Old.Ys_target
               (Old.Ytgt_add_executable
                  {
                    name = Old.Yexpr_name { ns = Old.Ns_target; name = "app" };
                    exclude_from_all = false;
                    sources = [ old_str "main.c" ];
                  });
             Old.Ys_target
               (Old.Ytgt_link_directories
                  {
                    target = Old.Yexpr_name { ns = Old.Ns_target; name = "app" };
                    before = false;
                    items =
                      [
                        { kind = Yelu_langs.Lang_cmake.Private; items = [ old_str "/opt/lib" ] };
                        { kind = Yelu_langs.Lang_cmake.Interface; items = [ old_str "/usr/local/lib" ] };
                      ];
                  });
           ])
        ~expected_value:VUnit
        ~expected_env:
          (env_of_bindings
             ~targets:
               [
                 target "app"
                   ~link_directories:
                     [
                       { visibility = "PRIVATE"; link_directory = "/opt/lib" };
                       { visibility = "INTERFACE"; link_directory = "/usr/local/lib" };
                   ];
               ]
             []);
      check_parsed_yelu_bridge_to_yelu1 "parsed old target link directories bridge to Yelu1"
        {|
        (
          add_exe Target app "main.c";
          link_dirs Target app PRIVATE "/opt/lib" INTERFACE "/usr/local/lib"
        )
        |}
        ~expected_value:VUnit
        ~expected_env:
          (env_of_bindings
             ~targets:
               [
                 target "app"
                   ~link_directories:
                     [
                       { visibility = "PRIVATE"; link_directory = "/opt/lib" };
                       { visibility = "INTERFACE"; link_directory = "/usr/local/lib" };
                     ];
               ]
             []);
      check_yelu_cmake_bridge_to_yelu1 "old custom target bridge to Yelu1"
        (Old.Ys_target
           (Old.Ytgt_add_custom_target
              {
                name = "hello";
                all = false;
                commands =
                  [ { Yelu_langs.Lang_cmake.command = "cmake"; args = [ "-E"; "echo"; "HELLO" ] } ];
                depends = [ old_str "input.txt" ];
                comment = Some "hello target";
              }))
        ~expected_value:VUnit
        ~expected_env:
          (env_of_bindings
             ~custom_targets:
               [
                 {
                   name = "hello";
                   all = false;
                   commands = [ { command = "cmake"; args = [ "-E"; "echo"; "HELLO" ] } ];
                   depends = [ "input.txt" ];
                   comment = Some "hello target";
                 };
               ]
             []);
      check_parsed_yelu_bridge_to_yelu1 "parsed old custom target bridge to Yelu1"
        "( add_custom_target \"hello\" )"
        ~expected_value:VUnit
        ~expected_env:
          (env_of_bindings
             ~custom_targets:
               [
                 {
                   name = "hello";
                   all = false;
                   commands = [];
                   depends = [];
                   comment = None;
                 };
               ]
             []);
      check_yelu_cmake_bridge_to_yelu1 "old custom command bridge to Yelu1"
        (Old.Ys_target
           (Old.Ytgt_add_custom_command
              {
                outputs = [ old_str "generated.txt" ];
                commands =
                  [ { Yelu_langs.Lang_cmake.command = "cmake";
                      args = [ "-E"; "touch"; "generated.txt" ] } ];
                depends = [ old_str "input.txt" ];
                verbatim = true;
                comment = Some "generating generated.txt";
              }))
        ~expected_value:VUnit
        ~expected_env:
          (env_of_bindings
             ~custom_commands:
               [
                 {
                   outputs = [ "generated.txt" ];
                   commands = [ { command = "cmake"; args = [ "-E"; "touch"; "generated.txt" ] } ];
                   depends = [ "input.txt" ];
                   comment = Some "generating generated.txt";
                   verbatim = true;
                 };
               ]
             []);
      check_yelu_cmake_bridge_to_yelu1 "old install targets and files bridge to Yelu1"
        (Old.Ystmt_list
           [
             Old.Ys_target
               (Old.Ytgt_add_executable
                  {
                    name = Old.Yexpr_name { ns = Old.Ns_target; name = "app" };
                    exclude_from_all = false;
                    sources = [ old_str "main.c" ];
                  });
             Old.Ys_install
               (Old.Yinstall_targets
                  {
                    targets = [ Old.Yexpr_name { ns = Old.Ns_target; name = "app" } ];
                    destination = old_str "bin";
                    export = None;
                  });
             Old.Ys_install
               (Old.Yinstall_files
                  { files = [ old_str "include/app.h" ]; destination = old_str "include" });
           ])
        ~expected_value:VUnit
        ~expected_env:
          (env_of_bindings
             ~targets:[ target "app" ]
             ~install_rules:
               [
                 InstallTargets { targets = [ "app" ]; destination = "bin"; export = None };
                 InstallFiles { files = [ "include/app.h" ]; destination = "include" };
               ]
             []);
      check_parsed_yelu_bridge_to_yelu1 "parsed old install targets and files bridge to Yelu1"
        {|
        (
          add_exe Target app "main.c";
          install_targets "bin" { Target app };
          install_files "include" { "include/app.h" }
        )
        |}
        ~expected_value:VUnit
        ~expected_env:
          (env_of_bindings
             ~targets:[ target "app" ]
             ~install_rules:
               [
                 InstallTargets { targets = [ "app" ]; destination = "bin"; export = None };
                 InstallFiles { files = [ "include/app.h" ]; destination = "include" };
               ]
             []);
      check_yelu_cmake_bridge_to_yelu1 "old cmake_op project + min_required + message bridge to Yelu1"
        (Old.Ystmt_list
           [
             Old.Ys_cmake
               (Old.Ycmake_minimum_required
                  { min = { major = 3; minor = 20; patch = "" }; max = None });
             Old.Ys_cmake
               (Old.Ycmake_project
                  { name = "demo"; version = None; languages = [ Lang_c ] });
             Old.Ys_cmake
               (Old.Ycmake_message { mode = Mm_status; texts = [ "hello" ] });
           ])
        ~expected_value:VUnit
        ~expected_env:
          (env_of_bindings
             ~project:{ name = "demo"; languages = [ "C" ]; version = None }
             ~cmake_min_version:"3.20"
             ~messages:[ { mode = "STATUS"; texts = [ "hello" ] } ]
             []);
      check_yelu_cmake_bridge_to_yelu1 "old dir add_subdirectory bridge to Yelu1"
        (Old.Ystmt_list
           [
             Old.Ys_dir
               (Old.Ydir_add_subdirectory
                  { source_dir = old_str "subdir_a" });
             Old.Ys_dir
               (Old.Ydir_add_subdirectory
                  { source_dir = old_str "subdir_b" });
           ])
        ~expected_value:VUnit
        ~expected_env:
          (env_of_bindings
             ~subdirectories:[ "subdir_a"; "subdir_b" ]
             []);
      check_yelu_cmake_bridge_to_yelu1 "old test enable + add_test bridge to Yelu1"
        (Old.Ystmt_list
           [
             Old.Ys_test Old.Ytest_enable_testing;
             Old.Ys_test
               (Old.Ytest_add_test
                  { name = old_str "smoke";
                    command = old_str "/bin/true";
                    args = [ old_str "--quiet" ] });
           ])
        ~expected_value:VUnit
        ~expected_env:
          (env_of_bindings
             ~testing_enabled:true
             ~tests:[ { name = "smoke"; command = "/bin/true"; args = [ "--quiet" ] } ]
             []);
      check_yelu_cmake_bridge_to_yelu1 "old Ylet bridges to ELet with rest as body"
        (Old.Ystmt_list
           [
             Old.Ylet { var = Old.Yvar "msg"; value = old_str "scoped" };
             Old.Ys_string
               (Old.Ystr_toupper { string = old_var "msg"; out = old_cvar "OUT" });
           ])
        ~expected_value:VUnit
        ~expected_env:
          (* `msg` is gone after the body — proves it's an ELet, not an
             ESetVar that would persist. *)
          (env_of_bindings [ "OUT", VString "SCOPED" ]);
      check_yelu_cmake_bridge_to_yelu1 "old find_package bridge to Yelu1"
        (Old.Ys_find
           (Old.Yfind_package
              { name = "Threads";
                version = None;
                exact = false;
                quiet = false;
                config_mode = false;
                required = false;
                components = [];
                optional_components = [] }))
        ~expected_value:VUnit
        ~expected_env:
          (env_of_bindings
             ~find_packages:[ { package_name = "Threads"; required = false } ]
             []);
      check_yelu_cmake_bridge_to_yelu1 "old try_compile bridge to Yelu1"
        (Old.Ys_try
           (Old.Ytry_compile
              { result_var = old_cvar "HAS_C";
                sources = [ old_str "src/probe.c" ];
                compile_definitions = [];
                link_libraries = [];
                link_options = [];
                output_variable = None;
                no_cache = false;
                c_standard = None;
                cxx_standard = None }))
        ~expected_value:VUnit
        ~expected_env:
          (env_of_bindings
             ~try_compiles:[ { result_var = "HAS_C"; sources = [ "src/probe.c" ] } ]
             [ "HAS_C", VBool true ]);
      check_yelu_cmake_bridge_to_yelu1 "old property set/get target bridge to Yelu1"
        (Old.Ystmt_list
           [
             Old.Ys_target
               (Old.Ytgt_add_executable
                  {
                    name = Old.Yexpr_name { ns = Old.Ns_target; name = "app" };
                    exclude_from_all = false;
                    sources = [ old_str "main.c" ];
                  });
             Old.Ys_property
               (Old.Yprop_set_target
                  {
                    target = Old.Yexpr_name { ns = Old.Ns_target; name = "app" };
                    properties = [ "OUTPUT_NAME", old_str "myapp" ];
                  });
             Old.Ys_property
               (Old.Yprop_get_target
                  { var = old_cvar "OUT"; target = "app"; property = "OUTPUT_NAME" });
           ])
        ~expected_value:VUnit
        ~expected_env:
          (env_of_bindings
             ~targets:[ target "app" ]
             ~target_properties:[ "app", "OUTPUT_NAME", "myapp" ]
             [ "OUT", VString "myapp" ]);
    ] )

(* Step1 bridge: drive a real production yelu_cmake AST (the tutorial v1 step1
   program) through the tiny bridge and verify it emits CMakeLists.txt without
   any "unsupported in Yelu1 bridge" failures. Stricter checks (env equality,
   output equivalence) come later as the bridge matures. *)
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
          Alcotest.(check bool) "contains add_executable" true
            (String.is_substring cmake_text ~substring:"add_executable(");
          Alcotest.(check bool) "contains configure_file" true
            (String.is_substring cmake_text ~substring:"configure_file(");
          Alcotest.(check bool) "contains target_include_directories" true
            (String.is_substring cmake_text
               ~substring:"target_include_directories("));
    ] )

(* Phase-2a tests for ELet emit-time resolution. ELet binds a name; EVar
   references in expression positions inside the body get the bound value
   substituted at emit time, instead of emitting `${name}` (which would be
   an unbound cmake runtime variable). Surface target-name fields are
   still typed `string` in this phase, so let-bound target references in
   target-name positions still emit unresolved — that's phase-2b. *)
let let_emit_resolve =
  ( "let_emit_resolve",
    [
      Alcotest.test_case "ELet substitutes EVar in ESetVar value position"
        `Quick
        (fun () ->
          let prog =
            ELet { var = "msg";
                   value = EString "hello";
                   body = ESetVar ("OUT", EVar "msg") }
          in
          let cmake_text =
            Yelu_langs.Yelu_tiny_cmake_emit.emit_script prog
          in
          Alcotest.(check bool)
            "emits substituted literal, not ${msg}"
            true
            (String.is_substring cmake_text ~substring:"set(OUT \"hello\")");
          Alcotest.(check bool)
            "no remaining ${msg} reference"
            false
            (String.is_substring cmake_text ~substring:"${msg}"));
      Alcotest.test_case "ELet drops the let header from emit"
        `Quick
        (fun () ->
          let prog =
            ELet { var = "msg";
                   value = EString "hello";
                   body = EUnit }
          in
          let cmake_text =
            Yelu_langs.Yelu_tiny_cmake_emit.emit_script prog
          in
          (* let header has no cmake equivalent; body is empty -> empty
             output (just the trailing newline). *)
          Alcotest.(check string) "empty body emits empty script"
            "\n" cmake_text);
      Alcotest.test_case "Inner ELet shadows outer in emit substitution"
        `Quick
        (fun () ->
          let prog =
            ELet { var = "x";
                   value = EString "outer";
                   body =
                     ESeq
                       [ ESetVar ("BEFORE", EVar "x");
                         ELet { var = "x";
                                value = EString "inner";
                                body = ESetVar ("INSIDE", EVar "x") };
                         ESetVar ("AFTER", EVar "x");
                       ] }
          in
          let cmake_text =
            Yelu_langs.Yelu_tiny_cmake_emit.emit_script prog
          in
          Alcotest.(check bool) "BEFORE sees outer"
            true (String.is_substring cmake_text ~substring:"set(BEFORE \"outer\")");
          Alcotest.(check bool) "INSIDE sees inner"
            true (String.is_substring cmake_text ~substring:"set(INSIDE \"inner\")");
          Alcotest.(check bool) "AFTER restored to outer"
            true (String.is_substring cmake_text ~substring:"set(AFTER \"outer\")"));
    ] )

let () =
  Alcotest.run "yelu_tiny_composition"
    [ yelu1_to_yelu2;
      yelu2_to_yelu1;
      yelu1_roundtrip;
      yelu_cmake_bridge;
      step1_bridge;
      let_emit_resolve;
    ]
