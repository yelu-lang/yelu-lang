open Yelu_langs.Yelu_cmake_ir_utils
open Yelu_langs.Lang_cmake
open Step_common_ir

(* cmake Tests/CMakeOnly/AllFindModules/CMakeLists.txt
   Full translation including file(GLOB) enumeration. *)

(* macro(do_find MODULE_NAME)
     message(STATUS "   Checking Find${MODULE_NAME}")
     find_package(${MODULE_NAME})
     set(CMAKE_MODULE_PATH "${ORIGINAL_MODULE_PATH}")
   endmacro() *)
let do_find_macro =
  yc_macro (ystr "do_find") ~args:[ "MODULE_NAME" ]
    [
      yc_message ~mode:Mm_status [ "   Checking Find${MODULE_NAME}" ];
      yc_find_package ~quiet:true "${MODULE_NAME}";
      yc_set (ycvar "CMAKE_MODULE_PATH") [ ystr_eval "${ORIGINAL_MODULE_PATH}" ];
    ]

(* macro(check_version_string MODULE_NAME VERSION_VAR)
   Simplified: drops execute_process/SKIP_CHECK (HG edge case) and the
   CMake_TEST config exclusion list. Core version-range checks preserved. *)
let check_version_string_macro =
  yc_macro (ystr "check_version_string") ~args:[ "MODULE_NAME"; "VERSION_VAR" ]
    [
      yifthen
        (ytruthy (ycstr "${MODULE_NAME}_FOUND"))
        (yif
           (yis_defined (ycstr "${VERSION_VAR}"))
           (ycmd_of_list
              [
                yc_message ~mode:Mm_status
                  [ "${VERSION_VAR}='${${VERSION_VAR}}'" ];
                yifthen
                  (ynot (ymatches (ystr_eval "${${VERSION_VAR}}") "^[0-9]"))
                  (yc_message ~mode:Mm_send_error
                     [ "unexpected: ${VERSION_VAR} does not begin with a \
                        decimal digit" ]);
                yifthen
                  (ystrequal (ystr_eval "${${VERSION_VAR}}") (ystr ""))
                  (yc_message ~mode:Mm_send_error
                     [ "unexpected: ${VERSION_VAR} is empty" ]);
                yifthen
                  (yversion_equal (ystr_eval "${${VERSION_VAR}}") (ystr "0"))
                  (yc_message ~mode:Mm_send_error
                     [ "unexpected: ${VERSION_VAR} is VERSION_EQUAL 0" ]);
                yifthen
                  (ynot
                     (yversion_greater
                        (ystr_eval "${${VERSION_VAR}}")
                        (ystr "0")))
                  (yc_message ~mode:Mm_send_error
                     [ "unexpected: ${VERSION_VAR} is NOT VERSION_GREATER 0" ]);
              ])
           (yc_message ~mode:Mm_send_error
              [ "${MODULE_NAME}_FOUND is set but version number variable \
                 ${VERSION_VAR} is NOT DEFINED" ]));
    ]

(* file(GLOB FIND_MODULES .../Modules/Find*.cmake) *)
let glob_modules =
  yc_file_glob (ycvar "FIND_MODULES")
    [ ystr_eval "${CMAKE_CURRENT_SOURCE_DIR}/../../../Modules/Find*.cmake" ]

(* foreach(FIND_MODULE IN LISTS FIND_MODULES)
     string(REGEX REPLACE ".*/Find(.*)\\.cmake$" "\\1" MODULE_NAME "${FIND_MODULE}")
     do_find(${MODULE_NAME})
   endforeach() *)
let glob_loop =
  yc_foreach_in ~lists:[ ycvar "FIND_MODULES" ] (ycvar "FIND_MODULE")
    (ycmd_of_list
       [
         yc_string_regex_replace
           ".*/Find(.*)\\.cmake$" (ystr "\\\\1")
           (ycvar "MODULE_NAME") [ ystr_eval "${FIND_MODULE}" ];
         yc_apply (ystr "do_find") [ ystr_eval "${MODULE_NAME}" ];
       ])

(* foreach(VTEST ALSA ... ZLIB) check_version_string(${VTEST} ${VTEST}_VERSION_STRING) *)
let vtest_version_string =
  yc_foreach (ycvar "VTEST")
    ~items:(List.map ystr
      [ "ALSA"; "BZIP2"; "CUPS"; "CURL"; "EXPAT"; "FREETYPE"; "GETTEXT"; "GIT";
        "GNUTLS"; "HG"; "HSPELL"; "LIBLZMA"; "LIBXML2"; "LIBXSLT"; "PNG"; "TIFF";
        "ZLIB" ])
    (yc_apply (ystr "check_version_string")
       [ ystr_eval "${VTEST}"; ystr_eval "${VTEST}_VERSION_STRING" ])

(* foreach(VTEST Boost BZip2 ... ZLIB) check_version_string(${VTEST} ${VTEST}_VERSION) *)
let vtest_version =
  yc_foreach (ycvar "VTEST")
    ~items:(List.map ystr
      [ "Armadillo"; "BISON"; "Boost"; "BZip2"; "BZIP2"; "Doxygen"; "DOXYGEN";
        "EXPAT"; "FLEX"; "Freetype"; "Gettext"; "Git"; "GnuTLS"; "GNUTLS";
        "HDF5"; "Hg"; "HSPELL"; "Jasper"; "JPEG"; "LibArchive"; "LibLZMA";
        "LIBLZMA"; "LibXml2"; "LibXslt"; "Lua"; "OpenSSL"; "OPENSSL"; "Perl";
        "PkgConfig"; "PNG"; "PostgreSQL"; "Protobuf"; "SDL"; "SWIG"; "TIFF";
        "wxWidgets"; "ZLIB" ])
    (yc_apply (ystr "check_version_string")
       [ ystr_eval "${VTEST}"; ystr_eval "${VTEST}_VERSION" ])

let cmd =
  ycmd_of_list
    [
      yc_minimum_required_s "3.10.";
      yc_project "AllFindModules";
      yc_message ~mode:Mm_status [ "CTEST_FULL_OUTPUT" ];
      yc_set (ycvar "ORIGINAL_MODULE_PATH") [ ystr_eval "${CMAKE_MODULE_PATH}" ];
      do_find_macro;
      check_version_string_macro;
      glob_modules;
      glob_loop;
      vtest_version_string;
      vtest_version;
    ]

let () = print_cmake cmd
