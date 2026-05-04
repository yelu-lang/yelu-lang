open Yelu_langs.Lang_yelu_utils
open Step_common

let cmd =
  ycmd_of_list
    (project_preamble
    @ [
        ylet "tut" (ytval "Tutorial");
        ylet "flags" (ytval "tutorial_compiler_flags");
        ylet "do_test" (ycstr "do_test");
      ]
    @ compiler_flags_lib
    @ compiler_warning_options
    @ [
        configure_tutorial_header;
        yc_add_subdirectory (ydir "MathFunctions");
        add_exe ~sources:[ yfile "tutorial.cxx" ] (yvar "tut");
        link_lib [ yvar "tut" ]
          [ ytarget_def [ ytval "MathFunctions"; yvar "flags" ] ];
        include_dirs (yvar "tut")
          [ ytarget_def [ dir output_root ] ];
      ]
    @ install_tutorial
    @ test_suite ~ctest:true
    @ cpack_basic)

let () = print_cmake cmd
