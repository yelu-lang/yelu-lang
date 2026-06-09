(* Cmake text → yelu_cmake.expr bridge — the I/O-doing side of
   the bridge chain. The library [yelu_langs] is I/O-free;
   anything that spawns subprocesses or reads files lives here
   in [yelu_runner].

   Used by:
   - The fmt smoke tests (single + matrix), which both used to
     inline this logic.
   - The include() eval path: env.include_loader is registered
     to call parse_file, so ECmakeInclude { file = "GNUInstallDirs" }
     resolves → reads → bridges → evals in the current scope.

   Pipeline this module covers (steps 1 → 2 → 3 of the
   cache_plan.md smoke):

     cmake text
       → parse.py (subprocess)
         → JSON CST
           → Cmake_text_parse.file_of_json
             → Stage-1 untyped AST
               → per-stmt: parse_cmd + from_emit + recurse on
                 if-block bodies
                 → yelu_cmake.expr (ESeq) *)

open Base
module Cp = Yelu_langs.Cmake_text_parse
module Yc = Yelu_langs.Yelu_cmake
module Fe = Yelu_langs.Yelu_cmake_from_emit
module If_frag = Yelu_langs.Yelu_cmake_if

(* ============================================================
   Configuration — paths the bridge needs to find.

   parse_py defaults to the project-relative location; callers
   can override at startup if running from a different cwd.
   cmake_modules_dir is probed once via `cmake -P` and cached. *)

let default_parse_py = "tool/cmake_text/cmake_to_json.py"
let parse_py = ref default_parse_py
let set_parse_py p = parse_py := p

(* Probe cmake for ${CMAKE_ROOT}/Modules. The same probe
   test_corpus.sh uses to find the stdlib-functions directory
   for Bar #3-lite's cmake-stdlib-name index. *)
let probe_cmake_modules_dir () : string option =
  let cmd =
    "printf 'message(\"${CMAKE_ROOT}\")\\n' | cmake -P /dev/stdin 2>&1 | tail -1"
  in
  let ic = Unix.open_process_in cmd in
  let line = try Some (Stdlib.input_line ic) with End_of_file -> None in
  let _ = Unix.close_process_in ic in
  match line with
  | Some root when not (String.is_empty root)
                && Stdlib.Sys.file_exists (root ^ "/Modules") ->
    Some (root ^ "/Modules")
  | _ ->
    (* Fallback to a known location for cmake 4.3 on this host. *)
    if Stdlib.Sys.file_exists "/usr/share/cmake-4.3/Modules"
    then Some "/usr/share/cmake-4.3/Modules"
    else None

let cmake_modules_dir : string option Lazy.t = lazy (probe_cmake_modules_dir ())

(* ============================================================
   Subprocess helpers. *)

let read_all ic =
  let buf = Buffer.create 4096 in
  let chunk = Bytes.create 4096 in
  (try
     while true do
       let n = Stdlib.input ic chunk 0 (Bytes.length chunk) in
       if n = 0 then raise Stdlib.End_of_file
       else Buffer.add_subbytes buf chunk ~pos:0 ~len:n
     done
   with Stdlib.End_of_file -> ());
  Buffer.contents buf

(* ============================================================
   Stage-1 stmt list → yelu_cmake.expr.

   Same shape as the inline version in test_fmt_bridge_smoke.ml.
   For each Stage-1 statement:
   - Cmd c     → parse_cmd c → Some _ → from_emit | None → EUnit
   - Block(if) → ECmakeIfStmt translated recursively
   - Other blocks → EUnit (Day 2/3 work)
   - Raw / Unknown → EUnit *)

(* Convert a raw cmake argument string to a yc expression, applying
   the same ${X} substitution as arg_to_expr in from_emit. Used for
   ECmakeApply's args list (which carries raw strings from parse_cmd
   rather than typed C.arg values). *)
let str_to_yelu_expr s =
  Fe.arg_to_expr (Cp.arg_of_raw s)

(* Helpers for the function/macro/apply construction sites (same
   extensible-variant gotcha as elsewhere — qualify the module). *)
let e_function name params body =
  Yelu_langs.Yelu_cmake_cmake_op.ECmakeFunction { name; params; body }
let e_macro name params body =
  Yelu_langs.Yelu_cmake_cmake_op.ECmakeMacro { name; params; body }
let e_apply name args =
  Yelu_langs.Yelu_cmake_cmake_op.ECmakeApply { name; args }

let rec stmts_to_yelu (stmts : Cp.stmt list) : Yc.expr =
  Yc.ESeq (List.map stmts ~f:stmt_to_yelu)

