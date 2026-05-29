(** Configure-mode tests: compile yelu → cmake text → cmake -S -B → check cache/stdout.
    Uses run_configure from cmake_runner. *)

open Yelu_langs.Lang_cmake
open Yelu_langs.Yelu_cmake
open Yelu_langs.Yelu_cmake_utils
open Yelu_langs.Lang_cmake_pp
open Yelu_runner.Cmake_runner

let compile exp =
  Fmt.str "%a" (Fmt.vbox pp) (Yelu_langs.Yelu_cmake_emit.emit_ast exp)

let check_conf name prog f =
  Alcotest.test_case name `Quick (fun () ->
      let result = run_configure (compile prog) in
      if result.run.exit_code <> 0 then
        Alcotest.failf "cmake exited %d\nstderr:\n%s" result.run.exit_code result.run.stderr;
      f result)

(* set(VAR val CACHE STRING "doc") → cache entry visible in CMakeCache.txt *)
let cache_string =
  check_conf "cache_string"
    (yc_set_cache ~cache_type:Ct_string ~docstring:"test" (ycvar "MY_STR") [ystr "hello"])
    (fun r -> check_cache "MY_STR" "hello" r)

(* set(VAR ON CACHE BOOL "doc") → cache bool *)
let cache_bool =
  check_conf "cache_bool"
    (yc_set_cache ~cache_type:Ct_bool ~docstring:"test" (ycvar "MY_FLAG") [ybool true])
    (fun r -> check_cache "MY_FLAG" "ON" r)

(* option(MY_OPT "desc" ON) → CACHE BOOL, first-write-wins *)
let cache_option =
  check_conf "cache_option"
    (yc_option ~value:(ybool true) ~msg:"an option" (ycvar "MY_OPT"))
    (fun r -> check_cache "MY_OPT" "ON" r)

(* message(STATUS ...) → captured in stdout *)
let message_to_stdout =
  check_conf "message_stdout"
    (yc_message ~mode:Mm_status ["configure says hello"])
    (fun r -> check_stdout_matches "configure says hello" r.run)

(* cmake_path GET FILENAME — configure-mode value check via message *)
let cmake_path_get =
  check_conf "cmake_path_get"
    (ESeq [
      yc_path_set (ycvar "P") (ystr "/usr/local/bin/cmake");
      yc_path_get (ycvar "P") Cpf_filename (ycvar "FNAME");
      yc_message ~mode:Mm_status ["${FNAME}"];
    ])
    (fun r -> check_stdout_matches "cmake" r.run)

let pass_c   = "int main(void) { return 0; }"
let fail_c   = "#error forced failure\nint main(void) { return 1; }"
let c99_src  = "#include <stdbool.h>\nint main(void) { _Bool x = 1; return 0; }"
let cxx11_src = "#include <vector>\nint main() { auto v = std::vector<int>{1,2,3}; return 0; }"

let check_conf_c name prog f =
  Alcotest.test_case name `Quick (fun () ->
      let result = run_configure ~languages:["C"] ~files:[("pass.c", pass_c); ("fail.c", fail_c)]
                     (compile prog) in
      if result.run.exit_code <> 0 then
        Alcotest.failf "cmake exited %d\nstderr:\n%s" result.run.exit_code result.run.stderr;
      f result)

let check_conf_c_files files name prog f =
  Alcotest.test_case name `Quick (fun () ->
      let result = run_configure ~languages:["C"] ~files (compile prog) in
      if result.run.exit_code <> 0 then
        Alcotest.failf "cmake exited %d\nstderr:\n%s" result.run.exit_code result.run.stderr;
      f result)

let check_conf_cxx_files files name prog f =
  Alcotest.test_case name `Quick (fun () ->
      let result = run_configure ~languages:["CXX"] ~files (compile prog) in
      if result.run.exit_code <> 0 then
        Alcotest.failf "cmake exited %d\nstderr:\n%s" result.run.exit_code result.run.stderr;
      f result)

let src name = ystr_eval ("${CMAKE_CURRENT_SOURCE_DIR}/" ^ name)

(* try_compile on a valid C source → RESULT = 1 (true) in cache *)
let try_compile_pass =
  check_conf_c "try_compile_pass"
    (yc_try_compile ~no_cache:false (ycvar "RESULT") [src "pass.c"])
    (fun r -> check_cache "RESULT" "TRUE" r)

