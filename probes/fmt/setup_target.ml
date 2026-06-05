(* fmt CMakeLists.txt — setup_target(target, kind) helper.

   Sets up a fmt library target: alias + include dirs + Unicode
   conditional + properties.

   Uses .ml (parser gaps: dynamic target names, ${kind} as
   visibility, ${FMT_SYSTEM_HEADERS_ATTRIBUTE} as keyword). *)

open Yelu_langs.Yelu_cmake
open Yelu_langs.Yelu_cmake_utils
open Yelu_langs.Yelu_cmake_target

let helpers =
  yc_function (ystr "setup_target") ["target"; "kind"] [
    (* add_library(fmt::${target} ALIAS ${target}) *)
    ECmakeAddLibraryAlias { name = "fmt::${target}"; target = "${target}" };

    (* target_include_directories(
         ${target} ${FMT_SYSTEM_HEADERS_ATTRIBUTE} BEFORE ${kind}
         $<BUILD_INTERFACE:${PROJECT_SOURCE_DIR}/include>
         $<INSTALL_INTERFACE:${FMT_INC_DIR}>)

       ${FMT_SYSTEM_HEADERS_ATTRIBUTE} expands to empty or SYSTEM;
       we represent it as a SYSTEM flag-from-variable via Apply
       since the IR has system : bool, not expr. Falling back to
       Apply for the whole call preserves the runtime semantics. *)
    yc_apply (ystr "target_include_directories") [
      EVar "target";
      EVar "FMT_SYSTEM_HEADERS_ATTRIBUTE";
      ystr "BEFORE";
      EVar "kind";
      ystr "$<BUILD_INTERFACE:${PROJECT_SOURCE_DIR}/include>";
      ystr "$<INSTALL_INTERFACE:${FMT_INC_DIR}>";
    ];

    (* if (NOT MSVC) (empty) elseif (FMT_UNICODE) ... else ... endif() *)
    (* Encode as nested if/else: if NOT MSVC then nothing else
       (if FMT_UNICODE then opts else defs) *)
    Yelu_langs.Yelu_cmake_if.ECmakeIfStmt {
      cond = ynot (EVar "MSVC");
      then_ = EUnit;  (* empty branch — fmt's comment-only block *)
      else_ = Some (
        Yelu_langs.Yelu_cmake_if.ECmakeIfStmt {
          cond = EVar "FMT_UNICODE";
          then_ = yc_apply (ystr "target_compile_options") [
            EVar "target";
            EVar "kind";
            ystr "$<$<AND:$<COMPILE_LANGUAGE:CXX>,$<CXX_COMPILER_ID:MSVC>>:/utf-8>";
          ];
          else_ = Some (
            yc_apply (ystr "target_compile_definitions") [
              EVar "target";
              EVar "kind";
              ystr "FMT_UNICODE=0";
            ]);
        });
    };

    (* set_target_properties(${target} PROPERTIES VERSION ${FMT_VERSION}
                                                  SOVERSION ${CPACK_PACKAGE_VERSION_MAJOR}
                                                  DEBUG_POSTFIX "${FMT_DEBUG_POSTFIX}") *)
    yc_apply (ystr "set_target_properties") [
      EVar "target";
      ystr "PROPERTIES";
      ystr "VERSION"; EVar "FMT_VERSION";
      ystr "SOVERSION"; EVar "CPACK_PACKAGE_VERSION_MAJOR";
      ystr "DEBUG_POSTFIX"; ystr "${FMT_DEBUG_POSTFIX}";
    ];
  ]

let () = Yelu_langs.Yelu_emit_main.print helpers
