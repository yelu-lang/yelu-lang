open Base
open Yelu_langs.Lang_yelu_cmake
open Yelu_langs.Lang_yelu_parse

let parse input =
  match parse_program input with
  | Ok stmt -> stmt
  | Error e -> Alcotest.failf "Parse error: %s" e

(* R6 — glue parser tests through the tiny bridge. The smoke check is
   "bridge accepts the parser's output, emit_ast produces text without
   raising".

   As of the post-Phase-1 coverage expansion (commit TBD), the parser
   exercises emit_ast directly with no fallback to direct emit. The
   parser-only gaps that surfaced earlier (ECmakeSetCache, find_library
   family, dir-level commands, property scopes, export / package
   config, etc.) are now wired through emit_ast as well as the byte
   oracle's 194 programs.

   Stronger semantic equivalence (parse → bridge → emit → cmake-run →
   match) would need per-test expected outputs that don't exist
   here. *)
let parse_bridge_skip : string list = [
]

let do_bridge name =
  not (Base.List.mem parse_bridge_skip name ~equal:Base.String.equal)

let assert_bridge_ok name stmt =
  if do_bridge name then
    match Yelu_langs.Yelu_cmake_to_yelu1.stmt stmt with
    | exception Yelu_langs.Yelu_cmake_to_yelu1.Bridge_error msg ->
      Alcotest.failf "%s: tiny bridge raised: %s" name msg
    | yelu1 ->
      (try
         let (_ : string) = Yelu_langs.Yelu_tiny_cmake_emit_ast.emit_script yelu1 in
         ()
       with Yelu_langs.Yelu_tiny.Eval_error msg ->
         Alcotest.failf "%s: emit_ast raised: %s" name msg)

let assert_parses name input =
  Alcotest.test_case name `Quick (fun () ->
    let stmt = parse input in
    assert_bridge_ok name stmt)

(* Phase 2a pair-wise oracle: for inputs the new Yelu1 parser accepts,
   assert that both paths produce byte-identical cmake text.

   - legacy path: source → Lang_yelu_parse.parse_program
                          → Yelu_cmake_to_yelu1.stmt
                          → Yelu_tiny_cmake_emit_ast.emit_script
   - new path:    source → Yelu_parse_y1.parse_program_y1
                          → Yelu_tiny_cmake_emit_ast.emit_script

   Same emit_ast lowering on both sides, so any divergence is parser-
   level. The new parser currently handles only the var family
   (Phase 2a pilot); other inputs return Error and the oracle skips. *)
let assert_parse_y1_equiv name source =
  Alcotest.test_case name `Quick (fun () ->
    let legacy_text =
      let stmt = parse source in
      let yelu1 = Yelu_langs.Yelu_cmake_to_yelu1.stmt stmt in
      Yelu_langs.Yelu_tiny_cmake_emit_ast.emit_script yelu1
    in
    match Yelu_langs.Yelu_parse_y1.parse_program_y1 source with
    | Error msg ->
      Alcotest.failf "%s: new parser failed: %s" name msg
    | Ok new_yelu1 ->
      let new_text =
        Yelu_langs.Yelu_tiny_cmake_emit_ast.emit_script new_yelu1
      in
      Alcotest.(check string) "legacy parse == new parse via emit_ast"
        legacy_text new_text)

let assert_list_get_indices name input expected_indices =
  Alcotest.test_case name `Quick (fun () ->
    match parse input with
    | Ys_list (Ylist_get { indices; _ }) ->
      Alcotest.(check (list int)) "indices" expected_indices indices
    | _ -> Alcotest.fail "expected list_get statement")

let assert_path_normal_out name input expected_out =
  Alcotest.test_case name `Quick (fun () ->
    match parse input with
    | Ys_path (Ypath_normal_path { out = Some { name; _ }; _ }) ->
      Alcotest.(check string) "out" expected_out name
    | Ys_path (Ypath_normal_path { out = None; _ }) ->
      Alcotest.fail "expected path_normal_path output variable"
    | _ -> Alcotest.fail "expected path_normal_path statement")

