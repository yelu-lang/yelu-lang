(* Unit tests for Yelu_cmake.substitute — cmake ${X} interpolation.

   The single source of truth for ${X} substitution in yelu_langs.
   Exercises each case the parent chat called out (and the corner
   cases we deferred) so we know what we DO and DON'T support. *)

open Base
open Yelu_langs.Yelu_cmake

let env_with vars =
  List.fold vars ~init:empty_env ~f:(fun env (k, v) ->
    set_var env ~key:k ~data:(VString v))

let check_sub name ~env ~input ~expected =
  Alcotest.test_case name `Quick (fun () ->
    Alcotest.(check string) name expected (substitute env input))

(* ============================================================
   The basic case
   ============================================================ *)
let basic =
  ( "basic",
    [
      check_sub "no interpolation passes through"
        ~env:empty_env ~input:"hello" ~expected:"hello";
      check_sub "empty string"
        ~env:empty_env ~input:"" ~expected:"";
      check_sub "whole-string ${X}"
        ~env:(env_with [ "X", "world" ])
        ~input:"${X}" ~expected:"world";
      check_sub "${X} unbound → empty (cmake silent deref)"
        ~env:empty_env ~input:"${UNDEF}" ~expected:"";
    ] )

(* ============================================================
   Mid-string interpolation — the case parse-time hacks miss
   ============================================================ *)
let mid_string =
  ( "mid_string",
    [
      check_sub "prefix${X}suffix"
        ~env:(env_with [ "X", "M" ])
        ~input:"prefix${X}suffix" ~expected:"prefixMsuffix";
      check_sub "${A}-${B} multiple refs"
        ~env:(env_with [ "A", "left"; "B", "right" ])
        ~input:"${A}-${B}" ~expected:"left-right";
      check_sub "${A}${B} adjacent"
        ~env:(env_with [ "A", "x"; "B", "y" ])
        ~input:"${A}${B}" ~expected:"xy";
      check_sub "literal text on both sides"
        ~env:(env_with [ "X", "M" ])
        ~input:"abc${X}def" ~expected:"abcMdef";
    ] )

(* ============================================================
   Nested ${${prefix}_X} — the case that breaks ad-hoc hacks
   ============================================================ *)
let nested =
  ( "nested",
    [
      check_sub "${${prefix}_X} — inner-first, then outer lookup"
        ~env:(env_with [ "prefix", "MY"; "MY_X", "bingo" ])
        ~input:"${${prefix}_X}" ~expected:"bingo";
      check_sub "${${prefix}_X} with mid-string suffix"
        ~env:(env_with [ "prefix", "MY"; "MY_X", "v" ])
        ~input:"prefix:${${prefix}_X}:end" ~expected:"prefix:v:end";
      check_sub "${${A}} double-nested"
        ~env:(env_with [ "A", "B"; "B", "final" ])
        ~input:"${${A}}" ~expected:"final";
    ] )

(* ============================================================
   Edge cases — unbalanced, escape-like patterns
   ============================================================ *)
let edges =
  ( "edges",
    [
      check_sub "unbalanced ${ at end → literal"
        ~env:empty_env ~input:"foo${" ~expected:"foo${";
      check_sub "${ without matching } → literal"
        ~env:empty_env ~input:"a${b c" ~expected:"a${b c";
      check_sub "$ without { is literal"
        ~env:empty_env ~input:"$foo" ~expected:"$foo";
      check_sub "} alone is literal"
        ~env:empty_env ~input:"close }" ~expected:"close }";
      check_sub "${X with spaces} — treated as a name with spaces"
        ~env:(env_with [ "X Y", "spaced" ])
        ~input:"${X Y}" ~expected:"spaced";
    ] )

(* ============================================================
   Deferred-corner explicit documentation: these have no fix
   but the tests pin our current behavior so a future change
   that touches them is visible.
   ============================================================ *)
let deferred =
  ( "deferred_corners",
    [
      check_sub "$ENV{X} — not handled; literal passes through"
        ~env:empty_env ~input:"$ENV{HOME}" ~expected:"$ENV{HOME}";
      check_sub "@X@ — configure_file syntax; not handled"
        ~env:(env_with [ "X", "v" ])
        ~input:"@X@" ~expected:"@X@";
      check_sub "$<...> — generator expression; not handled"
        ~env:empty_env ~input:"$<CONFIG:Debug>" ~expected:"$<CONFIG:Debug>";
    ] )

(* ============================================================
   Value-stringification — bool / int / unbound → cmake-style
   ============================================================ *)
let stringify =
  ( "stringify",
    [
      Alcotest.test_case "bool true → ON" `Quick (fun () ->
        let env = set_var empty_env ~key:"X" ~data:(VBool true) in
        Alcotest.(check string) "" "ON" (substitute env "${X}"));
      Alcotest.test_case "bool false → OFF" `Quick (fun () ->
        let env = set_var empty_env ~key:"X" ~data:(VBool false) in
        Alcotest.(check string) "" "OFF" (substitute env "${X}"));
      Alcotest.test_case "int 42 → 42" `Quick (fun () ->
        let env = set_var empty_env ~key:"X" ~data:(VInt 42) in
        Alcotest.(check string) "" "42" (substitute env "${X}"));
    ] )

(* ============================================================
   Cache fallback — substitute uses find_var, which falls
   through normal → cache. So ${X} where X is in cache_vars
   resolves correctly.
   ============================================================ *)
let cache_fallback =
  ( "cache_fallback",
    [
      Alcotest.test_case "cache var resolved via fallback" `Quick (fun () ->
        let env = set_cache_var empty_env ~key:"X" ~data:(VString "from-cache") in
        Alcotest.(check string) "" "from-cache" (substitute env "${X}"));
      Alcotest.test_case "normal wins over cache" `Quick (fun () ->
        let env = set_cache_var empty_env ~key:"X" ~data:(VString "cache") in
        let env = set_var env ~key:"X" ~data:(VString "normal") in
        Alcotest.(check string) "" "normal" (substitute env "${X}"));
    ] )

let () =
  Alcotest.run "substitute"
    [ basic; mid_string; nested; edges; deferred; stringify; cache_fallback ]
