(* fmt support/cmake/JoinPaths.cmake — yelu IR for the
   join_paths() helper. Replaces the function body (anchors:
   `function (join_paths joined_path first_path_segment)` …
   `endfunction ()`).

   Notes:
   - .ml not .ye because yelu surface parser doesn't yet
     support `foreach IN LISTS X` (only `foreach v in RANGE`
     and bracketed literal lists). Filed under migration_plan
     risk #6 (parser coverage). *)

open Yelu_langs.Yelu_cmake_utils
open Yelu_langs.Yelu_cmake_string

let helpers =
  yc_function (ystr "join_paths") ["joined_path"; "first_path_segment"] [
    yc_set (ycvar "temp_path") [ystr "${first_path_segment}"];
    yc_foreach_in ~lists:["ARGN"] (ycvar "current_segment")
      (yifthen
        (ynot (ECmakeStringEqual (ystr "${current_segment}", ystr "")))
        (yif
          (ECmakeIsAbsolute (ystr "${current_segment}"))
          (yc_set (ycvar "temp_path") [ystr "${current_segment}"])
          (yc_set (ycvar "temp_path") [ystr "${temp_path}/${current_segment}"])));
    yc_set ~parent_scope:true (ycvar "${joined_path}") [ystr "${temp_path}"];
  ]

let () =
  let cmake_ast = Yelu_langs.Yelu_cmake_emit.emit_ast helpers in
  let buf = Buffer.create 512 in
  let ff = Format.formatter_of_buffer buf in
  Format.pp_open_vbox ff 0;
  Yelu_langs.Lang_cmake_pp.pp ff cmake_ast;
  Format.pp_close_box ff ();
  Format.pp_print_flush ff ();
  print_string (Buffer.contents buf);
  print_newline ()
