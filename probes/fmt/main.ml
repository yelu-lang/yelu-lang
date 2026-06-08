(* fmt CMakeLists.txt — whole-file emit (Phase 6).
   Supersedes the splice-based set_verbose / setup_target /
   add_module_library / add_doc_target / use_cmake_modules_false
   migrations: this single .ml is the source of truth for the
   main CMakeLists.txt. *)

open Yelu_langs.Yelu_cmake
open Yelu_langs.Yelu_cmake_utils
open Yelu_langs.Yelu_cmake_target

(* ============================================================
   Preamble: cmake_minimum_required, include_guard, policy fallback,
   FMT_MASTER_PROJECT detection, join + set_verbose helpers, BUILD_TYPE. *)

let preamble = ESeq [
  yc_apply (ystr "cmake_minimum_required") [ystr "VERSION"; ystr "3.8...3.28"];
  Yelu_langs.Yelu_cmake_cmake_op.ECmakeIncludeGuard { scope = "GLOBAL" };

  yifthen
    (Yelu_langs.Yelu_cmake_string.ECmakeVersionLess
       (EVar "CMAKE_VERSION", ystr "3.12"))
    (yc_apply (ystr "cmake_policy")
       [ystr "VERSION"; ystr "${CMAKE_MAJOR_VERSION}.${CMAKE_MINOR_VERSION}"]);

  yifthen
    (ynot (Yelu_langs.Yelu_cmake_store.ECmakeVarDefined "FMT_MASTER_PROJECT"))
    (ESeq [
      yc_set (ycvar "FMT_MASTER_PROJECT") [ystr "OFF"];
      yifthen
        (ynot (Yelu_langs.Yelu_cmake_store.ECmakeVarDefined "PROJECT_NAME"))
        (ESeq [
          yc_set (ycvar "FMT_MASTER_PROJECT") [ystr "ON"];
          yc_message ["CMake version: ${CMAKE_VERSION}"];
        ]);
    ]);

  yc_function (ystr "join") ["result_var"] [
    yc_set (ycvar "result") [ystr ""];
    yc_foreach ~items:[EVar "ARGN"] (ycvar "arg")
      (yc_set (ycvar "result") [ystr "${result}${arg}"]);
    yc_set ~parent_scope:true (ycvar "${result_var}") [ystr "${result}"];
  ];

  yc_function (ystr "set_verbose") ["variable"; "value"; "_cache"; "type"] [
    yc_apply (ystr "join") [ystr "doc"; EVar "ARGN"];
    Yelu_langs.Yelu_cmake_store.ECmakeSetCache {
      name = "${variable}"; values = [EVar "value"];
      cache_type = "${type}"; docstring = "${doc}"; force = false;
    };
  ];

  yifthen
    (Yelu_langs.Yelu_cmake_normal_bool.EAnd
       (EVar "FMT_MASTER_PROJECT", ynot (EVar "CMAKE_BUILD_TYPE")))
    (yc_apply (ystr "set_verbose") [
       ystr "CMAKE_BUILD_TYPE"; ystr "Release"; ystr "CACHE"; ystr "STRING";
       ystr "Choose the type of build, options are: None(CMAKE_CXX_FLAGS or ";
       ystr "CMAKE_C_FLAGS used) Debug Release RelWithDebInfo MinSizeRel.";
     ]);
]

(* ============================================================
   project() + FMT_USE_CMAKE_MODULES detection (cmake 3.28 + compiler probes). *)

let project_and_modules_detect = ESeq [
  yc_apply (ystr "project") [ystr "FMT"; ystr "CXX"];

  yc_set (ycvar "FMT_USE_CMAKE_MODULES") [ystr "FALSE"];
  yifthen
    (Yelu_langs.Yelu_cmake_normal_bool.EAnd
       (Yelu_langs.Yelu_cmake_string.ECmakeVersionGreaterEqual
          (EVar "CMAKE_VERSION", ystr "3.28"),
        Yelu_langs.Yelu_cmake_string.ECmakeVersionGreaterEqual
          (EVar "CMAKE_CXX_STANDARD", ystr "20")))
    (Yelu_langs.Yelu_cmake_if.ECmakeIfStmt {
      cond = Yelu_langs.Yelu_cmake_string.ECmakeStringEqual
               (EVar "CMAKE_GENERATOR", ystr "Ninja");
      then_ = ESeq [
        Yelu_langs.Yelu_cmake_cmake_op.ECmakeExecuteProcess {
          commands = [[EString "${CMAKE_MAKE_PROGRAM}"; EString "--version"]];
          working_directory = None; timeout = None;
          result_variable = None;
          output_variable = Some "NINJA_VERSION"; error_variable = None;
          input_file = None; output_file = None; error_file = None;
          output_quiet = false; error_quiet = false;
          output_strip_trailing_whitespace = false;
          error_strip_trailing_whitespace = false;
          command_error_is_fatal = None;
        };
        yifthen
          (Yelu_langs.Yelu_cmake_string.ECmakeVersionGreaterEqual
             (EVar "NINJA_VERSION", ystr "1.11"))
          (yifthen
             (Yelu_langs.Yelu_cmake_normal_bool.EOr
                (Yelu_langs.Yelu_cmake_normal_bool.EAnd
                   (Yelu_langs.Yelu_cmake_string.ECmakeStringEqual
                      (EVar "CMAKE_CXX_COMPILER_ID", ystr "GNU"),
                    Yelu_langs.Yelu_cmake_string.ECmakeVersionGreaterEqual
                      (EVar "CMAKE_CXX_COMPILER_VERSION", ystr "15")),
                 Yelu_langs.Yelu_cmake_normal_bool.EOr
                   (Yelu_langs.Yelu_cmake_normal_bool.EAnd
                      (Yelu_langs.Yelu_cmake_string.ECmakeStringEqual
                         (EVar "CMAKE_CXX_COMPILER_ID", ystr "Clang"),
                       Yelu_langs.Yelu_cmake_string.ECmakeVersionGreaterEqual
                         (EVar "CMAKE_CXX_COMPILER_VERSION", ystr "16")),
                    Yelu_langs.Yelu_cmake_normal_bool.EAnd
                      (Yelu_langs.Yelu_cmake_string.ECmakeStringEqual
                         (EVar "CMAKE_CXX_COMPILER_ID", ystr "MSVC"),
                       Yelu_langs.Yelu_cmake_string.ECmakeVersionGreaterEqual
                         (EVar "MSVC_VERSION", ystr "1934")))))
             (yc_set (ycvar "FMT_USE_CMAKE_MODULES") [ystr "TRUE"]));
      ];
      else_ = Some (
        yifthen
          (Yelu_langs.Yelu_cmake_normal_bool.EAnd
             (Yelu_langs.Yelu_cmake_string.ECmakeMatches
                { expr_ = EVar "CMAKE_GENERATOR"; regex = "^Visual Studio" },
              Yelu_langs.Yelu_cmake_string.ECmakeVersionGreaterEqual
                (EVar "MSVC_VERSION", ystr "1934")))
          (yc_set (ycvar "FMT_USE_CMAKE_MODULES") [ystr "TRUE"]));
    });
]

