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

let () =
  Alcotest.run "Yelu Parser" [
    tier0_control; tier0_cond; tier0_var; tier0_cmake_op;
    tier0_target; tier0_dir; tier0_file; tier0_scripting; tier0_full;
    tier1_target; tier2_string;
  ]
