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
    "cmake_minimum_required \"3.8\"";
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
    (* include_guard is not Step-2-rejected; fmt is pass-through (no positional→
       ~flag codemod). A bare GLOBAL canonicalizes to the `Global` enum
       constructor (lexer), and the `~global` flag form stays — both parse to
       Ig_global. *)
    Alcotest.(check string) "include_guard GLOBAL → Global (enum canon, no codemod)"
      "include_guard Global\n" (fmt "include_guard GLOBAL");
    Alcotest.(check string) "include_guard ~global stable"
      "include_guard ~global\n" (fmt "include_guard ~global");
    (* a bare GLOBAL in another command is NOT the include_guard flag, but it
       IS a known enum constructor (Pos3 entity slice — GLOBAL/SOURCE/CACHE/
       INSTALL/TEST/DIRECTORY are leading-cap canonicalized like Public/Static).
       So the `~global` flag canonicalization correctly does NOT fire; the
       leading-cap canonicalization does. *)
    Alcotest.(check string) "GLOBAL elsewhere: not the flag, IS a constructor"
      "some_cmd Global\n" (fmt "some_cmd GLOBAL");
    (* install_directory ~optional — labeled-only (Step 2): the positional
       OPTIONAL/DESTINATION form is rejected (see test_yc_wellform); the labeled
       flag round-trips and emits the cmake OPTIONAL. *)
    Alcotest.(check string) "install_directory ~optional stable"
      "install_directory 'd' ~destination='x' ~optional\n"
      (fmt "install_directory 'd' ~destination='x' ~optional");
    Alcotest.(check string) "install_directory ~optional emit-invariant"
      (emit_ast "install_directory 'd' ~destination='x' ~optional")
      (emit_ast (fmt "install_directory 'd' ~destination='x' ~optional"));
    (* find_package is not Step-2-rejected: positional REQUIRED is still good
       code and fmt is pass-through (no ~required codemod). The ~required kwarg
       is also accepted by the parser; both emit the same cmake. *)
    Alcotest.(check string) "find_package REQUIRED pass-through"
      "find_package Foo REQUIRED\n" (fmt "find_package Foo REQUIRED");
    Alcotest.(check string) "find_package ~required stable"
      "find_package Foo ~required\n" (fmt "find_package Foo ~required");
    Alcotest.(check string) "REQUIRED / ~required emit identically"
      (emit_ast "find_package Foo REQUIRED")
      (emit_ast "find_package Foo ~required");
    (* set_property — labeled-only (Step 2): APPEND/APPEND_STRING → ~append/
       ~append_string flags; PROPERTY name vals → ~property=[name, vals…] value
       list. The positional cmake-keyword form is rejected (see
       test_yc_wellform). The entity scope (Target/Source/Cache/Global/Test/
       Install) stays positional — it is the enum-constructor surface. *)
    let canon_target =
      "set_property foo ~append ~property=[LINK_LIBRARIES, 'bar']\n" in
    Alcotest.(check string) "set_property TARGET canon stable"
      canon_target
      (fmt "set_property foo ~append ~property=[LINK_LIBRARIES, 'bar']");
    let canon_source =
      "set_property Source 'main.c' ~append ~property=[COMPILE_FLAGS, '-Wall']\n" in
    Alcotest.(check string) "set_property Source canon stable"
      canon_source
      (fmt canon_source);
    (* set_property CACHE — the entry name flows through emit (a bare `FOO` is
       the entry name literal, not a var; the derefed `CACHE ${FOO}` was the
       regression that broke the matrix). Entry name + all three STRINGS values
       survive to cmake. *)
    let canon_cache =
      "set_property Cache FOO ~append ~property=[STRINGS, 'a', 'b', 'c']\n" in
    Alcotest.(check string) "set_property Cache canon stable"
      canon_cache
      (fmt canon_cache);
    Alcotest.(check bool) "set_property CACHE keeps the entry name on emit"
      true
      (String.is_substring ~substring:"CACHE FOO" (emit_ast canon_cache));
    Alcotest.(check bool) "set_property CACHE multi-value list survives emit"
      true
      (String.is_substring ~substring:"STRINGS a;b;c" (emit_ast canon_cache));
    (* APPEND_STRING — second flag, independent of APPEND. *)
    let canon_aps =
      "set_property foo ~append_string ~property=[COMPILE_FLAGS, '-Wall']\n" in
    Alcotest.(check string) "set_property ~append_string stable"
      canon_aps
      (fmt canon_aps);
    Alcotest.(check string) "set_property: both flags + value-list preserved"
      "set_property foo ~append ~append_string ~property=[COMPILE_FLAGS, '-Wall']\n"
      (fmt "set_property foo ~append ~append_string ~property=[COMPILE_FLAGS, '-Wall']");
    (* Pos3 entity surface — scope discriminators (`Source`, `Cache`, `Global`,
       `Test`, `Install`) are first-class kinded entities via [p_cmake_entity],
       routed through the unified ECmakeSetProperty IR (one ctor, scope sum). *)
    Alcotest.(check string) "Pos3: Global emits set_property(GLOBAL ...)"
      "set_property(GLOBAL PROPERTY USE_FOLDERS ON)"
      (emit_ast "set_property Global ~property=[USE_FOLDERS, ON]");
    Alcotest.(check string) "Pos3: Test emits set_property(TEST ...)"
      "set_property(TEST mytest PROPERTY ENVIRONMENT V=1)"
      (emit_ast "set_property Test 'mytest' ~property=[ENVIRONMENT, 'V=1']");
    Alcotest.(check string) "Pos3: Install emits set_property(INSTALL ...)"
      "set_property(INSTALL lib.so PROPERTY CPACK_NEVER TRUE)"
      (emit_ast "set_property Install 'lib.so' ~property=[CPACK_NEVER, 'TRUE']");
    (* get_property — unified Pos3 dispatch parallel to set_property:
       { var; scope; property; mode } mirroring Lang_cmake.Get_property 1:1.
       VARIABLE scope is unique to get; mode via ~mode=Value/Set/Defined/…. *)
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

