open Yelu_langs.Lang_yelu_cmake
open Yelu_langs.Lang_yelu_utils
open Step_common

(* Generates: Tests/CMakeOnly/LinkInterfaceLoop/CMakeLists.txt
   Tests cmake's handling of cyclic IMPORTED target link interfaces. *)
let cmd =
  ycmd_of_list
    [
      yc_minimum_required_s "3.10.";
      yc_project ~languages:[ Lang_c ] "LinkInterfaceLoop";
      (* A: SHARED IMPORTED that names itself as a link dependency — cycle *)
      add_lib_imported ~lib_type:"SHARED" (ytval "A");
      yc_set_target_properties
        (ytval "A")
        [
          ("IMPORTED_LINK_DEPENDENT_LIBRARIES", ytval "A");
          ("IMPORTED_LOCATION", ystr_eval "${CMAKE_CURRENT_BINARY_DIR}/dirA/A");
        ];
      (* B: SHARED IMPORTED that names itself in its link interface — cycle *)
      add_lib_imported ~lib_type:"SHARED" (ytval "B");
      yc_set_target_properties
        (ytval "B")
        [
          ("IMPORTED_LINK_INTERFACE_LIBRARIES", ytval "B");
          ("IMPORTED_LOCATION", ystr_eval "${CMAKE_CURRENT_BINARY_DIR}/dirB/B");
        ];
      (* C: SHARED library with empty link interface, depends on B and A *)
      add_lib ~type_:Lib_shared ~sources:[ yfile "lib.c" ] (ytval "C");
      yc_set_property
        ~targets:[ ytval "C" ]
        [ ("LINK_INTERFACE_LIBRARIES", ystr "") ];
      link_lib
        [ ytval "C" ]
        [ ytarget_def ~kind:Plain [ ytval "B"; ytval "A" ] ];
      add_exe ~sources:[ yfile "main.c" ] (ytval "main");
      link_lib
        [ ytval "main" ]
        [ ytarget_def ~kind:Plain [ ytval "C" ] ];
    ]

let () = print_cmake cmd
