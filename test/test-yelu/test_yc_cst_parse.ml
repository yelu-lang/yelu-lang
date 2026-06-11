(* Tests for the yc CST parser (M1.1, first slice): atoms, the uniform
   command, kwargs, flow, blocks, and the program-level comment side-list.
   See doc/lang/surface_status.md. *)

open Base
module C = Yelu_langs.Yc_cst
module P = Yelu_langs.Yc_cst_parse

let parse s =
  match P.parse s with
  | Ok p -> p
  | Error e -> Alcotest.failf "parse %S failed: %s" s e

(* 1. A uniform command with positional name args. *)
let test_command =
  Alcotest.test_case "uniform command" `Quick (fun () ->
    match (parse "policy_set CMP0074 NEW").stmts with
    | [ { node = C.S_command { name = "policy_set";
                               args = [ C.Pos (C.A_name "CMP0074");
                                        C.Pos (C.A_name "NEW") ] }; _ } ] -> ()
    | other ->
      Alcotest.failf "unexpected: %s"
        (Sexp.to_string ([%sexp_of: C.stmt list] other)))

(* 2. A leading comment lands in the program-level side list, not the stmt. *)
let test_comment_sidelist =
  Alcotest.test_case "comment in side list" `Quick (fun () ->
    let p = parse "# adopt\nmessage 'hi'" in
    (match p.comments with
     | [ { text = " adopt"; _ } ] -> ()
     | other ->
       Alcotest.failf "comments: %s"
         (Sexp.to_string ([%sexp_of: C.comment list] other)));
    match p.stmts with
    | [ { node = C.S_command { name = "message";
                               args = [ C.Pos (C.A_string "hi") ] }; _ } ] -> ()
    | other ->
      Alcotest.failf "stmts: %s"
        (Sexp.to_string ([%sexp_of: C.stmt list] other)))

(* 3. Keyword args: ~out:OUT becomes a Kw arg. *)
let test_kwargs =
  Alcotest.test_case "kwargs" `Quick (fun () ->
    match (parse "string_concat 'a' 'b' ~out:OUT").stmts with
    | [ { node = C.S_command
            { name = "string_concat";
              args = [ C.Pos (C.A_string "a"); C.Pos (C.A_string "b");
                       C.Kw ("out", C.A_name "OUT") ] }; _ } ] -> ()
    | other ->
      Alcotest.failf "unexpected: %s"
        (Sexp.to_string ([%sexp_of: C.stmt list] other)))

(* 4. A block groups statements; flow keyword inside. *)
let test_block =
  Alcotest.test_case "block + flow" `Quick (fun () ->
    match (parse "( message 'y'; break )").stmts with
    | [ { node = C.S_block
            [ { node = C.S_command { name = "message"; _ }; _ };
              { node = C.S_flow C.Break; _ } ]; _ } ] -> ()
    | other ->
      Alcotest.failf "unexpected: %s"
        (Sexp.to_string ([%sexp_of: C.stmt list] other)))

(* 5. Several top-level statements split on ';'. *)
let test_multi =
  Alcotest.test_case "multiple statements" `Quick (fun () ->
    let p = parse "message 'a'; message 'b'; message 'c'" in
    Alcotest.(check int) "3 stmts" 3 (List.length p.stmts))

(* 6. A statement span slices a plausible source range. *)
let test_span =
  Alcotest.test_case "stmt span within source" `Quick (fun () ->
    let src = "message 'hi'" in
    match (parse src).stmts with
    | [ { span = { lo; hi }; _ } ] ->
      Alcotest.(check bool) "covers source" true
        (lo = 0 && hi = String.length src)
    | _ -> Alcotest.fail "expected one stmt")

let () =
  Alcotest.run "yc_cst_parse"
    [ "slice",
      [ test_command; test_comment_sidelist; test_kwargs;
        test_block; test_multi; test_span ] ]
