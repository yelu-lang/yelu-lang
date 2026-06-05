(* fmt test/fuzzing/CMakeLists.txt — whole-file emit.
   option + cached STRING + add_fuzzer function + foreach. *)

open Yelu_langs.Yelu_cmake
open Yelu_langs.Yelu_cmake_utils
open Yelu_langs.Yelu_cmake_target

let add_fuzzer_fn =
  yc_function (ystr "add_fuzzer") ["source"] [
    yc_get_filename_component ~mode:"NAME_WE" "basename" (EVar "source");
    yc_set (ycvar "name") [ystr "${basename}-fuzzer"];
    ECmakeAddExecutable {
      name = EVar "name";
      sources = [EVar "source"; ystr "fuzzer-common.h"];
    };
    yifthen (EVar "FMT_FUZZ_LINKMAIN") (
      ECmakeTargetSources {
        target = EVar "name"; visibility = "PRIVATE";
        sources = [ystr "main.cc"];
      });
    ECmakeTargetLinkLibraries {
      target = EVar "name"; visibility = "PRIVATE";
      items = [ystr "fmt"];
    };
    yifthen (EVar "FMT_FUZZ_LDFLAGS") (
      ECmakeTargetLinkLibraries {
        target = EVar "name"; visibility = "PRIVATE";
        items = [EVar "FMT_FUZZ_LDFLAGS"];
      });
    ECmakeTargetCompileFeatures {
      target = EVar "name"; visibility = "PRIVATE";
      features = [ystr "cxx_std_14"];
    };
  ]

let helpers = ESeq [
  yc_option "FMT_FUZZ_LINKMAIN"
    ~msg:"Enables the reproduce mode, instead of libFuzzer"
    ~value:(EBool true);
  yc_set_cache (ycvar "FMT_FUZZ_LDFLAGS")
    ~docstring:"LDFLAGS for the fuzz targets"
    [ystr ""];
  add_fuzzer_fn;
  yc_foreach
    ~items:[
      ystr "chrono-duration.cc"; ystr "chrono-timepoint.cc";
      ystr "float.cc"; ystr "named-arg.cc";
      ystr "one-arg.cc"; ystr "two-args.cc";
    ]
    (ycvar "source")
    (yc_apply (ystr "add_fuzzer") [EVar "source"]);
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
