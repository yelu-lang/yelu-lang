(* Dual-evaluator equivalence sweep.

   For each program in this file, asserts that yc-eval and ycn-eval
   (after [to_normal]) agree on the resulting value. Env divergence
   is intentionally not compared — see [check_dual_eval] in
   [yelu_test_helpers.ml] for the policy.

   This is the broader-but-looser companion to
   [test_yelu_lift_lower.ml]:
   - lift_lower: 75 cases, strict env+value equivalence, hand-built
     programs with explicit [~expected_env].
   - dual_eval: N cases (this file), value-only, programs lifted
     from real-corpus shapes.

   First cut is small. The intent is to grow this file (or a
   parametrized variant of it) until it covers the same shape
   surface as [test_yelu_compile.ml]'s 194 byte-equality tests —
   at which point every yc program with an emit oracle also has
   a dual-eval oracle. See [doc/yelu_cmake/cmake_vs_normal.md] §
   "Tests" for the broader rollout plan. *)

open Yelu_langs.Yelu_cmake
open Yelu_langs.Yelu_cmake_store
open Yelu_langs.Yelu_cmake_string
open Yelu_langs.Yelu_cmake_list
open Yelu_langs.Yelu_cmake_normal_list
open Yelu_langs.Yelu_cmake_if
open Yelu_test_helpers

(* Programs that return a meaningful value via a trailing [EVar].
   yc-eval and ycn-eval should agree on the final value. *)
let value_returning =
  ( "value_returning",
    [
      check_dual_eval "set then read"
        (ESeq [ ESetVar ("X", EString "hello"); EVar "X" ]);
      check_dual_eval "string toupper"
        (ESeq [
          ECmakeStringToupper { input = EString "hello"; out = "OUT" };
          EVar "OUT";
        ]);
      check_dual_eval "string concat"
        (ESeq [
          ECmakeStringConcat
            { inputs = [ EString "a"; EString "b"; EString "c" ]; out = "OUT" };
          EVar "OUT";
        ]);
      check_dual_eval "string upper then concat"
        (ESeq [
          ECmakeStringToupper { input = EString "b"; out = "TMP" };
          ECmakeStringConcat { inputs = [ EString "a"; EVar "TMP" ]; out = "OUT" };
          EVar "OUT";
        ]);
      check_dual_eval "list length"
        (ESeq [
          ESetVar ("LST", EList [ EString "a"; EString "b"; EString "c" ]);
          ECmakeListLength { list = "LST"; out = "N" };
          EVar "N";
        ]);
    ] )

(* Programs that drive side effects but return VUnit. The helper
   reduces to a fate-sharing check: both evaluators must process
   the (yc, ycn) program pair without crashing. Useful for shapes
   that lift_lower hasn't gotten around to covering. *)
let fate_sharing =
  ( "fate_sharing",
    [
      check_dual_eval "set var only"
        (ESetVar ("FOO", EString "bar"));
      check_dual_eval "set then unset"
        (ESeq [
          ESetVar ("X", EString "1");
          ECmakeUnsetVar "X";
        ]);
      check_dual_eval "if cond branches"
        (ESeq [
          ESetVar ("OUT", EString "init");
          ECmakeIfStmt {
            cond = ECmakeStringEqual (EString "L", EString "R");
            then_ = ESetVar ("OUT", EString "then-branch");
            else_ = Some (ESetVar ("OUT", EString "else-branch"));
          };
          EVar "OUT";
        ]);
      check_dual_eval "nested string ops"
        (ESeq [
          ECmakeStringTolower { input = EString "ABC"; out = "L" };
          ECmakeStringToupper { input = EVar "L"; out = "U" };
          ECmakeStringConcat
            { inputs = [ EVar "L"; EString "-"; EVar "U" ]; out = "OUT" };
          EVar "OUT";
        ]);
      check_dual_eval "list append"
        (ESeq [
          ESetVar ("LST", EList [ EString "a" ]);
          ECmakeListAppend { list = "LST"; items = [ EString "b"; EString "c" ] };
          EVar "LST";
        ]);
    ] )

let () =
  Alcotest.run "yelu_cmake_dual_eval"
    [ value_returning; fate_sharing ]
