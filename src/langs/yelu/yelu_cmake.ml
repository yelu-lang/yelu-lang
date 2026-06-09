open Base

(* Visibility keyword for target commands. *)
type visibility =
  | Vis_public
  | Vis_private
  | Vis_interface
[@@deriving equal, sexp_of]

let string_of_visibility = function
  | Vis_public -> "PUBLIC"
  | Vis_private -> "PRIVATE"
  | Vis_interface -> "INTERFACE"

let visibility_of_string = function
  | "PUBLIC" -> Vis_public
  | "PRIVATE" -> Vis_private
  | "INTERFACE" -> Vis_interface
  | _ -> Vis_private

type expr = ..

type target_source = {
  visibility : visibility;
  source : string;
}
[@@deriving equal, sexp_of]

type target_link = {
  visibility : visibility;
  item : string;
}
[@@deriving equal, sexp_of]

type target_include_dir = {
  visibility : visibility;
  dir : string;
}
[@@deriving equal, sexp_of]

type target_compile_definition = {
  visibility : visibility;
  definition : string;
}
[@@deriving equal, sexp_of]

type target_compile_option = {
  visibility : visibility;
  option_ : string;
}
[@@deriving equal, sexp_of]

type target_compile_feature = {
  visibility : visibility;
  feature : string;
}
[@@deriving equal, sexp_of]

type target_link_option = {
  visibility : visibility;
  link_option : string;
}
[@@deriving equal, sexp_of]

type target_link_directory = {
  visibility : visibility;
  link_directory : string;
}
[@@deriving equal, sexp_of]

type target_kind =
  | TargetUnknown
  | TargetExecutable
  | TargetLibrary of string option
[@@deriving equal, sexp_of]

type target = {
  name : string;
  kind : target_kind;
  sources : target_source list;
  link_libraries : target_link list;
  include_directories : target_include_dir list;
  compile_definitions : target_compile_definition list;
  compile_options : target_compile_option list;
  compile_features : target_compile_feature list;
  link_options : target_link_option list;
  link_directories : target_link_directory list;
}
[@@deriving equal, sexp_of]

type build_command = {
  command : string;
  args : string list;
}
[@@deriving equal, sexp_of]

type custom_target = {
  name : string;
  all : bool;
  commands : build_command list;
  depends : string list;
  comment : string option;
  sources : string list;
}
[@@deriving equal, sexp_of]

type custom_command = {
  outputs : string list;
  commands : build_command list;
  depends : string list;
  comment : string option;
  verbatim : bool;
}
[@@deriving equal, sexp_of]

(* File-set group for [target_sources(... FILE_SET <name> TYPE HEADERS BASE_DIRS ... FILES ...)].
   Lives in the shared core so theory- and surface-target fragments can both
   carry the same [target_sources_fs] item shape without each one needing
   to depend on the other. *)
type tiny_file_set = {
  kind : string;
  type_ : string;
  base_dirs : expr list;
  files : expr list;
}

and tiny_target_sources_item =
  | Tsi_plain of { visibility : visibility; items : expr list }
  | Tsi_file_set of tiny_file_set

type install_rule =
  | InstallTargets of {
      targets : string list;
      destination : string option;
      component : string option;
      export : string option;
      artifact_clauses : (string * string) list;
    }
  | InstallFiles of {
      files : string list;
      destination : string;
      component : string option;
    }
  (* [install(EXPORT name FILE file DESTINATION dest NAMESPACE ns)] —
     emit-time install rule that writes out an export set declared via
     [Yinstall_targets ~export]. *)
  | InstallExport of {
      export : string;
      destination : string;
      file : string option;
      namespace : string option;
      component : string option;
    }
  | InstallDirectory of {
      directory : string;
      destination : string;
      component : string option;
      optional : bool;
    }
  (* [export(EXPORT name FILE file)] — eager export of the in-tree
     targets to a file usable by sibling projects. Stored alongside
     install rules because cmake treats them as the same family of
     packaging artefacts. *)
  | ExportExport of {
      name : string;
      file : string option;
    }
  (* [configure_package_config_file(INPUT OUTPUT INSTALL_DESTINATION ...)]
     from CMakePackageConfigHelpers. Runs as part of the package-config
     emit slice; recorded eagerly so the env can be inspected later. *)
  | ConfigurePackageConfigFile of {
      install_dest : string;
      input : string;
      output : string;
      no_set_and_check_macro : bool;
      no_check_required_components_macro : bool;
    }
  (* [write_basic_package_version_file(file VERSION v COMPATIBILITY c)]
     from CMakePackageConfigHelpers. *)
  | WriteBasicPackageVersionFile of {
      file : string;
      version : string option;
      compatibility : string;
      arch_independent : bool;
    }
