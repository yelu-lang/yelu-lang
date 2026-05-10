open Base
open Yelu_tiny
open Yelu_surface_cmake_store
open Yelu_theory_bool
open Yelu_theory_int
open Yelu_theory_list
open Yelu_surface_cmake_list
open Yelu_surface_cmake_path
open Yelu_surface_cmake_file
open Yelu_theory_target
open Yelu_surface_cmake_target
open Yelu_surface_cmake_install
open Yelu_surface_cmake_string
open Yelu_surface_cmake_if
open Yelu_surface_cmake_cmake_op
open Yelu_surface_cmake_dir
open Yelu_surface_cmake_test
open Yelu_surface_cmake_property
open Yelu_surface_cmake_find
open Yelu_surface_cmake_try

let escape_quoted s =
  s
  |> String.substr_replace_all ~pattern:"\\" ~with_:"\\\\"
  |> String.substr_replace_all ~pattern:"\"" ~with_:"\\\""

let quoted s = "\"" ^ escape_quoted s ^ "\""

(* Substitution env carried through emit so that ELet bindings can be
   resolved as a side effect of textual rendering. The architecture is the
   "fold into emit" choice (option #1 in PLAN): no separate resolve module,
   ELet stays first-class in the IR, emit_script applies the binding map
   inline. EVar references inside an ELet body get the bound value
   substituted; ELet header itself is dropped from the output. *)
type subst = expr Map.M(String).t

let empty_subst : subst = Map.empty (module String)

let rec arg ?(env = empty_subst) = function
  | EVar name ->
    (match Map.find env name with
     | Some replacement -> arg ~env replacement
     | None -> quoted ("${" ^ name ^ "}"))
  | EString s -> quoted s
  | EInt n -> Int.to_string n
  | EBool true -> "ON"
  | EBool false -> "OFF"
  | ETarget name -> quoted name
  | _ -> fail "cannot emit expression as CMake argument"

(* Target-name position: cmake conventionally accepts an unquoted identifier
   for target/file names. After resolving via the substitution env, render
   bare strings as bare tokens (no quoting), and unresolved EVar as the
   cmake runtime deref form `${name}`. *)
let rec target_arg ?(env = empty_subst) = function
  | EVar name ->
    (match Map.find env name with
     | Some replacement -> target_arg ~env replacement
     | None -> "${" ^ name ^ "}")
  | EString s -> s
  | ETarget name -> name
  | _ -> fail "cannot emit expression as cmake target name"

let build_command_arg arg = quoted arg

let build_command (cmd : build_command) =
  String.concat ~sep:" " (List.map (cmd.command :: cmd.args) ~f:build_command_arg)

let rec cond ?(env = empty_subst) = function
  | EBool true -> "TRUE"
  | EBool false -> "FALSE"
  | ENot expr -> "NOT " ^ cond_atom ~env expr
  | EAnd (left, right) -> cond_atom ~env left ^ " AND " ^ cond_atom ~env right
  | EOr (left, right) -> cond_atom ~env left ^ " OR " ^ cond_atom ~env right
  | EIntLess (left, right) -> arg ~env left ^ " LESS " ^ arg ~env right
  | EIntEqual (left, right) -> arg ~env left ^ " EQUAL " ^ arg ~env right
  | ECmakeStringEqual (left, right) ->
    arg ~env left ^ " STREQUAL " ^ arg ~env right
  | ECmakeVarDefined name -> "DEFINED " ^ name
  | ECmakeTargetExists target -> "TARGET " ^ target_arg ~env target
  | ECmakeFileExists path -> "EXISTS " ^ arg ~env path
  | expr -> arg ~env expr

and cond_atom ?(env = empty_subst) expr =
  match expr with
  | EBool _ | ENot _ | ECmakeStringEqual _ | ECmakeVarDefined _
  | ECmakeTargetExists _ | ECmakeFileExists _ | EIntLess _ | EIntEqual _
  | EVar _ | EString _ -> cond ~env expr
  | EAnd _ | EOr _ -> "(" ^ cond ~env expr ^ ")"
  | _ -> cond ~env expr

(* Emit walks the IR producing cmake lines. ELet extends the substitution
   env, drops the header. EVar and arg/cond consult the env via lexical
   rebinding at the top of [emit_expr_impl] so all match arms below see the
   env-aware versions without changing their bodies. ELet recurses through
   [emit_expr_impl] directly so it can pass a different env. *)
let rec emit_expr_impl ~env e =
  let arg = arg ~env in
  let cond = cond ~env in
  let target_arg = target_arg ~env in
  let emit_expr = emit_expr_impl ~env in
  match e with
  | EUnit -> []
  | ESeq exprs -> List.concat_map exprs ~f:emit_expr
  | ELet { var; value; body } ->
    (* Bind var -> value (the [value] expression is stored as-is; transitive
       resolution happens lazily on lookup via [arg] / EVar substitution).
       The let header itself is not emitted. *)
    let env = Map.set env ~key:var ~data:value in
    emit_expr_impl ~env body
  | EVar name when Map.mem env name ->
    (* Resolved EVar in a top-level (statement) position emits as a message
       on the substituted value, not as the original ${name}. *)
    emit_expr (Map.find_exn env name)
  | ESetVar (name, EList exprs) ->
    [ Fmt.str "set(%s %s)" name (String.concat ~sep:" " (List.map exprs ~f:arg)) ]
  | ESetVar (name, expr) -> [ Fmt.str "set(%s %s)" name (arg expr) ]
  | ECmakeUnsetVar name -> [ Fmt.str "unset(%s)" name ]
  | ECmakeOption { name; message; value } ->
    [ Fmt.str "option(%s %s %s)" name (quoted message) (arg value) ]
  | ETarget _ -> []
  | EVar name -> [ Fmt.str "message(\"RESULT=${%s}\")" name ]
  | EString s -> [ Fmt.str "message(\"RESULT=%s\")" (escape_quoted s) ]
  | EInt n -> [ Fmt.str "message(\"RESULT=%d\")" n ]
  | EBool b -> [ Fmt.str "message(\"RESULT=%s\")" (if b then "ON" else "OFF") ]
  | ECmakeStringConcat { inputs; out } ->
    [ Fmt.str "string(CONCAT %s %s)" out (String.concat ~sep:" " (List.map inputs ~f:arg)) ]
  | ECmakeStringToupper { input; out } ->
    [ Fmt.str "string(TOUPPER %s %s)" (arg input) out ]
  | ECmakeStringReplace { match_; replace; input; out } ->
    [ Fmt.str "string(REPLACE %s %s %s %s)" (arg match_) (arg replace) out (arg input) ]
  | ECmakeStringLength { input; out } ->
    [ Fmt.str "string(LENGTH %s %s)" (arg input) out ]
  | ECmakeListAppend { list; items } ->
    [ Fmt.str "list(APPEND %s %s)" list (String.concat ~sep:" " (List.map items ~f:arg)) ]
  | ECmakeListGet { list; index; out } ->
    [ Fmt.str "list(GET %s %s %s)" list (arg index) out ]
  | ECmakeListLength { list; out } ->
    [ Fmt.str "list(LENGTH %s %s)" list out ]
  | ECmakeListJoin { list; glue; out } ->
    [ Fmt.str "list(JOIN %s %s %s)" list (arg glue) out ]
  | ECmakePathSet { path; input; normalize } ->
    [ Fmt.str "cmake_path(SET %s%s %s)" path (if normalize then " NORMALIZE" else "") (arg input) ]
  | ECmakePathGetFilename { path; out } ->
    [ Fmt.str "cmake_path(GET %s FILENAME %s)" path out ]
  | ECmakePathNormalPath { path; out } ->
    [ Fmt.str "cmake_path(NORMAL_PATH %s%s)"
        path
        (Option.value_map out ~default:"" ~f:(fun out -> " OUTPUT_VARIABLE " ^ out))
    ]
  | ECmakeFileWrite { path; content } ->
    [ Fmt.str "file(WRITE %s %s)"
        (arg path)
        (String.concat ~sep:" " (List.map content ~f:arg))
    ]
  | ECmakeFileRead { path; out } ->
    [ Fmt.str "file(READ %s %s)" (arg path) out ]
  | ECmakeConfigureFile { input; output } ->
    [ Fmt.str "configure_file(%s %s)" (arg input) (arg output) ]
  | ECmakeAddExecutable { name; sources } ->
    [ Fmt.str "add_executable(%s %s)" (target_arg name) (String.concat ~sep:" " (List.map sources ~f:arg)) ]
  | ECmakeAddLibrary { name; type_; sources } ->
    let args =
      Option.to_list type_ @ List.map sources ~f:arg
      |> String.concat ~sep:" "
    in
    [ Fmt.str "add_library(%s %s)"
        (target_arg name)
        args
    ]
  | ECmakeTargetSources { target; visibility; sources } ->
    [ Fmt.str "target_sources(%s %s %s)" (target_arg target) visibility (String.concat ~sep:" " (List.map sources ~f:arg)) ]
  | ECmakeTargetLinkLibraries { target; visibility; items } ->
    [ Fmt.str "target_link_libraries(%s %s %s)" (target_arg target) visibility (String.concat ~sep:" " (List.map items ~f:arg)) ]
  | ECmakeTargetIncludeDirectories { target; visibility; dirs } ->
    [ Fmt.str "target_include_directories(%s %s %s)" (target_arg target) visibility (String.concat ~sep:" " (List.map dirs ~f:arg)) ]
  | ECmakeTargetCompileDefinitions { target; visibility; definitions } ->
    [ Fmt.str "target_compile_definitions(%s %s %s)" (target_arg target) visibility (String.concat ~sep:" " (List.map definitions ~f:arg)) ]
  | ECmakeTargetCompileOptions { target; visibility; options_ } ->
    [ Fmt.str "target_compile_options(%s %s %s)" (target_arg target) visibility (String.concat ~sep:" " (List.map options_ ~f:arg)) ]
  | ECmakeTargetCompileFeatures { target; visibility; features } ->
    [ Fmt.str "target_compile_features(%s %s %s)" (target_arg target) visibility (String.concat ~sep:" " (List.map features ~f:target_arg)) ]
  | ECmakeTargetLinkOptions { target; visibility; options_ } ->
    [ Fmt.str "target_link_options(%s %s %s)" (target_arg target) visibility (String.concat ~sep:" " (List.map options_ ~f:arg)) ]
  | ECmakeTargetLinkDirectories { target; visibility; dirs } ->
    [ Fmt.str "target_link_directories(%s %s %s)" (target_arg target) visibility (String.concat ~sep:" " (List.map dirs ~f:arg)) ]
  | ECmakeAddCustomTarget { name; all; commands; depends; comment } ->
    let all = if all then " ALL" else "" in
    let command_lines =
      List.map commands ~f:(fun command ->
        Fmt.str "  COMMAND %s" (build_command command))
    in
    let depends =
      match depends with
      | [] -> []
      | depends ->
        [ Fmt.str "  DEPENDS %s" (String.concat ~sep:" " (List.map depends ~f:arg)) ]
    in
    let comment =
      match comment with
      | None -> []
      | Some comment -> [ Fmt.str "  COMMENT %s" (quoted comment) ]
    in
    [ Fmt.str "add_custom_target(%s%s" (target_arg name) all ]
    @ command_lines
    @ depends
    @ comment
    @ [ "  VERBATIM"; ")" ]
  | ECmakeAddCustomCommand { outputs; commands; depends; comment; verbatim } ->
    let outputs_line =
      Fmt.str "  OUTPUT %s" (String.concat ~sep:" " (List.map outputs ~f:arg))
    in
    let command_lines =
      List.map commands ~f:(fun command ->
        Fmt.str "  COMMAND %s" (build_command command))
    in
    let depends_lines =
      match depends with
      | [] -> []
      | depends ->
        [ Fmt.str "  DEPENDS %s" (String.concat ~sep:" " (List.map depends ~f:arg)) ]
    in
    let comment_lines =
      match comment with
      | None -> []
      | Some comment -> [ Fmt.str "  COMMENT %s" (quoted comment) ]
    in
    let verbatim_lines = if verbatim then [ "  VERBATIM" ] else [] in
    [ "add_custom_command(" ]
    @ [ outputs_line ]
    @ command_lines
    @ depends_lines
    @ comment_lines
    @ verbatim_lines
    @ [ ")" ]
  | ECmakeInstallTargets { targets; destination; export } ->
    let export =
      Option.value_map export ~default:"" ~f:(fun export ->
        " EXPORT " ^ arg export)
    in
    [ Fmt.str "install(TARGETS %s%s DESTINATION %s)"
        (String.concat ~sep:" " (List.map targets ~f:target_arg))
        export
        (arg destination)
    ]
  | ECmakeInstallFiles { files; destination } ->
    [ Fmt.str "install(FILES %s DESTINATION %s)"
        (String.concat ~sep:" " (List.map files ~f:arg))
        (arg destination)
    ]
  | ECmakeIfStmt { cond = c; then_; else_ } ->
    let then_lines = emit_expr then_ in
    let else_lines = Option.value_map else_ ~default:[] ~f:emit_expr in
    [ "if(" ^ cond c ^ ")" ]
    @ List.map then_lines ~f:(fun line -> "  " ^ line)
    @ (match else_lines with
       | [] -> []
       | lines -> "else()" :: List.map lines ~f:(fun line -> "  " ^ line))
    @ [ "endif()" ]
  | ECmakeProject { name; languages; version } ->
    let parts =
      [ name ]
      @ (match version with
         | None -> []
         | Some v -> [ "VERSION"; v ])
      @ (match languages with
         | [] -> []
         | langs -> "LANGUAGES" :: langs)
    in
    [ Fmt.str "project(%s)" (String.concat ~sep:" " parts) ]
  | ECmakeMinimumRequired version ->
    [ Fmt.str "cmake_minimum_required(VERSION %s)" version ]
  | ECmakeMessage { mode; texts } ->
    let mode_part = if String.is_empty mode then "" else mode ^ " " in
    [ Fmt.str "message(%s%s)"
        mode_part
        (String.concat ~sep:" " (List.map texts ~f:arg)) ]
  | ECmakeFunction { name; params; body } ->
    let body_lines = emit_expr body in
    [ Fmt.str "function(%s%s)"
        (target_arg name)
        (match params with
         | [] -> ""
         | params -> " " ^ String.concat ~sep:" " params)
    ]
    @ List.map body_lines ~f:(fun line -> "  " ^ line)
    @ [ "endfunction()" ]
  | ECmakeApply { name; args } ->
    [ Fmt.str "%s(%s)"
        (target_arg name)
        (String.concat ~sep:" " (List.map args ~f:arg)) ]
  | ECmakeAddSubdirectory path ->
    [ Fmt.str "add_subdirectory(%s)" (arg path) ]
  | ECmakeEnableTesting -> [ "enable_testing()" ]
  | ECmakeAddTest { name; command; args = [] } ->
    [ Fmt.str "add_test(NAME %s COMMAND %s)" (arg name) (arg command) ]
  | ECmakeAddTest { name; command; args } ->
    [ Fmt.str "add_test(NAME %s COMMAND %s %s)"
        (arg name) (arg command)
        (String.concat ~sep:" " (List.map args ~f:arg)) ]
  | ECmakeSetTargetProperty { target; property; value } ->
    [ Fmt.str "set_target_properties(%s PROPERTIES %s %s)"
        (target_arg target) property (arg value) ]
  | ECmakeGetTargetProperty { var; target; property } ->
    [ Fmt.str "get_target_property(%s %s %s)" var (target_arg target) property ]
  | ECmakeSetTestsProperties { tests; properties } ->
    let property_args =
      properties
      |> List.concat_map ~f:(fun (property, value) -> [ property; arg value ])
      |> String.concat ~sep:" "
    in
    [ Fmt.str "set_tests_properties(%s PROPERTIES %s)"
        (String.concat ~sep:" " (List.map tests ~f:arg))
        property_args ]
  | ECmakeFindPackage { package_name; required = false } ->
    [ Fmt.str "find_package(%s)" package_name ]
  | ECmakeFindPackage { package_name; required = true } ->
    [ Fmt.str "find_package(%s REQUIRED)" package_name ]
  | ECmakeTryCompile { result_var; sources } ->
    [ Fmt.str "try_compile(%s SOURCES %s)"
        result_var
        (String.concat ~sep:" " (List.map sources ~f:arg)) ]
  | _ -> fail "cannot emit Yelu1 expression to CMake"

let emit_expr ?(env = empty_subst) expr = emit_expr_impl ~env expr

let emit_script expr =
  String.concat ~sep:"\n" (emit_expr expr) ^ "\n"
