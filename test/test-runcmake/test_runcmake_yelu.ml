(** Paired RunCMake equivalence tests: for each case, run both the upstream cmake
    script (or an inline cmake reference) and the yelu-compiled equivalent, then
    assert both exit 0 and produce identical stdout.

    Two helpers:
      check_pair      — reference is the upstream RunCMake .cmake file
      check_pair_text — reference is an inline cmake string (used when the
                        upstream script produces no stdout, e.g. cmake_path) *)

open Yelu_langs.Lang_yelu_cmake
open Yelu_langs.Lang_yelu_utils
open Yelu_langs.Lang_cmake
open Yelu_langs.Lang_yelu_compile
open Yelu_langs.Lang_cmake_pp
open Yelu_runner.Cmake_runner

let runcmake_dir =
  match Sys.getenv_opt "RUNCMAKE_DIR" with
  | Some d -> d
  | None ->
    let rec find dir depth =
      if depth > 10 then
        failwith ("cannot find workspace root from " ^ Sys.getcwd ())
      else
        let marker = Filename.concat dir "yelu/vendor" in
        if Sys.file_exists marker then dir
        else find (Filename.dirname dir) (depth + 1)
    in
    let ws_root = find (Sys.getcwd ()) 0 in
    let vendor_cmake = Filename.concat ws_root "yelu/vendor/cmake" in
    let resolved = try Unix.realpath vendor_cmake with Unix.Unix_error _ -> vendor_cmake in
    Filename.concat resolved "Tests/RunCMake"

let script_dir d = Filename.concat runcmake_dir d

let compile_to_cmake prog =
  let _, ast = compile empty_env prog in
  let buf = Buffer.create 512 in
  let ff = Format.formatter_of_buffer buf in
  Format.pp_open_vbox ff 0;
  pp ff ast;
  Format.pp_close_box ff ();
  Format.pp_print_flush ff ();
  Buffer.contents buf

(* R5 — same prog through the tiny bridge instead of production compile.
   Used by the [check_pair_*] helpers to assert tiny's emit produces
   cmake that runs identically to the reference. *)
let bridge_to_cmake_via_tiny prog =
  let yelu1 = Yelu_langs.Yelu_cmake_to_yelu1.stmt prog in
  Yelu_langs.Yelu_tiny_cmake_emit.emit_script yelu1

let fail_mismatch ref_result yelu_result cmake_text =
  Alcotest.failf "stdout mismatch\nref :\n%s\nyelu:\n%s\nyelu cmake:\n%s"
    ref_result.stdout yelu_result.stdout cmake_text

(* R5 — drive [prog] through the tiny bridge and assert that the
   resulting cmake (a) runs successfully and (b) produces the same
   stdout as the reference. The bridge / emit code is intentionally
   different from the production compile path; matching stdouts is the
   semantic-equivalence check. *)
let check_tiny_matches_ref name ref_result prog =
  match bridge_to_cmake_via_tiny prog with
  | exception Yelu_langs.Yelu_cmake_to_yelu1.Bridge_error msg ->
    Alcotest.failf "%s: tiny bridge raised: %s" name msg
  | tiny_cmake ->
    let tiny_result = run_script tiny_cmake in
    if tiny_result.exit_code <> 0 then
      Alcotest.failf
        "%s: tiny-emitted cmake failed at configure (exit %d)\nstderr:\n%s\ntiny cmake:\n%s"
        name tiny_result.exit_code tiny_result.stderr tiny_cmake;
    if ref_result.stdout <> tiny_result.stdout then
      Alcotest.failf
        "%s: tiny stdout differs from reference\nref:\n%s\ntiny:\n%s\ntiny cmake:\n%s"
        name ref_result.stdout tiny_result.stdout tiny_cmake

(* R5 skip-list. Names of tests where the tiny bridge can't produce
   equivalent cmake yet — typically because tiny's emit handles a
   construct differently than the production compile, or because the
   bridge raises. Each entry needs a follow-up R2-style attrition fix
   before it can come off the list. Empty means R5 is fully closed. *)
let tiny_bridge_skip : string list = [
]

let do_tiny_check name =
  not (Base.List.mem tiny_bridge_skip name ~equal:Base.String.equal)

(** Reference is the upstream RunCMake .cmake file. *)
let check_pair name dir ?(cmake_flags = []) yelu_prog =
  Alcotest.test_case name `Quick (fun () ->
    let ref_result = run_script_file ~flags:cmake_flags
                       (Filename.concat dir (name ^ ".cmake")) in
    check_exit 0 ref_result;
    let cmake_text = compile_to_cmake yelu_prog in
    let yelu_result = run_script cmake_text in
    check_exit 0 yelu_result;
    if ref_result.stdout <> yelu_result.stdout then
      fail_mismatch ref_result yelu_result cmake_text;
    if do_tiny_check name then check_tiny_matches_ref name ref_result yelu_prog)

(** Reference is an inline cmake string. Use when the upstream RunCMake script
    produces no stdout (only FATAL_ERROR on failure) — write a minimal cmake
    that does the same operation and prints the result for comparison. *)
let check_pair_text name ref_cmake yelu_prog =
  Alcotest.test_case name `Quick (fun () ->
    let ref_result = run_script ref_cmake in
    check_exit 0 ref_result;
    let cmake_text = compile_to_cmake yelu_prog in
    let yelu_result = run_script cmake_text in
    check_exit 0 yelu_result;
    if ref_result.stdout <> yelu_result.stdout then
      fail_mismatch ref_result yelu_result cmake_text;
    if do_tiny_check name then check_tiny_matches_ref name ref_result yelu_prog)

