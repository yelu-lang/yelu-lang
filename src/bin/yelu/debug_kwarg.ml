open Base
open Yelu_langs.Lang_yelu_parse

let test name input =
  Stdio.printf "%-25s " name;
  match parse_program input with
  | Ok _ -> Stdio.print_endline "OK"
  | Error e -> Stdio.printf "Error: %s\n" e

let () =
  test "toupper ~out" "( string_toupper 'hello' ~out:OUT )";
  test "toupper no ~out" "( string_toupper 'hello' )";
  test "concat ~out" "( string_concat ~out:OUT 'a' 'b' )";
  test "concat ~out only" "( string_concat ~out:OUT )"
