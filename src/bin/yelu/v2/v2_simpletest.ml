open Yelu_langs.Lang_cmake
open Yelu_langs.Lang_yelu_cmake
open Yelu_langs.Lang_yelu_utils
open Step_common

(* SimpleTest/CMakeLists.txt *)
let cmd =
  ycmd_of_list [
    yc_project ~version:{ major = 0; minor = 0; patch = "1" } "SimpleTest";
    add_lib ~type_:Lib_interface (ytval "SimpleTest");
    yc_target_sources_fs (ytval "SimpleTest") [
      ytsi_file_set_headers ~files:[ yfile "SimpleTest.h" ] Interface;
    ];
    compile_feats (ytval "SimpleTest")
      [ { kind = Interface; feature = "cxx_std_20" } ];
    compile_defs (ytval "SimpleTest")
      [ ytarget_def ~kind:Interface [ ystr_eval "\"SIMPLETEST_CONFIG=$<CONFIG>\"" ] ];
    yc_find_package ~required:true "TransitiveDep";
    link_lib [ ytval "SimpleTest" ]
      [ ytarget_def ~kind:Interface [ ytval "TransitiveDep::TransitiveDep" ] ];
    yc_include (yname "GNUInstallDirs");
    yc_include (yname "CMakePackageConfigHelpers");
    yc_apply (yname "install")
      [ ykeyword "TARGETS"; ytval "SimpleTest";
        ykeyword "EXPORT"; yname "SimpleTestTargets";
        ykeyword "FILE_SET"; ykeyword "HEADERS" ];
    yc_install_export ~namespace:"SimpleTest::"
      (yname "SimpleTestTargets")
      (ystr_eval "${CMAKE_INSTALL_LIBDIR}/cmake/SimpleTest");
    yc_write_basic_package_version_file
      ~compatibility:Exact_version
      ~arch_independent:true
      (ystr_eval "${CMAKE_CURRENT_BINARY_DIR}/SimpleTestConfigVersion.cmake");
    yc_install_files
      [ yfile "cmake/simpletest_discover_impl.cmake";
        yfile "cmake/simpletest_discover_tests.cmake";
        yfile "cmake/SimpleTestConfig.cmake";
        ystr_eval "${CMAKE_CURRENT_BINARY_DIR}/SimpleTestConfigVersion.cmake" ]
      (ystr_eval "${CMAKE_INSTALL_LIBDIR}/cmake/SimpleTest");
  ]

let () = print_cmake cmd
