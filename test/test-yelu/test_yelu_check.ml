open Base
open Yelu_langs.Lang_cmake
open Yelu_langs.Lang_yelu_cmake
open Yelu_langs.Lang_yelu_utils
open Yelu_langs.Lang_yelu_wellform

let _stage = Cmake_check.stage
let _wellform_stage = stage

let no_errors name stmts =
  Alcotest.test_case name `Quick (fun () ->
    let (_, errs) = Cmake_check.check_stmts Cmake_check.empty_env stmts in
    Alcotest.(check int) name 0 (List.length errs))

let has_errors name stmts =
  Alcotest.test_case name `Quick (fun () ->
    let (_, errs) = Cmake_check.check_stmts Cmake_check.empty_env stmts in
    Alcotest.(check bool) name true (not (List.is_empty errs)))

(* Wellform helpers *)
let wf_no_errors name stmts =
  Alcotest.test_case name `Quick (fun () ->
    let (_, errs) = check_stmts empty_env stmts in
    Alcotest.(check int) name 0 (List.length errs))

let wf_has_errors name stmts =
  Alcotest.test_case name `Quick (fun () ->
    let (_, errs) = check_stmts empty_env stmts in
    Alcotest.(check bool) name true (not (List.is_empty errs)))

(* helpers *)
let str_lit s = ystr s           (* Yexpr_string (Ycs_val s) *)
let bool_lit b = Yexpr_bool b
let cvar_expr s = ycstr s
let yvar_expr s = Yexpr_var (Yvar s)
let out = ycvar "OUT"

(* ============================================================
   Positive — no type errors expected
   ============================================================ *)

let positive = ("string_check_positive", [

  no_errors "toupper string literal"
    [ Ys_string (Ystr_toupper { string = str_lit "hello"; out }) ];

  no_errors "tolower string literal"
    [ Ys_string (Ystr_tolower { string = str_lit "HELLO"; out }) ];

  no_errors "length of string literal"
    [ Ys_string (Ystr_length { string = str_lit "hi"; out }) ];

  no_errors "concat two strings"
    [ Ys_string (Ystr_concat { out; inputs = [str_lit "a"; str_lit "b"] }) ];

  no_errors "join strings"
    [ Ys_string (Ystr_join { glue = str_lit ";"; out; inputs = [str_lit "x"; str_lit "y"] }) ];

  no_errors "untyped cvar passes through (Ty_any)"
    [ Ys_string (Ystr_toupper { string = cvar_expr "UNTYPED"; out }) ];

  (* env flow: Ylet binds a string, subsequent op sees Ty_string *)
  no_errors "ylet string then toupper"
    [ Ylet { var = Yvar "msg"; value = str_lit "world" };
      Ys_string (Ystr_toupper { string = yvar_expr "msg"; out }) ];

  no_errors "ylet string then length"
    [ Ylet { var = Yvar "msg"; value = str_lit "world" };
      Ys_string (Ystr_length { string = yvar_expr "msg"; out }) ];

  (* output binding propagates type forward *)
  no_errors "string op output reused"
    [ Ys_string (Ystr_toupper { string = str_lit "hi"; out = ycvar "TMP" });
      Ys_string (Ystr_length { string = cvar_expr "TMP"; out }) ];

  no_errors "cond strequal two strings"
    [ Yif { cond = Ystrequal (str_lit "a", str_lit "b");
            then_ = Ystmt_list []; else_ = None } ];
])

(* ============================================================
   Negative — at least one type error expected
   ============================================================ *)

