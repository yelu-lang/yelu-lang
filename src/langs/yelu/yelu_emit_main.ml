(* Shared `let () = ...` trailer for probe / step .ml files that
   emit a single yelu_cmake program to stdout as cmake text.

   Usage:
     let helpers = ESeq [ ... ]
     let () = Yelu_emit_main.print helpers *)

(* Escape a raw string for embedding inside a cmake-quoted argument.
   Delegates to [Lang_cmake_strings.escape_quoted], the canonical
   implementation in the cmake layer. *)
let escape = Lang_cmake_strings.escape_quoted

(* Raw cmake escape — verbatim text dropped into the emitted file.
   Use sparingly: each call is unmodeled surface. See
   doc/yelu_cmake/hybrid_strategy.md Shape C. *)
let raw_cmake text = Yelu_cmake_utils.yc_raw text

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
