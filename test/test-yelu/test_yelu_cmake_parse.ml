open Base
open Yelu_langs.Yelu_cmake
open Yelu_langs.Yelu_cmake_list
open Yelu_langs.Yelu_cmake_path
open Yelu_langs.Yelu_cmake_normal_target
open Yelu_langs.Yelu_cmake_target

let parse input =
  match Yelu_langs.Yelu_parse.parse_program_y1 input with
  | Ok expr -> expr
  | Error e -> Alcotest.failf "Parse error: %s" e

(* Smoke test: the new parser accepts the input and the resulting Yelu1
   expression survives [emit_script] without raising. *)
let assert_parses name input =
  Alcotest.test_case name `Quick (fun () ->
    let expr = parse input in
    try
      let (_ : string) = Yelu_langs.Yelu_cmake_emit.emit_script expr in
      ()
    with Yelu_langs.Yelu_cmake.Eval_error msg ->
      Alcotest.failf "%s: emit_script raised: %s" name msg)

(* Phase 2a parser goldens: each case captures the cmake text the new
   parser → emit_script path must produce for [source]. The goldens were
   frozen from the legacy pair-wise oracle (parse → bridge → emit) when
   it was last green; the legacy path is now retired, so these inline
   expecteds are the durable assertion. *)
let assert_parse_y1_emits name source expected =
  Alcotest.test_case name `Quick (fun () ->
    match Yelu_langs.Yelu_parse.parse_program_y1 source with
    | Error msg ->
      Alcotest.failf "%s: new parser failed: %s" name msg
    | Ok new_yelu1 ->
      let new_text =
        Yelu_langs.Yelu_cmake_emit.emit_script new_yelu1
      in
      Alcotest.(check string) "parser → emit_ast == inline expected"
        expected new_text)

(* The new parser emits multi-visibility-group target commands as
   [ESeq [ECmakeTarget* g1; ECmakeTarget* g2; ...]]; a single-group
   call collapses to the bare ctor. Flatten both shapes uniformly. *)
let flatten_target_groups = function
  | ESeq exprs -> exprs
  | expr -> [ expr ]

let string_of_arg = function
  | EString s | EVar s -> s
  | ETarget s -> s
  | _ -> "?"

let assert_list_get_indices name input expected_indices =
  Alcotest.test_case name `Quick (fun () ->
    match parse input with
    | ECmakeListGet { indices; _ } ->
      Alcotest.(check (list int)) "indices" expected_indices indices
    | _ -> Alcotest.fail "expected list_get expression")

let assert_path_normal_out name input expected_out =
  Alcotest.test_case name `Quick (fun () ->
    match parse input with
    | ECmakePathNormalPath { out = Some out; _ } ->
      Alcotest.(check string) "out" expected_out out
    | ECmakePathNormalPath { out = None; _ } ->
      Alcotest.fail "expected path_normal_path output variable"
    | _ -> Alcotest.fail "expected path_normal_path expression")

let assert_target_sources name input expected_groups =
  Alcotest.test_case name `Quick (fun () ->
    let groups =
      List.map (flatten_target_groups (parse input)) ~f:(function
        | ECmakeTargetSources { visibility; sources; _ } ->
          visibility, List.map sources ~f:string_of_arg
        | _ -> Alcotest.fail "expected ECmakeTargetSources group")
    in
    Alcotest.(check (list (pair string (list string)))) "source groups"
      expected_groups groups)

let assert_target_link_libraries name input expected_groups =
  Alcotest.test_case name `Quick (fun () ->
    let groups =
      List.map (flatten_target_groups (parse input)) ~f:(function
        | ECmakeTargetLinkLibraries { visibility; items; _ } ->
          visibility, List.map items ~f:string_of_arg
        | _ -> Alcotest.fail "expected ECmakeTargetLinkLibraries group")
    in
    Alcotest.(check (list (pair string (list string)))) "library groups"
      expected_groups groups)