(* Value-labels (critique #2) — labeled-only (Step 2): the value-carrying cmake
   keywords are expressed as `~destination=`/`~component=`/… labels; the
   positional cmake-keyword form is rejected (see test_yc_wellform). The labels
   round-trip and are order-independent on emit. *)
let test_value_labels =
  Alcotest.test_case "value-labels (install_directory)" `Quick (fun () ->
    let fmt s =
      match Cstp.parse s with
      | Ok c -> Yelu_langs.Yc_cst_print.print_program c
      | Error e -> Alcotest.failf "parse %S: %s" s e
    in
    Alcotest.(check string) "label form stable"
      "install_directory 'd' ~destination='x' ~component='c'\n"
      (fmt "install_directory 'd' ~destination='x' ~component='c'");
    (* order-independence: labels in any order emit the same cmake (cmake's
       positional-keyword ordering pain, compiled away) *)
    Alcotest.(check string) "label order-independent on emit"
      (emit_ast "install_directory 'd' ~destination='x' ~component='c'")
      (emit_ast "install_directory 'd' ~component='c' ~destination='x'");
    (* install_files: ~destination/~component *)
    Alcotest.(check string) "install_files labels stable"
      "install_files $f ~destination='x' ~component='c'\n"
      (fmt "install_files $f ~destination='x' ~component='c'");
    (* install_export: ~destination/~file/~namespace/~component *)
    Alcotest.(check string) "install_export labels stable"
      "install_export $e ~destination='x' ~namespace='ns::' ~component='c'\n"
      (fmt "install_export $e ~destination='x' ~namespace='ns::' ~component='c'");
    (* dotted label key `~library.destination=` (shape-4 foundation): parses
       and round-trips through the generic kwarg printer *)
    Alcotest.(check string) "dotted kwarg key round-trips"
      "some_cmd $t ~library.destination='x'\n"
      (fmt "some_cmd $t ~library.destination='x'"))

(* install_targets — labeled-only (Step 2). The dotted-label form lowers to the
   nested per-artifact-kind clauses + top-level options; fmt round-trips it. The
   positional cmake-keyword form is REJECTED (a wellform fatal — exercised in
   test_yc_wellform), so it has no place here. *)
let test_install_targets =
  Alcotest.test_case "install_targets dotted labels" `Quick (fun () ->
    let dotted =
      "install_targets $t ~component='c' ~export=$e \
       ~library.destination='lib' ~archive.destination='ar'" in
    Alcotest.(check string) "dotted labels emit the nested clauses"
      "install(TARGETS ${t} EXPORT ${e} COMPONENT c \
       LIBRARY DESTINATION lib ARCHIVE DESTINATION ar)"
      (emit_ast dotted);
    let fmt s =
      match Cstp.parse s with
      | Ok c -> Yelu_langs.Yc_cst_print.print_program c
      | Error e -> Alcotest.failf "parse %S: %s" s e in
    Alcotest.(check string) "fmt round-trips the labeled form"
      (dotted ^ "\n") (fmt dotted);
    Alcotest.(check string) "fmt emit-invariant"
      (emit_ast dotted) (emit_ast (fmt dotted)))

(* execute_process — labeled-only (Step 2): the COMMAND value-list is
   ~command=[…] (single) or ~commands=[[…],[…]] (piped, shape-2); value labels
   (~output_variable, ~working_directory, …) and flags (~output_quiet, …) read
   from kwargs. The positional cmake-keyword form is rejected (see
   test_yc_wellform). *)
let test_execute_process =
  Alcotest.test_case "execute_process value-labels + COMMAND list" `Quick (fun () ->
    let fmt s =
      match Cstp.parse s with
      | Ok c -> Yelu_langs.Yc_cst_print.print_program c
      | Error e -> Alcotest.failf "parse %S: %s" s e in
    let single = "execute_process ~command=[$prog, '--version'] ~output_variable=NINJA_VERSION" in
    Alcotest.(check string) "~command list + ~output_variable round-trip"
      (single ^ "\n") (fmt single);
    Alcotest.(check string) "fmt emit-invariant"
      (emit_ast single) (emit_ast (fmt single));
    (* flag (~output_quiet) + a scalar value-label *)
    let flagged = "execute_process ~command=[$p] ~working_directory='/tmp' ~output_quiet" in
    Alcotest.(check string) "flag + value-label round-trip"
      (flagged ^ "\n") (fmt flagged);
    (* piped multi-COMMAND → plural ~commands=[[…],[…]] (shape-2) *)
    let piped = "execute_process ~commands=[[$a, 'x'], [$b, 'y']] ~output_variable=o" in
    Alcotest.(check string) "~commands plural round-trip"
      (piped ^ "\n") (fmt piped);
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

(* shape-3 record: set_target_properties ~properties={…} — labeled-only
   (Step 2). A multi-value property becomes a list value; each property emits
   its own set_target_properties call. The positional PROPERTY/PROPERTIES form
   is rejected (see test_yc_wellform). *)
let test_set_target_properties =
  Alcotest.test_case "set_target_properties record (shape 3)" `Quick (fun () ->
    let fmt s =
      match Cstp.parse s with
      | Ok c -> Yelu_langs.Yc_cst_print.print_program c
      | Error e -> Alcotest.failf "parse %S: %s" s e in
    let rec_ = "set_target_properties $t ~properties={version=$V, sources=[a, b]}" in
    Alcotest.(check string) "record form stable"
      (rec_ ^ "\n") (fmt rec_);
    Alcotest.(check string) "record emit-invariant"
      (emit_ast rec_) (emit_ast (fmt rec_));
    (* Honest emit (2026-06): a *bare* target name is a literal, NOT a deref.
       `fmt` → `fmt` (the target), not `${fmt}` (a variable read). A real
       variable holding a name is written `$t` → `${t}`. *)
    Alcotest.(check string) "bare target name emits literal (not ${})"
      "set_target_properties(fmt PROPERTIES VERSION 1)"
      (emit_ast "set_target_properties fmt ~properties={version='1'}");
    Alcotest.(check string) "$-var target name still derefs"
      "set_target_properties(${t} PROPERTIES VERSION 1)"
      (emit_ast "set_target_properties $t ~properties={version='1'}"))

(* add_custom_command / add_custom_target — labeled-only (Step 2). OUTPUT/
   DEPENDS/SOURCES → ~output/~depends/~sources value-lists; COMMAND →
   ~command/~commands; COMMENT → scalar; VERBATIM/COMMAND_EXPAND_LISTS/ALL →
   flags. COMMAND_EXPAND_LISTS survives emit (the IR gap fixed in 591f261).
   The positional cmake-keyword form is rejected (see test_yc_wellform). *)
let test_add_custom =
  Alcotest.test_case "add_custom_command / add_custom_target" `Quick (fun () ->
    let fmt s =
      match Cstp.parse s with
      | Ok c -> Yelu_langs.Yc_cst_print.print_program c
      | Error e -> Alcotest.failf "parse %S: %s" s e in
    let acc =
      "add_custom_command ~output=[$o] ~command=[$cc, '-c'] \
       ~command_expand_lists ~depends=[$s]" in
    Alcotest.(check string) "add_custom_command labels round-trip"
      (acc ^ "\n") (fmt acc);
    Alcotest.(check string) "add_custom_command emit-invariant (COMMAND_EXPAND_LISTS kept)"
      (emit_ast acc) (emit_ast (fmt acc));
    let act = "add_custom_target doc ~all ~command=[$cc, 'build'] ~sources=[$srcs]" in
    Alcotest.(check string) "add_custom_target labels round-trip"
      (act ^ "\n") (fmt act);
    Alcotest.(check string) "add_custom_target emit-invariant"
      (emit_ast act) (emit_ast (fmt act)))

let () =
  Alcotest.run "yc_cst_bridge"
    [ "bridge", List.map corpus ~f:bridge;
      "install_targets", [ test_install_targets ];
      "execute_process", [ test_execute_process ];
      "set_target_properties", [ test_set_target_properties ];
      "add_custom", [ test_add_custom ];
      "value_grammar", [ test_value_grammar ];
      "roundtrip", List.map corpus ~f:roundtrip;
      "comments", [ test_comment_placement ];
      "elision", [ test_brace_elision ];
      "enum", [ test_enum_constructor ];
      "separator", [ test_separator ];
      "value_labels", [ test_value_labels ];
      "flags", [ test_flags ] ]
