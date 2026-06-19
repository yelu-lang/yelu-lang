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
      "compile_feats fmt ~public=[cxx_std_11]\n"
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
    (* a bare GLOBAL in another command is NOT the include_guard flag, but it
       IS a known enum constructor (Pos3 entity slice — GLOBAL/SOURCE/CACHE/
       INSTALL/TEST/DIRECTORY are leading-cap canonicalized like Public/Static).
       So the `~global` flag canonicalization correctly does NOT fire; the
       leading-cap canonicalization does. *)
    Alcotest.(check string) "GLOBAL elsewhere: not the flag, IS a constructor"
      "some_cmd Global\n" (fmt "some_cmd GLOBAL");
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
      (emit_ast "find_package Foo ~required");
    (* set_property:
       - APPEND / APPEND_STRING → ~append / ~append_string (Lane B flags)
       - PROPERTY name vals → ~property=[name, vals...] (Lane C value-list label,
         the multi-value shape — cmake's PROPERTY introduces a (name, vals...)
         pair; the leading list element plays the "key" role until the shape-3
         record literal lands)
       Both directions: byte-identical cmake emit. *)
    let canon_target =
      "set_property foo ~append ~property=[LINK_LIBRARIES, 'bar']\n" in
    Alcotest.(check string) "set_property TARGET: positional → canon"
      canon_target
      (fmt "set_property foo APPEND PROPERTY LINK_LIBRARIES 'bar'");
    Alcotest.(check string) "set_property TARGET canon stable"
      canon_target
      (fmt "set_property foo ~append ~property=[LINK_LIBRARIES, 'bar']");
    Alcotest.(check string) "set_property TARGET: positional / canon emit identically"
      (emit_ast "set_property foo APPEND PROPERTY LINK_LIBRARIES 'bar'")
      (emit_ast "set_property foo ~append ~property=[LINK_LIBRARIES, 'bar']");
    let canon_source =
      "set_property Source 'main.c' ~append ~property=[COMPILE_FLAGS, '-Wall']\n" in
    Alcotest.(check string) "set_property SOURCE → Source: positional → canon"
      canon_source
      (fmt "set_property SOURCE 'main.c' APPEND PROPERTY COMPILE_FLAGS '-Wall'");
    Alcotest.(check string) "set_property SOURCE: positional / canon emit identically"
      (emit_ast "set_property SOURCE 'main.c' APPEND PROPERTY COMPILE_FLAGS '-Wall'")
      (emit_ast canon_source);
    (* set_property CACHE — the entry name now flows through emit (cache_entry
       was a placeholder Cache_entry singleton that dropped names; lifted to
       string list 2026-06-13). Verify canon round-trip and that the entry
       name + all three STRINGS values survive to cmake. *)
    let canon_cache =
      "set_property Cache FOO ~append ~property=[STRINGS, 'a', 'b', 'c']\n" in
    Alcotest.(check string) "set_property CACHE → Cache: positional → canon"
      canon_cache
      (fmt "set_property CACHE FOO APPEND PROPERTY STRINGS 'a' 'b' 'c'");
    Alcotest.(check string) "set_property Cache canon stable"
      canon_cache
      (fmt "set_property Cache FOO ~append ~property=[STRINGS, 'a', 'b', 'c']");
    Alcotest.(check string) "set_property CACHE: positional / canon emit identically"
      (emit_ast "set_property CACHE FOO APPEND PROPERTY STRINGS 'a' 'b' 'c'")
      (emit_ast canon_cache);
    Alcotest.(check bool) "set_property CACHE keeps the entry name on emit"
      true
      (* the entry name is a LITERAL (cmake derefs ${} — a bare `FOO` is the
         entry name, not a var). Earlier this asserted the derefed `CACHE
         ${FOO}`, which was the regression that broke the matrix. *)
      (String.is_substring
         ~substring:"CACHE FOO"
         (emit_ast "set_property CACHE FOO APPEND PROPERTY STRINGS 'a' 'b' 'c'"));
    Alcotest.(check bool) "set_property CACHE multi-value list survives emit"
      true
      (String.is_substring
         ~substring:"STRINGS a;b;c"
         (emit_ast canon_cache));
    (* APPEND_STRING — second flag, independent of APPEND. *)
    let canon_aps =
      "set_property foo ~append_string ~property=[COMPILE_FLAGS, '-Wall']\n" in
    Alcotest.(check string) "set_property APPEND_STRING: positional → canon"
      canon_aps
      (fmt "set_property foo APPEND_STRING PROPERTY COMPILE_FLAGS '-Wall'");
    Alcotest.(check string) "set_property APPEND_STRING: positional / canon emit identically"
      (emit_ast "set_property foo APPEND_STRING PROPERTY COMPILE_FLAGS '-Wall'")
      (emit_ast canon_aps);
    Alcotest.(check string) "set_property: both flags + value-list preserved"
      "set_property foo ~append ~append_string ~property=[COMPILE_FLAGS, '-Wall']\n"
      (fmt "set_property foo APPEND APPEND_STRING PROPERTY COMPILE_FLAGS '-Wall'");
    (* Pos3 entity surface — scope discriminators (`Source`, `Cache`, `Global`,
       `Test`, `Install`) canonicalize to leading-cap and parse as first-class
       kinded entities via [p_cmake_entity]. Previously GLOBAL/TEST/INSTALL
       scopes fell back to yc_raw; Pos3 routes them through the unified
       ECmakeSetProperty IR (one ctor, scope sum). *)
    Alcotest.(check string) "Pos3: SOURCE → Source (leading-cap)"
      "set_property Source 'main.c' ~property=[COMPILE_FLAGS, '-Wall']\n"
      (fmt "set_property SOURCE 'main.c' PROPERTY COMPILE_FLAGS '-Wall'");
    Alcotest.(check string) "Pos3: CACHE → Cache (leading-cap)"
      "set_property Cache FOO ~property=[STRINGS, 'a', 'b']\n"
      (fmt "set_property CACHE FOO PROPERTY STRINGS 'a' 'b'");
    Alcotest.(check string) "Pos3 stable: Cache FOO round-trips"
      "set_property Cache FOO ~property=[STRINGS, 'a', 'b']\n"
      (fmt "set_property Cache FOO ~property=[STRINGS, 'a', 'b']");
    (* GLOBAL scope: previously yc_raw fallback, now typed via Pos3 *)
    Alcotest.(check string) "Pos3: Global scope (newly typed)"
      "set_property Global ~property=[USE_FOLDERS, ON]\n"
      (fmt "set_property Global PROPERTY USE_FOLDERS ON");
    Alcotest.(check string) "Pos3: Global emits set_property(GLOBAL ...)"
      "set_property(GLOBAL PROPERTY USE_FOLDERS ON)"
      (emit_ast "set_property Global PROPERTY USE_FOLDERS ON");
    (* TEST scope: previously yc_raw, now typed *)
    Alcotest.(check string) "Pos3: Test scope (newly typed)"
      "set_property Test 'mytest' ~property=[ENVIRONMENT, 'V=1']\n"
      (fmt "set_property TEST 'mytest' PROPERTY ENVIRONMENT 'V=1'");
    Alcotest.(check string) "Pos3: Test emits set_property(TEST ...)"
      "set_property(TEST mytest PROPERTY ENVIRONMENT V=1)"
      (emit_ast "set_property Test 'mytest' PROPERTY ENVIRONMENT 'V=1'");
    (* INSTALL scope: previously yc_raw, now typed *)
    Alcotest.(check string) "Pos3: Install scope (newly typed)"
      "set_property Install 'lib.so' ~property=[CPACK_NEVER, 'TRUE']\n"
      (fmt "set_property INSTALL 'lib.so' PROPERTY CPACK_NEVER 'TRUE'");
    Alcotest.(check string) "Pos3: Install emits set_property(INSTALL ...)"
      "set_property(INSTALL lib.so PROPERTY CPACK_NEVER TRUE)"
      (emit_ast "set_property Install 'lib.so' PROPERTY CPACK_NEVER 'TRUE'");
    (* get_property — unified Pos3 dispatch parallel to set_property. The 4-way
       legacy shape collapsed 2026-06-14: ECmakeGetProperty now carries
       { var; scope; property; mode } mirroring Lang_cmake.Get_property 1:1.
       VARIABLE scope is unique to get and now supported. Mode enum (Value,
       Set, Defined, Brief_docs, Full_docs) replaces the prior [set_form : bool]. *)
    Alcotest.(check string) "Pos3 get_property: Target scope, default mode"
      "get_property(myvar TARGET foo PROPERTY ALIASED_TARGET)"
      (emit_ast "get_property Target foo ~property=ALIASED_TARGET ~out=myvar");
    Alcotest.(check string) "Pos3 get_property: ~mode=Set"
      "get_property(myvar TARGET foo PROPERTY USE_FOLDERS SET)"
      (emit_ast "get_property Target foo ~property=USE_FOLDERS ~mode=Set ~out=myvar");
    Alcotest.(check string) "Pos3 get_property: ~mode=Defined"
      "get_property(myvar GLOBAL PROPERTY USE_FOLDERS DEFINED)"
      (emit_ast "get_property Global ~property=USE_FOLDERS ~mode=Defined ~out=myvar");
    Alcotest.(check string) "Pos3 get_property: Cache scope"
      "get_property(myvar CACHE FOO PROPERTY STRINGS)"
      (emit_ast "get_property Cache FOO ~property=STRINGS ~out=myvar");
    (* VARIABLE scope — unique to get_property, no payload (like Global). *)
    Alcotest.(check string) "Pos3 get_property: Variable scope (newly typed)"
      "get_property(myvar VARIABLE PROPERTY CMAKE_VERSION DEFINED)"
      (emit_ast "get_property Variable ~property=CMAKE_VERSION ~mode=Defined ~out=myvar");
    (* mode flag canonicalization on input: positional `DEFINED` → ~mode=Defined *)
    Alcotest.(check string) "Pos3 get_property: positional DEFINED → typed mode"
      "get_property(myvar GLOBAL PROPERTY USE_FOLDERS DEFINED)"
      (emit_ast "get_property Global PROPERTY USE_FOLDERS DEFINED ~out=myvar");
    (* fmt canonicalization: PROPERTY → ~property= (Lane C shape-1), scope
       keyword leading-cap'd, mode flag stays positional (mode-as-kwarg is a
       future micro-slice; the lexer at least canonicalizes DEFINED → Defined). *)
    Alcotest.(check string) "Pos3 get_property: fmt canonicalizes positional form"
      "get_property Cache FOO ~property=STRINGS Defined ~out=myvar\n"
      (fmt "get_property CACHE FOO PROPERTY STRINGS DEFINED ~out=myvar");
    (* `:=` low-priority command-call sugar (2026-06-14). When the RHS of
       `:=` starts with a known command name + command-shape tokens, parse
       the rest as a full command and inject `~out=lhs` so any command with
       ~out semantics becomes assignable. fmt round-trips back to the
       `:=` form. *)
    Alcotest.(check string) "`:=` command-call: get_property → cmake"
      "get_property(myvar TARGET foo PROPERTY NAME)"
      (emit_ast "myvar := get_property Target foo ~property=NAME");
    Alcotest.(check string) "`:=` command-call: fmt round-trips"
      "myvar := get_property target foo ~property=NAME\n"
      (fmt "myvar := get_property Target foo ~property=NAME");
    Alcotest.(check string) "`:=` command-call: Cache scope"
      "get_property(myvar CACHE FOO PROPERTY STRINGS)"
      (emit_ast "myvar := get_property Cache FOO ~property=STRINGS");
    (* Works for multi-family — string_/list_/path_/etc. all have ~out
       semantics and become assignable via the same mechanism. *)
    Alcotest.(check string) "`:=` command-call: string_toupper"
      "string(TOUPPER hello upper)"
      (emit_ast "upper := string_toupper 'hello'");
    (* `var := bare_value` keeps the legacy value-list path (no command shape
       signal — no extra positional, no TILDE). *)
    Alcotest.(check string) "`:=` bare value stays value-assignment"
      "var := 'hello'\n"
      (fmt "var := \"hello\""))

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
      "compile_feats fmt ~public=[a, b]\n" (fmt "compile_feats fmt ~public:[a b]");
    Alcotest.(check string) "`=` list accepted"
      "compile_feats fmt ~public=[a, b]\n" (fmt "compile_feats fmt ~public=[a b]"))

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
      (emit_ast "install_export $e ~destination='x' ~file='f.cmake' ~namespace='ns::'");
    (* dotted label key `~library.destination=` (shape-4 foundation): parses
       and round-trips through the generic kwarg printer *)
    Alcotest.(check string) "dotted kwarg key round-trips"
      "some_cmd $t ~library.destination='x'\n"
      (fmt "some_cmd $t ~library.destination='x'"))

