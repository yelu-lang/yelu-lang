(** Run RunCMake positive-test scripts directly via cmake -P, bypassing CTest.
    Each test: run <dir>/<name>.cmake, check exit 0, match <name>-stdout.txt patterns. *)

open Yelu_runner.Cmake_runner

let runcmake_dir =
  match Sys.getenv_opt "RUNCMAKE_DIR" with
  | Some d -> d
  | None ->
    (* Walk up from CWD to find the source workspace root.
       The source root contains yelu/vendor/; the build tree does not. *)
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

let check name dir =
  Alcotest.test_case name `Quick (fun () ->
    let script = Filename.concat dir (name ^ ".cmake") in
    let result = run_script_file script in
    check_exit 0 result;
    check_stdout_patterns (load_stdout_patterns dir name) result)

(* Scripts that use include(relative.cmake): run cmake with CWD = script dir. *)
let check_from_dir name dir =
  Alcotest.test_case name `Quick (fun () ->
    let script = Filename.concat dir (name ^ ".cmake") in
    let result = run_script_file ~cwd:(Some dir) script in
    check_exit 0 result;
    check_stdout_patterns (load_stdout_patterns dir name) result)

(* cmake_path scripts all include check_errors.cmake via ${RunCMake_SOURCE_DIR} *)
let check_cmake_path name =
  let dir = script_dir "cmake_path" in
  Alcotest.test_case name `Quick (fun () ->
    let script = Filename.concat dir (name ^ ".cmake") in
    let result = run_script_file ~flags:["-DRunCMake_SOURCE_DIR=" ^ dir] script in
    check_exit 0 result;
    check_stdout_patterns (load_stdout_patterns dir name) result)

let () =
  Alcotest.run "RunCMake compat"
    [ ("math", [
        check "MATH"     (script_dir "math");
        check "Overflow" (script_dir "math") ]);
      ("list", [
        check "JOIN"     (script_dir "list");
        check "SORT"     (script_dir "list");
        check "POP_BACK" (script_dir "list");
        check "POP_FRONT"(script_dir "list");
        check "PREPEND"  (script_dir "list") ]);
      ("string", [
        check "Concat"   (script_dir "string");
        check "Append"   (script_dir "string");
        check "Join"     (script_dir "string");
        check "Hex"      (script_dir "string");
        check "Uuid"            (script_dir "string");
        check "Repeat"          (script_dir "string");
        (* CMP0186 NEW is default in cmake 4.1+; regex zero-length match now well-defined *)
        check "RegexEmptyMatch" (script_dir "string") ]);
      ("foreach", [
        check "foreach-all-test" (script_dir "foreach") ]);
      ("message", [
        check "newline"          (script_dir "message");
        check "message-indent"   (script_dir "message") ]);
      ("variable_watch", [
        check "ModifiedAccess"       (script_dir "variable_watch");
        check "ModifyWatchInCallback"(script_dir "variable_watch");
        check "NoWatcher"            (script_dir "variable_watch");
        check "RaiseInParentScope"   (script_dir "variable_watch");
        check "WatchTwice"           (script_dir "variable_watch") ]);
      ("cmake_path", [
        check_cmake_path "ABSOLUTE_PATH";
        check_cmake_path "APPEND";
        check_cmake_path "APPEND_STRING";
        check_cmake_path "COMPARE";
        check_cmake_path "CONVERT";
        check_cmake_path "GET";
        check_cmake_path "HASH";
        check_cmake_path "HAS_ITEM";
        check_cmake_path "IS_ABSOLUTE";
        check_cmake_path "IS_PREFIX";
        check_cmake_path "IS_RELATIVE";
        check_cmake_path "NATIVE_PATH";
        check_cmake_path "NORMAL_PATH";
        check_cmake_path "RELATIVE_PATH";
        check_cmake_path "REMOVE_EXTENSION";
        check_cmake_path "REMOVE_FILENAME";
        check_cmake_path "REPLACE_EXTENSION";
        check_cmake_path "REPLACE_FILENAME";
        check_cmake_path "SET" ]);
      ("while", [
        (* CMP0130-OLD/-WARN use include(relative.cmake) — need cwd = script dir *)
        check_from_dir "CMP0130-OLD"    (script_dir "while");
        check_from_dir "CMP0130-WARN"   (script_dir "while");
        check          "CMP0130-common" (script_dir "while");
        check          "EndMismatch"    (script_dir "while") ]);
      ("return", [
        check "CMP0140-NEW"       (script_dir "return");
        check "CMP0140-OLD"       (script_dir "return");
        check "PropagateNothing"  (script_dir "return") ]);
      ("option", [
        check "CMP0077-NEW"         (script_dir "option");
        check "CMP0077-OLD"         (script_dir "option");
        check "CMP0077-SECOND-PASS" (script_dir "option");
        check "CMP0077-WARN"        (script_dir "option") ]);
      ("set", [
        check "Env"                   (script_dir "set");
        check "ExtraEnvValue"         (script_dir "set");
        check "ParentPulling"         (script_dir "set");
        check "ParentPullingRecursive"(script_dir "set") ]);
      ("include",
        let check_include_warning name =
          Alcotest.test_case name `Quick (fun () ->
            let script = Filename.concat (script_dir "include") (name ^ ".cmake") in
            let result = run_script_file script in
            check_exit 0 result;
            check_stderr_matches "given empty file name" result)
        in [
        (* EmptyString/Optional: no stdout — verify the dev warning appears in stderr *)
        check_include_warning "EmptyString";
        check_include_warning "EmptyStringOptional";
        (* CMP0146/CMP0148: deprecated find modules — module search works in -P mode *)
        check "CMP0146-OLD"          (script_dir "include");
        check "CMP0146-WARN"         (script_dir "include");
        check "CMP0148-Interp-OLD"   (script_dir "include");
        check "CMP0148-Interp-WARN"  (script_dir "include");
        check "CMP0148-Libs-OLD"     (script_dir "include");
        check "CMP0148-Libs-WARN"    (script_dir "include") ]);
      ("get_filename_component", [
        (* KnownComponents: was blocked on CMP0057 OLD (IN_LIST) on 3.28; passes on 4.3 *)
        check "KnownComponents" (script_dir "get_filename_component") ]);
    ]
