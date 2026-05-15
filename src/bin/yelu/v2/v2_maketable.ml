open Yelu_langs.Lang_cmake
open Yelu_langs.Yelu_cmake_utils
open Step_common_ir

(* TutorialProject/MathFunctions/MakeTable/CMakeLists.txt
   Code generation: MakeTable exe → SqrtTable.h via add_custom_command OUTPUT.
   SqrtTable exposed as INTERFACE FILE_SET HEADERS with BASE_DIRS pointing at
   the binary directory. *)
let cmd =
  ycmd_of_list [
    add_exe (ytval "MakeTable");
    yc_target_sources_fs (ytval "MakeTable") [
      ytsi_plain Private [ yfile "MakeTable.cxx" ];
    ];
    yc_add_custom_command
      ~outputs:[ yfile "SqrtTable.h" ]
      ~depends:[ ytval "MakeTable" ]
      ~verbatim:true
      [ { command = "MakeTable"; args = [ "SqrtTable.h" ] } ];
    yc_add_custom_target ~depends:[ yfile "SqrtTable.h" ] "RunMakeTable";
    add_lib ~type_:Lib_interface (ytval "SqrtTable");
    yc_target_sources_fs (ytval "SqrtTable") [
      ytsi_file_set_headers
        ~base_dirs:[ ystr_eval "${CMAKE_CURRENT_BINARY_DIR}" ]
        ~files:[ ystr_eval "${CMAKE_CURRENT_BINARY_DIR}/SqrtTable.h" ]
        Interface;
    ];
    yc_add_dependencies "SqrtTable" "RunMakeTable";
  ]

let () = print_cmake cmd