(** Like check_pair_text but also compares stderr (with cmake filepath normalized).
    Use for negative-path tests that produce warnings/errors on stderr with no stdout. *)
let check_pair_text_stderr name ref_cmake yelu_prog =
  Alcotest.test_case name `Quick (fun () ->
    let ref_result = run_script ref_cmake in
    check_exit 0 ref_result;
    let cmake_text = compile_to_cmake yelu_prog in
    let yelu_result = run_script cmake_text in
    check_exit 0 yelu_result;
    if ref_result.stdout <> yelu_result.stdout then
      fail_mismatch ref_result yelu_result cmake_text;
    check_stderr_normalized ref_result yelu_result cmake_text;
    if do_tiny_check name then check_tiny_matches_ref name ref_result yelu_prog)

(* ==================================================================== *)
(* variable_watch                                                        *)
(* ==================================================================== *)

(* variable_watch(b) with no callback fires a cmake debug log to stderr,
   not stdout — both ref and yelu produce empty stdout, exit 0. *)
let vw_modified_access =
  Ystmt_list [
    yc_set (ycvar "b") [ystr "a"];
    yc_variable_watch (ycvar "b");
    yc_set (ycvar "b") [ystr "b"];
  ]

(* All callbacks are empty functions; registering watch inside a callback
   is allowed. No stdout output. *)
let vw_modify_watch_in_callback =
  Ystmt_list [
    yc_function (ystr "watch2") [] [];
    yc_function (ystr "watch1") [] [
      yc_variable_watch ~command:(Some "watch2") (ycvar "watched");
      yc_variable_watch ~command:(Some "watch2") (ycvar "watched");
      yc_variable_watch ~command:(Some "watch2") (ycvar "watched");
      yc_variable_watch ~command:(Some "watch2") (ycvar "watched");
      yc_variable_watch ~command:(Some "watch2") (ycvar "watched");
      yc_variable_watch ~command:(Some "watch2") (ycvar "watched");
    ];
    yc_variable_watch ~command:(Some "watch1") (ycvar "watched");
    yc_variable_watch ~command:(Some "watch2") (ycvar "watched");
    yc_set (ycvar "access") [ystr_eval "${watched}"];
  ]

let vw_no_watcher =
  Ystmt_list [
    yc_function (ystr "my_func") [] [ yc_message ~mode:Mm_none ["my_func"] ];
    yc_variable_watch ~command:(Some "my_func") (ycvar "a");
    yc_set (ycvar "a") [ystr ""];
    yc_variable_watch (ycvar "b");
    yc_set (ycvar "b") [ystr ""];
  ]

let vw_raise_in_parent_scope =
  Ystmt_list [
    yc_function (ystr "watch") ["variable"; "access"; "value"] [
      yc_message ~mode:Mm_none [ "${variable} ${access} ${value}" ]
    ];
    yc_variable_watch ~command:(Some "watch") (ycvar "var");
    yc_set (ycvar "var") [ystr "a"];
    yc_function (ystr "f") [] [
      yc_set ~parent_scope:true (ycvar "var") [ystr "b"]
    ];
    yc_language_call "f" [];
  ]

let vw_watch_twice =
  Ystmt_list [
    yc_function (ystr "watch1") [] [ yc_message ~mode:Mm_none ["From watch1"] ];
    yc_function (ystr "watch2") [] [ yc_message ~mode:Mm_none ["From watch2"] ];
    yc_variable_watch ~command:(Some "watch1") (ycvar "watched");
    yc_variable_watch ~command:(Some "watch2") (ycvar "watched");
    yc_set (ycvar "access") [ystr_eval "${watched}"];
  ]

(* ==================================================================== *)
(* cmake_path — inline pairs (upstream scripts have no stdout)          *)
(* Each pair: minimal cmake that prints the result + yelu equivalent.   *)
(* ==================================================================== *)

let cp_append_ref = {|
cmake_path(SET path "/a/b")
cmake_path(APPEND path "c")
message("${path}")
cmake_path(APPEND path "x/y" OUTPUT_VARIABLE out)
message("${out}")
|}

let cp_append_yelu =
  Ystmt_list [
    yc_path_set (ycvar "path") (ystr "/a/b");
    yc_path_append (ycvar "path") [ystr "c"];
    yc_message ~mode:Mm_none ["${path}"];
    yc_path_append ~out:(Some (ycvar "out")) (ycvar "path") [ystr "x/y"];
    yc_message ~mode:Mm_none ["${out}"];
  ]

let cp_normal_path_ref = {|
cmake_path(SET path "a/./b/../c")
cmake_path(NORMAL_PATH path)
message("${path}")
|}

let cp_normal_path_yelu =
  Ystmt_list [
    yc_path_set (ycvar "path") (ystr "a/./b/../c");
    yc_path_normal_path (ycvar "path");
    yc_message ~mode:Mm_none ["${path}"];
  ]

let cp_remove_filename_ref = {|
cmake_path(SET path "/a/b/c.txt")
cmake_path(REMOVE_FILENAME path)
message("${path}")
|}

let cp_remove_filename_yelu =
  Ystmt_list [
    yc_path_set (ycvar "path") (ystr "/a/b/c.txt");
    yc_path_remove_filename (ycvar "path");
    yc_message ~mode:Mm_none ["${path}"];
  ]

let cp_replace_extension_ref = {|
cmake_path(SET path "a/b/c.txt")
cmake_path(REPLACE_EXTENSION path ".md")
message("${path}")
|}

let cp_replace_extension_yelu =
  Ystmt_list [
    yc_path_set (ycvar "path") (ystr "a/b/c.txt");
    yc_path_replace_extension (ycvar "path") (ystr ".md");
    yc_message ~mode:Mm_none ["${path}"];
  ]

let cp_is_absolute_ref = {|
cmake_path(SET path "/a/b")
cmake_path(IS_ABSOLUTE path result)
message("${result}")
cmake_path(SET path "a/b")
cmake_path(IS_ABSOLUTE path result)
message("${result}")
|}

let cp_is_absolute_yelu =
  Ystmt_list [
    yc_path_set (ycvar "path") (ystr "/a/b");
    yc_path_is_absolute (ycvar "path") (ycvar "result");
    yc_message ~mode:Mm_none ["${result}"];
    yc_path_set (ycvar "path") (ystr "a/b");
    yc_path_is_absolute (ycvar "path") (ycvar "result");
    yc_message ~mode:Mm_none ["${result}"];
  ]

let cp_compare_ref = {|
cmake_path(COMPARE "/a/b" EQUAL "/a/b" result)
message("${result}")
cmake_path(COMPARE "/a/b" NOT_EQUAL "/a/c" result)
message("${result}")
|}

let cp_compare_yelu =
  Ystmt_list [
    yc_path_compare (ystr "/a/b") Cpco_equal (ystr "/a/b") (ycvar "result");
    yc_message ~mode:Mm_none ["${result}"];
    yc_path_compare (ystr "/a/b") Cpco_not_equal (ystr "/a/c") (ycvar "result");
    yc_message ~mode:Mm_none ["${result}"];
  ]

(* ==================================================================== *)
(* while                                                                *)
(* CMP0130-* scripts include a relative file — untractable outside      *)
(* RunCMake context. Use inline pairs testing while semantics directly. *)
(* ==================================================================== *)

(* Count from 0 to 2 with a while loop, print each value. *)
let while_counter_ref = {|
set(i 0)
while(i LESS 3)
  message("${i}")
  math(EXPR i "${i} + 1")
endwhile()
|}

let while_counter_yelu =
  Ystmt_list [
    yc_set (ycvar "i") [ystr "0"];
    yc_while (Yexpr_less (ystr_eval "${i}", ystr "3"))
      (Ystmt_list [
        yc_message ~mode:Mm_none ["${i}"];
        yc_math "${i} + 1" (ycvar "i");
      ]);
  ]

(* break exits the loop early. *)
let while_break_ref = {|
set(i 0)
while(i LESS 10)
  if(i EQUAL 3)
    break()
  endif()
  message("${i}")
  math(EXPR i "${i} + 1")
endwhile()
|}

let while_break_yelu =
  Ystmt_list [
    yc_set (ycvar "i") [ystr "0"];
    yc_while (Yexpr_less (ystr_eval "${i}", ystr "10"))
      (Ystmt_list [
        yifthen (ystrequal (ystr_eval "${i}") (ystr "3")) yc_break;
        yc_message ~mode:Mm_none ["${i}"];
        yc_math "${i} + 1" (ycvar "i");
      ]);
  ]

(* ==================================================================== *)
(* return                                                                *)
(* CMP0140 policy tests use cmake_policy not in yelu. Use inline pairs  *)
(* testing return() semantics: early exit and PROPAGATE.                *)
(* ==================================================================== *)

(* Early return from a function; code after return() is unreachable. *)
let return_early_ref = {|
function(f)
  message("before")
  return()
  message("unreachable")
endfunction()
f()
|}

let return_early_yelu =
  Ystmt_list [
    yc_function (ystr "f") [] [
      yc_message ~mode:Mm_none ["before"];
      yc_return ();
      yc_message ~mode:Mm_none ["unreachable"];
    ];
    yc_language_call "f" [];
  ]

(* return(PROPAGATE) with CMP0140 NEW: caller sees the updated variable. *)
let return_propagate_ref = {|
cmake_policy(SET CMP0140 NEW)
function(f)
  set(result "from_f")
  return(PROPAGATE result)
endfunction()
set(result "initial")
f()
message("${result}")
|}

let return_propagate_yelu =
  Ystmt_list [
    yc_language_eval "cmake_policy(SET CMP0140 NEW)";
    yc_function (ystr "f") [] [
      yc_set (ycvar "result") [ystr "from_f"];
      yc_return ~propogate_vars:["result"] ();
    ];
    yc_set (ycvar "result") [ystr "initial"];
    yc_language_call "f" [];
    yc_message ~mode:Mm_none ["${result}"];
  ]

(* ==================================================================== *)
(* option                                                                *)
(* CMP0077 tests use cmake_policy not in yelu. Use inline pairs testing *)
(* option() semantics: default value, override via set().               *)
(* ==================================================================== *)

(* Basic option with default OFF — value is accessible as a variable. *)
let option_default_ref = {|
option(MY_OPT "A test option" OFF)
if(MY_OPT)
  message("ON")
else()
  message("OFF")
endif()
|}

let option_default_yelu =
  Ystmt_list [
    yc_option ~msg:"A test option" (ycvar "MY_OPT");
    yif (ytruthy (ycstr "MY_OPT"))
      (yc_message ~mode:Mm_none ["ON"])
      (yc_message ~mode:Mm_none ["OFF"]);
  ]

(* option() respects a pre-existing normal variable (CMP0077 NEW default). *)
let option_respects_var_ref = {|
cmake_policy(SET CMP0077 NEW)
set(MY_OPT ON)
option(MY_OPT "A test option" OFF)
if(MY_OPT)
  message("ON")
else()
  message("OFF")
endif()
|}

let option_respects_var_yelu =
  Ystmt_list [
    yc_language_eval "cmake_policy(SET CMP0077 NEW)";
    yc_set (ycvar "MY_OPT") [ybool true];
    yc_option ~msg:"A test option" (ycvar "MY_OPT");
    yif (ytruthy (ycstr "MY_OPT"))
      (yc_message ~mode:Mm_none ["ON"])
      (yc_message ~mode:Mm_none ["OFF"]);
  ]

(* ==================================================================== *)
(* set                                                                  *)
(* ==================================================================== *)

(* set(VAR val PARENT_SCOPE) inside a function updates the caller's var. *)
let set_parent_pulling =
  Ystmt_list [
    yc_function (ystr "test_set") [] [
      yc_set (ycvar "blah") [ystr "value2"];
      yc_message ~mode:Mm_none ["before PARENT_SCOPE blah=${blah}"];
      yc_set ~parent_scope:true (ycvar "blah") [ystr_eval "${blah}"];
      yc_message ~mode:Mm_none ["after PARENT_SCOPE blah=${blah}"];
    ];
    yc_set (ycvar "blah") [ystr "value1"];
    yc_language_call "test_set" [];
    yc_message ~mode:Mm_none ["in parent scope, blah=${blah}"];
  ]

(* set(ENV{X}) / unset(ENV{X}) — DEFINED ENV{X} not in yelu cond types,
   so use an inline pair that prints the env var value directly. *)
let set_env_ref = {|
set(ENV{MY_VAR} "hello")
message("$ENV{MY_VAR}")
unset(ENV{MY_VAR})
message("${MY_VAR}")
|}

let set_env_yelu =
  Ystmt_list [
    yc_set_env "MY_VAR" (ystr "hello");
    yc_message ~mode:Mm_none ["$ENV{MY_VAR}"];
    yc_unset_env "MY_VAR";
    yc_message ~mode:Mm_none ["${MY_VAR}"];
  ]

(* ==================================================================== *)
(* cmake_path — remaining 12 inline pairs                               *)
(* ==================================================================== *)

let cp_set_ref = {|
cmake_path(SET path "/x/y/z")
message("${path}")
cmake_path(SET path NORMALIZE "/x/y/../z")
message("${path}")
|}
let cp_set_yelu =
  Ystmt_list [
    yc_path_set (ycvar "path") (ystr "/x/y/z");
    yc_message ~mode:Mm_none ["${path}"];
    yc_path_set ~normalize:true (ycvar "path") (ystr "/x/y/../z");
    yc_message ~mode:Mm_none ["${path}"];
  ]

let cp_absolute_path_ref = {|
cmake_path(SET path "../../a/d")
cmake_path(ABSOLUTE_PATH path BASE_DIRECTORY "/x/y/a/f" OUTPUT_VARIABLE out)
message("${out}")
cmake_path(ABSOLUTE_PATH path BASE_DIRECTORY "/x/y/a/f" NORMALIZE OUTPUT_VARIABLE out)
message("${out}")
|}
let cp_absolute_path_yelu =
  Ystmt_list [
    yc_path_set (ycvar "path") (ystr "../../a/d");
    yc_path_absolute_path ~base_dir:(Some (ystr "/x/y/a/f"))
      ~out:(Some (ycvar "out")) (ycvar "path");
    yc_message ~mode:Mm_none ["${out}"];
    yc_path_absolute_path ~base_dir:(Some (ystr "/x/y/a/f"))
      ~normalize:true ~out:(Some (ycvar "out")) (ycvar "path");
    yc_message ~mode:Mm_none ["${out}"];
  ]

let cp_append_string_ref = {|
cmake_path(SET path "/a/b")
cmake_path(APPEND_STRING path "cd" OUTPUT_VARIABLE out)
message("${out}")
|}
let cp_append_string_yelu =
  Ystmt_list [
    yc_path_set (ycvar "path") (ystr "/a/b");
    yc_path_append_string ~out:(Some (ycvar "out")) (ycvar "path") [ystr "cd"];
    yc_message ~mode:Mm_none ["${out}"];
  ]

let cp_is_relative_ref = {|
cmake_path(SET path "a/b")
cmake_path(IS_RELATIVE path out)
message("${out}")
cmake_path(SET path "/a/b")
cmake_path(IS_RELATIVE path out)
message("${out}")
|}
let cp_is_relative_yelu =
  Ystmt_list [
    yc_path_set (ycvar "path") (ystr "a/b");
    yc_path_is_relative (ycvar "path") (ycvar "out");
    yc_message ~mode:Mm_none ["${out}"];
    yc_path_set (ycvar "path") (ystr "/a/b");
    yc_path_is_relative (ycvar "path") (ycvar "out");
    yc_message ~mode:Mm_none ["${out}"];
  ]

let cp_is_prefix_ref = {|
cmake_path(SET path "a/b/c")
cmake_path(IS_PREFIX path "a/b/c/d" out)
message("${out}")
cmake_path(SET path "a/b/c/../d")
cmake_path(IS_PREFIX path "a/b/d/e" NORMALIZE out)
message("${out}")
|}
let cp_is_prefix_yelu =
  Ystmt_list [
    yc_path_set (ycvar "path") (ystr "a/b/c");
    yc_path_is_prefix (ycvar "path") (ystr "a/b/c/d") (ycvar "out");
    yc_message ~mode:Mm_none ["${out}"];
    yc_path_set (ycvar "path") (ystr "a/b/c/../d");
    yc_path_is_prefix ~normalize:true (ycvar "path") (ystr "a/b/d/e") (ycvar "out");
    yc_message ~mode:Mm_none ["${out}"];
  ]

let cp_has_item_ref = {|
cmake_path(SET path "/a/b/c.txt")
cmake_path(HAS_ROOT_DIRECTORY path out)
message("${out}")
cmake_path(HAS_FILENAME path out)
message("${out}")
cmake_path(HAS_EXTENSION path out)
message("${out}")
cmake_path(SET path "a/b")
cmake_path(HAS_ROOT_DIRECTORY path out)
message("${out}")
|}
let cp_has_item_yelu =
  Ystmt_list [
    yc_path_set (ycvar "path") (ystr "/a/b/c.txt");
    yc_path_has (ycvar "path") Cph_root_directory (ycvar "out");
    yc_message ~mode:Mm_none ["${out}"];
    yc_path_has (ycvar "path") Cph_filename (ycvar "out");
    yc_message ~mode:Mm_none ["${out}"];
    yc_path_has (ycvar "path") Cph_extension (ycvar "out");
    yc_message ~mode:Mm_none ["${out}"];
    yc_path_set (ycvar "path") (ystr "a/b");
    yc_path_has (ycvar "path") Cph_root_directory (ycvar "out");
    yc_message ~mode:Mm_none ["${out}"];
  ]

(* HASH: two normalized-equivalent paths produce the same hash. *)
let cp_hash_ref = {|
cmake_path(SET path1 "a/b/c")
cmake_path(SET path2 "a/b////c")
cmake_path(HASH path1 h1)
cmake_path(HASH path2 h2)
if(h1 STREQUAL h2)
  message("equal")
else()
  message("not equal: ${h1} vs ${h2}")
endif()
|}
let cp_hash_yelu =
  Ystmt_list [
    yc_path_set (ycvar "path1") (ystr "a/b/c");
    yc_path_set (ycvar "path2") (ystr "a/b////c");
    yc_path_hash (ycvar "path1") (ycvar "h1");
    yc_path_hash (ycvar "path2") (ycvar "h2");
    yif (ystrequal (ystr_eval "${h1}") (ystr_eval "${h2}"))
      (yc_message ~mode:Mm_none ["equal"])
      (yc_message ~mode:Mm_none ["not equal: ${h1} vs ${h2}"]);
  ]

let cp_relative_path_ref = {|
cmake_path(SET path "/a/d")
cmake_path(RELATIVE_PATH path BASE_DIRECTORY "/a/b/c" OUTPUT_VARIABLE out)
message("${out}")
cmake_path(SET path "a/b/c")
cmake_path(RELATIVE_PATH path BASE_DIRECTORY "a" OUTPUT_VARIABLE out)
message("${out}")
|}
let cp_relative_path_yelu =
  Ystmt_list [
    yc_path_set (ycvar "path") (ystr "/a/d");
    yc_path_relative_path ~base_dir:(Some (ystr "/a/b/c"))
      ~out:(Some (ycvar "out")) (ycvar "path");
    yc_message ~mode:Mm_none ["${out}"];
    yc_path_set (ycvar "path") (ystr "a/b/c");
    yc_path_relative_path ~base_dir:(Some (ystr "a"))
      ~out:(Some (ycvar "out")) (ycvar "path");
    yc_message ~mode:Mm_none ["${out}"];
  ]

let cp_remove_extension_ref = {|
cmake_path(SET path "a/b/c.e.f")
cmake_path(REMOVE_EXTENSION path OUTPUT_VARIABLE out)
message("${out}")
cmake_path(SET path "a/b/c.e.f")
cmake_path(REMOVE_EXTENSION path LAST_ONLY OUTPUT_VARIABLE out)
message("${out}")
|}
let cp_remove_extension_yelu =
  Ystmt_list [
    yc_path_set (ycvar "path") (ystr "a/b/c.e.f");
    yc_path_remove_extension ~out:(Some (ycvar "out")) (ycvar "path");
    yc_message ~mode:Mm_none ["${out}"];
    yc_path_set (ycvar "path") (ystr "a/b/c.e.f");
    yc_path_remove_extension ~last_only:true ~out:(Some (ycvar "out")) (ycvar "path");
    yc_message ~mode:Mm_none ["${out}"];
  ]

let cp_replace_filename_ref = {|
cmake_path(SET path "a/b/c.e.f")
cmake_path(REPLACE_FILENAME path "x.y" OUTPUT_VARIABLE out)
message("${out}")
|}
let cp_replace_filename_yelu =
  Ystmt_list [
    yc_path_set (ycvar "path") (ystr "a/b/c.e.f");
    yc_path_replace_filename ~out:(Some (ycvar "out")) (ycvar "path") (ystr "x.y");
    yc_message ~mode:Mm_none ["${out}"];
  ]

(* CONVERT: on Linux TO_CMAKE_PATH_LIST is identity (no backslash conversion). *)
let cp_convert_ref = {|
cmake_path(CONVERT "/a/b/c" TO_CMAKE_PATH_LIST out)
message("${out}")
cmake_path(CONVERT "/x/y/../z" TO_CMAKE_PATH_LIST out NORMALIZE)
message("${out}")
|}
let cp_convert_yelu =
  Ystmt_list [
    yc_path_convert_to_cmake (ystr "/a/b/c") (ycvar "out");
    yc_message ~mode:Mm_none ["${out}"];
    yc_path_convert_to_cmake ~normalize:true (ystr "/x/y/../z") (ycvar "out");
    yc_message ~mode:Mm_none ["${out}"];
  ]

(* NATIVE_PATH: on Linux identical to input path (no backslash conversion). *)
let cp_native_path_ref = {|
cmake_path(SET path "/a/b/c")
cmake_path(NATIVE_PATH path out)
message("${out}")
|}
let cp_native_path_yelu =
  Ystmt_list [
    yc_path_set (ycvar "path") (ystr "/a/b/c");
    yc_path_native_path (ycvar "path") (ycvar "out");
    yc_message ~mode:Mm_none ["${out}"];
  ]

(* ==================================================================== *)
(* math                                                                 *)
(* ==================================================================== *)

(* Basic math operations with DECIMAL and HEXADECIMAL output format. *)
let math_ops_ref = {|
math(EXPR r "100 * 10")
message("${r}")
math(EXPR r "0xFF" OUTPUT_FORMAT DECIMAL)
message("${r}")
math(EXPR r "255" OUTPUT_FORMAT HEXADECIMAL)
message("${r}")
|}

let math_ops_yelu =
  Ystmt_list [
    yc_math "100 * 10" (ycvar "r");
    yc_message ~mode:Mm_none ["${r}"];
    yc_math "0xFF" (ycvar "r");
    yc_message ~mode:Mm_none ["${r}"];
    yc_math ~output_format:Hexdecimal "255" (ycvar "r");
    yc_message ~mode:Mm_none ["${r}"];
  ]

(* foreach + math: iterate expressions, evaluate and print each result. *)
let math_overflow_yelu =
  Ystmt_list [
    yc_foreach_in ~items:[
      ystr "-4 <<   1";
      ystr "-4 >>   1";
      ystr " 4 << -63";
      ystr " 4 >> -63";
      ystr " 4 <<  65";
      ystr " 4 >>  65";
      ystr " 0x7FFFFFFFFFFFFFFF + 1";
      ystr "-0x7FFFFFFFFFFFFFFF - 2";
      ystr " 0x7FFFFFFFFFFFFFFF * 2";
      ystr "-~0x7FFFFFFFFFFFFFFF";
    ] (ycvar "expr") (Ystmt_list [
      yc_math "${expr}" (ycvar "result");
      yc_message ~mode:Mm_status ["${expr}: ${result}"];
    ]);
  ]

(* ==================================================================== *)
(* list                                                                 *)
(* ==================================================================== *)

let list_join_ref = {|
set(myList a b c)
list(JOIN myList , out)
message("${out}")
|}

let list_join_yelu =
  Ystmt_list [
    yc_list_append (ycvar "myList") [ystr "a"; ystr "b"; ystr "c"];
    yc_list_join (ycvar "myList") (ystr ",") (ycvar "out");
    yc_message ~mode:Mm_none ["${out}"];
  ]

let list_sort_ref = {|
set(myList c a b)
list(SORT myList)
message("${myList}")
|}

let list_sort_yelu =
  Ystmt_list [
    yc_list_append (ycvar "myList") [ystr "c"; ystr "a"; ystr "b"];
    yc_list_sort (ycvar "myList");
    yc_message ~mode:Mm_none ["${myList}"];
  ]

let list_pop_back_ref = {|
set(myList a b c)
list(POP_BACK myList popped)
message("${popped}")
message("${myList}")
|}

let list_pop_back_yelu =
  Ystmt_list [
    yc_list_append (ycvar "myList") [ystr "a"; ystr "b"; ystr "c"];
    yc_list_pop_back ~out_vars:[ycvar "popped"] (ycvar "myList");
    yc_message ~mode:Mm_none ["${popped}"];
    yc_message ~mode:Mm_none ["${myList}"];
  ]

let list_pop_front_ref = {|
set(myList a b c)
list(POP_FRONT myList popped)
message("${popped}")
message("${myList}")
|}

let list_pop_front_yelu =
  Ystmt_list [
    yc_list_append (ycvar "myList") [ystr "a"; ystr "b"; ystr "c"];
    yc_list_pop_front ~out_vars:[ycvar "popped"] (ycvar "myList");
    yc_message ~mode:Mm_none ["${popped}"];
    yc_message ~mode:Mm_none ["${myList}"];
  ]

let list_prepend_ref = {|
set(myList a b)
list(PREPEND myList x)
message("${myList}")
|}

let list_prepend_yelu =
  Ystmt_list [
    yc_list_append (ycvar "myList") [ystr "a"; ystr "b"];
    yc_list_prepend (ycvar "myList") [ystr "x"];
    yc_message ~mode:Mm_none ["${myList}"];
  ]

(* ==================================================================== *)
(* string                                                               *)
(* ==================================================================== *)

let string_concat_ref = {|
string(CONCAT out "hello" " " "world")
message("${out}")
|}

let string_concat_yelu =
  Ystmt_list [
    yc_string_concat (ycvar "out") [ystr "hello"; ystr " "; ystr "world"];
    yc_message ~mode:Mm_none ["${out}"];
  ]

let string_append_ref = {|
set(out "hello")
string(APPEND out " world")
message("${out}")
|}

let string_append_yelu =
  Ystmt_list [
    yc_set (ycvar "out") [ystr "hello"];
    yc_string_append (ycvar "out") [ystr " world"];
    yc_message ~mode:Mm_none ["${out}"];
  ]

let string_join_ref = {|
string(JOIN , out a b c)
message("${out}")
|}

let string_join_yelu =
  Ystmt_list [
    yc_string_join (ystr ",") (ycvar "out") [ystr "a"; ystr "b"; ystr "c"];
    yc_message ~mode:Mm_none ["${out}"];
  ]

let string_hex_ref = {|
string(HEX "hello" out)
message("${out}")
|}

let string_hex_yelu =
  Ystmt_list [
    yc_string_hex (ystr "hello") (ycvar "out");
    yc_message ~mode:Mm_none ["${out}"];
  ]

let string_uuid_ref = {|
string(UUID out NAMESPACE 6ba7b810-9dad-11d1-80b4-00c04fd430c8 NAME www.example.com TYPE MD5)
message("${out}")
|}

let string_uuid_yelu =
  Ystmt_list [
    yc_string_uuid
      ~namespace:"6ba7b810-9dad-11d1-80b4-00c04fd430c8"
      ~name:"www.example.com"
      ~type_:`Md5
      (ycvar "out");
    yc_message ~mode:Mm_none ["${out}"];
  ]

