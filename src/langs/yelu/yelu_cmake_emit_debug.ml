(* Direct-text emit for yelu_cmake.expr.

   As of Phase 1.5 (retirement plan), this module is no longer on the
   production path — production emits via
   [yelu_cmake_emit] -> [lang_cmake_pp]. The direct-text emit
   stays callable as a *diagnostic aid*: useful for human inspection of
   the bridge output without going through the cmake AST, and as a
   regression target for the step-level bridge tests in
   [test_yelu_steps] and [test_yelu_emit_debug] that document
   specific bridge format conventions.

   Removal is gated on AST parity holding through at least one R3 /
   Y17 milestone — see [doc/yelu_cmake/retirement_plan.md]. *)
open Base
open Yelu_cmake
open Yelu_cmake_store
open Yelu_cmake_normal_bool
open Yelu_cmake_normal_int
open Yelu_cmake_normal_list
open Yelu_cmake_list
open Yelu_cmake_path
open Yelu_cmake_file
open Yelu_cmake_normal_target
open Yelu_cmake_target
open Yelu_cmake_install
open Yelu_cmake_string
open Yelu_cmake_if
open Yelu_cmake_cmake_op
open Yelu_cmake_dir
open Yelu_cmake_test
open Yelu_cmake_property
open Yelu_cmake_find
open Yelu_cmake_try

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
     (* Unquoted ${name} so cmake's list-deref splitting applies in
        list contexts (foreach, list APPEND items, target_link_libs).
        Users who want quoted-with-substitution should write an
        EString containing the literal "${name}" text — that case
        renders as a quoted string and preserves the user's intent.
        EString containing exactly "${name}" stays quoted (correct):
        the user wrote a string literal. *)
     | None -> "${" ^ name ^ "}")
  | EString s -> quoted s
  | ECmakeGenex s -> quoted s
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
  | EIntGreater (left, right) -> arg ~env left ^ " GREATER " ^ arg ~env right
  | EIntLessEqual (left, right) ->
    arg ~env left ^ " LESS_EQUAL " ^ arg ~env right
  | EIntGreaterEqual (left, right) ->
    arg ~env left ^ " GREATER_EQUAL " ^ arg ~env right
  | ECmakeStringEqual (left, right) ->
    arg ~env left ^ " STREQUAL " ^ arg ~env right
  | ECmakeVersionLess (a, b) ->
    arg ~env a ^ " VERSION_LESS " ^ arg ~env b
  | ECmakeVersionGreater (a, b) ->
    arg ~env a ^ " VERSION_GREATER " ^ arg ~env b
  | ECmakeVersionEqual (a, b) ->
    arg ~env a ^ " VERSION_EQUAL " ^ arg ~env b
  | ECmakeVersionLessEqual (a, b) ->
    arg ~env a ^ " VERSION_LESS_EQUAL " ^ arg ~env b
  | ECmakeVersionGreaterEqual (a, b) ->
    arg ~env a ^ " VERSION_GREATER_EQUAL " ^ arg ~env b
  | ECmakeVarDefined name -> "DEFINED " ^ name
  | ECmakeTargetExists target -> "TARGET " ^ target_arg ~env target
  | ECmakeFileExists path -> "EXISTS " ^ arg ~env path
  | ECmakeMatches { expr_; regex } ->
    arg ~env expr_ ^ " MATCHES " ^ quoted regex
  | ECmakeInList { item; list_ } ->
    arg ~env item ^ " IN_LIST " ^ arg ~env list_
  | ECmakeIsDirectory path ->
    "IS_DIRECTORY " ^ arg ~env path
  | ECmakeIsAbsolute path ->
    "IS_ABSOLUTE " ^ arg ~env path
  | ECmakePolicyCheck p ->
    "POLICY " ^ p
  | expr -> arg ~env expr

