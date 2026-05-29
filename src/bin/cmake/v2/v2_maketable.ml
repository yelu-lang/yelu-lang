open Yelu_langs.Lang_cmake
open Yelu_langs.Lang_cmake_utils
open Yelu_langs.Lang_cmake_pp

(* TutorialProject/MathFunctions/MakeTable/CMakeLists.txt
   Code generation: MakeTable exe → SqrtTable.h via add_custom_command OUTPUT.
   SqrtTable exposed as INTERFACE FILE_SET HEADERS with BASE_DIRS pointing at
   the binary directory. *)
let () =
  let ast = cmd_of_list [
    add_executable "MakeTable";
    target_sources "MakeTable" [{ kind = "PRIVATE"; items = [ str_ "MakeTable.cxx" ] }];
    add_custom_command
      ~outputs:[ "SqrtTable.h" ]
      ~depends:[ "MakeTable" ]
      ~verbatim:true
      [ { command = "MakeTable"; args = [ "SqrtTable.h" ] } ];
    add_custom_target ~depends:[ "SqrtTable.h" ] "RunMakeTable" ();
    add_library "SqrtTable" ~type_:"INTERFACE";
    target_sources_fs "SqrtTable" [
      file_set_headers
        ~base_dirs:[ "${CMAKE_CURRENT_BINARY_DIR}" ]
        ~files:[ "${CMAKE_CURRENT_BINARY_DIR}/SqrtTable.h" ]
        "INTERFACE";
    ];
    Project_cmd (Add_dependencies { target = "SqrtTable"; deps = [ "RunMakeTable" ] });
  ] in
  Fmt.pr "%a@." (Fmt.vbox pp) ast
