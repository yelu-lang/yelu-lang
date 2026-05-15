(** Build-level equivalence tests: run upstream CMakeCommands reference cmake AND
    yelu-generated cmake through configure + build. Both must exit 0.
    Source: Tests/CMakeCommands/ — one subdirectory per target_* command. *)

open Yelu_langs.Yelu_cmake
open Yelu_langs.Yelu_cmake_utils
open Yelu_langs.Lang_cmake_pp
open Yelu_runner.Cmake_runner

let cmake_commands_dir =
  match Sys.getenv_opt "RUNCMAKE_DIR" with
  | Some d -> Filename.concat (Filename.dirname d) "CMakeCommands"
  | None ->
    let rec find dir depth =
      if depth > 10 then failwith ("cannot find workspace root from " ^ Sys.getcwd ())
      else
        let marker = Filename.concat dir "yelu/vendor" in
        if Sys.file_exists marker then dir
        else find (Filename.dirname dir) (depth + 1)
    in
    let ws_root = find (Sys.getcwd ()) 0 in
    let vendor_cmake = Filename.concat ws_root "yelu/vendor/cmake" in
    let resolved = try Unix.realpath vendor_cmake with Unix.Unix_error _ -> vendor_cmake in
    Filename.concat resolved "Tests/CMakeCommands"

(* Parent of cmake_commands_dir: Tests/ — used for Group 2 tests outside CMakeCommands/ *)
let tests_dir = Filename.dirname cmake_commands_dir

let ref_dir name = Filename.concat cmake_commands_dir name

let compile prog =
  let ast = Yelu_langs.Yelu_cmake_emit.emit_ast prog in
  let buf = Buffer.create 512 in
  let ff = Format.formatter_of_buffer buf in
  Format.pp_open_vbox ff 0;
  pp ff ast;
  Format.pp_close_box ff ();
  Format.pp_print_flush ff ();
  Buffer.contents buf

let run_build_pair ref_path ?(files = []) yelu_prog =
  let ref_result  = run_build_existing ref_path in
  let cmake_text  = compile yelu_prog in
  let yelu_result = run_configure_and_build ~files cmake_text in
  (if ref_result.configure.run.exit_code <> 0 then
     Alcotest.failf "ref configure failed (exit %d)\nstderr:\n%s"
       ref_result.configure.run.exit_code ref_result.configure.run.stderr);
  (if ref_result.build.exit_code <> 0 then
     Alcotest.failf "ref build failed (exit %d)\nstderr:\n%s"
       ref_result.build.exit_code ref_result.build.stderr);
  (if yelu_result.configure.run.exit_code <> 0 then
     Alcotest.failf "yelu configure failed (exit %d)\nstderr:\n%s\ncmake:\n%s"
       yelu_result.configure.run.exit_code yelu_result.configure.run.stderr cmake_text);
  (if yelu_result.build.exit_code <> 0 then
     Alcotest.failf "yelu build failed (exit %d)\nstderr:\n%s\ncmake:\n%s"
       yelu_result.build.exit_code yelu_result.build.stderr cmake_text);
  check_artifacts_match ref_result.artifacts yelu_result.artifacts

(** Yelu-only build test: configure + build yelu-generated cmake, no reference. *)
let check_build_yelu name ?(files = []) yelu_prog =
  Alcotest.test_case name `Quick (fun () ->
    let cmake_text = compile yelu_prog in
    let r = run_configure_and_build ~files cmake_text in
    (if r.configure.run.exit_code <> 0 then
       Alcotest.failf "configure failed (exit %d)\nstderr:\n%s\ncmake:\n%s"
         r.configure.run.exit_code r.configure.run.stderr cmake_text);
    if r.build.exit_code <> 0 then
      Alcotest.failf "build failed (exit %d)\nstderr:\n%s\ncmake:\n%s"
        r.build.exit_code r.build.stderr cmake_text)

(** Fate-sharing build test against Tests/CMakeCommands/<ref_name>. *)
let check_build_pair name ref_name ?(files = []) yelu_prog =
  Alcotest.test_case name `Quick (fun () ->
    run_build_pair (ref_dir ref_name) ~files yelu_prog)

