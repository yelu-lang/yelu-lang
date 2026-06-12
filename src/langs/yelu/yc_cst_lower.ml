(* yc_cst_lower — lower yc_cst → Yelu_cmake.expr (M1.2).

   This is the one-directional half of the layering: the per-command
   interpretation that yelu_parse does inline is reproduced here over the
   CST. Commands dispatch by name (the same family guards as
   p_stmt_inner_y1) to yelu_parse's token-free `_inner` functions; bespoke
   forms / conditions / atoms are constructed directly. Validated against
   the proven text→expr parser by the emit-bridge oracle
   (emit(lower(parse_cst t)) == emit(parse_ast t)) — see
   test_yc_cst_bridge. *)

open Base
(* Same constructor scope as yelu_parse, so the ECmake* / smart ctors
   resolve. ECmakeIfStmt lives in Yelu_cmake_if (used qualified below). *)
open Yelu_cmake
open Yelu_cmake_normal_bool
open Yelu_cmake_normal_int
open Yelu_cmake_store
open Yelu_cmake_string
open Yelu_cmake_file
open Yelu_cmake_normal_target
open Yelu_cmake_target
open Yelu_cmake_cmake_op
open Yelu_cmake_utils
module Cst = Yc_cst
module P = Yelu_parse

(* ── atoms (mirror p_expr_y1's expr decisions) ── *)
let rec lower_atom (a : Cst.atom) : expr =
  match a with
  | A_name n   -> EVar n
  | A_string s -> EString s
  | A_path s   -> EString s
  | A_eval s   ->
    if String.is_substring s ~substring:"$<" then ECmakeGenex s else EString s
  | A_bool b    -> EBool b
  | A_int n     -> EString (Int.to_string n)
  | A_keyword s -> EString s
  | A_target n  -> ETarget n
  | A_paren a   -> lower_atom a

let rec str_of_atom (a : Cst.atom) : string =
  match a with
  | A_name s | A_string s | A_path s | A_eval s | A_keyword s | A_target s -> s
  | A_bool true -> "ON"
  | A_bool false -> "OFF"
  | A_int n -> Int.to_string n
  | A_paren a -> str_of_atom a

(* ── conditions (mirror p_cond_atom_y1's typed construction) ── *)
let rec lower_cond (c : Cst.cond) : expr =
  match c with
  | C_not c -> ENot (lower_cond c)
  | C_and (a, b) -> EAnd (lower_cond a, lower_cond b)
  | C_or (a, b) -> EOr (lower_cond a, lower_cond b)
  | C_paren c -> lower_cond c
  | C_expr a -> lower_atom a
  | C_target a ->
    let e = lower_atom a in
    let target = match e with
      | ETarget _ | EString _ -> e
      | EVar name -> ETarget name
      | _ -> ETarget "?"
    in
    ECmakeTargetExists target
  | C_app (op, args) ->
    let name_of a = match lower_atom a with EVar s | EString s -> s | _ -> "?" in
    (match op, args with
     | "defined", [ a ] -> ECmakeVarDefined (name_of a)
     | "exists", [ a ] -> ECmakeFileExists (lower_atom a)
     | "is_dir", [ a ] -> ECmakeIsDirectory (lower_atom a)
     | "is_abs", [ a ] -> ECmakeIsAbsolute (lower_atom a)
     | "str_eq", [ a; b ] -> ECmakeStringEqual (lower_atom a, lower_atom b)
     | "eq", [ a; b ] -> EIntEqual (lower_atom a, lower_atom b)
     | "lt", [ a; b ] -> EIntLess (lower_atom a, lower_atom b)
     | "gt", [ a; b ] -> EIntGreater (lower_atom a, lower_atom b)
     | "ver_lt", [ a; b ] -> ECmakeVersionLess (lower_atom a, lower_atom b)
     | "ver_gt", [ a; b ] -> ECmakeVersionGreater (lower_atom a, lower_atom b)
     | "ver_eq", [ a; b ] -> ECmakeVersionEqual (lower_atom a, lower_atom b)
     | "ver_ge", [ a; b ] -> ECmakeVersionGreaterEqual (lower_atom a, lower_atom b)
     | "ver_le", [ a; b ] -> ECmakeVersionLessEqual (lower_atom a, lower_atom b)
     | "match", [ e; r ] ->
       ECmakeMatches { expr_ = lower_atom e; regex = str_of_atom r }
     | "list_in", [ item; list_ ] ->
       ECmakeInList { item = lower_atom item; list_ = lower_atom list_ }
     | "policy", [ a ] -> ECmakePolicyCheck (str_of_atom a)
     | _ -> EBool true (* unreachable for well-formed conds *))

(* ── command args → (positional exprs, kwargs) — mirror collect_command_args *)
let convert_args (args : Cst.arg list) : expr list * (string * expr) list =
  let pos =
    List.filter_map args ~f:(function Cst.Pos a -> Some (lower_atom a) | _ -> None)
  in
  let kwargs =
    List.concat_map args ~f:(function
      | Cst.Pos _ -> []
      | Cst.Kw (k, v) -> [ (k, lower_atom v) ]
      | Cst.Kw_flag k -> [ (k, EBool true) ]
      | Cst.Kw_list (k, items) -> List.map items ~f:(fun a -> (k, lower_atom a)))
  in
  (pos, kwargs)

let in_set names name = List.mem names name ~equal:String.equal

let target_names =
  [ "add_exe"; "add_lib"; "link_lib"; "include_dirs";
    "target_link_libraries"; "target_include_directories";
    "compile_defs"; "compile_opts"; "compile_feats";
    "target_compile_definitions"; "target_compile_options";
    "target_compile_features"; "target_link_options";
    "target_link_directories"; "link_opts"; "link_dirs"; "target_sources";
    "add_lib_alias"; "add_custom_target"; "add_custom_command" ]
let dir_names =
  [ "add_subdirectory"; "include_directories"; "add_compile_definitions";
    "add_compile_options"; "add_link_options"; "add_definitions";
    "link_directories" ]
let test_names = [ "enable_testing"; "add_test" ]
let property_names =
  [ "get_target_property"; "set_target_properties"; "set_property";
    "get_directory_property"; "set_directory_property"; "set_test_properties";
    "set_source_property"; "set_source_files_properties";
    "set_global_property"; "get_global_property" ]
let install_names =
  [ "install_targets"; "install_files"; "install_export"; "install_directory";
    "export"; "configure_package_config_file";
    "write_basic_package_version_file" ]
let try_names = [ "try_compile"; "try_run" ]
let cmake_op_names =
  [ "cmake_minimum_required"; "project"; "message"; "math"; "include";
    "include_guard"; "policy_set"; "enable_language"; "execute_process";
    "separate_arguments"; "cmake_call"; "cmake_eval"; "cmake_get_log_level";
    "yc_raw" ]

(* Dispatch a command by name to the matching family `_inner`, mirroring
   p_stmt_inner_y1's order + guards, with raw fallback. *)
let lower_command (name : string) (args : Cst.arg list) : expr =
  let pos, kwargs = convert_args args in
  (* Implicit target (syntax #1) is applied inside p_target_command_y1_inner,
     which both this CST path and the legacy parser call — single source of
     truth, so both stay consistent. *)
  let raw () = ECmakeRawCmd { name = cmake_name_of_yelu name; args = pos } in
  let via inner = match inner name pos kwargs with Some e -> e | None -> raw () in
  let prefix p = String.is_prefix name ~prefix:p in
  if prefix "string_" then via P.p_string_command_y1_inner
  else if prefix "list_" then via P.p_list_command_y1_inner
  else if prefix "path_" || String.equal name "get_filename_component" then
    via P.p_path_command_y1_inner
  else if prefix "file_" || String.equal name "configure_file" then
    via P.p_file_command_y1_inner
  else if in_set target_names name then via P.p_target_command_y1_inner
  else if in_set dir_names name then via P.p_dir_command_y1_inner
  else if in_set test_names name then via P.p_test_command_y1_inner
  else if in_set property_names name then via P.p_property_command_y1_inner
  else if prefix "find_" then via P.p_find_command_y1_inner
  else if in_set install_names name then via P.p_install_command_y1_inner
  else if in_set try_names name then via P.p_try_command_y1_inner
  else if in_set cmake_op_names name then via P.p_cmake_op_command_y1_inner
  else
    (* var-family + generic, mirroring p_var_stmt then p_generic_command *)
    let pos_atoms =
      List.filter_map args ~f:(function Cst.Pos a -> Some a | _ -> None)
    in
    match name, pos_atoms with
    | "set", name_atom :: rest ->
      let parent_scope, value_atoms =
        match List.last rest with
        | Some (Cst.A_name "PARENT_SCOPE") ->
          (true, List.drop_last_exn rest)
        | _ -> (false, rest)
      in
      yc_set ~parent_scope (str_of_atom name_atom)
        (List.map value_atoms ~f:lower_atom)
    | "option", name_atom :: rest ->
      (match rest with
       | [ help; value ] ->
         yc_option ~value:(lower_atom value) ~msg:(str_of_atom help)
           (str_of_atom name_atom)
       | [ value ] ->
         yc_option ~value:(lower_atom value) ~msg:"" (str_of_atom name_atom)
       | _ -> raw ())
    | "unset_cache", name_atom :: _ -> yc_unset_cache (str_of_atom name_atom)
    | _ ->
      if Yc_primitives.is_known_command name then raw ()
      else ECmakeApply { name = EString name; args = pos }

(* ── statements ── *)
let rec lower_stmt (s : Cst.stmt) : expr =
  match s.node with
  | S_command { name; args } -> lower_command name args
  | S_flow Break -> ECmakeBreak
  | S_flow Continue -> ECmakeContinue
  | S_flow Return -> ECmakeReturn { propagate_vars = [] }
  | S_block stmts -> lower_block stmts
  | S_let { var; value; body; ty = _ } ->
    ELet { var; value = lower_atom value; body = lower_stmt body }
  | S_while { cond; body } ->
    ECmakeWhile { cond = lower_cond cond; body = lower_block body }
  | S_function { name; params; body } ->
    ECmakeFunction { name = EString name; params; body = lower_block body }
  | S_macro { name; params; body } ->
    ECmakeMacro { name = EString name; params; body = lower_block body }
  | S_if { cond; then_; else_ } ->
    let else_ = match else_ with
      | None -> None
      | Some (Else_block b) -> Some (lower_block b)
      | Some (Else_if s) -> Some (lower_stmt s)
    in
    Yelu_cmake_if.ECmakeIfStmt { cond = lower_cond cond; then_ = lower_block then_; else_ }
  | S_foreach { var; iter; body } ->
    let body = lower_block body in
    (match iter with
     | F_range { start; stop } ->
       ECmakeForeachRange { loop_var = var; start; stop; step = None; body }
     | F_lists lists ->
       ECmakeForeachInList { loop_var = var; lists; items = []; body }
     | F_items items ->
       ECmakeForeach { loop_var = var; items = List.map items ~f:lower_atom; body })
  | S_assign { cache; name; values; kwargs; docstring; parent_scope } ->
    let vals = List.map values ~f:lower_atom in
    if cache then
      let cache_type =
        match List.Assoc.find kwargs ~equal:String.equal "type" with
        | Some a -> str_of_atom a
        | None -> "STRING"
      in
      let force = List.Assoc.mem kwargs ~equal:String.equal "force" in
      ECmakeSetCache
        { name; values = vals; cache_type;
          docstring = Option.value docstring ~default:""; force }
    else yc_set ~parent_scope name vals

and lower_block (b : Cst.block) : expr =
  match b with
  | [ s ] -> lower_stmt s
  | ss -> ESeq (List.map ss ~f:lower_stmt)

let lower_program (p : Cst.program) : expr =
  match p.stmts with
  | [ s ] -> lower_stmt s
  | ss -> ESeq (List.map ss ~f:lower_stmt)
