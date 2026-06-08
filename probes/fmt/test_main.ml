(* fmt test/CMakeLists.txt — whole-file emit.
   Preamble + add_fmt_test fn + ~20 callsites + perf-sanity + posix-mock
   + FMT_PEDANTIC block + add_test driver block + cuda + c-test. *)

open Yelu_langs.Yelu_cmake
open Yelu_langs.Yelu_cmake_utils
open Yelu_langs.Yelu_cmake_target

(* ---------- helpers ---------- *)

let add_test name args = yc_apply (ystr "add_fmt_test") (ystr name :: args)
let aft name = add_test name []
let aft_args name args =
  add_test name (List.map (fun s -> ystr s) args)

let add_fmt_test_fn =
  yc_function (ystr "add_fmt_test") ["name"] [
    yc_apply (ystr "cmake_parse_arguments")
      [ystr "ADD_FMT_TEST"; ystr "HEADER_ONLY;MODULE"; ystr ""; ystr "";
       EVar "ARGN"];
    yc_set (ycvar "sources")
      [ystr "${name}.cc"; EVar "ADD_FMT_TEST_UNPARSED_ARGUMENTS"];
    Yelu_langs.Yelu_cmake_if.ECmakeIfStmt {
      cond = EVar "ADD_FMT_TEST_HEADER_ONLY";
      then_ = ESeq [
        yc_set (ycvar "sources")
          [EVar "sources"; EVar "TEST_MAIN_SRC"; ystr "../src/os.cc"];
        yc_set (ycvar "libs") [ystr "gtest"; ystr "fmt-header-only"];
        yifthen
          (Yelu_langs.Yelu_cmake_string.ECmakeMatches
             { expr_ = EVar "CMAKE_CXX_COMPILER_ID"; regex = "Clang" })
          (yc_set (ycvar "PEDANTIC_COMPILE_FLAGS")
             [EVar "PEDANTIC_COMPILE_FLAGS"; ystr "-Wno-weak-vtables"]);
      ];
      else_ = Some (Yelu_langs.Yelu_cmake_if.ECmakeIfStmt {
        cond = EVar "ADD_FMT_TEST_MODULE";
        then_ = yc_set (ycvar "libs") [ystr "test-main"; ystr "fmt-module"];
        else_ = Some (yc_set (ycvar "libs") [ystr "test-main"; ystr "fmt"]);
      });
    };
    ECmakeAddExecutable { name = EVar "name"; sources = [EVar "sources"] };
    ECmakeTargetLinkLibraries {
      target = EVar "name"; visibility = "PUBLIC"; items = [EVar "libs"];
    };
    yifthen
      (Yelu_langs.Yelu_cmake_normal_bool.EAnd
         (EVar "ADD_FMT_TEST_HEADER_ONLY", ynot (EVar "FMT_UNICODE")))
      (ECmakeTargetCompileDefinitions {
        target = EVar "name"; visibility = "PUBLIC";
        definitions = [EString "FMT_UNICODE=0"];
      });
    yifthen (EVar "FMT_PEDANTIC")
      (ECmakeTargetCompileOptions {
        target = EVar "name"; visibility = "PRIVATE"; before = false;
        options_ = [EVar "PEDANTIC_COMPILE_FLAGS"];
      });
    yifthen (EVar "FMT_WERROR")
      (ECmakeTargetCompileOptions {
        target = EVar "name"; visibility = "PRIVATE"; before = false;
        options_ = [EVar "WERROR_FLAG"];
      });
    yc_add_test (EVar "name") (EVar "name") [];
  ]

(* ---------- preamble ---------- *)

let preamble = ESeq [
  yc_add_subdirectory (ystr "gtest");
  yc_set (ycvar "TEST_MAIN_SRC")
    [ystr "test-main.cc"; ystr "gtest-extra.cc";
     ystr "gtest-extra.h"; ystr "util.cc"];
  ECmakeAddLibrary {
    name = ystr "test-main"; type_ = Some "STATIC";
    sources = [EVar "TEST_MAIN_SRC"];
  };
  ECmakeTargetIncludeDirectories {
    target = ystr "test-main"; visibility = "PUBLIC";
    before = false; system = false;
    dirs = [ystr "$<BUILD_INTERFACE:${PROJECT_SOURCE_DIR}/include>"];
  };
  ECmakeTargetLinkLibraries {
    target = ystr "test-main"; visibility = "PUBLIC";
    items = [ystr "gtest"; ystr "fmt"];
  };
]

(* ---------- test callsites between the function and the std-test block ---------- *)

