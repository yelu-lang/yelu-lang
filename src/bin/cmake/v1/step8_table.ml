open Yelu_langs.Lang_cmake_utils
open Yelu_langs.Lang_cmake_pp

let cmd =
  cmd_of_list
    [
      add_executable ~sources:[ "MakeTable.cxx" ] "MakeTable";
      target_link_libraries [ "MakeTable" ]
        [ target_def ~kind:"PRIVATE" [ str_ "tutorial_compiler_flags" ] ];
      add_custom_command
        ~outputs:[ "${CMAKE_CURRENT_BINARY_DIR}/Table.h" ]
        ~depends:[ "MakeTable" ]
        [ custom_command "MakeTable" [ "${CMAKE_CURRENT_BINARY_DIR}/Table.h" ] ];
    ]

let () = Fmt.pr "%a" (Fmt.vbox pp) cmd
