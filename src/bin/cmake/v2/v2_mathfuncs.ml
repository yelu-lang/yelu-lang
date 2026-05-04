open Yelu_langs.Lang_cmake_utils
open Yelu_langs.Lang_cmake_pp

(* TutorialProject/MathFunctions/CMakeLists.txt *)
let () =
  let ast = cmd_of_list [
    add_library "MathFunctions";
    add_library_alias "Tutorial::MathFunctions" ~alias_of:"MathFunctions";
    target_sources_fs "MathFunctions" [
      ts_plain "PRIVATE" [ str_ "MathFunctions.cxx" ];
      file_set_headers ~files:[ "MathFunctions.h" ] "PUBLIC";
    ];
    target_link_libraries [ "MathFunctions" ] [
      target_def ~kind:"PRIVATE" [ str_ "MathLogger"; str_ "SqrtTable" ];
      target_def ~kind:"PUBLIC"  [ str_ "OpAdd"; str_ "OpMul"; str_ "OpSub" ];
    ];
    target_compile_features "MathFunctions"
      [ target_feature ~kind:"PRIVATE" "cxx_std_20" ];
    ifthen [ "TUTORIAL_USE_STD_SQRT" ]
      (target_compile_definitions "MathFunctions"
        [ target_def ~kind:"PRIVATE" [ str_ "TUTORIAL_USE_STD_SQRT" ] ]);
    include_ (str_ "CheckIncludeFiles");
    apply "check_include_files"
      [ str_ "emmintrin.h"; str_ "HAS_EMMINTRIN"; str_ "LANGUAGE"; str_ "CXX" ];
    ifthen [ "HAS_EMMINTRIN" ]
      (target_compile_definitions "MathFunctions"
        [ target_def ~kind:"PRIVATE" [ str_ "TUTORIAL_USE_SSE2" ] ]);
    include_ (str_ "CheckSourceCompiles");
    apply "check_source_compiles"
      [ str_ "CXX";
        bracket_str {|
    typedef double v2df __attribute__((vector_size(16)));
    int main() {
      __builtin_ia32_sqrtsd(v2df{});
    }
  |};
        str_ "HAS_GNU_BUILTIN" ];
    ifthen [ "HAS_GNU_BUILTIN" ]
      (target_compile_definitions "MathFunctions"
        [ target_def ~kind:"PRIVATE" [ str_ "TUTORIAL_USE_GNU_BUILTIN" ] ]);
    add_subdirectory "MathLogger";
    add_subdirectory "MathExtensions";
    add_subdirectory "MakeTable";
  ] in
  Fmt.pr "%a@." (Fmt.vbox pp) ast