(* ============================================================
   options() declarations + FMT_SYSTEM_HEADERS_ATTRIBUTE +
   GNUInstallDirs + FMT_INC_DIR + FMT_DEBUG_POSTFIX. *)

let opt name help default =
  yc_option name ~msg:help ~value:default

let options_block = ESeq [
  opt "FMT_DOC" "Generate the doc target." (EVar "FMT_MASTER_PROJECT");
  opt "FMT_INSTALL" "Generate the install target." (EVar "FMT_MASTER_PROJECT");
  opt "FMT_TEST" "Generate the test target." (EVar "FMT_MASTER_PROJECT");
  opt "FMT_FUZZ" "Generate the fuzz target." (EBool false);
  opt "FMT_CUDA_TEST" "Generate the cuda-test target." (EBool false);
  opt "FMT_OS" "Include OS-specific APIs." (EBool true);
  opt "FMT_MODULE" "Build a module library." (EVar "FMT_USE_CMAKE_MODULES");
  opt "FMT_SYSTEM_HEADERS" "Expose headers with marking them as system."
    (EBool false);
  opt "FMT_UNICODE" "Enable Unicode support." (EBool true);
  opt "FMT_PEDANTIC" "Enable extra warnings and expensive tests." (EBool false);
  opt "FMT_WERROR" "Halt the compilation with an error on compiler warnings."
    (EBool false);

  yc_set (ycvar "FMT_SYSTEM_HEADERS_ATTRIBUTE") [ystr ""];
  yifthen (EVar "FMT_SYSTEM_HEADERS")
    (yc_set (ycvar "FMT_SYSTEM_HEADERS_ATTRIBUTE") [ystr "SYSTEM"]);

  yc_include (ystr "GNUInstallDirs");

  yc_apply (ystr "set_verbose") [
    ystr "FMT_INC_DIR"; EVar "CMAKE_INSTALL_INCLUDEDIR";
    ystr "CACHE"; ystr "STRING";
    ystr "Installation directory for include files, a relative path that ";
    ystr "will be joined with ${CMAKE_INSTALL_PREFIX} or an absolute path.";
  ];

  Yelu_langs.Yelu_cmake_store.ECmakeSetCache {
    name = "FMT_DEBUG_POSTFIX"; values = [ystr "d"];
    cache_type = "STRING"; docstring = "Debug library postfix."; force = false;
  };
]

(* ============================================================
   VERSION detection from base.h, build-type message, output dirs,
   module path, includes. *)

let version_block = ESeq [
  Yelu_langs.Yelu_cmake_file.ECmakeFileRead {
    path = ystr "include/fmt/base.h"; out = "base_h";
  };
  yifthen
    (ynot (Yelu_langs.Yelu_cmake_string.ECmakeMatches
             { expr_ = EVar "base_h";
               regex = "FMT_VERSION ([0-9]+)([0-9][0-9])([0-9][0-9])" }))
    (yc_message_mode "FATAL_ERROR" ["Cannot get FMT_VERSION from base.h."]);
  Yelu_langs.Yelu_cmake_cmake_op.ECmakeMath {
    exp = "${CMAKE_MATCH_1}"; out = "CPACK_PACKAGE_VERSION_MAJOR";
  };
  Yelu_langs.Yelu_cmake_cmake_op.ECmakeMath {
    exp = "${CMAKE_MATCH_2}"; out = "CPACK_PACKAGE_VERSION_MINOR";
  };
  Yelu_langs.Yelu_cmake_cmake_op.ECmakeMath {
    exp = "${CMAKE_MATCH_3}"; out = "CPACK_PACKAGE_VERSION_PATCH";
  };
  yc_apply (ystr "join") [
    ystr "FMT_VERSION";
    ystr "${CPACK_PACKAGE_VERSION_MAJOR}.${CPACK_PACKAGE_VERSION_MINOR}.";
    ystr "${CPACK_PACKAGE_VERSION_PATCH}";
  ];
  yc_message ["{fmt} version: ${FMT_VERSION}"];
  yc_message ["Build type: ${CMAKE_BUILD_TYPE}"];

  yifthen (ynot (EVar "CMAKE_RUNTIME_OUTPUT_DIRECTORY"))
    (yc_set (ycvar "CMAKE_RUNTIME_OUTPUT_DIRECTORY")
       [ystr "${CMAKE_CURRENT_BINARY_DIR}/bin"]);

  yc_list_append "CMAKE_MODULE_PATH"
    [EString "${CMAKE_CURRENT_SOURCE_DIR}/support/cmake"];

  yc_include (ystr "CheckCXXCompilerFlag");
  yc_include (ystr "JoinPaths");
]

