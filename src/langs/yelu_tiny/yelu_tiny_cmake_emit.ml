open Base
open Yelu_tiny
open Yelu_surface_cmake_store
open Yelu_theory_bool
open Yelu_theory_int
open Yelu_theory_list
open Yelu_surface_cmake_list
open Yelu_surface_cmake_path
open Yelu_theory_target
open Yelu_surface_cmake_target
open Yelu_surface_cmake_string
open Yelu_surface_cmake_if

let escape_quoted s =
  s
  |> String.substr_replace_all ~pattern:"\\" ~with_:"\\\\"
  |> String.substr_replace_all ~pattern:"\"" ~with_:"\\\""

let quoted s = "\"" ^ escape_quoted s ^ "\""

let arg = function
  | EString s -> quoted s
  | EInt n -> Int.to_string n
  | EBool true -> "ON"
  | EBool false -> "OFF"
  | ETarget name -> quoted name
  | EVar name -> quoted ("${" ^ name ^ "}")
  | _ -> fail "cannot emit expression as CMake argument"

let build_command_arg arg = quoted arg

let build_command { command; args } =
  String.concat ~sep:" " (List.map (command :: args) ~f:build_command_arg)

let rec cond = function
  | EBool true -> "TRUE"
  | EBool false -> "FALSE"
  | ENot expr -> "NOT " ^ cond_atom expr
  | EAnd (left, right) -> cond_atom left ^ " AND " ^ cond_atom right
  | EOr (left, right) -> cond_atom left ^ " OR " ^ cond_atom right
  | EIntLess (left, right) -> arg left ^ " LESS " ^ arg right
  | EIntEqual (left, right) -> arg left ^ " EQUAL " ^ arg right
  | ECmakeStringEqual (left, right) -> arg left ^ " STREQUAL " ^ arg right
  | ECmakeVarDefined name -> "DEFINED " ^ name
  | ECmakeTargetExists name -> "TARGET " ^ name
  | expr -> arg expr

and cond_atom expr =
  match expr with
  | EBool _ | ENot _ | ECmakeStringEqual _ | ECmakeVarDefined _
  | ECmakeTargetExists _ | EIntLess _ | EIntEqual _ | EVar _ | EString _ -> cond expr
  | EAnd _ | EOr _ -> "(" ^ cond expr ^ ")"
  | _ -> cond expr

let rec emit_expr = function
  | EUnit -> []
  | ESeq exprs -> List.concat_map exprs ~f:emit_expr
  | ESetVar (name, EList exprs) ->
    [ Fmt.str "set(%s %s)" name (String.concat ~sep:" " (List.map exprs ~f:arg)) ]
  | ESetVar (name, expr) -> [ Fmt.str "set(%s %s)" name (arg expr) ]
  | ECmakeUnsetVar name -> [ Fmt.str "unset(%s)" name ]
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
  | ECmakeAddExecutable { name; sources } ->
    [ Fmt.str "add_executable(%s %s)" name (String.concat ~sep:" " (List.map sources ~f:arg)) ]
  | ECmakeTargetSources { target; visibility; sources } ->
    [ Fmt.str "target_sources(%s %s %s)" target visibility (String.concat ~sep:" " (List.map sources ~f:arg)) ]
  | ECmakeTargetLinkLibraries { target; visibility; items } ->
    [ Fmt.str "target_link_libraries(%s %s %s)" target visibility (String.concat ~sep:" " (List.map items ~f:arg)) ]
  | ECmakeTargetIncludeDirectories { target; visibility; dirs } ->
    [ Fmt.str "target_include_directories(%s %s %s)" target visibility (String.concat ~sep:" " (List.map dirs ~f:arg)) ]
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
    [ Fmt.str "add_custom_target(%s%s" name all ]
    @ command_lines
    @ depends
    @ comment
    @ [ "  VERBATIM"; ")" ]
  | ECmakeIfStmt { cond = c; then_; else_ } ->
    let then_lines = emit_expr then_ in
    let else_lines = Option.value_map else_ ~default:[] ~f:emit_expr in
    [ "if(" ^ cond c ^ ")" ]
    @ List.map then_lines ~f:(fun line -> "  " ^ line)
    @ (match else_lines with
       | [] -> []
       | lines -> "else()" :: List.map lines ~f:(fun line -> "  " ^ line))
    @ [ "endif()" ]
  | _ -> fail "cannot emit Yelu1 expression to CMake"

let emit_script expr =
  String.concat ~sep:"\n" (emit_expr expr) ^ "\n"