let string_repeat_ref = {|
string(REPEAT "ab" 3 out)
message("${out}")
|}

let string_repeat_yelu =
  Ystmt_list [
    yc_string_repeat (ystr "ab") 3 (ycvar "out");
    yc_message ~mode:Mm_none ["${out}"];
  ]

(* ==================================================================== *)
(* foreach — inline pairs (upstream script uses ITEMS/LISTS ordering   *)
(* not supported by PP, and CMAKE_MESSAGE_INDENT manipulations)        *)
(* ==================================================================== *)

let foreach_range_ref = {|
foreach(i RANGE 3)
  message(STATUS "${i}")
endforeach()
|}

let foreach_range_yelu =
  Ystmt_list [
    yc_foreach_range ~stop:3 (ycvar "i") (yc_message ~mode:Mm_status ["${i}"]);
  ]

let foreach_in_ref = {|
set(myList satu dua tiga)
foreach(i IN LISTS myList ITEMS one two)
  message(STATUS "${i}")
endforeach()
|}

let foreach_in_yelu =
  Ystmt_list [
    yc_list_append (ycvar "myList") [ystr "satu"; ystr "dua"; ystr "tiga"];
    yc_foreach_in ~lists:[ycvar "myList"] ~items:[ystr "one"; ystr "two"] (ycvar "i")
      (yc_message ~mode:Mm_status ["${i}"]);
  ]