(* ============================================================
   Visibility presets + PEDANTIC_COMPILE_FLAGS per-compiler chain. *)

let pedantic_gnu_flags = [
  "-pedantic-errors"; "-Wall"; "-Wextra"; "-pedantic"; "-Wold-style-cast";
  "-Wundef"; "-Wredundant-decls"; "-Wwrite-strings"; "-Wpointer-arith";
  "-Wcast-qual"; "-Wformat=2"; "-Wmissing-include-dirs"; "-Wcast-align";
  "-Wctor-dtor-privacy"; "-Wdisabled-optimization"; "-Winvalid-pch";
  "-Woverloaded-virtual"; "-Wconversion"; "-Wundef"; "-Wno-ctor-dtor-privacy";
  "-Wno-format-nonliteral";
]

let pedantic_clang_flags = [
  "-Wall"; "-Wextra"; "-pedantic"; "-Wconversion"; "-Wundef"; "-Wdeprecated";
  "-Wweak-vtables"; "-Wshadow"; "-Wno-gnu-zero-variadic-macro-arguments";
]

let visibility_and_flags = ESeq [
  yifthen
    (Yelu_langs.Yelu_cmake_normal_bool.EAnd
       (EVar "FMT_MASTER_PROJECT",
        ynot (Yelu_langs.Yelu_cmake_store.ECmakeVarDefined "CMAKE_CXX_VISIBILITY_PRESET")))
    (ESeq [
      yc_apply (ystr "set_verbose") [
        ystr "CMAKE_CXX_VISIBILITY_PRESET"; ystr "hidden";
        ystr "CACHE"; ystr "STRING";
        ystr "Preset for the export of private symbols.";
      ];
      yc_apply (ystr "set_property") [
        ystr "CACHE"; ystr "CMAKE_CXX_VISIBILITY_PRESET";
        ystr "PROPERTY"; ystr "STRINGS"; ystr "hidden"; ystr "default";
      ];
    ]);

  yifthen
    (Yelu_langs.Yelu_cmake_normal_bool.EAnd
       (EVar "FMT_MASTER_PROJECT",
        ynot (Yelu_langs.Yelu_cmake_store.ECmakeVarDefined "CMAKE_VISIBILITY_INLINES_HIDDEN")))
    (yc_apply (ystr "set_verbose") [
      ystr "CMAKE_VISIBILITY_INLINES_HIDDEN"; ystr "ON";
      ystr "CACHE"; ystr "BOOL";
      ystr "Whether to add a compile flag to hide symbols of inline ";
      ystr "functions.";
    ]);

  yifthen
    (Yelu_langs.Yelu_cmake_string.ECmakeMatches
       { expr_ = EVar "CMAKE_CXX_COMPILER_ID"; regex = "GNU" })
    (ESeq [
      yc_set (ycvar "PEDANTIC_COMPILE_FLAGS")
        (List.map ystr pedantic_gnu_flags);
      yifthen
        (ynot (Yelu_langs.Yelu_cmake_string.ECmakeVersionLess
                 (EVar "CMAKE_CXX_COMPILER_VERSION", ystr "4.6")))
        (yc_set (ycvar "PEDANTIC_COMPILE_FLAGS")
           [EVar "PEDANTIC_COMPILE_FLAGS";
            ystr "-Wno-dangling-else"; ystr "-Wno-unused-local-typedefs"]);
      yifthen
        (ynot (Yelu_langs.Yelu_cmake_string.ECmakeVersionLess
                 (EVar "CMAKE_CXX_COMPILER_VERSION", ystr "5.0")))
        (yc_set (ycvar "PEDANTIC_COMPILE_FLAGS")
           [EVar "PEDANTIC_COMPILE_FLAGS";
            ystr "-Wdouble-promotion"; ystr "-Wtrampolines";
            ystr "-Wzero-as-null-pointer-constant"; ystr "-Wuseless-cast";
            ystr "-Wvector-operation-performance"; ystr "-Wsized-deallocation";
            ystr "-Wshadow"]);
      yifthen
        (ynot (Yelu_langs.Yelu_cmake_string.ECmakeVersionLess
                 (EVar "CMAKE_CXX_COMPILER_VERSION", ystr "6.0")))
        (ESeq [
          yc_set (ycvar "PEDANTIC_COMPILE_FLAGS")
            [EVar "PEDANTIC_COMPILE_FLAGS";
             ystr "-Wshift-overflow=2"; ystr "-Wduplicated-cond"];
          yifthen
            (Yelu_langs.Yelu_cmake_string.ECmakeVersionLess
               (EVar "CMAKE_CXX_COMPILER_VERSION", ystr "12.0"))
            (yc_set (ycvar "PEDANTIC_COMPILE_FLAGS")
               [EVar "PEDANTIC_COMPILE_FLAGS"; ystr "-Wnull-dereference"]);
        ]);
      yc_set (ycvar "WERROR_FLAG") [ystr "-Werror"];
    ]);

  yifthen
    (Yelu_langs.Yelu_cmake_string.ECmakeMatches
       { expr_ = EVar "CMAKE_CXX_COMPILER_ID"; regex = "Clang" })
    (ESeq [
      yc_set (ycvar "PEDANTIC_COMPILE_FLAGS")
        (List.map ystr pedantic_clang_flags);
      yc_apply (ystr "check_cxx_compiler_flag")
        [ystr "-Wzero-as-null-pointer-constant"; ystr "HAS_NULLPTR_WARNING"];
      yifthen (EVar "HAS_NULLPTR_WARNING")
        (yc_set (ycvar "PEDANTIC_COMPILE_FLAGS")
           [EVar "PEDANTIC_COMPILE_FLAGS";
            ystr "-Wzero-as-null-pointer-constant"]);
      yc_set (ycvar "WERROR_FLAG") [ystr "-Werror"];
    ]);

  yifthen (EVar "MSVC") (ESeq [
    yc_set (ycvar "PEDANTIC_COMPILE_FLAGS") [ystr "/W3"];
    yc_set (ycvar "WERROR_FLAG") [ystr "/WX"];
  ]);

  yifthen
    (Yelu_langs.Yelu_cmake_normal_bool.EAnd
       (EVar "FMT_MASTER_PROJECT",
        Yelu_langs.Yelu_cmake_string.ECmakeMatches
          { expr_ = EVar "CMAKE_GENERATOR"; regex = "Visual Studio" }))
    (* Shape C escape: this block embeds backslash-laden Windows
       paths and a multi-line bat-file body that the cmake-pp
       quoting layer can't round-trip cleanly. Emit it as raw
       cmake text — semantically equivalent, dead code on
       non-Visual-Studio configurations. *)
    (Yelu_langs.Yelu_emit_main.raw_cmake
       {|include(FindSetEnv)
if (WINSDK_SETENV)
  set(MSBUILD_SETUP "call \"${WINSDK_SETENV}\"")
endif ()
join(netfxpath
     "C:\\Program Files\\Reference Assemblies\\Microsoft\\Framework\\"
     ".NETFramework\\v4.0")
file(WRITE run-msbuild.bat "${MSBUILD_SETUP}
  ${CMAKE_MAKE_PROGRAM} -p:FrameworkPathOverride=\"${netfxpath}\" %*")
|});
]

