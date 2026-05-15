(** conf-run level tests for set(ENV{...}) / $ENV{VAR} / unset(ENV{...}).
    Uses run_script ~env to pre-populate the cmake process environment. *)

open Yelu_langs.Yelu_cmake
open Yelu_langs.Yelu_cmake_utils
open Yelu_langs.Lang_cmake_pp
open Yelu_runner.Cmake_runner

let compile exp =
  Fmt.str "%a" (Fmt.vbox pp) (Yelu_langs.Yelu_cmake_emit.emit_ast exp)

let check_cmake_env name env prog =
  Alcotest.test_case name `Quick (fun () ->
      let result = run_script ~env (compile prog) in
      if result.exit_code <> 0 then
        Alcotest.failf "cmake exited %d\nstderr:\n%s" result.exit_code result.stderr)

(* Read an env var set by the caller via ~env *)
let read_env_var =
  check_cmake_env "read_env_var" [("YELU_TEST_VAR", "hello")] (
    yifthen (ynot (ystrequal (ystr_eval "$ENV{YELU_TEST_VAR}") (ystr "hello")))
      (yc_message ~mode:Mm_fatal_error ["read_env_var: YELU_TEST_VAR should be hello"])
  )

(* set(ENV{VAR} value) sets an env var readable via $ENV{} in the same script *)
let set_env_var =
  check_cmake_env "set_env_var" [] (ESeq [
    yc_set_env "YELU_SET_VAR" (ystr "world");
    yifthen (ynot (ystrequal (ystr_eval "$ENV{YELU_SET_VAR}") (ystr "world")))
      (yc_message ~mode:Mm_fatal_error ["set_env_var: YELU_SET_VAR should be world"]);
  ])

(* unset(ENV{VAR}) clears the variable *)
let unset_env_var =
  check_cmake_env "unset_env_var" [("YELU_UNSET_VAR", "present")] (ESeq [
    yifthen (ynot (ystrequal (ystr_eval "$ENV{YELU_UNSET_VAR}") (ystr "present")))
      (yc_message ~mode:Mm_fatal_error ["unset_env_var: var should be present before unset"]);
    yc_unset_env "YELU_UNSET_VAR";
    yifthen (ynot (ystrequal (ystr_eval "$ENV{YELU_UNSET_VAR}") (ystr "")))
      (yc_message ~mode:Mm_fatal_error ["unset_env_var: var should be empty after unset"]);
  ])

let () =
  Alcotest.run "set_env"
    [ ("read_env_var",  [ read_env_var ]);
      ("set_env_var",   [ set_env_var ]);
      ("unset_env_var", [ unset_env_var ]);
    ]