(* install_targets shape-4: the nested per-artifact-kind clauses parse
   correctly (two-level split), and the positional and dotted-label forms
   emit identical, correct cmake. Real `cmake --install` confirmed the
   clause shape installs each artifact to its per-kind destination. *)
let test_install_targets =
  Alcotest.test_case "install_targets nested clauses" `Quick (fun () ->
    let positional =
      "install_targets $t COMPONENT 'c' EXPORT $e \
       LIBRARY DESTINATION 'lib' ARCHIVE DESTINATION 'ar'" in
    let dotted =
      "install_targets $t ~component='c' ~export=$e \
       ~library.destination='lib' ~archive.destination='ar'" in
    let expected =
      "install(TARGETS ${t} EXPORT ${e} COMPONENT c \
       LIBRARY DESTINATION lib ARCHIVE DESTINATION ar)" in
    Alcotest.(check string) "positional emits all clauses + COMPONENT"
      expected (emit_ast positional);
    Alcotest.(check string) "dotted-label form emits identically"
      expected (emit_ast dotted);
    (* formatter: a clean positional line canonicalizes to the dotted labels,
       and fmt is emit-invariant (parser reads both forms to the same IR) *)
    let fmt s =
      match Cstp.parse s with
      | Ok c -> Yelu_langs.Yc_cst_print.print_program c
      | Error e -> Alcotest.failf "parse %S: %s" s e in
    Alcotest.(check string) "fmt canonicalizes clean line → dotted labels"
      "install_targets $t ~component='c' ~export=$e \
       ~library.destination='lib' ~archive.destination='ar'\n"
      (fmt positional);
    Alcotest.(check string) "fmt emit-invariant (clean line)"
      (emit_ast positional) (emit_ast (fmt positional));
    (* guard: a trailing positional after the clauses (e.g. a dynamic FILE_SET
       clause held in a var) is NOT representable as dotted labels — the dotted
       (kwarg) form loses the post-clause position. Such a line is left
       positional so fmt stays emit-invariant. *)
    let with_trailing = "install_targets $t LIBRARY DESTINATION 'lib' $fileset" in
    Alcotest.(check bool) "trailing positional → left positional (no ~label)"
      false (String.is_substring (fmt with_trailing) ~substring:"~library");
    Alcotest.(check string) "fmt emit-invariant (trailing-positional line)"
      (emit_ast with_trailing) (emit_ast (fmt with_trailing)))

(* execute_process: a mix of a keyword-terminated value-list (COMMAND), value
   labels (OUTPUT_VARIABLE, …) and flags (OUTPUT_QUIET, …). The COMMAND list
   stops at the next keyword; a piped multi-COMMAND can't be encoded (flat
   kwargs merge the groups) so it is left positional. *)
let test_execute_process =
  Alcotest.test_case "execute_process value-labels + COMMAND list" `Quick (fun () ->
    let fmt s =
      match Cstp.parse s with
      | Ok c -> Yelu_langs.Yc_cst_print.print_program c
      | Error e -> Alcotest.failf "parse %S: %s" s e in
    (* COMMAND list terminates at OUTPUT_VARIABLE; both forms emit identically *)
    let pos = "execute_process COMMAND $prog '--version' OUTPUT_VARIABLE NINJA_VERSION" in
    Alcotest.(check string) "COMMAND list + ~output_variable"
      "execute_process ~command=[$prog, '--version'] ~output_variable=NINJA_VERSION\n"
      (fmt pos);
    Alcotest.(check string) "fmt emit-invariant"
      (emit_ast pos) (emit_ast (fmt pos));
    (* flag (OUTPUT_QUIET) + a scalar value-label *)
    Alcotest.(check string) "flag + value-label"
      "execute_process ~command=[$p] ~working_directory='/tmp' ~output_quiet\n"
      (fmt "execute_process COMMAND $p WORKING_DIRECTORY '/tmp' OUTPUT_QUIET");
    (* multi-COMMAND (pipe) → plural ~commands=[[…], […]] (shape-2); the
       nested lists carry the per-COMMAND grouping, so emit is unchanged *)
    let piped = "execute_process COMMAND $a 'x' COMMAND $b 'y' OUTPUT_VARIABLE o" in
    Alcotest.(check string) "piped multi-COMMAND → ~commands plural"
      "execute_process ~commands=[[$a, 'x'], [$b, 'y']] ~output_variable=o\n"
      (fmt piped);
    Alcotest.(check string) "fmt emit-invariant (multi-COMMAND)"
      (emit_ast piped) (emit_ast (fmt piped)))