[@@deriving equal, sexp_of]

type project_info = {
  name : string;
  languages : string list;
  version : string option;
}
[@@deriving equal, sexp_of]

type log_entry = {
  mode : string;
  texts : string list;
}
[@@deriving equal, sexp_of]

type test_decl = {
  name : string;
  command : string;
  args : string list;
}
[@@deriving equal, sexp_of]

type find_package_decl = {
  package_name : string;
  required : bool;
}
[@@deriving equal, sexp_of]

type try_compile_decl = {
  result_var : string;
  sources : string list;
}
[@@deriving equal, sexp_of]

(* A function declaration: formal parameter names plus the body to
   re-evaluate at each call site. Body is an [expr] and the extensible
   sum can't derive equality automatically, so [equal_function_decl]
   and [sexp_of_function_decl] are defined manually below (polymorphic
   equal on the body is acceptable for test fixture comparison). *)
type function_decl = {
  params : string list;
  body : expr;
  (* True for [macro()], false for [function()]. Macros are textual:
     they execute in the caller's frame, with param + ARGN / ARGV /
     ARGC / ARGVn temporarily bound in the caller's locals and
     restored on exit. Functions push their own frame. See R4-b.4 and
     doc/cmake/scope_and_control_flow.md macro section. *)
  is_macro : bool;
}

let equal_function_decl (a : function_decl) (b : function_decl) =
  List.equal String.equal a.params b.params
  && Poly.equal a.body b.body
  && Bool.equal a.is_macro b.is_macro

let sexp_of_function_decl (d : function_decl) =
  Sexp.List
    [ Sexp.List (List.map d.params ~f:(fun s -> Sexp.Atom s))
    ; Sexp.Atom (if d.is_macro then "<macro-body>" else "<body>")
    ]

type value =
  | VString of string
  | VBool of bool
  | VInt of int
  | VList of value list
  | VTarget of string
  | VUnit
[@@deriving equal, sexp_of]

