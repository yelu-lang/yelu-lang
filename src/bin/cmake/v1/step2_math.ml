open Yelu_langs.Lang_cmake_utils
open Yelu_langs.Lang_cmake_pp

let cmd =
  cmd_of_list
    [
      add_library "MathFunctions" ~sources:[ "MathFunctions.cxx" ];
      option_ ~value:(bool_ true)
        ~msg:"Use tutorial provided math implementation" "USE_MYMATH";
      ifthen ["USE_MYMATH"]
        (cmd_of_list
           [
             target_compile_definitions "MathFunctions"
               [ target_def ~kind:"PRIVATE" [ quote "USE_MYMATH" ] ];
             add_library "SqrtLibrary" ~type_:"STATIC"
               ~sources:[ "mysqrt.cxx" ];
             target_link_libraries [ "MathFunctions" ]
               [ target_def ~kind:"PRIVATE" [ str_ "SqrtLibrary" ] ];
           ]);
    ]

let () = Fmt.pr "%a" (Fmt.vbox pp) cmd
