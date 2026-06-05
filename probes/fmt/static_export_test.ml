(* fmt test/static-export-test/CMakeLists.txt — whole-file emit. *)

open Yelu_langs.Yelu_cmake
open Yelu_langs.Yelu_cmake_utils
open Yelu_langs.Yelu_cmake_target

let helpers = ESeq [
  yc_apply (ystr "cmake_minimum_required") [ystr "VERSION"; ystr "3.8...3.25"];
  yc_apply (ystr "project") [ystr "fmt-link"; ystr "CXX"];

  yc_set (ycvar "BUILD_SHARED_LIBS") [ystr "OFF"];
  yc_set (ycvar "CMAKE_VISIBILITY_INLINES_HIDDEN") [ystr "TRUE"];
  yc_set (ycvar "CMAKE_CXX_VISIBILITY_PRESET") [ystr "hidden"];

  (* if (CMAKE_COMPILER_IS_GNUCXX AND CMAKE_CXX_COMPILER_VERSION VERSION_LESS 5) *)
  yifthen
    (Yelu_langs.Yelu_cmake_normal_bool.EAnd
       (EVar "CMAKE_COMPILER_IS_GNUCXX",
        Yelu_langs.Yelu_cmake_string.ECmakeVersionLess
          (EVar "CMAKE_CXX_COMPILER_VERSION", ystr "5")))
    (yc_set (ycvar "BROKEN_LTO") [ystr "ON"]);

  (* if (NOT BROKEN_LTO AND CMAKE_VERSION VERSION_GREATER "3.8") *)
  yifthen
    (Yelu_langs.Yelu_cmake_normal_bool.EAnd
       (ynot (EVar "BROKEN_LTO"),
        Yelu_langs.Yelu_cmake_string.ECmakeVersionGreater
          (EVar "CMAKE_VERSION", ystr "3.8")))
    (ESeq [
      yc_apply (ystr "include") [ystr "CheckIPOSupported"];
      yc_apply (ystr "check_ipo_supported")
        [ystr "RESULT"; ystr "HAVE_IPO"];
      yifthen (EVar "HAVE_IPO")
        (yc_set (ycvar "CMAKE_INTERPROCEDURAL_OPTIMIZATION") [ystr "TRUE"]);
    ]);

  yc_apply (ystr "add_subdirectory") [ystr "../.."; ystr "fmt"];
  yc_apply (ystr "set_property")
    [ystr "TARGET"; ystr "fmt";
     ystr "PROPERTY"; ystr "POSITION_INDEPENDENT_CODE"; ystr "ON"];

  ECmakeAddLibrary {
    name = ystr "library-test"; type_ = Some "SHARED";
    sources = [ystr "library.cc"];
  };
  ECmakeTargetLinkLibraries {
    target = ystr "library-test"; visibility = "PRIVATE";
    items = [ystr "fmt::fmt"];
  };

  ECmakeAddExecutable { name = ystr "exe-test"; sources = [ystr "main.cc"] };
  ECmakeTargetLinkLibraries {
    target = ystr "exe-test"; visibility = "PRIVATE";
    items = [ystr "library-test"];
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
