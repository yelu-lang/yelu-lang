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

let () =
  Alcotest.run "yc_cst_bridge" [ "bridge", List.map corpus ~f:bridge ]
