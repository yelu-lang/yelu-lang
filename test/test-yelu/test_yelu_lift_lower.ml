open Yelu_langs.Yelu_cmake
open Yelu_langs.Yelu_cmake_normal_store
open Yelu_langs.Yelu_cmake_store
open Yelu_langs.Yelu_cmake_normal_int
open Yelu_langs.Yelu_cmake_normal_list
open Yelu_langs.Yelu_cmake_list
open Yelu_langs.Yelu_cmake_path
open Yelu_langs.Yelu_cmake_normal_path
open Yelu_langs.Yelu_cmake_file
open Yelu_langs.Yelu_cmake_normal_file
open Yelu_langs.Yelu_cmake_target
open Yelu_langs.Yelu_cmake_normal_target
open Yelu_langs.Yelu_cmake_install
open Yelu_langs.Yelu_cmake_normal_install
open Yelu_langs.Yelu_cmake_string
open Yelu_langs.Yelu_cmake_normal_string
open Yelu_langs.Yelu_cmake_if
open Yelu_langs.Yelu_cmake_normal_if
open Yelu_langs.Yelu_cmake_cmake_op
open Yelu_langs.Yelu_cmake_normal_cmake_op
open Yelu_langs.Yelu_cmake_dir
open Yelu_langs.Yelu_cmake_normal_dir
open Yelu_langs.Yelu_cmake_test
open Yelu_langs.Yelu_cmake_normal_test
open Yelu_langs.Yelu_cmake_property
open Yelu_langs.Yelu_cmake_normal_property
open Yelu_langs.Yelu_cmake_find
open Yelu_langs.Yelu_cmake_normal_find
open Yelu_langs.Yelu_cmake_try
open Yelu_langs.Yelu_cmake_normal_try
open Yelu_test_helpers
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
          ECmakeListGet { list = "XS"; indices = [ 1 ]; out = "ITEM" };
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
          ECmakeAddExecutable { name = EString "app"; sources = [ EString "main.c" ] };
          ESetVar ("OUT", ECmakeTargetExists (EString "app"));
          EVar "OUT";
        ])
        ~expected_value:(VBool true)
        ~expected_env:
          (env_of_bindings
             ~targets:[ target "app" ~sources:[ { visibility = Vis_private; source = "main.c" } ] ]
             [ "OUT", VBool true ]);
      check_yelu1_to_yelu2 "library declaration"
        (ESeq [
          ECmakeAddLibrary { name = EString "core"; type_ = Some "STATIC"; sources = [ EString "core.c" ] };
          ESetVar ("OUT", ECmakeTargetExists (EString "core"));
          EVar "OUT";
        ])
        ~expected_value:(VBool true)
        ~expected_env:
          (env_of_bindings
             ~targets:[ target "core" ~kind:(TargetLibrary (Some "STATIC")) ~sources:[ { visibility = Vis_private; source = "core.c" } ] ]
             [ "OUT", VBool true ]);
      check_yelu1_to_yelu2 "target sources mutation"
        (ESeq [
          ECmakeAddExecutable { name = EString "app"; sources = [ EString "main.c" ] };
          ECmakeTargetSources { target = EString "app"; visibility = Vis_public; sources = [ EString "extra.c" ] };
          ETarget "app";
        ])
        ~expected_value:(VTarget "app")
        ~expected_env:
          (env_of_bindings
             ~targets:
               [
                 target "app"
                   ~sources:[ { visibility = Vis_private; source = "main.c" }; { visibility = Vis_public; source = "extra.c" } ];
               ]
             []);
      check_yelu1_to_yelu2 "target link libraries mutation"
        (ESeq [
          ECmakeAddExecutable { name = EString "app"; sources = [ EString "main.c" ] };
          ECmakeTargetLinkLibraries { target = EString "app"; visibility = Vis_private; items = [ EString "m" ] };
          ETarget "app";
        ])
        ~expected_value:(VTarget "app")
        ~expected_env:
          (env_of_bindings
             ~targets:
               [
                 target "app"
                   ~sources:[ { visibility = Vis_private; source = "main.c" } ]
                   ~link_libraries:[ { visibility = Vis_private; item = "m" } ];
               ]
             []);
      check_yelu1_to_yelu2 "target include directories mutation"
        (ESeq [
          ECmakeAddExecutable { name = EString "app"; sources = [ EString "main.c" ] };
          ECmakeTargetIncludeDirectories
            { target = EString "app"; visibility = Vis_public;
              before = false; system = false;
              dirs = [ EString "include" ] };
          ETarget "app";
        ])
        ~expected_value:(VTarget "app")
        ~expected_env:
          (env_of_bindings
             ~targets:
               [
                 target "app"
                   ~sources:[ { visibility = Vis_private; source = "main.c" } ]
                   ~include_directories:[ { visibility = Vis_public; dir = "include" } ];
               ]
             []);
      check_yelu1_to_yelu2 "target compile definitions mutation"
        (ESeq [
          ECmakeAddExecutable { name = EString "app"; sources = [ EString "main.c" ] };
          ECmakeTargetCompileDefinitions
            { target = EString "app"; visibility = Vis_private; definitions = [ EString "USE_FEATURE" ] };
          ETarget "app";
        ])
        ~expected_value:(VTarget "app")
        ~expected_env:
          (env_of_bindings
             ~targets:
               [
                 target "app"
                   ~sources:[ { visibility = Vis_private; source = "main.c" } ]
                   ~compile_definitions:
                     [ { visibility = Vis_private; definition = "USE_FEATURE" } ];
               ]
             []);
      check_yelu1_to_yelu2 "target compile options mutation"
        (ESeq [
          ECmakeAddExecutable { name = EString "app"; sources = [ EString "main.c" ] };
          ECmakeTargetCompileOptions
            { target = EString "app"; visibility = Vis_private;
              before = false;
              options_ = [ EString "-Wall" ] };
          ETarget "app";
        ])
        ~expected_value:(VTarget "app")
        ~expected_env:
          (env_of_bindings
             ~targets:
               [
	                 target "app"
	                   ~sources:[ { visibility = Vis_private; source = "main.c" } ]
	                   ~compile_options:
	                     [ { visibility = Vis_private; option_ = "-Wall" } ];
	               ]
	             []);
      check_yelu1_to_yelu2 "target compile features mutation"
        (ESeq [
          ECmakeAddLibrary
            { name = EString "flags"; type_ = Some "INTERFACE"; sources = [] };
          ECmakeTargetCompileFeatures
            { target = EString "flags"; visibility = Vis_interface; features = [ EString "cxx_std_11" ] };
          ETarget "flags";
        ])
        ~expected_value:(VTarget "flags")
        ~expected_env:
          (env_of_bindings
             ~targets:
               [
                 target "flags"
                   ~kind:(TargetLibrary (Some "INTERFACE"))
                   ~compile_features:
                     [ { visibility = Vis_interface; feature = "cxx_std_11" } ];
               ]
             []);
      check_yelu1_to_yelu2 "target link options mutation"
        (ESeq [
          ECmakeAddExecutable { name = EString "app"; sources = [ EString "main.c" ] };
          ECmakeTargetLinkOptions
            { target = EString "app"; visibility = Vis_private;
              before = false;
              options_ = [ EString "-Wl,--as-needed" ] };
          ETarget "app";
        ])
        ~expected_value:(VTarget "app")
        ~expected_env:
          (env_of_bindings
             ~targets:
               [
                 target "app"
                   ~sources:[ { visibility = Vis_private; source = "main.c" } ]
                   ~link_options:
                     [ { visibility = Vis_private; link_option = "-Wl,--as-needed" } ];
               ]
             []);
      check_yelu1_to_yelu2 "target link directories mutation"
        (ESeq [
          ECmakeAddExecutable { name = EString "app"; sources = [ EString "main.c" ] };
          ECmakeTargetLinkDirectories
            { target = EString "app"; visibility = Vis_public;
              before = false;
              dirs = [ EString "/opt/lib" ] };
          ETarget "app";
        ])
        ~expected_value:(VTarget "app")
        ~expected_env:
          (env_of_bindings
             ~targets:
               [
                 target "app"
                   ~sources:[ { visibility = Vis_private; source = "main.c" } ]
                   ~link_directories:
                     [ { visibility = Vis_public; link_directory = "/opt/lib" } ];
               ]
             []);
      check_yelu1_to_yelu2 "custom target declaration"
        (ECmakeAddCustomTarget
           {
             name = EString "hello";
             all = false;
             commands = [ { command = "cmake"; args = [ "-E"; "echo"; "HELLO" ] } ];
             depends = [ EString "input.txt" ];
             comment = Some "hello target";
             sources = [];
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
                   sources = [];
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
          ECmakeAddExecutable { name = EString "app"; sources = [ EString "main.c" ] };
          ECmakeInstallTargets
            { targets = [ EString "app" ]; destination = Some (EString "bin"); export = None; component = None; artifact_clauses = [] };
          ECmakeInstallFiles
            { files = [ EString "include/app.h" ]; destination = EString "include"; component = None };
        ])
        ~expected_value:VUnit
        ~expected_env:
          (env_of_bindings
             ~targets:[ target "app" ~sources:[ { visibility = Vis_private; source = "main.c" } ] ]
             ~install_rules:
               [
                 InstallTargets { targets = [ "app" ]; destination = Some "bin"; export = None; component = None; artifact_clauses = [] };
                 InstallFiles { files = [ "include/app.h" ]; destination = "include"; component = None };
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
          ECmakeAddExecutable { name = EString "app"; sources = [ EString "main.c" ] };
          ECmakeSetTargetProperty
            { target = EString "app"; property = "OUTPUT_NAME"; value = EString "myapp" };
          ECmakeGetTargetProperty
            { var = "OUT"; target = EString "app"; property = "OUTPUT_NAME" };
        ])
        ~expected_value:VUnit
        ~expected_env:
          (env_of_bindings
             ~targets:[ target "app" ~sources:[ { visibility = Vis_private; source = "main.c" } ] ]
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
      (* Use a non-whitelisted package name so this test stays focused
         on the bookkeeping shape — "Threads" triggers the
         assumed_found_packages cache write (see yelu_cmake_find.ml),
         which mixes two concerns into one assertion. *)
      check_yelu1_to_yelu2 "find_package declaration"
        (ECmakeFindPackage
           { package_name = "MyTestPkg"; required = false;
             version = None; exact = false; quiet = false; config_mode = false;
             components = []; optional_components = [] })
        ~expected_value:VUnit
        ~expected_env:
          (env_of_bindings
             ~find_packages:[ { package_name = "MyTestPkg"; required = false } ]
             []);
      (* try_compile stub now writes FALSE (safe direction — assumed
         failed compile, matches real cmake's behavior on this system
         for compile_result_unused). Also writes the cache_var
         "FALSE" to mirror real cmake's INTERNAL cache type. The test
         here only checks the local var; cache_vars assertion would
         need an env_of_bindings extension. *)
      check_yelu1_to_yelu2 "try_compile records and stubs result_var"
        (ECmakeTryCompile
           { result_var = "HAS_C"; sources = [ EString "src/probe.c" ] })
        ~expected_value:VUnit
        ~expected_env:
          (let base =
             env_of_bindings
               ~try_compiles:[ { result_var = "HAS_C"; sources = [ "src/probe.c" ] } ]
               [ "HAS_C", VBool false ]
           in
           set_cache_var base ~key:"HAS_C" ~data:(VString "FALSE"));
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
             ~targets:[ target "app" ~sources:[ { visibility = Vis_private; source = "main.c" } ] ]
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
             ~targets:[ target "core" ~kind:(TargetLibrary (Some "STATIC")) ~sources:[ { visibility = Vis_private; source = "core.c" } ] ]
             [
               "CORE", VTarget "core";
               "OUT", VBool true;
             ]);
      check_yelu2_to_yelu1 "target sources lowers to cmake surface"
        (ESeq [
          ESetVar
            ("APP", EExecutable { name = EString "app"; sources = [ EString "main.c" ] });
          ETargetAddSources { target = ETarget "app"; visibility = Vis_interface; sources = [ EString "extra.c" ] };
        ])
        ~expected_value:(VTarget "app")
        ~expected_env:
          (env_of_bindings
             ~targets:
               [
                 target "app"
                   ~sources:[ { visibility = Vis_private; source = "main.c" }; { visibility = Vis_interface; source = "extra.c" } ];
               ]
             [
               "APP", VTarget "app";
             ]);
      check_yelu2_to_yelu1 "target link libraries lowers to cmake surface"
        (ESeq [
          ESetVar
            ("APP", EExecutable { name = EString "app"; sources = [ EString "main.c" ] });
          ETargetLinkLibraries { target = ETarget "app"; visibility = Vis_private; items = [ EString "m" ] };
        ])
        ~expected_value:(VTarget "app")
        ~expected_env:
          (env_of_bindings
             ~targets:
               [
                 target "app"
                   ~sources:[ { visibility = Vis_private; source = "main.c" } ]
                   ~link_libraries:[ { visibility = Vis_private; item = "m" } ];
               ]
             [
               "APP", VTarget "app";
             ]);
      check_yelu2_to_yelu1 "target include directories lowers to cmake surface"
        (ESeq [
          ESetVar
            ("APP", EExecutable { name = EString "app"; sources = [ EString "main.c" ] });
          ETargetIncludeDirectories { target = ETarget "app"; visibility = Vis_interface; dirs = [ EString "iface" ] };
        ])
        ~expected_value:(VTarget "app")
        ~expected_env:
          (env_of_bindings
             ~targets:
               [
                 target "app"
                   ~sources:[ { visibility = Vis_private; source = "main.c" } ]
                   ~include_directories:[ { visibility = Vis_interface; dir = "iface" } ];
               ]
             [
               "APP", VTarget "app";
             ]);
      check_yelu2_to_yelu1 "target compile definitions lowers to cmake surface"
        (ESeq [
          ESetVar
            ("APP", EExecutable { name = EString "app"; sources = [ EString "main.c" ] });
          ETargetCompileDefinitions
            { target = ETarget "app"; visibility = Vis_public; definitions = [ EString "USE_FEATURE" ] };
        ])
        ~expected_value:(VTarget "app")
        ~expected_env:
          (env_of_bindings
             ~targets:
               [
                 target "app"
                   ~sources:[ { visibility = Vis_private; source = "main.c" } ]
                   ~compile_definitions:
                     [ { visibility = Vis_public; definition = "USE_FEATURE" } ];
               ]
             [
               "APP", VTarget "app";
             ]);
      check_yelu2_to_yelu1 "target compile options lowers to cmake surface"
        (ESeq [
          ESetVar
            ("APP", EExecutable { name = EString "app"; sources = [ EString "main.c" ] });
          ETargetCompileOptions
            { target = ETarget "app"; visibility = Vis_public; options_ = [ EString "-O2" ] };
        ])
        ~expected_value:(VTarget "app")
        ~expected_env:
          (env_of_bindings
             ~targets:
               [
	                 target "app"
	                   ~sources:[ { visibility = Vis_private; source = "main.c" } ]
	                   ~compile_options:
	                     [ { visibility = Vis_public; option_ = "-O2" } ];
	               ]
	             [
	               "APP", VTarget "app";
	             ]);
      check_yelu2_to_yelu1 "target compile features lowers to cmake surface"
        (ESeq [
          ESetVar
            ("FLAGS", ELibrary { name = EString "flags"; type_ = Some "INTERFACE"; sources = [] });
          ETargetCompileFeatures
            { target = ETarget "flags"; visibility = Vis_interface; features = [ EString "cxx_std_11" ] };
        ])
        ~expected_value:(VTarget "flags")
        ~expected_env:
          (env_of_bindings
             ~targets:
               [
                 target "flags"
                   ~kind:(TargetLibrary (Some "INTERFACE"))
                   ~compile_features:
                     [ { visibility = Vis_interface; feature = "cxx_std_11" } ];
               ]
             [
               "FLAGS", VTarget "flags";
             ]);
      check_yelu2_to_yelu1 "target link options lowers to cmake surface"
        (ESeq [
          ESetVar
            ("APP", EExecutable { name = EString "app"; sources = [ EString "main.c" ] });
          ETargetLinkOptions
            { target = ETarget "app"; visibility = Vis_private; options_ = [ EString "-Wl,--gc-sections" ] };
        ])
        ~expected_value:(VTarget "app")
        ~expected_env:
          (env_of_bindings
             ~targets:
               [
                 target "app"
                   ~sources:[ { visibility = Vis_private; source = "main.c" } ]
                   ~link_options:
                     [ { visibility = Vis_private; link_option = "-Wl,--gc-sections" } ];
               ]
             [
               "APP", VTarget "app";
             ]);
      check_yelu2_to_yelu1 "target link directories lowers to cmake surface"
        (ESeq [
          ESetVar
            ("APP", EExecutable { name = EString "app"; sources = [ EString "main.c" ] });
          ETargetLinkDirectories
            { target = ETarget "app"; visibility = Vis_interface; dirs = [ EString "/usr/local/lib" ] };
        ])
        ~expected_value:(VTarget "app")
        ~expected_env:
          (env_of_bindings
             ~targets:
               [
                 target "app"
                   ~sources:[ { visibility = Vis_private; source = "main.c" } ]
                   ~link_directories:
                     [ { visibility = Vis_interface; link_directory = "/usr/local/lib" } ];
               ]
             [
               "APP", VTarget "app";
             ]);
      check_yelu2_to_yelu1 "custom target lowers to cmake surface"
        (ECustomTarget
           {
             name = EString "hello";
             all = false;
             commands = [ { command = "cmake"; args = [ "-E"; "echo"; "HELLO" ] } ];
             depends = [ EString "input.txt" ];
             comment = None;
             sources = [];
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
                   sources = [];
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
            { targets = [ ETarget "app" ]; destination = Some (EString "bin"); export = None };
          EInstallFiles
            { files = [ EString "include/app.h" ]; destination = EString "include" };
        ])
        ~expected_value:VUnit
        ~expected_env:
          (env_of_bindings
             ~targets:[ target "app" ~sources:[ { visibility = Vis_private; source = "main.c" } ] ]
             ~install_rules:
               [
                 InstallTargets { targets = [ "app" ]; destination = Some "bin"; export = None; component = None; artifact_clauses = [] };
                 InstallFiles { files = [ "include/app.h" ]; destination = "include"; component = None };
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
      (* Non-whitelisted package — "Threads" would also write the
         FIND_PACKAGE_MESSAGE_DETAILS cache entry, mixing two concerns. *)
      check_yelu2_to_yelu1 "find_package lower to cmake"
        (EFindPackage { package_name = "MyTestPkg"; required = true })
        ~expected_value:VUnit
        ~expected_env:
          (env_of_bindings
             ~find_packages:[ { package_name = "MyTestPkg"; required = true } ]
             []);
      (* try_compile stub: result=FALSE (safe direction). Mirrors
         yc-side behavior — see the yc test sibling above. *)
      check_yelu2_to_yelu1 "try_compile lower to cmake"
        (ETryCompile
           { result_var = "HAS_C"; sources = [ EString "src/probe.c" ] })
        ~expected_value:VUnit
        ~expected_env:
          (let base =
             env_of_bindings
               ~try_compiles:[ { result_var = "HAS_C"; sources = [ "src/probe.c" ] } ]
               [ "HAS_C", VBool false ]
           in
           set_cache_var base ~key:"HAS_C" ~data:(VString "FALSE"));
      check_yelu2_to_yelu1 "property set/get lower to cmake"
        (ESeq [
          ESetVar
            ("APP", EExecutable { name = EString "app"; sources = [ EString "main.c" ] });
          ESetTargetProperty
            { target = EString "app"; property = "OUTPUT_NAME"; value = EString "myapp" };
          EGetTargetProperty
            { var = "OUT"; target = EString "app"; property = "OUTPUT_NAME" };
        ])
        ~expected_value:VUnit
        ~expected_env:
          (env_of_bindings
             ~targets:[ target "app" ~sources:[ { visibility = Vis_private; source = "main.c" } ] ]
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

let () =
  Alcotest.run "yelu_tiny_lift_lower"
    [ yelu1_to_yelu2; yelu2_to_yelu1; yelu1_roundtrip ]
