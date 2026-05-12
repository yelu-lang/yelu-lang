open Yelu_langs.Lang_yelu_cmake
open Yelu_langs.Yelu_cmake_utils
open Step_common_ir

(* TutorialProject/MathFunctions/CMakeLists.txt *)
let cmd =
  ycmd_of_list [
    add_lib (ytval "MathFunctions");
    add_lib_alias ~alias_of:"MathFunctions" "Tutorial::MathFunctions";
    yc_target_sources_fs (ytval "MathFunctions") [
      ytsi_plain Private [ yfile "MathFunctions.cxx" ];
      ytsi_file_set_headers ~files:[ yfile "MathFunctions.h" ] Public;
    ];
    link_lib [ ytval "MathFunctions" ] [
      ytarget_def ~kind:Private [ ytval "MathLogger"; ytval "SqrtTable" ];
      ytarget_def ~kind:Public  [ ytval "OpAdd"; ytval "OpMul"; ytval "OpSub" ];
    ];
    compile_feats (ytval "MathFunctions")
      [ { kind = Private; feature = "cxx_std_20" } ];
    yifthen (ytruthy (ycstr "TUTORIAL_USE_STD_SQRT"))
      (compile_defs (ytval "MathFunctions")
        [ ytarget_def ~kind:Private [ ykeyword "TUTORIAL_USE_STD_SQRT" ] ]);
    yc_include (yname "CheckIncludeFiles");
    yc_apply (yname "check_include_files")
      [ yfile "emmintrin.h"; ycstr "HAS_EMMINTRIN";
        ykeyword "LANGUAGE"; ykeyword "CXX" ];
    yifthen (ytruthy (ycstr "HAS_EMMINTRIN"))
      (compile_defs (ytval "MathFunctions")
        [ ytarget_def ~kind:Private [ ykeyword "TUTORIAL_USE_SSE2" ] ]);
    yc_include (yname "CheckSourceCompiles");
    yc_apply (yname "check_source_compiles")
      [ ykeyword "CXX";
        ystr_eval {|[=[
    typedef double v2df __attribute__((vector_size(16)));
    int main() {
      __builtin_ia32_sqrtsd(v2df{});
    }
  ]=]|};
        ycstr "HAS_GNU_BUILTIN" ];
    yifthen (ytruthy (ycstr "HAS_GNU_BUILTIN"))
      (compile_defs (ytval "MathFunctions")
        [ ytarget_def ~kind:Private [ ykeyword "TUTORIAL_USE_GNU_BUILTIN" ] ]);
    yc_add_subdirectory (ydir "MathLogger");
    yc_add_subdirectory (ydir "MathExtensions");
    yc_add_subdirectory (ydir "MakeTable");
  ]

let () = print_cmake cmd
