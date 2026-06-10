(* Co-truth lock for the yc vocabulary manifest.

   The manifest ([Yc_manifest]) is the curated single source the TextMate
   generator consumes. These tests lock it to the *other* enumerable
   providers so the three can never silently drift:

   1. manifest Command surfaces  ≡  Yc_primitives.command_names
   2. manifest word surfaces     ≡  Yc_primitives.reserved_names
   3. Yelu_lexer hard keywords   ⊆  manifest Control ∪ Type surfaces

   See doc/lang/surface_lsp_framework.md Sec 3.8. *)

open Base
module M = Yelu_langs.Yc_manifest
module P = Yelu_langs.Yc_primitives

let sset l = Set.of_list (module String) l

let pp_set s = String.concat ~sep:" " (Set.to_list s)

let check_set_eq name ~expected ~got =
  Alcotest.test_case name `Quick (fun () ->
    let missing = Set.diff expected got in   (* in provider, absent from manifest *)
    let extra   = Set.diff got expected in   (* in manifest, absent from provider *)
    Alcotest.(check bool)
      (Printf.sprintf "%s\n  manifest-missing: [%s]\n  manifest-extra:   [%s]"
         name (pp_set missing) (pp_set extra))
      true
      (Set.is_empty missing && Set.is_empty extra))

let check_subset name ~sub ~super =
  Alcotest.test_case name `Quick (fun () ->
    let uncovered = Set.diff sub super in
    Alcotest.(check bool)
      (Printf.sprintf "%s\n  uncovered by manifest: [%s]" name (pp_set uncovered))
      true
      (Set.is_empty uncovered))

let command_surfaces = sset (M.surfaces_of_class M.Command)
let word_surfaces = sset M.word_surfaces

(* Control + Type are the manifest's hard-keyword classes — the ones the
   lexer turns into dedicated keyword tokens. *)
let manifest_hard_keywords =
  sset (M.surfaces_of_class M.Control_keyword @ M.surfaces_of_class M.Type_keyword)

let lexer_hard_keywords =
  sset (Map.keys Yelu_langs.Yelu_lexer.reserved)

let tests =
  [ check_set_eq "commands ≡ Yc_primitives.command_names"
      ~expected:P.command_names ~got:command_surfaces;
    check_set_eq "word surfaces ≡ Yc_primitives.reserved_names"
      ~expected:P.reserved_names ~got:word_surfaces;
    check_subset "lexer hard keywords ⊆ manifest (Control ∪ Type)"
      ~sub:lexer_hard_keywords ~super:manifest_hard_keywords;
  ]

let () =
  Alcotest.run "yc_manifest" [ "co-truth", tests ]
