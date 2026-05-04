open Yelu_langs.Lang_cmake_utils
open Yelu_langs.Lang_cmake_pp

(* SimpleTest/CMakeLists.txt *)
let () =
  let ast = cmd_of_list [
    cmake_minimum_required "3.23";
    Project_cmd (Project { name = "SimpleTest"; version = Some (version_of_string "0.0.1");
      description = None; homepage_url = None; languages = [] });
    add_library "SimpleTest" ~type_:"INTERFACE";
    target_sources_fs "SimpleTest" [
      file_set_headers ~files:[ "SimpleTest.h" ] "INTERFACE";
    ];
    target_compile_features "SimpleTest"
      [ target_feature ~kind:"INTERFACE" "cxx_std_20" ];
    target_compile_definitions "SimpleTest"
      [ target_def ~kind:"INTERFACE" [ quote "SIMPLETEST_CONFIG=$<CONFIG>" ] ];
    find_package ~required:true "TransitiveDep";
    target_link_libraries [ "SimpleTest" ]
      [ target_def ~kind:"INTERFACE" [ str_ "TransitiveDep::TransitiveDep" ] ];
    include_ (str_ "GNUInstallDirs");
    include_ (str_ "CMakePackageConfigHelpers");
    apply "install"
      [ str_ "TARGETS"; str_ "SimpleTest";
        str_ "EXPORT"; str_ "SimpleTestTargets";
        str_ "FILE_SET"; str_ "HEADERS" ];
    install_export ~namespace:"SimpleTest::" (str_ "SimpleTestTargets")
      (str_ "${CMAKE_INSTALL_LIBDIR}/cmake/SimpleTest");
    write_basic_package_version_file
      ~compatibility:"ExactVersion"
      ~arch_independent:true
      (str_ "${CMAKE_CURRENT_BINARY_DIR}/SimpleTestConfigVersion.cmake");
    install_files
      [ str_ "cmake/simpletest_discover_impl.cmake";
        str_ "cmake/simpletest_discover_tests.cmake";
        str_ "cmake/SimpleTestConfig.cmake";
        str_ "${CMAKE_CURRENT_BINARY_DIR}/SimpleTestConfigVersion.cmake" ]
      (str_ "${CMAKE_INSTALL_LIBDIR}/cmake/SimpleTest");
  ] in
  Fmt.pr "%a@." (Fmt.vbox pp) ast
