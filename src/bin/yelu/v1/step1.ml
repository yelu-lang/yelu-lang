open Yelu_langs.Lang_yelu_utils
open Step_common

let cmd =
  ycmd_of_list
    (project_preamble
    @ cxx_standard_11
    @ [
        ylet "tut" (ytval "Tutorial");
        configure_tutorial_header;
        add_exe ~sources:[ yfile "tutorial.cxx" ] (yvar "tut");
        include_dirs (yvar "tut")
          [ ytarget_def [ dir output_root ] ];
      ])

let () = print_cmake cmd
