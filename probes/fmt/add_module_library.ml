(* fmt CMakeLists.txt — add_module_library(name) helper.
   75 lines of complex cmake; heavy use of cmake_parse_arguments,
   file(TO_NATIVE_PATH), add_custom_command, get_target_property,
   set_source_files_properties, FILE_SET CXX_MODULES.

   Uses yc_apply liberally for unmodeled cmake commands —
   codegen produces equivalent cmake text; cmake itself parses it
   the same way it parses the original. .ml because both the
   target-name-dynamic gap and the modern-cmake-modules gap
   would block .ye. *)

open Yelu_langs.Yelu_cmake
open Yelu_langs.Yelu_cmake_utils
open Yelu_langs.Yelu_cmake_target

let helpers =
  yc_function (ystr "add_module_library") ["name"] [
    (* cmake_parse_arguments(AML "" "USE_CMAKE_MODULES" "" ${ARGN}) *)
    yc_apply (ystr "cmake_parse_arguments")
      [ystr "AML"; ystr ""; ystr "USE_CMAKE_MODULES"; ystr ""; EVar "ARGN"];
    (* set(sources ${AML_UNPARSED_ARGUMENTS}) *)
    yc_set (ycvar "sources") [EVar "AML_UNPARSED_ARGUMENTS"];

    (* add_library(${name}) *)
    yc_apply (ystr "add_library") [EVar "name"];
    (* set_target_properties(${name} PROPERTIES LINKER_LANGUAGE CXX) *)
    yc_apply (ystr "set_target_properties")
      [EVar "name"; ystr "PROPERTIES"; ystr "LINKER_LANGUAGE"; ystr "CXX"];

    (* target_compile_features(${name} PUBLIC cxx_std_20) *)
    ECmakeTargetCompileFeatures {
      target = EVar "name"; visibility = "PUBLIC";
      features = [ystr "cxx_std_20"];
    };

    (* if (MSVC) if (NOT CMAKE_GENERATOR STREQUAL "Ninja") ... endif endif *)
    yifthen (EVar "MSVC") (
      yifthen
        (ynot (Yelu_langs.Yelu_cmake_string.ECmakeStringEqual
                 (EVar "CMAKE_GENERATOR", ystr "Ninja")))
        (ESeq [
          yc_set (ycvar "BMI_DIR") [ystr "${CMAKE_CURRENT_BINARY_DIR}"];
          yc_apply (ystr "file")
            [ystr "TO_NATIVE_PATH"; ystr "${BMI_DIR}/${name}.ifc"; ystr "BMI"];
          yc_apply (ystr "target_compile_options") [
            EVar "name";
            ystr "PRIVATE"; ystr "/interface"; ystr "/ifcOutput"; EVar "BMI";
            ystr "INTERFACE"; ystr "/reference"; ystr "fmt=${BMI}";
          ];
          yc_apply (ystr "set_target_properties")
            [EVar "name"; ystr "PROPERTIES"; ystr "ADDITIONAL_CLEAN_FILES"; EVar "BMI"];
          yc_apply (ystr "set_source_files_properties")
            [EVar "BMI"; ystr "PROPERTIES"; ystr "GENERATED"; ystr "ON"];
        ]));

    (* if (${AML_USE_CMAKE_MODULES}) ... return() endif *)
    yifthen (EVar "AML_USE_CMAKE_MODULES") (ESeq [
      yc_apply (ystr "target_sources") [
        EVar "name"; ystr "PUBLIC"; ystr "FILE_SET"; ystr "fmt";
        ystr "TYPE"; ystr "CXX_MODULES"; ystr "FILES"; EVar "sources";
      ];
      Yelu_langs.Yelu_cmake_cmake_op.ECmakeReturn { propagate_vars = [] };
    ]);

    (* if (CMAKE_COMPILER_IS_GNUCXX) target_compile_options(...) endif *)
    yifthen (EVar "CMAKE_COMPILER_IS_GNUCXX") (
      yc_apply (ystr "target_compile_options")
        [EVar "name"; ystr "PUBLIC"; ystr "-fmodules-ts"]);

    (* get_target_property(std ${name} CXX_STANDARD) *)
    yc_apply (ystr "get_target_property")
      [ystr "std"; EVar "name"; ystr "CXX_STANDARD"];

    (* if (CMAKE_CXX_COMPILER_ID MATCHES "Clang") ... endif *)
    yifthen
      (Yelu_langs.Yelu_cmake_string.ECmakeMatches
         { expr_ = EVar "CMAKE_CXX_COMPILER_ID"; regex = "Clang" })
      (ESeq [
        yc_set (ycvar "pcms") [];
        yc_foreach ~items:[EVar "sources"] (ycvar "src") (ESeq [
          yc_apply (ystr "get_filename_component")
            [ystr "pcm"; EVar "src"; ystr "NAME_WE"];
          yc_set (ycvar "pcm") [ystr "${pcm}.pcm"];
          yc_apply (ystr "target_compile_options")
            [EVar "name"; ystr "PUBLIC";
             ystr "-fmodule-file=${CMAKE_CURRENT_BINARY_DIR}/${pcm}"];
          yc_set (ycvar "pcms") [EVar "pcms"; ystr "${CMAKE_CURRENT_BINARY_DIR}/${pcm}"];
          yc_apply (ystr "add_custom_command") [
            ystr "OUTPUT"; EVar "pcm";
            ystr "COMMAND";
              EVar "CMAKE_CXX_COMPILER"; ystr "-std=c++${std}";
              ystr "-x"; ystr "c++-module"; ystr "--precompile"; ystr "-c"; ystr "-o";
              EVar "pcm"; ystr "${CMAKE_CURRENT_SOURCE_DIR}/${src}";
              ystr "-I$<JOIN:$<TARGET_PROPERTY:${name},INCLUDE_DIRECTORIES>,;-I>";
            ystr "COMMAND_EXPAND_LISTS";
            ystr "DEPENDS"; EVar "src";
          ];
        ]);
        yc_set (ycvar "sources") [];
        yc_foreach ~items:[EVar "pcms"] (ycvar "pcm") (ESeq [
          yc_apply (ystr "get_filename_component")
            [ystr "pcm_we"; EVar "pcm"; ystr "NAME_WE"];
          yc_set (ycvar "obj") [ystr "${pcm_we}.o"];
          yc_set (ycvar "sources") [EVar "sources"; EVar "pcm"; ystr "${CMAKE_CURRENT_BINARY_DIR}/${obj}"];
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

    (* target_sources(${name} PRIVATE ${sources}) *)
    ECmakeTargetSources {
      target = EVar "name"; visibility = "PRIVATE";
      sources = [EVar "sources"];
    };
  ]

let () = Yelu_langs.Yelu_emit_main.print helpers