(* ============================================================
   setup_target function + FMT_HEADERS foreach. *)

let setup_target_fn =
  yc_function (ystr "setup_target") ["target"; "kind"] [
    ECmakeAddLibraryAlias { name = "fmt::${target}"; target = "${target}" };
    yc_apply (ystr "target_include_directories") [
      EVar "target"; EVar "FMT_SYSTEM_HEADERS_ATTRIBUTE";
      ystr "BEFORE"; EVar "kind";
      ystr "$<BUILD_INTERFACE:${PROJECT_SOURCE_DIR}/include>";
      ystr "$<INSTALL_INTERFACE:${FMT_INC_DIR}>";
    ];
    Yelu_langs.Yelu_cmake_if.ECmakeIfStmt {
      cond = ynot (EVar "MSVC");
      then_ = EUnit;
      else_ = Some (
        Yelu_langs.Yelu_cmake_if.ECmakeIfStmt {
          cond = EVar "FMT_UNICODE";
          then_ = yc_apply (ystr "target_compile_options") [
            EVar "target"; EVar "kind";
            ystr "$<$<AND:$<COMPILE_LANGUAGE:CXX>,$<CXX_COMPILER_ID:MSVC>>:/utf-8>";
          ];
          else_ = Some (yc_apply (ystr "target_compile_definitions")
                          [EVar "target"; EVar "kind"; ystr "FMT_UNICODE=0"]);
        });
    };
    yc_set_target_properties (EVar "target")
      [("VERSION", EVar "FMT_VERSION");
       ("SOVERSION", EVar "CPACK_PACKAGE_VERSION_MAJOR");
       ("DEBUG_POSTFIX", EString "${FMT_DEBUG_POSTFIX}")];
  ]

let fmt_headers_block = ESeq [
  yc_set (ycvar "FMT_HEADERS") [];
  yc_foreach
    ~items:(List.map ystr [
      "args.h"; "base.h"; "chrono.h"; "color.h"; "compile.h"; "core.h";
      "format.h"; "format-inl.h"; "os.h"; "ostream.h"; "printf.h";
      "ranges.h"; "std.h"; "xchar.h";
    ])
    (ycvar "header")
    (yc_set (ycvar "FMT_HEADERS") [EVar "FMT_HEADERS"; ystr "include/fmt/${header}"]);
]

(* ============================================================
   fmt library + setup + PUBLIC_HEADER + OS/WERROR/PEDANTIC/cxx_std_11. *)

