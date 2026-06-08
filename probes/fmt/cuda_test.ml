(* fmt test/cuda-test/CMakeLists.txt — whole-file emit.
   FMT_CUDA_TEST is OFF by default; this file is included only when ON.
   Matrix oracle doesn't exercise it, so we only need syntactic validity. *)

open Yelu_langs.Yelu_cmake
open Yelu_langs.Yelu_cmake_utils
open Yelu_langs.Yelu_cmake_target

let pre_3_15_branch = ESeq [
  yc_list_append "CUDA_NVCC_FLAGS" [EString "-std=c++14"];
  yifthen (EVar "MSVC") (ESeq [
    yc_list_append "CUDA_NVCC_FLAGS"
      [EString "-Xcompiler"; EString "/std:c++14"];
    yc_list_append "CUDA_NVCC_FLAGS"
      [EString "-Xcompiler"; EString "/Zc:__cplusplus"];
  ]);
  yc_apply (ystr "cuda_add_executable")
    [ystr "fmt-in-cuda-test"; ystr "cuda-cpp14.cu"; ystr "cpp14.cc"];
  ECmakeTargetCompileFeatures {
    target = ystr "fmt-in-cuda-test"; visibility = Vis_private;
    features = [ystr "cxx_std_14"];
  };
  yifthen (EVar "MSVC")
    (ECmakeTargetCompileOptions {
      target = ystr "fmt-in-cuda-test"; visibility = Vis_private;
      before = false;
      options_ = [ystr "/Zc:__cplusplus"; ystr "/permissive-"];
    });
]

let post_3_15_branch = ESeq [
  ECmakeAddExecutable {
    name = ystr "fmt-in-cuda-test";
    sources = [ystr "cuda-cpp14.cu"; ystr "cpp14.cc"];
  };
  yc_set_target_properties (ystr "fmt-in-cuda-test")
    [("CUDA_SEPARABLE_COMPILATION", EString "ON")];
  ECmakeTargetCompileFeatures {
    target = ystr "fmt-in-cuda-test"; visibility = Vis_private;
    features = [ystr "cxx_std_14"];
  };
  yifthen (EVar "MSVC") (ESeq [
    yc_apply (ystr "set_property") [
      ystr "SOURCE"; ystr "cuda-cpp14.cu";
      ystr "APPEND";
      ystr "PROPERTY"; ystr "COMPILE_OPTIONS";
      ystr "-Xcompiler"; ystr "/std:c++14";
      ystr "-Xcompiler"; ystr "/Zc:__cplusplus";
    ];
    yc_apply (ystr "set_property") [
      ystr "SOURCE"; ystr "cpp14.cc";
      ystr "APPEND";
      ystr "PROPERTY"; ystr "COMPILE_OPTIONS";
      ystr "/std:c++14"; ystr "/Zc:__cplusplus";
    ];
  ]);
]

let helpers = ESeq [
  yc_set (ycvar "CMAKE_CUDA_STANDARD") [ystr "14"];
  yc_set (ycvar "CMAKE_CUDA_STANDARD_REQUIRED") [ystr "14"];
  Yelu_langs.Yelu_cmake_if.ECmakeIfStmt {
    cond = Yelu_langs.Yelu_cmake_string.ECmakeVersionLess
             (EVar "CMAKE_VERSION", ystr "3.15");
    then_ = pre_3_15_branch;
    else_ = Some post_3_15_branch;
  };
  yc_get_target_property "IN_USE_CUDA_STANDARD" "fmt-in-cuda-test" "CUDA_STANDARD";
  yc_message ["cuda_standard:          ${IN_USE_CUDA_STANDARD}"];
  yc_get_target_property "IN_USE_CUDA_STANDARD_REQUIRED" "fmt-in-cuda-test"
    "CUDA_STANDARD_REQUIRED";
  yc_message ["cuda_standard_required: ${IN_USE_CUDA_STANDARD_REQUIRED}"];
  ECmakeTargetLinkLibraries {
    target = ystr "fmt-in-cuda-test"; visibility = Vis_private;
    items = [ystr "fmt::fmt"];
  };
]

let () = Yelu_langs.Yelu_emit_main.print helpers
