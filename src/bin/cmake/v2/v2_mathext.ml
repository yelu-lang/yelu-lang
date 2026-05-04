open Yelu_langs.Lang_cmake_utils
open Yelu_langs.Lang_cmake_pp

(* TutorialProject/MathFunctions/MathExtensions/CMakeLists.txt
   Three add_subdirectory calls — trivially maps to existing infrastructure. *)
let () =
  let ast = cmd_of_list [
    add_subdirectory "OpAdd";
    add_subdirectory "OpMul";
    add_subdirectory "OpSub";
  ] in
  Fmt.pr "%a@." (Fmt.vbox pp) ast
