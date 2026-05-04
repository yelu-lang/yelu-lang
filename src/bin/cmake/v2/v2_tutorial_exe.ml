open Yelu_langs.Lang_cmake_utils
open Yelu_langs.Lang_cmake_pp

(* TutorialProject/Tutorial/CMakeLists.txt *)
let () =
  let msvc_cond =
    [ "("; "CMAKE_CXX_COMPILER_ID"; "STREQUAL"; "\"MSVC\""; ")"; "OR";
      "("; "CMAKE_CXX_COMPILER_FRONTEND_VARIANT"; "STREQUAL"; "\"MSVC\""; ")" ] in
  let gnu_clang_cond =
    [ "("; "CMAKE_CXX_COMPILER_ID"; "STREQUAL"; "\"GNU\""; ")"; "OR";
      "("; "CMAKE_CXX_COMPILER_ID"; "MATCHES"; "\"Clang\""; ")" ] in
  let ast = cmd_of_list [
    add_executable "Tutorial";
    target_sources "Tutorial" [ target_def ~kind:"PRIVATE" [ str_ "Tutorial.cxx" ] ];
    target_link_libraries [ "Tutorial" ]
      [ target_def ~kind:"PRIVATE" [ str_ "MathFunctions" ] ];
    target_compile_features "Tutorial"
      [ target_feature ~kind:"PRIVATE" "cxx_std_20" ];
    if_ msvc_cond
      (target_compile_options "Tutorial"
        [ target_def ~kind:"PRIVATE" [ str_ "/W3" ] ])
      (ifthen gnu_clang_cond
        (target_compile_options "Tutorial"
          [ target_def ~kind:"PRIVATE" [ str_ "-Wall" ] ]));
    find_path ~names:[ str_ "Unpackaged.h" ] ~required:true
      ~path_suffixes:[ "Unpackaged" ] "UnpackagedIncludeFolder";
    target_include_directories "Tutorial"
      [ target_def ~kind:"PRIVATE" [ str_ "${UnpackagedIncludeFolder}" ] ];
  ] in
  Fmt.pr "%a@." (Fmt.vbox pp) ast
