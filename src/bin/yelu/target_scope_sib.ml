open Yelu_langs.Lang_yelu_utils
open Step_common

(* Generates: Tests/CMakeOnly/TargetScope/Sib/CMakeLists.txt *)
let cmd =
  ycmd_of_list
    [
      yifthen
        (yis_target (ytval "SubLibLocal"))
        (ycmd_of_list
           [ yc_message ~mode:Mm_fatal_error [ "SubLibLocal visible in sibling directory" ] ]);
      yifthen
        (ynot (yis_target (ytval "SubLibGlobal")))
        (ycmd_of_list
           [ yc_message ~mode:Mm_fatal_error [ "SubLibGlobal not visible in sibling directory" ] ]);
    ]

let () = print_cmake cmd
