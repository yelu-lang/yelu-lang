open Yelu_langs.Lang_yelu_cmake
open Yelu_langs.Yelu_cmake_utils
open Step_common_ir

let cmd =
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

let () = print_cmake cmd