(* The interpreter [env] mixes state that conceptually belongs to different
   cmake phases. Today we keep it flat for evaluation simplicity; the
   comment groups below mark the intended phase so a future refactor can
   move each field next to its own theory module (and possibly into
   phase-distinguished records).

   - **Configure-time script state.** Read/written while the cmake script
     itself executes. Includes the [vars] store (which doubles as the
     home for [ELet] lexical bindings via save/restore — a known
     conflation; a future split could give let bindings their own
     namespace separate from cmake's mutable [set()] variables).
   - **Configure-time declarations.** Records of what the script said,
     used as oracle state to verify behavior, not consumed by cmake the
     tool. [messages] / [find_packages] / [try_compiles] /
     [subdirectories] / [project] / [cmake_min_version] sit here.
   - **Build-time graph.** Declared at configure-time but materialized
     when the build runs. The [targets] / [custom_targets] /
     [custom_commands] / [tests] / [target_properties] live here.
     [testing_enabled] is a configure-time switch that gates whether
     [tests] become observable.
   - **Install-time rules.** Recorded at configure-time; executed only
     when [cmake --install] runs. [install_rules] is the lone field. *)
(* Exceptions are defined here so that env-frame helpers below can raise
   them. [Eval_error] is for hard failures; [Break_loop] / [Continue_loop]
   / [Return_function] carry control flow that the surrounding construct
   catches. *)
exception Eval_error of string

exception Break_loop
exception Continue_loop

let fail fmt = Fmt.kstr (fun msg -> raise (Eval_error msg)) fmt

(* Variable scope frame. cmake's block() and function() both push a
   frame; reads consult [locals] then [parent_snapshot]; PARENT_SCOPE
   writes land in the next frame down's [locals]; PROPAGATE merges
   selected [locals] entries into the parent on frame exit. The
   snapshot is taken once at push-time and never updated mid-frame —
   this is the cmake quirk that probes P15/P20/P21 verified. See
   doc/cmake/scope_and_control_flow.md for the full model. *)
type frame = {
  locals : value Map.M(String).t;
  parent_snapshot : value Map.M(String).t;
  (* Names touched (set or unset) inside this frame, distinguishing
     "never touched" from "explicitly unset". block(PROPAGATE x) uses
     this to decide:
       touched + present in locals → write value to parent
       touched + absent from locals → unset x in parent (P4)
       not touched                 → leave parent alone (P3) *)
  touched : Set.M(String).t;
}

let empty_frame = {
  locals = Map.empty (module String);
  parent_snapshot = Map.empty (module String);
  touched = Set.empty (module String);
}

type env = {
  (* Configure-time: script state. *)
  frames : frame list;  (* head is current frame; root frame at tail *)
  (* Cache namespace — global to the configure run, lives OUTSIDE the
     frame stack because cmake's cache is shared across all
     add_subdirectory / function() / block() scopes. Populated by:
       - [-DFOO=Bar] cmd-line input (via [?cmd_line] on eval entry)
       - set(FOO ... CACHE ...) when FOO is not yet in cache
       - option(FOO ... ON|OFF) when FOO is not yet in cache
     Read by [find_var]'s fallback (normal vars win; cache fills in).
     See doc/cmake/cache_semantics.md for the full decision tree and
     doc/yelu_cmake/cache_plan.md for the design of this slice. *)
  cache_vars : value Map.M(String).t;
  files : string Map.M(String).t;
  functions : function_decl Map.M(String).t;

  (* Configure-time: declarations / diagnostics. *)
  project : project_info option;
  cmake_min_version : string option;
  messages : log_entry list;
  subdirectories : string list;
  includes : string list;
  find_packages : find_package_decl list;
  try_compiles : try_compile_decl list;

  (* Build-time: target graph + test graph. *)
  targets : target Map.M(String).t;
  custom_targets : custom_target Map.M(String).t;
  custom_commands : custom_command Map.M(String).t;
  target_properties : string Map.M(String).t Map.M(String).t;
  testing_enabled : bool;
  tests : test_decl list;

  (* Install-time: deferred actions. *)
  install_rules : install_rule list;

  (* I/O callback for include() / find_package / etc. The library
     itself does NO filesystem I/O (the [yelu_langs] module never
     spawns subprocesses or reads files). The caller (runner /
     tests) registers a loader that takes the raw file argument
     from cmake source + the resolution context, and returns
     either the loaded module's expression or None.

     Loader signature:
       file ~current_list_dir ~module_path -> expr option
     where:
       file: raw arg from include(<file>), e.g. "GNUInstallDirs"
             or "cmake/Helpers.cmake".
       current_list_dir: value of CMAKE_CURRENT_LIST_DIR at the
             include call site (for resolving relative paths).
       module_path: list of dirs from CMAKE_MODULE_PATH (for
             resolving bare module names).

     If None registered, ECmakeInclude falls back to bookkeeping-
     only mode (pre-2026-06-02 behavior). Excluded from equal_env
     (functions can't be compared). *)
  include_loader :
    (string -> current_list_dir:string -> module_path:string list ->
     expr option) option;

  (* Cycle protection: paths currently being processed by an
     include() chain. If a path is already on this stack, the
     include is a no-op. Prevents infinite recursion on
     accidental A→B→A circular includes. *)
  include_stack : string list;

  (* add_subdirectory(): given the source_dir (resolved against
     CMAKE_CURRENT_SOURCE_DIR by the caller), return the parsed
     CMakeLists.txt in that directory as a yc expr. None = no loader
     registered, EAddSubdirectory eval falls back to bookkeeping-only
     (records the path in env.subdirectories without recursing). *)
  subdir_loader : (string -> expr option) option;
}

let empty_env : env =
  {
    (* Configure-time: script state. *)
    frames = [ empty_frame ];   (* root frame always present *)
    cache_vars = Map.empty (module String);
    files = Map.empty (module String);
    functions = Map.empty (module String);

    (* Configure-time: declarations / diagnostics. *)
    project = None;
    cmake_min_version = None;
    messages = [];
    subdirectories = [];
    includes = [];
    find_packages = [];
    try_compiles = [];

    (* Build-time: target graph + test graph. *)
    targets = Map.empty (module String);
    custom_targets = Map.empty (module String);
    custom_commands = Map.empty (module String);
    target_properties = Map.empty (module String);
    testing_enabled = false;
    tests = [];

    (* Install-time: deferred actions. *)
    install_rules = [];

    (* I/O callback — see env type comment. None = no loader,
       ECmakeInclude falls back to bookkeeping-only. *)
    include_loader = None;
    include_stack = [];
    subdir_loader = None;
  }

let equal_frame a b =
  (* [touched] is intentionally excluded: it's implementation state for
     PROPAGATE bookkeeping, not part of the observable env. Comparing it
     would make tests brittle (e.g. a set-then-unset would not match a
     never-set, even though the resulting variable view is identical). *)
  Map.equal equal_value a.locals b.locals
  && Map.equal equal_value a.parent_snapshot b.parent_snapshot

let equal_env left right =
  (* Configure-time: script state. *)
  List.equal equal_frame left.frames right.frames
  && Map.equal equal_value left.cache_vars right.cache_vars
  && Map.equal String.equal left.files right.files
  && Map.equal equal_function_decl left.functions right.functions
  (* Configure-time: declarations / diagnostics. *)
  && Option.equal equal_project_info left.project right.project
  && Option.equal String.equal left.cmake_min_version right.cmake_min_version
  && List.equal equal_log_entry left.messages right.messages
  && List.equal String.equal left.subdirectories right.subdirectories
  && List.equal String.equal left.includes right.includes
  && List.equal equal_find_package_decl left.find_packages right.find_packages
  && List.equal equal_try_compile_decl left.try_compiles right.try_compiles
  (* Build-time: target graph + test graph. *)
  && Map.equal equal_target left.targets right.targets
  && Map.equal equal_custom_target left.custom_targets right.custom_targets
  && Map.equal equal_custom_command left.custom_commands right.custom_commands
  && Map.equal (Map.equal String.equal) left.target_properties right.target_properties
  && Bool.equal left.testing_enabled right.testing_enabled
  && List.equal equal_test_decl left.tests right.tests
  (* Install-time: deferred actions. *)
  && List.equal equal_install_rule left.install_rules right.install_rules

let empty_target ?(kind = TargetUnknown) name =
  {
    name;
    kind;
    sources = [];
    link_libraries = [];
    include_directories = [];
    compile_definitions = [];
    compile_options = [];
    compile_features = [];
    link_options = [];
    link_directories = [];
  }

(* Frame helpers. The frames list is non-empty (the root frame is always
   present, created by empty_env). [top_frame], [with_top_frame], and
   [update_top_frame] capture the common pattern of operating on the
   current frame. *)

let top_frame env =
  match env.frames with
  | f :: _ -> f
  | [] ->
    failwith "yelu_cmake: env.frames is empty (invariant violation)"

let with_top_frame env f =
  match env.frames with
  | top :: rest -> { env with frames = f top :: rest }
  | [] -> failwith "yelu_cmake: env.frames is empty (invariant violation)"

(* Read: consult [locals] first, fall through to [parent_snapshot],
   then fall through to [cache_vars]. The normal-then-cache fallback
   is cmake's [${VAR}] read semantics — see
   doc/cmake/cache_semantics.md § "Read path". Frame snapshot rules
   per the verified cmake semantics (P15 / P20 / P21): the snapshot
   is fixed at frame-push time and never updated by PARENT_SCOPE /
   PROPAGATE writes from inside this frame or its children. *)
let find_var env name =
  let f = top_frame env in
  match Map.find f.locals name with
  | Some _ as v -> v
  | None ->
    (match Map.find f.parent_snapshot name with
     | Some _ as v -> v
     | None -> Map.find env.cache_vars name)

let set_var env ~key ~data =
  with_top_frame env (fun f ->
    { f with
      locals = Map.set f.locals ~key ~data;
      touched = Set.add f.touched key })

let remove_var env name =
  with_top_frame env (fun f ->
    { f with
      locals = Map.remove f.locals name;
      touched = Set.add f.touched name })

(* ============================================================
   Cmake string interpolation — ${X} substitution.

   The single source of truth for ${...} substitution in
   yelu_langs. Used everywhere a string slot is consumed at
   eval time (ECmakeSetCache.name, EString eval, etc.).

   Handles:
   - ${X}  → find_var env X, stringified; "" if unbound
            (cmake silent-deref semantics)
   - Nested ${${prefix}_X}: inner-first, single recursive pass
   - Mid-string: "prefix${X}suffix" → "prefix<val>suffix"
   - Multiple refs: "${A}-${B}" → "<A>-<B>"
   - Balanced braces inside: tracks nesting via depth counter

   NOT handled (deferred — different scopes / phases):
   - @X@  → configure_file substitution (different command set)
   - $ENV{X} → process env read (needs I/O callback)
   - $CACHE{X} → explicit cache lookup
                 (implicit via find_var's normal→cache fallback)
   - $<...> → generator expressions (generate-time, not configure)
   - \${X} → escape (cmake's escaping is rare in practice)
   See doc/cmake/cache_var_namespacing.md § 7 for the deferred
   set. Each surfaces in the matrix smoke as a diff when it
   bites; closing them happens then.

   Before this function existed, ${X} was handled inconsistently
   in 5 different parse-time places (arg_to_expr in from_emit,
   Var_exp arm, cond_token_to_expr, an inline ECmakeSetCache name
   hack, and the cmd_line entry channel). This function
   consolidates the eval-time mechanism; the parse-time places
   stay (they're correct for whole-arg shapes) but no longer
   need to handle nested / mid-string cases. *)

(* Stringify a value for substitution into a cmake-shaped string.
   Matches cmake's behavior: ON/OFF for bools, decimal for ints,
   string as-is for strings, ; for lists. *)
let value_to_cmake_string = function
  | VString s -> s
  | VBool true -> "ON"
  | VBool false -> "OFF"
  | VInt n -> Int.to_string n
  | VUnit -> ""
  | VList _ | VTarget _ -> ""  (* lists shouldn't reach here directly *)

let rec substitute env s =
  let n = String.length s in
  let buf = Buffer.create n in
  (* Find the matching '}' for the '{' at position p+1 (we're
     called when s.[p] = '$' and s.[p+1] = '{'). Returns the
     position of the matching '}'. Tracks ${...} nesting via
     depth so inner ${...} count as one unit. None on
     unbalanced (treated as literal). *)
  let find_match p =
    let rec loop i depth =
      if i >= n then None
      else if Char.equal s.[i] '}' then
        if depth = 0 then Some i else loop (i + 1) (depth - 1)
      else if i + 1 < n
           && Char.equal s.[i] '$' && Char.equal s.[i + 1] '{'
      then loop (i + 2) (depth + 1)
      else loop (i + 1) depth
    in
    loop p 0
  in
  let rec scan i =
    if i >= n then ()
    else if i + 1 < n
         && Char.equal s.[i] '$' && Char.equal s.[i + 1] '{' then
      (match find_match (i + 2) with
       | None ->
         Buffer.add_char buf s.[i];
         scan (i + 1)
       | Some close ->
         let raw = String.sub s ~pos:(i + 2) ~len:(close - i - 2) in
         (* Nested ${...} inside the name slot: recursively
            substitute that first, then look up the resolved name. *)
         let name = if String.is_substring raw ~substring:"${"
                    then substitute env raw
                    else raw
         in
         let value = match find_var env name with
           | Some v -> value_to_cmake_string v
           | None -> ""
         in
         Buffer.add_string buf value;
         scan (close + 1))
    else begin
      Buffer.add_char buf s.[i];
      scan (i + 1)
    end
  in
  scan 0;
  Buffer.contents buf

let var_defined env name =
  let f = top_frame env in
  Map.mem f.locals name
  || Map.mem f.parent_snapshot name
  || Map.mem env.cache_vars name

(* Cache namespace helpers. Cache is global to the configure run — no
   frame-scoping. See doc/cmake/cache_semantics.md § "Write path"
   for the first-write-wins / dual-write / -D-interaction rules
   that [ECmakeSetCache] and [ECmakeOption] implement on top of
   these primitives. *)

let find_cache_var env name =
  Map.find env.cache_vars name

let cache_var_defined env name =
  Map.mem env.cache_vars name

let set_cache_var env ~key ~data =
  { env with cache_vars = Map.set env.cache_vars ~key ~data }

let remove_cache_var env name =
  { env with cache_vars = Map.remove env.cache_vars name }

(* unset(VAR CACHE) clears BOTH namespaces — cache_semantics.md row 3.3. *)
let unset_var_both env name =
  let env = remove_var env name in
  remove_cache_var env name

(* Populate cache from -D-style cmd-line bindings. Values are always
   stored as VString (cmake's cmd line is string-typed; bool/int
   reinterpretation happens at read time via the existing truthy /
   numeric coercion helpers). Used by eval entry points to seed
   [cache_vars] before walking the program — see
   doc/cmake/cache_semantics.md § "Set 4: -D command-line". *)
let populate_cmd_line env bindings =
  List.fold bindings ~init:env ~f:(fun env (name, value) ->
    set_cache_var env ~key:name ~data:(VString value))

(* PARENT_SCOPE write: lands in the next frame down's locals. Tiny
   raises a dedicated [Eval_error] at the root frame (cmake silently
   no-ops; tiny choses strictness to surface accidental top-level use,
   with a message that flags the divergence). *)
let set_var_parent_scope env ~key ~data =
  match env.frames with
  | _ :: parent :: rest ->
    let parent =
      { parent with
        locals = Map.set parent.locals ~key ~data;
        touched = Set.add parent.touched key }
    in
    { env with frames = List.hd_exn env.frames :: parent :: rest }
  | _ ->
    fail "tiny: PARENT_SCOPE at root frame (has no parent); this is a \
          tiny-only diagnostic (cmake silently no-ops)"

(* Push a new frame for block() / function(). The new frame's
   [parent_snapshot] is a merged copy of the parent's locals + its own
   snapshot — equivalent to flattening the inherited view at push time.
   Reads inside the child won't chain-walk; they consult their own
   snapshot only. *)
let push_frame env =
  let parent = top_frame env in
  let merged =
    Map.merge parent.locals parent.parent_snapshot ~f:(fun ~key:_ v ->
      match v with
      | `Left x | `Both (x, _) -> Some x
      | `Right x -> Some x)
  in
  let child =
    { locals = Map.empty (module String);
      parent_snapshot = merged;
      touched = Set.empty (module String) }
  in
  { env with frames = child :: env.frames }

(* Pop the current frame, optionally propagating named locals to the
   parent. For each name in [propagate]: if present in current frame's
   locals, write that value to parent's locals; if absent (which means
   the frame either never touched it or it was unset), remove the name
   from parent's locals to mirror block(PROPAGATE x) + unset(x) (P4). *)
let pop_frame ?(propagate = []) env =
  match env.frames with
  | top :: parent :: rest ->
    let parent =
      List.fold propagate ~init:parent ~f:(fun parent name ->
        if Set.mem top.touched name then
          (* Frame touched this name. Present in locals = lift the value;
             absent = explicit unset, so unset in parent. *)
          match Map.find top.locals name with
          | Some v ->
            { parent with
              locals = Map.set parent.locals ~key:name ~data:v;
              touched = Set.add parent.touched name }
          | None ->
            { parent with
              locals = Map.remove parent.locals name;
              touched = Set.add parent.touched name }
        else
          (* Untouched: leave parent alone (P3). *)
          parent)
    in
    { env with frames = parent :: rest }
  | _ ->
    failwith "yelu_cmake: pop_frame on root frame (invariant violation)"

(* [Return_function] is the control-flow exception raised by
   [ECmakeReturn]. Carries:
   - [env_at_return]: the env at the moment of return, so side effects
     performed inside the function body (messages, install rules,
     target writes, …) survive the unwind.
   - [propagated]: the values of each PROPAGATE-named var, captured
     at the return site (which may be inside several nested blocks).
     [None] means the var was not bound at the return site, which the
     catch turns into an unset in the caller. *)
exception Return_function of {
  env_at_return : env;
  propagated : (string * value option) list;
}

let find_file env path = Map.find env.files path

let set_file env ~path ~content =
  { env with files = Map.set env.files ~key:path ~data:content }

let file_exists env path =
  Map.mem env.files path

let find_function env name = Map.find env.functions name

let set_function env name decl =
  { env with functions = Map.set env.functions ~key:name ~data:decl }

let find_target env name = Map.find env.targets name

let set_target env (target : target) =
  { env with targets = Map.set env.targets ~key:target.name ~data:target }

let update_target env name ~f =
  match find_target env name with
  | None -> failwith ("unknown target " ^ name)
  | Some target -> set_target env (f target)

let find_custom_target env name = Map.find env.custom_targets name

let set_custom_target env (custom_target : custom_target) =
  {
    env with
    custom_targets =
      Map.set env.custom_targets ~key:custom_target.name ~data:custom_target;
  }

let find_custom_command env primary_output =
  Map.find env.custom_commands primary_output

let set_custom_command env (custom_command : custom_command) =
  match custom_command.outputs with
  | [] -> fail "add_custom_command requires at least one OUTPUT"
  | primary :: _ ->
    {
      env with
      custom_commands =
        Map.set env.custom_commands ~key:primary ~data:custom_command;
    }

let add_install_rule env rule =
  { env with install_rules = env.install_rules @ [ rule ] }

let set_project env info =
  { env with project = Some info }

let set_cmake_min_version env version =
  { env with cmake_min_version = Some version }

let add_message env mode texts =
  { env with messages = env.messages @ [ { mode; texts } ] }

let add_subdirectory env path =
  { env with subdirectories = env.subdirectories @ [ path ] }

let add_include env file =
  { env with includes = env.includes @ [ file ] }

let enable_testing env =
  { env with testing_enabled = true }

let add_test env decl =
  { env with tests = env.tests @ [ decl ] }

let find_target_property env ~target ~property =
  Option.bind (Map.find env.target_properties target) ~f:(fun m ->
    Map.find m property)

let set_target_property env ~target ~property ~value =
  let inner =
    Option.value (Map.find env.target_properties target)
      ~default:(Map.empty (module String))
  in
  let inner = Map.set inner ~key:property ~data:value in
  { env with
    target_properties = Map.set env.target_properties ~key:target ~data:inner }

let add_find_package env decl =
  { env with find_packages = env.find_packages @ [ decl ] }

let add_try_compile env decl =
  { env with try_compiles = env.try_compiles @ [ decl ] }

let rec string_of_value = function
  | VString s -> s
  | VBool b -> if b then "true" else "false"
  | VInt n -> Int.to_string n
  | VList values ->
    values
    |> List.map ~f:string_of_value
    |> String.concat ~sep:";"
  | VTarget name -> name
  | VUnit -> "()"

(* A target name [VTarget _] coerces to its underlying string when a string
   is expected — they are textually interchangeable in target-name contexts
   (cmake itself sees only a string). *)
let expect_string = function
  | VString s -> s
  | VTarget s -> s
  | v -> fail "expected string, got %s" (Sexp.to_string ([%sexp_of: value] v))

let expect_int = function
  | VInt n -> n
  | v -> fail "expected int, got %s" (Sexp.to_string ([%sexp_of: value] v))

(* Cmake-style truthiness: cmake's if() treats empty string, "OFF",
   "NO", "FALSE", "0", "N", "IGNORE", "NOTFOUND", and suffix "-NOTFOUND"
   as false; non-empty otherwise true. For tiny we keep it lightweight:
   VBool b -> b; VString s with cmake's false-spelling table -> false;
   any non-empty otherwise -> true; VInt 0 -> false; other VInt -> true. *)
let expect_bool = function
  | VBool b -> b
  | VInt 0 -> false
  | VInt _ -> true
  | VString s ->
    let upper = String.uppercase s in
    not (String.is_empty s)
    && not (List.mem [
      "OFF"; "NO"; "FALSE"; "0"; "N"; "IGNORE"; "NOTFOUND" ] upper
        ~equal:String.equal)
    && not (String.is_suffix upper ~suffix:"-NOTFOUND")
  | VTarget _ -> true
  | VList _ -> true
  | _ -> false

let expect_list = function
  | VList values -> values
  | v -> fail "expected list, got %s" (Sexp.to_string ([%sexp_of: value] v))

(* Accept both [VTarget _] (an explicit target value) and [VString _] (a
   target name as a plain string). Phase 2b makes target-name positions
   carry [expr], which means an [EString "app"] reaches eval as
   [VString "app"]; conceptually a target name and a string-of-target-name
   are interchangeable so [expect_target] accepts either. *)
let expect_target = function
  | VTarget name -> name
  | VString name -> name
  | v -> fail "expected target, got %s" (Sexp.to_string ([%sexp_of: value] v))

type expr +=
  | EVar of string
  | EString of string
  | EBool of bool
  | ECmakeRaw of string  (* verbatim cmake text — codegen-only escape *)
  | ECmakeRawCmd of {     (* raw cmake with structured args — parser fallback *)
      name : string;
      args : expr list;
    }
  | EInt of int
  | EUnit
  | ESetVar of string * expr
  | ESeq of expr list
  (* Compile-time, lexically-scoped, immutable name binding (option A:
     canonical let-expression). [body] is the binding's scope; once it's
     evaluated the binding is gone. Distinct from ESetVar, which models
     cmake's global/mutable [set()] and persists across the program. *)
  | ELet of { var : string; value : expr; body : expr }

(* Parse-time cmake bool-literal recognition. Case-insensitive; returns
   [None] on non-bool so the caller decides the fallback. Related to
   [expect_bool] above (eval-time, total). Future (Y17): collapse these
   into one place. *)
let bool_literal_of_string (s : string) : expr option =
  match String.uppercase s with
  | "TRUE" | "ON" | "YES" | "Y" | "1" -> Some (EBool true)
  | "FALSE" | "OFF" | "NO" | "N" | "0" | "IGNORE" | "NOTFOUND" ->
    Some (EBool false)
  | _ -> None