let negative = ("string_check_negative", [

  has_errors "bool where string expected (toupper)"
    [ Ys_string (Ystr_toupper { string = bool_lit true; out }) ];

  has_errors "bool in concat inputs"
    [ Ys_string (Ystr_concat { out; inputs = [str_lit "ok"; bool_lit false] }) ];

  has_errors "bool in join glue"
    [ Ys_string (Ystr_join { glue = bool_lit true; out; inputs = [str_lit "x"] }) ];

  has_errors "bool in join item"
    [ Ys_string (Ystr_join { glue = str_lit ","; out; inputs = [bool_lit false] }) ];

  (* env flow: Ylet binds a bool, subsequent string op catches it *)
  has_errors "ylet bool then toupper"
    [ Ylet { var = Yvar "flag"; value = bool_lit true };
      Ys_string (Ystr_toupper { string = yvar_expr "flag"; out }) ];

  has_errors "ylet bool then length"
    [ Ylet { var = Yvar "flag"; value = bool_lit true };
      Ys_string (Ystr_length { string = yvar_expr "flag"; out }) ];

  has_errors "cond strequal bool and string"
    [ Yif { cond = Ystrequal (bool_lit true, str_lit "b");
            then_ = Ystmt_list []; else_ = None } ];
])

(* ============================================================
   Wellform — positive (no errors expected)
   ============================================================ *)