let assert_target_sources name input expected_groups =
  Alcotest.test_case name `Quick (fun () ->
    match parse input with
    | Ys_target (Ytgt_sources { items; _ }) ->
      let groups =
        List.map items ~f:(fun { kind; items } ->
          let kind =
            match kind with
            | Private -> "PRIVATE"
            | Public -> "PUBLIC"
            | Interface -> "INTERFACE"
            | Plain -> "PLAIN"
          in
          let sources =
            List.map items ~f:(function
              | Yexpr_string (Ycs_string source | Ycs_path source) -> source
              | _ -> "?")
          in
          kind, sources)
      in
      Alcotest.(check (list (pair string (list string)))) "source groups" expected_groups groups
    | _ -> Alcotest.fail "expected target_sources statement")

let assert_target_link_libraries name input expected_groups =
  Alcotest.test_case name `Quick (fun () ->
    match parse input with
    | Ys_target (Ytgt_link_libraries { items; _ }) ->
      let groups =
        List.map items ~f:(fun { kind; items } ->
          let kind =
            match kind with
            | Private -> "PRIVATE"
            | Public -> "PUBLIC"
            | Interface -> "INTERFACE"
            | Plain -> "PLAIN"
          in
          let libraries =
            List.map items ~f:(function
              | Yexpr_string (Ycs_string library | Ycs_path library) -> library
              | _ -> "?")
          in
          kind, libraries)
      in
      Alcotest.(check (list (pair string (list string)))) "library groups" expected_groups groups
    | _ -> Alcotest.fail "expected target_link_libraries statement")