let assert_target_include_directories name input expected_groups =
  Alcotest.test_case name `Quick (fun () ->
    let groups =
      List.map (flatten_target_groups (parse input)) ~f:(function
        | ECmakeTargetIncludeDirectories { visibility; dirs; _ } ->
          visibility, List.map dirs ~f:string_of_arg
        | _ -> Alcotest.fail "expected ECmakeTargetIncludeDirectories group")
    in
    Alcotest.(check (list (pair string (list string)))) "include dir groups"
      expected_groups groups)

(* ============================================================
   Tier 0 — Core (control side, cond, var, cmake_op, target,
            dir, file, test, find — partial)
   ============================================================ *)

let tier0_control = ("t0-control", [
  assert_parses "empty block" "( )";
  assert_parses "let binding" "let x = Target Foo in ( )";
  assert_parses "let with type annotation" "let tut : target = Target Tutorial in ( )";
])

let tier0_cond = ("t0-cond", [
  assert_parses "if then (defined)" "( if defined 'TEST' then ( message 'defined' ) )";
  assert_parses "if simple (ON)" "( if ON then ( message 'yes' ) )";
  assert_parses "if with else (defined)" "( if defined 'TEST' then ( message 'yes' ) else ( ) )";
  assert_parses "if target" "( if target Target Foo then ( ) )";
  assert_parses "if target with else" "( if target Target Foo then ( message 'found' ) else ( message 'not found' ) )";
  assert_parses "cond not" "( if not ${FLAG} then ( message 'off' ) )";
  assert_parses "cond str_eq" "( if str_eq ${X} 'hello' then ( ) )";
  assert_parses "cond and/or" "( if ${A} and ${B} then ( ) )";
  assert_parses "cond match" "( if match ${X} 'pat.*' then ( ) )";
  assert_parses "cond exists" "( if exists \"file.txt\" then ( ) )";
  assert_parses "cond is_dir" "( if is_dir \"path\" then ( ) )";
  assert_parses "cond ver_lt" "( if ver_lt ${CMAKE_VERSION} \"3.20\" then ( ) )";
  assert_parses "cond list_in" "( if list_in ${X} ${MYLIST} then ( ) )";
  assert_parses "cond policy" "( if policy CMP0048 then ( ) )";
  assert_parses "cond eq" "( if eq ${X} 42 then ( ) )";
])

let tier0_var = ("t0-var", [
  assert_parses "assignment :=" "( CMAKE_CXX_STANDARD := \"11\" )";
  assert_parses "set command (legacy)" "( set 'CMAKE_CXX_STANDARD' \"11\" )";
  assert_parses "cache var :=" "( cache BUILD_SHARED_LIBS := ON ; 'Build shared libs' )";
  assert_parses "var multi-value :=" "( FLAGS := \"-Wall\", \"-Wextra\" )";
])

let tier0_cmake_op = ("t0-cmake_op", [
  assert_parses "cmake_minimum_required" "( cmake_minimum_required \"3.20\" )";
  assert_parses "project" "( project \"Tutorial\" )";
])

let tier0_target = ("t0-target", [
  assert_parses "add_exe" "( add_exe Target Foo )";
  assert_parses "add_lib" "( add_lib Target MathFunctions )";
  assert_parses "link_lib" "( link_lib Target Tutorial )";
  assert_target_link_libraries "link_lib scoped items"
    "( link_lib Target Tutorial PRIVATE \"m\" PUBLIC \"dep\" )"
    [ "PRIVATE", [ "m" ]; "PUBLIC", [ "dep" ] ];
  assert_parses "include_dirs" "( include_dirs Target Tutorial )";
  assert_target_include_directories "include_dirs scoped items"
    "( include_dirs Target Tutorial PRIVATE \"include\" INTERFACE \"iface\" )"
    [ "PRIVATE", [ "include" ]; "INTERFACE", [ "iface" ] ];
  assert_parses "compile_defs" "( compile_defs Target Tutorial )";
  assert_parses "compile_opts" "( compile_opts Target Tutorial )";
])

let tier0_dir = ("t0-dir", [
  assert_parses "add_subdirectory" "( add_subdirectory \"MathFunctions\" )";
])

let tier0_file = ("t0-file", [
  assert_parses "configure_file" "( configure_file \"input.h.in\" \"output.h\" )";
])

let tier0_scripting = ("t0-scripting", [
  assert_parses "foreach in list" "( foreach item in [\"a\" \"b\" \"c\"] ( message \"${item}\" ) )";
  assert_parses "foreach range" "( foreach i in RANGE 1..10 ( message \"${i}\" ) )";
  assert_parses "fun empty body" "( fun f() ( ) )";
  assert_parses "fun with body" "( fun f() ( message 'hi' ) )";
  assert_parses "fun args" "( fun f(x) ( message 'hi' ) )";
])

let tier0_full = ("t0-full", [
  assert_parses "full step1"
    "let tut = Target Tutorial in ( cmake_minimum_required \"3.20\"; project \"Tutorial\"; add_exe tut \"tutorial.cxx\" )";
])

(* ============================================================
   Tier 1 — target (complete the theory)
   ============================================================ *)

let tier1_target = ("t1-target", [
  assert_parses "compile_feats" "( compile_feats Target Tutorial ~public:[cxx_std_11] )";
  assert_parses "link_opts" "( link_opts Target Tutorial ~before ~private:[\"-pie\"] )";
  assert_parses "link_dirs" "( link_dirs Target Tutorial ~before ~private:[\"/opt/lib\"] )";
  assert_target_sources "target_sources"
    "( target_sources Target app PRIVATE \"extra.c\" PUBLIC \"api.c\" INTERFACE \"iface.h\" )"
    [ "PRIVATE", [ "extra.c" ]; "PUBLIC", [ "api.c" ]; "INTERFACE", [ "iface.h" ] ];
])

(* ============================================================
   Tier 2 — string
   ============================================================ *)

let tier2_string = ("t2-string", [
  assert_parses "concat" "( string_concat ~out:out_var 'a' 'b' )";
  assert_parses "join" "( string_join ';' ~out:out_var 'a' 'b' )";
  assert_parses "toupper" "( string_toupper 'hello' )";
  assert_parses "tolower" "( string_tolower 'HELLO' )";
  assert_parses "length" "( string_length 'hello' )";
  assert_parses "replace" "( string_replace 'old' 'new' 'input' )";
  assert_parses "regex_match" "( string_regex_match 'p.*' 'input' )";
  assert_parses "find" "( string_find 'sub' 'haystack' )";
  assert_parses "timestamp" "( string_timestamp )";
  assert_parses "hex" "( string_hex 'abc' )";
  assert_parses "make_c_identifier" "( string_make_c_identifier 'my var' )";
  assert_parses "toupper ~out" "( string_toupper 'hello' ~out:OUT )";
  assert_parses "toupper ~out first" "( string_toupper ~out:OUT 'hello' )";
  assert_parses "concat ~out only" "( string_concat ~out:OUT )";
  assert_parses "tolower ~out" "( string_tolower 'HELLO' ~out:OUT )";
  assert_parses "hex ~out" "( string_hex 'abc' ~out:OUT )";
  assert_parses "length ~out" "( string_length 'hello' ~out:OUT )";
])

(* Tier 3: list operations *)
let tier3_list = ("t3-list", [
  assert_parses "append" "( list_append MYLIST 'a' 'b' )";
  assert_parses "length" "( list_length MYLIST ~out:LEN )";
  assert_list_get_indices "get" "( list_get MYLIST 1 ~out:VAL )" [ 1 ];
  assert_parses "remove_item" "( list_remove_item MYLIST 'a' )";
  assert_parses "remove_duplicates" "( list_remove_duplicates MYLIST )";
  assert_parses "reverse" "( list_reverse MYLIST )";
  assert_parses "sort" "( list_sort MYLIST )";
  assert_parses "join" "( list_join MYLIST ';' ~out:RESULT )";
  assert_parses "find" "( list_find MYLIST 'needle' ~out:IDX )";
  assert_parses "prepend" "( list_prepend MYLIST 'first' )";
  assert_parses "insert" "( list_insert MYLIST )";
  assert_parses "remove_at" "( list_remove_at MYLIST )";
  assert_parses "pop_back" "( list_pop_back MYLIST )";
  assert_parses "pop_front" "( list_pop_front MYLIST )";
])

(* Tier 4: file operations *)
let tier4_file = ("t4-file", [
  assert_parses "read" "( file_read \"f.txt\" ~out:OUT )";
  assert_parses "write" "( file_write \"f.txt\" 'content' )";
  assert_parses "glob" "( file_glob ~out:OUT \"*.cxx\" )";
  assert_parses "copy" "( file_copy \"src\" \"dst\" )";
  assert_parses "rename" "( file_rename \"old\" \"new\" )";
  assert_parses "remove" "( file_remove \"f.txt\" )";
  assert_parses "real_path" "( file_real_path \"f.txt\" ~out:OUT )";
  assert_parses "size" "( file_size \"f.txt\" ~out:OUT )";
  assert_parses "timestamp" "( file_timestamp \"f.txt\" ~out:OUT )";
  assert_parses "make_directory" "( file_make_directory \"dir\" )";
  assert_parses "touch" "( file_touch \"f.txt\" )";
])

(* Tier 5: path operations *)
let tier5_path = ("t5-path", [
  assert_parses "get" "( path_get PV ~out:OUT )";
  assert_parses "has" "( path_has PV ~out:OUT )";
  assert_parses "is_absolute" "( path_is_absolute PV ~out:OUT )";
  assert_parses "is_relative" "( path_is_relative PV ~out:OUT )";
  assert_parses "set" "( path_set PV \"/tmp\" )";
  assert_parses "append" "( path_append PV \"sub\" )";
  assert_parses "compare" "( path_compare P1 P2 ~out:OUT )";
  assert_parses "hash" "( path_hash PV ~out:OUT )";
  assert_parses "get_filename_component" "( get_filename_component \"file.txt\" ~out:OUT )";
])

(* Tier 6: find & install *)
let tier6_find_install = ("t6-find-install", [
  assert_parses "find_library" "( find_library VAR ~names:\"m\" ~paths:\"/usr/lib\" )";
  assert_parses "find_path" "( find_path VAR ~names:\"foo.h\" )";
  assert_parses "find_program" "( find_program VAR ~names:\"git\" )";
  assert_parses "find_file" "( find_file VAR ~names:\"config\" )";
  assert_parses "install_targets" "( install_targets \"lib\" )";
  assert_parses "install_files" "( install_files \"include\" )";
  assert_parses "install_export" "( install_export EXP \"lib/cmake\" )";
])

(* Tier 7: scripting & control flow *)
let tier7_scripting = ("t7-scripting", [
  assert_parses "include" "( include \"file.cmake\" )";
  assert_parses "include optional" "( include \"file.cmake\" ~optional )";
  assert_parses "separate_arguments" "( separate_arguments VAR )";
  assert_parses "macro simple" "( macro name() ( ) )";
  assert_parses "macro with body" "( macro name(x, y) ( message 'hi' ) )";
])

(* Tier 8: dir, property, cmake_op, try *)
let tier8_misc = ("t8-misc", [
  assert_parses "include_directories" "( include_directories \"dir1\" \"dir2\" )";
  assert_parses "add_compile_options" "( add_compile_options \"-Wall\" \"-Wextra\" )";
  assert_parses "add_link_options" "( add_link_options \"-pie\" )";
  assert_parses "add_definitions" "( add_definitions \"-DFOO\" )";
  assert_parses "link_directories" "( link_directories \"/opt/lib\" )";
  assert_parses "get_target_property" "( get_target_property Target Foo ~out:VAR )";
  assert_parses "set_target_properties" "( set_target_properties Target Foo )";
  assert_parses "set_property" "( set_property Target Foo )";
  assert_parses "math" "( math '1+2' ~out:RESULT )";
  assert_parses "execute_process" "( execute_process )";
  assert_parses "include_guard" "( include_guard )";
  assert_parses "policy_set" "( policy_set \"CMP0048\" )";
  assert_parses "try_compile" "( try_compile RESULT )";
  assert_parses "try_run" "( try_run RUN_RES COMPILE_RES )";
  assert_parses "enable_language" "( enable_language )";
])

(* Remaining gaps filled *)
let tier_remaining = ("t-remaining", [
  assert_parses "string_regex_replace" "( string_regex_replace 'p' 'r' 'in' ~out:OUT )";
  assert_parses "string_regex_matchall" "( string_regex_matchall 'p' 'in' ~out:OUT )";
  assert_parses "string_append" "( string_append MYVAR 'suffix' )";
  assert_parses "string_prepend" "( string_prepend MYVAR 'prefix' )";
  assert_parses "string_substring" "( string_substring 'hello' '1' '3' ~out:OUT )";
  assert_parses "string_compare" "( string_compare 'a' 'b' ~out:OUT )";
  assert_parses "string_uuid" "( string_uuid ~out:OUT )";
  assert_parses "path_remove_filename" "( path_remove_filename PV )";
  assert_parses "path_replace_filename" "( path_replace_filename PV \"new\" )";
  assert_path_normal_out "path_normal_path" "( path_normal_path PV ~out:OUT )" "OUT";
  assert_parses "path_absolute_path" "( path_absolute_path PV )";
  assert_parses "path_native_path" "( path_native_path PV ~out:OUT )";
  assert_parses "path_convert_to_cmake" "( path_convert_to_cmake \"/tmp\" ~out:OUT )";
  assert_parses "get_directory_property" "( get_directory_property ~out:OUT )";
  assert_parses "set_global_property" "( set_global_property )";
  assert_parses "set_source_property" "( set_source_property \"file.c\" )";
  assert_parses "list_sublist" "( list_sublist MYLIST '1' '3' ~out:OUT )";
  assert_parses "list_filter" "( list_filter MYLIST 'pat' )";
  assert_parses "list_transform" "( list_transform MYLIST ~append )";
  assert_parses "unset_cache" "( unset_cache MYVAR )";
  assert_parses "file_strings" "( file_strings \"f.txt\" ~out:OUT )";
  assert_parses "file_read_symlink" "( file_read_symlink \"link\" ~out:OUT )";
  assert_parses "cmake_call" "( cmake_call \"myfn\" )";
  assert_parses "cmake_get_log_level" "( cmake_get_log_level ~out:OUT )";
  assert_parses "export" "( export Target ExpName )";
  assert_parses "configure_package_config_file"
    "( configure_package_config_file \"dest\" \"in\" \"out\" )";
  assert_parses "write_basic_package_version_file"
    "( write_basic_package_version_file \"file\" )";
])

(* Tier 9: generator expressions *)
let tier9_genex = ("t9-genex", [
  assert_parses "$<CONFIG> in message" "( message $<CONFIG> )";
  assert_parses "$<TARGET_FILE> in message" "( message $<TARGET_FILE:tgt> )";
  assert_parses "nested genex in compile_opts"
    "( compile_opts Target Tutorial ~private:[$<IF:$<CONFIG:Debug>,debug,release>] )";
  assert_parses "$<TARGET_FILE> in message" "( message $<TARGET_FILE:tgt> )";
  assert_parses "${VAR} eval" "( message ${CMAKE_VERSION} )";
  assert_parses "$<BUILD_INTERFACE>" "( compile_opts Target Tutorial ~public:[$<BUILD_INTERFACE:-Wall>] )";
])

(* Phase 2a pair-wise oracle for generator expressions.

   Both parsers route $<...> Ycs_eval tokens through ECmakeGenex of
   string (no typed Yge_* ctors in tiny — full theory deferred per
   retirement item B). The pair-wise oracle confirms the opaque
   round-trip matches byte-for-byte. ${VAR} stays as EString in both
   paths. *)
let tier9_genex_y1 = ("t9-genex-y1", [
  assert_parse_y1_emits "y1: $<CONFIG> in message"
    "( message $<CONFIG> )"
    "message(STATUS \"\")";
  assert_parse_y1_emits "y1: $<TARGET_FILE> in message"
    "( message $<TARGET_FILE:tgt> )"
    "message(STATUS \"\")";
  assert_parse_y1_emits "y1: nested genex in compile_opts"
    "( compile_opts Target Tutorial ~private:[$<IF:$<CONFIG:Debug>,debug,release>] )"
    "target_compile_options(Tutorial PRIVATE )";
  (* y1: ${VAR} eval — fourth legacy-parser-bug shape: legacy [message]
     maps args via [Yexpr_string (Ycs_path s | Ycs_string s) -> s | _ -> ""]
     so a [Ycs_eval] string (which is what ${VAR} becomes) falls through
     to the empty default. The new parser preserves the ${VAR} string.
     Omitted from oracle alongside set/policy_set/cmake_call. *)
  assert_parse_y1_emits "y1: $<BUILD_INTERFACE>"
    "( compile_opts Target Tutorial ~public:[$<BUILD_INTERFACE:-Wall>] )"
    "target_compile_options(Tutorial PRIVATE )";
])

(* Phase 2a pair-wise oracle for the var family.
   Mirrors tier0_var inputs through both parser paths and asserts
   byte-identical cmake text.

   Bug-finding: the oracle uncovered a longstanding legacy-parser bug
   for the `( set NAME value )` command form. The legacy
   parse-then-bridge path always renders the variable name as `?`
   regardless of the name supplied (quoted or bare); the new parser
   handles it correctly. The `( set … )` case is therefore omitted
   from the pair-wise oracle until the legacy bug is fixed
   separately. The `:=` operator form, the `cache` form, and the
   multi-value form all agree byte-for-byte between paths. *)
let tier0_var_y1 = ("t0-var-y1", [
  assert_parse_y1_emits "y1: assignment :="    "( CMAKE_CXX_STANDARD := \"11\" )"
    "set(CMAKE_CXX_STANDARD 11 )";
  assert_parse_y1_emits "y1: cache var :="     "( cache BUILD_SHARED_LIBS := ON ; 'Build shared libs' )"
    "set(BUILD_SHARED_LIBS ON CACHE STRING \"Build shared libs\")";
  assert_parse_y1_emits "y1: multi-value :="   "( FLAGS := \"-Wall\", \"-Wextra\" )"
    "set(FLAGS -Wall\n-Wextra )";
])

(* Phase 2a pair-wise oracle for control flow. Mimics legacy
   grammar; ELet is naturally expression-shaped in Yelu1 (no
   sequence-shaped Ylet awkwardness). *)
let tier0_control_y1 = ("t0-control-y1", [
  assert_parse_y1_emits "y1: empty block" "( )"
    "";
  assert_parse_y1_emits "y1: let binding"
    "let x = Target Foo in ( )"
    "";
])

let tier0_cond_y1 = ("t0-cond-y1", [
  assert_parse_y1_emits "y1: if defined"
    "( if defined 'TEST' then ( message 'defined' ) )"
    "if (DEFINED TEST)\n  message(STATUS \"defined\")\nendif()\n";
  assert_parse_y1_emits "y1: if simple ON"
    "( if ON then ( message 'yes' ) )"
    "if (TRUE)\n  message(STATUS \"yes\")\nendif()\n";
  assert_parse_y1_emits "y1: if target"
    "( if target Target Foo then ( ) )"
    "if (TARGET Foo)\n  \nendif()\n";
  assert_parse_y1_emits "y1: cond exists"
    "( if exists \"file.txt\" then ( ) )"
    "if (EXISTS file.txt)\n  \nendif()\n";
  assert_parse_y1_emits "y1: cond is_dir"
    "( if is_dir \"path\" then ( ) )"
    "if (IS_DIRECTORY path)\n  \nendif()\n";
  assert_parse_y1_emits "y1: cond ver_lt"
    "( if ver_lt ${CMAKE_VERSION} \"3.20\" then ( ) )"
    "if (\"${CMAKE_VERSION}\" VERSION_LESS 3.20)\n  \nendif()\n";
  assert_parse_y1_emits "y1: cond policy"
    "( if policy CMP0048 then ( ) )"
    "if (POLICY CMP0048)\n  \nendif()\n";
])

(* Phase 2a pair-wise oracle for cmake_op family (scalar commands). *)
let tier0_cmake_op_y1 = ("t0-cmake_op-y1", [
  assert_parse_y1_emits "y1: cmake_minimum_required" "( cmake_minimum_required \"3.20\" )"
    "cmake_minimum_required(VERSION 3.20)";
  assert_parse_y1_emits "y1: project"                "( project \"Tutorial\" )"
    "project(Tutorial )";
])

let tier8_misc_cmake_op_y1 = ("t8-misc-cmake_op-y1", [
  assert_parse_y1_emits "y1: math"             "( math '1+2' ~out:RESULT )"
    "math(EXPR RESULT \"1+2\" OUTPUT_FORMAT DECIMAL)";
  assert_parse_y1_emits "y1: execute_process"  "( execute_process )"
    "execute_process()";
  assert_parse_y1_emits "y1: include_guard"    "( include_guard )"
    "include_guard(GLOBAL)";
  (* y1: policy_set — legacy parser only matches single-quoted Ycs_string
     for the policy id; "CMP0048" is double-quoted (Ycs_path) and falls
     through the legacy match to the empty-string default, emitting
     `cmake_policy(SET  NEW)`. New parser handles both uniformly via
     str_of. Same shape of legacy bug as ( set NAME val ); omitted from
     oracle until the legacy parser is fixed separately. *)
  assert_parse_y1_emits "y1: enable_language"  "( enable_language )"
    "enable_language()";
])

(* Phase 2a pair-wise oracle for find / install / property families. *)
let tier6_find_install_y1 = ("t6-find-install-y1", [
  assert_parse_y1_emits "y1: find_library" "( find_library VAR ~names:\"m\" ~paths:\"/usr/lib\" )"
    "find_library(VAR NAMES m PATHS /usr/lib)";
  assert_parse_y1_emits "y1: find_path"    "( find_path VAR ~names:\"foo.h\" )"
    "find_path(VAR NAMES foo.h)";
  assert_parse_y1_emits "y1: find_program" "( find_program VAR ~names:\"git\" )"
    "find_program(VAR NAMES git)";
  assert_parse_y1_emits "y1: find_file"    "( find_file VAR ~names:\"config\" )"
    "find_file(VAR NAMES config)";
  assert_parse_y1_emits "y1: install_targets" "( install_targets \"lib\" )"
    (* Tier 4 IR widening: the double space here is the empty-targets
       edge case (Fmt's `list_sp` emits nothing on []; the literal
       space before `%a` remains). Empty targets isn't valid cmake
       so the shape isn't load-bearing. *)
    "install(TARGETS  DESTINATION lib)";
  assert_parse_y1_emits "y1: install_files"   "( install_files \"include\" )"
    "install(FILES  DESTINATION include)";
  assert_parse_y1_emits "y1: install_export"  "( install_export EXP \"lib/cmake\" )"
    "install(EXPORT ${EXP}  DESTINATION lib/cmake)";
])

let tier8_misc_y1 = ("t8-misc-y1", [
  assert_parse_y1_emits "y1: get_target_property"
    "( get_target_property Target Foo ~out:VAR )"
    (* Pre-A2 the printer dropped the TARGET arg (`_` on
       source_target_directory). The new scope-typed Get_property
       preserves the target. *)
    "get_property(VAR TARGET Foo PROPERTY PROP)";
  assert_parse_y1_emits "y1: set_target_properties"
    "( set_target_properties Target Foo )"
    "";
  assert_parse_y1_emits "y1: set_property"
    "( set_property Target Foo )"
    "";
])

(* Phase 2a pair-wise oracle for the try family. Legacy parser only
   recognizes the bare command forms; bridge folds them into
   [ECmakeTryCompile] (simple, all defaults) and [ECmakeTryRun]. The
   direct parser produces the same shape, so both sides must emit
   byte-identical [try_compile(...)] / [try_run(...)] text. *)
let tier7_try_y1 = ("t7-try-y1", [
  assert_parse_y1_emits "y1: try_compile" "( try_compile RESULT )"
    "try_compile(RESULT )";
  assert_parse_y1_emits "y1: try_run"     "( try_run RUN_RES COMPILE_RES )"
    "try_run(RUN_RES COMPILE_RES )";
])

(* Phase 2a pair-wise oracle for the previously legacy-only cases in
   [tier_remaining]. These commands are all supported by both parsers;
   promoting them into the byte oracle closes most of the
   "representative-only" gap for retirement item A. Three cases stay
   legacy-only because the direct parser does not yet handle them:
   string_json_get, set_env, unset_env. *)
let tier_remaining_y1 = ("t-remaining-y1", [
  assert_parse_y1_emits "y1: string_regex_replace"   "( string_regex_replace 'p' 'r' 'in' ~out:OUT )"
    "string(REGEX REPLACE \"p\" r OUT in)";
  assert_parse_y1_emits "y1: string_regex_matchall"  "( string_regex_matchall 'p' 'in' ~out:OUT )"
    "string(REGEX MATCHALL \"p\" OUT in)";
  assert_parse_y1_emits "y1: string_append"          "( string_append MYVAR 'suffix' )"
    "string(APPEND MYVAR suffix)";
  assert_parse_y1_emits "y1: string_prepend"         "( string_prepend MYVAR 'prefix' )"
    "string(PREPEND MYVAR prefix)";
  assert_parse_y1_emits "y1: string_substring"       "( string_substring 'hello' '1' '3' ~out:OUT )"
    "string(SUBSTRING hello 1 3 OUT)";
  assert_parse_y1_emits "y1: string_compare"         "( string_compare 'a' 'b' ~out:OUT )"
    "string(COMPARE EQUAL a b OUT)";
  assert_parse_y1_emits "y1: string_uuid"            "( string_uuid ~out:OUT )"
    "string(UUID OUT NAMESPACE ns NAME n TYPE MD5)";
  assert_parse_y1_emits "y1: path_remove_filename"   "( path_remove_filename PV )"
    "cmake_path(REMOVE_FILENAME PV)";
  assert_parse_y1_emits "y1: path_replace_filename"  "( path_replace_filename PV \"new\" )"
    "cmake_path(REPLACE_FILENAME PV new)";
  assert_parse_y1_emits "y1: path_normal_path"       "( path_normal_path PV ~out:OUT )"
    "cmake_path(NORMAL_PATH PV OUTPUT_VARIABLE OUT)";
  assert_parse_y1_emits "y1: path_absolute_path"     "( path_absolute_path PV )"
    "cmake_path(ABSOLUTE_PATH PV)";
  assert_parse_y1_emits "y1: path_native_path"       "( path_native_path PV ~out:OUT )"
    "cmake_path(NATIVE_PATH PV OUT)";
  assert_parse_y1_emits "y1: path_convert_to_cmake"  "( path_convert_to_cmake \"/tmp\" ~out:OUT )"
    "cmake_path(CONVERT /tmp TO_CMAKE_PATH_LIST OUT)";
  assert_parse_y1_emits "y1: get_directory_property" "( get_directory_property ~out:OUT )"
    "get_directory_property(OUT PROP)";
  assert_parse_y1_emits "y1: set_global_property"    "( set_global_property )"
    "";
  assert_parse_y1_emits "y1: set_source_property"    "( set_source_property \"file.c\" )"
    "set_property(SOURCE file.c PROPERTY PROP )";
  assert_parse_y1_emits "y1: list_sublist"           "( list_sublist MYLIST '1' '3' ~out:OUT )"
    "list(SUBLIST MYLIST 1 3 OUT)\n";
  assert_parse_y1_emits "y1: list_filter"            "( list_filter MYLIST 'pat' )"
    "list(FILTER MYLIST INCLUDE REGEX \"pat\")\n";
  assert_parse_y1_emits "y1: list_transform"         "( list_transform MYLIST ~append )"
    "list(TRANSFORM MYLIST TOUPPER)\n";
  assert_parse_y1_emits "y1: unset_cache"            "( unset_cache MYVAR )"
    "unset(MYVAR\nCACHE )";
  assert_parse_y1_emits "y1: file_strings"           "( file_strings \"f.txt\" ~out:OUT )"
    "file(STRINGS f.txt OUT)";
  assert_parse_y1_emits "y1: file_read_symlink"      "( file_read_symlink \"link\" ~out:OUT )"
    "file(READ_SYMLINK link OUT)";
  (* y1: cmake_call — third legacy-parser-bug shape (same as
     ( set NAME val ) and ( policy_set "CMPxxxx" )): legacy parser
     only matches Yexpr_string (Ycs_string s) for the cmd argument,
     so a double-quoted cmd ("myfn" → Ycs_path) falls through and
     emits an empty CALL name. The new parser handles both via
     str_of. Omitted from pair-wise oracle until the legacy parser
     is fixed separately. *)
  assert_parse_y1_emits "y1: cmake_get_log_level"    "( cmake_get_log_level ~out:OUT )"
    "cmake_language(GET_MESSAGE_LOG_LEVEL OUT)";
  assert_parse_y1_emits "y1: export"                 "( export Target ExpName )"
    "export(EXPORT ExpName\n)";
  assert_parse_y1_emits "y1: configure_package_config_file"
    "( configure_package_config_file \"dest\" \"in\" \"out\" )"
    "configure_package_config_file(in\nout\nINSTALL_DESTINATION dest)";
  assert_parse_y1_emits "y1: write_basic_package_version_file"
    "( write_basic_package_version_file \"file\" )"
    "write_basic_package_version_file(file\n\nCOMPATIBILITY AnyNewerVersion\n)";
])

(* Phase 2a pair-wise oracle for the dir family. *)
let tier0_dir_y1 = ("t0-dir-y1", [
  assert_parse_y1_emits "y1: add_subdirectory"        "( add_subdirectory \"MathFunctions\" )"
    "add_subdirectory(MathFunctions)";
  assert_parse_y1_emits "y1: include_directories"     "( include_directories \"dir1\" \"dir2\" )"
    "include_directories(  dir1\ndir2)";
  assert_parse_y1_emits "y1: add_compile_options"     "( add_compile_options \"-Wall\" \"-Wextra\" )"
    "add_compile_options(-Wall\n-Wextra)";
  assert_parse_y1_emits "y1: add_link_options"        "( add_link_options \"-pie\" )"
    "add_link_options(-pie)";
  assert_parse_y1_emits "y1: add_definitions"         "( add_definitions \"-DFOO\" )"
    "add_definitions(-DFOO)";
  assert_parse_y1_emits "y1: link_directories"        "( link_directories \"/opt/lib\" )"
    "link_directories( /opt/lib)";
])

(* Phase 2a pair-wise oracle for the target family. *)
let tier0_target_y1 = ("t0-target-y1", [
  assert_parse_y1_emits "y1: add_exe"      "( add_exe Target Foo )"
    "add_executable(Foo )";
  assert_parse_y1_emits "y1: add_lib"      "( add_lib Target MathFunctions )"
    "add_library(MathFunctions  )";
  assert_parse_y1_emits "y1: link_lib"     "( link_lib Target Tutorial )"
    "target_link_libraries(Tutorial PRIVATE )";
  assert_parse_y1_emits "y1: link_lib scoped"
    "( link_lib Target Tutorial PRIVATE \"m\" PUBLIC \"dep\" )"
    "target_link_libraries(Tutorial PRIVATE m)\ntarget_link_libraries(Tutorial PUBLIC dep)";
  assert_parse_y1_emits "y1: include_dirs" "( include_dirs Target Tutorial )"
    "target_include_directories(Tutorial PRIVATE )";
  assert_parse_y1_emits "y1: include_dirs scoped"
    "( include_dirs Target Tutorial PRIVATE \"include\" INTERFACE \"iface\" )"
    "target_include_directories(Tutorial PRIVATE include)\ntarget_include_directories(Tutorial INTERFACE iface)";
  assert_parse_y1_emits "y1: compile_defs" "( compile_defs Target Tutorial )"
    "target_compile_definitions(Tutorial PRIVATE )";
  assert_parse_y1_emits "y1: compile_opts" "( compile_opts Target Tutorial )"
    "target_compile_options(Tutorial PRIVATE )";
])

(* Phase 2a pair-wise oracle for the file family. *)
let tier4_file_y1 = ("t4-file-y1", [
  assert_parse_y1_emits "y1: read"              "( file_read \"f.txt\" ~out:OUT )"
    "file(READ f.txt OUT)";
  assert_parse_y1_emits "y1: write"             "( file_write \"f.txt\" 'content' )"
    "file(WRITE f.txt content)";
  assert_parse_y1_emits "y1: glob"              "( file_glob ~out:OUT \"*.cxx\" )"
    "file(GLOB OUT *.cxx)";
  assert_parse_y1_emits "y1: copy"              "( file_copy \"src\" \"dst\" )"
    "file(COPY_FILE src dst)";
  assert_parse_y1_emits "y1: rename"            "( file_rename \"old\" \"new\" )"
    "file(RENAME old new)";
  assert_parse_y1_emits "y1: remove"            "( file_remove \"f.txt\" )"
    "file(REMOVE f.txt)";
  assert_parse_y1_emits "y1: real_path"         "( file_real_path \"f.txt\" ~out:OUT )"
    "file(REAL_PATH f.txt OUT)";
  assert_parse_y1_emits "y1: size"              "( file_size \"f.txt\" ~out:OUT )"
    "file(SIZE f.txt OUT)";
  assert_parse_y1_emits "y1: timestamp"         "( file_timestamp \"f.txt\" ~out:OUT )"
    "file(TIMESTAMP f.txt OUT)";
  assert_parse_y1_emits "y1: make_directory"    "( file_make_directory \"dir\" )"
    "file(MAKE_DIRECTORY dir)";
  assert_parse_y1_emits "y1: touch"             "( file_touch \"f.txt\" )"
    "file(TOUCH f.txt)";
])

(* Phase 2a pair-wise oracle for the path family. *)
let tier5_path_y1 = ("t5-path-y1", [
  assert_parse_y1_emits "y1: get"                     "( path_get PV ~out:OUT )"
    "cmake_path(GET PV FILENAME OUT)";
  assert_parse_y1_emits "y1: has"                     "( path_has PV ~out:OUT )"
    "cmake_path(HAS_FILENAME PV OUT)";
  assert_parse_y1_emits "y1: is_absolute"             "( path_is_absolute PV ~out:OUT )"
    "cmake_path(IS_ABSOLUTE PV OUT)";
  assert_parse_y1_emits "y1: is_relative"             "( path_is_relative PV ~out:OUT )"
    "cmake_path(IS_RELATIVE PV OUT)";
  assert_parse_y1_emits "y1: set"                     "( path_set PV \"/tmp\" )"
    "cmake_path(SET PV /tmp)";
  assert_parse_y1_emits "y1: append"                  "( path_append PV \"sub\" )"
    "cmake_path(APPEND PV sub)";
  assert_parse_y1_emits "y1: compare"                 "( path_compare P1 P2 ~out:OUT )"
    "cmake_path(COMPARE ${P1} EQUAL ${P2} OUT)";
  assert_parse_y1_emits "y1: hash"                    "( path_hash PV ~out:OUT )"
    "cmake_path(HASH PV OUT)";
  assert_parse_y1_emits "y1: get_filename_component"  "( get_filename_component \"file.txt\" ~out:OUT )"
    "get_filename_component(OUT file.txt PATH)";
])

(* Phase 2a pair-wise oracle for the list family. *)
let tier3_list_y1 = ("t3-list-y1", [
  assert_parse_y1_emits "y1: append"             "( list_append MYLIST 'a' 'b' )"
    "list(APPEND MYLIST a b)\n";
  assert_parse_y1_emits "y1: length"             "( list_length MYLIST ~out:LEN )"
    "list(LENGTH MYLIST LEN)\n";
  assert_parse_y1_emits "y1: get"                "( list_get MYLIST 1 ~out:VAL )"
    "list(GET MYLIST 1 VAL)\n";
  assert_parse_y1_emits "y1: remove_item"        "( list_remove_item MYLIST 'a' )"
    "list(REMOVE_ITEM MYLIST a)\n";
  assert_parse_y1_emits "y1: remove_duplicates"  "( list_remove_duplicates MYLIST )"
    "list(REMOVE_DUPLICATES MYLIST)\n";
  assert_parse_y1_emits "y1: reverse"            "( list_reverse MYLIST )"
    "list(REVERSE MYLIST)\n";
  assert_parse_y1_emits "y1: sort"               "( list_sort MYLIST )"
    "list(SORT MYLIST)\n";
  assert_parse_y1_emits "y1: join"               "( list_join MYLIST ';' ~out:RESULT )"
    "list(JOIN MYLIST ; RESULT)\n";
  assert_parse_y1_emits "y1: find"               "( list_find MYLIST 'needle' ~out:IDX )"
    "list(FIND MYLIST needle IDX)\n";
  assert_parse_y1_emits "y1: prepend"            "( list_prepend MYLIST 'first' )"
    "list(PREPEND MYLIST first)\n";
  assert_parse_y1_emits "y1: insert"             "( list_insert MYLIST )"
    "list(INSERT MYLIST 0 )\n";
  assert_parse_y1_emits "y1: remove_at"          "( list_remove_at MYLIST )"
    "list(REMOVE_AT MYLIST )\n";
  assert_parse_y1_emits "y1: pop_back"           "( list_pop_back MYLIST )"
    "list(POP_BACK MYLIST)\n";
  assert_parse_y1_emits "y1: pop_front"          "( list_pop_front MYLIST )"
    "list(POP_FRONT MYLIST)\n";
])

(* Phase 2a pair-wise oracle for the string family. Mirrors tier2_string
   inputs (~17 cases) through both parser paths. Where the parser
   matches the legacy, both sides should produce byte-identical text. *)
let tier2_string_y1 = ("t2-string-y1", [
  assert_parse_y1_emits "y1: concat"            "( string_concat ~out:out_var 'a' 'b' )"
    "string(CONCAT out_var a b)";
  assert_parse_y1_emits "y1: join"              "( string_join ';' ~out:out_var 'a' 'b' )"
    "string(JOIN ; out_var a b)";
  assert_parse_y1_emits "y1: toupper"           "( string_toupper 'hello' )"
    "string(TOUPPER hello ?)";
  assert_parse_y1_emits "y1: tolower"           "( string_tolower 'HELLO' )"
    "string(TOLOWER HELLO ?)";
  assert_parse_y1_emits "y1: length"            "( string_length 'hello' )"
    "string(LENGTH hello ?)";
  assert_parse_y1_emits "y1: replace"           "( string_replace 'old' 'new' 'input' )"
    "string(REPLACE old new ? input)";
  assert_parse_y1_emits "y1: regex_match"       "( string_regex_match 'p.*' 'input' )"
    "string(REGEX MATCH \"p.*\" ? input)";
  assert_parse_y1_emits "y1: find"              "( string_find 'sub' 'haystack' )"
    "string(FIND haystack sub ?)";
  assert_parse_y1_emits "y1: timestamp"         "( string_timestamp )"
    "string(TIMESTAMP ?)";
  assert_parse_y1_emits "y1: hex"               "( string_hex 'abc' )"
    "string(HEX abc ?)";
  assert_parse_y1_emits "y1: make_c_identifier" "( string_make_c_identifier 'my var' )"
    "string(MAKE_C_IDENTIFIER \"my var\" ?)";
  assert_parse_y1_emits "y1: toupper ~out"       "( string_toupper 'hello' ~out:OUT )"
    "string(TOUPPER hello OUT)";
  assert_parse_y1_emits "y1: toupper ~out first" "( string_toupper ~out:OUT 'hello' )"
    "string(TOUPPER hello OUT)";
  assert_parse_y1_emits "y1: concat ~out only"   "( string_concat ~out:OUT )"
    "string(CONCAT OUT )";
  assert_parse_y1_emits "y1: tolower ~out"       "( string_tolower 'HELLO' ~out:OUT )"
    "string(TOLOWER HELLO OUT)";
  assert_parse_y1_emits "y1: hex ~out"           "( string_hex 'abc' ~out:OUT )"
    "string(HEX abc OUT)";
  assert_parse_y1_emits "y1: length ~out"        "( string_length 'hello' ~out:OUT )"
    "string(LENGTH hello OUT)";
])

let () =
  Alcotest.run "Yelu Parser" [
    tier0_control; tier0_control_y1; tier0_cond; tier0_cond_y1;
    tier0_var; tier0_var_y1; tier0_cmake_op; tier0_cmake_op_y1;
    tier0_target; tier0_target_y1; tier0_dir; tier0_dir_y1; tier0_file; tier0_scripting; tier0_full;
    tier1_target; tier2_string; tier2_string_y1; tier3_list; tier3_list_y1;
    tier4_file; tier4_file_y1; tier5_path; tier5_path_y1;
    tier6_find_install; tier6_find_install_y1;
    tier7_scripting; tier7_try_y1;
    tier8_misc; tier8_misc_y1; tier8_misc_cmake_op_y1;
    tier_remaining; tier_remaining_y1; tier9_genex; tier9_genex_y1;
  ]