(* ==================================================================== *)
(* message                                                              *)
(* ==================================================================== *)

(* message() with newline escape in the text. *)
let message_newline_ref = {|
message("line1\nline2")
|}

let message_newline_yelu =
  Ystmt_list [
    yc_message ~mode:Mm_none ["line1\nline2"];
  ]

(* CMAKE_MESSAGE_INDENT controls the indent prefix for STATUS messages. *)
let message_indent_ref = {|
list(APPEND CMAKE_MESSAGE_INDENT "  ")
message(STATUS "level1")
list(APPEND CMAKE_MESSAGE_INDENT "  ")
message(STATUS "level2")
list(POP_BACK CMAKE_MESSAGE_INDENT)
message(STATUS "back to level1")
list(POP_BACK CMAKE_MESSAGE_INDENT)
message(STATUS "no indent")
|}

let message_indent_yelu =
  Ystmt_list [
    yc_list_append (ycvar "CMAKE_MESSAGE_INDENT") [ystr "  "];
    yc_message ~mode:Mm_status ["level1"];
    yc_list_append (ycvar "CMAKE_MESSAGE_INDENT") [ystr "  "];
    yc_message ~mode:Mm_status ["level2"];
    yc_list_pop_back (ycvar "CMAKE_MESSAGE_INDENT");
    yc_message ~mode:Mm_status ["back to level1"];
    yc_list_pop_back (ycvar "CMAKE_MESSAGE_INDENT");
    yc_message ~mode:Mm_status ["no indent"];
  ]

