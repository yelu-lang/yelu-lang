(* Cache semantics — spec verification tier.

   Every row of the four enumerated tables in
   [doc/cmake/cache_semantics.md] (Set 1 through Set 4, 12 rows
   verified against cmake 4.3.1) becomes one [check_cache_eval]
   case. A failure here means our eval disagrees with our
   documented spec; the spec itself is doc/cmake/cache_semantics.md.

   Design plan: [doc/yelu_cmake/cache_plan.md] § 5.1.

   The doc encodes cmake's two read modes:
     - [${VAR}]            — normal-then-cache fallback chain
     - [$CACHE{VAR}]       — cache namespace only
   We model them by checking [find_var env "VAR"] (which implements
   the fallback chain post-2026-06-01) and [find_cache_var env "VAR"]
   (cache only). [var_defined] is the union of all three slots,
   matching cmake's [if(DEFINED VAR)].

   The "re-configure" rows (2.3 and 4.x) are modeled by populating
   [cache_vars] via [?cmd_line] before the program runs — see
   cache_plan.md § 6 for why this is a valid proxy for cross-run
   state within a single eval. *)

open Base
open Yelu_langs.Yelu_cmake
open Yelu_langs.Yelu_cmake_store
open Yelu_langs.Yelu_cmake_utils
open Yelu_langs.Yelu_cmake_convert

(* Render a value as the string ${VAR} / $CACHE{VAR} would produce.
   Cache values are always strings (cmake -D parses them as such);
   normal values can be Bool/Int from set() / option() but for the
   12 cases here everything is string-typed. *)
let value_str = function
  | VString s -> s
  | VBool true -> "ON"
  | VBool false -> "OFF"
  | VInt n -> Int.to_string n
  | VUnit -> ""
  | VList _ -> failwith "value_str: VList unexpected in cache tests"
  | VTarget _ -> failwith "value_str: VTarget unexpected in cache tests"

let opt_value_str =
  Option.map ~f:value_str

(* The single matrix-row checker. After eval, compares three
   observables against the cache_semantics.md tables. *)
