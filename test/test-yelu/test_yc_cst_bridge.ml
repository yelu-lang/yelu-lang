(* Emit-bridge oracle (M1.2): the CST path must be behavior-identical to
   the proven text→expr parser, measured at the emitted cmake text —
   emit(lower(parse_cst s)) == emit(parse_ast s). Reuses the byte-equality
   emit oracle rather than structural expr equality (extensible variant).
   See doc/lang/surface_status.md. *)

open Base
module Parse = Yelu_langs.Yelu_parse
module Cstp = Yelu_langs.Yc_cst_parse
module Lower = Yelu_langs.Yc_cst_lower
module Emit = Yelu_langs.Yelu_cmake_emit

let emit_ast src =
  match Parse.parse_program_y1 src with
  | Ok e -> Emit.emit_script e
  | Error e -> Alcotest.failf "ast-parse %S: %s" src e

let emit_cst src =
  match Cstp.parse src with
  | Ok p -> Emit.emit_script (Lower.lower_program p)
  | Error e -> Alcotest.failf "cst-parse %S: %s" src e

let bridge src =
  Alcotest.test_case src `Quick (fun () ->
    Alcotest.(check string) "emit(lower cst) == emit(ast)"
      (emit_ast src) (emit_cst src))

(* print round-trip + idempotence: printing the CST, re-parsing, and
   re-emitting must reproduce the original emit; printing is idempotent. *)
let roundtrip src =
  Alcotest.test_case src `Quick (fun () ->
    match Cstp.parse src with
    | Error e -> Alcotest.failf "cst-parse %S: %s" src e
    | Ok c1 ->
      let printed = Yelu_langs.Yc_cst_print.print_program c1 in
      (match Cstp.parse printed with
       | Error e -> Alcotest.failf "reparse of printed %S failed: %s\n%s" src e printed
       | Ok c2 ->
         Alcotest.(check string) "emit after round-trip == emit(ast)"
           (emit_ast src)
           (Emit.emit_script (Lower.lower_program c2));
         Alcotest.(check string) "print idempotent"
           printed (Yelu_langs.Yc_cst_print.print_program c2)))

let corpus =
  [ (* commands across families *)
    "policy_set CMP0074 NEW";
    "message \"hello\"";
    "cmake_minimum_required VERSION \"3.8\"";
    "include_guard GLOBAL";
    "set FOO \"a\" \"b\"";
    "string_concat 'a' 'b' ~out:OUT";
    "string_toupper 'abc' ~out:U";
    "list_append XS 'a' 'b'";
    "path_get_filename ${P} ~out:F";
    "add_subdirectory \"test\"";
    (* assignment forms *)
    "FOO := \"a\", \"b\"";
    "FOO := \"x\" PARENT_SCOPE";
    "option USE_X \"help text\" ON";
    "cache FMT_DEBUG_POSTFIX := \"d\" \"Debug postfix.\" ~type:STRING";
    (* control flow + conditions *)
    "if ver_lt ${CMAKE_VERSION} \"3.12\" then ( policy_set CMP0074 NEW )";
    "if not (defined X) then ( message \"y\" )";
    "if str_eq 'a' 'b' and defined Y then ( message \"z\" )";
    "while lt ${i} \"5\" ( message \"loop\" )";
    "foreach a in LISTS ARGN ( message \"i\" )";
    "foreach n in RANGE 0 .. 3 ( message \"r\" )";
    "fun join(result_var) ( result := \"\" )";
    (* generic / unknown *)
    "some_unknown_cmd \"a\" \"b\"";
  ]

(* Comment placement: the formatter preserves `#` comments and places them
   by source span — leading, between, inside-block (correct indent), and
   trailing — and is idempotent + comment-count-preserving across a
   re-parse. *)
let test_comment_placement =
  Alcotest.test_case "comment placement + preservation" `Quick (fun () ->
    let src =
      "# leading\nmessage 'a';\n# between\nif defined X then (\n# inside\n\
       message 'b'\n);\nmessage 'c'\n# trailing" in
    let fmt s =
      match Cstp.parse s with
      | Ok c -> Yelu_langs.Yc_cst_print.print_program c
      | Error e -> Alcotest.failf "parse %S: %s" s e
    in
    let out = fmt src in
    let expected =
      "# leading\nmessage 'a';\n# between\nif defined X then (\n  # inside\n\
      \  message 'b'\n);\nmessage 'c'\n# trailing\n" in
    Alcotest.(check string) "placement" expected out;
    (* idempotent + comments survive re-parse *)
    Alcotest.(check string) "idempotent" out (fmt out);
    (match Cstp.parse out with
     | Ok c -> Alcotest.(check int) "4 comments preserved" 4 (List.length c.comments)
     | Error e -> Alcotest.failf "reparse: %s" e))

(* `$foo` brace-elision sugar: the formatter canonicalizes `${ident}` to the
   lighter `$ident` in value AND name/target slots, while string-internal
   `${…}` and genex keep braces. Input `$foo` and `${foo}` are equivalent. *)
let test_brace_elision =
  Alcotest.test_case "brace-elision canonicalization" `Quick (fun () ->
    let fmt s =
      match Cstp.parse s with
      | Ok c -> Yelu_langs.Yc_cst_print.print_program c
      | Error e -> Alcotest.failf "parse %S: %s" s e
    in
    (* value slot: ${X} → $X; already-bare $X stays *)
    Alcotest.(check string) "value ${X}→$X" "Y := $X\n" (fmt "Y := ${X}");
    Alcotest.(check string) "value $X stays"  "Y := $X\n" (fmt "Y := $X");
    (* name slot (assignment LHS) elides too *)
    Alcotest.(check string) "name ${v}→$v" "$v := $w\n" (fmt "${v} := ${w}");
    (* string-internal ${…} keeps braces (verbatim to cmake); quote
       canonicalizes "…" → '…' since the content has no single quote *)
    Alcotest.(check string) "in-string keeps braces"
      "P := 'a${X}b'\n" (fmt "P := \"a${X}b\"");
    (* idempotent *)
    Alcotest.(check string) "idempotent" "Y := $X\n" (fmt (fmt "Y := ${X}")))

