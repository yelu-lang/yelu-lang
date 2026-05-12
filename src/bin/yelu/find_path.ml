open Yelu_langs.Yelu_cmake_utils
open Yelu_langs.Lang_cmake
open Step_common_ir

(* cmake Tests/CMakeOnly/find_path/CMakeLists.txt *)

let inner_if =
  yif
    (ynot (ystrequal (ystr_eval "${REL_HDR}") (ystr_eval "${expected}")))
    (yc_message ~mode:Mm_send_error
       [ "Header ${expected} found as [${REL_HDR}]" ])
    (yifthen
       (ytruthy (ycstr "CMAKE_FIND_DEBUG_MODE"))
       (yc_message ~mode:Mm_status
          [ "Header ${expected} found as [${REL_HDR}]" ]))

let outer_if =
  yif
    (ytruthy (ycstr "HDR"))
    (ycmd_of_list
       [
         yc_file_relative_path
           ~var:(ycstr "REL_HDR")
           ~base:(ystr_eval "${CMAKE_CURRENT_SOURCE_DIR}")
           (ystr_eval "${HDR}");
         inner_if;
       ])
    (yc_message ~mode:Mm_send_error [ "Header ${expected} NOT FOUND" ])

let test_macro =
  yc_macro (ystr "test_find_path") ~args:[ "expected" ]
    [
      yc_unset_cache (ycvar "HDR");
      yc_apply (ystr "find_path")
        [
          ycstr "HDR";
          ystr_eval "${ARGN}";
          ystr "NO_CMAKE_ENVIRONMENT_PATH";
          ystr "NO_SYSTEM_ENVIRONMENT_PATH";
        ];
      outer_if;
    ]

let cmd =
  ycmd_of_list
    [
      yc_minimum_required_s "3.10.";
      yc_project ~languages:[ Lang_none ] "FindPathTest";
      yc_set (ycvar "CMAKE_FIND_DEBUG_MODE") [ ystr "1" ];
      test_macro;
      yc_set (ycvar "CMAKE_SYSTEM_PREFIX_PATH") [ ycref source_this ];
      yc_set (ycvar "CMAKE_LIBRARY_ARCHITECTURE") [ ystr "arch" ];
      yc_apply (ystr "test_find_path")
        [ ystr "include"; ystr "NAMES"; ystr "test1.h" ];
      yc_apply (ystr "test_find_path")
        [ ystr "include/arch"; ystr "NAMES"; ystr "test1arch.h" ];
    ]

let () = print_cmake cmd
