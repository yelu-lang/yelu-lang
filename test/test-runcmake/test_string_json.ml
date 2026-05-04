(** conf-run tests for string(JSON ...).
    Covers GET, TYPE, LENGTH, MEMBER, REMOVE, SET, EQUAL.
    GET_RAW and STRING_ENCODE are cmake 4.3+ and are not tested here.
    JSON content is passed as cmake bracket strings via ystr_eval to avoid quoting issues. *)

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

(* bracket-string JSON literals — no quoting issues *)
let json1 = ystr_eval {|[=[{"name":"cmake","version":3,"tags":["a","b","c"]}]=]|}
let json2 = ystr_eval {|[=[{"x":1}]=]|}

(* GET: top-level string field *)
let json_get =
  check_cmake "json_get" (Ystmt_list [
    yc_string_json_get ~out:(ycvar "val") json1 ~path:["name"];
    yifthen (ynot (ystrequal (ycref "val") (ystr "cmake")))
      (yc_message ~mode:Mm_fatal_error ["JSON GET name failed"]);
    (* nested: tags[1] *)
    yc_string_json_get ~out:(ycvar "val") json1 ~path:["tags"; "1"];
    yifthen (ynot (ystrequal (ycref "val") (ystr "b")))
      (yc_message ~mode:Mm_fatal_error ["JSON GET tags 1 failed"]);
  ])

(* GET with ERROR_VARIABLE: missing key sets val to key-NOTFOUND *)
let json_get_error =
  check_cmake "json_get_error" (Ystmt_list [
    yc_string_json_get ~error_var:(ycvar "err") ~out:(ycvar "val") json1 ~path:["missing"];
    yifthen (ynot (ymatches (ycref "val") "NOTFOUND"))
      (yc_message ~mode:Mm_fatal_error ["JSON GET missing: expected NOTFOUND"]);
    yifthen (ystrequal (ycref "err") (ystr ""))
      (yc_message ~mode:Mm_fatal_error ["JSON GET missing: expected non-empty error"]);
  ])

(* TYPE: returns NULL, NUMBER, STRING, BOOLEAN, ARRAY, OBJECT *)
let json_type =
  check_cmake "json_type" (Ystmt_list [
    yc_string_json_type ~out:(ycvar "t") json1 ~path:["name"];
    yifthen (ynot (ystrequal (ycref "t") (ystr "STRING")))
      (yc_message ~mode:Mm_fatal_error ["JSON TYPE name: expected STRING"]);
    yc_string_json_type ~out:(ycvar "t") json1 ~path:["version"];
    yifthen (ynot (ystrequal (ycref "t") (ystr "NUMBER")))
      (yc_message ~mode:Mm_fatal_error ["JSON TYPE version: expected NUMBER"]);
    yc_string_json_type ~out:(ycvar "t") json1 ~path:["tags"];
    yifthen (ynot (ystrequal (ycref "t") (ystr "ARRAY")))
      (yc_message ~mode:Mm_fatal_error ["JSON TYPE tags: expected ARRAY"]);
  ])

(* LENGTH: number of elements in object or array *)
let json_length =
  check_cmake "json_length" (Ystmt_list [
    yc_string_json_length ~out:(ycvar "n") json1;
    yifthen (ynot (ystrequal (ycref "n") (ystr "3")))
      (yc_message ~mode:Mm_fatal_error ["JSON LENGTH root: expected 3"]);
    yc_string_json_length ~out:(ycvar "n") json1 ~path:["tags"];
    yifthen (ynot (ystrequal (ycref "n") (ystr "3")))
      (yc_message ~mode:Mm_fatal_error ["JSON LENGTH tags: expected 3"]);
  ])

(* MEMBER: get key name at index in an object *)
let json_member =
  check_cmake "json_member" (Ystmt_list [
    yc_string_json_member ~out:(ycvar "k") json1 ~path:["0"];
    yifthen (ynot (ystrequal (ycref "k") (ystr "name")))
      (yc_message ~mode:Mm_fatal_error ["JSON MEMBER 0: expected name"]);
  ])

(* REMOVE: removes a key, result is new JSON.
   ERROR_VARIABLE is NOTFOUND on success (cmake convention). *)
let json_remove =
  check_cmake "json_remove" (Ystmt_list [
    yc_string_json_remove ~error_var:(ycvar "err") ~out:(ycvar "result") json2 ~path:["x"];
    yifthen (ynot (ystrequal (ycref "err") (ystr "NOTFOUND")))
      (yc_message ~mode:Mm_fatal_error ["JSON REMOVE: unexpected error: ${err}"]);
    (* result should be an empty object {} — check it has length 0 *)
    yc_string_json_length ~out:(ycvar "n") (ycref "result");
    yifthen (ynot (ystrequal (ycref "n") (ystr "0")))
      (yc_message ~mode:Mm_fatal_error ["JSON REMOVE: expected empty object"]);
  ])

(* SET: adds or updates a key.
   Value must be a JSON literal — pass string values bracket-quoted. *)
let json_set =
  check_cmake "json_set" (Ystmt_list [
    yc_string_json_set ~out:(ycvar "result")
      ~value:(ystr_eval {|[=["hello"]=]|}) json2 ~path:["y"];
    yc_string_json_get ~out:(ycvar "val") (ycref "result") ~path:["y"];
    yifthen (ynot (ystrequal (ycref "val") (ystr "hello")))
      (yc_message ~mode:Mm_fatal_error ["JSON SET y: expected hello"]);
  ])

(* EQUAL: structural JSON equality — returns ON or OFF *)
let json_equal =
  check_cmake "json_equal" (Ystmt_list [
    yc_string_json_equal ~out:(ycvar "eq")
      (ystr_eval {|[=[{"a":1}]=]|})
      (ystr_eval {|[=[ { "a" : 1 } ]=]|});
    yifthen (ynot (ystrequal (ycref "eq") (ystr "ON")))
      (yc_message ~mode:Mm_fatal_error ["JSON EQUAL: expected ON"]);
    yc_string_json_equal ~out:(ycvar "eq")
      (ystr_eval {|[=[{"a":1}]=]|})
      (ystr_eval {|[=[{"a":2}]=]|});
    yifthen (ystrequal (ycref "eq") (ystr "ON"))
      (yc_message ~mode:Mm_fatal_error ["JSON EQUAL: expected OFF"]);
  ])

let () =
  Alcotest.run "string_json"
    [ ("json_get",       [ json_get ]);
      ("json_get_error", [ json_get_error ]);
      ("json_type",      [ json_type ]);
      ("json_length",    [ json_length ]);
      ("json_member",    [ json_member ]);
      ("json_remove",    [ json_remove ]);
      ("json_set",       [ json_set ]);
      ("json_equal",     [ json_equal ]);
    ]