(** Same, but ref is in Tests/<ref_name> (Group 2 tests outside CMakeCommands/). *)
let check_build_pair_tests name ref_name ?(files = []) yelu_prog =
  Alcotest.test_case name `Quick (fun () ->
    run_build_pair (Filename.concat tests_dir ref_name) ~files yelu_prog)

(* ==================================================================== *)
(* target_link_options                                                   *)
(* ==================================================================== *)

(* Ref: Tests/CMakeCommands/target_link_options/CMakeLists.txt
   Covers: PRIVATE/INTERFACE scopes, empty options, BEFORE ordering.
   The upstream cmake has get_target_property assertions that fail configure
   (via SEND_ERROR) if target properties are wrong — so configure exit 0
   means the assertions passed. *)

let c_lib_source = {|
#if defined(_WIN32)
__declspec(dllexport)
#endif
int flags_lib(void) { return 0; }
|}

let t name = ytval name

let tlo_yelu =
  ESeq [
    yc_project ~languages:[Lang_c] "target_link_options";
    add_lib ~type_:Lib_shared ~sources:[ystr "lib.c"] (t "target_link_options");
    yc_target_link_options (t "target_link_options")
      [ ytarget_def ~kind:Private [] ];
    add_lib ~type_:Lib_shared ~exclude_from_all:true ~sources:[ystr "lib.c"] (t "target_link_options_2");
    yc_target_link_options (t "target_link_options_2")
      [ ytarget_def ~kind:Private  [ystr "-PRIVATE_FLAG"];
        ytarget_def ~kind:Interface [ystr "-INTERFACE_FLAG"] ];
    add_lib ~type_:Lib_static ~exclude_from_all:true ~sources:[ystr "lib.c"] (t "target_link_options_3");
    yc_target_link_options (t "target_link_options_3")
      [ ytarget_def ~kind:Interface [ystr "-INTERFACE_FLAG"] ];
    add_lib ~type_:Lib_shared ~exclude_from_all:true ~sources:[ystr "lib.c"] (t "target_link_options_4");
    yc_target_link_options ~before:false (t "target_link_options_4")
      [ ytarget_def ~kind:Private [ystr "-PRIVATE_FLAG"] ];
    yc_target_link_options ~before:true (t "target_link_options_4")
      [ ytarget_def ~kind:Private [ystr "-BEFORE_PRIVATE_FLAG"] ];
  ]

(* ==================================================================== *)
(* add_compile_definitions                                               *)
(* ==================================================================== *)

(* Ref: Tests/CMakeCommands/add_compile_definitions/CMakeLists.txt
   Covers: plain def, genex $<COMPILE_LANGUAGE:CXX>, genex that evals false.
   main.cpp asserts TEST_DEFINITION and LANG_CXX are defined; UNEXPECTED_DEFINITION must not be. *)

let cpp_main_source = {|
#ifndef TEST_DEFINITION
#  error Expected TEST_DEFINITION
#endif
#ifndef LANG_CXX
#  error Expected LANG_CXX
#endif
#ifdef UNEXPECTED_DEFINITION
#  error Unexpected UNEXPECTED_DEFINITION
#endif
int main(void) { return 0; }
|}

let acd_yelu =
  ESeq [
    yc_project ~languages:[Lang_cxx] "add_compile_definitions";
    yc_add_compile_definitions [
      ystr "TEST_DEFINITION";
      ystr_eval "$<$<COMPILE_LANGUAGE:CXX>:LANG_$<COMPILE_LANGUAGE>>";
      ystr_eval "$<$<EQUAL:0,1>:UNEXPECTED_DEFINITION>";
    ];
    add_exe ~sources:[ystr "main.cpp"] (t "add_compile_definitions");
    add_lib_imported ~lib_type:"UNKNOWN" (t "imp");
    yc_get_target_property (ycvar "_res") "imp" "COMPILE_DEFINITIONS";
    yifthen (ytruthy (ycstr "_res"))
      (ESeq [ yc_message ~mode:Mm_send_error ["add_compile_definitions populated the COMPILE_DEFINITIONS target property"] ]);
  ]

(* ==================================================================== *)
(* add_link_options                                                      *)
(* ==================================================================== *)

(* Ref: Tests/CMakeCommands/add_link_options/CMakeLists.txt
   Covers: global link flag propagation to LINK_OPTIONS target property,
   imported targets must NOT inherit it. *)

let add_link_opts_yelu =
  ESeq [
    yc_project ~languages:[Lang_c] "add_link_options";
    yc_add_link_options [ystr "-LINK_FLAG"];
    add_exe ~exclude_from_all:true ~sources:[ystr "LinkOptionsExe.c"] (t "add_link_options");
    yc_get_target_property (ycvar "result") "add_link_options" "LINK_OPTIONS";
    yifthen (ynot (ymatches (ycstr "result") "-LINK_FLAG"))
      (ESeq [ yc_message ~mode:Mm_send_error ["add_link_options not populated the LINK_OPTIONS target property"] ]);
    add_lib_imported ~lib_type:"UNKNOWN" (t "imp");
    yc_get_target_property (ycvar "result") "imp" "LINK_OPTIONS";
    yifthen (ytruthy (ycstr "result"))
      (ESeq [ yc_message ~mode:Mm_fatal_error ["add_link_options populated the LINK_OPTIONS target property"] ]);
  ]

(* ==================================================================== *)
(* link_directories                                                      *)
(* ==================================================================== *)

(* Ref: Tests/CMakeCommands/link_directories/CMakeLists.txt
   Covers: BEFORE flag, CMAKE_LINK_DIRECTORIES_BEFORE, directory property,
   target property, imported target must NOT inherit. *)

let link_dirs_yelu =
  ESeq [
    yc_project ~languages:[Lang_c] "link_directories";
    yc_link_directories [ystr "/A"];
    yc_link_directories ~before:true [ystr "/B"];
    yc_set (ycvar "CMAKE_LINK_DIRECTORIES_BEFORE") [ybool true];
    yc_link_directories [ystr "/C"];
    yc_get_directory_property "LINK_DIRECTORIES" (ycvar "result");
    yifthen (ynot (ymatches (ycstr "result") "/C;/B;/A"))
      (ESeq [ yc_message ~mode:Mm_send_error ["link_directories not populated the LINK_DIRECTORIES directory property"] ]);
    add_exe ~exclude_from_all:true ~sources:[ystr "LinkDirectoriesExe.c"] (t "link_directories");
    yc_get_target_property (ycvar "result") "link_directories" "LINK_DIRECTORIES";
    yifthen (ynot (ymatches (ycstr "result") "/C;/B;/A"))
      (ESeq [ yc_message ~mode:Mm_send_error ["link_directories not populated the LINK_DIRECTORIES target property"] ]);
    add_lib_imported ~lib_type:"UNKNOWN" (t "imp");
    yc_get_target_property (ycvar "result") "imp" "LINK_DIRECTORIES";
    yifthen (ytruthy (ycstr "result"))
      (ESeq [ yc_message ~mode:Mm_fatal_error ["link_directories populated the LINK_DIRECTORIES target property"] ]);
  ]

(* ==================================================================== *)
(* add_compile_options                                                   *)
(* ==================================================================== *)

(* Ref: Tests/CMakeCommands/add_compile_options/CMakeLists.txt
   Covers: -DTEST_OPTION propagates to compile; imported target must NOT inherit.
   DO_GNU_TESTS block in main.cpp is guarded — skipping the compiler-conditional
   target_compile_definitions call is safe: the check won't fire on non-GNU. *)

let aco_main_source = {|
#ifdef DO_GNU_TESTS
#  ifndef TEST_OPTION
#    error Expected TEST_OPTION
#  endif
#endif
int main(void) { return 0; }
|}

let aco_yelu =
  ESeq [
    yc_project ~languages:[Lang_cxx] "add_compile_options";
    yc_add_compile_options [ystr "-DTEST_OPTION"];
    add_exe ~sources:[ystr "main.cpp"] (t "add_compile_options");
    yc_add_compile_options [ystr "-rtti"];
    add_lib_imported ~lib_type:"UNKNOWN" (t "imp");
    yc_get_target_property (ycvar "_res") "imp" "COMPILE_OPTIONS";
    yifthen (ytruthy (ycstr "_res"))
      (ESeq [ yc_message ~mode:Mm_send_error ["add_compile_options populated the COMPILE_OPTIONS target property"] ]);
  ]

(* ==================================================================== *)
(* target_compile_definitions                                            *)
(* ==================================================================== *)

(* Ref: Tests/CMakeCommands/target_compile_definitions/CMakeLists.txt
   Covers: PRIVATE/PUBLIC/INTERFACE scopes, genex COMPILE_LANGUAGE, -D prefix
   stripping, TARGET_PROPERTY interface propagation, UNKNOWN IMPORTED must not
   inherit add_compile_definitions. *)

let tcd_main_source = {|
#ifndef MY_PRIVATE_DEFINE
#  error Expected MY_PRIVATE_DEFINE
#endif
#ifndef MY_PUBLIC_DEFINE
#  error Expected MY_PUBLIC_DEFINE
#endif
#ifdef MY_INTERFACE_DEFINE
#  error Unexpected MY_INTERFACE_DEFINE
#endif
int main() { return 0; }
|}

let tcd_consumer_cpp_source = {|
#ifdef MY_PRIVATE_DEFINE
#  error Unexpected MY_PRIVATE_DEFINE
#endif
#ifndef MY_PUBLIC_DEFINE
#  error Expected MY_PUBLIC_DEFINE
#endif
#ifndef MY_INTERFACE_DEFINE
#  error Expected MY_INTERFACE_DEFINE
#endif
#ifndef DASH_D_DEFINE
#  error Expected DASH_D_DEFINE
#endif
#ifndef CONSUMER_LANG_CXX
#  error Expected CONSUMER_LANG_CXX
#endif
#ifdef CONSUMER_LANG_C
#  error Unexpected CONSUMER_LANG_C
#endif
#if !LANG_IS_CXX
#  error Expected LANG_IS_CXX
#endif
#if LANG_IS_C
#  error Unexpected LANG_IS_C
#endif
int main() { return 0; }
|}

let tcd_consumer_c_source = {|
#ifdef CONSUMER_LANG_CXX
#  error Unexpected CONSUMER_LANG_CXX
#endif
#ifndef CONSUMER_LANG_C
#  error Expected CONSUMER_LANG_C
#endif
#if !LANG_IS_C
#  error Expected LANG_IS_C
#endif
#if LANG_IS_CXX
#  error Unexpected LANG_IS_CXX
#endif
#if !LANG_IS_C_OR_CXX
#  error Expected LANG_IS_C_OR_CXX
#endif
void consumer_c(void) {}
|}

let tcd_yelu =
  ESeq [
    yc_project ~languages:[Lang_c; Lang_cxx] "target_compile_definitions";
    add_exe ~sources:[ystr "main.cpp"] (t "target_compile_definitions");
    compile_defs (t "target_compile_definitions") [
      ytarget_def ~kind:Private   [ystr "MY_PRIVATE_DEFINE"];
      ytarget_def ~kind:Public    [ystr "MY_PUBLIC_DEFINE"];
      ytarget_def ~kind:Interface [ystr "MY_INTERFACE_DEFINE"];
    ];
    add_exe ~sources:[ystr "consumer.cpp"] (t "consumer");
    compile_defs (t "consumer") [
      ytarget_def ~kind:Private [
        ystr_eval "$<TARGET_PROPERTY:target_compile_definitions,INTERFACE_COMPILE_DEFINITIONS>";
        ystr "-DDASH_D_DEFINE";
      ];
    ];
    compile_defs (t "consumer") [ ytarget_def ~kind:Private [] ];
    yc_target_sources (t "consumer") [ytarget_def ~kind:Private [ystr "consumer.c"]];
    compile_defs (t "consumer") [
      ytarget_def ~kind:Private [
        ystr_eval "CONSUMER_LANG_$<COMPILE_LANGUAGE>";
        ystr_eval "LANG_IS_CXX=$<COMPILE_LANGUAGE:CXX>";
        ystr_eval "LANG_IS_C=$<COMPILE_LANGUAGE:C>";
        ystr_eval "LANG_IS_C_OR_CXX=$<COMPILE_LANGUAGE:C,CXX>";
      ];
    ];
    yc_add_compile_definitions [ystr "-DSOME_DEF"];
    add_lib_imported ~lib_type:"UNKNOWN" (t "imp");
    yc_get_target_property (ycvar "_res") "imp" "COMPILE_DEFINITIONS";
    yifthen (ytruthy (ycstr "_res"))
      (ESeq [ yc_message ~mode:Mm_send_error ["add_definitions populated the COMPILE_DEFINITIONS target property"] ]);
  ]

(* ==================================================================== *)
(* target_compile_options                                                *)
(* ==================================================================== *)

(* Ref: Tests/CMakeCommands/target_compile_options/CMakeLists.txt
   Covers: genex CXX_COMPILER_ID / COMPILE_LANG_AND_ID scopes, COMPILE_LANGUAGE
   language-dispatch, TARGET_PROPERTY interface propagation.
   DO_GNU_TESTS / DO_CLANG_TESTS guards in sources protect compiler-specific
   checks — skipping those target_compile_definitions calls is safe. *)

let tco_main_source = {|
#ifdef DO_GNU_TESTS
#  ifndef MY_PRIVATE_DEFINE
#    error Expected MY_PRIVATE_DEFINE
#  endif
#  ifndef MY_PUBLIC_DEFINE
#    error Expected MY_PUBLIC_DEFINE
#  endif
#  ifndef MY_MUTLI_COMP_PUBLIC_DEFINE
#    error Expected MY_MUTLI_COMP_PUBLIC_DEFINE
#  endif
#  ifdef MY_INTERFACE_DEFINE
#    error Unexpected MY_INTERFACE_DEFINE
#  endif
#endif
#ifdef DO_CLANG_TESTS
#  ifndef MY_PRIVATE_DEFINE
#    error Expected MY_PRIVATE_DEFINE
#  endif
#  ifdef MY_PUBLIC_DEFINE
#    error Unexpected MY_PUBLIC_DEFINE
#  endif
#  ifndef MY_MUTLI_COMP_PUBLIC_DEFINE
#    error Expected MY_MUTLI_COMP_PUBLIC_DEFINE
#  endif
#endif
int main() { return 0; }
|}

let tco_consumer_cpp_source = {|
#ifdef DO_GNU_TESTS
#  ifdef MY_PRIVATE_DEFINE
#    error Unexpected MY_PRIVATE_DEFINE
#  endif
#  ifndef MY_PUBLIC_DEFINE
#    error Expected MY_PUBLIC_DEFINE
#  endif
#  ifndef MY_INTERFACE_DEFINE
#    error Expected MY_INTERFACE_DEFINE
#  endif
#  ifndef MY_MULTI_COMP_INTERFACE_DEFINE
#    error Expected MY_MULTI_COMP_INTERFACE_DEFINE
#  endif
#  ifndef MY_MUTLI_COMP_PUBLIC_DEFINE
#    error Expected MY_MUTLI_COMP_PUBLIC_DEFINE
#  endif
#endif
#ifdef DO_CLANG_TESTS
#  ifdef MY_PRIVATE_DEFINE
#    error Unexpected MY_PRIVATE_DEFINE
#  endif
#  ifndef MY_MULTI_COMP_INTERFACE_DEFINE
#    error Expected MY_MULTI_COMP_INTERFACE_DEFINE
#  endif
#  ifndef MY_MUTLI_COMP_PUBLIC_DEFINE
#    error Expected MY_MUTLI_COMP_PUBLIC_DEFINE
#  endif
#endif
#ifndef CONSUMER_LANG_CXX
#  error Expected CONSUMER_LANG_CXX
#endif
#ifdef CONSUMER_LANG_C
#  error Unexpected CONSUMER_LANG_C
#endif
#if !LANG_IS_CXX
#  error Expected LANG_IS_CXX
#endif
#if LANG_IS_C
#  error Unexpected LANG_IS_C
#endif
int main() { return 0; }
|}

let tco_consumer_c_source = {|
#ifdef CONSUMER_LANG_CXX
#  error Unexpected CONSUMER_LANG_CXX
#endif
#ifndef CONSUMER_LANG_C
#  error Expected CONSUMER_LANG_C
#endif
#if !LANG_IS_C
#  error Expected LANG_IS_C
#endif
#if LANG_IS_CXX
#  error Unexpected LANG_IS_CXX
#endif
void consumer_c(void) {}
|}

let tco_yelu =
  ESeq [
    yc_project ~languages:[Lang_c; Lang_cxx] "target_compile_options";
    add_exe ~sources:[ystr "main.cpp"] (t "target_compile_options");
    compile_opts (t "target_compile_options") [
      ytarget_def ~kind:Private   [ystr_eval "$<$<CXX_COMPILER_ID:AppleClang,IBMClang,CrayClang,Clang,GNU,LCC>:-DMY_PRIVATE_DEFINE>"];
      ytarget_def ~kind:Public    [ystr_eval "$<$<COMPILE_LANG_AND_ID:CXX,GNU,LCC>:-DMY_PUBLIC_DEFINE>"];
      ytarget_def ~kind:Public    [ystr_eval "$<$<COMPILE_LANG_AND_ID:CXX,GNU,LCC,Clang,AppleClang,CrayClang,IBMClang>:-DMY_MUTLI_COMP_PUBLIC_DEFINE>"];
      ytarget_def ~kind:Interface [ystr_eval "$<$<CXX_COMPILER_ID:GNU,LCC>:-DMY_INTERFACE_DEFINE>"];
      ytarget_def ~kind:Interface [ystr_eval "$<$<CXX_COMPILER_ID:GNU,LCC,Clang,AppleClang,CrayClang,IBMClang>:-DMY_MULTI_COMP_INTERFACE_DEFINE>"];
    ];
    add_exe ~sources:[ystr "consumer.cpp"] (t "consumer");
    yc_target_sources (t "consumer") [ytarget_def ~kind:Private [ystr "consumer.c"]];
    compile_opts (t "consumer") [
      ytarget_def ~kind:Private [
        ystr_eval "-DCONSUMER_LANG_$<COMPILE_LANGUAGE>";
        ystr_eval "-DLANG_IS_CXX=$<COMPILE_LANGUAGE:CXX>";
        ystr_eval "-DLANG_IS_C=$<COMPILE_LANGUAGE:C>";
      ];
    ];
    compile_opts (t "consumer") [
      ytarget_def ~kind:Private [
        ystr_eval "$<$<CXX_COMPILER_ID:GNU,LCC,Clang,AppleClang,CrayClang,IBMClang>:$<TARGET_PROPERTY:target_compile_options,INTERFACE_COMPILE_OPTIONS>>";
      ];
    ];
    compile_opts (t "consumer") [ ytarget_def ~kind:Private [] ];
  ]

(* ==================================================================== *)
(* target_link_directories                                               *)
(* ==================================================================== *)

(* Ref: Tests/CMakeCommands/target_link_directories/CMakeLists.txt
   Covers: PRIVATE/INTERFACE scopes, relative path resolution, subdir target,
   get_target_property assertions via configure exit code.
   subdir/CMakeLists.txt is passed via ~files — mkdirp creates the subdir. *)

let link_dir_lib_source = {|
#if defined(_WIN32)
__declspec(dllexport)
#endif
int flags_lib(void) { return 0; }
|}

let tld_yelu =
  ESeq [
    yc_project ~languages:[Lang_c] "target_link_directories";
    add_lib ~type_:Lib_shared ~sources:[ystr "LinkDirectoriesLib.c"] (t "target_link_directories");
    yc_target_link_directories (t "target_link_directories") [ ytarget_def ~kind:Private [] ];
    add_lib ~type_:Lib_shared ~exclude_from_all:true ~sources:[ystr "LinkDirectoriesLib.c"] (t "target_link_directories_2");
    yc_target_link_directories (t "target_link_directories_2") [
      ytarget_def ~kind:Private   [ystr "/private/dir"];
      ytarget_def ~kind:Interface [ystr "/interface/dir"];
    ];
    yc_get_target_property (ycvar "result") "target_link_directories_2" "LINK_DIRECTORIES";
    yifthen (ynot (ystrequal (ycstr "result") (ystr "/private/dir")))
      (ESeq [ yc_message ~mode:Mm_send_error ["${result} target_link_directories not populated the LINK_DIRECTORIES target property"] ]);
    yc_get_target_property (ycvar "result") "target_link_directories_2" "INTERFACE_LINK_DIRECTORIES";
    yifthen (ynot (ystrequal (ycstr "result") (ystr "/interface/dir")))
      (ESeq [ yc_message ~mode:Mm_send_error ["target_link_directories not populated the INTERFACE_LINK_DIRECTORIES target property of shared library"] ]);
    add_lib ~type_:Lib_static ~exclude_from_all:true ~sources:[ystr "LinkDirectoriesLib.c"] (t "target_link_directories_3");
    yc_target_link_directories (t "target_link_directories_3") [
      ytarget_def ~kind:Interface [ystr "/interface/dir"];
    ];
    yc_get_target_property (ycvar "result") "target_link_directories_3" "INTERFACE_LINK_DIRECTORIES";
    yifthen (ynot (ystrequal (ycstr "result") (ystr "/interface/dir")))
      (ESeq [ yc_message ~mode:Mm_send_error ["target_link_directories not populated the INTERFACE_LINK_DIRECTORIES target property of static library"] ]);
    add_lib ~type_:Lib_shared ~exclude_from_all:true ~sources:[ystr "LinkDirectoriesLib.c"] (t "target_link_directories_4");
    yc_target_link_directories (t "target_link_directories_4") [
      ytarget_def ~kind:Private [ystr "relative/dir"];
    ];
    yc_get_target_property (ycvar "result") "target_link_directories_4" "LINK_DIRECTORIES";
    yifthen (ynot (ystrequal (ycstr "result") (ystr_eval "${CMAKE_CURRENT_SOURCE_DIR}/relative/dir")))
      (ESeq [ yc_message ~mode:Mm_send_error ["target_link_directories not populated the LINK_DIRECTORIES with relative path"] ]);
    yc_add_subdirectory (ystr "subdir");
    yc_target_link_directories (t "target_link_directories_5") [
      ytarget_def ~kind:Private [ystr "relative/dir"];
    ];
    yc_get_target_property (ycvar "result") "target_link_directories_5" "LINK_DIRECTORIES";
    yifthen (ynot (ystrequal (ycstr "result") (ystr_eval "${CMAKE_CURRENT_SOURCE_DIR}/relative/dir")))
      (ESeq [ yc_message ~mode:Mm_send_error ["target_link_directories not populated the LINK_DIRECTORIES with relative path"] ]);
  ]

(* ==================================================================== *)
(* target_compile_features                                               *)
(* ==================================================================== *)

(* Ref: Tests/CMakeCommands/target_compile_features/CMakeLists.txt
   Covers: c_restrict/c_std_99/cxx_auto_type/cxx_std_11 features gated on
   CMAKE_*_COMPILE_FEATURES. Both sides use identical if() conditions, so
   whichever branches fire on the ref will fire identically on yelu → artifact
   names always match regardless of the compiler's feature set. *)

let tcf_main_c_source = {|
int foo(int* restrict a, int* restrict b)
{
  (void)a; (void)b;
  return 0;
}
int main(void) { return 0; }
|}

let tcf_lib_restrict_h = {|
#ifndef LIB_RESTRICT_H
#define LIB_RESTRICT_H
int foo(int* restrict a, int* restrict b);
#endif
|}

let tcf_lib_restrict_c = {|
#include "lib_restrict.h"
int foo(int* restrict a, int* restrict b)
{ (void)a; (void)b; return 0; }
|}

let tcf_restrict_user_c = {|
#include "lib_restrict.h"
int bar(int* restrict a, int* restrict b) { (void)a; (void)b; return foo(a, b); }
int main(void) { return 0; }
|}

let tcf_main_cpp_source = {|
int main(int, char**) { auto i = 0; return i; }
|}

let tcf_lib_auto_type_h = {|
int getAutoTypeImpl();
inline int getAutoType() { auto i = getAutoTypeImpl(); return i; }
|}

let tcf_lib_auto_type_cpp = {|
int getAutoTypeImpl() { auto i = 0; return i; }
|}

let tcf_lib_user_cpp = {|
#include "lib_auto_type.h"
int main(int, char**) { return getAutoType(); }
|}

let tcf_yelu =
  ESeq [
    yc_minimum_required_s "3.10";
    yc_project ~languages:[Lang_c; Lang_cxx] "target_compile_features";
    yifthen (yin_list (ystr "c_restrict") (ycstr "CMAKE_C_COMPILE_FEATURES"))
      (ESeq [
        add_exe ~sources:[ystr "main.c"] (t "c_target_compile_features_specific");
        compile_feats (t "c_target_compile_features_specific") [ytarget_feature ~kind:Private "c_restrict"];
        add_lib ~sources:[ystr "lib_restrict.c"] (t "c_lib_restrict_specific");
        compile_feats (t "c_lib_restrict_specific") [ytarget_feature ~kind:Public "c_restrict"];
        add_exe ~sources:[ystr "restrict_user.c"] (t "c_restrict_user_specific");
        link_lib [t "c_restrict_user_specific"] [ytarget_def ~kind:Plain [ytval "c_lib_restrict_specific"]];
      ]);
    yifthen (yand (yin_list (ystr "c_std_99") (ycstr "CMAKE_C_COMPILE_FEATURES")) (ynot (ystrequal (ycstr "CMAKE_C_COMPILER_ID") (ystr "MSVC"))))
      (ESeq [
        add_exe ~sources:[ystr "main.c"] (t "c_target_compile_features_meta");
        compile_feats (t "c_target_compile_features_meta") [ytarget_feature ~kind:Private "c_std_99"];
        add_lib ~sources:[ystr "lib_restrict.c"] (t "c_lib_restrict_meta");
        compile_feats (t "c_lib_restrict_meta") [ytarget_feature ~kind:Public "c_std_99"];
        add_exe ~sources:[ystr "restrict_user.c"] (t "c_restrict_user_meta");
        link_lib [t "c_restrict_user_meta"] [ytarget_def ~kind:Plain [ytval "c_lib_restrict_meta"]];
      ]);
    yifthen (yin_list (ystr "cxx_auto_type") (ycstr "CMAKE_CXX_COMPILE_FEATURES"))
      (ESeq [
        add_exe ~sources:[ystr "main.cpp"] (t "cxx_target_compile_features_specific");
        compile_feats (t "cxx_target_compile_features_specific") [ytarget_feature ~kind:Private "cxx_auto_type"];
        add_lib ~sources:[ystr "lib_auto_type.cpp"] (t "cxx_lib_auto_type_specific");
        compile_feats (t "cxx_lib_auto_type_specific") [ytarget_feature ~kind:Public "cxx_auto_type"];
        add_exe ~sources:[ystr "lib_user.cpp"] (t "cxx_lib_user_specific");
        link_lib [t "cxx_lib_user_specific"] [ytarget_def ~kind:Plain [ytval "cxx_lib_auto_type_specific"]];
      ]);
    yifthen (yin_list (ystr "cxx_std_11") (ycstr "CMAKE_CXX_COMPILE_FEATURES"))
      (ESeq [
        add_exe ~sources:[ystr "main.cpp"] (t "cxx_target_compile_features_meta");
        compile_feats (t "cxx_target_compile_features_meta") [ytarget_feature ~kind:Private "cxx_std_11"];
        add_lib ~sources:[ystr "lib_auto_type.cpp"] (t "cxx_lib_auto_type_meta");
        compile_feats (t "cxx_lib_auto_type_meta") [ytarget_feature ~kind:Public "cxx_std_11"];
        add_exe ~sources:[ystr "lib_user.cpp"] (t "cxx_lib_user_meta");
        link_lib [t "cxx_lib_user_meta"] [ytarget_def ~kind:Plain [ytval "cxx_lib_auto_type_meta"]];
      ]);
  ]

(* ==================================================================== *)
(* target_sources                                                        *)
(* ==================================================================== *)

(* Ref: Tests/CMakeCommands/target_sources/CMakeLists.txt
   Covers: CMP0076=NEW (relative→absolute path conversion), genex-wrapped
   source paths, cross-dir target_sources, SOURCES property IN_LIST assertions. *)

let ts_main_cpp = {|
#include <iostream>
int empty_1(); int subdir_empty_1(); int subdir_empty_2();
int main() {
  std::cout << empty_1() << " " << subdir_empty_1() << " " << subdir_empty_2() << std::endl;
  return 0;
}
|}

let ts_empty_1_cpp = {|
#ifdef IS_LIB
int internal_empty_1() { return 0; }
#else
int empty_1() { return 0; }
#endif
|}

let ts_empty_2_cpp = {|int empty_2() { return 0; }|}
let ts_empty_3_cpp = {|int empty_3() { return 0; }|}

let ts_subdir_empty_1_cpp = {|
#ifdef IS_LIB
int internal_subdir_empty_1() { return 0; }
#else
int subdir_empty_1() { return 0; }
#endif
|}

let ts_subdir_empty_2_cpp = {|
#ifdef IS_LIB
int internal_subdir_empty_2() { return 0; }
#else
int subdir_empty_2() { return 0; }
#endif
|}

(* subdir/CMakeLists.txt: adds sources to parent target_sources_lib via target_sources *)
let ts_subdir_cmake = {|target_sources(target_sources_lib PUBLIC $<1:${CMAKE_CURRENT_LIST_DIR}/subdir_empty_1.cpp>
                                         $<1:${CMAKE_CURRENT_LIST_DIR}/../empty_1.cpp>
                                         subdir_empty_2.cpp
                                  PRIVATE $<1:empty_2.cpp>
                                          ../empty_3.cpp)|}

let ts_yelu =
  ESeq [
    yc_minimum_required_s "3.12";
    yc_policy_set "CMP0076";
    yc_project ~languages:[Lang_cxx] "target_sources";
    add_lib (t "target_sources_lib");
    compile_defs (t "target_sources_lib") [ytarget_def ~kind:Private [ystr "-DIS_LIB"]];
    yc_add_subdirectory (ystr "subdir");
    yc_set (ycvar "subdir_fullpath") [ystr_eval "${CMAKE_CURRENT_LIST_DIR}/subdir"];
    yc_get_target_property (ycvar "target_sources_lib_property") "target_sources_lib" "SOURCES";
    yifthen (ynot (yin_list (ystr_eval "$<1:${subdir_fullpath}/subdir_empty_1.cpp>") (ycstr "target_sources_lib_property")))
      (ESeq [ yc_message ~mode:Mm_send_error ["target_sources_lib: Generator expression to absolute sub directory file not found"] ]);
    yifthen (ynot (yin_list (ystr_eval "$<1:${subdir_fullpath}/../empty_1.cpp>") (ycstr "target_sources_lib_property")))
      (ESeq [ yc_message ~mode:Mm_send_error ["target_sources_lib: Generator expression to absolute main directory file not found"] ]);
    yifthen (ynot (yin_list (ystr_eval "${subdir_fullpath}/subdir_empty_2.cpp") (ycstr "target_sources_lib_property")))
      (ESeq [ yc_message ~mode:Mm_send_error ["target_sources_lib: Relative sub directory file not converted to absolute"] ]);
    yifthen (ynot (yin_list (ystr_eval "$<1:empty_2.cpp>") (ycstr "target_sources_lib_property")))
      (ESeq [ yc_message ~mode:Mm_send_error ["target_sources_lib: Generator expression to relative main directory file not found"] ]);
    yifthen (ynot (yin_list (ystr_eval "${subdir_fullpath}/../empty_3.cpp") (ycstr "target_sources_lib_property")))
      (ESeq [ yc_message ~mode:Mm_send_error ["target_sources_lib: Relative main directory file not converted to absolute"] ]);
    add_exe ~sources:[ystr "main.cpp"] (t "target_sources");
    link_lib [t "target_sources"] [ytarget_def ~kind:Plain [ytval "target_sources_lib"]];
    yc_get_target_property (ycvar "target_sources_property") "target_sources" "SOURCES";
    yifthen (ynot (yin_list (ystr "main.cpp") (ycstr "target_sources_property")))
      (ESeq [ yc_message ~mode:Mm_send_error ["target_sources: Relative main directory file converted to absolute"] ]);
  ]

(* ==================================================================== *)
(* target_include_directories                                            *)
(* ==================================================================== *)

(* Ref: Tests/CMakeCommands/target_include_directories/CMakeLists.txt
   Covers: PRIVATE/PUBLIC/INTERFACE/BEFORE/SYSTEM scopes, genex include paths,
   binary-dir header generation, header-order (same.h BEFORE override),
   include_directories must NOT populate imported target's INCLUDE_DIRECTORIES. *)

let tid_main_cpp = {|
#include "common.h"
#include "privateinclude.h"
#include "publicinclude.h"
#ifndef PRIVATEINCLUDE_DEFINE
#  error Expected PRIVATEINCLUDE_DEFINE
#endif
#ifndef PUBLICINCLUDE_DEFINE
#  error Expected PUBLICINCLUDE_DEFINE
#endif
#ifdef INTERFACEINCLUDE_DEFINE
#  error Unexpected INTERFACEINCLUDE_DEFINE
#endif
#ifndef CURE_DEFINE
#  error Expected CURE_DEFINE
#endif
int main() { return 0; }
|}

let tid_consumer_cpp = {|
#include "consumer.h"
#include "common.h"
#include "cxx_only.h"
#include "interfaceinclude.h"
#include "publicinclude.h"
#include "relative_dir.h"
#ifdef PRIVATEINCLUDE_DEFINE
#  error Unexpected PRIVATEINCLUDE_DEFINE
#endif
#ifndef PUBLICINCLUDE_DEFINE
#  error Expected PUBLICINCLUDE_DEFINE
#endif
#ifndef INTERFACEINCLUDE_DEFINE
#  error Expected INTERFACEINCLUDE_DEFINE
#endif
#ifndef CURE_DEFINE
#  error Expected CURE_DEFINE
#endif
#ifndef RELATIVE_DIR_DEFINE
#  error Expected RELATIVE_DIR_DEFINE
#endif
#ifndef CONSUMER_DEFINE
#  error Expected CONSUMER_DEFINE
#endif
#ifndef CXX_ONLY_DEFINE
#  error Expected CXX_ONLY_DEFINE
#endif
int main() { return 0; }
|}

let tid_consumer_c = {|
#ifdef TEST_LANG_DEFINES_FOR_VISUAL_STUDIO_OR_XCODE
#  include "cxx_only.h"
#  ifndef CXX_ONLY_DEFINE
#    error Expected CXX_ONLY_DEFINE
#  endif
#else
#  include "c_only.h"
#  ifndef C_ONLY_DEFINE
#    error Expected C_ONLY_DEFINE
#  endif
#endif
int consumer_c(void) { return 0; }
|}

let tid_same_c = {|
#include "same.h"
#ifndef CORRECT_SAME_H_INCLUDED
#  error "Correct \"same.h\" not included!"
#endif
void same(void) {}
|}

let tid_yelu =
  let bindir = "${CMAKE_CURRENT_BINARY_DIR}" in
  ESeq [
    yc_project ~languages:[Lang_c; Lang_cxx] "target_include_directories";
    (* generate binary-dir headers at configure time *)
    yc_file_make_directory [ystr_eval (bindir ^ "/privateinclude")];
    yc_file_write (ystr_eval (bindir ^ "/privateinclude/privateinclude.h"))
      [ystr "#define PRIVATEINCLUDE_DEFINE\n"];
    yc_file_make_directory [ystr_eval (bindir ^ "/publicinclude")];
    yc_file_write (ystr_eval (bindir ^ "/publicinclude/publicinclude.h"))
      [ystr "#define PUBLICINCLUDE_DEFINE\n"];
    yc_file_make_directory [ystr_eval (bindir ^ "/interfaceinclude")];
    yc_file_write (ystr_eval (bindir ^ "/interfaceinclude/interfaceinclude.h"))
      [ystr "#define INTERFACEINCLUDE_DEFINE\n"];
    yc_file_make_directory [ystr_eval (bindir ^ "/poison")];
    yc_file_write (ystr_eval (bindir ^ "/poison/common.h"))
      [ystr "#error Should not be included\n"];
    yc_file_make_directory [ystr_eval (bindir ^ "/cure")];
    yc_file_write (ystr_eval (bindir ^ "/cure/common.h"))
      [ystr "#define CURE_DEFINE\n"];
    (* main exe: PRIVATE/PUBLIC/INTERFACE include dirs *)
    add_exe ~sources:[ystr "main.cpp"] (t "target_include_directories");
    include_dirs (t "target_include_directories") [
      ytarget_def ~kind:Private   [ystr_eval (bindir ^ "/privateinclude")];
      ytarget_def ~kind:Public    [ystr_eval (bindir ^ "/publicinclude")];
      ytarget_def ~kind:Interface [ystr_eval (bindir ^ "/interfaceinclude")];
    ];
    include_dirs (t "target_include_directories") [
      ytarget_def ~kind:Public [ystr_eval (bindir ^ "/poison")];
    ];
    (* BEFORE PUBLIC with genex: cure overrides poison for EXECUTABLE type *)
    include_dirs ~before:true (t "target_include_directories") [
      ytarget_def ~kind:Public [ystr_eval {|$<$<STREQUAL:$<TARGET_PROPERTY:target_include_directories,TYPE>,EXECUTABLE>:${CMAKE_CURRENT_BINARY_DIR}/cure>|}];
    ];
    (* no effect: SHARED_LIBRARY type never matches for exe *)
    include_dirs ~before:true (t "target_include_directories") [
      ytarget_def ~kind:Public [ystr_eval {|$<$<STREQUAL:$<TARGET_PROPERTY:target_include_directories,TYPE>,SHARED_LIBRARY>:${CMAKE_CURRENT_BINARY_DIR}/poison>|}];
    ];
    (* consumer exe: CXX/C language-dispatched include dirs *)
    add_exe ~sources:[ystr "consumer.cpp"] (t "consumer");
    yc_target_sources (t "consumer") [ytarget_def ~kind:Private [ystr "consumer.c"]];
    include_dirs (t "consumer") [
      ytarget_def ~kind:Private [
        ystr_eval "$<$<COMPILE_LANGUAGE:CXX>:${CMAKE_CURRENT_SOURCE_DIR}/cxx_only>";
        ystr_eval "$<$<COMPILE_LANGUAGE:C>:${CMAKE_CURRENT_SOURCE_DIR}/c_only>";
      ];
    ];
    include_dirs (t "consumer") [
      ytarget_def ~kind:Private [
        ystr_eval "$<TARGET_PROPERTY:target_include_directories,INTERFACE_INCLUDE_DIRECTORIES>";
        ystr "relative_dir";
        ystr_eval "relative_dir/$<TARGET_PROPERTY:NAME>";
      ];
    ];
    (* empty PRIVATE / BEFORE PRIVATE / SYSTEM BEFORE PRIVATE / SYSTEM PRIVATE *)
    include_dirs (t "consumer") [ ytarget_def ~kind:Private [] ];
    include_dirs ~before:true (t "consumer") [ ytarget_def ~kind:Private [] ];
    include_dirs ~before:true ~system:true (t "consumer") [ ytarget_def ~kind:Private [] ];
    include_dirs ~system:true (t "consumer") [ ytarget_def ~kind:Private [] ];
    (* global include_directories: must NOT populate imported target's property *)
    yc_include_directories [ystr_eval "${CMAKE_CURRENT_BINARY_DIR}"];
    add_lib_imported ~lib_type:"UNKNOWN" (t "imp");
    yc_get_target_property (ycvar "_res") "imp" "INCLUDE_DIRECTORIES";
    yifthen (ytruthy (ycstr "_res"))
      (ESeq [ yc_message ~mode:Mm_send_error ["include_directories populated the INCLUDE_DIRECTORIES target property"] ]);
    (* same: header-order test — same_two wins over same_one via PRIVATE include dir *)
    add_lib ~type_:Lib_static
      ~sources:[ystr "same.c"; ystr "same_one/same.h"; ystr "same_two/same.h"]
      (t "same");
    include_dirs (t "same") [ ytarget_def ~kind:Private [ystr "same_two"] ];
  ]

(* ==================================================================== *)
(* Group 2 — Tests/LibName                                              *)
(* ==================================================================== *)

(* Tests LIBRARY_OUTPUT_PATH / EXECUTABLE_OUTPUT_PATH and VERSION/SOVERSION.
   if(UNIX) block emitted unconditionally (always true on Linux). *)

let libname_bar_c = {|
#ifdef _WIN32
__declspec(dllexport)
#endif
extern void foo(void) {}
|}

let libname_foo_c = {|
#ifdef _WIN32
__declspec(dllimport)
#endif
extern void foo(void);
#ifdef _WIN32
__declspec(dllexport)
#endif
void bar(void) { foo(); }
|}

let libname_foobar_c = {|
#ifdef _WIN32
__declspec(dllimport)
#endif
extern void bar();
int main(void) { bar(); return 0; }
|}

let libname_yelu =
  ESeq [
    yc_minimum_required_s "3.10";
    yc_project ~languages:[Lang_c] "LibName";
    yc_set (ycvar "LIBRARY_OUTPUT_PATH") [ystr "lib"];
    yc_set (ycvar "EXECUTABLE_OUTPUT_PATH") [ystr "lib"];
    add_lib ~type_:Lib_shared ~sources:[ystr "bar.c"] (t "bar");
    add_lib ~type_:Lib_shared ~sources:[ystr "foo.c"] (t "foo");
    link_lib [t "foo"] [ytarget_def ~kind:Plain [ytval "bar"]];
    add_exe ~sources:[ystr "foobar.c"] (t "foobar");
    link_lib [t "foobar"] [ytarget_def ~kind:Plain [ytval "foo"]];
    yifthen (ytruthy (ycstr "UNIX"))
      (ESeq [ link_lib [t "foobar"] [ytarget_def ~kind:Plain [ystr "-L/usr/local/lib"]] ]);
    add_lib ~type_:Lib_shared ~sources:[ystr "foo.c"] (t "verFoo");
    link_lib [t "verFoo"] [ytarget_def ~kind:Plain [ytval "bar"]];
    yc_set_target_properties (t "verFoo")
      [("VERSION", ystr "3.1.4"); ("SOVERSION", ystr "3")];
    add_exe ~sources:[ystr "foobar.c"] (t "verFoobar");
    link_lib [t "verFoobar"] [ytarget_def ~kind:Plain [ytval "verFoo"]];
    (* if(MAKE_SUPPORTS_SPACES ...) block omitted: MAKE_SUPPORTS_SPACES not set *)
  ]

(* ==================================================================== *)
(* Group 2 — Tests/LinkStatic                                           *)
(* ==================================================================== *)

(* Static-links against libm.a. find_library / LINK_FLAGS / LINK_SEARCH_*
   have no typed yelu equivalents — use quote_cmd throughout. *)

let link_static_main_c = {|
#include <math.h>
int main(void) { return (int)sin(0); }
|}

let link_static_yelu =
  ESeq [
    yc_minimum_required_s "3.10";
    yifthen (ypolicy_defined "CMP0129") (ESeq [ yc_policy_set "CMP0129" ]);
    yc_project ~languages:[Lang_c] "LinkStatic";
    yifthen (ynot (ymatches (ycstr "CMAKE_C_COMPILER_ID") ("GNU|LCC")))
      (ESeq [ yc_message ~mode:Mm_fatal_error ["This test works only with the GNU or LCC compiler!"] ]);
    yc_find_library ~names:[ystr "libm.a"] (ycvar "MATH_LIBRARY");
    yif (ytruthy (ycstr "MATH_LIBRARY"))
      (ESeq [
        yc_get_filename_component ~mode:"PATH" (ycvar "MATH_LIB_DIR") (ycstr "MATH_LIBRARY");
        yc_link_directories [ystr_eval "${MATH_LIB_DIR}"];
        yc_set (ycvar "MATH_LIBRARIES") [ystr_eval "${MATH_LIBRARY}"; ystr "-lm"];
      ])
      (ESeq [ yc_message ~mode:Mm_fatal_error ["Cannot find libm.a needed for this test"] ]);
    add_exe ~sources:[ystr "LinkStatic.c"] (t "LinkStatic");
    link_lib [t "LinkStatic"]
      [ytarget_def ~kind:Plain [ystr_eval "${MATH_LIBRARIES}"]];
    yc_set_cache (ycvar "LinkStatic_FLAG") [ystr "-static"] ~cache_type:Ct_string
      ~docstring:"Flag to link statically";
    yc_set_target_properties (ytval "LinkStatic")
      [ ("LINK_FLAGS", ystr_eval "${LinkStatic_FLAG}");
        ("LINK_SEARCH_START_STATIC", ystr "1") ];
  ]

(* ==================================================================== *)
(* Group 2 — Tests/Simple                                               *)
(* ==================================================================== *)

let simple_simple_cxx = {|
extern void simpleLib();
extern "C" int FooBar();
extern int bar();
extern int bar1();
int main()
{
  FooBar();
  bar();
  simpleLib();
  return 0;
}
|}

let simple_simplelib_cxx = {|
void simpleLib()
{
}
|}

let simple_simpleclib_c = {|
#include <stdio.h>
int FooBar(void)
{
  int class;
  int private = 10;
  for (class = 0; class < private; class ++) {
    printf("Count: %d/%d\n", class, private);
  }
  return 0;
}
|}

let simple_simplewe_cpp = {|
#include <stdio.h>
class Foo
{
public:
  Foo() { printf("This one has nonstandard extension\n"); }
  int getnum() { return 0; }
};
int bar()
{
  Foo f;
  return f.getnum();
}
|}

let simple_yelu =
  ESeq [
    yc_project ~languages:[Lang_cxx; Lang_c] "Simple";
    add_exe ~sources:[ystr "simple.cxx"] (t "Simple");
    add_lib ~type_:Lib_static
      ~sources:[ystr "simpleLib.cxx"; ystr "simpleCLib.c"; ystr "simpleWe.cpp"]
      (t "simpleLib");
    link_lib [t "Simple"] [ytarget_def ~kind:Plain [ytval "simpleLib"]];
  ]

(* ==================================================================== *)
(* Group 2 — Tests/LinkLine                                             *)
(* ==================================================================== *)

(* One.c and Two.c are mutually recursive via static guards. *)
let ll_one_c = {|
void TwoFunc(void);
void OneFunc(void)
{
  static int i = 0;
  ++i;
  if (i == 1) { TwoFunc(); }
}
|}

let ll_two_c = {|
void OneFunc(void);
void TwoFunc(void)
{
  static int i = 0;
  ++i;
  if (i == 1) { OneFunc(); }
}
|}

let ll_exec_c = {|
void OneFunc();
void TwoFunc();
int main(void) { OneFunc(); TwoFunc(); return 0; }
|}

(* link_libraries() is the global (legacy) form — emit via quote_cmd. *)
let ll_yelu =
  ESeq [
    yc_minimum_required_s "3.10";
    yc_project ~languages:[Lang_c] "LinkLine";
    add_lib ~sources:[ystr "One.c"] (t "One");
    add_lib ~sources:[ystr "Two.c"] (t "Two");
    yc_link_libraries [ytval "One"; ytval "Two"];
    add_exe ~sources:[ystr "Exec.c"] (t "LinkLine");
  ]

(* ==================================================================== *)
(* Group 2 — Tests/LinkLineOrder                                        *)
(* ==================================================================== *)

let llo_nodep_a_c = {|void NoDepB_func(void); void NoDepA_func(void) { NoDepB_func(); }|}
let llo_nodep_b_c = {|void NoDepB_func(void) {}|}
let llo_nodep_c_c = {|void NoDepA_func(void); void NoDepC_func(void) { NoDepA_func(); }|}
let llo_nodep_e_c = {|
void NoDepF_func(void);
void NoDepE_func(void) {
  static int first = 1;
  if (first) { first = 0; NoDepF_func(); }
}
|}
let llo_nodep_f_c = {|
void NoDepE_func(void);
void NoDepF_func(void) {
  static int first = 1;
  if (first) { first = 0; NoDepE_func(); }
}
|}
let llo_nodep_x_c = {|void NoDepY_func(void); void NoDepX_func(void) { NoDepY_func(); }|}
let llo_nodep_y_c = {|void NoDepY_func(void) {}|}
let llo_nodep_z_c = {|void NoDepX_func(void); void NoDepZ_func(void) { NoDepX_func(); }|}
let llo_one_c = {|
void NoDepC_func(void); void NoDepE_func(void);
void OneFunc(void) { NoDepC_func(); NoDepE_func(); }
|}
let llo_two_c = {|
void OneFunc(void); void NoDepZ_func(void);
void TwoFunc(void) { OneFunc(); NoDepZ_func(); }
|}
let llo_exec1_c = {|void OneFunc(); int main(void) { OneFunc(); return 0; }|}
let llo_exec2_c = {|void TwoFunc(); int main(void) { TwoFunc(); return 0; }|}

let llo_yelu =
  ESeq [
    yc_minimum_required_s "3.10";
    yc_project ~languages:[Lang_c] "LinkLineOrder";
    add_lib ~sources:[ystr "NoDepA.c"] (t "NoDepA");
    add_lib ~sources:[ystr "NoDepB.c"] (t "NoDepB");
    add_lib ~sources:[ystr "NoDepC.c"] (t "NoDepC");
    add_lib ~sources:[ystr "NoDepE.c"] (t "NoDepE");
    add_lib ~sources:[ystr "NoDepF.c"] (t "NoDepF");
    add_lib ~sources:[ystr "One.c"] (t "One");
    link_lib [t "One"]
      [ytarget_def ~kind:Plain [ytval "NoDepC"; ytval "NoDepA"; ytval "NoDepB";
                                ytval "NoDepE"; ytval "NoDepF"; ytval "NoDepE"]];
    add_exe ~sources:[ystr "Exec1.c"] (t "Exec1");
    link_lib [t "Exec1"] [ytarget_def ~kind:Plain [ytval "One"]];
    add_lib ~sources:[ystr "NoDepX.c"] (t "NoDepX");
    add_lib ~sources:[ystr "NoDepY.c"] (t "NoDepY");
    add_lib ~sources:[ystr "NoDepZ.c"] (t "NoDepZ");
    add_lib ~sources:[ystr "Two.c"] (t "Two");
    link_lib [t "Two"]
      [ytarget_def ~kind:Plain [ytval "One"; ytval "NoDepZ";
                                ytval "NoDepX"; ytval "NoDepY"]];
    add_exe ~sources:[ystr "Exec2.c"] (t "Exec2");
    link_lib [t "Exec2"] [ytarget_def ~kind:Plain [ytval "Two"]];
  ]

(* ==================================================================== *)
(* Group 2 — Tests/OutName                                              *)
(* ==================================================================== *)

(* Tests OUTPUT_NAME prefix/suffix overrides on an executable target. *)
let out_name_yelu =
  ESeq [
    yc_minimum_required_s "3.12";
    yc_project ~languages:[Lang_c] "OutName";
    add_exe ~sources:[ystr "main.c"] (t "OutName");
    yc_set_target_properties (t "OutName")
      [("PREFIX", ystr "exe."); ("SUFFIX", ystr ".exe")];
  ]

(* ==================================================================== *)
(* Group 3 — Tests/EmptyLibrary                                         *)
(* ==================================================================== *)

(* Root adds one subdir; subdir adds a header-only static library.
   The resulting libtest.a is empty (no object files). *)
let _empty_lib_yelu =
  ESeq [
    yc_minimum_required_s "3.10";
    yc_project "TestEmptyLibrary";
    yc_add_subdirectory (ystr "subdir");
  ]

(* ==================================================================== *)
(* Group 3 — Tests/TargetName                                           *)
(* ==================================================================== *)

(* Two subdirs: executables/ builds hello_world exe; scripts/ custom-copies
   a shell script to the binary dir (always runs because we use out-of-source). *)
let target_name_hello_world_c = {|
#include <stdio.h>
int main(void) { printf("hello, world\n"); return 0; }
|}

let target_name_scripts_cmake = {|
if(NOT CMAKE_BINARY_DIR STREQUAL "${CMAKE_SOURCE_DIR}")
  add_custom_command(
    OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/hello_world
    COMMAND ${CMAKE_COMMAND} -E copy
      ${CMAKE_CURRENT_SOURCE_DIR}/hello_world ${CMAKE_CURRENT_BINARY_DIR}
    DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/hello_world
  )
  add_custom_target(
    hello_world_copy ALL
    DEPENDS
    ${CMAKE_CURRENT_BINARY_DIR}/hello_world
  )
endif()
|}

let target_name_yelu =
  ESeq [
    yc_minimum_required_s "3.10";
    yc_project ~languages:[Lang_c] "TargetName";
    yc_add_subdirectory (ystr "executables");
    yc_add_subdirectory (ystr "scripts");
  ]

(* ==================================================================== *)
(* Group 3 — Tests/CompileDefinitions                                   *)
(* ==================================================================== *)

(* Root cmake uses foreach+set for per-config flags and set_property(DIRECTORY).
   Three subdirs each build an executable from ../compiletest.cpp.
   All subdir cmake content is embedded verbatim; root uses quote_cmd. *)

let cd_compiletest_cpp = {|
#ifndef CMAKE_IS_FUN
#  error Expect CMAKE_IS_FUN definition
#endif
#if CMAKE_IS != Fun
#  error Expect CMAKE_IS=Fun definition
#endif
template <bool test> struct CMakeStaticAssert;
template <> struct CMakeStaticAssert<true> {};
static char const fun_string[] = CMAKE_IS_;
#ifndef NO_SPACES_IN_DEFINE_VALUES
static char const very_fun_string[] = CMAKE_IS_REALLY;
#endif
enum {
  StringLiteralTest1 = sizeof(CMakeStaticAssert<sizeof(CMAKE_IS_) == sizeof("Fun")>),
#ifndef NO_SPACES_IN_DEFINE_VALUES
  StringLiteralTest2 = sizeof(CMakeStaticAssert<sizeof(CMAKE_IS_REALLY) == sizeof("Very Fun")>),
#endif
#ifdef TEST_GENERATOR_EXPRESSIONS
  StringLiteralTest3 = sizeof(CMakeStaticAssert<sizeof(LETTER_LIST1) == sizeof("A,B,C,D")>),
  StringLiteralTest4 = sizeof(CMakeStaticAssert<sizeof(LETTER_LIST2) == sizeof("A,,B,,C,,D")>),
  StringLiteralTest5 = sizeof(CMakeStaticAssert<sizeof(LETTER_LIST3) == sizeof("A,-B,-C,-D")>),
  StringLiteralTest6 = sizeof(CMakeStaticAssert<sizeof(LETTER_LIST4) == sizeof("A-,-B-,-C-,-D")>),
  StringLiteralTest7 = sizeof(CMakeStaticAssert<sizeof(LETTER_LIST5) == sizeof("A-,B-,C-,D")>)
#endif
};
#ifdef TEST_GENERATOR_EXPRESSIONS
#  ifndef CMAKE_IS_DECLARATIVE
#    error Expect declarative definition
#  endif
#  ifdef GE_NOT_DEFINED
#    error Expect not defined generator expression
#  endif
#  ifndef ARGUMENT
#    error Expected define expanded from list
#  endif
#  ifndef LIST
#    error Expected define expanded from list
#  endif
#  ifndef PREFIX_DEF1
#    error Expect PREFIX_DEF1
#  endif
#  ifndef PREFIX_DEF2
#    error Expect PREFIX_DEF2
#  endif
#  ifndef LINK_CXX_DEFINE
#    error Expected LINK_CXX_DEFINE
#  endif
#  ifndef LINK_LANGUAGE_IS_CXX
#    error Expected LINK_LANGUAGE_IS_CXX
#  endif
#  ifdef LINK_C_DEFINE
#    error Unexpected LINK_C_DEFINE
#  endif
#  ifdef LINK_LANGUAGE_IS_C
#    error Unexpected LINK_LANGUAGE_IS_C
#  endif
#endif
#ifndef BUILD_IS_DEBUG
#  error "BUILD_IS_DEBUG not defined!"
#endif
#ifndef BUILD_IS_NOT_DEBUG
#  error "BUILD_IS_NOT_DEBUG not defined!"
#endif
#ifdef TEST_CONFIG_DEBUG
#  if !BUILD_IS_DEBUG
#    error "BUILD_IS_DEBUG false with TEST_CONFIG_DEBUG!"
#  endif
#  if BUILD_IS_NOT_DEBUG
#    error "BUILD_IS_NOT_DEBUG true with TEST_CONFIG_DEBUG!"
#  endif
#else
#  if BUILD_IS_DEBUG
#    error "BUILD_IS_DEBUG true without TEST_CONFIG_DEBUG!"
#  endif
#  if !BUILD_IS_NOT_DEBUG
#    error "BUILD_IS_NOT_DEBUG false without TEST_CONFIG_DEBUG!"
#  endif
#endif
int main(int argc, char** argv) { return 0; }
|}

let cd_compiletest_c = {|
#ifndef LINK_C_DEFINE
#  error Expected LINK_C_DEFINE
#endif
#ifndef LINK_LANGUAGE_IS_C
#  error Expected LINK_LANGUAGE_IS_C
#endif
#ifdef LINK_CXX_DEFINE
#  error Unexpected LINK_CXX_DEFINE
#endif
#ifdef LINK_LANGUAGE_IS_CXX
#  error Unexpected LINK_LANGUAGE_IS_CXX
#endif
int main(void) { return 0; }
|}

let cd_compiletest_mixed_c = {|
#ifndef LINK_CXX_DEFINE
#  error Expected LINK_CXX_DEFINE
#endif
#ifndef LINK_LANGUAGE_IS_CXX
#  error Expected LINK_LANGUAGE_IS_CXX
#endif
#ifdef LINK_C_DEFINE
#  error Unexpected LINK_C_DEFINE
#endif
#ifdef LINK_LANGUAGE_IS_C
#  error Unexpected LINK_LANGUAGE_IS_C
#endif
#ifndef C_EXECUTABLE_LINK_LANGUAGE_IS_C
#  error Expected C_EXECUTABLE_LINK_LANGUAGE_IS_C define
#endif
void someFunc(void) {}
|}

let cd_compiletest_mixed_cxx = {|
#ifndef LINK_CXX_DEFINE
#  error Expected LINK_CXX_DEFINE
#endif
#ifndef LINK_LANGUAGE_IS_CXX
#  error Expected LINK_LANGUAGE_IS_CXX
#endif
#ifdef LINK_C_DEFINE
#  error Unexpected LINK_C_DEFINE
#endif
#ifdef LINK_LANGUAGE_IS_C
#  error Unexpected LINK_LANGUAGE_IS_C
#endif
#ifndef C_EXECUTABLE_LINK_LANGUAGE_IS_C
#  error Expected C_EXECUTABLE_LINK_LANGUAGE_IS_C define
#endif
int main(int argc, char** argv) { return 0; }
|}

let cd_usetgt_c = {|
#ifndef TGT_DEF
#  error TGT_DEF incorrectly not defined
#endif
#ifndef TGT_TYPE_STATIC_LIBRARY
#  error TGT_TYPE_STATIC_LIBRARY incorrectly not defined
#endif
#ifdef TGT_TYPE_EXECUTABLE
#  error TGT_TYPE_EXECUTABLE incorrectly defined
#endif
int main(void) { return 0; }
|}

let cd_add_def_cmd_cmake = {|
add_definitions(-DCMAKE_IS_FUN -DCMAKE_IS=Fun -DCMAKE_IS_="Fun")
if(NOT NO_SPACES_IN_DEFINE_VALUES)
  add_definitions(-DCMAKE_IS_REALLY="Very Fun")
endif()
add_definitions(-DCMAKE_IS_="Fun")
if(NOT NO_SPACES_IN_DEFINE_VALUES)
  add_definitions(-DCMAKE_IS_REALLY="Very Fun")
endif()
add_definitions(-DCMAKE_IS_FUN -DCMAKE_IS=Fun)
add_definitions(-DBUILD_IS_DEBUG=$<CONFIG:Debug> -DBUILD_IS_NOT_DEBUG=$<NOT:$<CONFIG:Debug>>)
add_executable(add_def_cmd_exe ../compiletest.cpp)
|}

let cd_target_prop_cmake = {|
project(target_prop)
add_executable(target_prop_executable ../compiletest.cpp)
set_target_properties(target_prop_executable PROPERTIES COMPILE_DEFINITIONS CMAKE_IS_FUN)
if(NOT NO_SPACES_IN_DEFINE_VALUES)
  set_property(TARGET target_prop_executable APPEND PROPERTY COMPILE_DEFINITIONS CMAKE_IS_REALLY="Very Fun" CMAKE_IS=Fun)
else()
  set_property(TARGET target_prop_executable APPEND PROPERTY COMPILE_DEFINITIONS CMAKE_IS=Fun)
endif()
set_property(TARGET target_prop_executable APPEND PROPERTY COMPILE_DEFINITIONS CMAKE_IS_FUN CMAKE_IS_="Fun")
set_property(TARGET target_prop_executable APPEND PROPERTY COMPILE_DEFINITIONS
  TEST_GENERATOR_EXPRESSIONS
  "$<1:CMAKE_IS_DECLARATIVE>"
  "$<0:GE_NOT_DEFINED>"
  "$<1:ARGUMENT;LIST>"
  PREFIX_$<JOIN:DEF1;DEF2,;PREFIX_>
  LETTER_LIST1=\"$<JOIN:A;B;C;D,,>\"
  LETTER_LIST2=\"$<JOIN:A;B;C;D,,,>\"
  LETTER_LIST3=\"$<JOIN:A;B;C;D,,->\"
  LETTER_LIST4=\"$<JOIN:A;B;C;D,-,->\"
  LETTER_LIST5=\"$<JOIN:A;B;C;D,-,>\"
  "$<$<STREQUAL:$<TARGET_PROPERTY:LINKER_LANGUAGE>,CXX>:LINK_CXX_DEFINE>"
  "$<$<STREQUAL:$<TARGET_PROPERTY:LINKER_LANGUAGE>,C>:LINK_C_DEFINE>"
  "LINK_LANGUAGE_IS_$<TARGET_PROPERTY:LINKER_LANGUAGE>"
)
set_property(TARGET target_prop_executable APPEND PROPERTY COMPILE_DEFINITIONS
  BUILD_IS_DEBUG=$<CONFIG:Debug>
  BUILD_IS_NOT_DEBUG=$<NOT:$<CONFIG:Debug>>
)
add_executable(target_prop_c_executable ../compiletest.c)
set_property(TARGET target_prop_c_executable APPEND PROPERTY COMPILE_DEFINITIONS
  "$<$<STREQUAL:$<TARGET_PROPERTY:LINKER_LANGUAGE>,CXX>:LINK_CXX_DEFINE>"
  "$<$<STREQUAL:$<TARGET_PROPERTY:LINKER_LANGUAGE>,C>:LINK_C_DEFINE>"
  "LINK_LANGUAGE_IS_$<TARGET_PROPERTY:LINKER_LANGUAGE>"
)
add_executable(target_prop_mixed_executable ../compiletest_mixed_c.c ../compiletest_mixed_cxx.cpp)
set_property(TARGET target_prop_mixed_executable APPEND PROPERTY COMPILE_DEFINITIONS
  "$<$<STREQUAL:$<TARGET_PROPERTY:LINKER_LANGUAGE>,CXX>:LINK_CXX_DEFINE>"
  "$<$<STREQUAL:$<TARGET_PROPERTY:LINKER_LANGUAGE>,C>:LINK_C_DEFINE>"
  "LINK_LANGUAGE_IS_$<TARGET_PROPERTY:LINKER_LANGUAGE>"
  "C_EXECUTABLE_LINK_LANGUAGE_IS_$<TARGET_PROPERTY:target_prop_c_executable,LINKER_LANGUAGE>"
)
add_library(tgt STATIC IMPORTED)
set_property(TARGET tgt APPEND PROPERTY COMPILE_DEFINITIONS TGT_DEF TGT_TYPE_$<TARGET_PROPERTY:TYPE>)
add_executable(usetgt usetgt.c)
target_compile_definitions(usetgt PRIVATE $<TARGET_PROPERTY:tgt,COMPILE_DEFINITIONS>)
|}

let cd_add_def_cmd_tprop_cmake = {|
add_definitions(-DCMAKE_IS_FUN -DCMAKE_IS=Fun)
add_executable(add_def_cmd_tprop_exe ../compiletest.cpp)
set_target_properties(add_def_cmd_tprop_exe PROPERTIES COMPILE_DEFINITIONS CMAKE_IS_="Fun")
if(NOT NO_SPACES_IN_DEFINE_VALUES)
  set_property(TARGET add_def_cmd_tprop_exe APPEND PROPERTY COMPILE_DEFINITIONS CMAKE_IS_REALLY="Very Fun")
endif()
add_definitions(-DCMAKE_IS_FUN)
set_property(TARGET add_def_cmd_tprop_exe APPEND PROPERTY COMPILE_DEFINITIONS CMAKE_IS=Fun CMAKE_IS_="Fun")
add_definitions(-DBUILD_IS_DEBUG=$<CONFIG:Debug>)
set_property(TARGET add_def_cmd_tprop_exe APPEND PROPERTY COMPILE_DEFINITIONS BUILD_IS_NOT_DEBUG=$<NOT:$<CONFIG:Debug>>)
|}

(* -------------------------------------------------------------------------- *)
(* CxxOnly (Tests/CxxOnly/)                                                  *)
(* -------------------------------------------------------------------------- *)

let cxxonly_libcxx1_h = {|class LibCxx1Class { public: static float Method(); };|}
let cxxonly_libcxx1_cxx = {|#include "libcxx1.h"
float LibCxx1Class::Method() { return 2.0; }|}
let cxxonly_libcxx2_h = {|
#ifdef _WIN32
#  ifdef testcxx2_EXPORTS
#    define CM_TEST_LIB_EXPORT __declspec(dllexport)
#  else
#    define CM_TEST_LIB_EXPORT __declspec(dllimport)
#  endif
#else
#  define CM_TEST_LIB_EXPORT
#endif
class CM_TEST_LIB_EXPORT LibCxx2Class { public: static float Method(); };
|}
let cxxonly_libcxx2_cxx = {|#include "libcxx2.h"
float LibCxx2Class::Method() { return 1.0; }|}
let cxxonly_test_C = {|int testC;|}
let cxxonly_cxxonly_cxx = {|
#include "libcxx1.h"
#include "libcxx2.h"
extern int testC;
#include <stdio.h>
int main() {
  testC = 1;
  if (LibCxx1Class::Method() != 2.0) { printf("Problem with libcxx1\n"); return 1; }
  if (LibCxx2Class::Method() != 1.0) { printf("Problem with libcxx2\n"); return 1; }
  return 0;
}|}
let cxxonly_module_cxx = {|
#ifdef _WIN32
#  define TEST_EXPORT __declspec(dllexport)
#else
#  define TEST_EXPORT
#endif
TEST_EXPORT int testCxxModule(void) { return 0; }
|}

let cxxonly_yelu =
  ESeq [
    yc_minimum_required_s "3.10";
    yc_project ~languages:[Lang_cxx] "CxxOnly";
    yc_set (ycvar "CMAKE_DEBUG_POSTFIX") [ystr "_test_debug_postfix"];
    add_lib ~type_:Lib_static ~sources:[ystr "libcxx1.cxx"; ystr "test.C"] (t "testcxx1.my");
    add_lib ~type_:Lib_shared ~sources:[ystr "libcxx2.cxx"] (t "testcxx2");
    add_exe ~sources:[ystr "cxxonly.cxx"] (t "CxxOnly");
    link_lib [t "CxxOnly"] [ytarget_def ~kind:Plain [ytval "testcxx1.my"; ytval "testcxx2"]];
    add_lib ~type_:Lib_module ~sources:[ystr "testCxxModule.cxx"] (t "testCxxModule");
  ]

(* -------------------------------------------------------------------------- *)
(* AliasTarget (Tests/AliasTarget/)                                         *)
(* -------------------------------------------------------------------------- *)

let alias_target_commandgenerator_cpp = {|
#include <fstream>
#include "object.h"
int main(int argc, char** argv) {
  std::ofstream fout("commandoutput.h");
  if (!fout) return 1;
  fout << "#define COMMANDOUTPUT_DEFINE\n";
  fout.close();
  return object();
}
|}

let alias_target_targetgenerator_cpp = {|
#include <fstream>
int main(int argc, char** argv) {
  std::ofstream fout("targetoutput.h");
  if (!fout) return 1;
  fout << "#define TARGETOUTPUT_DEFINE\n";
  fout.close();
  return 0;
}
|}

let alias_target_empty_cpp = {|
#ifdef _WIN32
__declspec(dllexport)
#endif
int main(void) { return 0; }
|}

let alias_target_object_cpp = {|int object(void) { return 0; }|}

let alias_target_object_h = {|
#ifdef _WIN32
__declspec(dllexport)
#endif
int object(void);
|}

let alias_target_bat_cpp = {|
#ifndef FOO_DEFINE
#  error Expected FOO_DEFINE
#endif
#ifndef BAR_DEFINE
#  error Expected Bar_DEFINE
#endif
#include "commandoutput.h"
#ifndef COMMANDOUTPUT_DEFINE
#  error Expected COMMANDOUTPUT_DEFINE
#endif
#include "targetoutput.h"
#ifndef TARGETOUTPUT_DEFINE
#  error Expected TARGETOUTPUT_DEFINE
#endif
#ifdef _WIN32
__declspec(dllexport)
#endif
int bar() { return 0; }
|}

let alias_target_subdir_cmake = {|
add_library(tgt STATIC empty.cpp)
add_library(Sub::tgt ALIAS tgt)
add_library(Top::foo ALIAS foo)
get_target_property(some_prop Top::foo SOME_PROP)
target_link_libraries(tgt Top::foo)
|}

let alias_target_yelu =
  ESeq [
    yc_minimum_required_s "3.10";
    yc_project ~languages:[Lang_cxx] "AliasTarget";
    add_lib ~type_:Lib_shared ~sources:[ystr "empty.cpp"] (t "foo");
    add_lib_alias ~alias_of:"foo" "PREFIX::Foo";
    add_lib_alias ~alias_of:"foo" "Another::Alias";
    add_lib ~type_:Lib_object ~sources:[ystr "object.cpp"] (t "objects");
    add_lib_alias ~alias_of:"objects" "Alias::Objects";
    compile_defs (t "foo") [ytarget_def ~kind:Public [ytval "FOO_DEFINE"]];
    add_lib ~type_:Lib_shared ~sources:[ystr "empty.cpp"] (t "bar");
    compile_defs (t "bar") [ytarget_def ~kind:Public [ytval "BAR_DEFINE"]];
    link_lib [t "foo"] [ytarget_def ~kind:Public [ystr_eval {|$<$<STREQUAL:$<TARGET_PROPERTY:PREFIX::Foo,ALIASED_TARGET>,foo>:bar>|}]];
    add_exe ~sources:[ystr "commandgenerator.cpp";
                      ystr_eval "$<TARGET_OBJECTS:Alias::Objects>"] (t "AliasTarget");
    add_exe_alias ~alias_of:"AliasTarget" "PREFIX::AliasTarget";
    add_exe_alias ~alias_of:"AliasTarget" "Generator::Command";
    yc_add_custom_command ~outputs:[ystr "commandoutput.h"]
      [Yelu_langs.Lang_cmake.{ command = "Generator::Command"; args = [] }];
    add_lib ~type_:Lib_shared
      ~sources:[ystr "bat.cpp"; ystr "${CMAKE_CURRENT_BINARY_DIR}/commandoutput.h"]
      (t "bat");
    link_lib [t "bat"] [ytarget_def ~kind:Plain [ytval "PREFIX::Foo"]];
    include_dirs (t "bat")
      [ytarget_def ~kind:Private [ystr "${CMAKE_CURRENT_BINARY_DIR}"]];
    add_exe ~sources:[ystr "targetgenerator.cpp"] (t "targetgenerator");
    add_exe_alias ~alias_of:"targetgenerator" "Generator::Target";
    yc_add_subdirectory (ystr "subdir");
    yc_add_custom_target ~commands:[{ command = "Generator::Target";
                                      args = ["$<TARGET_FILE:Sub::tgt>"] }]
      "usealias";
    yc_add_dependencies "bat" "usealias";
    yifthen (ynot (yis_target (ystr "Another::Alias")))
      (yc_message ~mode:Mm_send_error ["Another::Alias is not considered a target."]);
    yc_get_target_property (ycvar "_alt") "PREFIX::Foo" "ALIASED_TARGET";
    yifthen (ynot (ystrequal (ycstr "_alt") (ystr "foo")))
      (yc_message ~mode:Mm_send_error ["ALIASED_TARGET is not foo: ${_alt}"]);
    yc_get_property ~target:(ystr "PREFIX::Foo") "ALIASED_TARGET" (ycvar "_alt2");
    yifthen (ynot (ystrequal (ycstr "_alt2") (ystr "foo")))
      (yc_message ~mode:Mm_send_error ["ALIASED_TARGET is not foo."]);
    add_lib ~type_:Lib_interface (t "iface");
    add_lib_alias ~alias_of:"iface" "Alias::Iface";
    yc_get_property ~set:true ~target:(ystr "foo") "ALIASED_TARGET"
      (ycvar "_aliased_target_set");
    yifthen (ytruthy (ycstr "_aliased_target_set"))
      (yc_message ~mode:Mm_send_error ["ALIASED_TARGET is set for target foo"]);
    yc_get_target_property (ycvar "_notAlias1") "foo" "ALIASED_TARGET";
    yifthen (ynot (yis_defined (ycstr "_notAlias1")))
      (yc_message ~mode:Mm_send_error ["_notAlias1 is not defined"]);
    yifthen (ytruthy (ycstr "_notAlias1"))
      (yc_message ~mode:Mm_send_error ["_notAlias1 is defined, but foo is not an ALIAS"]);
    yifthen (ynot (ystrequal (ycstr "_notAlias1") (ystr "_notAlias1-NOTFOUND")))
      (yc_message ~mode:Mm_send_error ["_notAlias1 not defined to a -NOTFOUND variant"]);
    yc_get_property ~target:(ystr "foo") "ALIASED_TARGET" (ycvar "_notAlias2");
    yifthen (ytruthy (ycstr "_notAlias2"))
      (yc_message ~mode:Mm_send_error ["_notAlias2 evaluates to true, but foo is not an ALIAS"]);
  ]

(* -------------------------------------------------------------------------- *)
(* PositionIndependentTargets (Tests/PositionIndependentTargets/)            *)
(* -------------------------------------------------------------------------- *)

let pic_lib_cpp = {|
#include "pic_test.h"
class PIC_TEST_EXPORT Dummy { int dummy(); };
int Dummy::dummy() { return 0; }
|}

let pic_main_cpp = {|
#include "pic_test.h"
int main(int, char**) { return 0; }
|}

let pic_main_no_inc_cpp = {|int main(int, char**) { return 0; }|}

let pic_test_h = {|
#if defined(__ELF__)
#  if !defined(__PIC__) && !defined(__PIE__)
#    error "The POSITION_INDEPENDENT_CODE property should cause __PIC__ or __PIE__ to be defined on ELF platforms."
#  endif
#endif
#if defined(PIC_TEST_STATIC_BUILD)
#  define PIC_TEST_EXPORT
#else
#  if defined(_WIN32) || defined(WIN32)
#    ifdef PIC_TEST_BUILD_DLL
#      define PIC_TEST_EXPORT __declspec(dllexport)
#    else
#      define PIC_TEST_EXPORT __declspec(dllimport)
#    endif
#  else
#    define PIC_TEST_EXPORT
#  endif
#endif
|}

let pic_global_cmake = {|
set(CMAKE_POSITION_INDEPENDENT_CODE True)
add_executable(test_target_executable_global
  "${CMAKE_CURRENT_SOURCE_DIR}/../pic_main.cpp"
)
add_library(test_target_shared_library_global
  SHARED "${CMAKE_CURRENT_SOURCE_DIR}/../pic_lib.cpp"
)
set_target_properties(test_target_shared_library_global
  PROPERTIES DEFINE_SYMBOL PIC_TEST_BUILD_DLL
)
add_library(test_target_static_library_global
  STATIC "${CMAKE_CURRENT_SOURCE_DIR}/../pic_lib.cpp"
)
set_target_properties(test_target_static_library_global
  PROPERTIES COMPILE_DEFINITIONS PIC_TEST_STATIC_BUILD
)
include(CheckCXXSourceCompiles)
file(READ "${CMAKE_CURRENT_SOURCE_DIR}/../pic_test.h" PIC_HEADER_CONTENT)
check_cxx_source_compiles(
  "${PIC_HEADER_CONTENT}\nint main(int,char**) { return 0; }\n"
  PIC_TRY_COMPILE_RESULT
)
if(NOT PIC_TRY_COMPILE_RESULT)
  message(SEND_ERROR "TRY_COMPILE with content requiring __PIC__ failed.")
endif()
|}

let pic_targets_cmake = {|
add_executable(test_target_executable_properties
  "${CMAKE_CURRENT_SOURCE_DIR}/../pic_main.cpp"
)
set_target_properties(test_target_executable_properties
  PROPERTIES POSITION_INDEPENDENT_CODE True
)
add_library(test_target_shared_library_properties
  SHARED "${CMAKE_CURRENT_SOURCE_DIR}/../pic_lib.cpp"
)
set_target_properties(test_target_shared_library_properties
  PROPERTIES
    POSITION_INDEPENDENT_CODE True
    DEFINE_SYMBOL PIC_TEST_BUILD_DLL
)
add_library(test_target_static_library_properties
  STATIC "${CMAKE_CURRENT_SOURCE_DIR}/../pic_lib.cpp"
)
set_target_properties(test_target_static_library_properties
  PROPERTIES
    POSITION_INDEPENDENT_CODE True
    COMPILE_DEFINITIONS PIC_TEST_STATIC_BUILD
)
|}

let pic_interface_cmake = {|
add_library(piciface INTERFACE)
set_property(TARGET piciface PROPERTY INTERFACE_POSITION_INDEPENDENT_CODE ON)
add_executable(test_empty_iface "${CMAKE_CURRENT_SOURCE_DIR}/../pic_main.cpp")
target_link_libraries(test_empty_iface piciface)
add_library(sharedlib SHARED "${CMAKE_CURRENT_SOURCE_DIR}/../pic_lib.cpp")
target_link_libraries(sharedlib piciface)
set_property(TARGET sharedlib PROPERTY DEFINE_SYMBOL PIC_TEST_BUILD_DLL)
add_executable(test_iface_via_shared "${CMAKE_CURRENT_SOURCE_DIR}/../pic_main.cpp")
target_link_libraries(test_iface_via_shared sharedlib)
add_library(objectlib OBJECT "${CMAKE_CURRENT_SOURCE_DIR}/../pic_lib.cpp")
target_link_libraries(objectlib piciface)
add_library(sharedlibpic SHARED "${CMAKE_CURRENT_SOURCE_DIR}/../pic_lib.cpp")
set_property(TARGET sharedlibpic PROPERTY INTERFACE_POSITION_INDEPENDENT_CODE ON)
set_property(TARGET sharedlibpic PROPERTY DEFINE_SYMBOL PIC_TEST_BUILD_DLL)
add_library(shared_iface INTERFACE)
target_link_libraries(shared_iface INTERFACE sharedlibpic)
add_executable(test_shared_via_iface "${CMAKE_CURRENT_SOURCE_DIR}/../pic_main.cpp")
target_link_libraries(test_shared_via_iface shared_iface)
add_executable(test_shared_via_iface_non_conflict
  "${CMAKE_CURRENT_SOURCE_DIR}/../pic_main.cpp"
)
set_property(TARGET test_shared_via_iface_non_conflict
  PROPERTY POSITION_INDEPENDENT_CODE ON
)
target_link_libraries(test_shared_via_iface_non_conflict shared_iface)
|}

let pic_yelu =
  ESeq [
    yc_minimum_required_s "3.10";
    yc_project ~languages:[Lang_cxx] "PositionIndependentTargets";
    yc_include (ystr "CheckCXXSourceCompiles");
    yc_include_directories [ystr_eval "${CMAKE_CURRENT_SOURCE_DIR}"];
    yc_add_subdirectory (ystr "global");
    yc_add_subdirectory (ystr "targets");
    yc_add_subdirectory (ystr "interface");
    add_exe ~sources:[ystr "main.cpp"] (t "PositionIndependentTargets");
  ]

(* ── ObjectLibrary ─────────────────────────────────────────────────────────── *)

let objlib_a_h = {|#ifndef A_DEF
#  error "A_DEF not defined"
#endif
#ifdef B_DEF
#  error "B_DEF must not be defined"
#endif
|}
let objlib_a1_c = {|#include "a.h"
int a1(void) { return 0; }
|}
let objlib_a2_c = {|#include "a.h"
int a2(void) { return 0; }
|}

let objlib_b_h = {|#ifdef A_DEF
#  error "A_DEF must not be defined"
#endif
#ifndef B_DEF
#  error "B_DEF not defined"
#endif
#if defined(_WIN32) && defined(Bexport)
#  define EXPORT_B __declspec(dllexport)
#else
#  define EXPORT_B
#endif
#if defined(_WIN32) && defined(SHARED_B)
#  define IMPORT_B __declspec(dllimport)
#else
#  define IMPORT_B
#endif
|}
let objlib_b1_c = {|#include "b.h"
EXPORT_B int b1(void) { return 0; }
|}
let objlib_b2_c = {|#include "b.h"
EXPORT_B int b2(void) { return 0; }
|}

let objlib_c_c = {|#if defined(_WIN32) && defined(Cshared_EXPORTS)
#  define EXPORT_C __declspec(dllexport)
#else
#  define EXPORT_C
#endif
extern int a1(void); extern int a2(void);
extern int b1(void); extern int b2(void);
EXPORT_C int c(void) { return 0 + a1() + a2() + b1() + b2(); }
|}

let objlib_main_c = {|#if defined(_WIN32) && defined(SHARED_C)
#  define IMPORT_C __declspec(dllimport)
#else
#  define IMPORT_C
#endif
extern IMPORT_C int b1(void); extern IMPORT_C int b2(void); extern IMPORT_C int c(void);
int main(void) { return 0 + c() + b1() + b2(); }
|}

let objlib_mainAB_c = {|#include "b.h"
extern IMPORT_B int b1(void); extern IMPORT_B int b2(void);
#ifndef NO_A
extern int a1(void); extern int a2(void);
#endif
int main(void) {
  return 0
#ifndef NO_A
    + a1() + a2()
#endif
    + b1() + b2();
}
|}

(* TransitiveLinkDeps source files *)
let objlib_tld_dep_c = "int from_dep(void) { return 0; }"
let objlib_tld_impl_obj_c = {|int from_dep(void);
int impl_obj(void) { return from_dep(); }
|}
let objlib_tld_main_c = {|int impl_obj(void);
int main(int argc, char* argv[]) { return impl_obj(); }
|}

(* A subdir — yelu program compiled to cmake string *)
let objlib_a_cmake =
  compile (ESeq [
    yc_project ~languages:[Lang_c] "ObjectLibraryA";
    yc_set (ycvar "CMAKE_POSITION_INDEPENDENT_CODE") [ystr "ON"];
    yc_add_definitions [ystr "-DA_DEF"];
    yc_add_custom_command
      ~outputs:[ystr "a1.c"]
      ~depends:[ystr "${CMAKE_CURRENT_SOURCE_DIR}/a1.c.in"]
      [custom_command "${CMAKE_COMMAND}"
         ["-E"; "copy"; "${CMAKE_CURRENT_SOURCE_DIR}/a1.c.in";
          "${CMAKE_CURRENT_BINARY_DIR}/a1.c"]];
    yc_file_remove [ystr "${CMAKE_CURRENT_BINARY_DIR}/a.cmake"];
    yc_add_custom_command
      ~outputs:[ystr "a.cmake"]
      [custom_command "${CMAKE_COMMAND}"
         ["-E"; "touch"; "${CMAKE_CURRENT_BINARY_DIR}/a.cmake"]];
    add_lib ~type_:Lib_object ~sources:[ystr "a1.c"; ystr "a2.c"; ystr "a.cmake"] (t "A");
    include_dirs (t "A") [ytarget_def ~kind:Private [ystr "${CMAKE_CURRENT_SOURCE_DIR}"]];
    yc_set_property ~targets:[t "A"] [("COMPILE_PDB_NAME", ystr "Apdb")];
  ])

(* B subdir — yelu program *)
let objlib_b_cmake =
  compile (ESeq [
    yc_project ~languages:[Lang_c] "ObjectLibraryB";
    yc_set (ycvar "CMAKE_POSITION_INDEPENDENT_CODE") [ystr "ON"];
    add_lib ~type_:Lib_object ~sources:[ystr "b1.c"; ystr "b2.c"] (t "B");
    include_dirs (t "B") [ytarget_def ~kind:Public [ystr "${CMAKE_CURRENT_SOURCE_DIR}"]];
    compile_defs (t "B") [ytarget_def ~kind:Public [ystr "B_DEF"]];
    add_lib ~type_:Lib_object ~sources:[ystr "b1.c"; ystr "b2.c"] (t "Bexport");
    yc_set_property ~targets:[t "Bexport"]
      [("COMPILE_DEFINITIONS", ystr "Bexport")];
    include_dirs (t "Bexport")
      [ytarget_def ~kind:Private
         [ystr_eval "$<TARGET_PROPERTY:B,INTERFACE_INCLUDE_DIRECTORIES>"]];
    compile_defs (t "Bexport")
      [ytarget_def ~kind:Private
         [ystr_eval "$<TARGET_PROPERTY:B,INTERFACE_COMPILE_DEFINITIONS>"]];
  ])



(* TransitiveLinkDeps subdir — verbatim cmake *)
let objlib_tld_cmake = {|
add_library(implgather INTERFACE)
add_library(dep STATIC dep.c)
add_library(deps INTERFACE)
target_link_libraries(deps INTERFACE dep)
add_library(impl_obj OBJECT impl_obj.c)
target_link_libraries(impl_obj PUBLIC deps)
target_sources(implgather INTERFACE "$<TARGET_OBJECTS:impl_obj>")
target_link_libraries(implgather INTERFACE impl_obj)
add_executable(useimpl main.c)
target_link_libraries(useimpl PRIVATE implgather)
|}

(* Root yelu program.
   ExportLanguages skipped — uses ExternalProject_Add (external cmake invocation). *)
let objlib_yelu =
  let obj = ystr_eval in  (* shorthand for $<TARGET_OBJECTS:X> *)
  ESeq [
    yc_project ~languages:[Lang_c] "ObjectLibrary";
    yc_add_subdirectory (ystr "A");
    yc_add_subdirectory (ystr "B");
    (* Cstatic: c.c + objects from A and B *)
    add_lib ~type_:Lib_static
      ~sources:[ystr "c.c"; obj "$<TARGET_OBJECTS:A>"; obj "$<TARGET_OBJECTS:B>"]
      (t "Cstatic");
    add_exe ~sources:[ystr "main.c"] (t "UseCstatic");
    link_lib [t "UseCstatic"] [ytarget_def ~kind:Private [t "Cstatic"]];
    (* Cshared *)
    add_lib ~type_:Lib_shared
      ~sources:[ystr "c.c"; obj "$<TARGET_OBJECTS:A>"; obj "$<TARGET_OBJECTS:Bexport>"]
      (t "Cshared");
    add_exe ~sources:[ystr "main.c"] (t "UseCshared");
    yc_set_property ~targets:[t "UseCshared"] [("COMPILE_DEFINITIONS", ystr "SHARED_C")];
    link_lib [t "UseCshared"] [ytarget_def ~kind:Private [t "Cshared"]];
    (* post-build add_custom_command(TARGET ...) verification removed:
       the IR does not yet model TARGET-form custom commands. *)
    (* ABstatic: no own sources *)
    add_lib ~type_:Lib_static
      ~sources:[obj "$<TARGET_OBJECTS:A>"; obj "$<TARGET_OBJECTS:B>"]
      (t "ABstatic");
    include_dirs (t "ABstatic")
      [ytarget_def ~kind:Public
         [obj "$<TARGET_PROPERTY:B,INTERFACE_INCLUDE_DIRECTORIES>"]];
    compile_defs (t "ABstatic")
      [ytarget_def ~kind:Public
         [obj "$<TARGET_PROPERTY:B,INTERFACE_COMPILE_DEFINITIONS>"]];
    add_exe ~sources:[ystr "mainAB.c"] (t "UseABstatic");
    link_lib [t "UseABstatic"] [ytarget_def ~kind:Private [t "ABstatic"]];
    (* ABshared: Linux path — B objects (no .def file needed on Linux) *)
    add_lib ~type_:Lib_shared
      ~sources:[obj "$<TARGET_OBJECTS:A>"; obj "$<TARGET_OBJECTS:B>"]
      (t "ABshared");
    include_dirs (t "ABshared")
      [ytarget_def ~kind:Public
         [obj "$<TARGET_PROPERTY:B,INTERFACE_INCLUDE_DIRECTORIES>"]];
    compile_defs (t "ABshared")
      [ytarget_def ~kind:Public
         [obj "$<TARGET_PROPERTY:B,INTERFACE_COMPILE_DEFINITIONS>"]];
    add_exe ~sources:[ystr "mainAB.c"] (t "UseABshared");
    yc_set_property ~targets:[t "UseABshared"] [("COMPILE_DEFINITIONS", ystr "SHARED_B")];
    link_lib [t "UseABshared"] [ytarget_def ~kind:Private [t "ABshared"]];
    (* ABmain OBJECT + UseABinternal executable from objects *)
    add_lib ~type_:Lib_object ~sources:[ystr "mainAB.c"] (t "ABmain");
    include_dirs (t "ABmain")
      [ytarget_def ~kind:Public
         [obj "$<TARGET_PROPERTY:B,INTERFACE_INCLUDE_DIRECTORIES>"]];
    compile_defs (t "ABmain")
      [ytarget_def ~kind:Public
         [obj "$<TARGET_PROPERTY:B,INTERFACE_COMPILE_DEFINITIONS>"]];
    add_exe
      ~sources:[obj "$<TARGET_OBJECTS:ABmain>"; obj "$<TARGET_OBJECTS:A>";
                obj "$<TARGET_OBJECTS:B>"]
      (t "UseABinternal");
    yc_file_remove [ystr "${CMAKE_CURRENT_BINARY_DIR}/UseABinternalDep.cmake"];
    yc_add_custom_target
      ~commands:[custom_command "${CMAKE_COMMAND}"
                   ["-E"; "touch"; "UseABinternalDep.cmake"]]
      "UseABinternalDep";
    (* post-build add_custom_command(TARGET ...) verification removed:
       the IR does not yet model TARGET-form custom commands. *)
    yc_add_dependencies "UseABinternal" "UseABinternalDep";
    (* Second-order object consumers *)
    add_lib ~type_:Lib_static
      ~sources:[obj "$<TARGET_OBJECTS:Cstatic>"; obj "$<TARGET_OBJECTS:A>";
                obj "$<TARGET_OBJECTS:Bexport>"]
      (t "UseCstaticObjs");
    add_lib ~type_:Lib_shared
      ~sources:[obj "$<TARGET_OBJECTS:Cshared>"; obj "$<TARGET_OBJECTS:A>";
                obj "$<TARGET_OBJECTS:Bexport>"]
      (t "UseCsharedObjs");
    add_exe ~sources:[obj "$<TARGET_OBJECTS:UseABstatic>"] (t "UseABstaticObjs");
    link_lib [t "UseABstaticObjs"] [ytarget_def ~kind:Private [t "ABstatic"]];
    (* ExportLanguages skipped (ExternalProject_Add).
       Transitive skipped (OBJECT INTERFACE dep propagation differs cmake 3.28 vs 4.3). *)
    yc_add_subdirectory (ystr "TransitiveLinkDeps");
  ]

let compile_options_main_cpp =
  (* _COMPILER_FRONTEND_VARIANT genex requires cmake 3.30+; stripped for 3.28 compat *)
  {|#ifndef TEST_DEFINE
#  error Expected definition TEST_DEFINE
#endif
#ifndef NEEDS_ESCAPE
#  error Expected definition NEEDS_ESCAPE
#endif
#ifdef DO_GNU_TESTS
#  ifndef TEST_DEFINE_GNU
#    error Expected definition TEST_DEFINE_GNU
#  endif
#  ifndef TEST_DEFINE_CXX_AND_GNU
#    error Expected definition TEST_DEFINE_CXX_AND_GNU
#  endif
#endif
#ifndef NO_DEF_TESTS
#  ifndef DEF_A
#    error Expected definition DEF_A
#  endif
#  ifndef DEF_B
#    error Expected definition DEF_B
#  endif
#  ifndef DEF_C
#    error Expected definition DEF_C
#  endif
#  ifndef DEF_D
#    error Expected definition DEF_D
#  endif
#  ifndef DEF_STR
#    error Expected definition DEF_STR
#  endif
#endif
#ifdef DO_FLAG_TESTS
#  if FLAG_A != 2
#    error "FLAG_A is not 2"
#  endif
#  if FLAG_B != 2
#    error "FLAG_B is not 2"
#  endif
#  if FLAG_C != 2
#    error "FLAG_C is not 2"
#  endif
#  if FLAG_D != 2
#    error "FLAG_D is not 2"
#  endif
#  if defined(FLAG_E) && FLAG_E != 2
#    error "FLAG_E is not 2"
#  endif
#endif
#include <string.h>
int main()
{
  return (strcmp(NEEDS_ESCAPE, "E$CAPE") == 0
#ifndef NO_DEF_TESTS
          && strcmp(DEF_STR, "string with spaces") == 0
#endif
          &&
          strcmp(EXPECTED_C_COMPILER_VERSION, TEST_C_COMPILER_VERSION) == 0 &&
          strcmp(EXPECTED_CXX_COMPILER_VERSION, TEST_CXX_COMPILER_VERSION) == 0
          ) ? 0 : 1;
}
|}

let compile_options_yelu =
  let co = t "CompileOptions" in
  let testlib = t "testlib" in
  ESeq [
    yc_minimum_required_s "3.10";
    yifthen (ypolicy_defined "CMP0092") (yc_policy_set "CMP0092");
    yifthen (ypolicy_defined "CMP0129") (yc_policy_set "CMP0129");
    yc_get_global_property ~property:"GENERATOR_IS_MULTI_CONFIG" (ycvar "_isMultiConfig");
    yifthen (yand (ynot (ytruthy (ycstr "_isMultiConfig"))) (ynot (ytruthy (ycstr "CMAKE_BUILD_TYPE"))))
      (yc_set_cache (ycvar "CMAKE_BUILD_TYPE") [ystr "Debug"]
         ~force:true ~cache_type:Ct_string ~docstring:"Choose the type of build");
    yc_project ~languages:[Lang_c; Lang_cxx] "CompileOptions";
    add_lib ~sources:[ystr "other.cpp"] testlib;
    add_exe ~sources:[ystr "main.cpp"] co;
    (* macro: appends per-compiler genex flags; _COMPILER_FRONTEND_VARIANT stripped for cmake 3.28 compat *)
    yc_macro (ystr "get_compiler_test_genex") ~args:["lst"; "lang"] [
      yc_list_append (ycvar "${lst}") [ystr_eval {|-DTEST_${lang}_COMPILER_VERSION=\"$<${lang}_COMPILER_VERSION>\"|}];
      yc_list_append (ycvar "${lst}") [ystr_eval {|-DTEST_${lang}_COMPILER_VERSION_EQUALITY=$<${lang}_COMPILER_VERSION:${CMAKE_${lang}_COMPILER_VERSION}>|}];
    ];
    yc_apply (ystr "get_compiler_test_genex") [ycstr "c_tests"; ystr "C"];
    yc_apply (ystr "get_compiler_test_genex") [ycstr "cxx_tests"; ystr "CXX"];
    (* set COMPILE_OPTIONS property: base flags + genex + per-lang version flags *)
    compile_opts co [
      ytarget_def ~kind:Private [
        ystr "-DTEST_DEFINE";
        ystr_eval {|-DNEEDS_ESCAPE=\"E$CAPE\"|};
        ystr_eval {|$<$<CXX_COMPILER_ID:GNU,LCC>:-DTEST_DEFINE_GNU>|};
        ystr_eval {|$<$<COMPILE_LANG_AND_ID:CXX,GNU,LCC>:-DTEST_DEFINE_CXX_AND_GNU>|};
        ystr "SHELL:";
        ystr_eval "${c_tests}";
        ystr_eval "${cxx_tests}";
      ];
    ];
    (* BORLAND/WATCOM: no -D flag support; others: SHELL -D defines *)
    yif (yor (ytruthy (ycstr "BORLAND")) (ytruthy (ycstr "WATCOM")))
      (compile_defs co [ ytarget_def ~kind:Private [ystr "NO_DEF_TESTS"] ])
      (compile_opts co [
        ytarget_def ~kind:Private [
          ystr {|SHELL:-D DEF_A|};
          ystr_eval {|$<1:SHELL:-D DEF_B>|};
          ystr_eval {|SHELL:-D 'DEF_C' -D \"DEF_D\"|};
          ystr_eval {|[=[SHELL:-D "DEF_STR=\"string with spaces\""]=]|};
        ]
      ]);
    (* octothorpe define: GNU/LCC/Clang compilers, not NMake *)
    yifthen (yand (ymatches (ycstr "CMAKE_CXX_COMPILER_ID") {|GNU|LCC|Clang|Borland|Embarcadero|}) (ynot (ymatches (ycstr "CMAKE_GENERATOR") "NMake Makefiles")))
      (compile_opts co [ ytarget_def ~kind:Private [ystr_eval {|-DTEST_OCTOTHORPE=\"#\"|}] ]);
    (* flag tests: GNU/LCC/AppleClang/MSVC compilers *)
    yifthen (ymatches (ycstr "CMAKE_CXX_COMPILER_ID") {|^(GNU|LCC|AppleClang|MSVC)$|})
      (ESeq [
        compile_defs co [ ytarget_def ~kind:Private [ystr "DO_FLAG_TESTS"] ];
        yifthen (ymatches (ycstr "CMAKE_CXX_COMPILER_ID") {|^(GNU|LCC|AppleClang)$|})
          (yc_string_append (ycvar "CMAKE_CXX_FLAGS") [ystr " -w"]);
        yc_string_append (ycvar "CMAKE_CXX_FLAGS")                [ystr " -DFLAG_A=1 -DFLAG_B=1"];
        yc_string_append (ycvar "CMAKE_CXX_FLAGS_DEBUG")          [ystr " -DFLAG_A=2 -DFLAG_C=1"];
        yc_string_append (ycvar "CMAKE_CXX_FLAGS_RELEASE")        [ystr " -DFLAG_A=2 -DFLAG_C=1"];
        yc_string_append (ycvar "CMAKE_CXX_FLAGS_RELWITHDEBINFO") [ystr " -DFLAG_A=2 -DFLAG_C=1"];
        yc_string_append (ycvar "CMAKE_CXX_FLAGS_MINSIZEREL")     [ystr " -DFLAG_A=2 -DFLAG_C=1"];
        yc_string_toupper (ystr_eval "${CMAKE_BUILD_TYPE}") (ycvar "_xbuild_type");
        yifthen (ynot (ymatches (ycstr "_xbuild_type") {|^(DEBUG|RELEASE|RELWITHDEBINFO|MINSIZEREL)$|}))
          (yc_string_append (ycvar "CMAKE_CXX_FLAGS_${_xbuild_type}") [ystr " -DFLAG_A=2 -DFLAG_C=1"]);
        compile_opts co [ ytarget_def ~kind:Private [ystr "-DFLAG_B=2"; ystr "-DFLAG_C=2"; ystr "-DFLAG_D=1"] ];
        yc_set_property ~append:true ~targets:[testlib]
          [("INTERFACE_COMPILE_OPTIONS", ystr "-DFLAG_D=2")];
        yc_set_property ~append:true ~targets:[testlib]
          [("INTERFACE_COMPILE_OPTIONS", ystr "-DFLAG_E=1")];
        yc_set_source_property (ystr "main.cpp") [ystr "-DFLAG_E=2"];
      ]);
    link_lib [co] [ ytarget_def ~kind:Plain [testlib] ];
    yifthen (ymatches (ycstr "CMAKE_CXX_COMPILER_ID") "GNU|LCC")
      (compile_defs co [ ytarget_def ~kind:Private [ystr "DO_GNU_TESTS"] ]);
    compile_defs co [
      ytarget_def ~kind:Private [
        ystr_eval {|EXPECTED_C_COMPILER_VERSION=\"${CMAKE_C_COMPILER_VERSION}\"|};
        ystr_eval {|EXPECTED_CXX_COMPILER_VERSION=\"${CMAKE_CXX_COMPILER_VERSION}\"|};

      ]
    ];
  ]

let compile_defs_yelu =
  ESeq [
    yc_minimum_required_s "3.10";
    yc_project ~languages:[Lang_cxx; Lang_c] "CompileDefinitions";
    yc_foreach ~items:[ystr "DEBUG"; ystr "RELEASE"; ystr "RELWITHDEBINFO"; ystr "MINSIZEREL"]
      (ycvar "c") (ESeq [
        yc_set (ycvar "CMAKE_C_FLAGS_${c}") [ystr_eval "${CMAKE_C_FLAGS_${c}} -DTEST_CONFIG_${c}"];
        yc_set (ycvar "CMAKE_CXX_FLAGS_${c}") [ystr_eval "${CMAKE_CXX_FLAGS_${c}} -DTEST_CONFIG_${c}"];
      ]);
    yc_set_directory_property ~append:true "COMPILE_DEFINITIONS"
      [ystr_eval {|BUILD_CONFIG_NAME=\"$<CONFIGURATION>\"|}];
    yc_add_subdirectory (ystr "add_def_cmd");
    yc_add_subdirectory (ystr "target_prop");
    yc_add_subdirectory (ystr "add_def_cmd_tprop");
    add_exe ~sources:[ystr "runtest.c"] (t "CompileDefinitions");
  ]

let () =
  Alcotest.run "CMakeCommands build tests"
    [ ("target_link_options", [
        check_build_pair "basic" "target_link_options"
          ~files:[("lib.c", c_lib_source)]
          tlo_yelu;
      ]);
      ("add_compile_definitions", [
        check_build_pair "basic" "add_compile_definitions"
          ~files:[("main.cpp", cpp_main_source)]
          acd_yelu;
      ]);
      ("add_link_options", [
        check_build_pair "basic" "add_link_options"
          ~files:[("LinkOptionsExe.c", {|int main(void) { return 0; }|})]
          add_link_opts_yelu;
      ]);
      ("link_directories", [
        check_build_pair "basic" "link_directories"
          ~files:[("LinkDirectoriesExe.c", {|int main(void) { return 0; }|})]
          link_dirs_yelu;
      ]);
      ("add_compile_options", [
        check_build_pair "basic" "add_compile_options"
          ~files:[("main.cpp", aco_main_source)]
          aco_yelu;
      ]);
      ("target_compile_definitions", [
        check_build_pair "basic" "target_compile_definitions"
          ~files:[("main.cpp", tcd_main_source);
                  ("consumer.cpp", tcd_consumer_cpp_source);
                  ("consumer.c", tcd_consumer_c_source)]
          tcd_yelu;
      ]);
      ("target_compile_options", [
        check_build_pair "basic" "target_compile_options"
          ~files:[("main.cpp", tco_main_source);
                  ("consumer.cpp", tco_consumer_cpp_source);
                  ("consumer.c", tco_consumer_c_source)]
          tco_yelu;
      ]);
      ("target_link_directories", [
        check_build_pair "basic" "target_link_directories"
          ~files:[("LinkDirectoriesLib.c", link_dir_lib_source);
                  ("subdir/CMakeLists.txt", {|add_library(target_link_directories_5 SHARED EXCLUDE_FROM_ALL ../LinkDirectoriesLib.c)|})]
          tld_yelu;
      ]);
      ("target_compile_features", [
        check_build_pair "basic" "target_compile_features"
          ~files:[("main.c", tcf_main_c_source);
                  ("lib_restrict.h", tcf_lib_restrict_h);
                  ("lib_restrict.c", tcf_lib_restrict_c);
                  ("restrict_user.c", tcf_restrict_user_c);
                  ("main.cpp", tcf_main_cpp_source);
                  ("lib_auto_type.h", tcf_lib_auto_type_h);
                  ("lib_auto_type.cpp", tcf_lib_auto_type_cpp);
                  ("lib_user.cpp", tcf_lib_user_cpp)]
          tcf_yelu;
      ]);
      ("target_sources", [
        check_build_pair "basic" "target_sources"
          ~files:[("main.cpp", ts_main_cpp);
                  ("empty_1.cpp", ts_empty_1_cpp);
                  ("empty_2.cpp", ts_empty_2_cpp);
                  ("empty_3.cpp", ts_empty_3_cpp);
                  ("subdir/CMakeLists.txt", ts_subdir_cmake);
                  ("subdir/subdir_empty_1.cpp", ts_subdir_empty_1_cpp);
                  ("subdir/subdir_empty_2.cpp", ts_subdir_empty_2_cpp)]
          ts_yelu;
      ]);
      ("target_include_directories", [
        check_build_pair "basic" "target_include_directories"
          ~files:[("main.cpp", tid_main_cpp);
                  ("consumer.cpp", tid_consumer_cpp);
                  ("consumer.c", tid_consumer_c);
                  ("same.c", tid_same_c);
                  ("cxx_only/cxx_only.h", "#define CXX_ONLY_DEFINE\n");
                  ("c_only/c_only.h", "\n#define C_ONLY_DEFINE\n");
                  ("same_one/same.h", {|#error "Wrong \"same.h\" included!"|});
                  ("same_two/same.h", "#define CORRECT_SAME_H_INCLUDED\n");
                  ("relative_dir/relative_dir.h", "\n#define RELATIVE_DIR_DEFINE\n");
                  ("relative_dir/consumer/consumer.h", "\n#define CONSUMER_DEFINE\n")]
          tid_yelu;
      ]);
      (* ------------------------------------------------------------------ *)
      (* Group 2: Tests/ (outside CMakeCommands/) — check_build_pair_tests  *)
      (* ------------------------------------------------------------------ *)
      (* NOTE: source strings and yelu programs defined above in the file   *)
      ("lib_name", [
        check_build_pair_tests "basic" "LibName"
          ~files:[("bar.c", libname_bar_c);
                  ("foo.c", libname_foo_c);
                  ("foobar.c", libname_foobar_c)]
          libname_yelu;
      ]);
      ("link_static", [
        check_build_pair_tests "basic" "LinkStatic"
          ~files:[("LinkStatic.c", link_static_main_c)]
          link_static_yelu;
      ]);
      ("simple", [
        check_build_pair_tests "basic" "Simple"
          ~files:[("simple.cxx", simple_simple_cxx);
                  ("simpleLib.cxx", simple_simplelib_cxx);
                  ("simpleCLib.c", simple_simpleclib_c);
                  ("simpleWe.cpp", simple_simplewe_cpp)]
          simple_yelu;
      ]);
      ("link_line", [
        check_build_pair_tests "basic" "LinkLine"
          ~files:[("One.c", ll_one_c);
                  ("Two.c", ll_two_c);
                  ("Exec.c", ll_exec_c)]
          ll_yelu;
      ]);
      ("link_line_order", [
        check_build_pair_tests "basic" "LinkLineOrder"
          ~files:[("NoDepA.c", llo_nodep_a_c);
                  ("NoDepB.c", llo_nodep_b_c);
                  ("NoDepC.c", llo_nodep_c_c);
                  ("NoDepE.c", llo_nodep_e_c);
                  ("NoDepF.c", llo_nodep_f_c);
                  ("NoDepX.c", llo_nodep_x_c);
                  ("NoDepY.c", llo_nodep_y_c);
                  ("NoDepZ.c", llo_nodep_z_c);
                  ("One.c", llo_one_c);
                  ("Two.c", llo_two_c);
                  ("Exec1.c", llo_exec1_c);
                  ("Exec2.c", llo_exec2_c)]
          llo_yelu;
      ]);
      ("out_name", [
        check_build_pair_tests "basic" "OutName"
          ~files:[("main.c", {|int main(void) { return 0; }|})]
          out_name_yelu;
      ]);
      (* empty_library: BLOCKED — cmake 3.28 rejects add_library(test test.h) with
         "Cannot determine link language"; upstream test requires older cmake *)
      ("target_name", [
        check_build_pair_tests "basic" "TargetName"
          ~files:[("executables/CMakeLists.txt", "add_executable(hello_world hello_world.c)");
                  ("executables/hello_world.c", target_name_hello_world_c);
                  ("scripts/CMakeLists.txt", target_name_scripts_cmake);
                  ("scripts/hello_world", "#!/bin/sh\necho \"hello, world\"\n")]
          target_name_yelu;
      ]);
      ("cxx_only", [
        check_build_pair_tests "basic" "CxxOnly"
          ~files:[("libcxx1.h", cxxonly_libcxx1_h);
                  ("libcxx1.cxx", cxxonly_libcxx1_cxx);
                  ("libcxx2.h", cxxonly_libcxx2_h);
                  ("libcxx2.cxx", cxxonly_libcxx2_cxx);
                  ("test.C", cxxonly_test_C);
                  ("cxxonly.cxx", cxxonly_cxxonly_cxx);
                  ("testCxxModule.cxx", cxxonly_module_cxx)]
          cxxonly_yelu;
      ]);
      ("alias_target", [
        check_build_pair_tests "basic" "AliasTarget"
          ~files:[("empty.cpp", alias_target_empty_cpp);
                  ("object.cpp", alias_target_object_cpp);
                  ("object.h", alias_target_object_h);
                  ("commandgenerator.cpp", alias_target_commandgenerator_cpp);
                  ("targetgenerator.cpp", alias_target_targetgenerator_cpp);
                  ("bat.cpp", alias_target_bat_cpp);
                  ("subdir/CMakeLists.txt", alias_target_subdir_cmake);
                  ("subdir/empty.cpp", alias_target_empty_cpp)]
          alias_target_yelu;
      ]);
      ("pic_targets", [
        check_build_pair_tests "basic" "PositionIndependentTargets"
          ~files:[("pic_lib.cpp", pic_lib_cpp);
                  ("pic_main.cpp", pic_main_cpp);
                  ("pic_test.h", pic_test_h);
                  ("main.cpp", pic_main_no_inc_cpp);
                  ("global/CMakeLists.txt", pic_global_cmake);
                  ("targets/CMakeLists.txt", pic_targets_cmake);
                  ("interface/CMakeLists.txt", pic_interface_cmake)]
          pic_yelu;
      ]);
      ("object_library", [
        (* Tests/ObjectLibrary/ uses ExternalProject_Add in ExportLanguages subdir
           → no reference comparison. Exercises: add_library(OBJECT), $<TARGET_OBJECTS:X>
           as source arg, add_custom_command TARGET POST_BUILD, add_definitions. *)
        check_build_yelu "basic"
          ~files:[("A/CMakeLists.txt", objlib_a_cmake);
                  ("A/a1.c.in",        objlib_a1_c);
                  ("A/a2.c",           objlib_a2_c);
                  ("A/a.h",            objlib_a_h);
                  ("B/CMakeLists.txt", objlib_b_cmake);
                  ("B/b1.c",           objlib_b1_c);
                  ("B/b2.c",           objlib_b2_c);
                  ("B/b.h",            objlib_b_h);
                  ("c.c",              objlib_c_c);
                  ("main.c",           objlib_main_c);
                  ("mainAB.c",         objlib_mainAB_c);
                  ("TransitiveLinkDeps/CMakeLists.txt", objlib_tld_cmake);
                  ("TransitiveLinkDeps/dep.c",          objlib_tld_dep_c);
                  ("TransitiveLinkDeps/impl_obj.c",     objlib_tld_impl_obj_c);
                  ("TransitiveLinkDeps/main.c",         objlib_tld_main_c)]
          objlib_yelu;
      ]);
      ("compile_options", [
        (* upstream Tests/CompileOptions uses $<C_COMPILER_FRONTEND_VARIANT> (cmake 3.30+);
           no reference comparison — yelu-only build *)
        check_build_yelu "basic"
          ~files:[("main.cpp", compile_options_main_cpp);
                  ("other.cpp", "void foo(void) {}\n")]
          compile_options_yelu;
      ]);
      ("custom_command", [
        (* Tests/CustomCommand/ is 609 lines: generator-exe subdirs, shell
           operators (< > >>), genex ($<1:generator>, $<TARGET_PROPERTY:...>),
           COMMAND_EXPAND_LISTS, configure_file, PerConfig sibling subdir —
           not tractable as a reference. Yelu-only build covering OUTPUT form,
           add_custom_target ALL+DEPENDS, and add_dependencies. *)
        check_build_yelu "basic"
          (ESeq [
            yc_project "CustomCommandTest";
            (* step 1: touch a stamp file *)
            yc_add_custom_command
              ~outputs:[ystr "stamp.txt"]
              ~verbatim:true
              ~comment:(Some "Stamping stamp.txt")
              [custom_command "${CMAKE_COMMAND}" ["-E"; "touch"; "stamp.txt"]];
            yc_add_custom_target ~all:true ~depends:[ystr "stamp.txt"]
              "drive_stamp";
            (* step 2: copy stamp to copy.txt, depends on stamp *)
            yc_add_custom_command
              ~outputs:[ystr "copy.txt"]
              ~depends:[ystr "stamp.txt"]
              ~verbatim:true
              ~comment:(Some "Copying stamp to copy.txt")
              [custom_command "${CMAKE_COMMAND}" ["-E"; "copy"; "stamp.txt"; "copy.txt"]];
            yc_add_custom_target ~all:true ~depends:[ystr "copy.txt"]
              "drive_copy";
            yc_add_dependencies "drive_copy" "drive_stamp";
          ]);
      ]);
      ("compile_definitions", [
        check_build_pair_tests "basic" "CompileDefinitions"
          ~files:[("compiletest.cpp", cd_compiletest_cpp);
                  ("compiletest.c", cd_compiletest_c);
                  ("compiletest_mixed_c.c", cd_compiletest_mixed_c);
                  ("compiletest_mixed_cxx.cpp", cd_compiletest_mixed_cxx);
                  ("runtest.c", {|
#include <ctype.h>
#include <stdio.h>
#include <string.h>
#ifndef BUILD_CONFIG_NAME
#  error "BUILD_CONFIG_NAME not defined!"
#endif
int main(void) {
  char build_config_name[] = BUILD_CONFIG_NAME;
  char* c;
  for (c = build_config_name; *c; ++c)
    *c = (char)((*c >= 'A' && *c <= 'Z') ? (*c + 32) : *c);
  fprintf(stderr, "build_config_name=\"%s\"\n", build_config_name);
  return 0;
}
|});
                  ("target_prop/CMakeLists.txt", cd_target_prop_cmake);
                  ("target_prop/usetgt.c", cd_usetgt_c);
                  ("add_def_cmd/CMakeLists.txt", cd_add_def_cmd_cmake);
                  ("add_def_cmd_tprop/CMakeLists.txt", cd_add_def_cmd_tprop_cmake)]
          compile_defs_yelu;
      ]);
      ("visibility", [
        (* Tests/Visibility/ — C_VISIBILITY_PRESET hidden + VISIBILITY_INLINES_HIDDEN.
           POST_BUILD runs cmake -P verify.cmake (nm check); build exit code is oracle. *)
        check_build_yelu "basic"
          ~files:[
            ("hidden.c", {|
int hidden_function(void) { return 0; }
__attribute__((visibility("default"))) int not_hidden(void) { return hidden_function(); }
|});
            ("shared.c", {|
extern int not_hidden(void);
int shared(void) { return not_hidden(); }
|});
            ("foo.cpp", {|
class Foo { public: void bar() {} };
void baz() { Foo foo; foo.bar(); }
|});
            ("bar.c", {|void bar(void) {}|});
            ("shared.cpp", {|
extern "C" int bar(void);
void baz();
int shared() { baz(); return bar(); }
|});
            ("verify.cmake", {|
execute_process(COMMAND ${CMAKE_NM} -D ${TEST_LIBRARY_PATH}
  RESULT_VARIABLE RESULT OUTPUT_VARIABLE OUTPUT ERROR_VARIABLE ERROR)
if(NOT "${RESULT}" STREQUAL "0")
  message(FATAL_ERROR "nm failed [${RESULT}] [${OUTPUT}] [${ERROR}]")
endif()
if(${OUTPUT} MATCHES "(Foo[^\n]*bar|hidden_function)")
  message(FATAL_ERROR "Found ${CMAKE_MATCH_1} which should have been hidden [${OUTPUT}]")
endif()
|})]
          (* post-build add_custom_command(TARGET ...) verification removed:
             the IR does not yet model TARGET-form custom commands. The
             visibility build still configures + builds; the nm-based
             oracle is skipped. *)
          (let pb _tname = EUnit in
           ESeq [
             yc_project "Visibility";
             (* C hidden targets *)
             add_lib ~type_:Lib_shared ~sources:[ystr "hidden.c"] (t "hidden1");
             yc_set_property ~targets:[t "hidden1"]
               [("C_VISIBILITY_PRESET", ystr "hidden")];
             add_lib ~type_:Lib_object ~sources:[ystr "hidden.c"] (t "hidden_object");
             yc_set_property ~targets:[t "hidden_object"]
               [("C_VISIBILITY_PRESET", ystr "hidden");
                ("POSITION_INDEPENDENT_CODE", ystr "ON")];
             add_lib ~type_:Lib_static ~sources:[ystr "hidden.c"] (t "hidden_static");
             yc_set_property ~targets:[t "hidden_static"]
               [("C_VISIBILITY_PRESET", ystr "hidden");
                ("POSITION_INDEPENDENT_CODE", ystr "ON")];
             add_lib ~type_:Lib_shared
               ~sources:[ystr_eval "$<TARGET_OBJECTS:hidden_object>"; ystr "shared.c"] (t "hidden2");
             add_lib ~type_:Lib_shared ~sources:[ystr "shared.c"] (t "hidden3");
             link_lib [t "hidden3"] [ytarget_def [t "hidden_static"]];
             pb "hidden1"; pb "hidden2"; pb "hidden3";
             (* C++ inlines_hidden targets *)
             add_lib ~type_:Lib_shared ~sources:[ystr "foo.cpp"; ystr "bar.c"] (t "inlines_hidden1");
             yc_set_property ~targets:[t "inlines_hidden1"]
               [("VISIBILITY_INLINES_HIDDEN", ystr "ON")];
             compile_opts (t "inlines_hidden1") [ytarget_def ~kind:Private [ystr "-Werror"]];
             add_lib ~type_:Lib_object ~sources:[ystr "foo.cpp"; ystr "bar.c"] (t "inlines_hidden_object");
             yc_set_property ~targets:[t "inlines_hidden_object"]
               [("VISIBILITY_INLINES_HIDDEN", ystr "ON");
                ("POSITION_INDEPENDENT_CODE", ystr "ON")];
             compile_opts (t "inlines_hidden_object") [ytarget_def ~kind:Private [ystr "-Werror"]];
             add_lib ~type_:Lib_static ~sources:[ystr "foo.cpp"; ystr "bar.c"] (t "inlines_hidden_static");
             yc_set_property ~targets:[t "inlines_hidden_static"]
               [("VISIBILITY_INLINES_HIDDEN", ystr "ON");
                ("POSITION_INDEPENDENT_CODE", ystr "ON")];
             compile_opts (t "inlines_hidden_static") [ytarget_def ~kind:Private [ystr "-Werror"]];
             add_lib ~type_:Lib_shared
               ~sources:[ystr_eval "$<TARGET_OBJECTS:inlines_hidden_object>"; ystr "shared.cpp"]
               (t "inlines_hidden2");
             add_lib ~type_:Lib_shared ~sources:[ystr "shared.cpp"] (t "inlines_hidden3");
             link_lib [t "inlines_hidden3"] [ytarget_def [t "inlines_hidden_static"]];
             pb "inlines_hidden1"; pb "inlines_hidden2"; pb "inlines_hidden3";
           ]);
      ]);
    ]