let fmt_lib_block = ESeq [
  ECmakeAddLibrary {
    name = ystr "fmt"; type_ = None;
    sources = [ystr "src/format.cc"; EVar "FMT_HEADERS";
               ystr "README.md"; ystr "ChangeLog.md"];
  };
  yc_apply (ystr "setup_target") [ystr "fmt"; ystr "PUBLIC"];
  yc_set_target_properties (ystr "fmt")
    [("PUBLIC_HEADER", EString "${FMT_HEADERS}")];

  Yelu_langs.Yelu_cmake_if.ECmakeIfStmt {
    cond = EVar "FMT_OS";
    then_ = ECmakeTargetSources {
      target = ystr "fmt"; visibility = "PRIVATE";
      sources = [ystr "src/os.cc"];
    };
    else_ = Some (ECmakeTargetCompileDefinitions {
      target = ystr "fmt"; visibility = "PRIVATE";
      definitions = [ystr "FMT_OS=0"];
    });
  };

  yifthen (EVar "FMT_WERROR")
    (ECmakeTargetCompileOptions {
      target = ystr "fmt"; visibility = "PRIVATE";
      before = false; options_ = [EVar "WERROR_FLAG"];
    });
  yifthen (EVar "FMT_PEDANTIC")
    (ECmakeTargetCompileOptions {
      target = ystr "fmt"; visibility = "PRIVATE";
      before = false; options_ = [EVar "PEDANTIC_COMPILE_FLAGS"];
    });

  Yelu_langs.Yelu_cmake_if.ECmakeIfStmt {
    cond = Yelu_langs.Yelu_cmake_string.ECmakeInList
             { item = ystr "cxx_std_11"; list_ = EVar "CMAKE_CXX_COMPILE_FEATURES" };
    then_ = ECmakeTargetCompileFeatures {
      target = ystr "fmt"; visibility = "PUBLIC";
      features = [ystr "cxx_std_11"];
    };
    else_ = Some (yc_message_mode "WARNING"
                    ["Feature cxx_std_11 is unknown for the CXX compiler"]);
  };

  yc_set (ycvar "FMT_LIB_NAME") [ystr "fmt"];
  yifthen
    (Yelu_langs.Yelu_cmake_string.ECmakeStringEqual
       (EVar "CMAKE_BUILD_TYPE", ystr "Debug"))
    (yc_set (ycvar "FMT_LIB_NAME")
       [ystr "${FMT_LIB_NAME}${FMT_DEBUG_POSTFIX}"]);

  yifthen (EVar "BUILD_SHARED_LIBS")
    (ESeq [
      ECmakeTargetCompileDefinitions {
        target = ystr "fmt"; visibility = "PRIVATE";
        definitions = [ystr "FMT_LIB_EXPORT"];
      };
      ECmakeTargetCompileDefinitions {
        target = ystr "fmt"; visibility = "INTERFACE";
        definitions = [ystr "FMT_SHARED"];
      };
    ]);
  yifthen (EVar "FMT_SAFE_DURATION_CAST")
    (ECmakeTargetCompileDefinitions {
      target = ystr "fmt"; visibility = "PUBLIC";
      definitions = [ystr "FMT_SAFE_DURATION_CAST"];
    });
]

(* ============================================================
   add_module_library function. *)

