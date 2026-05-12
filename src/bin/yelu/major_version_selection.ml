open Yelu_langs.Yelu_cmake_utils
open Yelu_langs.Lang_cmake
open Step_common_ir

(* cmake Tests/CMakeOnly/MajorVersionSelection/CMakeLists.txt
   Concrete instantiation: module=OpenSSL, major_version=3.
   The original is a parameterized harness driven by -DMAJOR_TEST_MODULE=X
   -DMAJOR_TEST_VERSION=N. We translate the core pattern with static values. *)

let version_check =
  ycmd_of_list
    [
      yc_message ~mode:Mm_status
        [ "OPENSSL_VERSION_STRING is '${OPENSSL_VERSION_STRING}'" ];
      yifthen
        (yversion_less (ycstr "OPENSSL_VERSION_STRING") (ystr "3"))
        (yc_message ~mode:Mm_send_error
           [ "Found version ${OPENSSL_VERSION_STRING} is less than \
              requested major version 3" ]);
      yc_math "3 + 1" (ycvar "V_PLUS_ONE");
      yifthen
        (yversion_greater (ycstr "OPENSSL_VERSION_STRING") (ycstr "V_PLUS_ONE"))
        (yc_message ~mode:Mm_send_error
           [ "Found version ${OPENSSL_VERSION_STRING} is greater than \
              requested major version 3" ]);
    ]

let cmd =
  ycmd_of_list
    [
      yc_minimum_required_s "3.10.";
      yc_project ~languages:[ Lang_none ] "major_detect_OpenSSL_3";
      yc_find_package ~version:(Some "3") ~quiet:true "OpenSSL";
      yc_string_toupper (ystr "OpenSSL") (ycvar "MODULE_UPPER");
      yifthen
        (yand (ytruthy (ycstr "OPENSSL_FOUND")) (ytruthy (ycstr "OPENSSL_VERSION_STRING")))
        version_check;
    ]

let () = print_cmake cmd