let check_cache_eval
      ?(cmd_line = [])
      name prog
      ~expected_normal
      ~expected_cache
      ~expected_defined
  =
  Alcotest.test_case name `Quick (fun () ->
    let env, _ = eval_yelu_cmake_expr ~cmd_line empty_env prog in
    let normal = opt_value_str (find_var env "VAR") in
    let cache  = opt_value_str (find_cache_var env "VAR") in
    let defined = var_defined env "VAR" in
    Alcotest.(check (option string)) (name ^ " ${VAR}") expected_normal normal;
    Alcotest.(check (option string)) (name ^ " $CACHE{VAR}") expected_cache cache;
    Alcotest.(check bool) (name ^ " DEFINED VAR") expected_defined defined)

(* Short aliases for the test programs. *)
let set_normal v = yc_set "VAR" [ ystr v ]
let set_cache v  = yc_set_cache "VAR" [ ystr v ]
let unset_normal = ECmakeUnsetVar "VAR"
let unset_cache  = ECmakeUnsetVarCache "VAR"
let nop = EUnit

(* ============================================================
   Set 1: Read on empty (no prior writes)
   ============================================================ *)
let set_1 =
  ( "set_1_read_on_empty",
    [
      check_cache_eval "1.1 never set"
        nop
        ~expected_normal:None
        ~expected_cache:None
        ~expected_defined:false;
      check_cache_eval "1.2 set normal then read"
        (set_normal "val")
        ~expected_normal:(Some "val")
        ~expected_cache:None
        ~expected_defined:true;
      check_cache_eval "1.3 set cache then read"
        (set_cache "val")
        ~expected_normal:(Some "val")   (* dual-write puts it in normal too *)
        ~expected_cache:(Some "val")
        ~expected_defined:true;
    ] )

(* ============================================================
   Set 2: Order matters — normal vs cache, same name
   ============================================================ *)
let set_2 =
  ( "set_2_order_matters",
    [
      check_cache_eval "2.1 normal then cache (dual-write wins)"
        (ESeq [ set_normal "first_n"; set_cache "then_c" ])
        ~expected_normal:(Some "then_c")   (* dual-write overwrites *)
        ~expected_cache:(Some "then_c")
        ~expected_defined:true;
      check_cache_eval "2.2 cache then normal (normal wins read)"
        (ESeq [ set_cache "first_c"; set_normal "then_n" ])
        ~expected_normal:(Some "then_n")   (* normal frame wins *)
        ~expected_cache:(Some "first_c")   (* cache unchanged *)
        ~expected_defined:true;
      (* 2.3 simulates row 2.1 on RE-configure: cache pre-populated
         from cmd_line (proxy for prior CMakeCache.txt). Now the
         set(CACHE) is a NO-OP (cache_var_defined true) so dual-write
         doesn't fire — normal keeps its earlier value. *)
      check_cache_eval "2.3 re-configure: normal sticks, cache untouched"
        ~cmd_line:[("VAR", "then_c")]
        (ESeq [ set_normal "first_n"; set_cache "ignored" ])
        ~expected_normal:(Some "first_n")   (* normal wins; cache write was no-op *)
        ~expected_cache:(Some "then_c")     (* unchanged from cmd_line *)
        ~expected_defined:true;
    ] )

(* ============================================================
   Set 3: unset behavior
   ============================================================ *)
let set_3 =
  ( "set_3_unset_behavior",
    [
      check_cache_eval "3.1 set norm+cache, unset normal -> cache fallback"
        (ESeq [ set_cache "c"; unset_normal ])
        ~expected_normal:(Some "c")   (* fallback through cache *)
        ~expected_cache:(Some "c")
        ~expected_defined:true;
      (* 3.2: cache populated WITHOUT normal-side dual-write. The
         only way to get there in a single eval is cmd_line — set(CACHE)
         always dual-writes on first call. *)
      check_cache_eval "3.2 cache only (via cmd_line), unset normal"
        ~cmd_line:[("VAR", "c")]
        unset_normal
        ~expected_normal:(Some "c")   (* fallback *)
        ~expected_cache:(Some "c")    (* unchanged *)
        ~expected_defined:true;
      check_cache_eval "3.3 set norm+cache, unset CACHE -> both cleared"
        (ESeq [ set_cache "c"; unset_cache ])
        ~expected_normal:None
        ~expected_cache:None
        ~expected_defined:false;
    ] )

(* ============================================================
   Set 4: -D command-line
   ============================================================ *)
let set_4 =
  ( "set_4_cmd_line",
    [
      check_cache_eval "4.1 -D only, no script set"
        ~cmd_line:[("VAR", "cmdline")]
        nop
        ~expected_normal:(Some "cmdline")   (* fallback *)
        ~expected_cache:(Some "cmdline")
        ~expected_defined:true;
      check_cache_eval "4.2 -D, then normal set (normal wins read)"
        ~cmd_line:[("VAR", "cmdline")]
        (set_normal "n")
        ~expected_normal:(Some "n")
        ~expected_cache:(Some "cmdline")    (* untouched *)
        ~expected_defined:true;
      check_cache_eval "4.3 -D, then set CACHE (already in cache -> no-op)"
        ~cmd_line:[("VAR", "cmdline")]
        (set_cache "c")
        ~expected_normal:(Some "cmdline")   (* fallback; cache write was no-op *)
        ~expected_cache:(Some "cmdline")    (* unchanged from cmd_line *)
        ~expected_defined:true;
    ] )

(* ============================================================
   Bonus: option() — cache_semantics.md § "Equivalences"
   option(VAR "msg" V) ≡ set(VAR V CACHE BOOL "msg")
   ============================================================ *)
let options =
  ( "options",
    [
      check_cache_eval "option default ON, first call (writes cache + dual)"
        (yc_option ~msg:"help" ~value:(EBool true) "VAR")
        ~expected_normal:(Some "ON")
        ~expected_cache:(Some "ON")
        ~expected_defined:true;
      check_cache_eval "option default ON, -D OFF wins (suppression)"
        ~cmd_line:[("VAR", "OFF")]
        (yc_option ~msg:"help" ~value:(EBool true) "VAR")
        ~expected_normal:(Some "OFF")   (* fallback to cache; option() was no-op *)
        ~expected_cache:(Some "OFF")    (* untouched from cmd_line *)
        ~expected_defined:true;
    ] )

let () =
  Alcotest.run "yelu_cmake_cache"
    [ set_1; set_2; set_3; set_4; options ]