(* Recursive value grammar (shapes 2 & 3 core): nested lists `[[…], […]]`
   and records `{k=v, …}` parse and round-trip at the CST level (no command is
   wired to consume them yet — that's the per-command phases). Space/comma both
   accepted; canonical output is comma. *)
let test_value_grammar =
  Alcotest.test_case "recursive value grammar (list/record core)" `Quick (fun () ->
    let fmt s =
      match Cstp.parse s with
      | Ok c -> Yelu_langs.Yc_cst_print.print_program c
      | Error e -> Alcotest.failf "parse %S: %s" s e in
    Alcotest.(check string) "nested list canonicalizes (space → comma)"
      "somecmd ~commands=[[a, b], [c, d]]\n"
      (fmt "somecmd ~commands=[[a b] [c d]]");
    Alcotest.(check string) "nested list idempotent"
      "somecmd ~commands=[[a, b], [c, d]]\n"
      (fmt "somecmd ~commands=[[a, b], [c, d]]");
    Alcotest.(check string) "record with a nested list value"
      "somecmd ~properties={version='1.0', sources=[a, b]}\n"
      (fmt "somecmd ~properties={version='1.0', sources=[a, b]}");
    Alcotest.(check string) "record accepts `:` separator, canonicalizes to `=`"
      "somecmd ~properties={version='1.0'}\n"
      (fmt "somecmd ~properties={version:'1.0'}"))

(* shape-3 record: set_target_properties PROPERTY name v… → ~properties={…}.
   A multi-value property becomes a list value; positional and record forms
   emit identically (each property → its own set_target_properties call). *)
let test_set_target_properties =
  Alcotest.test_case "set_target_properties record (shape 3)" `Quick (fun () ->
    let fmt s =
      match Cstp.parse s with
      | Ok c -> Yelu_langs.Yc_cst_print.print_program c
      | Error e -> Alcotest.failf "parse %S: %s" s e in
    let pos =
      "set_target_properties $t PROPERTY VERSION $V PROPERTY SOURCES a b" in
    Alcotest.(check string) "PROPERTY triples → ~properties record"
      "set_target_properties $t ~properties={version=$V, sources=[a, b]}\n"
      (fmt pos);
    Alcotest.(check string) "fmt emit-invariant"
      (emit_ast pos) (emit_ast (fmt pos));
    Alcotest.(check string) "record form stable"
      "set_target_properties $t ~properties={version=$V, sources=[a, b]}\n"
      (fmt "set_target_properties $t ~properties={version=$V, sources=[a, b]}"))

let () =
  Alcotest.run "yc_cst_bridge"
    [ "bridge", List.map corpus ~f:bridge;
      "install_targets", [ test_install_targets ];
      "execute_process", [ test_execute_process ];
      "set_target_properties", [ test_set_target_properties ];
      "value_grammar", [ test_value_grammar ];
      "roundtrip", List.map corpus ~f:roundtrip;
      "comments", [ test_comment_placement ];
      "elision", [ test_brace_elision ];
      "enum", [ test_enum_constructor ];
      "separator", [ test_separator ];
      "value_labels", [ test_value_labels ];
      "flags", [ test_flags ] ]
