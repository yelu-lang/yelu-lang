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

let parse_tests = ("parse", [
  assert_parses "empty block" "{ }";

  assert_parses "let binding"
    "let x = Target Foo in { }";

  assert_parses "let with type annotation"
    "let tut : target = Target Tutorial in { }";

  assert_parses "assignment :="
    "{ CMAKE_CXX_STANDARD := \"11\" }";

  assert_parses "set command (legacy)"
    "{ set 'CMAKE_CXX_STANDARD' \"11\" }";

  assert_parses "cmake_minimum_required"
    "{ cmake_minimum_required \"3.20\" }";

  assert_parses "project"
    "{ project \"Tutorial\" }";

  assert_parses "add_exe"
    "{ add_exe Target Foo }";

  assert_parses "add_lib"
    "{ add_lib Target MathFunctions }";

  assert_parses "link_lib"
    "{ link_lib Target Tutorial }";

  assert_parses "include_dirs"
    "{ include_dirs Target Tutorial { } }";

  assert_parses "compile_defs"
    "{ compile_defs Target Tutorial { } }";

  assert_parses "compile_opts"
    "{ compile_opts Target Tutorial { } }";

  assert_parses "configure_file"
    "{ configure_file \"input.h.in\" \"output.h\" }";

  assert_parses "add_subdirectory"
    "{ add_subdirectory \"MathFunctions\" }";

  assert_parses "if then (defined)"
    "{ if defined 'TEST' then { message 'defined' } }";

  assert_parses "if simple (ON)"
    "{ if ON then { message 'yes' } }";

  assert_parses "if with else (defined)"
    "{ if defined 'TEST' then { message 'yes' } else { } }";

  assert_parses "if target"
    "{ if target Target Foo then { } }";

  assert_parses "if target with else"
    "{ if target Target Foo then { message 'found' } else { message 'not found' } }";

  assert_parses "foreach in list"
    "{ foreach item in [\"a\" \"b\" \"c\"] { message \"${item}\" } }";

  assert_parses "foreach range"
    "{ foreach i in RANGE 1..10 { message \"${i}\" } }";

  assert_parses "fun empty body"
    "{ fun f() { } }";

  assert_parses "fun with body"
    "{ fun f() { message 'hi' } }";

  assert_parses "fun args"
    "{ fun f(x) { message 'hi' } }";

  assert_parses "cache var :="
    "{ cache BUILD_SHARED_LIBS := ON ; 'Build shared libs' }";

  assert_parses "var multi-value :="
    "{ FLAGS := \"-Wall\", \"-Wextra\" }";

  assert_parses "cond not"
    "{ if not ${FLAG} then { message 'off' } }";

  assert_parses "cond str_eq"
    "{ if str_eq ${X} 'hello' then { } }";

  assert_parses "cond and/or"
    "{ if ${A} and ${B} then { } }";

  assert_parses "cond match"
    "{ if match ${X} 'pat.*' then { } }";

  assert_parses "cond exists"
    "{ if exists \"file.txt\" then { } }";

  assert_parses "cond is_dir"
    "{ if is_dir \"path\" then { } }";

  assert_parses "cond ver_lt"
    "{ if ver_lt ${CMAKE_VERSION} \"3.20\" then { } }";

  assert_parses "cond list_in"
    "{ if list_in ${X} ${MYLIST} then { } }";

  assert_parses "cond policy"
    "{ if policy CMP0048 then { } }";

  assert_parses "cond eq"
    "{ if eq ${X} 42 then { } }";

  assert_parses "labeled arg ~msg:"
    "{ option 'ENABLE_FOO' ON ~msg:'Enable foo' }";

  assert_parses "bare flag ~global"
    "{ add_lib_imported Target Foo ~global }";

  assert_parses "full step1"
    "let tut = Target Tutorial in { cmake_minimum_required \"3.20\"; project \"Tutorial\"; add_exe tut \"tutorial.cxx\" }";
])

let () = Alcotest.run "Yelu Parser" [ parse_tests ]