(* Enum constructor (visibility): the legacy `:PRIVATE` colon-keyword
   canonicalizes to the leading-cap `Private`; the bare `Public` form already
   reads that way; the `~public:` kwarg key is untouched (lowercase). *)
let test_enum_constructor =
  Alcotest.test_case "enum constructor canonicalization" `Quick (fun () ->
    let fmt s =
      match Cstp.parse s with
      | Ok c -> Yelu_langs.Yc_cst_print.print_program c
      | Error e -> Alcotest.failf "parse %S: %s" s e
    in
    Alcotest.(check string) ":PRIVATE → Private"
      "compile_opts fmt Private $flags\n" (fmt "compile_opts fmt :PRIVATE $flags");
    Alcotest.(check string) "Public stays Public"
      "compile_opts fmt Public $x\n" (fmt "compile_opts fmt Public $x");
    (* the ~public kwarg key is a lowercase identifier, not the enum; the
       separator canonicalizes to `=` (the `:` form is still accepted) *)
    Alcotest.(check string) "~public key untouched, `:`→`=`"
      "compile_feats fmt ~public=[ cxx_std_11 ]\n"
      (fmt "compile_feats fmt ~public:[cxx_std_11]");
    (* slice 2: enum VALUES inside ~type/~mode canonicalize, key kept; the
       separator is `=`. A `:Constructor`-cased input emits unchanged. *)
    Alcotest.(check string) "~type:STRING value → ~type=String"
      "cache X := 'v' ~type=String\n" (fmt "cache X := 'v' ~type:STRING");
    Alcotest.(check string) "~mode value, input already leading-cap"
      "get_filename_component p ~mode=Name_we $src\n"
      (fmt "get_filename_component p ~mode:Name_we $src"))

(* `~`-half flags slice: the cmake `PARENT_SCOPE` flag canonicalizes to
   `~parent_scope`; the `~parent_scope` form is accepted and stable. Emit is
   unchanged (both → cmake `PARENT_SCOPE`), proven by the matrix. *)
let test_flags =
  Alcotest.test_case "flag canonicalization (~parent_scope)" `Quick (fun () ->
    let fmt s =
      match Cstp.parse s with
      | Ok c -> Yelu_langs.Yc_cst_print.print_program c
      | Error e -> Alcotest.failf "parse %S: %s" s e
    in
    Alcotest.(check string) "PARENT_SCOPE → ~parent_scope"
      "X := 1 ~parent_scope\n" (fmt "X := 1 PARENT_SCOPE");
    Alcotest.(check string) "~parent_scope stable"
      "X := 1 ~parent_scope\n" (fmt "X := 1 ~parent_scope");
    (* include_guard GLOBAL → ~global (per-command, command-aware: only the
       include_guard flag, not a generic ${GLOBAL} var) *)
    Alcotest.(check string) "include_guard GLOBAL → ~global"
      "include_guard ~global\n" (fmt "include_guard GLOBAL");
    Alcotest.(check string) "include_guard ~global stable"
      "include_guard ~global\n" (fmt "include_guard ~global");
    (* a bare GLOBAL in another command is NOT a flag — left as-is *)
    Alcotest.(check string) "GLOBAL elsewhere untouched"
      "some_cmd GLOBAL\n" (fmt "some_cmd GLOBAL");
    (* install_directory OPTIONAL → ~optional (detected via kwarg in the
       parser, since OPTIONAL is otherwise positional) *)
    Alcotest.(check string) "install_directory OPTIONAL → ~optional"
      "install_directory 'd' ~destination='x' ~optional\n"
      (fmt "install_directory 'd' DESTINATION 'x' OPTIONAL");
    Alcotest.(check string) "install_directory ~optional stable"
      "install_directory 'd' ~destination='x' ~optional\n"
      (fmt "install_directory 'd' ~destination='x' ~optional");
    (* the parser change must keep emit identical: positional OPTIONAL and the
       ~optional flag lower to the same cmake (the kwarg sets ~optional:true) *)
    Alcotest.(check string) "OPTIONAL / ~optional emit identically"
      (emit_ast "install_directory 'd' DESTINATION 'x' OPTIONAL")
      (emit_ast "install_directory 'd' DESTINATION 'x' ~optional");
    (* find_package REQUIRED → ~required (positional flag; parser reads kwarg) *)
    Alcotest.(check string) "find_package REQUIRED → ~required"
      "find_package Foo ~required\n" (fmt "find_package Foo REQUIRED");
    Alcotest.(check string) "find_package ~required stable"
      "find_package Foo ~required\n" (fmt "find_package Foo ~required");
    Alcotest.(check string) "REQUIRED / ~required emit identically"
      (emit_ast "find_package Foo REQUIRED")
      (emit_ast "find_package Foo ~required"))

