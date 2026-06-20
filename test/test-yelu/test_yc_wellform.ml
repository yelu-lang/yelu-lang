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

(* Step 2 (labeled-only): a known command in the positional cmake-keyword form
   is a fatal wellform reject (use ~label= / yc_raw). *)
let has_positional src =
  List.exists (W.check_all (parse src)) ~f:(function
    | W.Positional_form _ -> true
    | _ -> false)

let pcase name src ~expect =
  Alcotest.test_case name `Quick (fun () ->
    Alcotest.(check bool) name expect (has_positional src))

let () =
  Alcotest.run "yc_wellform"
    [ ( "Y14 enum shadow",
        [ case "set public shadows Public" "public := 1" ~expect:true;
          case "cache static shadows Static" "cache static := 1" ~expect:true;
          case "option string shadows String" "option string 'h' ON" ~expect:true;
          (* a normal variable is fine *)
          case "result ok" "result := 1" ~expect:false;
          case "snake local ok" "my_var := 1" ~expect:false ] );
      ( "positional-form reject",
        [ pcase "install_targets positional → reject"
            "install_targets $t COMPONENT 'c' LIBRARY DESTINATION 'lib'" ~expect:true;
          (* the labeled form is the supported surface — no reject *)
          pcase "install_targets labeled ok"
            "install_targets $t ~component='c' ~library.destination='lib'" ~expect:false;
          (* a genuinely unknown/external command stays a plain raw — no reject *)
          pcase "unknown command not flagged"
            "some_external_macro 'a' 'b'" ~expect:false ] ) ]
