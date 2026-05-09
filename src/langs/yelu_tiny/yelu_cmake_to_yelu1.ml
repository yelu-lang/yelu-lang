open Base
open Yelu_tiny
open Yelu_surface_cmake_store
open Yelu_theory_bool
open Yelu_theory_target
open Yelu_surface_cmake_list
open Yelu_surface_cmake_path
open Yelu_surface_cmake_string
open Yelu_surface_cmake_target

module Old = Lang_yelu_cmake

exception Bridge_error of string

let fail fmt = Fmt.kstr (fun msg -> raise (Bridge_error msg)) fmt

let cvar_name ({ name; _ } : Old.tc_name) = name

let target_name = function
  | Old.Yexpr_name { ns = Old.Ns_target; name }
  | Old.Yexpr_string (Old.Ycs_path name | Old.Ycs_keyword name | Old.Ycs_string name | Old.Ycs_eval name)
  | Old.Yexpr_var (Old.Yvar name) -> name
  | _ -> fail "unsupported target name expression for Yelu1 bridge"

let rec expr : Old.yelu_expr -> Yelu_tiny.expr = function
  | Yexpr_string (Ycs_path s | Ycs_keyword s | Ycs_string s | Ycs_eval s) ->
    EString s
  | Yexpr_bool b -> EBool b
  | Yexpr_var (Yvar name) -> EVar name
  | Yexpr_name { ns = Ns_var; name } -> EVar name
  | Yexpr_name { ns = Ns_target; name } -> ETarget name
  | Yexpr_name { name; _ } -> EString name
  | Yexpr_not cond -> ENot (expr cond)
  | Yexpr_and (left, right) -> EAnd (expr left, expr right)
  | Yexpr_or (left, right) -> EOr (expr left, expr right)
  | Yexpr_str_equal (left, right) -> ECmakeStringEqual (expr left, expr right)
  | Yexpr_is_defined { name; _ } -> ECmakeVarDefined name
  | Yexpr_is_target { name; _ } -> ECmakeTargetExists name
  | _ -> fail "unsupported yelu_cmake expression for Yelu1 bridge"

let one_input ~op = function
  | [ input ] -> expr input
  | inputs ->
    fail "%s bridge currently requires exactly one input, got %d"
      op (List.length inputs)

let string_statement : Old.yelu_string_stmt -> Yelu_tiny.expr = function
  | Ystr_concat { out; inputs } ->
    ECmakeStringConcat { out = cvar_name out; inputs = List.map inputs ~f:expr }
  | Ystr_toupper { string; out } ->
    ECmakeStringToupper { input = expr string; out = cvar_name out }
  | Ystr_replace { match_string; replace_string; out; inputs } ->
    ECmakeStringReplace
      {
        match_ = expr match_string;
        replace = expr replace_string;
        input = one_input ~op:"string(REPLACE)" inputs;
        out = cvar_name out;
      }
  | Ystr_length { string; out } ->
    ECmakeStringLength { input = expr string; out = cvar_name out }
  | Ystr_compare { op = Sco_equal; string1; string2; out } ->
    ESetVar (cvar_name out, ECmakeStringEqual (expr string1, expr string2))
  | _ -> fail "unsupported yelu_cmake string statement for Yelu1 bridge"

let var_statement : Old.yelu_var_stmt -> Yelu_tiny.expr = function
  | Yvar_set { cvar; values = [ value ]; parent_scope = false } ->
    ESetVar (cvar_name cvar, expr value)
  | Yvar_set { cvar; values = []; parent_scope = false } ->
    ESetVar (cvar_name cvar, EString "")
  | Yvar_set { values; parent_scope = false; _ } ->
    fail "set() bridge currently requires zero or one value, got %d"
      (List.length values)
  | Yvar_set { parent_scope = true; _ } ->
    fail "set(PARENT_SCOPE) is outside the first Yelu1 bridge slice"
  | _ -> fail "unsupported yelu_cmake variable statement for Yelu1 bridge"

let list_index ~indices =
  match indices with
  | [ index ] -> EInt index
  | [] -> fail "list(GET) bridge requires one index; parser does not expose one yet"
  | _ -> fail "list(GET) bridge currently supports exactly one index"

