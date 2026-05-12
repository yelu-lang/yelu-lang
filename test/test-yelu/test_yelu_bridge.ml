open Yelu_langs.Yelu_cmake
open Yelu_test_helpers
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
      check_yelu_cmake_bridge_to_yelu1 "old target compile features bridge to Yelu1"
        (Old.Ystmt_list
           [
             Old.Ys_target
               (Old.Ytgt_add_library
                  {
                    name = Old.Yexpr_name { ns = Old.Ns_target; name = "flags" };
                    type_ = Some Yelu_langs.Lang_cmake.Lib_interface;
                    exclude_from_all = false;
                    sources = [];
                  });
             Old.Ys_target
               (Old.Ytgt_compile_features
                  {
                    target = Old.Yexpr_name { ns = Old.Ns_target; name = "flags" };
                    features =
                      [
                        { kind = Yelu_langs.Lang_cmake.Interface; feature = "cxx_std_11" };
                      ];
                  });
           ])
        ~expected_value:VUnit
        ~expected_env:
          (env_of_bindings
             ~targets:
               [
                 target "flags"
                   ~kind:(TargetLibrary (Some "INTERFACE"))
                   ~compile_features:
                     [ { visibility = "INTERFACE"; feature = "cxx_std_11" } ];
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

let () =
  Alcotest.run "yelu_tiny_bridge" [ yelu_cmake_bridge ]
