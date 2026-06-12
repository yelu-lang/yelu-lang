(* Wellform checks — Y14: a variable declaration must not shadow an enum
   constructor (case-insensitively). The capitalized form (`set Public`) is a
   *parse* error (the lexer tokenizes it as the KEYWORD), so here we cover the
   lowercase/mixed shadow that parses and must be rejected at wellform. *)

open Base
module W = Yelu_langs.Yc_wellform

let parse s =
  match Yelu_langs.Yelu_parse.parse_program_y1 s with
  | Ok e -> e
  | Error e -> Alcotest.failf "parse %S: %s" s e

let has_enum_shadow src =
  List.exists (W.check_all (parse src)) ~f:(function
    | W.Enum_shadow _ -> true
    | _ -> false)

let case name src ~expect =
  Alcotest.test_case name `Quick (fun () ->
    Alcotest.(check bool) name expect (has_enum_shadow src))

let () =
  Alcotest.run "yc_wellform"
    [ ( "Y14 enum shadow",
        [ case "set public shadows Public" "public := 1" ~expect:true;
          case "cache static shadows Static" "cache static := 1" ~expect:true;
          case "option string shadows String" "option string 'h' ON" ~expect:true;
          (* a normal variable is fine *)
          case "result ok" "result := 1" ~expect:false;
          case "snake local ok" "my_var := 1" ~expect:false ] ) ]