let wf_positive = ("wellform_positive", [

  wf_no_errors "set then reference"
    [ Ys_var (Yvar_set { cvar = ycvar "X"; values = [ str_lit "hello" ]; parent_scope = false });
      Ys_string (Ystr_toupper { string = cvar_expr "X"; out }) ];

  wf_no_errors "string op output reused"
    [ Ys_string (Ystr_toupper { string = str_lit "hi"; out = ycvar "TMP" });
      Ys_string (Ystr_length { string = cvar_expr "TMP"; out }) ];

  wf_no_errors "builtin cvar passes without declaration"
    [ Ys_string (Ystr_toupper { string = cvar_expr "CMAKE_C_COMPILER"; out }) ];

  wf_no_errors "CMAKE_ prefix works"
    [ Ys_string (Ystr_toupper { string = cvar_expr "CMAKE_SOURCE_DIR"; out }) ];

  wf_no_errors "PROJECT_ prefix works"
    [ Ys_string (Ystr_toupper { string = cvar_expr "PROJECT_NAME"; out }) ];

  wf_no_errors "BUILD_ prefix works"
    [ Ys_string (Ystr_toupper { string = cvar_expr "BUILD_SHARED_LIBS"; out }) ];

  wf_no_errors "ctest prefix works"
    [ Ys_string (Ystr_toupper { string = cvar_expr "CTEST_TEST_LOAD"; out }) ];

  wf_no_errors "cpack prefix works"
    [ Ys_string (Ystr_toupper { string = cvar_expr "CPACK_PACKAGE_NAME"; out }) ];

  wf_no_errors "yis_defined does not require cvar to be declared"
    [ Yif { cond = Yis_defined (cvar_expr "UNDECLARED");
            then_ = Ystmt_list []; else_ = None } ];

  wf_no_errors "foreach loop var scoped to body"
    [ Yc_foreach { loop_var = ycvar "ITEM"; items = [ str_lit "a" ];
                  commands = Ys_string (Ystr_toupper { string = cvar_expr "ITEM"; out }) } ];

  wf_no_errors "foreach loop var not available outside body"
    [ Yc_foreach { loop_var = ycvar "ITEM"; items = [ str_lit "a" ];
                  commands = Ystmt_list [] };
      Ys_string (Ystr_toupper { string = str_lit "ok"; out = ycvar "ITEM" }) ];

  wf_no_errors "Yc_extern_cvar satisfies declaration"
    [ Yc_extern_cvar (ycvar "PRE_EXISTING");
      Ys_string (Ystr_toupper { string = cvar_expr "PRE_EXISTING"; out }) ];

  wf_no_errors "Yc_extern_target then reference"
    [ Yc_extern_target (ytarget "MyLib");
      Ys_install (Yinstall_targets
        { targets = [ ytval "MyLib" ];
          destination = yfile "lib"; export = None }) ];

  wf_no_errors "branch union: target declared in both branches available after"
    [ Yif { cond = Ytruthy (bool_lit true);
            then_ = Ys_target (Ytgt_add_library
              { name = ytval "LibA"; type_ = None; exclude_from_all = false; sources = [] });
            else_ = Some (Ys_target (Ytgt_add_library
              { name = ytval "LibA"; type_ = None; exclude_from_all = false; sources = [] })) };
      Ys_install (Yinstall_targets
        { targets = [ ytval "LibA" ];
          destination = yfile "lib"; export = None }) ];

  wf_no_errors "Ylet then reference via yvar"
    [ Ylet { var = Yvar "tgt"; value = ytval "MyTarget" };
      Ys_target (Ytgt_add_library
        { name = yvar_expr "tgt"; type_ = None; exclude_from_all = false; sources = [] }) ];

  wf_no_errors "set then list op with cvar"
    [ Ys_var (Yvar_set { cvar = ycvar "MY_LIST"; values = [ str_lit "a"; str_lit "b" ]; parent_scope = false });
      Ys_list (Ylist_append { cvar = ycvar "MY_LIST"; values = [ str_lit "c" ] }) ];

  wf_no_errors "target then target_include_directories"
    [ Ys_target (Ytgt_add_executable
        { name = ytval "MyExe"; exclude_from_all = false; sources = [ yfile "main.cxx" ] });
      Ys_target (Ytgt_include_directories
        { target = ytval "MyExe"; before = false; system = false;
          items = [{ kind = Public; items = [ ydir "include" ] }] }) ];

  wf_no_errors "option declares cvar"
    [ Ys_var (Yvar_option { cvar = ycvar "ENABLE_FOO"; msg = "Enable foo"; value = bool_lit true });
      Yif { cond = Ytruthy (cvar_expr "ENABLE_FOO");
            then_ = Ystmt_list []; else_ = None } ];

  wf_no_errors "set_cache declares cvar"
    [ Ys_var (Yvar_set_cache { cvar = ycvar "CACHED_VAR";
        values = [ str_lit "val" ]; cache_type = Ct_string;
        docstring = "doc"; force = false });
      Ys_string (Ystr_toupper { string = cvar_expr "CACHED_VAR"; out }) ];

  wf_no_errors "find library declares cvar"
    [ Ys_find (Yfind_library { cvar = ycvar "MATH_LIB";
        names = [ str_lit "m" ]; paths = []; hints = [];
        no_default_path = false; no_cmake_environment_path = false;
        no_system_environment_path = false; required = false });
      Ys_string (Ystr_toupper { string = cvar_expr "MATH_LIB"; out }) ];

  wf_no_errors "path op declares cvar"
    [ Ys_path (Ypath_convert_to_cmake
        { input = yfile "/tmp"; normalize = false; out = ycvar "CMAKE_PATH" });
      Ys_string (Ystr_toupper { string = cvar_expr "CMAKE_PATH"; out }) ];

  wf_no_errors "try_compile declares result cvar"
    [ Ys_try (Ytry_compile { result_var = ycvar "TRY_RESULT";
        sources = [ yfile "test.c" ]; compile_definitions = [];
        link_libraries = []; link_options = []; output_variable = None;
        no_cache = false; c_standard = None; cxx_standard = None });
      Yif { cond = Ytruthy (cvar_expr "TRY_RESULT");
            then_ = Ystmt_list []; else_ = None } ];

  wf_no_errors "var_set parent_scope does not declare in current scope"
    [ Ys_var (Yvar_set { cvar = ycvar "PARENT_VAR"; values = [ str_lit "v" ]; parent_scope = true });
      Ys_string (Ystr_toupper { string = str_lit "ok"; out = ycvar "PARENT_VAR" }) ];

  wf_no_errors "list_length declares output"
    [ Ys_var (Yvar_set { cvar = ycvar "L"; values = [ str_lit "a"; str_lit "b" ]; parent_scope = false });
      Ys_list (Ylist_length { cvar = ycvar "L"; out = ycvar "LEN" });
      Ys_string (Ystr_toupper { string = cvar_expr "LEN"; out }) ];

  wf_no_errors "ylet target name then use in install"
    [ Ylet { var = Yvar "lib"; value = ytval "MathLib" };
      Ys_target (Ytgt_add_library
        { name = yvar_expr "lib"; type_ = None; exclude_from_all = false; sources = [] });
      Ys_install (Yinstall_targets
        { targets = [ yvar_expr "lib" ]; destination = ydir "lib"; export = None }) ];

  wf_no_errors "yis_target does not require target declaration"
    [ Yif { cond = Yis_target (ytval "MaybeTarget");
            then_ = Ystmt_list []; else_ = None } ];

])

