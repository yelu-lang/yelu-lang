open Yelu_langs.Lang_yelu_utils
open Step_common

(* Generates: Tests/CMakeOnly/TargetScope/Sub/CMakeLists.txt *)
let cmd =
  ycmd_of_list
    [
      add_lib_imported ~lib_type:"UNKNOWN" (ytval "SubLibLocal");
      add_lib_imported ~lib_type:"UNKNOWN" ~global:true (ytval "SubLibGlobal");
      yc_add_subdirectory (ystr "Sub");
      yifthen
        (ynot (yis_target (ytval "SubLibLocal")))
        (ycmd_of_list
           [ yc_message ~mode:Mm_fatal_error [ "SubLibLocal not visible in own directory" ] ]);
      yifthen
        (ynot (yis_target (ytval "SubLibGlobal")))
        (ycmd_of_list
           [ yc_message ~mode:Mm_fatal_error [ "SubLibGlobal not visible in own directory" ] ]);
    ]

let () = print_cmake cmd
