(* fmt test/find-package-test/CMakeLists.txt — whole-file emit. *)

open Yelu_langs.Yelu_cmake
open Yelu_langs.Yelu_cmake_utils
open Yelu_langs.Yelu_cmake_target

let target_block tname libname = ESeq [
  ECmakeAddExecutable { name = ystr tname; sources = [ystr "main.cc"] };
  yc_apply (ystr "target_link_libraries") [ystr tname; ystr libname];
  ECmakeTargetCompileOptions {
    target = ystr tname; visibility = "PRIVATE";
    before = false; options_ = [EVar "PEDANTIC_COMPILE_FLAGS"];
  };
  ECmakeTargetIncludeDirectories {
    target = ystr tname; visibility = "PUBLIC";
    before = false; system = true; dirs = [ystr "."];
  };
]

let helpers = ESeq [
  yc_apply (ystr "cmake_minimum_required") [ystr "VERSION"; ystr "3.8...3.25"];
  yc_apply (ystr "project") [ystr "fmt-test"];
  yc_apply (ystr "find_package") [ystr "FMT"; ystr "REQUIRED"];
  target_block "library-test" "fmt::fmt";
  yifthen (ECmakeTargetExists (ystr "fmt::fmt-header-only"))
    (target_block "header-only-test" "fmt::fmt-header-only");
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
