(* Yelu parser — two-pass: lex to token list, then parse with pure OCaml.
   Avoids Angstrom backtracking issues. Uses plain match, no binding operators. *)

open Base
open Lang_yelu_cmake
open Lang_yelu_lexer

type 'a parser = token list -> ('a * token list) option

(* ============================================================
   Token matchers — plain functions, no operator magic
   ============================================================ *)

let kw s toks =
  let expect = match s with
    | "let" -> LET | "in" -> IN | "if" -> IF | "then" -> THEN | "else" -> ELSE
    | "foreach" -> FOREACH | "function" -> FUNCTION | "fun" -> FUNCTION | "macro" -> MACRO
    | "while" -> WHILE | "break" -> BREAK | "continue" -> CONTINUE | "return" -> RETURN
    | "target" -> TARGET | "cvar" -> CVAR | "cache" -> CACHE | "RANGE" -> RANGE
    | _ -> EOF in
  match toks with
  | IDENT s' :: rest when String.equal s s' -> Some ((), rest)
  | t :: rest when Poly.equal t expect -> Some ((), rest)
  | _ -> None

let delim t toks = match toks with t' :: rest when Poly.equal t t' -> Some ((), rest) | _ -> None
let lbrace = delim LBRACE and rbrace = delim RBRACE
let lbrack = delim LBRACK and rbrack = delim RBRACK
let lparen = delim LPAREN and rparen = delim RPAREN
let eq_tok = delim EQ and dotdot = delim DOTDOT

let p_ident toks = match toks with IDENT s :: rest -> Some (s, rest) | _ -> None
let p_path_s toks = match toks with PATH s :: rest -> Some (s, rest) | _ -> None
let p_string_s toks = match toks with STRING s :: rest -> Some (s, rest) | _ -> None
let p_eval_s toks = match toks with EVAL s :: rest -> Some (s, rest) | _ -> None
let p_keyword_s toks = match toks with KEYWORD s :: rest -> Some (s, rest) | _ -> None
let p_bool_v toks = match toks with BOOL b :: rest -> Some (b, rest) | _ -> None
let p_int_v toks = match toks with INT n :: rest -> Some (n, rest) | _ -> None

let map f p toks = match p toks with Some (x, r) -> Some (f x, r) | None -> None
let p_path = map (fun s -> Yexpr_string (Ycs_path s)) p_path_s
let p_string = map (fun s -> Yexpr_string (Ycs_string s)) p_string_s
let p_eval = map (fun s -> Yexpr_string (Ycs_eval s)) p_eval_s
let p_bool = map (fun b -> Yexpr_bool b) p_bool_v

(* ============================================================
   Expressions — try each alternative on the same token list
   ============================================================ *)

let p_target_ref toks =
  (* Target Foo -- bare identifier after Target keyword *)
  match toks with
  | TARGET :: IDENT name :: rest -> Some (Yexpr_name { ns = Ns_target; name }, rest)
  | _ -> (
    (* Legacy: target "Foo" -- quoted path *)
    match kw "target" toks with
    | Some ((), r) -> map (fun s -> Yexpr_name { ns = Ns_target; name = s }) p_path_s r
    | None -> None)

let p_cvar_ref toks = match kw "cvar" toks with
  | Some ((), r) -> map (fun s -> Yexpr_name { ns = Ns_var; name = s }) p_path_s r
  | None -> None

let p_var_ref = map (fun name -> Yexpr_var (Yvar name)) p_ident

let p_int_expr = map (fun n -> Yexpr_string (Ycs_string (Int.to_string n))) p_int_v

let p_expr toks =
  match p_target_ref toks with Some r -> Some r | None ->
  match p_cvar_ref toks with Some r -> Some r | None ->
  match p_eval toks with Some r -> Some r | None ->
  match p_path toks with Some r -> Some r | None ->
  match p_string toks with Some r -> Some r | None ->
  match p_bool toks with Some r -> Some r | None ->
  match p_int_expr toks with Some r -> Some r | None ->
  p_var_ref toks

(* ============================================================
   Conditions
   ============================================================ *)

