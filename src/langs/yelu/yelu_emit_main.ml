(* Shared `let () = ...` trailer for probe / step .ml files that
   emit a single yelu_cmake program to stdout as cmake text.

   Usage:
     let helpers = ESeq [ ... ]
     let () = Yelu_emit_main.print helpers *)

let print (helpers : Yelu_cmake.expr) : unit =
  let cmake_ast = Yelu_cmake_emit.emit_ast helpers in
  let buf = Buffer.create 512 in
  let ff = Format.formatter_of_buffer buf in
  Format.pp_open_vbox ff 0;
  Lang_cmake_pp.pp ff cmake_ast;
  Format.pp_close_box ff ();
  Format.pp_print_flush ff ();
  print_string (Buffer.contents buf);
  print_newline ()
