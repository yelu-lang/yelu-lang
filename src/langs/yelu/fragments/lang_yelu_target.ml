open Base
open Lang_yelu_type

module Make_target_op (T : LANG_TYPES) = struct
  type yelu_items_with_kind = { kind : Lang_cmake.target_kind; items : T.expr list }
  type yelu_target_feature = { kind : Lang_cmake.target_kind; feature : string }

  type yelu_file_set = {
    kind : Lang_cmake.target_kind;
    type_ : Lang_cmake.file_set_type;
    base_dirs : T.expr list;
    files : T.expr list;
  }

  type yelu_target_sources_item =
    | Ytsi_plain of yelu_items_with_kind
    | Ytsi_file_set of yelu_file_set

  type yelu_target_stmt =
    | Ytgt_add_executable of {
        name : T.expr;
        exclude_from_all : bool;
        sources : T.expr list;
      }
    | Ytgt_add_library of {
        name : T.expr;
        type_ : Lang_cmake.library_type option;
        exclude_from_all : bool;
        sources : T.expr list;
      }
    | Ytgt_add_library_imported of {
        name : T.expr;
        lib_type : string option;
        global : bool;
      }
    | Ytgt_add_library_alias of { name : string; target : string }
    | Ytgt_add_executable_alias of { name : string; target : string }
    | Ytgt_include_directories of {
        target : T.expr;
        before : bool;
        system : bool;
        items : yelu_items_with_kind list;
      }
    | Ytgt_link_libraries of {
        targets : T.expr list;
        items : yelu_items_with_kind list;
      }
    | Ytgt_compile_definitions of {
        target : T.expr;
        items : yelu_items_with_kind list;
      }
    | Ytgt_compile_features of {
        target : T.expr;
        features : yelu_target_feature list;
      }
    | Ytgt_compile_options of {
        target : T.expr;
        before : bool;
        items : yelu_items_with_kind list;
      }
    | Ytgt_link_options of {
        target : T.expr;
        before : bool;
        items : yelu_items_with_kind list;
      }
    | Ytgt_link_directories of {
        target : T.expr;
        before : bool;
        items : yelu_items_with_kind list;
      }
    | Ytgt_sources of { target : T.expr; items : yelu_items_with_kind list }
    | Ytgt_sources_fs of {
        target : T.expr;
        items : yelu_target_sources_item list;
      }
    | Ytgt_precompile_headers of {
        target : T.expr;
        items : yelu_items_with_kind list;
      }
    | Ytgt_add_custom_command of {
        outputs : T.expr list;
        commands : Lang_cmake.custom_command list;
        depends : T.expr list;
        verbatim : bool;
        comment : string option;
      }
    | Ytgt_add_custom_command_target of {
        target : string;
        when_ : Lang_cmake.custom_when;
        commands : Lang_cmake.custom_command list;
        comment : string option;
        verbatim : bool;
      }
    | Ytgt_add_custom_target of {
        name : string;
        all : bool;
        commands : Lang_cmake.custom_command list;
        depends : T.expr list;
        comment : string option;
      }
    | Ytgt_add_dependencies of { target : string; dep : string }
end

module Make_target_check (T : LANG_TYPES) = struct
  include Make_target_op (T)
  let stage = Stage_typecheck

  let check ~(type_of : T.expr -> yelu_type) : yelu_target_stmt -> type_error list =
    let tgt e ctx = check_compat ~context:ctx Ty_target (type_of e) in
    let str e ctx = check_compat ~context:ctx Ty_string (type_of e) in
    let path e ctx = check_compat ~context:ctx Ty_path (type_of e) in
    let strs es ctx = List.concat_map es ~f:(fun e -> str e ctx) in
    let paths es ctx = List.concat_map es ~f:(fun e -> path e ctx) in
    let tgts es ctx = List.concat_map es ~f:(fun e -> tgt e ctx) in
    let items_as ty ctx items =
      List.concat_map items ~f:(fun { items = es; _ } ->
        List.concat_map es ~f:(fun e -> check_compat ~context:ctx ty (type_of e)))
    in
    function
    | Ytgt_add_executable { name; sources; _ } ->
      str name "add_executable name" @ paths sources "add_executable sources"
    | Ytgt_add_library { name; sources; _ } ->
      str name "add_library name" @ paths sources "add_library sources"
    | Ytgt_add_library_imported { name; _ } ->
      str name "add_library imported name"
    | Ytgt_add_library_alias _ | Ytgt_add_executable_alias _ -> []
    | Ytgt_include_directories { target; items; _ } ->
      tgt target "include_directories target"
      @ items_as Ty_path "include_directories" items
    | Ytgt_link_libraries { targets; items = _ } ->
      (* items are mixed (targets, flags, genexes) — bypass item check *)
      tgts targets "link_libraries targets"
    | Ytgt_compile_definitions { target; items } ->
      tgt target "compile_definitions target"
      @ items_as Ty_string "compile_definitions" items
    | Ytgt_compile_features { target; _ } ->
      (* features : yelu_target_feature list — no T.expr inside *)
      tgt target "compile_features target"
    | Ytgt_compile_options { target; items; _ } ->
      tgt target "compile_options target"
      @ items_as Ty_string "compile_options" items
    | Ytgt_link_options { target; items; _ } ->
      tgt target "link_options target"
      @ items_as Ty_string "link_options" items
    | Ytgt_link_directories { target; items; _ } ->
      tgt target "link_directories target"
      @ items_as Ty_path "link_directories" items
    | Ytgt_sources { target; items } ->
      tgt target "target_sources target"
      @ items_as Ty_path "target_sources" items
    | Ytgt_sources_fs { target; items = _ } ->
      (* file_set items have complex structure — bypass *)
      tgt target "target_sources_fs target"
    | Ytgt_precompile_headers { target; items } ->
      tgt target "precompile_headers target"
      @ items_as Ty_path "precompile_headers" items
    | Ytgt_add_custom_command { outputs; depends; _ } ->
      paths outputs "custom_command outputs"
      @ strs depends "custom_command depends"
    | Ytgt_add_custom_command_target _ -> []
    | Ytgt_add_custom_target { depends; _ } ->
      strs depends "custom_target depends"
    | Ytgt_add_dependencies _ -> []
end
