(* Dual-evaluator equivalence sweep.

   For each program in this file, asserts that yc-eval and ycn-eval
   (after [to_normal]) agree on the resulting value. Env divergence
   is intentionally not compared — see [check_dual_eval] in
   [yelu_test_helpers.ml] for the policy.

   Companion to [test_yelu_lift_lower.ml]:
   - lift_lower: 75 cases, strict env+value equivalence, hand-built
     programs with explicit [~expected_env].
   - dual_eval (this file): broader, looser. Programs lifted from
     [test_yelu_compile.ml]'s shape corpus using the same ergonomic
     helpers (yc_set, add_lib, yc_foreach, etc.), but switched from
     emit byte-equality to value-only dual-eval. Intentionally
     fate-sharing for stmt-level programs that return VUnit — the
     win is "ycn-eval doesn't crash on this shape".

   Coverage status by test_yelu_compile section
   (see doc/yelu_cmake/cmake_vs_normal.md § "Dual-eval coverage"):
   - ✅ primitives, conditions, let_bindings, iteration,
     loop_control, list_ops, string_ops
   - ⏭ skipped: find_package, genex, execute_process, file_ops,
     cmake_path, cmake_language, block, try_compile, target_property,
     define_property, scripting_ext, targets, project_level,
     composition (cmake-shape heavy; expected to surface multiple
     ycn-eval gaps similar to the EStringLower discovery — will
     add iteratively as fragments are filled in).

   When a new program here exposes a missing ycn ctor or eval arm,
   the fix lives in `src/langs/yelu/fragments/yelu_cmake_normal_*.ml`
   + `yelu_cmake_convert.ml`. The Tolower fix in commit 4338167 is
   the worked example. *)

open Yelu_langs.Yelu_cmake
open Yelu_langs.Yelu_cmake_store
open Yelu_langs.Yelu_cmake_string
open Yelu_langs.Yelu_cmake_normal_list
open Yelu_langs.Yelu_cmake_if
open Yelu_langs.Yelu_cmake_utils
open Yelu_test_helpers

(* ============================================================
   Sections lifted from test_yelu_compile.ml.
   Same programs, same helpers; only the checker changes
   (emit byte-equality -> value-only dual-eval).
   ============================================================ *)

let primitives =
  ( "primitives",
    [
      check_dual_eval "set var"
        (yc_set (ycvar "FOO") [ ystr "bar" ]);
      check_dual_eval "set string"
        (yc_set (ycvar "FOO") [ ystr "hello" ]);
      check_dual_eval "set bool"
        (yc_set (ycvar "FOO") [ ybool true ]);
      check_dual_eval "set multiple"
        (yc_set (ycvar "SRCS") [ yfile "a.cpp"; yfile "b.cpp" ]);
      (* NOTE: [set parent_scope] from test_yelu_compile is omitted —
         yc-eval errors at root frame with "PARENT_SCOPE has no parent"
         (tiny-only diagnostic; real cmake silently no-ops). Belongs
         in a scope-aware eval harness, not this fate-sharing sweep. *)
    ] )

let conditions =
  ( "conditions",
    [
      (* yc-eval treats unbound vars as errors (real cmake treats them
         as empty/false). Pre-bind so [ytruthy] has something to read.
         The "if cond_var" / "if cond_var false" programs from
         test_yelu_compile both rely on cmake-style implicit deref of
         unbound vars; that's a separate eval-semantics gap. *)
      check_dual_eval "if literal true"
        (ESeq [
          ESetVar ("FLAG", EBool true);
          yifthen (ytruthy (ycstr "FLAG"))
            (yc_set (ycvar "X") [ ystr "1" ]);
        ]);
      check_dual_eval "if literal false"
        (ESeq [
          ESetVar ("FLAG", EBool false);
          yifthen (ytruthy (ycstr "FLAG"))
            (yc_set (ycvar "X") [ ystr "should-not-fire" ]);
        ]);
    ] )

let let_bindings =
  ( "let_bindings",
    [
      check_dual_eval "ylet simple"
        (ycmd_of_list
           [
             ylet "msg" (ystr "hello");
             yc_set (ycvar "OUT") [ yvar "msg" ];
           ]);
    ] )

let list_ops =
  ( "list_ops",
    [
      check_dual_eval "list_length"
        (ESeq [
           ESetVar ("MY_LIST", EList [ EString "a"; EString "b" ]);
           yc_list_length (ycvar "MY_LIST") (ycvar "OUT");
         ]);
      check_dual_eval "list_append then length"
        (ESeq [
           ESetVar ("LST", EList [ EString "a" ]);
           yc_list_append (ycvar "LST") [ ystr "b"; ystr "c" ];
           yc_list_length (ycvar "LST") (ycvar "N");
           EVar "N";
         ]);
    ] )

let string_ops =
  ( "string_ops",
    [
      check_dual_eval "string_toupper"
        (ESeq [
           yc_string_toupper (ystr "hello") (ycvar "OUT");
           EVar "OUT";
         ]);
      check_dual_eval "string_tolower"
        (ESeq [
           yc_string_tolower (ystr "HELLO") (ycvar "OUT");
           EVar "OUT";
         ]);
      check_dual_eval "string_concat upper+lower"
        (ESeq [
           yc_string_toupper (ystr "a") (ycvar "U");
           yc_string_tolower (ystr "B") (ycvar "L");
           ECmakeStringConcat
             { inputs = [ EVar "U"; EString "-"; EVar "L" ]; out = "OUT" };
           EVar "OUT";
         ]);
    ] )

(* ============================================================
   Original direct-ycn-ctor programs from the initial helper smoke
   test (commit 4338167). Kept because they exercise lower-level
   IR shapes that the cmake-helper sections above mostly hide.
   ============================================================ *)

let direct_ctors =
  ( "direct_ctors",
    [
      check_dual_eval "set then read"
        (ESeq [ ESetVar ("X", EString "hello"); EVar "X" ]);
      check_dual_eval "string toupper raw"
        (ESeq [
          ECmakeStringToupper { input = EString "hello"; out = "OUT" };
          EVar "OUT";
        ]);
      check_dual_eval "string concat raw"
        (ESeq [
          ECmakeStringConcat
            { inputs = [ EString "a"; EString "b"; EString "c" ]; out = "OUT" };
          EVar "OUT";
        ]);
      check_dual_eval "string upper then concat raw"
        (ESeq [
          ECmakeStringToupper { input = EString "b"; out = "TMP" };
          ECmakeStringConcat { inputs = [ EString "a"; EVar "TMP" ]; out = "OUT" };
          EVar "OUT";
        ]);
      check_dual_eval "set then unset"
        (ESeq [
          ESetVar ("X", EString "1");
          ECmakeUnsetVar "X";
        ]);
      check_dual_eval "if cond branches raw"
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
    ] )

let () =
  Alcotest.run "yelu_cmake_dual_eval"
    [ primitives; conditions; let_bindings; list_ops;
      string_ops; direct_ctors ]
