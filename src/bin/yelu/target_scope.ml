open Yelu_langs.Yelu_cmake_ir_utils
open Step_common_ir

(* Generates: Tests/CMakeOnly/TargetScope/CMakeLists.txt *)
let cmd =
  ycmd_of_list
    [
      yc_minimum_required_s "3.10.";
      yc_project ~languages:[ Lang_none ] "TargetScope";
      yc_add_subdirectory (ystr "Sub");
      yifthen
        (yis_target (ytval "SubLibLocal"))
        (ycmd_of_list
           [ yc_message ~mode:Mm_fatal_error [ "SubLibLocal visible in top directory" ] ]);
      yifthen
        (ynot (yis_target (ytval "SubLibGlobal")))
        (ycmd_of_list
           [ yc_message ~mode:Mm_fatal_error [ "SubLibGlobal not visible in top directory" ] ]);
      yc_add_subdirectory (ystr "Sib");
    ]

let () = print_cmake cmd