let rec p_cond_atom toks =
  match toks with
  (* boolean logic *)
  | IDENT s :: rest when String.equal s "not" ->
    map (fun c -> Yexpr_not c) p_cond_atom rest
  (* target / defined *)
  | TARGET :: rest ->
    map (fun e -> match e with
      | Yexpr_name t -> Yexpr_is_target t
      | Yexpr_string (Ycs_string s) -> Yexpr_is_target { ns = Ns_target; name = s }
      | Yexpr_string (Ycs_path s) -> Yexpr_is_target { ns = Ns_target; name = s }
      | _ -> Yexpr_is_target { ns = Ns_target; name = "?" }) p_expr rest
  | IDENT s :: rest when String.equal s "defined" ->
    map (fun e -> match e with
      | Yexpr_name t -> Yexpr_is_defined t
      | Yexpr_string (Ycs_string s) -> Yexpr_is_defined { ns = Ns_var; name = s }
      | Yexpr_string (Ycs_path s) -> Yexpr_is_defined { ns = Ns_var; name = s }
      | _ -> Yexpr_is_defined { ns = Ns_var; name = "?" }) p_expr rest
  (* string comparison *)
  | IDENT s :: rest when String.equal s "str_eq" ->
    (match p_expr rest with Some (a, rest) -> map (fun b -> Yexpr_str_equal (a, b)) p_expr rest | None -> None)
  | IDENT s :: rest when String.equal s "str_lt" ->
    (match p_expr rest with Some (a, rest) -> map (fun b -> Yexpr_str_less (a, b)) p_expr rest | None -> None)
  | IDENT s :: rest when String.equal s "str_gt" ->
    (match p_expr rest with Some (a, rest) -> map (fun b -> Yexpr_str_greater (a, b)) p_expr rest | None -> None)
  (* numeric comparison *)
  | IDENT s :: rest when String.equal s "eq" ->
    (match p_expr rest with Some (a, rest) -> map (fun b -> Yexpr_equal (a, b)) p_expr rest | None -> None)
  | IDENT s :: rest when String.equal s "lt" ->
    (match p_expr rest with Some (a, rest) -> map (fun b -> Yexpr_less (a, b)) p_expr rest | None -> None)
  | IDENT s :: rest when String.equal s "gt" ->
    (match p_expr rest with Some (a, rest) -> map (fun b -> Yexpr_greater (a, b)) p_expr rest | None -> None)
  (* version comparison *)
  | IDENT s :: rest when String.equal s "ver_lt" ->
    (match p_expr rest with Some (a, rest) -> map (fun b -> Yexpr_ver_less (a, b)) p_expr rest | None -> None)
  | IDENT s :: rest when String.equal s "ver_gt" ->
    (match p_expr rest with Some (a, rest) -> map (fun b -> Yexpr_ver_greater (a, b)) p_expr rest | None -> None)
  | IDENT s :: rest when String.equal s "ver_eq" ->
    (match p_expr rest with Some (a, rest) -> map (fun b -> Yexpr_ver_equal (a, b)) p_expr rest | None -> None)
  (* match / list / filesystem *)
  | IDENT s :: rest when String.equal s "match" ->
    (match p_expr rest with Some (e, rest) -> map (fun regex -> Yexpr_matches (e, regex)) p_string_s rest | None -> None)
  | IDENT s :: rest when String.equal s "list_in" ->
    (match p_expr rest with Some (e, rest) -> map (fun l -> Yexpr_in_list (e, l)) p_expr rest | None -> None)
  | IDENT s :: rest when String.equal s "exists" ->
    map (fun e -> Yexpr_exists e) p_expr rest
  | IDENT s :: rest when String.equal s "is_dir" ->
    map (fun e -> Yexpr_is_directory e) p_expr rest
  | IDENT s :: rest when String.equal s "is_abs" ->
    map (fun e -> Yexpr_is_absolute e) p_expr rest
  | IDENT s :: rest when String.equal s "policy" ->
    (match p_ident rest with Some (id, rest) -> Some (Yexpr_policy id, rest) | None -> None)
  (* bare expression = truthy *)
  | _ -> p_expr toks

