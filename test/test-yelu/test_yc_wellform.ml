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
          (* audit #3 rollout: find / test / property-stub families *)
          pcase "find_library positional NAMES → reject"
            "find_library mylib NAMES foo bar" ~expect:true;
          pcase "find_library labeled ok"
            "find_library mylib ~names=[foo, bar]" ~expect:false;
          pcase "find_package positional REQUIRED → reject"
            "find_package Foo REQUIRED" ~expect:true;
          pcase "find_package positional COMPONENTS → reject (was silent drop)"
            "find_package Foo COMPONENTS a b" ~expect:true;
          pcase "find_package ~required ok"
            "find_package Foo ~required" ~expect:false;
          pcase "add_test positional NAME/COMMAND → reject"
            "add_test NAME t COMMAND runner 'a'" ~expect:true;
          pcase "add_test labeled ok"
            "add_test ~name='t' ~command=[runner, 'a']" ~expect:false;
          pcase "add_test bare shorthand ok"
            "add_test 't' 'runner' 'a'" ~expect:false;
          pcase "set_global_property positional PROPERTY → reject (yc-name leak)"
            "set_global_property PROPERTY FOO bar" ~expect:true;
          pcase "set_test_properties positional PROPERTIES → reject"
            "set_test_properties mytest PROPERTIES FOO bar" ~expect:true;
          pcase "message positional mode → reject"
            "message FATAL_ERROR 'boom'" ~expect:true;
          pcase "message ~mode labeled ok"
            "message ~mode=Fatal_error 'boom'" ~expect:false;
          (* a quoted text that reads like a mode is fine (EString, not bare) *)
          pcase "message quoted mode-like text ok"
            "message 'STATUS report'" ~expect:false;
          (* a *quoted* string equal to a cmake keyword is a literal, not the
             positional keyword — the guards match bare EVar only, so no
             false-positive reject (the keyword form is always bare). *)
          pcase "install_files quoted-keyword literal not rejected"
            "install_files 'lib' 'DESTINATION'" ~expect:false;
          pcase "set_property quoted-keyword literal not rejected"
            "set_property foo ~property=[X, 'APPEND']" ~expect:false;
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
          (* cmake-stdlib calls — silenced via Cmake_stdlib_names whitelist
             (discovered-cache pattern; see doc/yelu_cmake/discovered_cache.md).
             Before the stdlib cache landed (2026-06-21) these fired as
             closed-world Unknown_command; the test history before that
             commit asserted ~expect:true. *)
          ucase "stdlib call (cmake_parse_arguments) is silenced"
            "cmake_parse_arguments 'P' '' '' '' $ARGN" ~expect:false;
          ucase "stdlib call (check_language) is silenced"
            "check_language CXX" ~expect:false;
          ucase "stdlib call is case-insensitive"
            "CMAKE_PARSE_ARGUMENTS 'P' '' '' '' $ARGN" ~expect:false;
          (* A genuinely unknown external (not in stdlib whitelist) still
             escalates to closed-world fatal. *)
          ucase "unknown non-stdlib external flagged"
            "mystery_command_not_in_stdlib 'x'" ~expect:true;
          fcase "unknown non-stdlib external FATAL in closed world"
            "mystery_command_not_in_stdlib 'x'" ~expect:true;
          (* An [include] opens the world → unknowns demote to warning. *)
          fcase "include opens world → unknown is NOT fatal"
            "include 'Helpers.cmake'; mystery_command_not_in_stdlib 'x'"
            ~expect:false;
          (* Same for [find_package]. *)
          fcase "find_package opens world → unknown is NOT fatal"
            "find_package Foo; some_foo_command 'a' 'b'" ~expect:false;
          (* Same for [add_subdirectory]. *)
          fcase "add_subdirectory opens world → unknown is NOT fatal"
            "add_subdirectory 'sub'; sub_helper 'x'" ~expect:false;
          (* …but the warning still fires (we just don't escalate). *)
          ucase "open-world unknown still warns"
            "include 'Helpers.cmake'; mystery_command 'x'" ~expect:true ] );
      ( "function-def-typo shape (CST-level)",
        let has_def_typo src =
          let cst = match Yelu_langs.Yc_cst_parse.parse src with
            | Ok c -> c
            | Error e -> Alcotest.failf "parse %S: %s" src e
          in
          List.exists (W.check_cst cst) ~f:(function
            | W.Function_def_typo _ -> true
            | _ -> false)
        in
        let dcase name src ~expect =
          Alcotest.test_case name `Quick (fun () ->
            Alcotest.(check bool) name expect (has_def_typo src))
        in
        let typo_closed_world src =
          let cst = match Yelu_langs.Yc_cst_parse.parse src with
            | Ok c -> c
            | Error e -> Alcotest.failf "parse %S: %s" src e
          in
          List.find_map (W.check_cst cst) ~f:(function
            | W.Function_def_typo { closed_world; _ } -> Some closed_world
            | _ -> None)
        in
        let wcase name src ~expect =
          Alcotest.test_case name `Quick (fun () ->
            Alcotest.(check (option bool)) name expect (typo_closed_world src))
        in
        [ (* Escalation mirrors Unknown_command (audit #4): the shape is
             flagged in both worlds, but open-world is a WARNING (the name may
             be a cross-file command followed by a block), closed-world FATAL. *)
          dcase "open-world IDENT(args)(block) flagged"
            "include 'X.cmake'; funnnn join(result_var) ( result := 1 )"
            ~expect:true;
          wcase "open-world typo carries closed_world=false"
            "include 'X.cmake'; funnnn join(result_var) ( result := 1 )"
            ~expect:(Some false);
          (* Closed-world: caught by both Unknown_command and Function_def_typo. *)
          dcase "closed-world IDENT(args)(block) flagged"
            "funnnn join(result_var) ( result := 1 )" ~expect:true;
          wcase "closed-world typo carries closed_world=true"
            "funnnn join(result_var) ( result := 1 )" ~expect:(Some true);
          (* Real `fun` keyword goes through S_function — no command/block shape. *)
          dcase "real fun keyword not flagged"
            "fun join(result_var) ( result := 1 )" ~expect:false;
          (* In-file declared function called normally — no block after, OK. *)
          dcase "in-file call (no block) not flagged"
            "fun helper(x) ( $x := 'v' ); helper 'OUT'" ~expect:false;
          (* Typed primitive followed by a block — shouldn't fire (the
             primitive is known, so the gate stays open). *)
          dcase "typed primitive followed by block not flagged"
            "message 'hi'; ( $x := 1 )" ~expect:false ] );
      ( "reserved-name declarations (audit #4)",
        (* Production path (parse_and_check = CST parse + lower + all checks) —
           the same pipeline compile / fmt / LSP run. *)
        let has_reserved_decl src =
          match Yelu_langs.Yc_driver.parse_and_check src with
          | Error e -> Alcotest.failf "parse %S: %s" src e
          | Ok { Yelu_langs.Yc_driver.findings; _ } ->
            List.exists findings ~f:(function
              | W.Reserved_name { context; _ } ->
                String.is_substring context ~substring:"declaration"
                || String.equal context "let binding"
              | _ -> false)
        in
        let rcase name src ~expect =
          Alcotest.test_case name `Quick (fun () ->
            Alcotest.(check bool) name expect (has_reserved_decl src))
        in
        [ (* a var declared with a typed-primitive name now warns (references
             were already checked; declarations slipped through) *)
          rcase "command-name var declaration flagged"
            "add_custom_target := 'x'" ~expect:true;
          rcase "cache declaration with command name flagged"
            "cache list_append := 'y'" ~expect:true;
          rcase "ordinary var declaration ok"
            "my_var := 1" ~expect:false;
          rcase "let binding with command name flagged"
            "let math = '1' in message $math" ~expect:true ] );
      ( "unknown-kwarg (CST-level)",
        let has_unknown_kwarg src =
          let cst = match Yelu_langs.Yc_cst_parse.parse src with
            | Ok c -> c
            | Error e -> Alcotest.failf "parse %S: %s" src e
          in
          List.exists (W.check_cst cst) ~f:(function
            | W.Unknown_kwarg _ -> true
            | _ -> false)
        in
        let kcase name src ~expect =
          Alcotest.test_case name `Quick (fun () ->
            Alcotest.(check bool) name expect (has_unknown_kwarg src))
        in
        [ (* THE audit bug: ~public= silently dropped the libraries. *)
          kcase "link_lib ~public= → reject"
            "link_lib foo ~public=['bar', 'baz']" ~expect:true;
          kcase "link_lib ~banana= → reject"
            "link_lib foo ~banana='x' Public 'bar'" ~expect:true;
          (* target family has no ~out semantics — would be dropped *)
          kcase "link_lib ~out= → reject"
            "link_lib foo ~out=U Public 'bar'" ~expect:true;
          (* legit kwargs pass *)
          kcase "include_dirs ~system ok"
            "include_dirs fmt ~system 'inc'" ~expect:false;
          kcase "add_lib ~type ok"
            "add_lib foo ~type:STATIC 'a.c'" ~expect:false;
          kcase "string family ~out ok"
            "string_toupper 'x' ~out=U" ~expect:false;
          kcase "include_guard ~global ok"
            "include_guard ~global" ~expect:false;
          kcase "message ~mode ok"
            "message ~mode=Fatal_error 'boom'" ~expect:false;
          (* install_targets dotted artifact keys: known kind ok, unknown not *)
          kcase "install_targets ~library.destination ok"
            "install_targets $t ~library.destination='lib'" ~expect:false;
          kcase "install_targets ~banana.destination → reject"
            "install_targets $t ~banana.destination='lib'" ~expect:true;
          (* `:=` command-call sugar (S_assign_call) is covered too *)
          kcase ":= sugar legit kwarg ok"
            "v := get_property Target foo ~property=NAME" ~expect:false;
          kcase ":= sugar unknown kwarg → reject"
            "v := get_property Target foo ~banana=NAME" ~expect:true;
          (* unknown/user commands have an open vocabulary — exempt *)
          kcase "unknown command kwargs exempt"
            "include 'X.cmake'; my_own_macro ~foo=1 'a'" ~expect:false;
          (* assignment kwargs are S_assign, not a command — exempt *)
          kcase "assignment ~parent_scope exempt"
            "X := 1 ~parent_scope" ~expect:false ] ) ]
