open Yelu_langs.Lang_yelu_cmake
open Yelu_langs.Lang_yelu_utils
open Step_common

let cmd =
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
                 ~sources:[ yfile "mysqrt.cxx"; yfile "${CMAKE_CURRENT_BINARY_DIR}/Table.h" ]
                 (yvar "sqrt");
               include_dirs (yvar "sqrt")
                 [
                   ytarget_def ~kind:Private [ ydir "${CMAKE_CURRENT_BINARY_DIR}" ];
                 ];
               yc_set_target_properties (yvar "sqrt")
                 [ ("POSITION_INDEPENDENT_CODE", ystr "${BUILD_SHARED_LIBS}") ];
               link_lib [ yvar "sqrt" ]
                 [ ytarget_def ~kind:Public [ yvar "flags" ] ];
             ]
            @ math_check_cxx_features
            @ [
                link_lib [ yvar "math" ]
                  [ ytarget_def ~kind:Private [ yvar "sqrt" ] ];
                compile_defs (yvar "math")
                  [ ytarget_def ~kind:Private [ ykeyword "EXPORTING_MYMATH" ] ];
              ]));
       link_lib [ yvar "math" ]
         [ ytarget_def ~kind:Public [ yvar "flags" ] ];
     ]
    @ math_install_libs ())

let () = print_cmake cmd