let p_cond toks =
  match p_cond_atom toks with
  | None -> None
  | Some (c1, rest) ->
    let rec loop acc = function
      | IDENT s :: r when String.equal s "and" ->
        (match p_cond_atom r with Some (c, r') -> loop (Yexpr_and (acc, c)) r' | None -> Some (acc, r))
      | IDENT s :: r when String.equal s "or" ->
        (match p_cond_atom r with Some (c, r') -> loop (Yexpr_or (acc, c)) r' | None -> Some (acc, r))
      | r -> Some (acc, r) in
    loop c1 rest

(* ============================================================
   Command builder (pure, no recursion into statements)
   ============================================================ *)


(* Helper: extract ~out labeled arg as tc_name *)
let out_var kwargs =
  match List.Assoc.find kwargs ~equal:String.equal "out" with
  | Some (Yexpr_name { ns = Ns_var; name }) -> { ns = Ns_var; name }
  | Some (Yexpr_var (Yvar name)) -> { ns = Ns_var; name }
  | _ -> { ns = Ns_var; name = "?" }

(* Helper: extract first positional arg as tc_name *)
let cvar_of_expr = function
  | Yexpr_name n -> n
  | Yexpr_var (Yvar name) -> { ns = Ns_var; name }
  | _ -> { ns = Ns_var; name = "?" }

let build_stmt name args kwargs record_args =
  match name, args with
  | "cmake_minimum_required", [v] ->
    let s = match v with Yexpr_string (Ycs_path s') | Yexpr_string (Ycs_string s') -> s' | _ -> "3.20" in
    Some (Ys_cmake (Ycmake_minimum_required { min = Lang_cmake_utils.version_of_string s; max = None }))
  | "project", [name_e] ->
    let s = match name_e with Yexpr_string (Ycs_path s') | Yexpr_string (Ycs_string s') -> s' | _ -> "Project" in
    Some (Ys_cmake (Ycmake_project { name = s; version = None; languages = [] }))
  | "message", _ ->
    let texts = List.map args ~f:(fun e -> match e with Yexpr_string (Ycs_path s) | Yexpr_string (Ycs_string s) -> s | _ -> "") in
    Some (Ys_cmake (Ycmake_message { mode = Lang_cmake.Mm_status; texts }))
  | "set", cvar :: values ->
    let n = match cvar with Yexpr_name { name; _ } -> { ns = Ns_var; name } | Yexpr_string (Ycs_path s) -> { ns = Ns_var; name = s } | _ -> { ns = Ns_var; name = "?" } in
    Some (Ys_var (Yvar_set { cvar = n; values; parent_scope = false }))
  | "option", [cvar; value] ->
    let n = match cvar with Yexpr_name { name; _ } -> { ns = Ns_var; name } | _ -> { ns = Ns_var; name = "?" } in
    let msg = List.Assoc.find kwargs ~equal:String.equal "msg" |> Option.value_map ~default:"" ~f:(fun e -> match e with Yexpr_string (Ycs_string s) -> s | _ -> "") in
    Some (Ys_var (Yvar_option { cvar = n; msg; value }))
  | "add_exe", name :: rest ->
    Some (Ys_target (Ytgt_add_executable { name; exclude_from_all = false; sources = rest @ record_args }))
  | "add_lib", name :: rest ->
    Some (Ys_target (Ytgt_add_library { name; type_ = None; exclude_from_all = false; sources = rest @ record_args }))
  | "link_lib", [target] ->
    Some (Ys_target (Ytgt_link_libraries { targets = [target]; items = [] }))
  | "link_lib", target :: _ ->
    Some (Ys_target (Ytgt_link_libraries { targets = [target]; items = [] }))
  | "include_dirs", [target] ->
    Some (Ys_target (Ytgt_include_directories { target; before = false; system = false; items = [] }))
  | "compile_defs", [target] ->
    Some (Ys_target (Ytgt_compile_definitions { target; items = [] }))
  | "compile_opts", [target] ->
    Some (Ys_target (Ytgt_compile_options { target; before = false; items = [] }))
  | "target_sources", [target] ->
    Some (Ys_target (Ytgt_sources { target; items = [] }))
  | "add_lib_imported", [name] ->
    let lib_type = List.Assoc.find kwargs ~equal:String.equal "type"
      |> Option.value_map ~default:None ~f:(fun e -> match e with Yexpr_string (Ycs_keyword s) -> Some s | _ -> None) in
    let global = List.Assoc.find kwargs ~equal:String.equal "global"
      |> Option.value_map ~default:false ~f:(fun _ -> true) in
    Some (Ys_target (Ytgt_add_library_imported { name; lib_type; global }))
  | "configure_file", [input; output] ->
    Some (Ys_file (Yfile_configure { input; output }))
  | "add_subdirectory", [dir] ->
    Some (Ys_dir (Ydir_add_subdirectory { source_dir = dir }))
  | "link_libraries", _ -> Some (Ys_dir (Ydir_link_libraries { items = args }))
  | "add_compile_definitions", _ -> Some (Ys_dir (Ydir_add_compile_definitions { defs = args }))
  | "enable_testing", [] -> Some (Ys_test Ytest_enable_testing)
  | "add_test", name :: command :: rest' -> Some (Ys_test (Ytest_add_test { name; command; args = rest' }))
  | "find_package", [name] ->
    let s = match name with Yexpr_string (Ycs_path s') | Yexpr_string (Ycs_string s') -> s' | _ -> "" in
    Some (Ys_find (Yfind_package { name = s; version = None; exact = false; quiet = false; config_mode = false; required = false; components = []; optional_components = [] }))
  (* Tier 1: remaining target commands *)
  | "compile_feats", [target] ->
    Some (Ys_target (Ytgt_compile_features { target; features = [] }))
  | "link_opts", [target] ->
    Some (Ys_target (Ytgt_link_options { target; before = false; items = [] }))
  | "link_dirs", [target] ->
    Some (Ys_target (Ytgt_link_directories { target; before = false; items = [] }))
  | "precompile_headers", [target] ->
    Some (Ys_target (Ytgt_precompile_headers { target; items = [] }))
  | "add_lib_alias", [name; target] ->
    Some (Ys_target (Ytgt_add_library_alias { name = (match name with Yexpr_string (Ycs_string s) -> s | _ -> "?"); target = (match target with Yexpr_string (Ycs_string s) -> s | _ -> "?") }))
  | "add_exe_alias", [name; target] ->
    Some (Ys_target (Ytgt_add_executable_alias { name = (match name with Yexpr_string (Ycs_string s) -> s | _ -> "?"); target = (match target with Yexpr_string (Ycs_string s) -> s | _ -> "?") }))
  | "add_custom_target", [name] ->
    Some (Ys_target (Ytgt_add_custom_target { name = (match name with Yexpr_string (Ycs_string s) -> s | _ -> "?"); all = false; commands = []; depends = []; comment = None }))
  | "add_dependencies", [target; dep] ->
    Some (Ys_target (Ytgt_add_dependencies { target = (match target with Yexpr_string (Ycs_string s) -> s | _ -> "?"); dep = (match dep with Yexpr_string (Ycs_string s) -> s | _ -> "?") }))
  | "string_toupper", [s] -> Some (Ys_string (Ystr_toupper { string = s; out = out_var kwargs }))
  | "string_tolower", [s] -> Some (Ys_string (Ystr_tolower { string = s; out = out_var kwargs }))
  | "string_length", [s] -> Some (Ys_string (Ystr_length { string = s; out = out_var kwargs }))
  | "string_strip", [s] -> Some (Ys_string (Ystr_strip { string = s; out = out_var kwargs }))
  | "string_concat", inputs -> Some (Ys_string (Ystr_concat { out = out_var kwargs; inputs }))
  | "string_replace", [match_s; repl_s; input] ->
    Some (Ys_string (Ystr_replace { match_string = match_s; replace_string = repl_s; out = out_var kwargs; inputs = [input] }))
  | "string_regex_match", [regex; input] ->
    let re_s = match regex with Yexpr_string (Ycs_string s) | Yexpr_string (Ycs_path s) -> s | _ -> "" in
    Some (Ys_string (Ystr_regex_match { regex = re_s; out = out_var kwargs; inputs = [input] }))
  | "string_join", glue :: inputs ->
    Some (Ys_string (Ystr_join { glue; out = out_var kwargs; inputs }))
  | "string_find", [sub; s] ->
    Some (Ys_string (Ystr_find { string = s; substring = sub; out = out_var kwargs; reverse = false }))
  | "string_timestamp", [] ->
    let utc = List.Assoc.find kwargs ~equal:String.equal "utc" |> Option.is_some in
    Some (Ys_string (Ystr_timestamp { out = out_var kwargs; format = None; utc }))
  | "string_hex", [s] -> Some (Ys_string (Ystr_hex { string = s; out = out_var kwargs }))
  | "string_make_c_identifier", [s] -> Some (Ys_string (Ystr_make_c_identifier { string = s; out = out_var kwargs }))
  (* Tier 3: list operations *)
  | "list_append", cvar :: values ->
    let n = cvar_of_expr cvar in
    Some (Ys_list (Ylist_append { cvar = n; values }))
  | "list_length", [cvar] ->
    Some (Ys_list (Ylist_length { cvar = cvar_of_expr cvar; out = out_var kwargs }))
  | "list_get", [cvar] ->
    Some (Ys_list (Ylist_get { cvar = cvar_of_expr cvar; indices = []; out = out_var kwargs }))
  | "list_remove_item", cvar :: values ->
    Some (Ys_list (Ylist_remove_item { cvar = cvar_of_expr cvar; values }))
  | "list_remove_duplicates", [cvar] ->
    Some (Ys_list (Ylist_remove_duplicates { cvar = cvar_of_expr cvar }))
  | "list_reverse", [cvar] ->
    Some (Ys_list (Ylist_reverse { cvar = cvar_of_expr cvar }))
  | "list_sort", [cvar] ->
    Some (Ys_list (Ylist_sort { cvar = cvar_of_expr cvar; order = None; compare = None; case = None }))
  | "list_join", [cvar; glue] ->
    Some (Ys_list (Ylist_join { cvar = cvar_of_expr cvar; glue; out = out_var kwargs }))
  | "list_find", [cvar; value] ->
    Some (Ys_list (Ylist_find { cvar = cvar_of_expr cvar; value; out = out_var kwargs }))
  | "list_prepend", cvar :: values ->
    Some (Ys_list (Ylist_prepend { cvar = cvar_of_expr cvar; values }))
  | "list_insert", [cvar] ->
    Some (Ys_list (Ylist_insert { cvar = cvar_of_expr cvar; index = 0; values = [] }))
  | "list_remove_at", cvar :: _ ->
    Some (Ys_list (Ylist_remove_at { cvar = cvar_of_expr cvar; indices = [] }))
  | "list_pop_back", [cvar] ->
    Some (Ys_list (Ylist_pop_back { cvar = cvar_of_expr cvar; out_vars = [] }))
  | "list_pop_front", [cvar] ->
    Some (Ys_list (Ylist_pop_front { cvar = cvar_of_expr cvar; out_vars = [] }))
  (* Tier 4: file operations *)
  | "file_read", [file] ->
    Some (Ys_file (Yfile_read { out = out_var kwargs; file; offset = None; limit = None; hex = false }))
  | "file_write", file :: content ->
    Some (Ys_file (Yfile_write { file; append = false; content }))
  | "file_glob", patterns ->
    Some (Ys_file (Yfile_glob { out = out_var kwargs; recurse = false; relative = None; configure_depends = false; patterns }))
  | "file_copy", [input; output] ->
    Some (Ys_file (Yfile_copy { input; output; result = None; only_if_different = false }))
  | "file_rename", [old_; new_] ->
    Some (Ys_file (Yfile_rename { old_; new_; result = None; no_replace = false }))
  | "file_remove", files ->
    Some (Ys_file (Yfile_remove { files; recurse = false }))
  | "file_real_path", [path] ->
    Some (Ys_file (Yfile_real_path { out = out_var kwargs; path; base_dir = None; expand_tilde = false }))
  | "file_size", [file] ->
    Some (Ys_file (Yfile_size { out = out_var kwargs; file }))
  | "file_timestamp", [file] ->
    Some (Ys_file (Yfile_timestamp { out = out_var kwargs; file; format = None; utc = false }))
  | "file_make_directory", [dir] ->
    Some (Ys_file (Yfile_make_directory { dirs = [dir] }))
  | "file_touch", files ->
    Some (Ys_file (Yfile_touch { files; nocreate = false }))
  (* Tier 5: path operations *)
  | "path_get", [path_var] ->
    Some (Ys_path (Ypath_get { path_var = cvar_of_expr path_var; field = Lang_cmake.Cpf_filename; out = out_var kwargs }))
  | "path_has", [path_var] ->
    Some (Ys_path (Ypath_has { path_var = cvar_of_expr path_var; field = Lang_cmake.Cph_filename; out = out_var kwargs }))
  | "path_is_absolute", [path_var] ->
    Some (Ys_path (Ypath_is_absolute { path_var = cvar_of_expr path_var; out = out_var kwargs }))
  | "path_is_relative", [path_var] ->
    Some (Ys_path (Ypath_is_relative { path_var = cvar_of_expr path_var; out = out_var kwargs }))
  | "path_set", [path_var; input] ->
    Some (Ys_path (Ypath_set { path_var = cvar_of_expr path_var; input; normalize = false }))
  | "path_append", [path_var; input] ->
    Some (Ys_path (Ypath_append { path_var = cvar_of_expr path_var; inputs = [input]; out = None }))
  | "path_compare", [input1; input2] ->
    Some (Ys_path (Ypath_compare { input1; op = Lang_cmake.Cpco_equal; input2; out = out_var kwargs }))
  | "path_hash", [path_var] ->
    Some (Ys_path (Ypath_hash { path_var = cvar_of_expr path_var; out = out_var kwargs }))
  | "get_filename_component", [filename] ->
    Some (Ys_path (Ypath_get_filename_component { var = out_var kwargs; filename; mode = "PATH" }))
  (* Tier 6: find & install *)
  | "find_library", [cvar] ->
    Some (Ys_find (Yfind_library { cvar = cvar_of_expr cvar; names = []; paths = []; hints = [];
      no_default_path = false; no_cmake_environment_path = false;
      no_system_environment_path = false; required = false }))
  | "find_path", [cvar] ->
    Some (Ys_find (Yfind_path { cvar = cvar_of_expr cvar; names = []; paths = []; hints = [];
      no_default_path = false; no_cmake_environment_path = false;
      no_system_environment_path = false; required = false }))
  | "find_program", [cvar] ->
    Some (Ys_find (Yfind_program { cvar = cvar_of_expr cvar; names = []; paths = []; hints = [];
      no_default_path = false; no_cmake_environment_path = false;
      no_system_environment_path = false; required = false }))
  | "find_file", [cvar] ->
    Some (Ys_find (Yfind_file { cvar = cvar_of_expr cvar; names = []; paths = []; hints = [];
      no_default_path = false; no_cmake_environment_path = false;
      no_system_environment_path = false; required = false }))
  | "install_targets", [destination] ->
    Some (Ys_install (Yinstall_targets { targets = record_args; destination; export = None }))
  | "install_files", [destination] ->
    Some (Ys_install (Yinstall_files { files = record_args; destination }))
  | "install_export", [export; destination] ->
    Some (Ys_install (Yinstall_export { file = None; export; destination; namespace = None }))
  (* Tier 7: scripting & control flow *)
  | "include", [file] ->
    let optional = List.Assoc.find kwargs ~equal:String.equal "optional" |> Option.is_some in
    Some (Yc_include { file; optional })
  | "macro", _ ->
    (* macro is handled by p_macro in p_stmt, not via build_stmt *)
    None
  | "separate_arguments", [cvar] ->
    Some (Yc_separate_arguments { cvar = cvar_of_expr cvar; mode = Lang_cmake.Sa_plain; input = None })
  (* Tier 8: dir, property, cmake_op, try *)
  | "include_directories", dirs ->
    Some (Ys_dir (Ydir_include_directories { dirs; before = false; system = false }))
  | "add_compile_options", opts ->
    Some (Ys_dir (Ydir_add_compile_options { options = opts }))
  | "add_link_options", opts ->
    Some (Ys_dir (Ydir_add_link_options { options = opts }))
  | "add_definitions", defs ->
    Some (Ys_dir (Ydir_add_definitions { defs }))
  | "link_directories", dirs ->
    Some (Ys_dir (Ydir_link_directories { before = false; dirs }))
  | "get_target_property", [tgt] ->
    Some (Ys_property (Yprop_get { var = out_var kwargs; target = tgt; property = "PROP"; set = false }))
  | "set_target_properties", [tgt] ->
    Some (Ys_property (Yprop_set_target { target = tgt; properties = [] }))
  | "set_property", targets ->
    Some (Ys_property (Yprop_set { targets; append = false; properties = [] }))
  | "math", [exp] ->
    Some (Ys_cmake (Ycmake_math { exp = (match exp with Yexpr_string (Ycs_string s) -> s | _ -> ""); out = out_var kwargs; output_format = Lang_cmake.Decical }))
  | "execute_process", _ ->
    Some (Ys_cmake (Ycmake_execute_process { commands = []; working_directory = None; timeout = None;
      result_variable = None; output_variable = None; error_variable = None;
      input_file = None; output_file = None; error_file = None;
      output_quiet = false; error_quiet = false; output_strip_trailing_whitespace = false;
      error_strip_trailing_whitespace = false; command_error_is_fatal = None }))
  | "include_guard", [] ->
    Some (Ys_cmake (Ycmake_include_guard { scope = Lang_cmake.Ig_global }))
  | "policy_set", [id] ->
    Some (Ys_cmake (Ycmake_policy_set { id = (match id with Yexpr_string (Ycs_string s) -> s | _ -> ""); new_ = true }))
  | "try_compile", [result] ->
    Some (Ys_try (Ytry_compile { result_var = cvar_of_expr result; sources = []; compile_definitions = [];
      link_libraries = []; link_options = []; output_variable = None;
      no_cache = false; c_standard = None; cxx_standard = None }))
  | "try_run", [run_result; compile_result] ->
    Some (Ys_try (Ytry_run { run_result_var = cvar_of_expr run_result;
      compile_result_var = cvar_of_expr compile_result; sources = [];
      compile_definitions = []; link_libraries = [];
      compile_output_variable = None; run_output_variable = None; args = [] }))
  | "enable_language", _ ->
    Some (Ys_cmake (Ycmake_enable_language { langs = []; optional = false }))
  | _ -> None

