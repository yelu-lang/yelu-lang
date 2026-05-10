open Base

type expr = ..

type target_source = {
  visibility : string;
  source : string;
}
[@@deriving equal, sexp_of]

type target_link = {
  visibility : string;
  item : string;
}
[@@deriving equal, sexp_of]

type target_include_dir = {
  visibility : string;
  dir : string;
}
[@@deriving equal, sexp_of]

type target_compile_definition = {
  visibility : string;
  definition : string;
}
[@@deriving equal, sexp_of]

type target_compile_option = {
  visibility : string;
  option_ : string;
}
[@@deriving equal, sexp_of]

type target_compile_feature = {
  visibility : string;
  feature : string;
}
[@@deriving equal, sexp_of]

type target_link_option = {
  visibility : string;
  link_option : string;
}
[@@deriving equal, sexp_of]

type target_link_directory = {
  visibility : string;
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

type install_rule =
  | InstallTargets of {
      targets : string list;
      destination : string;
      export : string option;
    }
  | InstallFiles of {
      files : string list;
      destination : string;
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
type env = {
  (* Configure-time: script state. *)
  vars : value Map.M(String).t;
  files : string Map.M(String).t;

  (* Configure-time: declarations / diagnostics. *)
  project : project_info option;
  cmake_min_version : string option;
  messages : log_entry list;
  subdirectories : string list;
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
}

let empty_env : env =
  {
    (* Configure-time: script state. *)
    vars = Map.empty (module String);
    files = Map.empty (module String);

    (* Configure-time: declarations / diagnostics. *)
    project = None;
    cmake_min_version = None;
    messages = [];
    subdirectories = [];
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
  }

let equal_env left right =
  (* Configure-time: script state. *)
  Map.equal equal_value left.vars right.vars
  && Map.equal String.equal left.files right.files
  (* Configure-time: declarations / diagnostics. *)
  && Option.equal equal_project_info left.project right.project
  && Option.equal String.equal left.cmake_min_version right.cmake_min_version
  && List.equal equal_log_entry left.messages right.messages
  && List.equal String.equal left.subdirectories right.subdirectories
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

let find_var env name = Map.find env.vars name

let set_var env ~key ~data =
  { env with vars = Map.set env.vars ~key ~data }

let remove_var env name =
  { env with vars = Map.remove env.vars name }

let var_defined env name =
  Map.mem env.vars name

let find_file env path = Map.find env.files path

let set_file env ~path ~content =
  { env with files = Map.set env.files ~key:path ~data:content }

let file_exists env path =
  Map.mem env.files path

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

exception Eval_error of string

let fail fmt = Fmt.kstr (fun msg -> raise (Eval_error msg)) fmt

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
  | EInt of int
  | EUnit
  | ESetVar of string * expr
  | ESeq of expr list
  (* Compile-time, lexically-scoped, immutable name binding (option A:
     canonical let-expression). [body] is the binding's scope; once it's
     evaluated the binding is gone. Distinct from ESetVar, which models
     cmake's global/mutable [set()] and persists across the program. *)
  | ELet of { var : string; value : expr; body : expr }
