(* Phase 1 parity tests: direct-text emit vs. AST-emit-then-pp.

   Each test runs a small Yelu1 program through both pipelines:
     A. Yelu_tiny_cmake_emit.emit_script         (direct text)
     B. Yelu_tiny_cmake_emit_ast.emit_script     (AST then lang_cmake_pp)

   Phase 1.1 is a *skeleton* — only a handful of constructors are wired.
   These tests cover what's wired; coverage expands in Phase 1.3.

   Exact byte equality is not the bar — pp_to_string and direct emit
   make different formatting choices (e.g. trailing whitespace, line
   breaking). The tests instead check substring-level invariants that
   both paths must satisfy. Once parity coverage is broad enough we
   can pick lang_cmake_pp's output as canonical and tighten. *)

open Base
open Yelu_langs.Yelu_tiny

module E = Yelu_langs.Yelu_tiny_cmake_emit
module A = Yelu_langs.Yelu_tiny_cmake_emit_ast

let both prog =
  E.emit_script prog, A.emit_script prog

let contains s ~substring = String.is_substring s ~substring

let parity =
  ( "emit_ast parity",
    [
      Alcotest.test_case "set(VAR value) — both paths emit the command"
        `Quick (fun () ->
          let prog = ESetVar ("FOO", EString "hello") in
          let direct, ast = both prog in
          Alcotest.(check bool) "direct contains set(FOO ..."
            true (contains direct ~substring:"set(FOO");
          Alcotest.(check bool) "ast contains set(FOO ..."
            true (contains ast ~substring:"set(FOO");
          Alcotest.(check bool) "direct contains hello"
            true (contains direct ~substring:"hello");
          Alcotest.(check bool) "ast contains hello"
            true (contains ast ~substring:"hello"));

      Alcotest.test_case "unset(VAR) — both paths emit the command"
        `Quick (fun () ->
          let prog = Yelu_langs.Yelu_surface_cmake_store.ECmakeUnsetVar "FOO" in
          let direct, ast = both prog in
          Alcotest.(check bool) "direct" true (contains direct ~substring:"unset(FOO");
          Alcotest.(check bool) "ast"    true (contains ast    ~substring:"unset(FOO"));

      Alcotest.test_case "message(STATUS \"hi\") — both paths emit"
        `Quick (fun () ->
          let prog =
            Yelu_langs.Yelu_surface_cmake_cmake_op.ECmakeMessage
              { mode = "STATUS"; texts = [ EString "hi" ] }
          in
          let direct, ast = both prog in
          Alcotest.(check bool) "direct STATUS" true (contains direct ~substring:"STATUS");
          Alcotest.(check bool) "ast STATUS"    true (contains ast    ~substring:"STATUS");
          Alcotest.(check bool) "direct hi"     true (contains direct ~substring:"hi");
          Alcotest.(check bool) "ast hi"        true (contains ast    ~substring:"hi"));

      Alcotest.test_case "cmake_minimum_required — both paths emit version"
        `Quick (fun () ->
          let prog =
            Yelu_langs.Yelu_surface_cmake_cmake_op.ECmakeMinimumRequired "3.20"
          in
          let direct, ast = both prog in
          Alcotest.(check bool) "direct" true (contains direct ~substring:"cmake_minimum_required");
          Alcotest.(check bool) "ast"    true (contains ast    ~substring:"cmake_minimum_required");
          Alcotest.(check bool) "direct version" true (contains direct ~substring:"3.20");
          Alcotest.(check bool) "ast version"    true (contains ast    ~substring:"3.20"));

      Alcotest.test_case "ELet substitution survives AST path"
        `Quick (fun () ->
          let prog =
            ELet { var = "msg"; value = EString "hello";
                   body = ESetVar ("OUT", EVar "msg") }
          in
          let _direct, ast = both prog in
          Alcotest.(check bool) "ast: substituted hello present"
            true (contains ast ~substring:"hello");
          Alcotest.(check bool) "ast: ${msg} not present"
            false (contains ast ~substring:"${msg}"));

      Alcotest.test_case "if(COND) then body — AST emits if/endif"
        `Quick (fun () ->
          let prog =
            Yelu_langs.Yelu_surface_cmake_if.ECmakeIfStmt
              { cond = EBool true;
                then_ = ESetVar ("X", EString "y");
                else_ = None }
          in
          let _direct, ast = both prog in
          (* cmake_pp renders "if (TRUE)" with a space; direct emit uses
             "if(TRUE)". When parity coverage tightens, lang_cmake_pp's
             form wins. *)
          Alcotest.(check bool) "ast contains TRUE"
            true (contains ast ~substring:"TRUE");
          Alcotest.(check bool) "ast contains if header"
            true (contains ast ~substring:"if " || contains ast ~substring:"if(");
          Alcotest.(check bool) "ast contains endif"
            true (contains ast ~substring:"endif"));
    ] )

let () = Alcotest.run "yelu_tiny_emit_ast" [ parity ]
