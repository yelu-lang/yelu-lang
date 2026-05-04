open Yelu_langs.Lang_cmake_utils
open Yelu_langs.Lang_cmake_pp

let cmd =
  cmd_of_list
    [
      minimum_required_s ~max:"3.20." "3.20.";
      project ~version:(version_of_string "1.0.") "Tutorial";
      add_library "tutorial_compiler_flags" ~type_:"INTERFACE";
      target_compile_features "tutorial_compiler_flags"
        [ target_feature ~kind:"INTERFACE" "cxx_std_11" ];
      set "CMAKE_CXX_STANDARD" [ str_ "11" ];
      set "CMAKE_CXX_STANDARD_REQUIRED" [ bool_ true ];
      configure_file ~input:"TutorialConfig.h.in" "TutorialConfig.h";
      add_subdirectory "MathFunctions";
      add_executable ~sources:[ "tutorial.cxx" ] "Tutorial";
      target_link_libraries [ "Tutorial" ]
        [ target_def [ str_ "MathFunctions"; str_ "tutorial_compiler_flags" ] ];
      target_include_directories "Tutorial"
        [
          target_def
            [ quote "${PROJECT_BINARY_DIR}" (* ;quote " ${EXTRA_INCLUDES}" *) ];
        ];
    ]

let () = Fmt.pr "%a" (Fmt.vbox pp) cmd
