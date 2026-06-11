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

(* 7. Assignment with a value list. *)
let test_assign =
  Alcotest.test_case "assign := value list" `Quick (fun () ->
    match (parse "FOO := 'a', 'b'").stmts with
    | [ { node = C.S_assign { cache = false; name = "FOO";
                              values = [ C.A_string "a"; C.A_string "b" ];
                              parent_scope = false; _ }; _ } ] -> ()
    | other ->
      Alcotest.failf "unexpected: %s"
        (Sexp.to_string ([%sexp_of: C.stmt list] other)))

(* 7b. cache assignment with docstring + ~type:STRING (regression: the
   `:STRING` colon-keyword form, found by the main.yc smoke). *)
let test_cache_assign =
  Alcotest.test_case "cache := with ~type:STRING" `Quick (fun () ->
    match (parse "cache FMT_DEBUG_POSTFIX := 'd' 'Debug postfix.' ~type:STRING").stmts with
    | [ { node = C.S_assign
            { cache = true; name = "FMT_DEBUG_POSTFIX";
              values = [ C.A_string "d" ];
              docstring = Some "Debug postfix.";
              kwargs = [ ("type", C.A_name "STRING") ]; _ }; _ } ] -> ()
    | other ->
      Alcotest.failf "unexpected: %s"
        (Sexp.to_string ([%sexp_of: C.stmt list] other)))

(* 8. if with a compound condition + then block. *)
let test_if_cond =
  Alcotest.test_case "if str_eq..and defined.. then" `Quick (fun () ->
    match (parse "if str_eq 'a' 'b' and defined X then ( break )").stmts with
    | [ { node = C.S_if
            { cond = C.C_and (C.C_app ("str_eq", [ C.A_string "a"; C.A_string "b" ]),
                              C.C_app ("defined", [ C.A_name "X" ]));
              then_ = [ { node = C.S_flow C.Break; _ } ];
              else_ = None }; _ } ] -> ()
    | other ->
      Alcotest.failf "unexpected: %s"
        (Sexp.to_string ([%sexp_of: C.stmt list] other)))

(* 9. let ... in, foreach LISTS, function — the control forms parse. *)
let test_control_forms =
  Alcotest.test_case "let / foreach / function" `Quick (fun () ->
    (match (parse "let x = 'v' in message x").stmts with
     | [ { node = C.S_let { var = "x"; value = C.A_string "v"; _ }; _ } ] -> ()
     | o -> Alcotest.failf "let: %s" (Sexp.to_string ([%sexp_of: C.stmt list] o)));
    (match (parse "foreach a in LISTS ARGN ( break )").stmts with
     | [ { node = C.S_foreach { var = "a"; iter = C.F_lists [ "ARGN" ]; _ }; _ } ] -> ()
     | o -> Alcotest.failf "foreach: %s" (Sexp.to_string ([%sexp_of: C.stmt list] o)));
    match (parse "fun join(r) ( break )").stmts with
    | [ { node = C.S_function { name = "join"; params = [ "r" ]; _ }; _ } ] -> ()
    | o -> Alcotest.failf "fun: %s" (Sexp.to_string ([%sexp_of: C.stmt list] o)))

(* 10. A representative multi-construct program (mirrors main.yc's head)
   parses end to end: commands, nested if/cond, blocks, assignment,
   function + foreach, and a comment. *)
let test_representative =
  Alcotest.test_case "representative program parses" `Quick (fun () ->
    let src =
      "cmake_minimum_required VERSION \"3.8...3.28\";\n\
       include_guard GLOBAL;\n\
       # bump policy on old cmake\n\
       if ver_lt ${CMAKE_VERSION} \"3.12\" then (\n\
      \  policy_set CMP0074 NEW\n\
       );\n\
       if not (defined FMT_MASTER_PROJECT) then (\n\
      \  FMT_MASTER_PROJECT := \"OFF\";\n\
      \  message \"CMake version: ${CMAKE_VERSION}\"\n\
       );\n\
       fun join(result_var) (\n\
      \  result := \"\";\n\
      \  foreach arg in LISTS ARGN ( break )\n\
       )"
    in
    match P.parse src with
    | Ok p ->
      Alcotest.(check int) "5 top-level statements" 5 (List.length p.stmts);
      Alcotest.(check int) "1 comment captured" 1 (List.length p.comments)
    | Error e -> Alcotest.failf "representative program failed: %s" e)

let () =
  Alcotest.run "yc_cst_parse"
    [ "slice",
      [ test_command; test_comment_sidelist; test_kwargs;
        test_block; test_multi; test_span ];
      "constructs",
      [ test_assign; test_cache_assign; test_if_cond; test_control_forms;
        test_representative ] ]
