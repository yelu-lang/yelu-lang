open Base
open Yelu_langs.Yelu_tiny
let let_emit_resolve =
  ( "let_emit_resolve",
    [
      Alcotest.test_case "ELet substitutes EVar in ESetVar value position"
        `Quick
        (fun () ->
          let prog =
            ELet { var = "msg";
                   value = EString "hello";
                   body = ESetVar ("OUT", EVar "msg") }
          in
          let cmake_text =
            Yelu_langs.Yelu_tiny_cmake_emit.emit_script prog
          in
          Alcotest.(check bool)
            "emits substituted literal, not ${msg}"
            true
            (String.is_substring cmake_text ~substring:"set(OUT \"hello\")");
          Alcotest.(check bool)
            "no remaining ${msg} reference"
            false
            (String.is_substring cmake_text ~substring:"${msg}"));
      Alcotest.test_case "ELet drops the let header from emit"
        `Quick
        (fun () ->
          let prog =
            ELet { var = "msg";
                   value = EString "hello";
                   body = EUnit }
          in
          let cmake_text =
            Yelu_langs.Yelu_tiny_cmake_emit.emit_script prog
          in
          (* let header has no cmake equivalent; body is empty -> empty
             output (just the trailing newline). *)
          Alcotest.(check string) "empty body emits empty script"
            "\n" cmake_text);
      Alcotest.test_case "Inner ELet shadows outer in emit substitution"
        `Quick
        (fun () ->
          let prog =
            ELet { var = "x";
                   value = EString "outer";
                   body =
                     ESeq
                       [ ESetVar ("BEFORE", EVar "x");
                         ELet { var = "x";
                                value = EString "inner";
                                body = ESetVar ("INSIDE", EVar "x") };
                         ESetVar ("AFTER", EVar "x");
                       ] }
          in
          let cmake_text =
            Yelu_langs.Yelu_tiny_cmake_emit.emit_script prog
          in
          Alcotest.(check bool) "BEFORE sees outer"
            true (String.is_substring cmake_text ~substring:"set(BEFORE \"outer\")");
          Alcotest.(check bool) "INSIDE sees inner"
            true (String.is_substring cmake_text ~substring:"set(INSIDE \"inner\")");
          Alcotest.(check bool) "AFTER restored to outer"
            true (String.is_substring cmake_text ~substring:"set(AFTER \"outer\")"));
    ] )

let () =
  Alcotest.run "yelu_tiny_emit" [ let_emit_resolve ]
