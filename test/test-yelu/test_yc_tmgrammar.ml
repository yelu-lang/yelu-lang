(* Tests for the TextMate vocabulary-rule generation (Yc_tmgrammar).
   Locks the bug-prone bits: scope coverage, longest-first ordering,
   regex escaping, and `\b` boundaries. See
   doc/lang/surface_lsp_framework.md Sec 3.8. *)

open Base
module D = Yelu_langs.Yc_driver
module G = Yelu_langs.Yc_tmgrammar
module M = Yelu_langs.Yc_manifest

let rules = lazy (G.vocabulary_rules (D.manifest ()))

let index_of_regex ~f =
  List.findi (Lazy.force rules) ~f:(fun _ (re, _) -> f re)
  |> Option.map ~f:fst

let test_scope_coverage =
  Alcotest.test_case "every manifest scope appears in a rule" `Quick (fun () ->
    let rule_scopes =
      List.map (Lazy.force rules) ~f:snd |> Set.of_list (module String)
    in
    let manifest_scopes =
      List.map M.all ~f:(fun e -> e.M.tm_scope) |> Set.of_list (module String)
    in
    let missing = Set.diff manifest_scopes rule_scopes in
    Alcotest.(check bool)
      (Printf.sprintf "scopes missing from rules: [%s]"
         (String.concat ~sep:" " (Set.to_list missing)))
      true (Set.is_empty missing))

let test_walrus_before_colon =
  Alcotest.test_case "':=' rule precedes ':' rule (longest-first)" `Quick
    (fun () ->
      let i_walrus = index_of_regex ~f:(String.equal "(:=)") in
      let i_colon  = index_of_regex ~f:(String.equal "(:)") in
      match i_walrus, i_colon with
      | Some w, Some c ->
        Alcotest.(check bool) "walrus index < colon index" true (w < c)
      | _ ->
        Alcotest.failf "missing punctuation rule: ':=' %b ':' %b"
          (Option.is_some i_walrus) (Option.is_some i_colon))

let test_paren_escaped =
  Alcotest.test_case "'(' is regex-escaped" `Quick (fun () ->
    let has_escaped_paren =
      List.exists (Lazy.force rules) ~f:(fun (re, _) ->
        String.is_substring re ~substring:"\\(")
    in
    Alcotest.(check bool) "some rule contains an escaped paren" true
      has_escaped_paren)

let test_word_boundary =
  Alcotest.test_case "word-class rules use \\b(...)\\b" `Quick (fun () ->
    let has_word_rule =
      List.exists (Lazy.force rules) ~f:(fun (re, _) ->
        String.is_prefix re ~prefix:"\\b(" && String.is_suffix re ~suffix:")\\b")
    in
    Alcotest.(check bool) "some rule is word-boundary bounded" true has_word_rule)

let () =
  Alcotest.run "yc_tmgrammar"
    [ "vocabulary",
      [ test_scope_coverage; test_walrus_before_colon;
        test_paren_escaped; test_word_boundary ] ]
