(* Shared building blocks for yelu step programs.
   Blocks are [yelu_stmt list] values, composed with [@] into [ycmd_of_list].
   [ylet] bindings stay in each step file to wire blocks together. *)
open Yelu_langs.Lang_yelu_cmake
open Yelu_langs.Lang_yelu_utils

(* --- Root CMakeLists blocks --- *)

(** cmake_minimum_required(VERSION 3.20) + project(Tutorial VERSION 1.0).
    Steps: 1-12. *)
let project_preamble =
  [
    yc_minimum_required_s ~max:"3.20." "3.20.";
    yc_project
      ~version:(Yelu_langs.Lang_cmake_utils.version_of_string "1.0.")
      "Tutorial";
  ]

(** set CMAKE_CXX_STANDARD=11, CMAKE_CXX_STANDARD_REQUIRED=true.
    Steps: 1-3. *)
let cxx_standard_11 =
  [
    yc_set (ycvar "CMAKE_CXX_STANDARD") [ ystr "11" ];
    yc_set (ycvar "CMAKE_CXX_STANDARD_REQUIRED") [ ybool true ];
  ]

(** INTERFACE library + cxx_std_11 compile feature.
    Requires: [yvar "flags"]. Steps: 3-12. *)
let compiler_flags_lib =
  [
    add_lib ~type_:Lib_interface (yvar "flags");
    compile_feats (yvar "flags")
      [ ytarget_feature ~kind:Interface "cxx_std_11" ];
  ]

(** gcc/msvc detection vars + compile warning options.
    Requires: [yvar "flags"]. Steps: 4-12. *)
let compiler_warning_options =
  [
    yc_set (ycvar "gcc_like_cxx")
      [ ystr_eval "$<COMPILE_LANG_AND_ID:CXX,ARMClang,AppleClang,Clang,GNU,LCC>" ];
    yc_set (ycvar "msvc_cxx") [ ystr_eval "$<COMPILE_LANG_AND_ID:CXX,MSVC>" ];
    compile_opts (yvar "flags")
      [
        ytarget_def ~kind:Interface
          [
            ystr_eval
              "$<${gcc_like_cxx}:-Wall;-Wextra;-Wshadow;-Wformat=2;-Wunused>";
            ystr_eval "$<${msvc_cxx}:-W3>";
          ];
      ];
    compile_opts (yvar "flags")
      [
        ytarget_def ~kind:Interface
          [
            ystr_eval
              "$<${gcc_like_cxx}:$<BUILD_INTERFACE:-Wall;-Wextra;-Wshadow;-Wformat=2;-Wunused>>";
            ystr_eval "$<${msvc_cxx}:$<BUILD_INTERFACE:-W3>>";
          ];
      ];
  ]

(** configure_file TutorialConfig.h.in -> TutorialConfig.h.
    Steps: 1-12. *)
let configure_tutorial_header =
  gen_file ~input:(yfile "TutorialConfig.h.in") (yfile "TutorialConfig.h")

(** Install Tutorial binary + config header.
    Requires: [yvar "tut"]. Steps: 5-12. *)
let install_tutorial =
  [
    yc_install_targets [ yvar "tut" ] (ydir "bin");
    yc_install_files
      [ dir_concat output_root "TutorialConfig.h" ]
      (ydir "include");
  ]

(** Test suite: testing infrastructure + do_test function + invocations.
    Requires: [yvar "tut"], [yvar "do_test"].
    @param ctest if true uses include(CTest) (step6+), else enable_testing() (step5). *)
let test_suite ~ctest =
  [
    (if ctest then yc_include (yfile "CTest") else yc_enable_testing);
    yc_add_test (ystr "Runs") (ystr "Tutorial") [ ystr "25" ];
    yc_add_test (ystr "Usage") (ystr "Tutorial") [];
    yc_set_tests_properties [ ystr "Usage" ]
      [ ("PASS_REGULAR_EXPRESSION", ystr "Usage:.*number") ];
    yc_add_test (ystr "StandardUse") (ystr "Tutorial") [ ystr "4" ];
    yc_set_tests_properties [ ystr "Usage" ]
      [ ("PASS_REGULAR_EXPRESSION", ystr "4 is 2") ];
    yc_function (yvar "do_test")
      [ "target"; "arg"; "result" ]
      [
        yc_add_test (ystr "Comp${arg}") (ystr "${target}") [ ystr "${arg}" ];
        yc_set_tests_properties [ ystr "Comp${arg}" ]
          [ ("PASS_REGULAR_EXPRESSION", ystr "${result}") ];
      ];
    yc_apply (yvar "do_test") [ yvar "tut"; ystr "4"; ystr "4 is 2" ];
    yc_apply (yvar "do_test") [ yvar "tut"; ystr "9"; ystr "9 is 3" ];
    yc_apply (yvar "do_test") [ yvar "tut"; ystr "5"; ystr "5 is 2.236" ];
    yc_apply (yvar "do_test") [ yvar "tut"; ystr "7"; ystr "7 is 2.645" ];
    yc_apply (yvar "do_test") [ yvar "tut"; ystr "25"; ystr "25 is 5" ];
    yc_apply (yvar "do_test")
      [ yvar "tut"; ystr "-25"; ystr "-25 is (-nan|nan|0)" ];
    yc_apply (yvar "do_test")
      [ yvar "tut"; ystr "0.0001"; ystr "0.0001 is 0.01" ];
  ]

