open Yelu_langs.Lang_cmake
open Yelu_langs.Yelu_cmake_utils
open Step_common_ir

(* TutorialProject/CMakeLists.txt *)
let cmd =
  ycmd_of_list [
    yc_project ~version:{ major = 1; minor = 0; patch = "0" } "Tutorial";
    yc_option ~value:(ybool true)  ~msg:"Build the Tutorial executable" (ycvar "TUTORIAL_BUILD_UTILITIES");
    yc_option ~value:(ybool false) ~msg:"Use std::sqrt"                  (ycvar "TUTORIAL_USE_STD_SQRT");
    yc_option ~value:(ybool true)  ~msg:"Check for and use IPO support"  (ycvar "TUTORIAL_ENABLE_IPO");
    yc_option ~value:(ybool true)  ~msg:"Enable testing and build tests"  (ycvar "BUILD_TESTING");
    yifthen (ytruthy (ycstr "TUTORIAL_ENABLE_IPO"))
      (ycmd_of_list [
        yc_include (yname "CheckIPOSupported");
        yc_apply (yname "check_ipo_supported")
          [ ystr_eval "RESULT"; ystr_eval "result";
            ystr_eval "OUTPUT"; ystr_eval "output" ];
        yif (ytruthy (ycstr "result"))
          (ycmd_of_list [
            yc_message ~mode:Mm_none [ "IPO is supported, enabling IPO" ];
            yc_set (ycvar "CMAKE_INTERPROCEDURAL_OPTIMIZATION") [ ybool true ];
          ])
          (yc_message ~mode:Mm_warning [ "IPO is not supported: ${output}" ]);
      ]);
    yifthen (ytruthy (ycstr "TUTORIAL_BUILD_UTILITIES"))
      (yc_add_subdirectory (ydir "Tutorial"));
    yifthen (ytruthy (ycstr "BUILD_TESTING"))
      (ycmd_of_list [
        yc_enable_testing;
        yc_add_subdirectory (ydir "Tests");
      ]);
    yc_add_subdirectory (ydir "MathFunctions");
    yc_include (yname "GNUInstallDirs");
    yc_apply (yname "install")
      [ ykeyword "TARGETS"; ytval "MathFunctions"; ytval "OpAdd"; ytval "OpMul";
        ytval "OpSub"; ytval "MathLogger"; ytval "SqrtTable";
        ykeyword "EXPORT"; yname "TutorialTargets";
        ykeyword "FILE_SET"; ykeyword "HEADERS" ];
    yc_install_export ~namespace:"Tutorial::"
      (yname "TutorialTargets")
      (ystr_eval "${CMAKE_INSTALL_LIBDIR}/cmake/Tutorial");
    yc_include (yname "CMakePackageConfigHelpers");
    yc_write_basic_package_version_file
      ~compatibility:Exact_version
      (ystr_eval "${CMAKE_CURRENT_BINARY_DIR}/TutorialConfigVersion.cmake");
    yc_install_files
      [ yfile "cmake/TutorialConfig.cmake";
        ystr_eval "${CMAKE_CURRENT_BINARY_DIR}/TutorialConfigVersion.cmake" ]
      (ystr_eval "${CMAKE_INSTALL_LIBDIR}/cmake/Tutorial");
  ]

let () = print_cmake cmd
