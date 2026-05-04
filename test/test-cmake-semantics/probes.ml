(* cmake semantics probes — small cmake programs for File API verification.
   Each probe defines a minimal cmake project + required source files.
   Run: probes.exe <name>           → print CMakeLists.txt
        probes.exe <name> --sources → print source files (one per line)
        probes.exe <name> --subdir <dir> → print subdir CMakeLists.txt
        probes.exe --list           → list all probe names *)

open Base
module U = Yelu_langs.Lang_cmake_utils
module P = Yelu_langs.Lang_cmake_pp

let s = U.str_

(* Every probe needs this preamble *)
let preamble name =
  [
    U.minimum_required_s "3.14.";
    U.project ~languages:[ "C" ] name;
  ]

type probe = {
  name : string;
  cmake : Yelu_langs.Lang_cmake.exp;
  sources : string list;
  subdirs : (string * Yelu_langs.Lang_cmake.exp * string list) list;
}

let mk ?(sources = []) ?(subdirs = []) name cmds =
  { name; cmake = U.cmd_of_list (preamble name @ cmds); sources; subdirs }

(* ---- Category 1: Target creation ---- *)

let target_from_lib =
  mk ~sources:[ "foo.c" ] "target_from_lib"
    [ U.add_library ~sources:[ "foo.c" ] "foo" ]

let target_from_exe =
  mk ~sources:[ "bar.c" ] "target_from_exe"
    [ U.add_executable ~sources:[ "bar.c" ] "bar" ]

let target_interface =
  mk "target_interface"
    [ U.add_library ~type_:"INTERFACE" "iface" ]

let target_named_like_file =
  mk ~sources:[ "foo.c" ] "target_named_like_file"
    [ U.add_library ~sources:[ "foo.c" ] "foo.c" ]

let target_interface_with_consumer =
  mk ~sources:[ "main.c" ] "target_interface_with_consumer"
    [
      U.add_library ~type_:"INTERFACE" "iface";
      U.add_executable ~sources:[ "main.c" ] "app";
      U.target_link_libraries [ "app" ]
        [ U.target_def ~kind:"PRIVATE" [ s "iface" ] ];
    ]

(* ---- Category 2: Files without targets ---- *)

let configure_file_no_target =
  mk ~sources:[ "config.h.in" ] "configure_file_no_target"
    [ U.configure_file ~input:"config.h.in" "config.h" ]

let install_file_no_target =
  mk ~sources:[ "x.h" ] "install_file_no_target"
    [ U.install_files [ s "x.h" ] (s "include") ]

(* ---- Category 3: String in different roles ---- *)

let same_name_target_and_subdir =
  let sub_cmake =
    U.cmd_of_list
      (preamble "Math" @ [ U.add_library ~sources:[ "math.c" ] "MathLib" ])
  in
  mk ~sources:[ "main.c" ]
    ~subdirs:[ ("Math", sub_cmake, [ "math.c" ]) ]
    "same_name_target_and_subdir"
    [
      U.add_executable ~sources:[ "main.c" ] "app";
      U.add_subdirectory "Math";
    ]

(* ---- Category 4: Expected failures ---- *)

let missing_source_file =
  mk "missing_source_file"
    [ U.add_library ~sources:[ "nonexistent.c" ] "foo" ]

(* ---- Category 5: Target properties ---- *)

let target_link_creates_dep =
  mk ~sources:[ "a.c"; "b.c" ] "target_link_creates_dep"
    [
      U.add_library ~sources:[ "a.c" ] "liba";
      U.add_library ~sources:[ "b.c" ] "libb";
      U.target_link_libraries [ "liba" ]
        [ U.target_def ~kind:"PRIVATE" [ s "libb" ] ];
    ]

let target_with_definitions =
  mk ~sources:[ "foo.c" ] "target_with_definitions"
    [
      U.add_library ~sources:[ "foo.c" ] "foo";
      U.target_compile_definitions "foo"
        [ U.target_def ~kind:"PRIVATE" [ s "USE_X" ] ];
    ]

(* ---- Category 6: Variables vs targets ---- *)

let set_var_not_target =
  mk "set_var_not_target"
    [ U.set "FOO" [ s "bar" ] ]

let option_creates_cache =
  mk "option_creates_cache"
    [ U.option_ ~value:(U.bool_ true) ~msg:"Enable feature X" "USE_X" ]

(* ---- Category 7: Multiple targets, same source ---- *)

let two_targets_same_source =
  mk ~sources:[ "shared.c" ] "two_targets_same_source"
    [
      U.add_library ~sources:[ "shared.c" ] "libA";
      U.add_library ~sources:[ "shared.c" ] "libB";
    ]

(* ---- Category 8: cmake introspection — what kind is a string? ---- *)

(* Use if(TARGET) + set(CACHE) to probe cmake's own classification.
   Results stored in cache variables, visible in File API cache-v2. *)

