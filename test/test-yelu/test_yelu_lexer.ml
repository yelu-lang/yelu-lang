open Base
open Angstrom
open Yelu_langs.Yelu_lexer

let lex input =
  match parse_string ~consume:All token_list input with
  | Ok toks -> toks
  | Error e -> Alcotest.failf "Lex error: %s" e

let assert_tokens name input expected =
  Alcotest.test_case name `Quick (fun () ->
    let got = List.map (lex input) ~f:(fun t -> Sexp.to_string ([%sexp_of: token] t)) in
    Alcotest.(check (list string)) name expected got)

let lex_tests = ("lex", [
  assert_tokens "keywords"
    "let in if then else foreach function macro while break continue return"
    ["LET"; "IN"; "IF"; "THEN"; "ELSE"; "FOREACH"; "FUNCTION"; "MACRO";
     "WHILE"; "BREAK"; "CONTINUE"; "RETURN"];

  assert_tokens "identifiers"
    "foo bar_baz x-1"
    ["(IDENT foo)"; "(IDENT bar_baz)"; "(IDENT x-1)"];

  assert_tokens "path string"
    "\"tutorial.cxx\" \"src/\""
    ["(PATH tutorial.cxx)"; "(PATH src/)"];

  assert_tokens "plain string"
    "'hello' 'world'"
    ["(STRING hello)"; "(STRING world)"];

  assert_tokens "eval"
    "${CMAKE_SOURCE_DIR} $<CONFIG>"
    ["(EVAL ${CMAKE_SOURCE_DIR})"; "(EVAL $<CONFIG>)"];

  assert_tokens "keyword prefix"
    ":PUBLIC :STATIC :private"
    ["(KEYWORD PUBLIC)"; "(KEYWORD STATIC)"; "(KEYWORD private)"];

  assert_tokens "bool"
    "ON OFF"
    ["(BOOL true)"; "(BOOL false)"];

  assert_tokens "integer"
    "42 0 100"
    ["(INT 42)"; "(INT 0)"; "(INT 100)"];

  assert_tokens "delimiters"
    "{ } [ ] ( ) , ; : .. ="
    ["LBRACE"; "RBRACE"; "LBRACK"; "RBRACK";
     "LPAREN"; "RPAREN"; "COMMA"; "SEMI"; "COLON"; "DOTDOT"; "EQ"];

  assert_tokens "let binding"
    "let x = Target Foo"
    ["LET"; "(IDENT x)"; "EQ"; "TARGET"; "(IDENT Foo)"];

  assert_tokens "walrus operator"
    "x := \"value\""
    ["(IDENT x)"; "WALRUS"; "(PATH value)"];

  assert_tokens "cache keyword"
    "cache X := ON"
    ["CACHE"; "(IDENT X)"; "WALRUS"; "(BOOL true)"];

  assert_tokens "fun keyword"
    "fun f() { }"
    ["FUNCTION"; "(IDENT f)"; "LPAREN"; "RPAREN"; "LBRACE"; "RBRACE"];

  assert_tokens "Target constructor"
    "Target Foo"
    ["TARGET"; "(IDENT Foo)"];

  assert_tokens "~label:value lexes as TILDE IDENT KEYWORD"
    "~out:OUT"
    ["TILDE"; "(IDENT out)"; "(KEYWORD OUT)"];

  assert_tokens "nested genex $<IF:$<CONFIG:Debug>,release>"
    "$<IF:$<CONFIG:Debug>,release>"
    ["(EVAL $<IF:$<CONFIG:Debug>,release>)"];

  assert_tokens "double nested genex"
    "$<AND:$<CONFIG:Debug>,$<BOOL:${FOO}>>"
    ["(EVAL $<AND:$<CONFIG:Debug>,$<BOOL:${FOO}>>)"];

  assert_tokens "plain ${VAR} still works"
    "${CMAKE_SOURCE_DIR}"
    ["(EVAL ${CMAKE_SOURCE_DIR})"];

  assert_tokens "bare < not a nesting delimiter"
    "$<IF:a<b,yes,no>"
    ["(EVAL $<IF:a<b,yes,no>)"];
])

(* Negative tests — lexer should reject malformed input *)
let lex_negative = ("lex-negative", [
  Alcotest.test_case "unterminated nested genex" `Quick (fun () ->
    match Angstrom.parse_string ~consume:All token_list "$<IF:$<CONFIG:Debug>,debug,release" with
    | Ok _ -> Alcotest.fail "expected lex error for unterminated genex"
    | Error _ -> ());
])

let lex2 = ("lex2", [
  assert_tokens "block with semis"
    "{ stmt1; stmt2 }"
    ["LBRACE"; "(IDENT stmt1)"; "SEMI"; "(IDENT stmt2)"; "RBRACE"];

  assert_tokens "command with keyword args"
    "add_executable tut :sources [\"a.cxx\"]"
    ["(IDENT add_executable)"; "(IDENT tut)"; "(KEYWORD sources)";
     "LBRACK"; "(PATH a.cxx)"; "RBRACK"];

  assert_tokens "comment skipped"
    "# this is a comment\n identifier"
    ["(IDENT identifier)"];

  assert_tokens "target and cvar"
    "target cvar"
    ["TARGET"; "CVAR"];

  assert_tokens "RANGE keyword"
    "foreach i in RANGE 1..10 {}"
    ["FOREACH"; "(IDENT i)"; "IN"; "RANGE"; "(INT 1)";
     "DOTDOT"; "(INT 10)"; "LBRACE"; "RBRACE"];
])

let () = Alcotest.run "Yelu Lexer" [ lex_tests; lex2; lex_negative ]
