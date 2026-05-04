open Yelu_langs.Lang_cmake_utils
open Yelu_langs.Lang_cmake_pp

(* TutorialProject/Tests/CMakeLists.txt *)
let () =
  let ast = cmd_of_list [
    add_executable "TestMathFunctions";
    target_sources "TestMathFunctions"
      [ target_def ~kind:"PRIVATE" [ str_ "TestMathFunctions.cxx" ] ];
    find_package ~required:true "SimpleTest";
    target_link_libraries [ "TestMathFunctions" ] [
      target_def ~kind:"PRIVATE"
        [ str_ "MathFunctions"; str_ "SimpleTest::SimpleTest" ];
    ];
    apply "simpletest_discover_tests" [ str_ "TestMathFunctions" ];
  ] in
  Fmt.pr "%a@." (Fmt.vbox pp) ast
