open Yelu_langs.Lang_cmake_utils
open Yelu_langs.Lang_cmake_pp

let cmd =
  cmd_of_list
    [
      minimum_required_s ~max:"3.20." "3.20.";
      project ~version:(version_of_string "1.0.") "Tutorial";
      set "CMAKE_ARCHIVE_OUTPUT_DIRECTORY"
        [ quote "${PROJECT_BINARY_DIR}" ];
      set "CMAKE_LIBRARY_OUTPUT_DIRECTORY"
        [ quote "${PROJECT_BINARY_DIR}" ];
      set "CMAKE_RUNTIME_OUTPUT_DIRECTORY"
        [ quote "${PROJECT_BINARY_DIR}" ];
      option_ ~value:(bool_ true) ~msg:"Build using shared libraries"
        "BUILD_SHARED_LIBS";
      set "CMAKE_DEBUG_POSTFIX" [ quote "d" ];
      add_library "tutorial_compiler_flags" ~type_:"INTERFACE";
      target_compile_features "tutorial_compiler_flags"
        [ target_feature ~kind:"INTERFACE" "cxx_std_11" ];
      set "gcc_like_cxx"
        [ quote "$<COMPILE_LANG_AND_ID:CXX,ARMClang,AppleClang,Clang,GNU,LCC>" ];
      set "msvc_cxx" [ quote "$<COMPILE_LANG_AND_ID:CXX,MSVC>" ];
      target_compile_options "tutorial_compiler_flags"
        [
          target_def ~kind:"INTERFACE"
            [
              quote
                "$<${gcc_like_cxx}:-Wall;-Wextra;-Wshadow;-Wformat=2;-Wunused>";
              quote "$<${msvc_cxx}:-W3>";
            ];
        ];
      target_compile_options "tutorial_compiler_flags"
        [
          target_def ~kind:"INTERFACE"
            [
              quote
                "$<${gcc_like_cxx}:$<BUILD_INTERFACE:-Wall;-Wextra;-Wshadow;-Wformat=2;-Wunused>>";
              quote "$<${msvc_cxx}:$<BUILD_INTERFACE:-W3>>";
            ];
        ];
      configure_file ~input:"TutorialConfig.h.in" "TutorialConfig.h";
      add_subdirectory "MathFunctions";
      add_executable ~sources:[ "tutorial.cxx" ] "Tutorial";
      set_target_properties "Tutorial"
        [ ("DEBUG_POSTFIX", str_ "${CMAKE_DEBUG_POSTFIX}") ];
      target_link_libraries [ "Tutorial" ]
        [ target_def [ str_ "MathFunctions"; str_ "tutorial_compiler_flags" ] ];
      target_include_directories "Tutorial"
        [ target_def [ quote "${PROJECT_BINARY_DIR}" ] ];
      install_targets [ "Tutorial" ] (str_ "bin");
      install_files
        [ quote "${PROJECT_BINARY_DIR}/TutorialConfig.h" ]
        (str_ "include");
      include_ (str_ "CTest");
      add_test "Runs" "Tutorial" [ "25" ];
      add_test "Usage" "Tutorial" [];
      set_tests_properties [ "Usage" ]
        [ ("PASS_REGULAR_EXPRESSION", quote "Usage:.*number") ];
      add_test "StandardUse" "Tutorial" [ "4" ];
      set_tests_properties [ "Usage" ]
        [ ("PASS_REGULAR_EXPRESSION", quote "4 is 2") ];
      function_ "do_test"
        [ "target"; "arg"; "result" ]
        [
          add_test "Comp${arg}" "${target}" [ "${arg}" ];
          set_tests_properties [ "Comp${arg}" ]
            [ ("PASS_REGULAR_EXPRESSION", str_ "${result}") ];
        ];
      apply "do_test" [ str_ "Tutorial"; str_ "4"; quote "4 is 2" ];
      apply "do_test" [ str_ "Tutorial"; str_ "9"; quote "9 is 3" ];
      apply "do_test" [ str_ "Tutorial"; str_ "5"; quote "5 is 2.236" ];
      apply "do_test" [ str_ "Tutorial"; str_ "7"; quote "7 is 2.645" ];
      apply "do_test" [ str_ "Tutorial"; str_ "25"; quote "25 is 5" ];
      apply "do_test"
        [ str_ "Tutorial"; str_ "-25"; quote "-25 is (-nan|nan|0)" ];
      apply "do_test"
        [ str_ "Tutorial"; str_ "0.0001"; quote "0.0001 is 0.01" ];
      include_ (str_ "InstallRequiredSystemLibraries");
      set "CPACK_RESOURCE_FILE_LICENSE"
        [ quote "${CMAKE_CURRENT_SOURCE_DIR}/License.txt" ];
      set "CPACK_PACKAGE_VERSION_MAJOR"
        [ quote "${Tutorial_VERSION_MAJOR}" ];
      set "CPACK_PACKAGE_VERSION_MINOR"
        [ quote "${Tutorial_VERSION_MINOR}" ];
      set "CPACK_GENERATOR" [ quote "TGZ" ];
      set "CPACK_SOURCE_GENERATOR" [ quote "TGZ" ];
      include_ (str_ "CPack");
      install_export
        ~file:(str_ "MathFunctionsTargets.cmake")
        (str_ "MathFunctionsTargets")
        (str_ "lib/cmake/MathFunctions");
      include_ (str_ "CMakePackageConfigHelpers");
      configure_package_config_file ~no_set_and_check_macro:true
        ~no_check_required_components_macro:true
        (quote "lib/cmake/MathFunctions")
        (str_ "${CMAKE_CURRENT_SOURCE_DIR}/Config.cmake.in")
        (quote "${CMAKE_CURRENT_BINARY_DIR}/MathFunctionsConfig.cmake");
      write_basic_package_version_file ~compatibility:"AnyNewerVersion"
        ~version:(quote "${Tutorial_VERSION_MAJOR}.${Tutorial_VERSION_MINOR}")
        (quote "${CMAKE_CURRENT_BINARY_DIR}/MathFunctionsConfigVersion.cmake");
      install_files
        [
          str_ "${CMAKE_CURRENT_BINARY_DIR}/MathFunctionsConfig.cmake";
          str_ "${CMAKE_CURRENT_BINARY_DIR}/MathFunctionsConfigVersion.cmake";
        ]
        (str_ "lib/cmake/MathFunctions");
      install_export
        ~file:(str_ "MathFunctionsTargets.cmake")
        (str_ "MathFunctionsTargets")
        (str_ "lib/cmake/MathFunctions");
      export_export "MathFunctionsTargets"
        ~file:(quote "${CMAKE_CURRENT_BINARY_DIR}/MathFunctionsTargets.cmake");
    ]

let () = Fmt.pr "%a" (Fmt.vbox pp) cmd
