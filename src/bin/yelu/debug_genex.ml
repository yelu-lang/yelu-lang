open Base
open Angstrom
open Yelu_langs.Lang_yelu_lexer

let test name input =
  match parse_string ~consume:All token_list input with
  | Ok [EVAL s] -> Stdio.printf "%-30s -> %s\n" name s
  | Ok toks -> Stdio.printf "%-30s -> %d tokens: %s\n" name (List.length toks)
      (String.concat ~sep:", " (List.map toks ~f:(fun t -> Sexp.to_string_hum ([%sexp_of: token] t))))
  | Error e -> Stdio.printf "%-30s -> ERROR: %s\n" name e

let () =
  test "simple" "$<CONFIG:Debug>";
  test "nested" "$<IF:$<CONFIG:Debug>,release>";
  test "double" "$<AND:$<CONFIG:Debug>,$<BOOL:${FOO}>>";
  test "bare <" "$<IF:a<b,yes,no>";
  test "plain var" "${HOME}";
  test "both in sequence" "$<CONFIG> $<TARGET_FILE:tgt>";
  test "nested in sequence" "$<IF:$<CONFIG:Debug>,a> $<IF:$<CONFIG:Release>,b>"
