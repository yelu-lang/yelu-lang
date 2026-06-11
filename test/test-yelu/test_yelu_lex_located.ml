(* Tests for the lossless located scanner (Yelu_lexer.lex_located):
   comment preservation, source spans, and consistency with the existing
   token_list path. Foundation for the comment-preserving CST / formatter
   (see doc/lang/surface_lsp_framework.md, Milestone 1). *)

open Base
open Yelu_langs.Yelu_lexer

let located input =
  match lex_located input with
  | Ok ts -> ts
  | Error e -> Alcotest.failf "lex_located error: %s" e

let plain input =
  match Angstrom.parse_string ~consume:All token_list input with
  | Ok ts -> ts
  | Error e -> Alcotest.failf "token_list error: %s" e

let tok_str t = Sexp.to_string ([%sexp_of: token] t)

(* 1. A comment between two identifiers is preserved with the right span. *)
let test_comment_preserved =
  Alcotest.test_case "comment kept with span" `Quick (fun () ->
    (* indices: a=0 ' '=1 #=2 ' '=3 c=4 \n=5 b=6 *)
    let got = located "a # c\nb" in
    let shape =
      List.map got ~f:(fun (t, s) ->
        Printf.sprintf "%s@%d-%d" (tok_str t) s.lo s.hi)
    in
    Alcotest.(check (list string)) "tokens+spans"
      [ "(IDENT a)@0-1"; "(COMMENT\" c\")@2-5"; "(IDENT b)@6-7" ]
      shape)

(* 2. The located stream, minus COMMENT trivia, equals the plain token_list
   — the lossless scanner is a faithful superset of the existing one. *)
let test_invariant_modulo_comments =
  Alcotest.test_case "located \\ comments == token_list" `Quick (fun () ->
    let src =
      "if ver_lt ${V} '3' then\n\
      \  # set the policy\n\
      \  policy_set(CMP0048)  # a trailing note\n\
       end" in
    let from_located =
      located src
      |> List.filter_map ~f:(fun (t, _) ->
           match t with COMMENT _ -> None | t -> Some t)
    in
    let from_plain = plain src in
    Alcotest.(check (list string)) "same tokens"
      (List.map from_plain ~f:tok_str)
      (List.map from_located ~f:tok_str))

(* 3. An IDENT's span exactly covers its text in the source. *)
let test_span_substring =
  Alcotest.test_case "IDENT span matches source slice" `Quick (fun () ->
    let src = "foreach x list_append" in
    located src
    |> List.iter ~f:(fun (t, s) ->
         match t with
         | IDENT name ->
           let slice = String.sub src ~pos:s.lo ~len:(s.hi - s.lo) in
           Alcotest.(check string) "slice = ident" name slice
         | _ -> ()))

(* 4. Comment body round-trips: "#" ^ body reproduces the source lexeme. *)
let test_comment_roundtrip =
  Alcotest.test_case "comment body round-trips" `Quick (fun () ->
    let src = "x #  hello world  " in
    match located src |> List.find_map ~f:(fun (t, s) ->
      match t with COMMENT b -> Some (b, s) | _ -> None)
    with
    | Some (body, s) ->
      let lexeme = String.sub src ~pos:s.lo ~len:(s.hi - s.lo) in
      Alcotest.(check string) "reconstruct" lexeme ("#" ^ body)
    | None -> Alcotest.fail "no comment found")

let () =
  Alcotest.run "yelu_lex_located"
    [ "located",
      [ test_comment_preserved; test_invariant_modulo_comments;
        test_span_substring; test_comment_roundtrip ] ]
