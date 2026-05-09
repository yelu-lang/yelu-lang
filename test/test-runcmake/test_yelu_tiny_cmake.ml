open Yelu_langs.Yelu_tiny
open Yelu_langs.Yelu_theory_store
open Yelu_langs.Yelu_theory_int
open Yelu_langs.Yelu_theory_list
open Yelu_langs.Yelu_theory_path
open Yelu_langs.Yelu_theory_target
open Yelu_langs.Yelu_theory_string
open Yelu_langs.Yelu_theory_if
open Yelu_langs.Yelu_surface_cmake_list
open Yelu_langs.Yelu_surface_cmake_path
open Yelu_langs.Yelu_surface_cmake_string
open Yelu_langs.Yelu_surface_cmake_if
open Yelu_langs.Yelu_tiny_eval
open Yelu_langs.Yelu_tiny_cmake_emit
open Yelu_runner.Cmake_runner

let check_same_cmake_output name left right =
  Alcotest.test_case name `Quick (fun () ->
    let left_text = emit_script left in
    let right_text = emit_script right in
    let left_result = run_script left_text in
    let right_result = run_script right_text in
    check_exit 0 left_result;
    check_exit 0 right_result;
    Alcotest.(check string) "stdout" left_result.stdout right_result.stdout;
    Alcotest.(check string) "stderr" left_result.stderr right_result.stderr)

let check_yelu1_roundtrip_cmake name expr =
  check_same_cmake_output name expr (lower_yelu2_to_yelu1 (lift_yelu1_to_yelu2 expr))

let check_yelu2_lowering_cmake name expr =
  Alcotest.test_case name `Quick (fun () ->
    let cmake_text = emit_script (lower_yelu2_to_yelu1 expr) in
    let result = run_script cmake_text in
    check_exit 0 result;
    Alcotest.(check string) "stdout" "" result.stdout;
    Alcotest.(check string) "stderr" "RESULT=YES\n" result.stderr)

