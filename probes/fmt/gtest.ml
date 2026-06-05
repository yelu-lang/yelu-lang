(* fmt test/gtest/CMakeLists.txt — whole-file emit. *)

open Yelu_langs.Yelu_cmake
open Yelu_langs.Yelu_cmake_utils
open Yelu_langs.Yelu_cmake_target

let helpers = ESeq [
  ECmakeAddLibrary {
    name = ystr "gtest"; type_ = Some "STATIC";
    sources = [
      ystr "gmock-gtest-all.cc"; ystr "gmock/gmock.h";
      ystr "gtest/gtest.h"; ystr "gtest/gtest-spi.h";
    ];
  };
  ECmakeTargetCompileDefinitions {
    target = ystr "gtest"; visibility = "PUBLIC";
    definitions = [ystr "GTEST_HAS_STD_WSTRING=1"];
  };
  ECmakeTargetIncludeDirectories {
    target = ystr "gtest"; visibility = "PUBLIC";
    before = false; system = true; dirs = [ystr "."];
  };
  ECmakeTargetCompileFeatures {
    target = ystr "gtest"; visibility = "PUBLIC";
    features = [ystr "cxx_std_11"];
  };

  yc_apply (ystr "find_package") [ystr "Threads"];
  Yelu_langs.Yelu_cmake_if.ECmakeIfStmt {
    cond = EVar "Threads_FOUND";
    then_ = yc_apply (ystr "target_link_libraries")
              [ystr "gtest"; EVar "CMAKE_THREAD_LIBS_INIT"];
    else_ = Some (ECmakeTargetCompileDefinitions {
      target = ystr "gtest"; visibility = "PUBLIC";
      definitions = [ystr "GTEST_HAS_PTHREAD=0"];
    });
  };

  yifthen (EVar "MSVC") (ESeq [
    ECmakeTargetCompileDefinitions {
      target = ystr "gtest"; visibility = "PRIVATE";
      definitions = [ystr "_CRT_SECURE_NO_WARNINGS"];
    };
    yifthen
      (Yelu_langs.Yelu_cmake_string.ECmakeMatches
         { expr_ = EVar "CMAKE_CXX_COMPILER_ID"; regex = "Clang" })
      (ECmakeTargetCompileOptions {
        target = ystr "gtest"; visibility = "PUBLIC";
        before = false; options_ = [ystr "-Wno-deprecated-declarations"];
      });
  ]);
]

let () =
  let cmake_ast = Yelu_langs.Yelu_cmake_emit.emit_ast helpers in
  let buf = Buffer.create 512 in
  let ff = Format.formatter_of_buffer buf in
  Format.pp_open_vbox ff 0;
  Yelu_langs.Lang_cmake_pp.pp ff cmake_ast;
  Format.pp_close_box ff ();
  Format.pp_print_flush ff ();
  print_string (Buffer.contents buf);
  print_newline ()
