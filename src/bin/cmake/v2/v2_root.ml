open Yelu_langs.Lang_cmake_utils
open Yelu_langs.Lang_cmake_pp

(* TutorialProject/CMakeLists.txt *)
let () =
  let ast = cmd_of_list [
    cmake_minimum_required "3.23";
    Project_cmd (Project { name = "Tutorial"; version = Some (version_of_string "1.0.0");
      description = None; homepage_url = None; languages = [] });
    option_ ~value:(bool_ true) ~msg:"Build the Tutorial executable"
      "TUTORIAL_BUILD_UTILITIES";
    option_ ~value:(bool_ false) ~msg:"Use std::sqrt"
      "TUTORIAL_USE_STD_SQRT";
    option_ ~value:(bool_ true) ~msg:"Check for and use IPO support"
      "TUTORIAL_ENABLE_IPO";
    option_ ~value:(bool_ true) ~msg:"Enable testing and build tests"
      "BUILD_TESTING";
    ifthen [ "TUTORIAL_ENABLE_IPO" ]
      (cmd_of_list [
        include_ (str_ "CheckIPOSupported");
        apply "check_ipo_supported"
          [ str_ "RESULT"; str_ "result"; str_ "OUTPUT"; str_ "output" ];
        if_ [ "result" ]
          (cmd_of_list [
            message ~mode:Mm_none [ "IPO is supported, enabling IPO" ];
            set "CMAKE_INTERPROCEDURAL_OPTIMIZATION" [ str_ "ON" ];
          ])
          (message ~mode:Mm_warning [ "IPO is not supported: ${output}" ]);
      ]);
    ifthen [ "TUTORIAL_BUILD_UTILITIES" ] (add_subdirectory "Tutorial");
    ifthen [ "BUILD_TESTING" ]
      (cmd_of_list [
        enable_testing;
        add_subdirectory "Tests";
      ]);
    add_subdirectory "MathFunctions";
    include_ (str_ "GNUInstallDirs");
    apply "install"
      [ str_ "TARGETS"; str_ "MathFunctions"; str_ "OpAdd"; str_ "OpMul";
        str_ "OpSub"; str_ "MathLogger"; str_ "SqrtTable";
        str_ "EXPORT"; str_ "TutorialTargets";
        str_ "FILE_SET"; str_ "HEADERS" ];
    install_export ~namespace:"Tutorial::" (str_ "TutorialTargets")
      (str_ "${CMAKE_INSTALL_LIBDIR}/cmake/Tutorial");
    include_ (str_ "CMakePackageConfigHelpers");
    write_basic_package_version_file
      ~compatibility:"ExactVersion"
      (str_ "${CMAKE_CURRENT_BINARY_DIR}/TutorialConfigVersion.cmake");
    install_files
      [ str_ "cmake/TutorialConfig.cmake";
        str_ "${CMAKE_CURRENT_BINARY_DIR}/TutorialConfigVersion.cmake" ]
      (str_ "${CMAKE_INSTALL_LIBDIR}/cmake/Tutorial");
  ] in
  Fmt.pr "%a@." (Fmt.vbox pp) ast