let add_module_library_fn =
  yc_function (ystr "add_module_library") ["name"] [
    yc_apply (ystr "cmake_parse_arguments")
      [ystr "AML"; ystr ""; ystr "USE_CMAKE_MODULES"; ystr ""; EVar "ARGN"];
    yc_set (ycvar "sources") [EVar "AML_UNPARSED_ARGUMENTS"];
    ECmakeAddLibrary { name = EVar "name"; type_ = None;
                       sources = [EVar "sources"] };
    yc_set_target_properties (EVar "name")
      [("LINKER_LANGUAGE", EString "CXX")];
    ECmakeTargetCompileFeatures {
      target = EVar "name"; visibility = "PUBLIC";
      features = [ystr "cxx_std_20"];
    };
    yifthen (EVar "MSVC") (
      yifthen
        (ynot (Yelu_langs.Yelu_cmake_string.ECmakeStringEqual
                 (EVar "CMAKE_GENERATOR", ystr "Ninja")))
        (ESeq [
          yc_set (ycvar "BMI_DIR") [ystr "${CMAKE_CURRENT_BINARY_DIR}"];
          yc_apply (ystr "file")
            [ystr "TO_NATIVE_PATH"; ystr "${BMI_DIR}/${name}.ifc"; ystr "BMI"];
          yc_apply (ystr "target_compile_options") [
            EVar "name"; ystr "PRIVATE";
            ystr "/interface"; ystr "/ifcOutput"; EVar "BMI";
            ystr "INTERFACE"; ystr "/reference"; ystr "fmt=${BMI}";
          ];
          yc_set_target_properties (EVar "name")
            [("ADDITIONAL_CLEAN_FILES", EVar "BMI")];
          yc_set_source_files_properties [EVar "BMI"]
            [("GENERATED", EString "ON")];
        ]));
    yifthen (EVar "AML_USE_CMAKE_MODULES") (ESeq [
      yc_apply (ystr "target_sources") [
        EVar "name"; ystr "PUBLIC"; ystr "FILE_SET"; ystr "fmt";
        ystr "TYPE"; ystr "CXX_MODULES"; ystr "FILES"; EVar "sources";
      ];
      Yelu_langs.Yelu_cmake_cmake_op.ECmakeReturn { propagate_vars = [] };
    ]);
    yifthen (EVar "CMAKE_COMPILER_IS_GNUCXX")
      (ECmakeTargetCompileOptions
         { target = EVar "name"; visibility = "PUBLIC";
           before = false; options_ = [EString "-fmodules-ts"] });
    yc_apply (ystr "get_target_property")
      [ystr "std"; EVar "name"; ystr "CXX_STANDARD"];
    yifthen
      (Yelu_langs.Yelu_cmake_string.ECmakeMatches
         { expr_ = EVar "CMAKE_CXX_COMPILER_ID"; regex = "Clang" })
      (ESeq [
        yc_set (ycvar "pcms") [];
        yc_foreach ~items:[EVar "sources"] (ycvar "src") (ESeq [
          yc_get_filename_component ~mode:"NAME_WE" "pcm" (EVar "src");
          yc_set (ycvar "pcm") [ystr "${pcm}.pcm"];
          ECmakeTargetCompileOptions
            { target = EVar "name"; visibility = "PUBLIC";
              before = false;
              options_ = [EString "-fmodule-file=${CMAKE_CURRENT_BINARY_DIR}/${pcm}"] };
          yc_set (ycvar "pcms")
            [EVar "pcms"; ystr "${CMAKE_CURRENT_BINARY_DIR}/${pcm}"];
          yc_apply (ystr "add_custom_command") [
            ystr "OUTPUT"; EVar "pcm";
            ystr "COMMAND";
              EVar "CMAKE_CXX_COMPILER"; ystr "-std=c++${std}";
              ystr "-x"; ystr "c++-module"; ystr "--precompile";
              ystr "-c"; ystr "-o"; EVar "pcm";
              ystr "${CMAKE_CURRENT_SOURCE_DIR}/${src}";
              ystr "-I$<JOIN:$<TARGET_PROPERTY:${name},INCLUDE_DIRECTORIES>,;-I>";
            ystr "COMMAND_EXPAND_LISTS";
            ystr "DEPENDS"; EVar "src";
          ];
        ]);
        yc_set (ycvar "sources") [];
        yc_foreach ~items:[EVar "pcms"] (ycvar "pcm") (ESeq [
          yc_get_filename_component ~mode:"NAME_WE" "pcm_we" (EVar "pcm");
          yc_set (ycvar "obj") [ystr "${pcm_we}.o"];
          yc_set (ycvar "sources")
            [EVar "sources"; EVar "pcm"; ystr "${CMAKE_CURRENT_BINARY_DIR}/${obj}"];
          yc_apply (ystr "add_custom_command") [
            ystr "OUTPUT"; EVar "obj";
            ystr "COMMAND";
              EVar "CMAKE_CXX_COMPILER";
              ystr "$<TARGET_PROPERTY:${name},COMPILE_OPTIONS>";
              ystr "-c"; ystr "-o"; EVar "obj"; EVar "pcm";
            ystr "DEPENDS"; EVar "pcm";
          ];
        ]);
      ]);
    ECmakeTargetSources {
      target = EVar "name"; visibility = "PRIVATE";
      sources = [EVar "sources"];
    };
  ]

(* ============================================================
   FMT_MODULE block + fmt-header-only + fmt-c. *)

let modules_and_variants = ESeq [
  yifthen (EVar "FMT_MODULE") (ESeq [
    yc_apply (ystr "add_module_library") [
      ystr "fmt-module"; ystr "src/fmt.cc";
      ystr "USE_CMAKE_MODULES"; EVar "FMT_USE_CMAKE_MODULES";
    ];
    yc_apply (ystr "setup_target") [ystr "fmt-module"; ystr "PUBLIC"];
  ]);

  ECmakeAddLibrary {
    name = ystr "fmt-header-only"; type_ = Some "INTERFACE"; sources = [];
  };
  ECmakeTargetCompileDefinitions {
    target = ystr "fmt-header-only"; visibility = "INTERFACE";
    definitions = [ystr "FMT_HEADER_ONLY=1"];
  };
  ECmakeTargetCompileFeatures {
    target = ystr "fmt-header-only"; visibility = "INTERFACE";
    features = [ystr "cxx_std_11"];
  };
  yc_apply (ystr "setup_target") [ystr "fmt-header-only"; ystr "INTERFACE"];

  ECmakeAddLibrary {
    name = ystr "fmt-c"; type_ = Some "STATIC";
    sources = [ystr "src/fmt-c.cc"];
  };
  ECmakeTargetCompileFeatures {
    target = ystr "fmt-c"; visibility = "INTERFACE";
    features = [ystr "c_std_11"];
  };
  yifthen (EVar "MSVC")
    (ECmakeTargetCompileOptions {
      target = ystr "fmt-c"; visibility = "PUBLIC";
      before = false; options_ = [ystr "/Zc:preprocessor"];
    });
  ECmakeTargetLinkLibraries {
    target = ystr "fmt-c"; visibility = "PUBLIC";
    items = [ystr "fmt::fmt"];
  };
  ECmakeAddLibraryAlias { name = "fmt::fmt-c"; target = "fmt-c" };
  yc_set_target_properties (ystr "fmt-c")
    [("PUBLIC_HEADER", EString "include/fmt/fmt-c.h")];
]

(* ============================================================
   FMT_INSTALL block — install / export / configure_package_config_file /
   write_basic_package_version_file / pkgconfig. *)