and stmt_to_yelu (s : Cp.stmt) : Yc.expr =
  match s with
  | Cp.Cmd c ->
    (match Cp.parse_cmd c with
     | Some exp -> Fe.from_emit exp
     | None ->
       (* Unmodeled cmake command OR project-defined function call.
          ECmakeApply's eval looks up env.functions; if not found,
          evaluates args for side effects and returns VUnit (lenient).
          So this single arm covers both user-defined dispatch AND
          unmodeled-builtin tolerance. *)
       let arg_exprs = List.map c.args ~f:str_to_yelu_expr in
       e_apply (Yc.EString c.name) arg_exprs)

  | Cp.Block { block_type = "if"; head; body; clauses; _ } ->
    let cond = Fe.parse_cond_tokens head.args in
    let then_ = stmts_to_yelu body in
    let else_ =
      match List.last clauses with
      | Some (_, body) when not (List.is_empty body) ->
        Some (stmts_to_yelu body)
      | _ -> None
    in
    If_frag.ECmakeIfStmt { cond; then_; else_ }

  | Cp.Block { block_type = "function"; head; body; _ } ->
    (* head.args = [name; param1; param2; ...]. Empty head bails. *)
    (match head.args with
     | name :: params ->
       e_function (Yc.EString name) params (stmts_to_yelu body)
     | [] -> Yc.EUnit)

  | Cp.Block { block_type = "macro"; head; body; _ } ->
    (* Same shape as function. Macro/function scope distinction
       (macro = textual paste, function = isolated scope) is
       collapsed at this slice — ECmakeMacro and ECmakeFunction
       have the same eval semantics today. Difference is captured
       in the IR (is_macro flag in env.functions) for future
       refinement. *)
    (match head.args with
     | name :: params ->
       e_macro (Yc.EString name) params (stmts_to_yelu body)
     | [] -> Yc.EUnit)

  | Cp.Block _ -> Yc.EUnit
  | Cp.Raw _ | Cp.Unknown _ -> Yc.EUnit

(* Parse a cmake file via parse.py → JSON → Stage-1 → yc-expr.

   Returns None on parse failure (file unreadable / parse.py
   produces no output / JSON malformed). Callers decide how to
   handle missing files (include's optional flag, etc.). *)
let parse_file ~path : Yc.expr option =
  let cmd =
    Printf.sprintf "python3 %s %s 2>/dev/null"
      (Stdlib.Filename.quote !parse_py)
      (Stdlib.Filename.quote path)
  in
  let ic = Unix.open_process_in cmd in
  let json_str = read_all ic in
  let _ = Unix.close_process_in ic in
  if String.is_empty json_str then None
  else
    try
      let json = Yojson.Safe.from_string json_str in
      let stmts = Cp.file_of_json json in
      Some (stmts_to_yelu stmts)
    with _ -> None

(* ============================================================
   include() path resolution.

   cmake's search order:
   1. If [file] ends in .cmake, treat as path:
        absolute → use as-is
        relative → resolve against [current_list_dir]
   2. Otherwise (module name): search
        [cmake_module_path] entries, then cmake's built-in
        Modules dir. Append ".cmake" to the bare name. *)

let file_exists_safely p =
  try Stdlib.Sys.file_exists p with _ -> false

let resolve_include
    ~current_list_dir
    ~cmake_module_path
    ~file
  : string option =
  let is_path_form =
    String.contains file '/' || String.is_suffix file ~suffix:".cmake"
  in
  if is_path_form then begin
    if String.is_prefix file ~prefix:"/" then
      if file_exists_safely file then Some file else None
    else
      let combined = Stdlib.Filename.concat current_list_dir file in
      if file_exists_safely combined then Some combined else None
  end else begin
    (* Module name — search MODULE_PATH then built-in Modules. *)
    let candidate_dirs =
      cmake_module_path @
      (match Lazy.force cmake_modules_dir with
       | Some d -> [ d ] | None -> [])
    in
    let basename = file ^ ".cmake" in
    List.find_map candidate_dirs ~f:(fun d ->
      let p = Stdlib.Filename.concat d basename in
      if file_exists_safely p then Some p else None)
  end

(* ============================================================
   The include_loader registered into env.

   Signature matches Yelu_cmake.env's include_loader slot:
     file -> current_list_dir:string -> module_path:string list
       -> Yc.expr option

   The caller (ECmakeInclude eval in yelu_cmake_cmake_op.ml)
   passes the raw file argument from cmake source plus the
   resolution context read from env. We:
   1. resolve_include to find the actual file on disk
   2. parse_file to read + parse + bridge
   None at either step yields None (eval treats as soft-fail
   per the include() optional flag policy). *)

let loader file ~current_list_dir ~module_path : Yc.expr option =
  match resolve_include ~current_list_dir ~cmake_module_path:module_path ~file with
  | None -> None
  | Some path -> parse_file ~path

(* The subdir_loader registered into env. Signature matches
   Yelu_cmake.env's subdir_loader slot: source_dir -> expr option.

   The caller (EAddSubdirectory eval in yelu_cmake_normal_dir.ml)
   passes a directory path already resolved against
   CMAKE_CURRENT_SOURCE_DIR. We append CMakeLists.txt and parse. *)
let subdir_loader source_dir : Yc.expr option =
  let path = Stdlib.Filename.concat source_dir "CMakeLists.txt" in
  if Stdlib.Sys.file_exists path then parse_file ~path else None