let basic_aft_block = ESeq [
  aft "args-test";
  aft "base-test";
  aft "assert-test";
  aft "chrono-test";
  aft "color-test";
  aft "gtest-extra-test";
  aft_args "format-test" ["mock-allocator.h"];
  yifthen (EVar "MSVC")
    (ECmakeTargetCompileOptions {
      target = ystr "format-test"; visibility = "PRIVATE"; before = false;
      options_ = [EString "/bigobj"];
    });
  yifthen
    (ynot (Yelu_langs.Yelu_cmake_normal_bool.EAnd
             (EVar "MSVC", EVar "BUILD_SHARED_LIBS")))
    (aft_args "format-impl-test" ["HEADER_ONLY"; "header-only-test.cc"]);
  aft "ostream-test";
  aft "compile-test";
  aft "printf-test";
  aft_args "ranges-test" ["ranges-odr-test.cc"];
  aft_args "no-builtin-types-test" ["HEADER_ONLY"];
  aft_args "scan-test" ["HEADER_ONLY"];
  aft "std-test";

  (* try_compile detect-stdfs.cc with OUTPUT_VARIABLE *)
  Yelu_langs.Yelu_cmake_try.ECmakeTryCompileEx {
    result_var = "compile_result_unused";
    sources = [ystr "${CMAKE_CURRENT_LIST_DIR}/detect-stdfs.cc"];
    compile_definitions = [];
    link_libraries = [];
    link_options = [];
    output_variable = Some "RAWOUTPUT";
    no_cache = false;
    c_standard = None;
    cxx_standard = None;
  };
  yc_apply (ystr "string")
    [ystr "REGEX"; ystr "REPLACE";
     ystr (Yelu_langs.Yelu_emit_main.escape ".*libfound \"([^\"]*)\".*");
     ystr "\\\\1"; ystr "STDLIBFS"; ystr "${RAWOUTPUT}"];
  yifthen (EVar "STDLIBFS")
    (ECmakeTargetLinkLibraries {
      target = ystr "std-test"; visibility = "PUBLIC";
      items = [EVar "STDLIBFS"];
    });

  aft_args "unicode-test" ["HEADER_ONLY"];
  yifthen (EVar "MSVC")
    (ECmakeTargetCompileOptions {
      target = ystr "unicode-test"; visibility = "PRIVATE"; before = false;
      options_ = [EString "/utf-8"];
    });
  aft "xchar-test";
  aft "enforce-checks-test";
  ECmakeTargetCompileDefinitions {
    target = ystr "enforce-checks-test"; visibility = "PRIVATE";
    definitions = [EString "-DFMT_ENFORCE_COMPILE_STRING"];
  };

  ECmakeAddExecutable { name = ystr "perf-sanity"; sources = [ystr "perf-sanity.cc"] };
  ECmakeTargetLinkLibraries {
    target = ystr "perf-sanity"; visibility = "PUBLIC";
    items = [ystr "fmt::fmt"];
  };

  yifthen (EVar "FMT_MODULE")
    (aft_args "module-test" ["MODULE"]);
]

(* ---------- MSVC static-runtime probe + posix-mock-test ---------- *)

let msvc_runtime_block = ESeq [
  yifthen
    (Yelu_langs.Yelu_cmake_normal_bool.EAnd
       (ynot (Yelu_langs.Yelu_cmake_store.ECmakeVarDefined "MSVC_STATIC_RUNTIME"),
        EVar "MSVC"))
    (yc_foreach_in
       ~items:[
         ystr "CMAKE_CXX_FLAGS"; ystr "CMAKE_CXX_FLAGS_DEBUG";
         ystr "CMAKE_CXX_FLAGS_RELEASE"; ystr "CMAKE_CXX_FLAGS_MINSIZEREL";
         ystr "CMAKE_CXX_FLAGS_RELWITHDEBINFO";
       ]
       (ycvar "flag_var")
       (yifthen
          (Yelu_langs.Yelu_cmake_string.ECmakeMatches
             { expr_ = ystr "${${flag_var}}"; regex = "^(/|-)(MT|MTd)" })
          (ESeq [
            yc_set (ycvar "MSVC_STATIC_RUNTIME") [ystr "ON"];
            yc_break;
          ])));

  yifthen (ynot (EVar "MSVC_STATIC_RUNTIME")) (ESeq [
    ECmakeAddExecutable {
      name = ystr "posix-mock-test";
      sources = [ystr "posix-mock-test.cc"; ystr "../src/format.cc";
                 EVar "TEST_MAIN_SRC"];
    };
    ECmakeTargetIncludeDirectories {
      target = ystr "posix-mock-test"; visibility = "PRIVATE";
      before = false; system = false;
      dirs = [ystr "${PROJECT_SOURCE_DIR}/include"];
    };
    ECmakeTargetLinkLibraries {
      target = ystr "posix-mock-test"; visibility = "PUBLIC";
      items = [ystr "gtest"];
    };
    yifthen (EVar "FMT_PEDANTIC")
      (ECmakeTargetCompileOptions {
        target = ystr "posix-mock-test"; visibility = "PRIVATE";
        before = false; options_ = [EVar "PEDANTIC_COMPILE_FLAGS"];
      });
    yifthen (EVar "MSVC")
      (ECmakeTargetCompileOptions {
        target = ystr "posix-mock-test"; visibility = "PRIVATE";
        before = false; options_ = [EString "/utf-8"];
      });
    yc_add_test (ystr "posix-mock-test") (ystr "posix-mock-test") [];
    aft "os-test";
  ]);

  yc_message ["FMT_PEDANTIC: ${FMT_PEDANTIC}"];
]