let assert_target_include_directories name input expected_groups =
  Alcotest.test_case name `Quick (fun () ->
    match parse input with
    | Ys_target (Ytgt_include_directories { items; _ }) ->
      let groups =
        List.map items ~f:(fun { kind; items } ->
          let kind =
            match kind with
            | Private -> "PRIVATE"
            | Public -> "PUBLIC"
            | Interface -> "INTERFACE"
            | Plain -> "PLAIN"
          in
          let dirs =
            List.map items ~f:(function
              | Yexpr_string (Ycs_string dir | Ycs_path dir) -> dir
              | _ -> "?")
          in
          kind, dirs)
      in
      Alcotest.(check (list (pair string (list string)))) "include dir groups" expected_groups groups
    | _ -> Alcotest.fail "expected target_include_directories statement")

(* ============================================================
   Tier 0 — Core (control side, cond, var, cmake_op, target,
            dir, file, test, find — partial)
   ============================================================ *)

let tier0_control = ("t0-control", [
  assert_parses "empty block" "( )";
  assert_parses "let binding" "let x = Target Foo in ( )";
  assert_parses "let with type annotation" "let tut : target = Target Tutorial in ( )";
])

let tier0_cond = ("t0-cond", [
  assert_parses "if then (defined)" "( if defined 'TEST' then ( message 'defined' ) )";
  assert_parses "if simple (ON)" "( if ON then ( message 'yes' ) )";
  assert_parses "if with else (defined)" "( if defined 'TEST' then ( message 'yes' ) else ( ) )";
  assert_parses "if target" "( if target Target Foo then ( ) )";
  assert_parses "if target with else" "( if target Target Foo then ( message 'found' ) else ( message 'not found' ) )";
  assert_parses "cond not" "( if not ${FLAG} then ( message 'off' ) )";
  assert_parses "cond str_eq" "( if str_eq ${X} 'hello' then ( ) )";
  assert_parses "cond and/or" "( if ${A} and ${B} then ( ) )";
  assert_parses "cond match" "( if match ${X} 'pat.*' then ( ) )";
  assert_parses "cond exists" "( if exists \"file.txt\" then ( ) )";
  assert_parses "cond is_dir" "( if is_dir \"path\" then ( ) )";
  assert_parses "cond ver_lt" "( if ver_lt ${CMAKE_VERSION} \"3.20\" then ( ) )";
  assert_parses "cond list_in" "( if list_in ${X} ${MYLIST} then ( ) )";
  assert_parses "cond policy" "( if policy CMP0048 then ( ) )";
  assert_parses "cond eq" "( if eq ${X} 42 then ( ) )";
])

let tier0_var = ("t0-var", [
  assert_parses "assignment :=" "( CMAKE_CXX_STANDARD := \"11\" )";
  assert_parses "set command (legacy)" "( set 'CMAKE_CXX_STANDARD' \"11\" )";
  assert_parses "cache var :=" "( cache BUILD_SHARED_LIBS := ON ; 'Build shared libs' )";
  assert_parses "var multi-value :=" "( FLAGS := \"-Wall\", \"-Wextra\" )";
])

let tier0_cmake_op = ("t0-cmake_op", [
  assert_parses "cmake_minimum_required" "( cmake_minimum_required \"3.20\" )";
  assert_parses "project" "( project \"Tutorial\" )";
])

let tier0_target = ("t0-target", [
  assert_parses "add_exe" "( add_exe Target Foo )";
  assert_parses "add_lib" "( add_lib Target MathFunctions )";
  assert_parses "link_lib" "( link_lib Target Tutorial )";
  assert_target_link_libraries "link_lib scoped items"
    "( link_lib Target Tutorial PRIVATE \"m\" PUBLIC \"dep\" )"
    [ "PRIVATE", [ "m" ]; "PUBLIC", [ "dep" ] ];
  assert_parses "include_dirs" "( include_dirs Target Tutorial )";
  assert_target_include_directories "include_dirs scoped items"
    "( include_dirs Target Tutorial PRIVATE \"include\" INTERFACE \"iface\" )"
    [ "PRIVATE", [ "include" ]; "INTERFACE", [ "iface" ] ];
  assert_parses "compile_defs" "( compile_defs Target Tutorial )";
  assert_parses "compile_opts" "( compile_opts Target Tutorial )";
])

let tier0_dir = ("t0-dir", [
  assert_parses "add_subdirectory" "( add_subdirectory \"MathFunctions\" )";
])

let tier0_file = ("t0-file", [
  assert_parses "configure_file" "( configure_file \"input.h.in\" \"output.h\" )";
])

let tier0_scripting = ("t0-scripting", [
  assert_parses "foreach in list" "( foreach item in [\"a\" \"b\" \"c\"] ( message \"${item}\" ) )";
  assert_parses "foreach range" "( foreach i in RANGE 1..10 ( message \"${i}\" ) )";
  assert_parses "fun empty body" "( fun f() ( ) )";
  assert_parses "fun with body" "( fun f() ( message 'hi' ) )";
  assert_parses "fun args" "( fun f(x) ( message 'hi' ) )";
  assert_parses "labeled arg ~msg:" "( option 'ENABLE_FOO' ON ~msg:'Enable foo' )";
  assert_parses "bare flag ~global" "( add_lib_imported Target Foo ~global )";
])

let tier0_full = ("t0-full", [
  assert_parses "full step1"
    "let tut = Target Tutorial in ( cmake_minimum_required \"3.20\"; project \"Tutorial\"; add_exe tut \"tutorial.cxx\" )";
])

(* ============================================================
   Tier 1 — target (complete the theory)
   ============================================================ *)

let tier1_target = ("t1-target", [
  assert_parses "compile_feats" "( compile_feats Target Tutorial ~public:[cxx_std_11] )";
  assert_parses "link_opts" "( link_opts Target Tutorial ~before ~private:[\"-pie\"] )";
  assert_parses "link_dirs" "( link_dirs Target Tutorial ~before ~private:[\"/opt/lib\"] )";
  assert_parses "precompile_headers" "( precompile_headers Target Tutorial ~private:[\"pch.h\"] )";
  assert_parses "add_lib_alias" "( add_lib_alias \"alias\" \"original\" )";
  assert_parses "add_exe_alias" "( add_exe_alias \"alias\" \"original\" )";
  assert_parses "add_custom_target" "( add_custom_target \"name\" )";
  assert_parses "add_dependencies" "( add_dependencies \"tgt\" \"dep\" )";
  assert_target_sources "target_sources"
    "( target_sources Target app PRIVATE \"extra.c\" PUBLIC \"api.c\" INTERFACE \"iface.h\" )"
    [ "PRIVATE", [ "extra.c" ]; "PUBLIC", [ "api.c" ]; "INTERFACE", [ "iface.h" ] ];
])

(* ============================================================
   Tier 2 — string
   ============================================================ *)

let tier2_string = ("t2-string", [
  assert_parses "concat" "( string_concat ~out:out_var 'a' 'b' )";
  assert_parses "join" "( string_join ';' ~out:out_var 'a' 'b' )";
  assert_parses "toupper" "( string_toupper 'hello' )";
  assert_parses "tolower" "( string_tolower 'HELLO' )";
  assert_parses "length" "( string_length 'hello' )";
  assert_parses "replace" "( string_replace 'old' 'new' 'input' )";
  assert_parses "regex_match" "( string_regex_match 'p.*' 'input' )";
  assert_parses "find" "( string_find 'sub' 'haystack' )";
  assert_parses "timestamp" "( string_timestamp )";
  assert_parses "hex" "( string_hex 'abc' )";
  assert_parses "make_c_identifier" "( string_make_c_identifier 'my var' )";
  assert_parses "toupper ~out" "( string_toupper 'hello' ~out:OUT )";
  assert_parses "toupper ~out first" "( string_toupper ~out:OUT 'hello' )";
  assert_parses "concat ~out only" "( string_concat ~out:OUT )";
  assert_parses "tolower ~out" "( string_tolower 'HELLO' ~out:OUT )";
  assert_parses "hex ~out" "( string_hex 'abc' ~out:OUT )";
  assert_parses "length ~out" "( string_length 'hello' ~out:OUT )";
])

(* Tier 3: list operations *)
let tier3_list = ("t3-list", [
  assert_parses "append" "( list_append MYLIST 'a' 'b' )";
  assert_parses "length" "( list_length MYLIST ~out:LEN )";
  assert_list_get_indices "get" "( list_get MYLIST 1 ~out:VAL )" [ 1 ];
  assert_parses "remove_item" "( list_remove_item MYLIST 'a' )";
  assert_parses "remove_duplicates" "( list_remove_duplicates MYLIST )";
  assert_parses "reverse" "( list_reverse MYLIST )";
  assert_parses "sort" "( list_sort MYLIST )";
  assert_parses "join" "( list_join MYLIST ';' ~out:RESULT )";
  assert_parses "find" "( list_find MYLIST 'needle' ~out:IDX )";
  assert_parses "prepend" "( list_prepend MYLIST 'first' )";
  assert_parses "insert" "( list_insert MYLIST )";
  assert_parses "remove_at" "( list_remove_at MYLIST )";
  assert_parses "pop_back" "( list_pop_back MYLIST )";
  assert_parses "pop_front" "( list_pop_front MYLIST )";
])

(* Tier 4: file operations *)
let tier4_file = ("t4-file", [
  assert_parses "read" "( file_read \"f.txt\" ~out:OUT )";
  assert_parses "write" "( file_write \"f.txt\" 'content' )";
  assert_parses "glob" "( file_glob ~out:OUT \"*.cxx\" )";
  assert_parses "copy" "( file_copy \"src\" \"dst\" )";
  assert_parses "rename" "( file_rename \"old\" \"new\" )";
  assert_parses "remove" "( file_remove \"f.txt\" )";
  assert_parses "real_path" "( file_real_path \"f.txt\" ~out:OUT )";
  assert_parses "size" "( file_size \"f.txt\" ~out:OUT )";
  assert_parses "timestamp" "( file_timestamp \"f.txt\" ~out:OUT )";
  assert_parses "make_directory" "( file_make_directory \"dir\" )";
  assert_parses "touch" "( file_touch \"f.txt\" )";
])

(* Tier 5: path operations *)
let tier5_path = ("t5-path", [
  assert_parses "get" "( path_get PV ~out:OUT )";
  assert_parses "has" "( path_has PV ~out:OUT )";
  assert_parses "is_absolute" "( path_is_absolute PV ~out:OUT )";
  assert_parses "is_relative" "( path_is_relative PV ~out:OUT )";
  assert_parses "set" "( path_set PV \"/tmp\" )";
  assert_parses "append" "( path_append PV \"sub\" )";
  assert_parses "compare" "( path_compare P1 P2 ~out:OUT )";
  assert_parses "hash" "( path_hash PV ~out:OUT )";
  assert_parses "get_filename_component" "( get_filename_component \"file.txt\" ~out:OUT )";
])

(* Tier 6: find & install *)
let tier6_find_install = ("t6-find-install", [
  assert_parses "find_library" "( find_library VAR ~names:\"m\" ~paths:\"/usr/lib\" )";
  assert_parses "find_path" "( find_path VAR ~names:\"foo.h\" )";
  assert_parses "find_program" "( find_program VAR ~names:\"git\" )";
  assert_parses "find_file" "( find_file VAR ~names:\"config\" )";
  assert_parses "install_targets" "( install_targets \"lib\" )";
  assert_parses "install_files" "( install_files \"include\" )";
  assert_parses "install_export" "( install_export EXP \"lib/cmake\" )";
])

(* Tier 7: scripting & control flow *)
let tier7_scripting = ("t7-scripting", [
  assert_parses "include" "( include \"file.cmake\" )";
  assert_parses "include optional" "( include \"file.cmake\" ~optional )";
  assert_parses "separate_arguments" "( separate_arguments VAR )";
  assert_parses "macro simple" "( macro name() ( ) )";
  assert_parses "macro with body" "( macro name(x, y) ( message 'hi' ) )";
  assert_parses "foreach_in" "( foreach x in a b ~items:[y, z] ( message 'hi' ) )";
  assert_parses "foreach_zip" "( foreach x, y in ~zip:[a, b] ( message 'hi' ) )";
  assert_parses "block" "( block ~scope:[x, y] ( message 'hi' ) )";
  assert_parses "extern cvar" "( extern 'VAR' )";
  assert_parses "extern target" "( extern Target Foo )";
])

(* Tier 8: dir, property, cmake_op, try *)
let tier8_misc = ("t8-misc", [
  assert_parses "include_directories" "( include_directories \"dir1\" \"dir2\" )";
  assert_parses "add_compile_options" "( add_compile_options \"-Wall\" \"-Wextra\" )";
  assert_parses "add_link_options" "( add_link_options \"-pie\" )";
  assert_parses "add_definitions" "( add_definitions \"-DFOO\" )";
  assert_parses "link_directories" "( link_directories \"/opt/lib\" )";
  assert_parses "get_target_property" "( get_target_property Target Foo ~out:VAR )";
  assert_parses "set_target_properties" "( set_target_properties Target Foo )";
  assert_parses "set_property" "( set_property Target Foo )";
  assert_parses "math" "( math '1+2' ~out:RESULT )";
  assert_parses "execute_process" "( execute_process )";
  assert_parses "include_guard" "( include_guard )";
  assert_parses "policy_set" "( policy_set \"CMP0048\" )";
  assert_parses "try_compile" "( try_compile RESULT )";
  assert_parses "try_run" "( try_run RUN_RES COMPILE_RES )";
  assert_parses "enable_language" "( enable_language )";
])

(* Remaining gaps filled *)
let tier_remaining = ("t-remaining", [
  assert_parses "string_regex_replace" "( string_regex_replace 'p' 'r' 'in' ~out:OUT )";
  assert_parses "string_regex_matchall" "( string_regex_matchall 'p' 'in' ~out:OUT )";
  assert_parses "string_append" "( string_append MYVAR 'suffix' )";
  assert_parses "string_prepend" "( string_prepend MYVAR 'prefix' )";
  assert_parses "string_substring" "( string_substring 'hello' '1' '3' ~out:OUT )";
  assert_parses "string_compare" "( string_compare 'a' 'b' ~out:OUT )";
  assert_parses "string_uuid" "( string_uuid ~out:OUT )";
  assert_parses "string_json_get" "( string_json_get '{\"a\":1}' ~out:OUT )";
  assert_parses "path_remove_filename" "( path_remove_filename PV )";
  assert_parses "path_replace_filename" "( path_replace_filename PV \"new\" )";
  assert_path_normal_out "path_normal_path" "( path_normal_path PV ~out:OUT )" "OUT";
  assert_parses "path_absolute_path" "( path_absolute_path PV )";
  assert_parses "path_native_path" "( path_native_path PV ~out:OUT )";
  assert_parses "path_convert_to_cmake" "( path_convert_to_cmake \"/tmp\" ~out:OUT )";
  assert_parses "get_directory_property" "( get_directory_property ~out:OUT )";
  assert_parses "set_global_property" "( set_global_property )";
  assert_parses "set_source_property" "( set_source_property \"file.c\" )";
  assert_parses "list_sublist" "( list_sublist MYLIST '1' '3' ~out:OUT )";
  assert_parses "list_filter" "( list_filter MYLIST 'pat' )";
  assert_parses "list_transform" "( list_transform MYLIST ~append )";
  assert_parses "unset_cache" "( unset_cache MYVAR )";
  assert_parses "set_env" "( set_env 'HOME' '/tmp' )";
  assert_parses "unset_env" "( unset_env 'TEMP' )";
  assert_parses "file_strings" "( file_strings \"f.txt\" ~out:OUT )";
  assert_parses "file_read_symlink" "( file_read_symlink \"link\" ~out:OUT )";
  assert_parses "cmake_call" "( cmake_call \"myfn\" )";
  assert_parses "cmake_get_log_level" "( cmake_get_log_level ~out:OUT )";
  assert_parses "export" "( export Target ExpName )";
  assert_parses "configure_package_config_file"
    "( configure_package_config_file \"dest\" \"in\" \"out\" )";
  assert_parses "write_basic_package_version_file"
    "( write_basic_package_version_file \"file\" )";
])

(* Tier 9: generator expressions *)
let tier9_genex = ("t9-genex", [
  assert_parses "$<CONFIG> in message" "( message $<CONFIG> )";
  assert_parses "$<TARGET_FILE> in message" "( message $<TARGET_FILE:tgt> )";
  assert_parses "nested genex in compile_opts"
    "( compile_opts Target Tutorial ~private:[$<IF:$<CONFIG:Debug>,debug,release>] )";
  assert_parses "$<TARGET_FILE> in message" "( message $<TARGET_FILE:tgt> )";
  assert_parses "${VAR} eval" "( message ${CMAKE_VERSION} )";
  assert_parses "$<BUILD_INTERFACE>" "( compile_opts Target Tutorial ~public:[$<BUILD_INTERFACE:-Wall>] )";
])

(* Phase 2a pair-wise oracle for the var family.
   Mirrors tier0_var inputs through both parser paths and asserts
   byte-identical cmake text.

   Bug-finding: the oracle uncovered a longstanding legacy-parser bug
   for the `( set NAME value )` command form. The legacy
   parse-then-bridge path always renders the variable name as `?`
   regardless of the name supplied (quoted or bare); the new parser
   handles it correctly. The `( set … )` case is therefore omitted
   from the pair-wise oracle until the legacy bug is fixed
   separately. The `:=` operator form, the `cache` form, and the
   multi-value form all agree byte-for-byte between paths. *)
let tier0_var_y1 = ("t0-var-y1", [
  assert_parse_y1_equiv "y1: assignment :="    "( CMAKE_CXX_STANDARD := \"11\" )";
  assert_parse_y1_equiv "y1: cache var :="     "( cache BUILD_SHARED_LIBS := ON ; 'Build shared libs' )";
  assert_parse_y1_equiv "y1: multi-value :="   "( FLAGS := \"-Wall\", \"-Wextra\" )";
])

(* Phase 2a pair-wise oracle for cmake_op family (scalar commands). *)
let tier0_cmake_op_y1 = ("t0-cmake_op-y1", [
  assert_parse_y1_equiv "y1: cmake_minimum_required" "( cmake_minimum_required \"3.20\" )";
  assert_parse_y1_equiv "y1: project"                "( project \"Tutorial\" )";
])

let tier8_misc_cmake_op_y1 = ("t8-misc-cmake_op-y1", [
  assert_parse_y1_equiv "y1: math"             "( math '1+2' ~out:RESULT )";
  assert_parse_y1_equiv "y1: execute_process"  "( execute_process )";
  assert_parse_y1_equiv "y1: include_guard"    "( include_guard )";
  (* y1: policy_set — legacy parser only matches single-quoted Ycs_string
     for the policy id; "CMP0048" is double-quoted (Ycs_path) and falls
     through the legacy match to the empty-string default, emitting
     `cmake_policy(SET  NEW)`. New parser handles both uniformly via
     str_of. Same shape of legacy bug as ( set NAME val ); omitted from
     oracle until the legacy parser is fixed separately. *)
  assert_parse_y1_equiv "y1: enable_language"  "( enable_language )";
])

(* Phase 2a pair-wise oracle for find / install / property families. *)
let tier6_find_install_y1 = ("t6-find-install-y1", [
  assert_parse_y1_equiv "y1: find_library" "( find_library VAR ~names:\"m\" ~paths:\"/usr/lib\" )";
  assert_parse_y1_equiv "y1: find_path"    "( find_path VAR ~names:\"foo.h\" )";
  assert_parse_y1_equiv "y1: find_program" "( find_program VAR ~names:\"git\" )";
  assert_parse_y1_equiv "y1: find_file"    "( find_file VAR ~names:\"config\" )";
  assert_parse_y1_equiv "y1: install_targets" "( install_targets \"lib\" )";
  assert_parse_y1_equiv "y1: install_files"   "( install_files \"include\" )";
  assert_parse_y1_equiv "y1: install_export"  "( install_export EXP \"lib/cmake\" )";
])

let tier8_misc_y1 = ("t8-misc-y1", [
  assert_parse_y1_equiv "y1: get_target_property"
    "( get_target_property Target Foo ~out:VAR )";
  assert_parse_y1_equiv "y1: set_target_properties"
    "( set_target_properties Target Foo )";
  assert_parse_y1_equiv "y1: set_property"
    "( set_property Target Foo )";
])

(* Phase 2a pair-wise oracle for the dir family. *)
let tier0_dir_y1 = ("t0-dir-y1", [
  assert_parse_y1_equiv "y1: add_subdirectory"        "( add_subdirectory \"MathFunctions\" )";
  assert_parse_y1_equiv "y1: include_directories"     "( include_directories \"dir1\" \"dir2\" )";
  assert_parse_y1_equiv "y1: add_compile_options"     "( add_compile_options \"-Wall\" \"-Wextra\" )";
  assert_parse_y1_equiv "y1: add_link_options"        "( add_link_options \"-pie\" )";
  assert_parse_y1_equiv "y1: add_definitions"         "( add_definitions \"-DFOO\" )";
  assert_parse_y1_equiv "y1: link_directories"        "( link_directories \"/opt/lib\" )";
])

(* Phase 2a pair-wise oracle for the target family. *)
let tier0_target_y1 = ("t0-target-y1", [
  assert_parse_y1_equiv "y1: add_exe"      "( add_exe Target Foo )";
  assert_parse_y1_equiv "y1: add_lib"      "( add_lib Target MathFunctions )";
  assert_parse_y1_equiv "y1: link_lib"     "( link_lib Target Tutorial )";
  assert_parse_y1_equiv "y1: link_lib scoped"
    "( link_lib Target Tutorial PRIVATE \"m\" PUBLIC \"dep\" )";
  assert_parse_y1_equiv "y1: include_dirs" "( include_dirs Target Tutorial )";
  assert_parse_y1_equiv "y1: include_dirs scoped"
    "( include_dirs Target Tutorial PRIVATE \"include\" INTERFACE \"iface\" )";
  assert_parse_y1_equiv "y1: compile_defs" "( compile_defs Target Tutorial )";
  assert_parse_y1_equiv "y1: compile_opts" "( compile_opts Target Tutorial )";
])

(* Phase 2a pair-wise oracle for the file family. *)
let tier4_file_y1 = ("t4-file-y1", [
  assert_parse_y1_equiv "y1: read"              "( file_read \"f.txt\" ~out:OUT )";
  assert_parse_y1_equiv "y1: write"             "( file_write \"f.txt\" 'content' )";
  assert_parse_y1_equiv "y1: glob"              "( file_glob ~out:OUT \"*.cxx\" )";
  assert_parse_y1_equiv "y1: copy"              "( file_copy \"src\" \"dst\" )";
  assert_parse_y1_equiv "y1: rename"            "( file_rename \"old\" \"new\" )";
  assert_parse_y1_equiv "y1: remove"            "( file_remove \"f.txt\" )";
  assert_parse_y1_equiv "y1: real_path"         "( file_real_path \"f.txt\" ~out:OUT )";
  assert_parse_y1_equiv "y1: size"              "( file_size \"f.txt\" ~out:OUT )";
  assert_parse_y1_equiv "y1: timestamp"         "( file_timestamp \"f.txt\" ~out:OUT )";
  assert_parse_y1_equiv "y1: make_directory"    "( file_make_directory \"dir\" )";
  assert_parse_y1_equiv "y1: touch"             "( file_touch \"f.txt\" )";
])

(* Phase 2a pair-wise oracle for the path family. *)
let tier5_path_y1 = ("t5-path-y1", [
  assert_parse_y1_equiv "y1: get"                     "( path_get PV ~out:OUT )";
  assert_parse_y1_equiv "y1: has"                     "( path_has PV ~out:OUT )";
  assert_parse_y1_equiv "y1: is_absolute"             "( path_is_absolute PV ~out:OUT )";
  assert_parse_y1_equiv "y1: is_relative"             "( path_is_relative PV ~out:OUT )";
  assert_parse_y1_equiv "y1: set"                     "( path_set PV \"/tmp\" )";
  assert_parse_y1_equiv "y1: append"                  "( path_append PV \"sub\" )";
  assert_parse_y1_equiv "y1: compare"                 "( path_compare P1 P2 ~out:OUT )";
  assert_parse_y1_equiv "y1: hash"                    "( path_hash PV ~out:OUT )";
  assert_parse_y1_equiv "y1: get_filename_component"  "( get_filename_component \"file.txt\" ~out:OUT )";
])

(* Phase 2a pair-wise oracle for the list family. *)
let tier3_list_y1 = ("t3-list-y1", [
  assert_parse_y1_equiv "y1: append"             "( list_append MYLIST 'a' 'b' )";
  assert_parse_y1_equiv "y1: length"             "( list_length MYLIST ~out:LEN )";
  assert_parse_y1_equiv "y1: get"                "( list_get MYLIST 1 ~out:VAL )";
  assert_parse_y1_equiv "y1: remove_item"        "( list_remove_item MYLIST 'a' )";
  assert_parse_y1_equiv "y1: remove_duplicates"  "( list_remove_duplicates MYLIST )";
  assert_parse_y1_equiv "y1: reverse"            "( list_reverse MYLIST )";
  assert_parse_y1_equiv "y1: sort"               "( list_sort MYLIST )";
  assert_parse_y1_equiv "y1: join"               "( list_join MYLIST ';' ~out:RESULT )";
  assert_parse_y1_equiv "y1: find"               "( list_find MYLIST 'needle' ~out:IDX )";
  assert_parse_y1_equiv "y1: prepend"            "( list_prepend MYLIST 'first' )";
  assert_parse_y1_equiv "y1: insert"             "( list_insert MYLIST )";
  assert_parse_y1_equiv "y1: remove_at"          "( list_remove_at MYLIST )";
  assert_parse_y1_equiv "y1: pop_back"           "( list_pop_back MYLIST )";
  assert_parse_y1_equiv "y1: pop_front"          "( list_pop_front MYLIST )";
])

(* Phase 2a pair-wise oracle for the string family. Mirrors tier2_string
   inputs (~17 cases) through both parser paths. Where the parser
   matches the legacy, both sides should produce byte-identical text. *)
let tier2_string_y1 = ("t2-string-y1", [
  assert_parse_y1_equiv "y1: concat"            "( string_concat ~out:out_var 'a' 'b' )";
  assert_parse_y1_equiv "y1: join"              "( string_join ';' ~out:out_var 'a' 'b' )";
  assert_parse_y1_equiv "y1: toupper"           "( string_toupper 'hello' )";
  assert_parse_y1_equiv "y1: tolower"           "( string_tolower 'HELLO' )";
  assert_parse_y1_equiv "y1: length"            "( string_length 'hello' )";
  assert_parse_y1_equiv "y1: replace"           "( string_replace 'old' 'new' 'input' )";
  assert_parse_y1_equiv "y1: regex_match"       "( string_regex_match 'p.*' 'input' )";
  assert_parse_y1_equiv "y1: find"              "( string_find 'sub' 'haystack' )";
  assert_parse_y1_equiv "y1: timestamp"         "( string_timestamp )";
  assert_parse_y1_equiv "y1: hex"               "( string_hex 'abc' )";
  assert_parse_y1_equiv "y1: make_c_identifier" "( string_make_c_identifier 'my var' )";
  assert_parse_y1_equiv "y1: toupper ~out"       "( string_toupper 'hello' ~out:OUT )";
  assert_parse_y1_equiv "y1: toupper ~out first" "( string_toupper ~out:OUT 'hello' )";
  assert_parse_y1_equiv "y1: concat ~out only"   "( string_concat ~out:OUT )";
  assert_parse_y1_equiv "y1: tolower ~out"       "( string_tolower 'HELLO' ~out:OUT )";
  assert_parse_y1_equiv "y1: hex ~out"           "( string_hex 'abc' ~out:OUT )";
  assert_parse_y1_equiv "y1: length ~out"        "( string_length 'hello' ~out:OUT )";
])

let () =
  Alcotest.run "Yelu Parser" [
    tier0_control; tier0_cond; tier0_var; tier0_var_y1; tier0_cmake_op; tier0_cmake_op_y1;
    tier0_target; tier0_target_y1; tier0_dir; tier0_dir_y1; tier0_file; tier0_scripting; tier0_full;
    tier1_target; tier2_string; tier2_string_y1; tier3_list; tier3_list_y1;
    tier4_file; tier4_file_y1; tier5_path; tier5_path_y1;
    tier6_find_install; tier6_find_install_y1;
    tier7_scripting; tier8_misc; tier8_misc_y1; tier8_misc_cmake_op_y1; tier_remaining; tier9_genex;
  ]