(* Helper: set a CACHE STRING variable via raw cmake *)
let cache_set var value =
  U.quote_cmd (Fmt.str "set(%s \"%s\" CACHE STRING \"\")" var value)

(* Helper: if(TARGET name) set RESULT_xxx to "yes" else "no" *)
let probe_is_target result_var target_name =
  U.cmd_of_list [
    U.quote_cmd (Fmt.str "if(TARGET %s)" target_name);
    cache_set result_var "yes";
    U.quote_cmd (Fmt.str "else()");
    cache_set result_var "no";
    U.quote_cmd "endif()";
  ]

(* Helper: if(DEFINED name) *)
let probe_is_defined result_var var_name =
  U.cmd_of_list [
    U.quote_cmd (Fmt.str "if(DEFINED %s)" var_name);
    cache_set result_var "yes";
    U.quote_cmd (Fmt.str "else()");
    cache_set result_var "no";
    U.quote_cmd "endif()";
  ]

let string_kind_after_add_library =
  mk ~sources:[ "foo.c" ] "string_kind_after_add_library"
    [
      U.add_library ~sources:[ "foo.c" ] "foo";
      probe_is_target "IS_TARGET_foo" "foo";
      probe_is_target "IS_TARGET_foo_c" "foo.c";
      probe_is_defined "IS_DEFINED_foo" "foo";
    ]

let string_kind_after_set =
  mk "string_kind_after_set"
    [
      U.set "MYVAR" [ s "hello" ];
      probe_is_target "IS_TARGET_MYVAR" "MYVAR";
      probe_is_defined "IS_DEFINED_MYVAR" "MYVAR";
    ]

let string_kind_interface_is_target =
  mk "string_kind_interface_is_target"
    [
      U.add_library ~type_:"INTERFACE" "iface";
      probe_is_target "IS_TARGET_iface" "iface";
    ]

let string_kind_after_option =
  mk "string_kind_after_option"
    [
      U.option_ ~value:(U.bool_ true) ~msg:"test" "MY_OPT";
      probe_is_target "IS_TARGET_MY_OPT" "MY_OPT";
      probe_is_defined "IS_DEFINED_MY_OPT" "MY_OPT";
    ]

(* Helper: if(COMMAND name) *)
let probe_is_command result_var cmd_name =
  U.cmd_of_list [
    U.quote_cmd (Fmt.str "if(COMMAND %s)" cmd_name);
    cache_set result_var "yes";
    U.quote_cmd (Fmt.str "else()");
    cache_set result_var "no";
    U.quote_cmd "endif()";
  ]

(* Helper: if(TEST name) — only valid after enable_testing() *)
let probe_is_test result_var test_name =
  U.cmd_of_list [
    U.quote_cmd (Fmt.str "if(TEST %s)" test_name);
    cache_set result_var "yes";
    U.quote_cmd (Fmt.str "else()");
    cache_set result_var "no";
    U.quote_cmd "endif()";
  ]

(* Helper: if(DEFINED CACHE{name}) *)
let probe_is_cache_defined result_var var_name =
  U.cmd_of_list [
    U.quote_cmd (Fmt.str "if(DEFINED CACHE{%s})" var_name);
    cache_set result_var "yes";
    U.quote_cmd (Fmt.str "else()");
    cache_set result_var "no";
    U.quote_cmd "endif()";
  ]

(* ---- Category 9: All cmake namespaces ---- *)

(* COMMAND namespace: built-in commands are in COMMAND, user function() too *)
let ns_command_builtin =
  mk "ns_command_builtin"
    [
      probe_is_command "IS_CMD_add_library" "add_library";
      probe_is_command "IS_CMD_set" "set";
      probe_is_command "IS_CMD_nonexistent" "nonexistent_cmd_xyz";
    ]

(* user-defined function enters COMMAND namespace *)
let ns_command_function =
  mk "ns_command_function"
    [
      U.function_ "my_func" [ "ARG1" ] [
        U.quote_cmd "message(STATUS \"hello\")";
      ];
      probe_is_command "IS_CMD_my_func" "my_func";
      probe_is_target "IS_TARGET_my_func" "my_func";
      probe_is_defined "IS_DEFINED_my_func" "my_func";
    ]

(* TEST namespace: add_test creates entries in TEST namespace *)
let ns_test =
  mk ~sources:[ "main.c" ] "ns_test"
    [
      U.add_executable ~sources:[ "main.c" ] "runner";
      U.enable_testing;
      U.add_test "mytest" "runner" [];
      probe_is_test "IS_TEST_mytest" "mytest";
      probe_is_target "IS_TARGET_mytest" "mytest";
      probe_is_defined "IS_DEFINED_mytest" "mytest";
      (* the target is "runner", not "mytest" *)
      probe_is_target "IS_TARGET_runner" "runner";
    ]

