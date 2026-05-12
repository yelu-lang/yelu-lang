open Yelu_langs.Yelu_cmake_ir_utils
open Step_common_ir

let cmd =
  ycmd_of_list
    (project_preamble
    @ cxx_standard_11
    @ [
        ylet "tut" (ytval "Tutorial");
        configure_tutorial_header;
        yc_add_subdirectory (ydir "MathFunctions");
        add_exe ~sources:[ yfile "tutorial.cxx" ] (yvar "tut");
        link_lib
          [ yvar "tut" ]
          [ ytarget_def [ ytval "MathFunctions" ] ];
        include_dirs (yvar "tut")
          [
            ytarget_def
              [
                dir output_root;
                dir_concat source_root "MathFunctions";
              ];
          ];
      ])

let () = print_cmake cmd
