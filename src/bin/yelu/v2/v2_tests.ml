open Yelu_langs.Lang_yelu_utils
open Step_common

(* TutorialProject/Tests/CMakeLists.txt *)
let cmd =
  ycmd_of_list [
    add_exe (ytval "TestMathFunctions");
    yc_target_sources_fs (ytval "TestMathFunctions") [
      ytsi_plain Private [ yfile "TestMathFunctions.cxx" ];
    ];
    yc_find_package ~required:true "SimpleTest";
    link_lib [ ytval "TestMathFunctions" ] [
      ytarget_def ~kind:Private
        [ ytval "MathFunctions"; ytval "SimpleTest::SimpleTest" ];
    ];
    yc_apply (yname "simpletest_discover_tests") [ ytval "TestMathFunctions" ];
  ]

let () = print_cmake cmd