(* ---------- FMT_PEDANTIC noexception + nolocale blocks ---------- *)

let pedantic_block =
  yifthen (EVar "FMT_PEDANTIC") (ESeq [
    yifthen
      (ynot (Yelu_langs.Yelu_cmake_string.ECmakeStringEqual
               (EVar "CMAKE_CXX_COMPILER_ID", ystr "Intel")))
      (yc_apply (ystr "check_cxx_compiler_flag")
         [ystr "-fno-exceptions"; ystr "HAVE_FNO_EXCEPTIONS_FLAG"]);
    yifthen (EVar "HAVE_FNO_EXCEPTIONS_FLAG") (ESeq [
      ECmakeAddLibrary {
        name = ystr "noexception-test"; type_ = None;
        sources = [ystr "../src/format.cc"; ystr "noexception-test.cc"];
      };
      ECmakeTargetIncludeDirectories {
        target = ystr "noexception-test"; visibility = "PRIVATE";
        before = false; system = false;
        dirs = [ystr "${PROJECT_SOURCE_DIR}/include"];
      };
      ECmakeTargetCompileOptions {
        target = ystr "noexception-test"; visibility = "PRIVATE";
        before = false; options_ = [EString "-fno-exceptions"];
      };
      ECmakeTargetCompileOptions {
        target = ystr "noexception-test"; visibility = "PRIVATE";
        before = false; options_ = [EVar "PEDANTIC_COMPILE_FLAGS"];
      };
    ]);
    ECmakeAddLibrary {
      name = ystr "nolocale-test"; type_ = None;
      sources = [ystr "../src/format.cc"];
    };
    ECmakeTargetIncludeDirectories {
      target = ystr "nolocale-test"; visibility = "PRIVATE";
      before = false; system = false;
      dirs = [ystr "${PROJECT_SOURCE_DIR}/include"];
    };
    ECmakeTargetCompileDefinitions {
      target = ystr "nolocale-test"; visibility = "PRIVATE";
      definitions = [EString "FMT_STATIC_THOUSANDS_SEPARATOR=1"];
    };
  ])

(* ---------- ctest --build-and-test drivers ---------- *)

let build_and_test_args =
  [ ystr "${CMAKE_CTEST_COMMAND}";
    ystr "--build-and-test";
  ]