(* ============================================================
   Command parser (standalone, no recursion)
   ============================================================ *)

let p_command toks =
  match p_ident toks with
  | None -> None
  | Some (name, toks) ->
    let rec collect args kwargs toks =
      match toks with
      (* ~public:[items], ~private:[items], ~interface:[items] — kind-scoped lists *)
      | TILDE :: IDENT kw :: COLON :: LBRACK :: rest
        when String.equal kw "public" || String.equal kw "private" || String.equal kw "interface" ->
        let rec items_loop acc = function
          | RBRACK :: r -> (List.rev acc, r)
          | COMMA :: r -> items_loop acc r
          | toks' -> match p_expr toks' with Some (e, r) -> items_loop (e :: acc) r | None -> (List.rev acc, toks') in
        let _, rest = items_loop [] rest in
        collect args ((kw, Yexpr_bool true) :: kwargs) rest
      (* ~label:value — colon separated *)
      | TILDE :: IDENT kw :: COLON :: rest ->
        (match p_expr rest with Some (v, r) -> collect args ((kw, v) :: kwargs) r | None -> (List.rev args, List.rev kwargs, toks))
      (* ~label:value — lexer combined :val into KEYWORD token *)
      | TILDE :: IDENT kw :: KEYWORD v :: rest ->
        collect args ((kw, Yexpr_var (Yvar v)) :: kwargs) rest
      (* ~flag *)
      | TILDE :: IDENT kw :: rest ->
        collect args ((kw, Yexpr_bool true) :: kwargs) rest
      (* legacy :keyword value *)
      | COLON :: IDENT kw :: rest
      | KEYWORD kw :: rest ->
        (match p_expr rest with Some (v, r) -> collect args ((kw, v) :: kwargs) r | None -> (List.rev args, List.rev kwargs, toks))
      | LBRACE :: _ | RBRACE :: _ | SEMI :: _ | EOF :: _ | [] -> (List.rev args, List.rev kwargs, toks)
      | _ ->
        (match p_expr toks with Some (e, r) -> collect (e :: args) kwargs r | None -> (List.rev args, List.rev kwargs, toks)) in
    let args, kwargs, rest = collect [] [] toks in
    let record_args, rest =
      match rest with
      | LBRACE :: r ->
        let rec coll_rec acc = function
          | RBRACE :: r' -> (List.rev acc, r')
          | SEMI :: r' -> coll_rec acc r'
          | toks' -> match p_expr toks' with Some (e, r') -> coll_rec (e :: acc) r' | None -> (List.rev acc, toks') in
        coll_rec [] r
      | _ -> ([], rest) in
    match build_stmt name args kwargs record_args with
    | Some stmt -> Some (stmt, rest)
    | None -> None

(* ============================================================
   Statement parsers — plain match style
   ============================================================ *)

let rec p_stmt toks =
  match p_let toks with Some r -> Some r | None ->
  match p_if toks with Some r -> Some r | None ->
  match p_foreach toks with Some r -> Some r | None ->
  match p_function toks with Some r -> Some r | None ->
  match p_macro toks with Some r -> Some r | None ->
  match p_while toks with Some r -> Some r | None ->
  match p_flow toks with Some r -> Some r | None ->
  match p_command toks with Some r -> Some r | None ->
  match p_assign toks with Some r -> Some r | None ->
  p_block toks

and p_block toks =
  match lparen toks with
  | None -> None
  | Some ((), toks) ->
    let rec collect toks =
      match p_stmt toks with
      | None -> Some ([], toks)
      | Some (s, rest) ->
        let rest = match rest with SEMI :: r -> r | _ -> rest in
        (match collect rest with
         | Some (ss, r) -> Some (s :: ss, r)
         | None -> None) in
    (match collect toks with
     | Some (stmts, (RPAREN :: rest)) ->
       Some ((match stmts with [s] -> s | _ -> Ystmt_list stmts), rest)
     | _ -> None)

and p_let toks =
  match kw "let" toks with
  | None -> None
  | Some ((), toks) ->
    match p_ident toks with
    | None -> None
    | Some (name, toks) ->
      (* skip optional :type *)
      (* skip optional :type — accept IDENT or keyword token (lexer maps "target"→TARGET) *)
      let toks = match toks with
        | COLON :: rest ->
          (match rest with
           | IDENT _ :: r -> Some r
           | TARGET :: r -> Some r
           | CVAR :: r -> Some r
           | _ -> None)
          |> Option.value ~default:toks
        | _ -> toks in
      match eq_tok toks with
      | None -> None
      | Some ((), toks) ->
        match p_expr toks with
        | None -> None
        | Some (value, toks) ->
          match kw "in" toks with
          | None -> None
          | Some ((), toks) ->
            match p_stmt toks with
            | Some (body, rest) -> Some (Ystmt_list [Ylet { var = Yvar name; value }; body], rest)
            | None -> None

and p_if toks =
  match kw "if" toks with
  | None -> None
  | Some ((), toks) ->
    match p_cond toks with
    | None -> None
    | Some (cond, toks) ->
      match kw "then" toks with
      | None -> None
      | Some ((), toks) ->
        match p_block toks with
        | None -> None
        | Some (then_, toks) ->
          let else_opt =
            match kw "else" toks with
            | Some ((), r) ->
              (match p_block r with Some (e, r') -> Some (Some e, r') | None ->
               match p_if r with Some (e, r') -> Some (Some e, r') | None -> None)
            | None -> None in
          (match else_opt with
           | Some (else_, rest) -> Some (Yif { cond; then_; else_ }, rest)
           | None -> Some (Yif { cond; then_; else_ = None }, toks))

and p_foreach toks =
  match kw "foreach" toks with
  | None -> None
  | Some ((), toks) ->
    match p_ident toks with
    | None -> None
    | Some (lv, toks) ->
      match kw "in" toks with
      | None -> None
      | Some ((), toks) ->
        (* Try RANGE *)
        match kw "RANGE" toks with
        | Some ((), r) ->
          (match p_int_v r with None -> None | Some (start, r) ->
           match dotdot r with None -> None | Some ((), r) ->
           match p_int_v r with None -> None | Some (stop, r) ->
           match p_block r with
           | Some (body, r') -> Some (Yc_foreach_range { loop_var = { ns = Ns_var; name = lv }; start = Some start; stop; step = None; commands = body }, r')
           | None -> None)
        | None ->
          (* Try [items] *)
          match toks with
          | LBRACK :: r ->
            let rec items_loop acc = function
              | RBRACK :: r' -> (List.rev acc, r')
              | toks' -> match p_expr toks' with Some (e, r') -> items_loop (e :: acc) r' | None -> (List.rev acc, toks') in
            let items, r = items_loop [] r in
            (match p_block r with
             | Some (body, r') -> Some (Yc_foreach { loop_var = { ns = Ns_var; name = lv }; items; commands = body }, r')
             | None -> None)
          | _ -> None

and p_function toks =
  match kw "function" toks with
  | None -> None
  | Some ((), toks) ->
    match p_ident toks with
    | None -> None
    | Some (name, toks) ->
      let args, toks =
        match toks with
        | LPAREN :: r ->
          let rec loop acc = function
            | RPAREN :: r' -> (List.rev acc, r')
            | COMMA :: r' -> loop acc r'
            | toks' -> match p_ident toks' with Some (a, r') -> loop (a :: acc) r' | None -> (List.rev acc, toks') in
          loop [] r
        | _ -> ([], toks) in
      match p_block toks with
      | Some (body, rest) ->
        let stmts = match body with Ystmt_list ss -> ss | s -> [s] in
        Some (Yc_function { name = Yexpr_string (Ycs_string name); args; body = stmts }, rest)
      | None -> None

and p_macro toks =
  match kw "macro" toks with
  | None -> None
  | Some ((), toks) ->
    match p_ident toks with
    | None -> None
    | Some (name, toks) ->
      let args, toks =
        match toks with
        | LPAREN :: r ->
          let rec loop acc = function
            | RPAREN :: r' -> (List.rev acc, r')
            | COMMA :: r' -> loop acc r'
            | toks' -> match p_ident toks' with Some (a, r') -> loop (a :: acc) r' | None -> (List.rev acc, toks') in
          loop [] r
        | _ -> ([], toks) in
      match p_block toks with
      | Some (body, rest) ->
        let stmts = match body with Ystmt_list ss -> ss | s -> [s] in
        Some (Yc_macro { name = Yexpr_string (Ycs_string name); args; body = stmts }, rest)
      | None -> None

and p_while toks =
  match kw "while" toks with
  | None -> None
  | Some ((), toks) ->
    match p_cond toks with
    | None -> None
    | Some (cond, toks) ->
      match p_block toks with
      | Some (body, rest) -> Some (Yc_while { cond; commands = body }, rest)
      | None -> None

and p_flow toks =
  match toks with
  | BREAK :: rest -> Some (Yc_break, rest)
  | CONTINUE :: rest -> Some (Yc_continue, rest)
  | RETURN :: rest -> Some (Yc_return { propogate_vars = [] }, rest)
  | _ -> None

(* VAR := v1, v2, v3             — variable set
   cache VAR := v1, v2, v3; 'msg' — cache set with docstring *)
and p_assign toks =
  let is_cache, toks =
    match toks with
    | CACHE :: rest -> (true, rest)
    | IDENT _ :: WALRUS :: _ -> (false, toks)
    | _ -> (false, toks) in
  match toks with
  | IDENT name :: WALRUS :: rest ->
    (* Collect comma-separated values *)
    let rec collect_vals acc toks =
      match p_expr toks with
      | Some (v, COMMA :: rest) -> collect_vals (v :: acc) rest
      | Some (v, rest) -> Some (List.rev (v :: acc), rest)
      | None -> if List.is_empty acc then None else Some (List.rev acc, toks) in
    (match collect_vals [] rest with
     | None -> None
     | Some (values, rest) ->
       if is_cache then
         let msg, rest =
           match rest with
           | SEMI :: STRING s :: rest' -> (s, rest')
           | SEMI :: PATH s :: rest' -> (s, rest')
           | STRING s :: SEMI :: rest' -> (s, rest')
           | _ -> ("", rest) in
         Some (Ys_var (Yvar_set_cache {
           cvar = { ns = Ns_var; name };
           values; cache_type = Lang_cmake.Ct_string; docstring = msg; force = false }), rest)
       else
         Some (Ys_var (Yvar_set {
           cvar = { ns = Ns_var; name }; values; parent_scope = false }), rest))
  | _ -> None

(* ============================================================
   Entry points
   ============================================================ *)

let parse_tokens toks =
  match p_stmt toks with
  | Some (stmt, []) -> Ok stmt
  | Some (_, rest) ->
    (* Reject trailing tokens — malformed input *)
    let ctx = match rest with
      | [] -> ""
      | t :: _ -> " at " ^ Sexp.to_string ([%sexp_of: token] t) in
    Error ("unexpected trailing tokens" ^ ctx)
  | None ->
    let ctx = match toks with
      | [] -> "at end of input"
      | t :: _ -> "at " ^ Sexp.to_string ([%sexp_of: token] t) in
    Error ("parse error " ^ ctx)

let parse_string input =
  match Angstrom.parse_string ~consume:All token_list input with
  | Ok toks -> parse_tokens toks
  | Error e -> Error ("lex error: " ^ e)

let parse_program = parse_string
