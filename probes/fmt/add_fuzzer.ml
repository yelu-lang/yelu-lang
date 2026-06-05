(* fmt test/fuzzing/CMakeLists.txt — yelu IR for the
   `add_fuzzer(source)` helper.

   Notes:
   - .ml not .ye because yelu surface parser doesn't yet support
     dynamic target names (`Target ${var}` form). All target ops
     in this helper use `${name}` (a function parameter). Filed
     under migration_plan risk #6 (parser coverage). *)

open Yelu_langs.Yelu_cmake
open Yelu_langs.Yelu_cmake_utils
open Yelu_langs.Yelu_cmake_target

let helpers =
  yc_function (ystr "add_fuzzer") ["source"] [
    (* get_filename_component(basename ${source} NAME_WE) *)
    yc_get_filename_component ~mode:"NAME_WE" "basename" (EVar "source");
    (* set(name ${basename}-fuzzer) *)
    yc_set (ycvar "name") [ystr "${basename}-fuzzer"];
    (* add_executable(${name} ${source} fuzzer-common.h) *)
    ECmakeAddExecutable {
      name = EVar "name";
      sources = [EVar "source"; ystr "fuzzer-common.h"];
    };
    (* if (FMT_FUZZ_LINKMAIN) target_sources(${name} PRIVATE main.cc) endif() *)
    yifthen (EVar "FMT_FUZZ_LINKMAIN") (
      ECmakeTargetSources {
        target = EVar "name";
        visibility = "PRIVATE";
        sources = [ystr "main.cc"];
      });
    (* target_link_libraries(${name} PRIVATE fmt) *)
    ECmakeTargetLinkLibraries {
      target = EVar "name";
      visibility = "PRIVATE";
      items = [ystr "fmt"];
    };
    (* if (FMT_FUZZ_LDFLAGS) target_link_libraries(${name} PRIVATE ${FMT_FUZZ_LDFLAGS}) endif() *)
    yifthen (EVar "FMT_FUZZ_LDFLAGS") (
      ECmakeTargetLinkLibraries {
        target = EVar "name";
        visibility = "PRIVATE";
        items = [EVar "FMT_FUZZ_LDFLAGS"];
      });
    (* target_compile_features(${name} PRIVATE cxx_std_14) *)
    ECmakeTargetCompileFeatures {
      target = EVar "name";
      visibility = "PRIVATE";
      features = [ystr "cxx_std_14"];
    };
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
