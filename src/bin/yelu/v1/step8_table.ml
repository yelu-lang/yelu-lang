open Yelu_langs.Yelu_cmake_utils
open Step_common_ir

let cmd =
  ycmd_of_list
    [
      yc_extern_target "tutorial_compiler_flags";
      add_exe ~sources:[ yfile "MakeTable.cxx" ] (ytval "MakeTable");
      link_lib [ ytval "MakeTable" ]
        [ ytarget_def ~kind:Private [ ytval "tutorial_compiler_flags" ] ];
      yc_add_custom_command
        ~outputs:[ yfile "${CMAKE_CURRENT_BINARY_DIR}/Table.h" ]
        ~depends:[ ystr "MakeTable" ]
        [ custom_command "MakeTable" [ "${CMAKE_CURRENT_BINARY_DIR}/Table.h" ] ];
    ]

let () = print_cmake cmd