(* try_compile on a source with #error → RESULT = FALSE in cache *)
let try_compile_fail =
  check_conf_c "try_compile_fail"
    (yc_try_compile ~no_cache:false (ycvar "RESULT") [src "fail.c"])
    (fun r -> check_cache "RESULT" "FALSE" r)

(* try_compile with OUTPUT_VARIABLE captures compiler output *)
let try_compile_output =
  check_conf_c "try_compile_output"
    (ESeq [
      yc_try_compile ~no_cache:true ~output_variable:(Some (ycvar "OUT"))
        (ycvar "RESULT") [src "pass.c"];
      yc_message ~mode:Mm_status ["${RESULT}"];
    ])
    (fun r -> check_stdout_matches "1" r.run)

(* try_compile with C_STANDARD 99 — stdbool.h requires C99 *)
let try_compile_c_standard =
  check_conf_c_files [("c99.c", c99_src)] "try_compile_c_standard"
    (yc_try_compile ~no_cache:false ~c_standard:(Some "99")
       (ycvar "RESULT") [src "c99.c"])
    (fun r -> check_cache "RESULT" "TRUE" r)

(* try_compile with CXX_STANDARD 11 — initializer list requires C++11 *)
let try_compile_cxx_standard =
  check_conf_cxx_files [("cxx11.cpp", cxx11_src)] "try_compile_cxx_standard"
    (yc_try_compile ~no_cache:false ~cxx_standard:(Some "11")
       (ycvar "RESULT") [src "cxx11.cpp"])
    (fun r -> check_cache "RESULT" "TRUE" r)

(* set_property(GLOBAL PROPERTY ...) + get_property(GLOBAL ...) round-trip *)
let prop_global_roundtrip =
  check_conf "prop_global_roundtrip"
    (ESeq [
      yc_set_global_property [("MY_GLOBAL_PROP", ystr "globalval")];
      yc_get_global_property ~property:"MY_GLOBAL_PROP" (ycvar "OUT");
      yc_message ~mode:Mm_status ["${OUT}"];
    ])
    (fun r -> check_stdout_matches "globalval" r.run)

(* set_target_properties + get_target_property round-trip via custom target *)
let prop_target_roundtrip =
  check_conf "prop_target_roundtrip"
    (ESeq [
      yc_add_custom_target "mytarget";
      yc_set_target_properties (ytval "mytarget") [("MY_PROP", ystr "myval")];
      yc_get_target_property (ycvar "OUT") "mytarget" "MY_PROP";
      yc_message ~mode:Mm_status ["${OUT}"];
    ])
    (fun r -> check_stdout_matches "myval" r.run)

(* set_property(TARGET ...) + get_target_property round-trip *)
let prop_target_set_property =
  check_conf "prop_target_set_property"
    (ESeq [
      yc_add_custom_target "t2";
      yc_set_property ~targets:[ytval "t2"] [("CUSTOM_PROP", ystr "custom")];
      yc_get_target_property (ycvar "OUT") "t2" "CUSTOM_PROP";
      yc_message ~mode:Mm_status ["${OUT}"];
    ])
    (fun r -> check_stdout_matches "custom" r.run)

(* define_property GLOBAL + set + get round-trip *)
let define_property_global =
  check_conf "define_property_global"
    (ESeq [
      yc_define_property ~brief_docs:["my prop"] Dp_global "MY_DEFINED_PROP";
      yc_set_global_property [("MY_DEFINED_PROP", ystr "defined_val")];
      yc_get_global_property ~property:"MY_DEFINED_PROP" (ycvar "OUT");
      yc_message ~mode:Mm_status ["${OUT}"];
    ])
    (fun r -> check_stdout_matches "defined_val" r.run)

(* define_property TARGET + set_target_properties + get_target_property round-trip *)
let define_property_target =
  check_conf "define_property_target"
    (ESeq [
      yc_define_property ~brief_docs:["target prop"] Dp_target "MY_TARGET_PROP";
      yc_add_custom_target "tprop_target";
      yc_set_target_properties (ytval "tprop_target") [("MY_TARGET_PROP", ystr "tval")];
      yc_get_target_property (ycvar "OUT") "tprop_target" "MY_TARGET_PROP";
      yc_message ~mode:Mm_status ["${OUT}"];
    ])
    (fun r -> check_stdout_matches "tval" r.run)

let () =
  Alcotest.run "configure"
    [ ("cache",       [ cache_string; cache_bool; cache_option ]);
      ("message",     [ message_to_stdout ]);
      ("cmake_path",  [ cmake_path_get ]);
      ("try_compile", [ try_compile_pass; try_compile_fail; try_compile_output;
                        try_compile_c_standard; try_compile_cxx_standard ]);
      ("property",    [ prop_global_roundtrip; prop_target_roundtrip;
                        prop_target_set_property ]);
      ("define_property", [ define_property_global; define_property_target ]);
      ("target_precompile_headers", [
        Alcotest.test_case "pch_private" `Quick (fun () ->
          let result = run_configure ~languages:["C"]
            ~files:[("pch_src.c", "int pch_fn(void) { return 0; }")]
            (compile (ESeq [
              add_lib ~type_:Lib_static ~sources:[src "pch_src.c"] (ytval "pchlib");
              yc_target_precompile_headers (ytval "pchlib")
                [ytarget_def ~kind:Private [yname "<stdio.h>"]];
              yc_message ~mode:Mm_status ["pch ok"];
            ])) in
          if result.run.exit_code <> 0 then
            Alcotest.failf "cmake exited %d\nstderr:\n%s" result.run.exit_code result.run.stderr;
          check_stdout_matches "pch ok" result.run);
        Alcotest.test_case "pch_interface" `Quick (fun () ->
          let result = run_configure ~languages:["C"]
            ~files:[("iface_src.c", "int iface_fn(void) { return 0; }")]
            (compile (ESeq [
              add_lib ~type_:Lib_interface (ytval "ifacelib");
              yc_target_precompile_headers (ytval "ifacelib")
                [ytarget_def ~kind:Interface [yname "<stdlib.h>"]];
              yc_message ~mode:Mm_status ["iface pch ok"];
            ])) in
          if result.run.exit_code <> 0 then
            Alcotest.failf "cmake exited %d\nstderr:\n%s" result.run.exit_code result.run.stderr;
          check_stdout_matches "iface pch ok" result.run) ]);
      ("add_dependencies", [
        check_conf "add_dependencies_basic"
          (ESeq [
            yc_add_custom_target "dep_a";
            yc_add_custom_target "dep_b";
            yc_add_dependencies "dep_b" [ "dep_a" ];
            yc_message ~mode:Mm_status ["deps ok"];
          ])
          (fun r -> check_stdout_matches "deps ok" r.run) ]);
      ("block", [
        check_conf "block_body_executes"
          (ESeq [
            yc_block [yc_message ~mode:Mm_status ["inside block"]];
          ])
          (fun r -> check_stdout_matches "inside block" r.run) ]);
      ("cmake_language", [
        check_conf "cmake_language_call"
          (ESeq [
            yc_macro (ystr "say_hi") [
              yc_message ~mode:Mm_status ["hi from macro"]
            ];
            yc_language_call "say_hi" [];
          ])
          (fun r -> check_stdout_matches "hi from macro" r.run);
        check_conf "cmake_language_eval"
          (yc_language_eval {|message(STATUS "eval says hello")|})
          (fun r -> check_stdout_matches "eval says hello" r.run);
        check_conf "cmake_language_get_log_level"
          (ESeq [
            yc_language_get_log_level (ycvar "LOG_LEVEL");
            yc_message ~mode:Mm_status ["${LOG_LEVEL}"];
          ])
          (fun r ->
            if String.length r.run.stdout = 0 then
              Alcotest.fail "expected non-empty LOG_LEVEL output") ]);
      ("variable_watch", [
        check_conf "variable_watch_triggers"
          (ESeq [
            yc_set_cache ~cache_type:Ct_string ~docstring:"" (ycvar "WATCHED") [ystr "initial"];
            yc_variable_watch (ycvar "WATCHED");
            yc_message ~mode:Mm_status ["${WATCHED}"];
          ])
          (fun r -> check_stdout_matches "initial" r.run) ]);
    ]