let driver_block = ESeq [
  yifthen
    (Yelu_langs.Yelu_cmake_normal_bool.EAnd
       (EVar "FMT_PEDANTIC",
        Yelu_langs.Yelu_cmake_normal_bool.EAnd
          (ynot (EVar "WIN32"),
           ynot (Yelu_langs.Yelu_cmake_normal_bool.EAnd
                   (Yelu_langs.Yelu_cmake_string.ECmakeMatches
                      { expr_ = EVar "CMAKE_CXX_COMPILER_ID"; regex = "GNU" },
                    Yelu_langs.Yelu_cmake_string.ECmakeVersionLess
                      (EVar "CMAKE_CXX_COMPILER_VERSION", ystr "4.9"))))))
    (ESeq [
      yc_apply (ystr "add_test") (
        [ystr "compile-error-test"]
        @ build_and_test_args
        @ [ystr "${CMAKE_CURRENT_SOURCE_DIR}/compile-error-test";
           ystr "${CMAKE_CURRENT_BINARY_DIR}/compile-error-test";
           ystr "--build-generator"; ystr "${CMAKE_GENERATOR}";
           ystr "--build-makeprogram"; ystr "${CMAKE_MAKE_PROGRAM}";
           ystr "--build-options";
           ystr "-DCMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}";
           ystr "-DCMAKE_CXX_FLAGS=${CMAKE_CXX_FLAGS}";
           ystr "-DCMAKE_CXX_STANDARD=${CMAKE_CXX_STANDARD}";
           ystr "-DCXX_STANDARD_FLAG=${CXX_STANDARD_FLAG}";
           ystr "-DFMT_DIR=${CMAKE_SOURCE_DIR}"]);

      yc_apply (ystr "add_test") (
        [ystr "find-package-test"; ystr "-C"; ystr "${CMAKE_BUILD_TYPE}"]
        @ build_and_test_args
        @ [ystr "${CMAKE_CURRENT_SOURCE_DIR}/find-package-test";
           ystr "${CMAKE_CURRENT_BINARY_DIR}/find-package-test";
           ystr "--build-generator"; ystr "${CMAKE_GENERATOR}";
           ystr "--build-makeprogram"; ystr "${CMAKE_MAKE_PROGRAM}";
           ystr "--build-options";
           ystr "-DCMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}";
           ystr "-DCMAKE_CXX_FLAGS=${CMAKE_CXX_FLAGS}";
           ystr "-DCMAKE_CXX_STANDARD=${CMAKE_CXX_STANDARD}";
           ystr "-DFMT_DIR=${PROJECT_BINARY_DIR}";
           ystr "-DPEDANTIC_COMPILE_FLAGS=${PEDANTIC_COMPILE_FLAGS}";
           ystr "-DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}"]);

      yc_apply (ystr "add_test") (
        [ystr "add-subdirectory-test"; ystr "-C"; ystr "${CMAKE_BUILD_TYPE}"]
        @ build_and_test_args
        @ [ystr "${CMAKE_CURRENT_SOURCE_DIR}/add-subdirectory-test";
           ystr "${CMAKE_CURRENT_BINARY_DIR}/add-subdirectory-test";
           ystr "--build-generator"; ystr "${CMAKE_GENERATOR}";
           ystr "--build-makeprogram"; ystr "${CMAKE_MAKE_PROGRAM}";
           ystr "--build-options";
           ystr "-DCMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}";
           ystr "-DCMAKE_CXX_STANDARD=${CMAKE_CXX_STANDARD}";
           ystr "-DPEDANTIC_COMPILE_FLAGS=${PEDANTIC_COMPILE_FLAGS}";
           ystr "-DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}"]);
    ]);

  yifthen
    (Yelu_langs.Yelu_cmake_normal_bool.EAnd
       (EVar "FMT_PEDANTIC", ynot (EVar "WIN32")))
    (yc_apply (ystr "add_test") (
       [ystr "static-export-test"; ystr "-C"; ystr "${CMAKE_BUILD_TYPE}"]
       @ build_and_test_args
       @ [ystr "${CMAKE_CURRENT_SOURCE_DIR}/static-export-test";
          ystr "${CMAKE_CURRENT_BINARY_DIR}/static-export-test";
          ystr "--build-generator"; ystr "${CMAKE_GENERATOR}";
          ystr "--build-makeprogram"; ystr "${CMAKE_MAKE_PROGRAM}";
          ystr "--build-options";
          ystr "-DCMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}";
          ystr "-DCMAKE_CXX_STANDARD=${CMAKE_CXX_STANDARD}";
          ystr "-DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}"]));
]

(* ---------- CUDA + C tests ---------- *)

let cuda_block =
  yifthen (EVar "FMT_CUDA_TEST") (ESeq [
    Yelu_langs.Yelu_cmake_if.ECmakeIfStmt {
      cond = Yelu_langs.Yelu_cmake_string.ECmakeVersionLess
               (EVar "CMAKE_VERSION", ystr "3.15");
      then_ = yc_apply (ystr "find_package") [ystr "CUDA"; ystr "9.0"];
      else_ = Some (ESeq [
        yc_include (ystr "CheckLanguage");
        yc_apply (ystr "check_language") [ystr "CUDA"];
        yifthen (EVar "CMAKE_CUDA_COMPILER") (ESeq [
          yc_apply (ystr "enable_language") [ystr "CUDA"; ystr "OPTIONAL"];
          yc_set (ycvar "CUDA_FOUND") [ystr "TRUE"];
        ]);
      ]);
    };
    yifthen (EVar "CUDA_FOUND") (ESeq [
      yc_add_subdirectory (ystr "cuda-test");
      yc_add_test (ystr "cuda-test") (ystr "fmt-in-cuda-test") [];
    ]);
  ])

let c_block = ESeq [
  yc_apply (ystr "enable_language") [ystr "C"];
  ECmakeAddExecutable { name = ystr "c-test"; sources = [ystr "c-test.c"] };
  ECmakeTargetLinkLibraries {
    target = ystr "c-test"; visibility = "PRIVATE";
    items = [ystr "fmt::fmt-c"];
  };
  yc_apply (ystr "add_test")
    [ystr "NAME"; ystr "c-test"; ystr "COMMAND"; ystr "c-test"];
]

let helpers = ESeq [
  preamble;
  add_fmt_test_fn;
  basic_aft_block;
  msvc_runtime_block;
  pedantic_block;
  driver_block;
  cuda_block;
  c_block;
]

let () = Yelu_langs.Yelu_emit_main.print helpers