let install_block =
  yifthen (EVar "FMT_INSTALL") (ESeq [
    yc_include (ystr "CMakePackageConfigHelpers");
    yc_apply (ystr "set_verbose") [
      ystr "FMT_CMAKE_DIR"; ystr "${CMAKE_INSTALL_LIBDIR}/cmake/fmt";
      ystr "CACHE"; ystr "STRING";
      ystr "Installation directory for cmake files, a relative path that ";
      ystr "will be joined with ${CMAKE_INSTALL_PREFIX} or an absolute ";
      ystr "path.";
    ];
    yc_set (ycvar "version_config") [ystr "${PROJECT_BINARY_DIR}/fmt-config-version.cmake"];
    yc_set (ycvar "project_config") [ystr "${PROJECT_BINARY_DIR}/fmt-config.cmake"];
    yc_set (ycvar "pkgconfig") [ystr "${PROJECT_BINARY_DIR}/fmt.pc"];
    yc_set (ycvar "targets_export_name") [ystr "fmt-targets"];

    yc_apply (ystr "set_verbose") [
      ystr "FMT_LIB_DIR"; EVar "CMAKE_INSTALL_LIBDIR";
      ystr "CACHE"; ystr "STRING";
      ystr "Installation directory for libraries, a relative path that ";
      ystr "will be joined to ${CMAKE_INSTALL_PREFIX} or an absolute path.";
    ];

    yc_apply (ystr "set_verbose") [
      ystr "FMT_PKGCONFIG_DIR"; ystr "${CMAKE_INSTALL_LIBDIR}/pkgconfig";
      ystr "CACHE"; ystr "STRING";
      ystr "Installation directory for pkgconfig (.pc) files, a relative ";
      ystr "path that will be joined with ${CMAKE_INSTALL_PREFIX} or an ";
      ystr "absolute path.";
    ];

    yc_write_basic_package_version_file
      ~compatibility:Yelu_langs.Lang_cmake.Any_newer_version
      ~version:(EVar "FMT_VERSION")
      (EVar "version_config");

    yc_apply (ystr "join_paths")
      [ystr "libdir_for_pc_file";
       ystr (Yelu_langs.Yelu_emit_main.escape "\\${exec_prefix}");
       ystr "${FMT_LIB_DIR}"];
    yc_apply (ystr "join_paths")
      [ystr "includedir_for_pc_file";
       ystr (Yelu_langs.Yelu_emit_main.escape "\\${prefix}");
       ystr "${FMT_INC_DIR}"];

    yc_apply (ystr "configure_file") [
      ystr "${PROJECT_SOURCE_DIR}/support/cmake/fmt.pc.in";
      ystr "${pkgconfig}"; ystr "@ONLY";
    ];
    yc_apply (ystr "configure_package_config_file") [
      ystr "${PROJECT_SOURCE_DIR}/support/cmake/fmt-config.cmake.in";
      EVar "project_config";
      ystr "INSTALL_DESTINATION"; EVar "FMT_CMAKE_DIR";
    ];

    yc_set (ycvar "INSTALL_TARGETS")
      [ystr "fmt"; ystr "fmt-header-only"; ystr "fmt-c"];
    yifthen (EVar "FMT_MODULE") (ESeq [
      yc_list_append "INSTALL_TARGETS" [EString "fmt-module"];
      yifthen (EVar "FMT_USE_CMAKE_MODULES")
        (yc_set (ycvar "INSTALL_FILE_SET")
           [ystr "FILE_SET"; ystr "fmt";
            ystr "DESTINATION"; ystr "${FMT_INC_DIR}/fmt"]);
    ]);

    yc_apply (ystr "install") [
      ystr "TARGETS"; EVar "INSTALL_TARGETS";
      ystr "COMPONENT"; ystr "fmt_core";
      ystr "EXPORT"; EVar "targets_export_name";
      ystr "LIBRARY"; ystr "DESTINATION"; EVar "FMT_LIB_DIR";
      ystr "ARCHIVE"; ystr "DESTINATION"; EVar "FMT_LIB_DIR";
      ystr "PUBLIC_HEADER"; ystr "DESTINATION"; ystr "${FMT_INC_DIR}/fmt";
      ystr "RUNTIME"; ystr "DESTINATION"; EVar "CMAKE_INSTALL_BINDIR";
      EVar "INSTALL_FILE_SET";
    ];

    yc_apply (ystr "export") [
      ystr "TARGETS"; EVar "INSTALL_TARGETS";
      ystr "NAMESPACE"; ystr "fmt::";
      ystr "FILE"; ystr "${PROJECT_BINARY_DIR}/${targets_export_name}.cmake";
    ];

    yc_apply (ystr "install") [
      ystr "FILES"; EVar "project_config"; EVar "version_config";
      ystr "DESTINATION"; EVar "FMT_CMAKE_DIR";
      ystr "COMPONENT"; ystr "fmt_core";
    ];
    yc_apply (ystr "install") [
      ystr "EXPORT"; EVar "targets_export_name";
      ystr "DESTINATION"; EVar "FMT_CMAKE_DIR";
      ystr "NAMESPACE"; ystr "fmt::";
      ystr "COMPONENT"; ystr "fmt_core";
    ];

    yc_apply (ystr "install") [
      ystr "FILES"; ystr "${pkgconfig}";
      ystr "DESTINATION"; ystr "${FMT_PKGCONFIG_DIR}";
      ystr "COMPONENT"; ystr "fmt_core";
    ];
  ])

(* ============================================================
   add_doc_target function + FMT_DOC/TEST/FUZZ/CPack. *)