(* CACHE{} vs normal variable: set() vs set(CACHE) *)
let ns_cache_vs_normal =
  mk "ns_cache_vs_normal"
    [
      U.set "NORMAL_VAR" [ s "hello" ];
      U.quote_cmd "set(CACHE_VAR \"world\" CACHE STRING \"\")";
      probe_is_defined "IS_DEFINED_NORMAL" "NORMAL_VAR";
      probe_is_cache_defined "IS_CACHE_NORMAL" "NORMAL_VAR";
      probe_is_defined "IS_DEFINED_CACHE" "CACHE_VAR";
      probe_is_cache_defined "IS_CACHE_CACHE" "CACHE_VAR";
    ]

(* overlap: same string in target + variable + cache *)
let ns_overlap_all =
  mk ~sources:[ "foo.c" ] "ns_overlap_all"
    [
      U.add_library ~sources:[ "foo.c" ] "foo";
      U.set "foo" [ s "bar" ];
      U.quote_cmd "set(foo \"cached\" CACHE STRING \"\")";
      probe_is_target "IS_TARGET_foo" "foo";
      probe_is_defined "IS_DEFINED_foo" "foo";
      probe_is_cache_defined "IS_CACHE_foo" "foo";
      probe_is_command "IS_CMD_foo" "foo";
    ]

(* POLICY namespace *)
let ns_policy =
  mk "ns_policy"
    [
      U.quote_cmd "if(POLICY CMP0048)";
      cache_set "HAS_POLICY_CMP0048" "yes";
      U.quote_cmd "else()";
      cache_set "HAS_POLICY_CMP0048" "no";
      U.quote_cmd "endif()";
      U.quote_cmd "if(POLICY CMP9999)";
      cache_set "HAS_POLICY_CMP9999" "yes";
      U.quote_cmd "else()";
      cache_set "HAS_POLICY_CMP9999" "no";
      U.quote_cmd "endif()";
    ]

(* ---- Registry ---- *)

let all_probes =
  [
    target_from_lib;
    target_from_exe;
    target_interface;
    target_named_like_file;
    target_interface_with_consumer;
    configure_file_no_target;
    install_file_no_target;
    same_name_target_and_subdir;
    missing_source_file;
    target_link_creates_dep;
    target_with_definitions;
    set_var_not_target;
    option_creates_cache;
    two_targets_same_source;
    string_kind_after_add_library;
    string_kind_after_set;
    string_kind_interface_is_target;
    string_kind_after_option;
    ns_command_builtin;
    ns_command_function;
    ns_test;
    ns_cache_vs_normal;
    ns_overlap_all;
    ns_policy;
  ]

let find_probe name =
  List.find all_probes ~f:(fun p -> String.equal p.name name)

let pp_cmake ast =
  Fmt.pr "%a" (Fmt.vbox P.pp) ast

let () =
  let args = Array.to_list (Sys.get_argv ()) |> List.tl_exn in
  match args with
  | [ "--list" ] ->
      List.iter all_probes ~f:(fun p -> Fmt.pr "%s@." p.name)
  | [ name ] ->
      (match find_probe name with
       | Some p -> pp_cmake p.cmake
       | None -> Fmt.epr "Unknown probe: %s@." name; Stdlib.exit 1)
  | [ name; "--sources" ] ->
      (match find_probe name with
       | Some p -> List.iter p.sources ~f:(fun s -> Fmt.pr "%s@." s)
       | None -> Fmt.epr "Unknown probe: %s@." name; Stdlib.exit 1)
  | [ name; "--subdir"; dir ] ->
      (match find_probe name with
       | Some p ->
           (match List.find p.subdirs ~f:(fun (d, _, _) -> String.equal d dir) with
            | Some (_, cmake, _) -> pp_cmake cmake
            | None -> Fmt.epr "No subdir '%s' in probe '%s'@." dir name; Stdlib.exit 1)
       | None -> Fmt.epr "Unknown probe: %s@." name; Stdlib.exit 1)
  | [ name; "--subdir-sources"; dir ] ->
      (match find_probe name with
       | Some p ->
           (match List.find p.subdirs ~f:(fun (d, _, _) -> String.equal d dir) with
            | Some (_, _, srcs) -> List.iter srcs ~f:(fun s -> Fmt.pr "%s@." s)
            | None -> Fmt.epr "No subdir '%s' in probe '%s'@." dir name; Stdlib.exit 1)
       | None -> Fmt.epr "Unknown probe: %s@." name; Stdlib.exit 1)
  | [ name; "--subdirs" ] ->
      (match find_probe name with
       | Some p ->
           List.iter p.subdirs ~f:(fun (d, _, _) -> Fmt.pr "%s@." d)
       | None -> Fmt.epr "Unknown probe: %s@." name; Stdlib.exit 1)
  | _ ->
      Fmt.epr "Usage: probes.exe --list | <name> [--sources | --subdir <dir> | --subdirs]@.";
      Stdlib.exit 1