(* `~key:value` and `~key=value` are both accepted; the formatter
   canonicalizes the separator to `=` (critique #2). *)
let test_separator =
  Alcotest.test_case "kwarg separator `:`/`=` → `=`" `Quick (fun () ->
    let fmt s =
      match Cstp.parse s with
      | Ok c -> Yelu_langs.Yc_cst_print.print_program c
      | Error e -> Alcotest.failf "parse %S: %s" s e
    in
    Alcotest.(check string) "`:` value → `=`"
      "string_toupper 'a' ~out=U\n" (fmt "string_toupper 'a' ~out:U");
    Alcotest.(check string) "`=` value accepted + stable"
      "string_toupper 'a' ~out=U\n" (fmt "string_toupper 'a' ~out=U");
    Alcotest.(check string) "`:` list → `=`"
      "compile_feats fmt ~public=[ a b ]\n" (fmt "compile_feats fmt ~public:[a b]");
    Alcotest.(check string) "`=` list accepted"
      "compile_feats fmt ~public=[ a b ]\n" (fmt "compile_feats fmt ~public=[a b]"))

(* Value-labels (critique #2): the value-carrying cmake keywords
   DESTINATION/COMPONENT canonicalize to `~destination=`/`~component=` for
   install_directory, and the parser reads them back identically. *)
let test_value_labels =
  Alcotest.test_case "value-labels (install_directory)" `Quick (fun () ->
    let fmt s =
      match Cstp.parse s with
      | Ok c -> Yelu_langs.Yc_cst_print.print_program c
      | Error e -> Alcotest.failf "parse %S: %s" s e
    in
    Alcotest.(check string) "DESTINATION/COMPONENT → labels"
      "install_directory 'd' ~destination='x' ~component='c'\n"
      (fmt "install_directory 'd' DESTINATION 'x' COMPONENT 'c'");
    Alcotest.(check string) "label form stable"
      "install_directory 'd' ~destination='x' ~component='c'\n"
      (fmt "install_directory 'd' ~destination='x' ~component='c'");
    (* parser change must keep emit identical (keyword vs label) *)
    Alcotest.(check string) "keyword / label emit identically"
      (emit_ast "install_directory 'd' DESTINATION 'x' COMPONENT 'c'")
      (emit_ast "install_directory 'd' ~destination='x' ~component='c'");
    (* order-independence: labels in any order emit the same cmake (cmake's
       positional-keyword ordering pain, compiled away) *)
    Alcotest.(check string) "label order-independent on emit"
      (emit_ast "install_directory 'd' ~destination='x' ~component='c'")
      (emit_ast "install_directory 'd' ~component='c' ~destination='x'");
    (* install_files: DESTINATION/COMPONENT *)
    Alcotest.(check string) "install_files → labels"
      "install_files $f ~destination='x' ~component='c'\n"
      (fmt "install_files $f DESTINATION 'x' COMPONENT 'c'");
    Alcotest.(check string) "install_files keyword/label emit identically"
      (emit_ast "install_files $f DESTINATION 'x' COMPONENT 'c'")
      (emit_ast "install_files $f ~destination='x' ~component='c'");
    (* install_export: DESTINATION/FILE/NAMESPACE/COMPONENT *)
    Alcotest.(check string) "install_export → labels"
      "install_export $e ~destination='x' ~namespace='ns::' ~component='c'\n"
      (fmt "install_export $e DESTINATION 'x' NAMESPACE 'ns::' COMPONENT 'c'");
    Alcotest.(check string) "install_export keyword/label emit identically"
      (emit_ast "install_export $e DESTINATION 'x' FILE 'f.cmake' NAMESPACE 'ns::'")
      (emit_ast "install_export $e ~destination='x' ~file='f.cmake' ~namespace='ns::'"))

let () =
  Alcotest.run "yc_cst_bridge"
    [ "bridge", List.map corpus ~f:bridge;
      "roundtrip", List.map corpus ~f:roundtrip;
      "comments", [ test_comment_placement ];
      "elision", [ test_brace_elision ];
      "enum", [ test_enum_constructor ];
      "separator", [ test_separator ];
      "value_labels", [ test_value_labels ];
      "flags", [ test_flags ] ]