let add_doc_target_fn =
  yc_function (ystr "add_doc_target") [] [
    yc_find_program
      ~names:[EString "doxygen"]
      ~paths:[EString "$ENV{ProgramFiles}/doxygen/bin";
              EString "$ENV{ProgramFiles\\(x86\\)}/doxygen/bin"]
      "DOXYGEN";
    yifthen (ynot (EVar "DOXYGEN")) (ESeq [
      yc_message ["Target 'doc' disabled because doxygen not found"];
      Yelu_langs.Yelu_cmake_cmake_op.ECmakeReturn { propagate_vars = [] };
    ]);
    yc_find_program ~names:[EString "mkdocs"] "MKDOCS";
    yifthen (ynot (EVar "MKDOCS")) (ESeq [
      yc_message ["Target 'doc' disabled because mkdocs not found"];
      Yelu_langs.Yelu_cmake_cmake_op.ECmakeReturn { propagate_vars = [] };
    ]);
    yc_set (ycvar "sources") [];
    yc_foreach
      ~items:[ystr "api.md"; ystr "index.md"; ystr "syntax.md";
              ystr "get-started.md"; ystr "fmt.css"; ystr "fmt.js"]
      (ycvar "source")
      (yc_set (ycvar "sources") [EVar "sources"; ystr "doc/${source}"]);
    yc_apply (ystr "add_custom_target") [
      ystr "doc"; ystr "COMMAND";
      EVar "CMAKE_COMMAND"; ystr "-E"; ystr "env";
      ystr "PYTHONPATH=${CMAKE_CURRENT_SOURCE_DIR}/support/python";
      EVar "MKDOCS"; ystr "build"; ystr "-f";
      ystr "${CMAKE_CURRENT_SOURCE_DIR}/support/mkdocs.yml";
      ystr "--site-dir"; ystr "${CMAKE_CURRENT_BINARY_DIR}/doc-html";
      ystr "--no-directory-urls";
      ystr "SOURCES"; EVar "sources";
    ];
    yc_apply (ystr "install") [
      ystr "DIRECTORY"; ystr "${CMAKE_CURRENT_BINARY_DIR}/doc-html/";
      ystr "DESTINATION"; ystr "${CMAKE_INSTALL_DATAROOTDIR}/doc/fmt";
      ystr "COMPONENT"; ystr "fmt_doc";
      ystr "OPTIONAL";
    ];
  ]

let trailing_gates = ESeq [
  yifthen (EVar "FMT_DOC") (yc_apply (ystr "add_doc_target") []);

  yifthen (EVar "FMT_TEST") (ESeq [
    yc_enable_testing;
    yc_add_subdirectory (ystr "test");
  ]);

  yifthen (EVar "FMT_FUZZ") (ESeq [
    yc_add_subdirectory (ystr "test/fuzzing");
    ECmakeTargetCompileDefinitions {
      target = ystr "fmt"; visibility = "PUBLIC";
      definitions = [ystr "FMT_FUZZ"];
    };
  ]);

  yc_set (ycvar "gitignore") [ystr "${PROJECT_SOURCE_DIR}/.gitignore"];
  yifthen
    (Yelu_langs.Yelu_cmake_normal_bool.EAnd
       (EVar "FMT_MASTER_PROJECT",
        Yelu_langs.Yelu_cmake_file.ECmakeFileExists (EVar "gitignore")))
    (ESeq [
      Yelu_langs.Yelu_cmake_file.ECmakeFileStrings {
        path = EVar "gitignore"; out = "lines";
        regex = None; encoding = None; limit_count = None;
      };
      yc_list_remove_item "lines" [EString "/doc/html"];
      yc_foreach ~items:[EVar "lines"] (ycvar "line") (ESeq [
        Yelu_langs.Yelu_cmake_string.ECmakeStringReplace {
          match_ = ystr "."; replace = ystr "[.]";
          input = ystr "${line}"; out = "line";
        };
        Yelu_langs.Yelu_cmake_string.ECmakeStringReplace {
          match_ = ystr "*"; replace = ystr ".*";
          input = ystr "${line}"; out = "line";
        };
        yc_set (ycvar "ignored_files")
          [EVar "ignored_files";
           ystr "${line}$"; ystr "${line}/"];
      ]);
      yc_set (ycvar "ignored_files")
        [EVar "ignored_files";
         ystr "/.git"; ystr "/build/doxyxml"; ystr ".vagrant"];

      yc_set (ycvar "CPACK_SOURCE_GENERATOR") [ystr "ZIP"];
      yc_set (ycvar "CPACK_SOURCE_IGNORE_FILES") [EVar "ignored_files"];
      yc_set (ycvar "CPACK_SOURCE_PACKAGE_FILE_NAME") [ystr "fmt-${FMT_VERSION}"];
      yc_set (ycvar "CPACK_PACKAGE_NAME") [ystr "fmt"];
      yc_set (ycvar "CPACK_RESOURCE_FILE_README") [ystr "${PROJECT_SOURCE_DIR}/README.md"];
      yc_include (ystr "CPack");
    ]);
]

let helpers = ESeq [
  preamble;
  project_and_modules_detect;
  options_block;
  version_block;
  visibility_and_flags;
  setup_target_fn;
  fmt_headers_block;
  fmt_lib_block;
  add_module_library_fn;
  modules_and_variants;
  install_block;
  add_doc_target_fn;
  trailing_gates;
]

let () = Yelu_langs.Yelu_emit_main.print helpers
