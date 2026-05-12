open Yelu_langs.Yelu_cmake_ir_utils
open Step_common_ir

let cmd =
  ycmd_of_list
    (project_preamble
    @ [
        ylet "tut" (ytval "Tutorial");
        ylet "flags" (ytval "tutorial_compiler_flags");
        ylet "do_test" (ycstr "do_test");
      ]
    @ shared_libs_output_dirs
    @ compiler_flags_lib
    @ compiler_warning_options
    @ [
        configure_tutorial_header;
        yc_add_subdirectory (ydir "MathFunctions");
        add_exe ~sources:[ yfile "tutorial.cxx" ] (yvar "tut");
        link_lib [ yvar "tut" ]
          [ ytarget_def [ ytval "MathFunctions"; yvar "flags" ] ];
        include_dirs (yvar "tut")
          [ ytarget_def [ dir output_root ] ];
      ]
    @ install_tutorial
    @ test_suite ~ctest:true
    @ cpack_basic
    @ [
        yc_install_export
          ~file:(yfile "MathFunctionsTargets.cmake")
          (ystr "MathFunctionsTargets")
          (ydir "lib/cmake/MathFunctions");
        yc_include (yfile "CMakePackageConfigHelpers");
        yc_configure_package_config_file ~no_set_and_check_macro:true
          ~no_check_required_components_macro:true
          (ydir "lib/cmake/MathFunctions")
          (yfile "${CMAKE_CURRENT_SOURCE_DIR}/Config.cmake.in")
          (dir_concat output_this "MathFunctionsConfig.cmake");
        yc_write_basic_package_version_file ~compatibility:Any_newer_version
          ~version:(ystr_eval "${Tutorial_VERSION_MAJOR}.${Tutorial_VERSION_MINOR}")
          (dir_concat output_this "MathFunctionsConfigVersion.cmake");
        yc_install_files
          [
            yfile "${CMAKE_CURRENT_BINARY_DIR}/MathFunctionsConfig.cmake";
            yfile "${CMAKE_CURRENT_BINARY_DIR}/MathFunctionsConfigVersion.cmake";
          ]
          (ydir "lib/cmake/MathFunctions");
        yc_install_export
          ~file:(yfile "MathFunctionsTargets.cmake")
          (ystr "MathFunctionsTargets")
          (ydir "lib/cmake/MathFunctions");
        yc_export_export (ystr "MathFunctionsTargets")
          ~file:(dir_concat output_this "MathFunctionsTargets.cmake");
      ])

let () = print_cmake cmd