let list_statement : Old.yelu_list_stmt -> Yelu_tiny.expr = function
  | Ylist_append { cvar; values } ->
    ECmakeListAppend { list = cvar_name cvar; items = List.map values ~f:expr }
  | Ylist_get { cvar; indices; out } ->
    ECmakeListGet
      { list = cvar_name cvar; index = list_index ~indices; out = cvar_name out }
  | Ylist_length { cvar; out } ->
    ECmakeListLength { list = cvar_name cvar; out = cvar_name out }
  | Ylist_join { cvar; glue; out } ->
    ECmakeListJoin { list = cvar_name cvar; glue = expr glue; out = cvar_name out }
  | _ -> fail "unsupported yelu_cmake list statement for Yelu1 bridge"

let path_statement : Old.yelu_path_stmt -> Yelu_tiny.expr = function
  | Ypath_set { path_var; input; normalize } ->
    ECmakePathSet { path = cvar_name path_var; input = expr input; normalize }
  | Ypath_get { path_var; field = Cpf_filename; out } ->
    ECmakePathGetFilename { path = cvar_name path_var; out = cvar_name out }
  | Ypath_normal_path { path_var; out } ->
    ECmakePathNormalPath
      { path = cvar_name path_var; out = Option.map out ~f:cvar_name }
  | _ -> fail "unsupported yelu_cmake path statement for Yelu1 bridge"

let visibility_of_kind = function
  | Old.Public -> "PUBLIC"
  | Old.Private -> "PRIVATE"
  | Old.Interface -> "INTERFACE"
  | Old.Plain -> "PRIVATE"

let build_command ({ command; args } : Lang_cmake.custom_command) =
  { command; args }

let target_statement : Old.yelu_target_stmt -> Yelu_tiny.expr = function
  | Ytgt_add_executable { name; sources; exclude_from_all = false } ->
    ECmakeAddExecutable { name = target_name name; sources = List.map sources ~f:expr }
  | Ytgt_add_executable { exclude_from_all = true; _ } ->
    fail "add_executable(EXCLUDE_FROM_ALL) is outside the first Yelu1 bridge slice"
  | Ytgt_sources { target; items } ->
    items
    |> List.map ~f:(fun ({ kind; items } : Old.yelu_items_with_kind) ->
      ECmakeTargetSources
        {
          target = target_name target;
          visibility = visibility_of_kind kind;
          sources = List.map items ~f:expr;
        })
    |> ESeq
  | Ytgt_link_libraries { targets = [ target ]; items } ->
    items
    |> List.map ~f:(fun ({ kind; items } : Old.yelu_items_with_kind) ->
      ECmakeTargetLinkLibraries
        {
          target = target_name target;
          visibility = visibility_of_kind kind;
          items = List.map items ~f:expr;
        })
    |> ESeq
  | Ytgt_link_libraries { targets; _ } ->
    fail "target_link_libraries bridge currently supports exactly one target, got %d"
      (List.length targets)
  | Ytgt_include_directories { target; before = false; system = false; items } ->
    items
    |> List.map ~f:(fun ({ kind; items } : Old.yelu_items_with_kind) ->
      ECmakeTargetIncludeDirectories
        {
          target = target_name target;
          visibility = visibility_of_kind kind;
          dirs = List.map items ~f:expr;
        })
    |> ESeq
  | Ytgt_include_directories { before = true; _ } ->
    fail "target_include_directories(BEFORE) is outside the current Yelu1 bridge slice"
  | Ytgt_include_directories { system = true; _ } ->
    fail "target_include_directories(SYSTEM) is outside the current Yelu1 bridge slice"
  | Ytgt_add_custom_target { name; all; commands; depends; comment } ->
    ECmakeAddCustomTarget
      {
        name;
        all;
        commands = List.map commands ~f:build_command;
        depends = List.map depends ~f:expr;
        comment;
      }
  | _ -> fail "unsupported yelu_cmake target statement for Yelu1 bridge"

let rec stmt : Old.yelu_stmt -> Yelu_tiny.expr = function
  | Ys_string string_stmt -> string_statement string_stmt
  | Ys_list list_stmt -> list_statement list_stmt
  | Ys_path path_stmt -> path_statement path_stmt
  | Ys_target target_stmt -> target_statement target_stmt
  | Ys_var var_stmt -> var_statement var_stmt
  | Ylet { var = Yvar name; value } -> ESetVar (name, expr value)
  | Yif { cond; then_; else_ } ->
    Yelu_surface_cmake_if.ECmakeIfStmt
      {
        cond = expr cond;
        then_ = stmt then_;
        else_ = Option.map else_ ~f:stmt;
      }
  | Ystmt_list stmts -> ESeq (List.map stmts ~f:stmt)
  | _ -> fail "unsupported yelu_cmake statement for Yelu1 bridge"
