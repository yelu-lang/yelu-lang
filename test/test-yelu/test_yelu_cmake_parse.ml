open Base
open Yelu_langs.Lang_yelu_parse

let parse input =
  match parse_program input with
  | Ok stmt -> stmt
  | Error e -> Alcotest.failf "Parse error: %s" e

let assert_parses name input =
  Alcotest.test_case name `Quick (fun () ->
    let _stmt = parse input in
    ())

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
  assert_parses "include_dirs" "( include_dirs Target Tutorial )";
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
  assert_parses "labeled arg ~msg:" "( option 'ENABLE_FOO' ON ~msg:'Enable foo' )";
  assert_parses "bare flag ~global" "( add_lib_imported Target Foo ~global )";
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
  assert_parses "precompile_headers" "( precompile_headers Target Tutorial ~private:[\"pch.h\"] )";
  assert_parses "add_lib_alias" "( add_lib_alias \"alias\" \"original\" )";
  assert_parses "add_exe_alias" "( add_exe_alias \"alias\" \"original\" )";
  assert_parses "add_custom_target" "( add_custom_target \"name\" )";
  assert_parses "add_dependencies" "( add_dependencies \"tgt\" \"dep\" )";
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
  assert_parses "get" "( list_get MYLIST ~out:VAL )";
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

(* Tier 9: generator expressions *)
let tier9_genex = ("t9-genex", [
  assert_parses "$<CONFIG> in message" "( message $<CONFIG> )";
  assert_parses "$<TARGET_FILE> in message" "( message $<TARGET_FILE:tgt> )";
  (* Nested $<...> not supported by simple lexer — known limitation *)
  assert_parses "${VAR} eval" "( message ${CMAKE_VERSION} )";
  assert_parses "$<BUILD_INTERFACE>" "( compile_opts Target Tutorial ~public:[$<BUILD_INTERFACE:-Wall>] )";
])

let () =
  Alcotest.run "Yelu Parser" [
    tier0_control; tier0_cond; tier0_var; tier0_cmake_op;
    tier0_target; tier0_dir; tier0_file; tier0_scripting; tier0_full;
    tier1_target; tier2_string; tier3_list; tier4_file; tier5_path;
    tier6_find_install; tier7_scripting; tier8_misc; tier9_genex;
  ]
