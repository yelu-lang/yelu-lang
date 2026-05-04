open Yelu_langs.Lang_yelu_utils
open Step_common

(* Generates: Tests/CMakeOnly/TargetScope/Sub/Sub/CMakeLists.txt *)
let cmd =
  ycmd_of_list
    [
      yifthen
        (ynot (yis_target (ytval "SubLibLocal")))
        (ycmd_of_list
           [ yc_message ~mode:Mm_fatal_error [ "SubLibLocal not visible in subdirectory" ] ]);
      yifthen
        (ynot (yis_target (ytval "SubLibGlobal")))
        (ycmd_of_list
           [ yc_message ~mode:Mm_fatal_error [ "SubLibGlobal not visible in subdirectory" ] ]);
    ]

let () = print_cmake cmd
