open Base
open Yelu_langs.Yelu_cmake
open Yelu_langs.Yelu_cmake_convert

module Old = Yelu_langs.Lang_yelu_cmake

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

let old_cvar name : Old.tc_name = { ns = Old.Ns_var; name }
let old_str s = Old.Yexpr_string (Old.Ycs_string s)
let old_var name = Old.Yexpr_var (Old.Yvar name)

let check_yelu_cmake_bridge_to_yelu1 name stmt ~expected_value ~expected_env =
  Alcotest.test_case name `Quick (fun () ->
    let expr = Yelu_langs.Yelu_cmake_legacy_bridge.stmt stmt in
    let env, value = eval_yelu_cmake_expr empty_env expr in
    Alcotest.(check bool) "expected value" true
      (equal_value expected_value value);
    Alcotest.(check bool) "expected env" true
      (equal_env expected_env env))

let parse_old_yelu source =
  match Yelu_langs.Lang_yelu_parse.parse_program source with
  | Ok stmt -> stmt
  | Error error -> Alcotest.failf "parse error: %s" error

let check_parsed_yelu_bridge_to_yelu1 name source ~expected_value ~expected_env =
  Alcotest.test_case name `Quick (fun () ->
    let expr =
      source
      |> parse_old_yelu
      |> Yelu_langs.Yelu_cmake_legacy_bridge.stmt
    in
    let env, value = eval_yelu_cmake_expr empty_env expr in
    Alcotest.(check bool) "expected value" true
      (equal_value expected_value value);
    Alcotest.(check bool) "expected env" true
      (equal_env expected_env env))

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