(* ============================================================
   Wellform — negative (errors expected)
   ============================================================ *)

let wf_negative = ("wellform_negative", [

  wf_has_errors "undeclared cvar in string op"
    [ Ys_string (Ystr_toupper { string = cvar_expr "UNDECLARED"; out }) ];

  wf_has_errors "undeclared target in install"
    [ Ys_install (Yinstall_targets
        { targets = [ ytval "NoSuchTarget" ]; destination = yfile "lib"; export = None }) ];

  wf_has_errors "cvar used before set"
    [ Ys_string (Ystr_toupper { string = cvar_expr "LATE_DECL"; out });
      Ys_var (Yvar_set { cvar = ycvar "LATE_DECL"; values = [ str_lit "too late" ]; parent_scope = false }) ];

  wf_has_errors "undeclared cvar in list op cvar position"
    [ Ys_list (Ylist_append { cvar = ycvar "NO_SUCH_LIST"; values = [ str_lit "x" ] }) ];

  wf_has_errors "undeclared cvar in condition"
    [ Yif { cond = Ytruthy (cvar_expr "UNDECLARED_COND");
            then_ = Ystmt_list []; else_ = None } ];

  wf_has_errors "undeclared cvar in for_each items"
    [ Yc_foreach { loop_var = ycvar "X"; items = [ cvar_expr "UNDECLARED_ITEM" ];
                  commands = Ystmt_list [] } ];

  wf_has_errors "undeclared target in target_include_directories"
    [ Ys_target (Ytgt_include_directories
        { target = ytval "MissingTarget"; before = false; system = false;
          items = [{ kind = Public; items = [ ydir "inc" ] }] }) ];

  wf_has_errors "undeclared cvar in while condition"
    [ Yc_while { cond = Ytruthy (cvar_expr "UNDECLARED_WHILE");
                 commands = Ystmt_list [] } ];

  wf_has_errors "undeclared target reference after library decl (wrong name)"
    [ Ys_target (Ytgt_add_library
        { name = ytval "RealLib"; type_ = None; exclude_from_all = false; sources = [] });
      Ys_install (Yinstall_targets
        { targets = [ ytval "WrongLib" ]; destination = yfile "lib"; export = None }) ];

  wf_has_errors "undeclared cvar in set value"
    [ Ys_var (Yvar_set { cvar = ycvar "X"; values = [ cvar_expr "UNDECLARED_SETVAL" ]; parent_scope = false }) ];

  wf_has_errors "undeclared cvar in foreach_in lists"
    [ Yc_foreach_in { loop_var = ycvar "X"; lists = [ ycvar "NO_SUCH" ]; items = [];
                      commands = Ystmt_list [] } ];

  wf_has_errors "undeclared cvar in foreach_zip lists"
    [ Yc_foreach_zip { loop_vars = [ ycvar "A" ]; lists = [ ycvar "NO_SUCH" ];
                       commands = Ystmt_list [] } ];

  wf_has_errors "undeclared cvar in path op path_var position"
    [ Ys_path (Ypath_get { path_var = ycvar "NO_PATH";
        field = Cpf_filename; out = ycvar "OUT" }) ];

  wf_has_errors "undeclared target in set_target_properties"
    [ Ys_property (Yprop_set_target
        { target = ytval "GhostTarget"; properties = [ "FOLDER", str_lit "Utils" ] }) ];

  wf_has_errors "undeclared target in link_libraries"
    [ Ys_target (Ytgt_link_libraries
        { targets = [ ytval "GhostTarget" ];
          items = [{ kind = Public; items = [] }] }) ];

])

let () = Alcotest.run "Yelu Check" [ positive; negative; wf_positive; wf_negative ]