let check_yelu2_lowering_configure ?(files = [ "main.c", "int main(void) { return 0; }\n" ]) name expr =
  Alcotest.test_case name `Quick (fun () ->
    let cmake_text = emit_script (lower_yelu2_to_yelu1 expr) in
    let result =
      run_configure ~languages:[ "C" ] ~files cmake_text
    in
    check_exit 0 result.run;
    check_stderr_matches "RESULT=YES" result.run)

let yelu1_roundtrip =
  ( "yelu1_roundtrip_cmake",
    [
      check_yelu1_roundtrip_cmake "string effects"
        (ESeq [
          ECmakeStringToupper { input = EString "abc"; out = "TMP" };
          ECmakeStringConcat { inputs = [ EVar "TMP"; EString "-x" ]; out = "OUT" };
          EVar "OUT";
        ]);
      check_yelu1_roundtrip_cmake "if and string effects"
        (ESeq [
          ECmakeIfStmt
            {
              cond = ECmakeStringEqual (EString "left", EString "right");
              then_ = ECmakeStringToupper { input = EString "bad"; out = "OUT" };
              else_ = Some (ECmakeStringToupper { input = EString "good"; out = "OUT" });
            };
          EVar "OUT";
        ]);
      check_yelu1_roundtrip_cmake "list effects"
        (ESeq [
          ECmakeListAppend { list = "XS"; items = [ EString "a"; EString "b" ] };
          ECmakeListGet { list = "XS"; index = EInt 1; out = "ITEM" };
          EVar "ITEM";
        ]);
      check_yelu1_roundtrip_cmake "path effects"
        (ESeq [
          ECmakePathSet { path = "P"; input = EString "a/./b/../c"; normalize = false };
          ECmakePathNormalPath { path = "P"; out = None };
          EVar "P";
        ]);
    ] )

let yelu2_lowering =
  ( "yelu2_lowering_cmake",
    [
      check_yelu2_lowering_cmake "if expression saved to output"
        (ESeq [
          ESetVar
            ( "OUT",
              EIfExpr
                {
                  cond = EStringEqual (EString "x", EString "x");
                  then_ = EStringUpper (EString "yes");
                  else_ = EStringUpper (EString "no");
                } );
          EVar "OUT";
        ]);
      check_yelu2_lowering_cmake "defined after unset"
        (ESeq [
          ESetVar ("X", EString "value");
          EUnsetVar "X";
          ESetVar
            ( "OUT",
              EIfExpr
                {
                  cond = EVarDefined "X";
                  then_ = EStringUpper (EString "no");
                  else_ = EStringUpper (EString "yes");
                } );
          EVar "OUT";
        ]);
      check_yelu2_lowering_cmake "int equality from string length"
        (ESeq [
          ESetVar ("LEN", EStringLen (EString "abc"));
          ESetVar
            ( "OUT",
              EIfExpr
                {
                  cond = EIntEqual (EVar "LEN", EInt 3);
                  then_ = EStringUpper (EString "yes");
                  else_ = EStringUpper (EString "no");
                } );
          EVar "OUT";
        ]);
      check_yelu2_lowering_cmake "list join in if expression"
        (ESeq [
          ESetVar ("XS", EList [ EString "a"; EString "b" ]);
          ESetVar ("JOINED", EStringJoin { sep = EString "-"; items = EVar "XS" });
          ESetVar
            ( "OUT",
              EIfExpr
                {
                  cond = EStringEqual (EVar "JOINED", EString "a-b");
                  then_ = EStringUpper (EString "yes");
                  else_ = EStringUpper (EString "no");
                } );
          EVar "OUT";
        ]);
      check_yelu2_lowering_cmake "list get in if expression"
        (ESeq [
          ESetVar ("XS", EList [ EString "no"; EString "yes" ]);
          ESetVar ("ITEM", EListGet (EVar "XS", EInt 1));
          ESetVar
            ( "OUT",
              EIfExpr
                {
                  cond = EStringEqual (EVar "ITEM", EString "yes");
                  then_ = EStringUpper (EString "yes");
                  else_ = EStringUpper (EString "no");
                } );
          EVar "OUT";
        ]);
      check_yelu2_lowering_cmake "path filename in if expression"
        (ESeq [
          ESetVar ("P", EString "/usr/local/bin/cmake");
          ESetVar ("FILENAME", EPathFilename (EVar "P"));
          ESetVar
            ( "OUT",
              EIfExpr
                {
                  cond = EStringEqual (EVar "FILENAME", EString "cmake");
                  then_ = EStringUpper (EString "yes");
                  else_ = EStringUpper (EString "no");
                } );
          EVar "OUT";
        ]);
    ] )

let yelu2_configure_lowering =
  ( "yelu2_lowering_configure",
    [
      check_yelu2_lowering_configure "target declaration and existence"
        (ESeq [
          ESetVar
            ("APP", EExecutable { name = EString "app"; sources = [ EString "main.c" ] });
          ESetVar
            ( "OUT",
              EIfExpr
                {
                  cond = ETargetExists (ETarget "app");
                  then_ = EStringUpper (EString "yes");
                  else_ = EStringUpper (EString "no");
                } );
          EVar "OUT";
        ]);
      check_yelu2_lowering_configure "target sources mutation"
        ~files:
          [
            "main.c", "int main(void) { return 0; }\n";
            "extra.c", "int extra(void) { return 0; }\n";
          ]
        (ESeq [
          ESetVar
            ("APP", EExecutable { name = EString "app"; sources = [ EString "main.c" ] });
          ETargetAddSources { target = ETarget "app"; visibility = "PRIVATE"; sources = [ EString "extra.c" ] };
          ESetVar
            ( "OUT",
              EIfExpr
                {
                  cond = ETargetExists (ETarget "app");
                  then_ = EStringUpper (EString "yes");
                  else_ = EStringUpper (EString "no");
                } );
          EVar "OUT";
        ]);
      check_yelu2_lowering_configure "target link libraries mutation"
        ~files:[ "main.c", "int main(void) { return 0; }\n" ]
        (ESeq [
          ESetVar
            ("APP", EExecutable { name = EString "app"; sources = [ EString "main.c" ] });
          ETargetLinkLibraries { target = ETarget "app"; visibility = "PRIVATE"; items = [ EString "m" ] };
          ESetVar
            ( "OUT",
              EIfExpr
                {
                  cond = ETargetExists (ETarget "app");
                  then_ = EStringUpper (EString "yes");
                  else_ = EStringUpper (EString "no");
                } );
          EVar "OUT";
        ]);
      check_yelu2_lowering_configure "target include directories mutation"
        ~files:[ "main.c", "int main(void) { return 0; }\n" ]
        (ESeq [
          ESetVar
            ("APP", EExecutable { name = EString "app"; sources = [ EString "main.c" ] });
          ETargetIncludeDirectories { target = ETarget "app"; visibility = "PRIVATE"; dirs = [ EString "include" ] };
          ESetVar
            ( "OUT",
              EIfExpr
                {
                  cond = ETargetExists (ETarget "app");
                  then_ = EStringUpper (EString "yes");
                  else_ = EStringUpper (EString "no");
                } );
          EVar "OUT";
        ]);
    ] )

let () =
  Alcotest.run "yelu_tiny_cmake"
    [ yelu1_roundtrip; yelu2_lowering; yelu2_configure_lowering ]