(* ==================================================================== *)
(* include                                                              *)
(* ==================================================================== *)

let include_empty_ref = {|include("")|}
let include_empty_yelu = yc_include (ystr "")

let include_empty_optional_ref = {|include("" OPTIONAL)|}
let include_empty_optional_yelu = yc_include ~optional:true (ystr "")

let () =
  Alcotest.run "RunCMake yelu pairs"
    [ ("variable_watch", [
        check_pair "ModifiedAccess"       (script_dir "variable_watch") vw_modified_access;
        check_pair "ModifyWatchInCallback"(script_dir "variable_watch") vw_modify_watch_in_callback;
        check_pair "NoWatcher"            (script_dir "variable_watch") vw_no_watcher;
        check_pair "RaiseInParentScope"   (script_dir "variable_watch") vw_raise_in_parent_scope;
        check_pair "WatchTwice"           (script_dir "variable_watch") vw_watch_twice;
      ]);
      ("cmake_path", [
        check_pair_text "APPEND"            cp_append_ref            cp_append_yelu;
        check_pair_text "NORMAL_PATH"       cp_normal_path_ref       cp_normal_path_yelu;
        check_pair_text "REMOVE_FILENAME"   cp_remove_filename_ref   cp_remove_filename_yelu;
        check_pair_text "REPLACE_EXTENSION" cp_replace_extension_ref cp_replace_extension_yelu;
        check_pair_text "IS_ABSOLUTE"       cp_is_absolute_ref       cp_is_absolute_yelu;
        check_pair_text "COMPARE"           cp_compare_ref           cp_compare_yelu;
        check_pair_text "SET"               cp_set_ref               cp_set_yelu;
        check_pair_text "ABSOLUTE_PATH"     cp_absolute_path_ref     cp_absolute_path_yelu;
        check_pair_text "APPEND_STRING"     cp_append_string_ref     cp_append_string_yelu;
        check_pair_text "IS_RELATIVE"       cp_is_relative_ref       cp_is_relative_yelu;
        check_pair_text "IS_PREFIX"         cp_is_prefix_ref         cp_is_prefix_yelu;
        check_pair_text "HAS_ITEM"          cp_has_item_ref          cp_has_item_yelu;
        check_pair_text "HASH"              cp_hash_ref              cp_hash_yelu;
        check_pair_text "RELATIVE_PATH"     cp_relative_path_ref     cp_relative_path_yelu;
        check_pair_text "REMOVE_EXTENSION"  cp_remove_extension_ref  cp_remove_extension_yelu;
        check_pair_text "REPLACE_FILENAME"  cp_replace_filename_ref  cp_replace_filename_yelu;
        check_pair_text "CONVERT"           cp_convert_ref           cp_convert_yelu;
        check_pair_text "NATIVE_PATH"       cp_native_path_ref       cp_native_path_yelu;
      ]);
      ("while", [
        check_pair_text "counter" while_counter_ref while_counter_yelu;
        check_pair_text "break"   while_break_ref   while_break_yelu;
      ]);
      ("return", [
        check_pair_text "early"     return_early_ref     return_early_yelu;
        check_pair_text "propagate" return_propagate_ref return_propagate_yelu;
      ]);
      ("option", [
        check_pair_text "default"      option_default_ref      option_default_yelu;
        check_pair_text "respects_var" option_respects_var_ref option_respects_var_yelu;
      ]);
      ("set", [
        check_pair      "ParentPulling" (script_dir "set") set_parent_pulling;
        check_pair_text "env"           set_env_ref         set_env_yelu;
      ]);
      ("math", [
        check_pair_text "ops"      math_ops_ref      math_ops_yelu;
        check_pair      "Overflow" (script_dir "math") math_overflow_yelu;
      ]);
      ("list", [
        check_pair_text "JOIN"      list_join_ref      list_join_yelu;
        check_pair_text "SORT"      list_sort_ref      list_sort_yelu;
        check_pair_text "POP_BACK"  list_pop_back_ref  list_pop_back_yelu;
        check_pair_text "POP_FRONT" list_pop_front_ref list_pop_front_yelu;
        check_pair_text "PREPEND"   list_prepend_ref   list_prepend_yelu;
      ]);
      ("string", [
        check_pair_text "Concat" string_concat_ref string_concat_yelu;
        check_pair_text "Append" string_append_ref string_append_yelu;
        check_pair_text "Join"   string_join_ref   string_join_yelu;
        check_pair_text "Hex"    string_hex_ref    string_hex_yelu;
        check_pair_text "Uuid"   string_uuid_ref   string_uuid_yelu;
        check_pair_text "Repeat" string_repeat_ref string_repeat_yelu;
      ]);
      ("foreach", [
        check_pair_text "range"   foreach_range_ref   foreach_range_yelu;
        check_pair_text "in"      foreach_in_ref      foreach_in_yelu;
      ]);
      ("message", [
        check_pair_text "newline" message_newline_ref message_newline_yelu;
        check_pair_text "indent"  message_indent_ref  message_indent_yelu;
      ]);
      ("include", [
        check_pair_text_stderr "EmptyString"         include_empty_ref          include_empty_yelu;
        check_pair_text_stderr "EmptyStringOptional" include_empty_optional_ref include_empty_optional_yelu;
      ]);
    ]
