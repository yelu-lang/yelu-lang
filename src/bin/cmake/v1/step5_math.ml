open Yelu_langs.Lang_cmake_utils
open Yelu_langs.Lang_cmake_pp

let cmd =
  cmd_of_list
    [
      add_library "MathFunctions" ~sources:[ "MathFunctions.cxx" ];
      target_include_directories "MathFunctions"
        [ target_def ~kind:"INTERFACE" [ str_ "${CMAKE_CURRENT_SOURCE_DIR}" ] ];
      option_ ~value:(bool_ true)
        ~msg:"Use tutorial provided math implementation" "USE_MYMATH";
      ifthen ["USE_MYMATH"]
        (cmd_of_list
           [
             target_compile_definitions "MathFunctions"
               [ target_def ~kind:"PRIVATE" [ quote "USE_MYMATH" ] ];
             add_library "SqrtLibrary" ~type_:"STATIC"
               ~sources:[ "mysqrt.cxx" ];
             target_link_libraries [ "SqrtLibrary" ]
               [ target_def ~kind:"PUBLIC" [ str_ "tutorial_compiler_flags" ] ];
             target_link_libraries [ "MathFunctions" ]
               [ target_def ~kind:"PRIVATE" [ str_ "SqrtLibrary" ] ];
           ]);
      target_link_libraries [ "MathFunctions" ]
        [ target_def ~kind:"PUBLIC" [ str_ "tutorial_compiler_flags" ] ];
      set "installable_libs"
        [ str_ "MathFunctions"; str_ "tutorial_compiler_flags" ];
      ifthen ["TARGET"; "SqrtLibrary"]
        (cmd_of_list
           [ list_append "installable_libs" [ str_ "SqrtLibrary" ] ]);
      install_targets [ "${installable_libs}" ] (str_ "lib");
      install_files [ quote "MathFunctions.h" ] (str_ "include");
    ]

let () = Fmt.pr "%a" (Fmt.vbox pp) cmd