(** CPack configuration.
    Steps: 9-12. *)
let cpack_basic =
  [
    yc_include (yfile "InstallRequiredSystemLibraries");
    yc_set (ycvar "CPACK_RESOURCE_FILE_LICENSE")
      [ dir_concat source_this "License.txt" ];
    yc_set (ycvar "CPACK_PACKAGE_VERSION_MAJOR")
      [ ystr_eval "${Tutorial_VERSION_MAJOR}" ];
    yc_set (ycvar "CPACK_PACKAGE_VERSION_MINOR")
      [ ystr_eval "${Tutorial_VERSION_MINOR}" ];
    yc_set (ycvar "CPACK_GENERATOR") [ ykeyword "TGZ" ];
    yc_set (ycvar "CPACK_SOURCE_GENERATOR") [ ykeyword "TGZ" ];
    yc_include (yfile "CPack");
  ]

(** Output directories + BUILD_SHARED_LIBS option.
    Steps: 10-12. *)
let shared_libs_output_dirs =
  [
    yc_set (ycvar "CMAKE_ARCHIVE_OUTPUT_DIRECTORY")
      [ dir output_root ];
    yc_set (ycvar "CMAKE_LIBRARY_OUTPUT_DIRECTORY")
      [ dir output_root ];
    yc_set (ycvar "CMAKE_RUNTIME_OUTPUT_DIRECTORY")
      [ dir output_root ];
    yc_option ~value:(ybool true) ~msg:"Build using shared libraries"
      (ycvar "BUILD_SHARED_LIBS");
  ]

(* --- MathFunctions blocks --- *)

(** CheckCXXSourceCompiles checks for log/exp + conditional define.
    Requires: [yvar "check_cxx"], [yvar "have_log"], [yvar "have_exp"],
    [yvar "sqrt"]. Steps: 7_math-12_math. *)
let math_check_cxx_features =
  [
    yc_include (yfile "CheckCXXSourceCompiles");
    yc_apply (yvar "check_cxx")
      [
        ystr_eval
          "\n\
          \  #include <cmath>\n\
          \  int main() {\n\
          \    std::log(1.0);\n\
          \    return 0;\n\
          \  }";
        yvar "have_log";
      ];
    yc_apply (yvar "check_cxx")
      [
        ystr_eval
          "\n\
          \  #include <cmath>\n\
          \  int main() {\n\
          \    std::exp(1.0);\n\
          \    return 0;\n\
          \  }";
        yvar "have_exp";
      ];
    yifthen
      (yand (ytruthy (yvar "have_log")) (ytruthy (yvar "have_exp")))
      (compile_defs (yvar "sqrt")
         [
           ytarget_def ~kind:Private [ ykeyword "HAVE_LOG"; ykeyword "HAVE_EXP" ];
         ]);
  ]

(** installable_libs set + conditional SqrtLibrary append + install.
    Requires: [yvar "inst_libs"], [yvar "math"], [yvar "flags"], [yvar "sqrt"].
    @param export optional export name for install(TARGETS ... EXPORT).
    Steps: 5_math-12_math. *)
let math_install_libs ?export () =
  [
    yc_set (ycvar "installable_libs") [ yvar "math"; yvar "flags" ];
    yifthen (yis_target (ytval "SqrtLibrary"))
      (ycmd_of_list [ yc_list_append (ycvar "installable_libs") [ yvar "sqrt" ] ]);
    yc_install_targets ?export [ ytval "${installable_libs}" ] (ydir "lib");
    yc_install_files [ yfile "MathFunctions.h" ] (ydir "include");
  ]

(** Compile and print a yelu command to stdout as cmake.

    Routes through the production path: bridge into Yelu1 IR, then
    [emit_ast] into [Lang_cmake.exp], then [Lang_cmake_pp]. The legacy
    [Lang_yelu_compile.compile] stays callable for the byte-equality
    oracle in [test_yelu_compile.ml]. *)
let print_cmake cmd =
  let yelu1 = Yelu_langs.Yelu_cmake_legacy_bridge.stmt cmd in
  Fmt.pr "%a" (Fmt.vbox Yelu_langs.Lang_cmake_pp.pp)
    (Yelu_langs.Yelu_cmake_surface_emit.emit_ast yelu1)