and cond_atom ?(env = empty_subst) expr =
  match expr with
  | EBool _ | ENot _ | ECmakeStringEqual _ | ECmakeVarDefined _
  | ECmakeTargetExists _ | ECmakeFileExists _
  | EIntLess _ | EIntEqual _ | EIntGreater _
  | EIntLessEqual _ | EIntGreaterEqual _
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
  | ECmakeUnsetVarCache name -> [ Fmt.str "unset(%s CACHE)" name ]
  | ECmakeSetParentScope { name; value = EList exprs } ->
    [ Fmt.str "set(%s %s PARENT_SCOPE)" name
        (String.concat ~sep:" " (List.map exprs ~f:arg)) ]
  | ECmakeSetParentScope { name; value } ->
    [ Fmt.str "set(%s %s PARENT_SCOPE)" name (arg value) ]
  | ECmakeSetEnvVar { name; value } ->
    [ Fmt.str "set(ENV{%s} %s)" name (arg value) ]
  | ECmakeUnsetEnvVar name ->
    [ Fmt.str "unset(ENV{%s})" name ]
  | ECmakeOption { name; message; value } ->
    [ Fmt.str "option(%s %s %s)" name (quoted message) (arg value) ]
  | ECmakeSetCache { name; values; cache_type; docstring; force } ->
    let values_s = String.concat ~sep:" " (List.map values ~f:arg) in
    let force_s = if force then " FORCE" else "" in
    [ Fmt.str "set(%s %s CACHE %s %s%s)"
        name values_s cache_type (quoted docstring) force_s ]
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
  | ECmakeStringRegexReplace { regex; replace; out; inputs } ->
    [ Fmt.str "string(REGEX REPLACE %s %s %s %s)"
        (quoted regex) (arg replace) out
        (String.concat ~sep:" " (List.map inputs ~f:arg)) ]
  | ECmakeStringLength { input; out } ->
    [ Fmt.str "string(LENGTH %s %s)" (arg input) out ]
  | ECmakeStringTolower { input; out } ->
    [ Fmt.str "string(TOLOWER %s %s)" (arg input) out ]
  | ECmakeStringStrip { input; out } ->
    [ Fmt.str "string(STRIP %s %s)" (arg input) out ]
  | ECmakeStringRegexMatch { regex; out; inputs } ->
    [ Fmt.str "string(REGEX MATCH %s %s %s)"
        (quoted regex) out
        (String.concat ~sep:" " (List.map inputs ~f:arg)) ]
  | ECmakeStringRegexMatchAll { regex; out; inputs } ->
    [ Fmt.str "string(REGEX MATCHALL %s %s %s)"
        (quoted regex) out
        (String.concat ~sep:" " (List.map inputs ~f:arg)) ]
  | ECmakeStringRegexQuote { out; inputs } ->
    [ Fmt.str "string(REGEX QUOTE %s %s)"
        out
        (String.concat ~sep:" " (List.map inputs ~f:arg)) ]
  | ECmakeStringAppend { cvar; inputs } ->
    [ Fmt.str "string(APPEND %s %s)"
        cvar (String.concat ~sep:" " (List.map inputs ~f:arg)) ]
  | ECmakeStringPrepend { cvar; inputs } ->
    [ Fmt.str "string(PREPEND %s %s)"
        cvar (String.concat ~sep:" " (List.map inputs ~f:arg)) ]
  | ECmakeStringJoin { glue; out; inputs } ->
    [ Fmt.str "string(JOIN %s %s %s)"
        (arg glue) out (String.concat ~sep:" " (List.map inputs ~f:arg)) ]
  | ECmakeStringFind { string; substring; out; reverse } ->
    let rev = if reverse then " REVERSE" else "" in
    [ Fmt.str "string(FIND %s %s %s%s)"
        (arg string) (arg substring) out rev ]
  | ECmakeStringSubstring { string; begin_; length; out } ->
    let len = match length with Some n -> n | None -> -1 in
    [ Fmt.str "string(SUBSTRING %s %d %d %s)"
        (arg string) begin_ len out ]
  | ECmakeStringRepeat { string; count; out } ->
    [ Fmt.str "string(REPEAT %s %d %s)" (arg string) count out ]
  | ECmakeStringGenexStrip { input; out } ->
    [ Fmt.str "string(GENEX_STRIP %s %s)" (arg input) out ]
  | ECmakeStringMakeCIdentifier { input; out } ->
    [ Fmt.str "string(MAKE_C_IDENTIFIER %s %s)" (arg input) out ]
  | ECmakeStringTimestamp { out; format; utc } ->
    let fmt = Option.value_map format ~default:""
        ~f:(fun f -> Fmt.str " %S" f) in
    let u = if utc then " UTC" else "" in
    [ Fmt.str "string(TIMESTAMP %s%s%s)" out fmt u ]
  | ECmakeStringHex { input; out } ->
    [ Fmt.str "string(HEX %s %s)" (arg input) out ]
  | ECmakeStringUuid { out; namespace; name; type_; upper } ->
    let up = if upper then " UPPER" else "" in
    [ Fmt.str "string(UUID %s NAMESPACE %s NAME %s TYPE %s%s)"
        out (quoted namespace) (quoted name) type_ up ]
  | ECmakeStringJson { out; error_var; op_name; args = _ } ->
    let ev = Option.value_map error_var ~default:""
        ~f:(fun v -> Fmt.str " ERROR_VARIABLE %s" v) in
    [ Fmt.str "string(JSON %s%s %s)" out ev op_name ]
  | ECmakeStringCompare { op; string1; string2; out } ->
    [ Fmt.str "string(COMPARE %s %s %s %s)"
        op (arg string1) (arg string2) out ]
  | ECmakeListAppend { list; items } ->
    [ Fmt.str "list(APPEND %s %s)" list (String.concat ~sep:" " (List.map items ~f:arg)) ]
  | ECmakeListGet { list; indices; out } ->
    let idxs = String.concat ~sep:" " (List.map indices ~f:Int.to_string) in
    [ Fmt.str "list(GET %s %s %s)" list idxs out ]
  | ECmakeListLength { list; out } ->
    [ Fmt.str "list(LENGTH %s %s)" list out ]
  | ECmakeListJoin { list; glue; out } ->
    [ Fmt.str "list(JOIN %s %s %s)" list (arg glue) out ]
  | ECmakeListPrepend { list; items } ->
    [ Fmt.str "list(PREPEND %s %s)"
        list (String.concat ~sep:" " (List.map items ~f:arg)) ]
  | ECmakeListInsert { list; index; items } ->
    [ Fmt.str "list(INSERT %s %d %s)"
        list index (String.concat ~sep:" " (List.map items ~f:arg)) ]
  | ECmakeListRemoveItem { list; items } ->
    [ Fmt.str "list(REMOVE_ITEM %s %s)"
        list (String.concat ~sep:" " (List.map items ~f:arg)) ]
  | ECmakeListRemoveAt { list; indices } ->
    [ Fmt.str "list(REMOVE_AT %s %s)"
        list
        (String.concat ~sep:" "
           (List.map indices ~f:Int.to_string)) ]
  | ECmakeListRemoveDuplicates { list } ->
    [ Fmt.str "list(REMOVE_DUPLICATES %s)" list ]
  | ECmakeListReverse { list } ->
    [ Fmt.str "list(REVERSE %s)" list ]
  | ECmakeListSort { list; order; compare; case } ->
    let kw kw_name = Option.value_map ~default:""
        ~f:(fun s -> Fmt.str " %s %s" kw_name s) in
    [ Fmt.str "list(SORT %s%s%s%s)"
        list (kw "ORDER" order) (kw "COMPARE" compare) (kw "CASE" case) ]
  | ECmakeListFilter { list; mode; regex } ->
    [ Fmt.str "list(FILTER %s %s REGEX %s)" list mode (quoted regex) ]
  | ECmakeListSublist { list; begin_; length; out } ->
    [ Fmt.str "list(SUBLIST %s %d %d %s)" list begin_ length out ]
  | ECmakeListFind { list; value; out } ->
    [ Fmt.str "list(FIND %s %s %s)" list (arg value) out ]
  | ECmakeListPopBack { list; out_vars } ->
    let vars = String.concat ~sep:" " out_vars in
    [ Fmt.str "list(POP_BACK %s%s)" list
        (if String.is_empty vars then "" else " " ^ vars) ]
  | ECmakeListPopFront { list; out_vars } ->
    let vars = String.concat ~sep:" " out_vars in
    [ Fmt.str "list(POP_FRONT %s%s)" list
        (if String.is_empty vars then "" else " " ^ vars) ]
  | ECmakeListTransform { list; action; selector; output } ->
    let sel = Option.value_map selector ~default:""
        ~f:(fun s -> " " ^ s) in
    let out_part = Option.value_map output ~default:""
        ~f:(fun v -> " OUTPUT_VARIABLE " ^ v) in
    [ Fmt.str "list(TRANSFORM %s %s%s%s)" list action sel out_part ]
  | ECmakePathSet { path; input; normalize } ->
    [ Fmt.str "cmake_path(SET %s%s %s)" path (if normalize then " NORMALIZE" else "") (arg input) ]
  | ECmakePathGetFilename { path; out } ->
    [ Fmt.str "cmake_path(GET %s FILENAME %s)" path out ]
  | ECmakePathNormalPath { path; out } ->
    [ Fmt.str "cmake_path(NORMAL_PATH %s%s)"
        path
        (Option.value_map out ~default:"" ~f:(fun out -> " OUTPUT_VARIABLE " ^ out))
    ]
  | ECmakeGetFilenameComponent { var; filename; mode } ->
    [ Fmt.str "get_filename_component(%s %s %s)" var (arg filename) mode ]
  (* Generalized cmake_path subcommands. *)
  | ECmakePathGet { path; field; out } ->
    [ Fmt.str "cmake_path(GET %s %s %s)" path field out ]
  | ECmakePathHas { path; field; out } ->
    [ Fmt.str "cmake_path(%s %s %s)" field path out ]
  | ECmakePathIsAbsolute { path; out } ->
    [ Fmt.str "cmake_path(IS_ABSOLUTE %s %s)" path out ]
  | ECmakePathIsRelative { path; out } ->
    [ Fmt.str "cmake_path(IS_RELATIVE %s %s)" path out ]
  | ECmakePathIsPrefix { path; input; normalize; out } ->
    [ Fmt.str "cmake_path(IS_PREFIX %s %s%s %s)"
        path (arg input)
        (if normalize then " NORMALIZE" else "")
        out ]
  | ECmakePathCompare { input1; op; input2; out } ->
    [ Fmt.str "cmake_path(COMPARE %s %s %s %s)"
        (arg input1) op (arg input2) out ]
  | ECmakePathAppend { path; inputs; out } ->
    let opt_out = Option.value_map out ~default:""
        ~f:(fun o -> " OUTPUT_VARIABLE " ^ o) in
    [ Fmt.str "cmake_path(APPEND %s %s%s)"
        path (String.concat ~sep:" " (List.map inputs ~f:arg)) opt_out ]
  | ECmakePathAppendString { path; inputs; out } ->
    let opt_out = Option.value_map out ~default:""
        ~f:(fun o -> " OUTPUT_VARIABLE " ^ o) in
    [ Fmt.str "cmake_path(APPEND_STRING %s %s%s)"
        path (String.concat ~sep:" " (List.map inputs ~f:arg)) opt_out ]
  | ECmakePathRemoveFilename { path; out } ->
    let opt_out = Option.value_map out ~default:""
        ~f:(fun o -> " OUTPUT_VARIABLE " ^ o) in
    [ Fmt.str "cmake_path(REMOVE_FILENAME %s%s)" path opt_out ]
  | ECmakePathReplaceFilename { path; input; out } ->
    let opt_out = Option.value_map out ~default:""
        ~f:(fun o -> " OUTPUT_VARIABLE " ^ o) in
    [ Fmt.str "cmake_path(REPLACE_FILENAME %s %s%s)"
        path (arg input) opt_out ]
  | ECmakePathRemoveExtension { path; last_only; out } ->
    let lo = if last_only then " LAST_ONLY" else "" in
    let opt_out = Option.value_map out ~default:""
        ~f:(fun o -> " OUTPUT_VARIABLE " ^ o) in
    [ Fmt.str "cmake_path(REMOVE_EXTENSION %s%s%s)" path lo opt_out ]
  | ECmakePathReplaceExtension { path; last_only; input; out } ->
    let lo = if last_only then " LAST_ONLY" else "" in
    let opt_out = Option.value_map out ~default:""
        ~f:(fun o -> " OUTPUT_VARIABLE " ^ o) in
    [ Fmt.str "cmake_path(REPLACE_EXTENSION %s%s %s%s)"
        path lo (arg input) opt_out ]
  | ECmakePathRelativePath { path; base_dir; out } ->
    let bd = Option.value_map base_dir ~default:""
        ~f:(fun d -> " BASE_DIRECTORY " ^ arg d) in
    let opt_out = Option.value_map out ~default:""
        ~f:(fun o -> " OUTPUT_VARIABLE " ^ o) in
    [ Fmt.str "cmake_path(RELATIVE_PATH %s%s%s)" path bd opt_out ]
  | ECmakePathAbsolutePath { path; base_dir; normalize; out } ->
    let bd = Option.value_map base_dir ~default:""
        ~f:(fun d -> " BASE_DIRECTORY " ^ arg d) in
    let nz = if normalize then " NORMALIZE" else "" in
    let opt_out = Option.value_map out ~default:""
        ~f:(fun o -> " OUTPUT_VARIABLE " ^ o) in
    [ Fmt.str "cmake_path(ABSOLUTE_PATH %s%s%s%s)" path bd nz opt_out ]
  | ECmakePathNativePath { path; normalize; out } ->
    let nz = if normalize then " NORMALIZE" else "" in
    [ Fmt.str "cmake_path(NATIVE_PATH %s%s %s)" path nz out ]
  | ECmakePathConvertToCmake { input; normalize; out } ->
    let nz = if normalize then " NORMALIZE" else "" in
    [ Fmt.str "cmake_path(CONVERT %s TO_CMAKE_PATH_LIST %s%s)"
        (arg input) out nz ]
  | ECmakePathConvertToNative { input; normalize; out } ->
    let nz = if normalize then " NORMALIZE" else "" in
    [ Fmt.str "cmake_path(CONVERT %s TO_NATIVE_PATH_LIST %s%s)"
        (arg input) out nz ]
  | ECmakePathHash { path; out } ->
    [ Fmt.str "cmake_path(HASH %s %s)" path out ]
  | ECmakeFileWrite { path; content } ->
    [ Fmt.str "file(WRITE %s %s)"
        (arg path)
        (String.concat ~sep:" " (List.map content ~f:arg))
    ]
  | ECmakeFileWriteAppend { path; content } ->
    [ Fmt.str "file(APPEND %s %s)"
        (arg path)
        (String.concat ~sep:" " (List.map content ~f:arg))
    ]
  | ECmakeFileRead { path; out } ->
    [ Fmt.str "file(READ %s %s)" (arg path) out ]
  | ECmakeFileReadFull { path; out; offset; limit; hex } ->
    let off = Option.value_map offset ~default:""
        ~f:(fun n -> Fmt.str " OFFSET %d" n) in
    let lim = Option.value_map limit ~default:""
        ~f:(fun n -> Fmt.str " LIMIT %d" n) in
    let h = if hex then " HEX" else "" in
    [ Fmt.str "file(READ %s %s%s%s%s)" (arg path) out off lim h ]
  | ECmakeFileStrings { out; path; regex; encoding; limit_count } ->
    let rx = Option.value_map regex ~default:""
        ~f:(fun r -> Fmt.str " REGEX %S" r) in
    let enc = Option.value_map encoding ~default:""
        ~f:(fun e -> Fmt.str " ENCODING %s" e) in
    let lc = Option.value_map limit_count ~default:""
        ~f:(fun n -> Fmt.str " LIMIT_COUNT %d" n) in
    [ Fmt.str "file(STRINGS %s %s%s%s%s)" (arg path) out rx enc lc ]
  | ECmakeFileTouch { files; nocreate } ->
    let sub = if nocreate then "TOUCH_NOCREATE" else "TOUCH" in
    [ Fmt.str "file(%s %s)" sub
        (String.concat ~sep:" " (List.map files ~f:arg)) ]
  | ECmakeFileMakeDirectory { dirs } ->
    [ Fmt.str "file(MAKE_DIRECTORY %s)"
        (String.concat ~sep:" " (List.map dirs ~f:arg)) ]
  | ECmakeFileRename { old_; new_; result; no_replace } ->
    let res = Option.value_map result ~default:""
        ~f:(fun v -> Fmt.str " RESULT %s" v) in
    let nr = if no_replace then " NO_REPLACE" else "" in
    [ Fmt.str "file(RENAME %s %s%s%s)" (arg old_) (arg new_) res nr ]
  | ECmakeFileRemove { files; recurse } ->
    let sub = if recurse then "REMOVE_RECURSE" else "REMOVE" in
    [ Fmt.str "file(%s %s)" sub
        (String.concat ~sep:" " (List.map files ~f:arg)) ]
  | ECmakeFileCopy { input; output; result; only_if_different } ->
    let res = Option.value_map result ~default:""
        ~f:(fun v -> Fmt.str " RESULT %s" v) in
    let oid = if only_if_different then " ONLY_IF_DIFFERENT" else "" in
    [ Fmt.str "file(COPY_FILE %s %s%s%s)"
        (arg input) (arg output) res oid ]
  | ECmakeFileRealPath { out; path; base_dir; expand_tilde } ->
    let bd = Option.value_map base_dir ~default:""
        ~f:(fun b -> Fmt.str " BASE_DIRECTORY %s" (arg b)) in
    let et = if expand_tilde then " EXPAND_TILDE" else "" in
    [ Fmt.str "file(REAL_PATH %s %s%s%s)" (arg path) out bd et ]
  | ECmakeFileSize { out; path } ->
    [ Fmt.str "file(SIZE %s %s)" (arg path) out ]
  | ECmakeFileReadSymlink { out; link } ->
    [ Fmt.str "file(READ_SYMLINK %s %s)" (arg link) out ]
  | ECmakeFileTimestamp { out; path; format; utc } ->
    let fmt = Option.value_map format ~default:""
        ~f:(fun f -> Fmt.str " %S" f) in
    let u = if utc then " UTC" else "" in
    [ Fmt.str "file(TIMESTAMP %s %s%s%s)" (arg path) out fmt u ]
  | ECmakeConfigureFile { input; output; only } ->
    let only_flag = if only then " @ONLY" else "" in
    [ Fmt.str "configure_file(%s %s%s)" (arg input) (arg output) only_flag ]
  | ECmakeFileRelativePath { var; base; file } ->
    [ Fmt.str "file(RELATIVE_PATH %s %s %s)" var (arg base) (arg file) ]
  | ECmakeFileGlob { out; recurse; relative; configure_depends; patterns } ->
    let cmd = if recurse then "GLOB_RECURSE" else "GLOB" in
    let rel = Option.value_map relative ~default:""
      ~f:(fun e -> Fmt.str " RELATIVE %s" (arg e)) in
    let cd = if configure_depends then " CONFIGURE_DEPENDS" else "" in
    [ Fmt.str "file(%s %s%s%s %s)" cmd out rel cd
        (String.concat ~sep:" " (List.map patterns ~f:arg)) ]
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
  | ECmakeAddLibraryAlias { name; target } ->
    [ Fmt.str "add_library(%s ALIAS %s)" name target ]
  | ECmakeAddExecutableAlias { name; target } ->
    [ Fmt.str "add_executable(%s ALIAS %s)" name target ]
  | ECmakeAddDependencies { target; deps } ->
    [ Fmt.str "add_dependencies(%s %s)" target (String.concat ~sep:" " deps) ]
  | ECmakeAddLibraryImported { name; lib_type; global } ->
    let lt = Option.value lib_type ~default:"UNKNOWN" in
    let g = if global then " GLOBAL" else "" in
    [ Fmt.str "add_library(%s %s IMPORTED%s)" (target_arg name) lt g ]
  | ECmakeTargetSources { target; visibility; sources } ->
    let visibility = string_of_visibility visibility in
    [ Fmt.str "target_sources(%s %s %s)" (target_arg target) visibility (String.concat ~sep:" " (List.map sources ~f:arg)) ]
  | ECmakeTargetSourcesFs { target; items } ->
    let render_item = function
      | Tsi_plain { visibility = vis; items } ->
        Fmt.str "%s %s" (string_of_visibility vis)
          (String.concat ~sep:" " (List.map items ~f:arg))
      | Tsi_file_set { kind; type_; base_dirs; files } ->
        let opt_kw kw xs =
          if List.is_empty xs then ""
          else " " ^ kw ^ " " ^ String.concat ~sep:" " (List.map xs ~f:arg)
        in
        Fmt.str "%s FILE_SET %s%s%s" kind type_
          (opt_kw "BASE_DIRS" base_dirs)
          (opt_kw "FILES" files)
    in
    [ Fmt.str "target_sources(%s %s)" (target_arg target)
        (String.concat ~sep:" " (List.map items ~f:render_item)) ]
  | ECmakeTargetPrecompileHeaders { target; visibility; headers } ->
    let visibility = string_of_visibility visibility in
    [ Fmt.str "target_precompile_headers(%s %s %s)"
        (target_arg target) visibility
        (String.concat ~sep:" " (List.map headers ~f:arg)) ]
  | ECmakeTargetLinkLibraries { target; visibility; items } ->
    let visibility = string_of_visibility visibility in
    [ Fmt.str "target_link_libraries(%s %s %s)" (target_arg target) visibility (String.concat ~sep:" " (List.map items ~f:arg)) ]
  | ECmakeTargetIncludeDirectories { target; visibility; before; system; dirs } ->
    let visibility = string_of_visibility visibility in
    let b = if before then "BEFORE " else "" in
    let s = if system then "SYSTEM " else "" in
    [ Fmt.str "target_include_directories(%s %s%s%s %s)"
        (target_arg target) b s visibility
        (String.concat ~sep:" " (List.map dirs ~f:arg)) ]
  | ECmakeTargetCompileDefinitions { target; visibility; definitions } ->
    let visibility = string_of_visibility visibility in
    [ Fmt.str "target_compile_definitions(%s %s %s)" (target_arg target) visibility (String.concat ~sep:" " (List.map definitions ~f:arg)) ]
  | ECmakeTargetCompileOptions { target; visibility; before; options_ } ->
    let visibility = string_of_visibility visibility in
    let b = if before then "BEFORE " else "" in
    [ Fmt.str "target_compile_options(%s %s%s %s)"
        (target_arg target) b visibility
        (String.concat ~sep:" " (List.map options_ ~f:arg)) ]
  | ECmakeTargetCompileFeatures { target; visibility; features } ->
    let visibility = string_of_visibility visibility in
    [ Fmt.str "target_compile_features(%s %s %s)" (target_arg target) visibility (String.concat ~sep:" " (List.map features ~f:target_arg)) ]
  | ECmakeTargetLinkOptions { target; visibility; before; options_ } ->
    let visibility = string_of_visibility visibility in
    let b = if before then "BEFORE " else "" in
    [ Fmt.str "target_link_options(%s %s%s %s)"
        (target_arg target) b visibility
        (String.concat ~sep:" " (List.map options_ ~f:arg)) ]
  | ECmakeTargetLinkDirectories { target; visibility; before; dirs } ->
    let visibility = string_of_visibility visibility in
    let b = if before then "BEFORE " else "" in
    [ Fmt.str "target_link_directories(%s %s%s %s)"
        (target_arg target) b visibility
        (String.concat ~sep:" " (List.map dirs ~f:arg)) ]
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
  | ECmakeInstallExport { export; destination; file; namespace } ->
    let file_part =
      Option.value_map file ~default:"" ~f:(fun f -> Fmt.str " FILE %s" (arg f))
    in
    let ns_part =
      Option.value_map namespace ~default:""
        ~f:(fun ns -> Fmt.str " NAMESPACE %s" ns)
    in
    [ Fmt.str "install(EXPORT %s%s DESTINATION %s%s)"
        (arg export) file_part (arg destination) ns_part ]
  | ECmakeExportExport { name; file } ->
    let file_part =
      Option.value_map file ~default:"" ~f:(fun f -> Fmt.str " FILE %s" (arg f))
    in
    [ Fmt.str "export(EXPORT %s%s)" (arg name) file_part ]
  | ECmakeConfigurePackageConfigFile
      { install_dest; input; output;
        no_set_and_check_macro; no_check_required_components_macro } ->
    let flag = function
      | true, kw -> " " ^ kw
      | false, _ -> ""
    in
    [ Fmt.str
        "configure_package_config_file(%s %s INSTALL_DESTINATION %s%s%s)"
        (arg input) (arg output) (arg install_dest)
        (flag (no_set_and_check_macro, "NO_SET_AND_CHECK_MACRO"))
        (flag (no_check_required_components_macro,
               "NO_CHECK_REQUIRED_COMPONENTS_MACRO"))
    ]
  | ECmakeWriteBasicPackageVersionFile
      { file; version; compatibility; arch_independent } ->
    let version_part =
      Option.value_map version ~default:""
        ~f:(fun v -> Fmt.str " VERSION %s" (arg v))
    in
    let arch_part = if arch_independent then " ARCH_INDEPENDENT" else "" in
    [ Fmt.str
        "write_basic_package_version_file(%s%s COMPATIBILITY %s%s)"
        (arg file) version_part compatibility arch_part ]
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
  | ECmakeMacro { name; params; body } ->
    let body_lines = emit_expr body in
    [ Fmt.str "macro(%s%s)"
        (target_arg name)
        (match params with
         | [] -> ""
         | params -> " " ^ String.concat ~sep:" " params)
    ]
    @ List.map body_lines ~f:(fun line -> "  " ^ line)
    @ [ "endmacro()" ]
  | ECmakeForeach { loop_var; items; body } ->
    let body_lines = emit_expr body in
    [ Fmt.str "foreach(%s %s)" loop_var
        (String.concat ~sep:" " (List.map items ~f:arg)) ]
    @ List.map body_lines ~f:(fun line -> "  " ^ line)
    @ [ "endforeach()" ]
  | ECmakeForeachZip { loop_vars; lists; body } ->
    let body_lines = emit_expr body in
    [ Fmt.str "foreach(%s IN ZIP_LISTS %s)"
        (String.concat ~sep:" " loop_vars)
        (String.concat ~sep:" " lists) ]
    @ List.map body_lines ~f:(fun line -> "  " ^ line)
    @ [ "endforeach()" ]
  | ECmakeForeachInList { loop_var; lists; items; body } ->
    let body_lines = emit_expr body in
    let lists_part =
      if List.is_empty lists then ""
      else " LISTS " ^ String.concat ~sep:" " lists
    in
    let items_part =
      if List.is_empty items then ""
      else " ITEMS " ^ String.concat ~sep:" " (List.map items ~f:arg)
    in
    [ Fmt.str "foreach(%s IN%s%s)" loop_var lists_part items_part ]
    @ List.map body_lines ~f:(fun line -> "  " ^ line)
    @ [ "endforeach()" ]
  | ECmakeForeachRange { loop_var; start; stop; step; body } ->
    let body_lines = emit_expr body in
    let args = match start, step with
      | None, None -> Fmt.str "%d" stop
      | Some s, None -> Fmt.str "%d %d" s stop
      | Some s, Some t -> Fmt.str "%d %d %d" s stop t
      | None, Some t -> Fmt.str "0 %d %d" stop t
    in
    [ Fmt.str "foreach(%s RANGE %s)" loop_var args ]
    @ List.map body_lines ~f:(fun line -> "  " ^ line)
    @ [ "endforeach()" ]
  | ECmakeSeparateArguments { var; mode; input } ->
    let inp = Option.value_map input ~default:""
        ~f:(fun e -> " " ^ arg e) in
    [ Fmt.str "separate_arguments(%s %s%s)" var mode inp ]
  | ECmakeWhile { cond = c; body } ->
    let body_lines = emit_expr body in
    [ Fmt.str "while(%s)" (cond c) ]
    @ List.map body_lines ~f:(fun line -> "  " ^ line)
    @ [ "endwhile()" ]
  | ECmakeBreak -> [ "break()" ]
  | ECmakeContinue -> [ "continue()" ]
  | ECmakeReturn { propagate_vars } ->
    if List.is_empty propagate_vars then [ "return()" ]
    else
      [ Fmt.str "return(PROPAGATE %s)"
          (String.concat ~sep:" " propagate_vars) ]
  | ECmakeBlock { scope_vars; propagate; body } ->
    let scope_part =
      if List.is_empty scope_vars then ""
      else " SCOPE_FOR VARIABLES " ^ String.concat ~sep:" " scope_vars
    in
    let propagate_part =
      if String.is_empty propagate then ""
      else " PROPAGATE " ^ propagate
    in
    let body_lines = emit_expr body in
    [ Fmt.str "block(%s%s)"
        (if String.is_empty scope_part then ""
         else String.lstrip scope_part)
        propagate_part ]
    @ List.map body_lines ~f:(fun line -> "  " ^ line)
    @ [ "endblock()" ]
  | ECmakeApply { name; args } ->
    [ Fmt.str "%s(%s)"
        (target_arg name)
        (String.concat ~sep:" " (List.map args ~f:arg)) ]
  | ECmakeInclude { file; optional = false } ->
    [ Fmt.str "include(%s)" (arg file) ]
  | ECmakeInclude { file; optional = true } ->
    [ Fmt.str "include(%s OPTIONAL)" (arg file) ]
  | ECmakeAtVar key -> [ Fmt.str "@%s@" key ]
  | ECmakeMath { exp; out } ->
    [ Fmt.str "math(EXPR %s %s)" out (quoted exp) ]
  | ECmakeEnableLanguage { langs; optional } ->
    let opt = if optional then " OPTIONAL" else "" in
    [ Fmt.str "enable_language(%s%s)" (String.concat ~sep:" " langs) opt ]
  | ECmakePolicySet { id; new_ } ->
    [ Fmt.str "cmake_policy(SET %s %s)" id (if new_ then "NEW" else "OLD") ]
  | ECmakeLanguageCall { cmd; args } ->
    [ Fmt.str "cmake_language(CALL %s %s)" cmd
        (String.concat ~sep:" " (List.map args ~f:arg)) ]
  | ECmakeLanguageEval { code } ->
    [ Fmt.str "cmake_language(EVAL CODE %S)" code ]
  | ECmakeLanguageGetLogLevel { out } ->
    [ Fmt.str "cmake_language(GET_MESSAGE_LOG_LEVEL %s)" out ]
  | ECmakeVariableWatch { var; command } ->
    let cmd_part = Option.value_map command ~default:""
        ~f:(fun c -> " " ^ c) in
    [ Fmt.str "variable_watch(%s%s)" var cmd_part ]
  | ECmakeExecuteProcess r ->
    let cmds =
      List.map r.commands ~f:(fun cmd ->
        Fmt.str "  COMMAND %s"
          (String.concat ~sep:" " (List.map cmd ~f:arg)))
    in
    let kv key v_opt =
      Option.value_map v_opt ~default:""
        ~f:(fun v -> Fmt.str "\n  %s %s" key v)
    in
    let arg_kv key e_opt =
      Option.value_map e_opt ~default:""
        ~f:(fun e -> Fmt.str "\n  %s %s" key (arg e))
    in
    let timeout =
      Option.value_map r.timeout ~default:""
        ~f:(fun t -> Fmt.str "\n  TIMEOUT %g" t)
    in
    let flag b kw = if b then "\n  " ^ kw else "" in
    let opts =
      kv "RESULT_VARIABLE" r.result_variable
      ^ kv "OUTPUT_VARIABLE" r.output_variable
      ^ kv "ERROR_VARIABLE" r.error_variable
      ^ arg_kv "INPUT_FILE" r.input_file
      ^ arg_kv "OUTPUT_FILE" r.output_file
      ^ arg_kv "ERROR_FILE" r.error_file
      ^ flag r.output_quiet "OUTPUT_QUIET"
      ^ flag r.error_quiet "ERROR_QUIET"
      ^ flag r.output_strip_trailing_whitespace
          "OUTPUT_STRIP_TRAILING_WHITESPACE"
      ^ flag r.error_strip_trailing_whitespace
          "ERROR_STRIP_TRAILING_WHITESPACE"
      ^ kv "COMMAND_ERROR_IS_FATAL" r.command_error_is_fatal
      ^ timeout
    in
    [ "execute_process("
      ^ String.concat ~sep:"\n" cmds
      ^ opts ^ ")" ]
  | ECmakeIncludeGuard { scope } ->
    [ Fmt.str "include_guard(%s)" scope ]
  | ECmakeQuoteCmd s -> [ s ]
  | ECmakeAddSubdirectory path ->
    [ Fmt.str "add_subdirectory(%s)" (arg path) ]
  | ECmakeIncludeDirectories { dirs; before; system } ->
    let prefix_parts =
      (if before then [ "BEFORE" ] else [])
      @ (if system then [ "SYSTEM" ] else [])
    in
    let inner =
      String.concat ~sep:" "
        (prefix_parts @ List.map dirs ~f:arg)
    in
    [ Fmt.str "include_directories(%s)" inner ]
  | ECmakeAddCompileDefinitions defs ->
    [ Fmt.str "add_compile_definitions(%s)"
        (String.concat ~sep:" " (List.map defs ~f:arg)) ]
  | ECmakeAddCompileOptions opts ->
    [ Fmt.str "add_compile_options(%s)"
        (String.concat ~sep:" " (List.map opts ~f:arg)) ]
  | ECmakeAddLinkOptions opts ->
    [ Fmt.str "add_link_options(%s)"
        (String.concat ~sep:" " (List.map opts ~f:arg)) ]
  | ECmakeAddDefinitions defs ->
    [ Fmt.str "add_definitions(%s)"
        (String.concat ~sep:" " (List.map defs ~f:arg)) ]
  | ECmakeLinkDirectories { dirs; before } ->
    let before_s = if before then "BEFORE " else "" in
    [ Fmt.str "link_directories(%s%s)"
        before_s
        (String.concat ~sep:" " (List.map dirs ~f:arg)) ]
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
  | ECmakeSetProperty { targets; append; properties } ->
    let ts = String.concat ~sep:" " (List.map targets ~f:target_arg) in
    let ap = if append then " APPEND" else "" in
    List.map properties ~f:(fun (property, value) ->
      Fmt.str "set_property(TARGET %s%s PROPERTY %s %s)"
        ts ap property (arg value))
  | ECmakeSetPropertySource { files; append; properties } ->
    let fs = String.concat ~sep:" " (List.map files ~f:target_arg) in
    let ap = if append then " APPEND" else "" in
    List.map properties ~f:(fun (property, value) ->
      Fmt.str "set_property(SOURCE %s%s PROPERTY %s %s)"
        fs ap property (arg value))
  | ECmakeSetGlobalProperty { properties } ->
    List.map properties ~f:(fun (property, value) ->
      Fmt.str "set_property(GLOBAL PROPERTY %s %s)" property (arg value))
  | ECmakeGetProperty { var; target; property; set_form } ->
    let suffix = if set_form then " SET" else "" in
    [ Fmt.str "get_property(%s TARGET %s PROPERTY %s%s)"
        var (arg target) property suffix ]
  | ECmakeGetDirectoryProperty { var; property } ->
    [ Fmt.str "get_directory_property(%s %s)" var property ]
  | ECmakeSetDirectoryProperty { property; append; values } ->
    let ap = if append then " APPEND" else "" in
    [ Fmt.str "set_directory_properties(PROPERTIES%s %s %s)"
        ap property
        (String.concat ~sep:" " (List.map values ~f:arg)) ]
  | ECmakeSetSourceProperty { file; property; values } ->
    [ Fmt.str "set_source_files_properties(%s PROPERTIES %s %s)"
        (arg file) property
        (String.concat ~sep:" " (List.map values ~f:arg)) ]
  | ECmakeGetGlobalProperty { var; property } ->
    [ Fmt.str "get_property(%s GLOBAL PROPERTY %s)" var property ]
  | ECmakeDefineProperty
      { mode; property_name; inherited; brief_docs; full_docs;
        initialize_from } ->
    let inh = if inherited then " INHERITED" else "" in
    let bd_part =
      if List.is_empty brief_docs then ""
      else " BRIEF_DOCS "
        ^ String.concat ~sep:" " (List.map brief_docs ~f:quoted)
    in
    let fd_part =
      if List.is_empty full_docs then ""
      else " FULL_DOCS "
        ^ String.concat ~sep:" " (List.map full_docs ~f:quoted)
    in
    let init = Option.value_map initialize_from ~default:""
        ~f:(fun v -> Fmt.str " INITIALIZE_FROM_VARIABLE %s" v) in
    [ Fmt.str "define_property(%s PROPERTY %s%s%s%s%s)"
        mode property_name inh bd_part fd_part init ]
  | ECmakeSetTestsProperties { tests; properties } ->
    let property_args =
      properties
      |> List.concat_map ~f:(fun (property, value) -> [ property; arg value ])
      |> String.concat ~sep:" "
    in
    [ Fmt.str "set_tests_properties(%s PROPERTIES %s)"
        (String.concat ~sep:" " (List.map tests ~f:arg))
        property_args ]
  | ECmakeFindPackage { package_name; version; exact; quiet; config_mode;
                        required; components; optional_components } ->
    let parts =
      [ Some package_name; version ]
      |> List.filter_opt
      |> fun xs -> xs
        @ (if exact then [ "EXACT" ] else [])
        @ (if quiet then [ "QUIET" ] else [])
        @ (if config_mode then [ "CONFIG" ] else [])
        @ (if required then [ "REQUIRED" ] else [])
        @ (if List.is_empty components then []
           else "COMPONENTS" :: components)
        @ (if List.is_empty optional_components then []
           else "OPTIONAL_COMPONENTS" :: optional_components)
    in
    [ Fmt.str "find_package(%s)" (String.concat ~sep:" " parts) ]
  | ECmakeFindLibrary { out; names; paths; hints; required } ->
    let kw_list key xs =
      if List.is_empty xs then ""
      else " " ^ key ^ " " ^ String.concat ~sep:" " (List.map xs ~f:arg)
    in
    let req = if required then " REQUIRED" else "" in
    [ Fmt.str "find_library(%s%s%s%s%s)"
        out (kw_list "NAMES" names) (kw_list "HINTS" hints)
        (kw_list "PATHS" paths) req ]
  | ECmakeFindPath { out; names; paths; hints; required } ->
    let kw_list key xs =
      if List.is_empty xs then ""
      else " " ^ key ^ " " ^ String.concat ~sep:" " (List.map xs ~f:arg)
    in
    let req = if required then " REQUIRED" else "" in
    [ Fmt.str "find_path(%s%s%s%s%s)"
        out (kw_list "NAMES" names) (kw_list "HINTS" hints)
        (kw_list "PATHS" paths) req ]
  | ECmakeFindProgram { out; names; paths; hints; required } ->
    let kw_list key xs =
      if List.is_empty xs then ""
      else " " ^ key ^ " " ^ String.concat ~sep:" " (List.map xs ~f:arg)
    in
    let req = if required then " REQUIRED" else "" in
    [ Fmt.str "find_program(%s%s%s%s%s)"
        out (kw_list "NAMES" names) (kw_list "HINTS" hints)
        (kw_list "PATHS" paths) req ]
  | ECmakeFindFile { out; names; paths; hints; required } ->
    let kw_list key xs =
      if List.is_empty xs then ""
      else " " ^ key ^ " " ^ String.concat ~sep:" " (List.map xs ~f:arg)
    in
    let req = if required then " REQUIRED" else "" in
    [ Fmt.str "find_file(%s%s%s%s%s)"
        out (kw_list "NAMES" names) (kw_list "HINTS" hints)
        (kw_list "PATHS" paths) req ]
  | ECmakeTryCompile { result_var; sources } ->
    [ Fmt.str "try_compile(%s SOURCES %s)"
        result_var
        (String.concat ~sep:" " (List.map sources ~f:arg)) ]
  | ECmakeTryCompileEx r ->
    let kw_list key xs =
      if List.is_empty xs then ""
      else " " ^ key ^ " "
        ^ String.concat ~sep:" " (List.map xs ~f:arg)
    in
    let opt_kv key v_opt =
      Option.value_map v_opt ~default:""
        ~f:(fun v -> Fmt.str " %s %s" key v)
    in
    let no_cache = if r.no_cache then " NO_CACHE" else "" in
    [ Fmt.str "try_compile(%s SOURCES %s%s%s%s%s%s%s%s)"
        r.result_var
        (String.concat ~sep:" " (List.map r.sources ~f:arg))
        (kw_list "COMPILE_DEFINITIONS" r.compile_definitions)
        (kw_list "LINK_LIBRARIES" r.link_libraries)
        (kw_list "LINK_OPTIONS" r.link_options)
        (opt_kv "OUTPUT_VARIABLE" r.output_variable)
        (opt_kv "C_STANDARD" r.c_standard)
        (opt_kv "CXX_STANDARD" r.cxx_standard)
        no_cache ]
  | ECmakeTryRun r ->
    let kw_list key xs =
      if List.is_empty xs then ""
      else " " ^ key ^ " "
        ^ String.concat ~sep:" " (List.map xs ~f:arg)
    in
    let opt_kv key v_opt =
      Option.value_map v_opt ~default:""
        ~f:(fun v -> Fmt.str " %s %s" key v)
    in
    [ Fmt.str "try_run(%s %s SOURCES %s%s%s%s%s%s)"
        r.run_result_var r.compile_result_var
        (String.concat ~sep:" " (List.map r.sources ~f:arg))
        (kw_list "COMPILE_DEFINITIONS" r.compile_definitions)
        (kw_list "LINK_LIBRARIES" r.link_libraries)
        (opt_kv "COMPILE_OUTPUT_VARIABLE" r.compile_output_variable)
        (opt_kv "RUN_OUTPUT_VARIABLE" r.run_output_variable)
        (kw_list "ARGS" r.args) ]
  | _ -> fail "cannot emit yelu_cmake expression to CMake"

let emit_expr ?(env = empty_subst) expr = emit_expr_impl ~env expr

let emit_script expr =
  String.concat ~sep:"\n" (emit_expr expr) ^ "\n"
