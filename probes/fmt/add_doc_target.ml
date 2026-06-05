(* fmt CMakeLists.txt — add_doc_target() helper.
   find_program + early return + foreach + add_custom_target + install. *)

open Yelu_langs.Yelu_cmake
open Yelu_langs.Yelu_cmake_utils

let helpers =
  yc_function (ystr "add_doc_target") [] [
    (* find_program(DOXYGEN doxygen PATHS "..." "...") *)
    yc_apply (ystr "find_program")
      [ystr "DOXYGEN"; ystr "doxygen"; ystr "PATHS";
       ystr "$ENV{ProgramFiles}/doxygen/bin";
       ystr "$ENV{ProgramFiles\\(x86\\)}/doxygen/bin"];
    (* if (NOT DOXYGEN) message(...) return() endif *)
    yifthen (ynot (EVar "DOXYGEN")) (ESeq [
      yc_apply (ystr "message")
        [ystr "STATUS"; ystr "Target 'doc' disabled because doxygen not found"];
      Yelu_langs.Yelu_cmake_cmake_op.ECmakeReturn { propagate_vars = [] };
    ]);

    (* find_program(MKDOCS mkdocs) *)
    yc_apply (ystr "find_program") [ystr "MKDOCS"; ystr "mkdocs"];
    yifthen (ynot (EVar "MKDOCS")) (ESeq [
      yc_apply (ystr "message")
        [ystr "STATUS"; ystr "Target 'doc' disabled because mkdocs not found"];
      Yelu_langs.Yelu_cmake_cmake_op.ECmakeReturn { propagate_vars = [] };
    ]);

    (* set(sources) *)
    yc_set (ycvar "sources") [];
    (* foreach (source api.md index.md syntax.md get-started.md fmt.css fmt.js) *)
    yc_foreach
      ~items:[ystr "api.md"; ystr "index.md"; ystr "syntax.md";
              ystr "get-started.md"; ystr "fmt.css"; ystr "fmt.js"]
      (ycvar "source")
      (yc_set (ycvar "sources") [EVar "sources"; ystr "doc/${source}"]);

    (* add_custom_target(doc COMMAND ... SOURCES ${sources}) *)
    yc_apply (ystr "add_custom_target") [
      ystr "doc"; ystr "COMMAND";
      EVar "CMAKE_COMMAND"; ystr "-E"; ystr "env";
      ystr "PYTHONPATH=${CMAKE_CURRENT_SOURCE_DIR}/support/python";
      EVar "MKDOCS"; ystr "build"; ystr "-f";
      ystr "${CMAKE_CURRENT_SOURCE_DIR}/support/mkdocs.yml";
      ystr "--site-dir"; ystr "${CMAKE_CURRENT_BINARY_DIR}/doc-html";
      ystr "--no-directory-urls";
      ystr "SOURCES"; EVar "sources";
    ];

    (* install(DIRECTORY ... DESTINATION ... COMPONENT fmt_doc OPTIONAL) *)
    yc_apply (ystr "install") [
      ystr "DIRECTORY"; ystr "${CMAKE_CURRENT_BINARY_DIR}/doc-html/";
      ystr "DESTINATION"; ystr "${CMAKE_INSTALL_DATAROOTDIR}/doc/fmt";
      ystr "COMPONENT"; ystr "fmt_doc";
      ystr "OPTIONAL";
    ];
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
