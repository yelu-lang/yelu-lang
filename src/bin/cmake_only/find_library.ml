open Yelu_langs.Yelu_cmake_utils
open Yelu_langs.Lang_cmake
open Step_common_ir

(* cmake Tests/CMakeOnly/find_library/CMakeLists.txt *)

(* macro(test_find_library desc expected) *)
let test_find_library_macro =
  let inner_if =
    yif
      (ynot (ystrequal (ystr_eval "${REL_LIB}") (ystr_eval "${expected}")))
      (yc_message ~mode:Mm_send_error
         [ "Library ${expected} found as [${REL_LIB}]${desc}" ])
      (yifthen
         (ytruthy (ycstr "CMAKE_FIND_DEBUG_MODE"))
         (yc_message ~mode:Mm_status
            [ "Library ${expected} found as [${REL_LIB}]${desc}" ]))
  in
  let outer_if =
    yif
      (ytruthy (ycstr "LIB"))
      (ycmd_of_list
         [
           yc_file_relative_path
             ~var:(ycstr "REL_LIB")
             ~base:(ystr_eval "${CMAKE_CURRENT_SOURCE_DIR}")
             (ystr_eval "${LIB}");
           inner_if;
         ])
      (yc_message ~mode:Mm_send_error [ "Library ${expected} NOT FOUND${desc}" ])
  in
  yc_macro (ystr "test_find_library") ~args:[ "desc"; "expected" ]
    [
      yc_unset_cache (ycvar "LIB");
      yc_apply (ystr "find_library")
        [
          ycstr "LIB";
          ystr_eval "${ARGN}";
          ystr "NO_DEFAULT_PATH";
        ];
      outer_if;
    ]

(* macro(test_find_library_subst expected) *)
let test_find_library_subst_macro =
  yc_macro (ystr "test_find_library_subst") ~args:[ "expected" ]
    [
      yc_get_filename_component ~mode:"PATH" (ycvar "dir") (ystr_eval "${expected}");
      yc_get_filename_component ~mode:"NAME" (ycvar "name") (ystr_eval "${expected}");
      yc_string_regex_replace "lib/?[36Xx][24Y3][Z2]*" (ystr "lib") (ycvar "dir")
        [ ystr_eval "${dir}" ];
      yc_apply (ystr "test_find_library")
        [
          ystr_eval ", searched as ${dir}";
          ystr_eval "${expected}";
          ystr "NAMES";
          ystr_eval "${name}";
          ystr "PATHS";
          ystr_eval "${CMAKE_CURRENT_SOURCE_DIR}/${dir}";
        ];
    ]

let cmd =
  ycmd_of_list
    [
      yc_minimum_required_s "3.10.";
      yc_project ~languages:[ Lang_none ] "FindLibraryTest";
      yc_set (ycvar "CMAKE_FIND_DEBUG_MODE") [ ystr "1" ];
      test_find_library_macro;
      test_find_library_subst_macro;
      yc_set (ycvar "CMAKE_FIND_LIBRARY_PREFIXES") [ ystr "lib" ];
      yc_set (ycvar "CMAKE_FIND_LIBRARY_SUFFIXES") [ ystr ".a" ];
      yc_set_global_property
        [ ("FIND_LIBRARY_USE_LIBX32_PATHS", ybool true) ];
      yc_set_global_property
        [ ("FIND_LIBRARY_USE_LIB32_PATHS", ybool true) ];
      yc_set_global_property
        [ ("FIND_LIBRARY_USE_LIB64_PATHS", ybool true) ];
      yc_set (ycvar "CMAKE_INTERNAL_PLATFORM_ABI") [ ystr "ELF" ];
      yc_set (ycvar "CMAKE_SIZEOF_VOID_P") [ ystr "4" ];
      yc_foreach ~items:
        [
          ystr "lib/32/libtest5.a";
          ystr "lib/A/lib/libtest1.a";
          ystr "lib/A/lib32/libtest3.a";
          ystr "lib/A/libtest1.a";
          ystr "lib/libtest1.a";
          ystr "lib/libtest2.a";
          ystr "lib/libtest3.a";
          ystr "lib/libtest3.a";
          ystr "lib32/A/lib/libtest2.a";
          ystr "lib32/A/lib32/libtest4.a";
          ystr "lib32/A/libtest4.a";
          ystr "lib32/libtest4.a";
        ] (ycvar "lib")
        (yc_apply (ystr "test_find_library_subst") [ ystr_eval "${lib}" ]);
      yc_set (ycvar "CMAKE_SIZEOF_VOID_P") [ ystr "8" ];
      yc_foreach ~items:
        [
          ystr "lib/64/libtest2.a";
          ystr "lib/A/lib64/libtest3.a";
          ystr "lib/libtest3.a";
          ystr "lib64/A/lib/libtest2.a";
          ystr "lib64/A/lib64/libtest1.a";
          ystr "lib64/A/libtest1.a";
          ystr "lib64/libtest1.a";
        ] (ycvar "lib64")
        (yc_apply (ystr "test_find_library_subst") [ ystr_eval "${lib64}" ]);
      yc_set (ycvar "CMAKE_INTERNAL_PLATFORM_ABI") [ ystr "ELF X32" ];
      yc_set (ycvar "CMAKE_SIZEOF_VOID_P") [ ystr "4" ];
      yc_foreach ~items:
        [
          ystr "lib/x32/libtest2.a";
          ystr "lib/A/libx32/libtest3.a";
          ystr "lib/libtest3.a";
          ystr "libx32/A/lib/libtest2.a";
          ystr "libx32/A/libx32/libtest1.a";
          ystr "libx32/A/libtest1.a";
          ystr "libx32/libtest1.a";
        ] (ycvar "libx32")
        (yc_apply (ystr "test_find_library_subst") [ ystr_eval "${libx32}" ]);
      yc_apply (ystr "test_find_library")
        [
          ystr "";
          ystr "A/libtestA.a";
          ystr "NAMES";
          ystr "testA";
          ystr "testB";
          ystr "PATHS";
          ycref_path source_this "A";
          ycref_path source_this "B";
        ];
      yc_apply (ystr "test_find_library")
        [
          ystr "";
          ystr "B/libtestB.a";
          ystr "NAMES";
          ystr "testB";
          ystr "testA";
          ystr "PATHS";
          ycref_path source_this "A";
          ycref_path source_this "B";
        ];
      yc_apply (ystr "test_find_library")
        [
          ystr "";
          ystr "A/libtestA.a";
          ystr "NAMES";
          ystr "testB";
          ystr "testA";
          ystr "NAMES_PER_DIR";
          ystr "PATHS";
          ycref_path source_this "A";
          ycref_path source_this "B";
        ];
      yc_set (ycvar "CMAKE_FIND_LIBRARY_CUSTOM_LIB_SUFFIX") [ ystr "XYZ" ];
      yc_foreach ~items:
        [
          ystr "lib/XYZ/libtest1.a";
          ystr "lib/A/libXYZ/libtest2.a";
          ystr "lib/libtest3.a";
          ystr "libXYZ/A/lib/libtest4.a";
          ystr "libXYZ/A/libXYZ/libtest5.a";
          ystr "libXYZ/A/libtest6.a";
          ystr "libXYZ/libtest7.a";
        ] (ycvar "libXYZ")
        (yc_apply (ystr "test_find_library_subst") [ ystr_eval "${libXYZ}" ]);
    ]

let () = print_cmake cmd
