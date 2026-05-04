(** conf-run tests for string(UUID ...).
    Expected values taken from cmake's own RunCMake/string/Uuid.cmake. *)

open Yelu_langs.Lang_yelu_cmake
open Yelu_langs.Lang_yelu_utils
open Yelu_langs.Lang_yelu_compile
open Yelu_langs.Lang_cmake_pp
open Yelu_runner.Cmake_runner

let compile exp =
  let cmake_ast = compile empty_env exp |> snd in
  Fmt.str "%a" (Fmt.vbox pp) cmake_ast

let check_cmake name prog =
  Alcotest.test_case name `Quick (fun () ->
      let result = run_script (compile prog) in
      if result.exit_code <> 0 then
        Alcotest.failf "cmake exited %d\nstderr:\n%s" result.exit_code result.stderr)

let dns_ns = "6ba7b810-9dad-11d1-80b4-00c04fd430c8"

(* MD5 UUID: www.example.com in DNS namespace *)
let uuid_md5 =
  check_cmake "uuid_md5" (Ystmt_list [
    yc_string_uuid ~namespace:dns_ns ~name:"www.example.com" ~type_:`Md5 (ycvar "out");
    yifthen (ynot (ystrequal (ycref "out") (ystr "5df41881-3aed-3515-88a7-2f4a814cf09e")))
      (yc_message ~mode:Mm_fatal_error ["UUID MD5 mismatch: ${out}"]);
  ])

(* SHA1 UUID with UPPER flag *)
let uuid_sha1_upper =
  check_cmake "uuid_sha1_upper" (Ystmt_list [
    yc_string_uuid ~namespace:dns_ns ~name:"www.example.com"
      ~type_:`Sha1 ~upper:true (ycvar "out");
    yifthen (ynot (ystrequal (ycref "out") (ystr "2ED6657D-E927-568B-95E1-2665A8AEA6A2")))
      (yc_message ~mode:Mm_fatal_error ["UUID SHA1 UPPER mismatch: ${out}"]);
  ])

(* UUID output length is always 36: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx *)
let uuid_length =
  check_cmake "uuid_length" (Ystmt_list [
    yc_string_uuid ~namespace:dns_ns ~name:"test" ~type_:`Md5 (ycvar "out");
    yc_string_length (ycref "out") (ycvar "n");
    yifthen (ynot (ystrequal (ycref "n") (ystr "36")))
      (yc_message ~mode:Mm_fatal_error ["UUID length should be 36, got: ${n}"]);
  ])

let () =
  Alcotest.run "string_uuid"
    [ ("uuid_md5",        [ uuid_md5 ]);
      ("uuid_sha1_upper", [ uuid_sha1_upper ]);
      ("uuid_length",     [ uuid_length ]);
    ]
