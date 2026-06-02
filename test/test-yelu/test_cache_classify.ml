(* Unit tests for cache variable classifier.

   Exercises each of the four tiers from
   doc/cmake/cache_var_namespacing.md § 2:
     - Project           (project-declared, via static enumerator)
     - Reserved_cmake    (cmake-emitted, prefix or named match)
     - Reserved_build    (BUILD_SHARED_LIBS / BUILD_TESTING)
     - Unknown           (residual — bridge gap or dynamic decl)

   The classifier is independent of any specific cmake version —
   prefix patterns + explicit named lists. Tests pass on any host. *)

open Base
open Yelu_runner.Cache_classify

let check_classify ~project ~reserved name expected_tier =
  let label =
    Printf.sprintf "%s -> %s" name (tier_to_string expected_tier)
  in
  Alcotest.test_case label `Quick (fun () ->
    let actual = classify ~project ~reserved name in
    Alcotest.(check string) label
      (tier_to_string expected_tier) (tier_to_string actual))

(* Mimic what real config calls would produce:
   - reserved = a small subset of `cmake --help-variable-list` plus
     the placeholder forms we know expand_placeholders handles
   - project = fmt-like names + a few common patterns *)
let reserved_cmake_subset =
  [ "CMAKE_INSTALL_PREFIX";
    "CMAKE_BUILD_TYPE";
    "CMAKE_CXX_COMPILER";
    "CMAKE_GENERATOR";
    "CTEST_TESTING_TIMEOUT";
    "CPACK_GENERATOR";
    (* explicit list-form names *)
    "APPLE"; "WIN32"; "UNIX";
    (* placeholder-expanded for project "FMT" *)
    "FMT_BINARY_DIR"; "FMT_VERSION"; "FMT_IS_TOP_LEVEL";
  ]

let fmt_project_names =
  [ "FMT_DOC"; "FMT_INSTALL"; "FMT_TEST"; "FMT_FUZZ";
    "FMT_CUDA_TEST"; "FMT_OS"; "FMT_MODULE";
    "FMT_SYSTEM_HEADERS"; "FMT_UNICODE";
    "FMT_PEDANTIC"; "FMT_WERROR";
    "FMT_DEBUG_POSTFIX";
    "FMT_FUZZ_LINKMAIN"; "FMT_FUZZ_LDFLAGS";
  ]

(* ============================================================
   Tier (3) project — direct hits in the project namelist
   ============================================================ *)
let project_tier =
  ( "project",
    [
      check_classify ~project:fmt_project_names ~reserved:reserved_cmake_subset
        "FMT_FUZZ" Project;
      check_classify ~project:fmt_project_names ~reserved:reserved_cmake_subset
        "FMT_DEBUG_POSTFIX" Project;
      check_classify ~project:fmt_project_names ~reserved:reserved_cmake_subset
        "FMT_FUZZ_LDFLAGS" Project;
    ] )

(* ============================================================
   Tier (1) reserved_cmake — named + prefix-matched
   ============================================================ *)
let reserved_cmake_tier =
  ( "reserved_cmake",
    [
      (* named match (in the reserved list) *)
      check_classify ~project:fmt_project_names ~reserved:reserved_cmake_subset
        "CMAKE_INSTALL_PREFIX" Reserved_cmake;
      check_classify ~project:fmt_project_names ~reserved:reserved_cmake_subset
        "CMAKE_GENERATOR" Reserved_cmake;
      check_classify ~project:fmt_project_names ~reserved:reserved_cmake_subset
        "APPLE" Reserved_cmake;
      (* prefix match (not in the reserved list, but CMAKE_* prefix) *)
      check_classify ~project:fmt_project_names ~reserved:reserved_cmake_subset
        "CMAKE_AR" Reserved_cmake;
      check_classify ~project:fmt_project_names ~reserved:reserved_cmake_subset
        "CMAKE_EXE_LINKER_FLAGS_DEBUG" Reserved_cmake;
      (* CTEST_ prefix *)
      check_classify ~project:fmt_project_names ~reserved:reserved_cmake_subset
        "CTEST_BUILD_NAME" Reserved_cmake;
      (* CPACK_ prefix *)
      check_classify ~project:fmt_project_names ~reserved:reserved_cmake_subset
        "CPACK_SOURCE_IGNORE_FILES" Reserved_cmake;
      (* HAVE_ prefix — probe result, not in --help-variable-list *)
      check_classify ~project:fmt_project_names ~reserved:reserved_cmake_subset
        "HAVE_FNO_EXCEPTIONS_FLAG" Reserved_cmake;
      check_classify ~project:fmt_project_names ~reserved:reserved_cmake_subset
        "CMAKE_HAVE_LIBC_PTHREAD" Reserved_cmake;
      (* FETCHCONTENT_ prefix *)
      check_classify ~project:fmt_project_names ~reserved:reserved_cmake_subset
        "FETCHCONTENT_FULLY_DISCONNECTED" Reserved_cmake;
      (* _FOUND suffix *)
      check_classify ~project:fmt_project_names ~reserved:reserved_cmake_subset
        "Threads_FOUND" Reserved_cmake;
      (* _INTERNAL suffix *)
      check_classify ~project:fmt_project_names ~reserved:reserved_cmake_subset
        "FOOBAR_INTERNAL" Reserved_cmake;
      (* placeholder-expanded — fmt-side of <PROJECT-NAME>_VERSION *)
      check_classify ~project:fmt_project_names ~reserved:reserved_cmake_subset
        "FMT_VERSION" Reserved_cmake;
      check_classify ~project:fmt_project_names ~reserved:reserved_cmake_subset
        "FMT_BINARY_DIR" Reserved_cmake;
    ] )

(* ============================================================
   Tier (2) reserved_build — the BUILD_* convention
   ============================================================ *)
let reserved_build_tier =
  ( "reserved_build",
    [
      check_classify ~project:fmt_project_names ~reserved:reserved_cmake_subset
        "BUILD_SHARED_LIBS" Reserved_build;
      check_classify ~project:fmt_project_names ~reserved:reserved_cmake_subset
        "BUILD_TESTING" Reserved_build;
    ] )

(* ============================================================
   Tier (4) unknown — residual
   ============================================================ *)
let unknown_tier =
  ( "unknown",
    [
      (* arbitrary project-shaped name we didn't declare *)
      check_classify ~project:fmt_project_names ~reserved:reserved_cmake_subset
        "MYPROJ_NEW_OPTION" Unknown;
      (* compiler-prefixed (we said "relaxed for completeness") *)
      check_classify ~project:fmt_project_names ~reserved:reserved_cmake_subset
        "GCC_HAVE_FPIC" Unknown;
      check_classify ~project:fmt_project_names ~reserved:reserved_cmake_subset
        "MSVC_FLAG_X" Unknown;
      (* doxygen — not in our reserved list (real cmake's cache has
         DOXYGEN_PROJECT_NAME etc. that aren't in the CMAKE_ prefix) *)
      check_classify ~project:fmt_project_names ~reserved:reserved_cmake_subset
        "DOXYGEN_PROJECT_NAME" Unknown;
    ] )

(* ============================================================
   Project-shadows-reserved precedence
   ============================================================ *)
let shadowing_tier =
  ( "shadowing",
    [
      (* If a project explicitly declares BUILD_TESTING as a project
         option, project tier wins over the reserved_build short list. *)
      check_classify
        ~project:("BUILD_TESTING" :: fmt_project_names)
        ~reserved:reserved_cmake_subset
        "BUILD_TESTING" Project;
      (* Same for a project that redefines CMAKE_BUILD_TYPE as their
         own option (rare but possible). *)
      check_classify
        ~project:("CMAKE_BUILD_TYPE" :: fmt_project_names)
        ~reserved:reserved_cmake_subset
        "CMAKE_BUILD_TYPE" Project;
    ] )

(* ============================================================
   Placeholder expansion
   ============================================================ *)
let placeholder_expansion_tier =
  ( "placeholder_expansion",
    [
      Alcotest.test_case "expand <PROJECT-NAME>_VERSION for FMT" `Quick
        (fun () ->
          let templates =
            [ "<PROJECT-NAME>_VERSION"; "<PROJECT-NAME>_BINARY_DIR" ]
          in
          let expanded = expand_placeholders ~project_name:"FMT" templates in
          Alcotest.(check (list string)) "expanded names"
            [ "FMT_VERSION"; "FMT_BINARY_DIR" ] expanded);
      Alcotest.test_case "PackageName placeholder dropped" `Quick
        (fun () ->
          let templates =
            [ "<PackageName>_ROOT"; "<PROJECT-NAME>_VERSION" ]
          in
          let expanded = expand_placeholders ~project_name:"FMT" templates in
          Alcotest.(check (list string)) "only PROJECT-NAME expanded"
            [ "FMT_VERSION" ] expanded);
    ] )

let () =
  Alcotest.run "cache_classify"
    [ project_tier; reserved_cmake_tier; reserved_build_tier;
      unknown_tier; shadowing_tier; placeholder_expansion_tier ]
