(* Wellform checks — Y14: a variable declaration must not shadow an enum
   constructor (case-insensitively). The capitalized form (`set Public`) is a
   *parse* error (the lexer tokenizes it as the KEYWORD), so here we cover the
   lowercase/mixed shadow that parses and must be rejected at wellform. *)

open Base
module W = Yelu_langs.Yc_wellform

let parse s =
  match Yelu_langs.Yelu_parse.parse_program_y1 s with
  | Ok e -> e
  | Error e -> Alcotest.failf "parse %S: %s" s e

let has_enum_shadow src =
  List.exists (W.check_all (parse src)) ~f:(function
    | W.Enum_shadow _ -> true
    | _ -> false)

let case name src ~expect =
  Alcotest.test_case name `Quick (fun () ->
    Alcotest.(check bool) name expect (has_enum_shadow src))

(* Step 2 (labeled-only): a known command in the positional cmake-keyword form
   is a fatal wellform reject (use ~label= / yc_raw). *)
let has_positional src =
  List.exists (W.check_all (parse src)) ~f:(function
    | W.Positional_form _ -> true
    | _ -> false)

let pcase name src ~expect =
  Alcotest.test_case name `Quick (fun () ->
    Alcotest.(check bool) name expect (has_positional src))

let () =
  Alcotest.run "yc_wellform"
    [ ( "Y14 enum shadow",
        [ case "set public shadows Public" "public := 1" ~expect:true;
          case "cache static shadows Static" "cache static := 1" ~expect:true;
          case "option string shadows String" "option string 'h' ON" ~expect:true;
          (* a normal variable is fine *)
          case "result ok" "result := 1" ~expect:false;
          case "snake local ok" "my_var := 1" ~expect:false ] );
      ( "positional-form reject",
        [ pcase "install_targets positional → reject"
            "install_targets $t COMPONENT 'c' LIBRARY DESTINATION 'lib'" ~expect:true;
          (* the labeled form is the supported surface — no reject *)
          pcase "install_targets labeled ok"
            "install_targets $t ~component='c' ~library.destination='lib'" ~expect:false;
          pcase "add_custom_command positional → reject"
            "add_custom_command OUTPUT $o COMMAND $cc '-c' DEPENDS $s" ~expect:true;
          pcase "add_custom_command labeled ok"
            "add_custom_command ~output=[$o] ~command=[$cc, '-c'] ~depends=[$s]" ~expect:false;
          pcase "add_custom_target positional → reject"
            "add_custom_target doc ALL COMMAND $cc 'build'" ~expect:true;
          pcase "add_custom_target labeled ok"
            "add_custom_target doc ~all ~command=[$cc, 'build']" ~expect:false;
          pcase "install_directory positional → reject"
            "install_directory 'd' DESTINATION 'x' COMPONENT 'c'" ~expect:true;
          pcase "install_directory labeled ok"
            "install_directory 'd' ~destination='x' ~component='c'" ~expect:false;
          pcase "install_files positional → reject"
            "install_files $f DESTINATION 'x' COMPONENT 'c'" ~expect:true;
          pcase "install_files labeled ok"
            "install_files $f ~destination='x' ~component='c'" ~expect:false;
          pcase "install_export positional → reject"
            "install_export $e DESTINATION 'x' NAMESPACE 'ns::'" ~expect:true;
          pcase "install_export labeled ok"
            "install_export $e ~destination='x' ~namespace='ns::'" ~expect:false;
          pcase "set_property positional → reject"
            "set_property foo APPEND PROPERTY LINK_LIBRARIES 'bar'" ~expect:true;
          pcase "set_property labeled ok"
            "set_property foo ~append ~property=[LINK_LIBRARIES, 'bar']" ~expect:false;
          pcase "set_property Source entity stays (labeled)"
            "set_property Source 'main.c' ~property=[COMPILE_FLAGS, '-Wall']" ~expect:false;
          pcase "get_property positional → reject"
            "get_property Global PROPERTY USE_FOLDERS DEFINED ~out=v" ~expect:true;
          pcase "get_property labeled ok"
            "get_property Global ~property=USE_FOLDERS ~mode=Defined ~out=v" ~expect:false;
          pcase "set_target_properties positional → reject"
            "set_target_properties $t PROPERTY VERSION $V" ~expect:true;
          pcase "set_target_properties labeled ok"
            "set_target_properties $t ~properties={version=$V}" ~expect:false;
          pcase "execute_process positional → reject"
            "execute_process COMMAND $prog '--version' OUTPUT_VARIABLE v" ~expect:true;
          pcase "execute_process labeled ok"
            "execute_process ~command=[$prog, '--version'] ~output_variable=v" ~expect:false;
          pcase "set_source_files_properties positional → reject"
            "set_source_files_properties $f PROPERTIES GENERATED ON" ~expect:true;
          pcase "set_source_files_properties labeled ok"
            "set_source_files_properties $f ~properties={generated=ON}" ~expect:false;
          pcase "enable_language OPTIONAL → reject"
            "enable_language CUDA OPTIONAL" ~expect:true;
          pcase "enable_language ~optional ok"
            "enable_language CUDA ~optional" ~expect:false;
          pcase "cmake_minimum_required VERSION → reject"
            "cmake_minimum_required VERSION '3.8'" ~expect:true;
          pcase "cmake_minimum_required bare ok"
            "cmake_minimum_required '3.8'" ~expect:false;
          pcase "export TARGETS positional → reject"
            "export TARGETS a b NAMESPACE 'ns::'" ~expect:true;
          pcase "export ~targets labeled ok"
            "export ~targets=[a, b] ~namespace='ns::'" ~expect:false;
          pcase "export name form ok"
            "export $name ~file='f.cmake'" ~expect:false;
          pcase "configure_package_config_file positional → reject"
            "configure_package_config_file 'in' 'out' INSTALL_DESTINATION 'd'" ~expect:true;
          pcase "configure_package_config_file labeled ok"
            "configure_package_config_file 'in' 'out' ~install_destination='d'" ~expect:false;
          pcase "message positional mode → reject"
            "message FATAL_ERROR 'boom'" ~expect:true;
          pcase "message ~mode labeled ok"
            "message ~mode=Fatal_error 'boom'" ~expect:false;
          (* a quoted text that reads like a mode is fine (EString, not bare) *)
          pcase "message quoted mode-like text ok"
            "message 'STATUS report'" ~expect:false;
          (* a genuinely unknown/external command stays a plain raw — no reject
             (Positional_form is for the *labeled-only* family; unknown commands
             are flagged separately by Unknown_command below) *)
          pcase "unknown command not Positional_form"
            "some_external_macro 'a' 'b'" ~expect:false ] );
      ( "unknown-command (closed/open world)",
        let has_unknown src =
          List.exists (W.check_all (parse src)) ~f:(function
            | W.Unknown_command _ -> true
            | _ -> false)
        in
        let has_closed_unknown src =
          List.exists (W.check_all (parse src)) ~f:(function
            | W.Unknown_command { closed_world = true; _ } -> true
            | _ -> false)
        in
        let ucase name src ~expect =
          Alcotest.test_case name `Quick (fun () ->
            Alcotest.(check bool) name expect (has_unknown src))
        in
        let fcase name src ~expect =
          Alcotest.test_case name `Quick (fun () ->
            Alcotest.(check bool) name expect (has_closed_unknown src))
        in
        [ (* The fun→funnn typo case from the user report — closed world. *)
          ucase "fun typo (funnn) is flagged"
            "funnn join(result_var) ( $result_var := 'foo' )" ~expect:true;
          fcase "fun typo (funnn) is FATAL in closed world"
            "funnn join(result_var) ( $result_var := 'foo' )" ~expect:true;
          (* A typed yc primitive — no warning. *)
          ucase "typed primitive ok (project)"
            "project 'fmt' Cxx" ~expect:false;
          (* In-file function declaration — calls to it should NOT warn. *)
          ucase "self-call ok (function then call)"
            "fun helper(x) ( $x := 'v' ); helper 'OUT'" ~expect:false;
          (* Forward reference: cmake resolves function calls at call-time, so
             defining later in the file should also be OK (collect is whole-program). *)
          ucase "forward-ref ok (call then function)"
            "helper 'OUT'; fun helper(x) ( $x := 'v' )" ~expect:false;
          (* Genuinely unknown external (cmake-stdlib, etc.) — IS flagged. *)
          ucase "external command flagged"
            "cmake_parse_arguments 'P' '' '' '' $ARGN" ~expect:true;
          (* …and FATAL because there's no opening construct in this snippet. *)
          fcase "external command FATAL in closed world"
            "cmake_parse_arguments 'P' '' '' '' $ARGN" ~expect:true;
          (* But an [include] opens the world → warning class (not fatal),
             since the unknown command might come from the included module. *)
          fcase "include opens world → unknown is NOT fatal"
            "include 'Helpers.cmake'; cmake_parse_arguments 'P' '' '' '' $ARGN"
            ~expect:false;
          (* Same for [find_package]. *)
          fcase "find_package opens world → unknown is NOT fatal"
            "find_package Foo; some_foo_command 'a' 'b'" ~expect:false;
          (* Same for [add_subdirectory]. *)
          fcase "add_subdirectory opens world → unknown is NOT fatal"
            "add_subdirectory 'sub'; sub_helper 'x'" ~expect:false;
          (* …but the warning still fires (we just don't escalate). *)
          ucase "open-world unknown still warns"
            "include 'Helpers.cmake'; mystery_command 'x'" ~expect:true ] ) ]
