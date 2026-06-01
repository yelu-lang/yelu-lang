open Base
open Yelu_langs.Yelu_cmake
open Yelu_langs.Yelu_cmake_convert

let target
      ?(kind = TargetExecutable)
      ?(sources = [])
      ?(link_libraries = [])
      ?(include_directories = [])
      ?(compile_definitions = [])
      ?(compile_options = [])
      ?(compile_features = [])
      ?(link_options = [])
      ?(link_directories = [])
      name =
  {
    name;
    kind;
    sources;
    link_libraries;
    include_directories;
    compile_definitions;
    compile_options;
    compile_features;
    link_options;
    link_directories;
  }

let env_of_bindings
      ?(files = [])
      ?(targets = [])
      ?(custom_targets = [])
      ?(custom_commands = [])
      ?(install_rules = [])
      ?project
      ?cmake_min_version
      ?(messages = [])
      ?(subdirectories = [])
      ?(testing_enabled = false)
      ?(tests = [])
      ?(target_properties = [])
      ?(find_packages = [])
      ?(try_compiles = [])
      ?(functions = [])
      bindings =
  let env =
    List.fold bindings ~init:empty_env ~f:(fun env (key, data) ->
      set_var env ~key ~data)
  in
  let env =
    List.fold files ~init:env ~f:(fun env (path, content) ->
      set_file env ~path ~content)
  in
  let env = List.fold targets ~init:env ~f:set_target in
  let env = List.fold custom_targets ~init:env ~f:set_custom_target in
  let env = List.fold custom_commands ~init:env ~f:set_custom_command in
  let env = List.fold install_rules ~init:env ~f:add_install_rule in
  let env =
    Option.value_map project ~default:env ~f:(fun info -> set_project env info)
  in
  let env =
    Option.value_map cmake_min_version ~default:env ~f:(fun v -> set_cmake_min_version env v)
  in
  let env =
    List.fold messages ~init:env ~f:(fun env { mode; texts } -> add_message env mode texts)
  in
  let env = List.fold subdirectories ~init:env ~f:add_subdirectory in
  let env = if testing_enabled then enable_testing env else env in
  let env = List.fold tests ~init:env ~f:add_test in
  let env =
    List.fold target_properties ~init:env ~f:(fun env (target, property, value) ->
      set_target_property env ~target ~property ~value)
  in
  let env = List.fold find_packages ~init:env ~f:add_find_package in
  let env = List.fold try_compiles ~init:env ~f:add_try_compile in
  List.fold functions ~init:env ~f:(fun env (name, decl) ->
    set_function env name decl)

let check_yelu1_to_yelu2 name expr ~expected_value ~expected_env =
  Alcotest.test_case name `Quick (fun () ->
    let env = empty_env in
    let left_env, left_value = eval_yelu_cmake_expr env expr in
    let right_env, right_value = eval_yelu_cmake_normal_expr env (to_normal expr) in
    Alcotest.(check bool) "translation preserves value" true
      (equal_value left_value right_value);
    Alcotest.(check bool) "translation preserves env" true
      (equal_env left_env right_env);
    Alcotest.(check bool) "expected value" true
      (equal_value expected_value left_value);
    Alcotest.(check bool) "expected env" true
      (equal_env expected_env left_env))

let check_yelu2_to_yelu1 name expr ~expected_value ~expected_env =
  Alcotest.test_case name `Quick (fun () ->
    let env = empty_env in
    let left_env, left_value = eval_yelu_cmake_normal_expr env expr in
    let right_env, right_value = eval_yelu_cmake_expr env (from_normal expr) in
    Alcotest.(check bool) "translation preserves value" true
      (equal_value left_value right_value);
    Alcotest.(check bool) "translation preserves env" true
      (equal_env left_env right_env);
    Alcotest.(check bool) "expected value" true
      (equal_value expected_value left_value);
    Alcotest.(check bool) "expected env" true
      (equal_env expected_env left_env))

let check_yelu1_lift_lower_roundtrip name expr =
  Alcotest.test_case name `Quick (fun () ->
    let env = empty_env in
    let left_env, left_value = eval_yelu_cmake_expr env expr in
    let lifted = to_normal expr in
    let lowered = from_normal lifted in
    let right_env, right_value = eval_yelu_cmake_expr env lowered in
    Alcotest.(check bool) "roundtrip preserves value" true
      (equal_value left_value right_value);
    Alcotest.(check bool) "roundtrip preserves env" true
      (equal_env left_env right_env))

(* Dual-evaluator equivalence (value-only).

   For a yc IR program, asserts
     eval_yelu_cmake_expr empty_env expr  =value=
       eval_yelu_cmake_normal_expr empty_env (to_normal expr).
   Env divergence is NOT compared. cmake-shape sugar (output-var
   convention, subcommand sugar) means the two languages legitimately
   produce different env shapes even when their *value semantics*
   agree; the lift_lower tests already exercise the stricter
   env-equivalence property on a small handful of programs. This
   helper is the broader, looser check meant to be sprinkled across
   the larger test corpora (test_yelu_compile, test_yelu_steps, …).

   Programs that don't return a meaningful value (most stmt-level
   cmake programs) evaluate to VUnit on both sides — the helper
   then reduces to a "fate-sharing" check: both evaluators must
   terminate without crashing on the program (and its to_normal
   image). That alone catches "ycn-eval breaks on a real-corpus
   shape" regressions that 75-case lift_lower can't surface.

   Future: value-only → observable-env (declared per-test) →
   structural env-equiv. Tracked in cmake_vs_normal.md § 5 and
   the broader test-coverage plan. *)
let check_dual_eval name expr =
  Alcotest.test_case name `Quick (fun () ->
    let _, yc_value = eval_yelu_cmake_expr empty_env expr in
    let _, ycn_value = eval_yelu_cmake_normal_expr empty_env (to_normal expr) in
    Alcotest.(check bool) "yc-eval and ycn-eval agree on value" true
      (equal_value yc_value ycn_value))
