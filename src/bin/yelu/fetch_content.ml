open Yelu_langs.Lang_yelu_utils
open Step_common

(* Demonstrates FetchContent_Declare + FetchContent_MakeAvailable.
   These are cmake module functions — no new AST nodes needed, just
   yc_include + yc_apply with keyword arguments as bare strings. *)

let cmd =
  ycmd_of_list
    [
      yc_minimum_required_s "3.14.";
      yc_project ~languages:[ Lang_none ] "FetchContentExample";
      yc_include (yfile "FetchContent");
      yc_apply (ystr "FetchContent_Declare")
        [ ystr "googletest";
          ykeyword "GIT_REPOSITORY"; ystr "https://github.com/google/googletest.git";
          ykeyword "GIT_TAG";        ystr "v1.14.0";
          ykeyword "EXCLUDE_FROM_ALL" ];
      yc_apply (ystr "FetchContent_MakeAvailable") [ ystr "googletest" ];
    ]

let () = print_cmake cmd
