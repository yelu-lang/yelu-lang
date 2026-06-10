(* Yc_tmgrammar — derive TextMate *vocabulary* rules from the manifest.

   Produces (oniguruma-regex, tm-scope) pairs for the vocabulary slice of
   the grammar — keywords, commands, operators, punctuation. The bug-prone
   parts (regex escaping, longest-first ordering, `\b` boundaries) live
   here so they can be unit-tested without JSON. The *structure* rules
   (strings, comments, `${…}` / `$<…>` interpolation, numbers) are NOT
   here — they are the hand-written template in the `yelu tmgrammar`
   emitter, per Sec 3.8 / Milestone 0 of
   doc/lang/surface_lsp_framework.md.

   Consumes a manifest entry list (passed in, normally from
   Yc_driver.manifest ()) so the driver stays the boundary. *)

open Base
module M = Yc_manifest

(* Escape oniguruma/regex metacharacters so a literal token matches. *)
let regex_escape s =
  String.concat_map s ~f:(fun c ->
    match c with
    | '.' | '*' | '+' | '?' | '(' | ')' | '[' | ']' | '{' | '}'
    | '|' | '^' | '$' | '\\' | '/' -> "\\" ^ String.of_char c
    | c -> String.of_char c)

(* Longest-first, then lexicographic — so ":=" precedes ":" in an
   alternation and a longer command precedes a prefix of it. *)
let by_len_desc surfaces =
  List.sort surfaces ~compare:(fun a b ->
    match Int.compare (String.length b) (String.length a) with
    | 0 -> String.compare a b
    | n -> n)

let alt parts = String.concat ~sep:"|" parts

(* (regex, scope) pairs. Word-classes become one `\b(a|b|…)\b` rule per
   scope; punctuation becomes one escaped rule per token, ordered globally
   longest-first so multi-char tokens (":=", "..") are tried before the
   single-char tokens that prefix them (":", "."-free here but safe). *)
let vocabulary_rules (entries : M.entry list) : (string * string) list =
  let word, punct =
    List.partition_tf entries ~f:(fun e -> M.is_word_class e.M.lexical_class)
  in
  let word_rules =
    Map.of_alist_multi (module String)
      (List.map word ~f:(fun e -> e.M.tm_scope, e.M.surface))
    |> Map.to_alist
    |> List.map ~f:(fun (scope, surfaces) ->
         Printf.sprintf "\\b(%s)\\b" (alt (by_len_desc surfaces)), scope)
  in
  let punct_rules =
    punct
    |> List.sort ~compare:(fun a b ->
         match
           Int.compare (String.length b.M.surface) (String.length a.M.surface)
         with
         | 0 -> String.compare a.M.surface b.M.surface
         | n -> n)
    |> List.map ~f:(fun e ->
         Printf.sprintf "(%s)" (regex_escape e.M.surface), e.M.tm_scope)
  in
  word_rules @ punct_rules
