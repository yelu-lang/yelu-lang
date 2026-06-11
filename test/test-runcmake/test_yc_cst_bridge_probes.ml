(* Emit-bridge over the real probe .yc corpus (M1.2): every .yc file under
   probes/ must satisfy emit(lower(parse_cst f)) == emit(parse_ast f).
   This is the comprehensive, real-input half of the bridge oracle (the
   in-sandbox unit test test_yc_cst_bridge covers construct families).
   Reads files by relative path from the repo root, like the matrix
   oracle — run via `dune exec`, not the runtest alias. *)

open Base

let rec find_yc dir =
  Stdlib.Sys.readdir dir
  |> Array.to_list
  |> List.concat_map ~f:(fun e ->
       let p = Stdlib.Filename.concat dir e in
       if Stdlib.Sys.is_directory p then find_yc p
       else if String.is_suffix e ~suffix:".yc" then [ p ] else [])

let read_all f =
  let ic = Stdlib.open_in f in
  let n = Stdlib.in_channel_length ic in
  let s = Stdlib.really_input_string ic n in
  Stdlib.close_in ic;
  s

let emit_ast src =
  match Yelu_langs.Yelu_parse.parse_program_y1 src with
  | Ok e -> Ok (Yelu_langs.Yelu_cmake_emit.emit_script e)
  | Error e -> Error ("ast-parse: " ^ e)

let emit_cst src =
  match Yelu_langs.Yc_cst_parse.parse src with
  | Ok p -> Ok (Yelu_langs.Yelu_cmake_emit.emit_script
                  (Yelu_langs.Yc_cst_lower.lower_program p))
  | Error e -> Error ("cst-parse: " ^ e)

let bridge_file f =
  Alcotest.test_case f `Quick (fun () ->
    let src = read_all f in
    match emit_ast src, emit_cst src with
    | Ok a, Ok c -> Alcotest.(check string) "emit(lower cst) == emit(ast)" a c
    | Error e, _ | _, Error e -> Alcotest.failf "%s: %s" f e)

let () =
  let files =
    if Stdlib.Sys.file_exists "probes" then List.sort ~compare:String.compare (find_yc "probes")
    else []
  in
  Stdlib.Printf.printf "[cst-bridge] %d .yc files under probes/\n%!"
    (List.length files);
  Alcotest.run "yc_cst_bridge_probes"
    [ "probe-corpus", List.map files ~f:bridge_file ]
