open Base
open Yelu_cmake
open Yelu_cmake_normal_target

let name = "tiny_cmake_target"
let requires = [ "core.string"; "core.path"; "core.bool" ]
let provides =
  [
    "target.add_executable";
    "target.add_library";
    "target.add_library_alias";
    "target.add_executable_alias";
    "target.add_dependencies";
    "target.exists";
    "target.sources";
    "target.sources_fs";
    "target.precompile_headers";
    "target.link_libraries";
    "target.include_directories";
    "target.compile_definitions";
    "target.compile_options";
    "target.compile_features";
    "target.link_options";
    "target.link_directories";
    "target.custom_target";
    "target.custom_command";
  ]

(* [tiny_file_set] / [tiny_target_sources_item] live in yelu_cmake.ml
   so theory and surface fragments can both reference the same shape
   without one depending on the other. See that file for definitions. *)

(* Phase 2b: target-name fields are now [expr] rather than [string] so that
   ELet bindings can flow through emit-time substitution into target-name
   positions. Eval extracts the string via [eval_string]; emit consults
   the substitution env via the new [target_arg] helper. *)
type expr +=
  | ECmakeAddExecutable of { name : expr; sources : expr list }
  | ECmakeAddLibrary of { name : expr; type_ : string option; sources : expr list }
  | ECmakeTargetSources of { target : expr; visibility : string; sources : expr list }
  | ECmakeTargetLinkLibraries of { target : expr; visibility : string; items : expr list }
  | ECmakeTargetIncludeDirectories of
      { target : expr; visibility : string;
        before : bool; system : bool; dirs : expr list }
  | ECmakeTargetCompileDefinitions of
      { target : expr; visibility : string; definitions : expr list }
  | ECmakeTargetCompileOptions of
      { target : expr; visibility : string; before : bool; options_ : expr list }
  | ECmakeTargetCompileFeatures of
      { target : expr; visibility : string; features : expr list }
  | ECmakeTargetLinkOptions of
      { target : expr; visibility : string; before : bool; options_ : expr list }
  | ECmakeTargetLinkDirectories of
      { target : expr; visibility : string; before : bool; dirs : expr list }
  | ECmakeAddCustomTarget of {
      name : expr;
      all : bool;
      commands : build_command list;
      depends : expr list;
      comment : string option;
    }
  | ECmakeAddCustomCommand of {
      outputs : expr list;
      commands : build_command list;
      depends : expr list;
      comment : string option;
      verbatim : bool;
    }
  | ECmakeTargetExists of expr
  (* [add_library(<name> ALIAS <target>)] and the executable sibling.
     Eval is a target declaration aliasing an existing target name. *)
  | ECmakeAddLibraryAlias of { name : string; target : string }
  | ECmakeAddExecutableAlias of { name : string; target : string }
  (* [add_library(name <lib_type> IMPORTED [GLOBAL])]. Eval declares a
     target with the given type; lib_type is one of STATIC/SHARED/MODULE/
     OBJECT/UNKNOWN/INTERFACE. *)
  | ECmakeAddLibraryImported of {
      name : expr;
      lib_type : string option;
      global : bool;
    }
  (* [add_dependencies(<target> <dep>...)]. Eval is a no-op for now —
     dependency graph tracking lives in env.build but no caller yet
     queries it. *)
  | ECmakeAddDependencies of { target : string; deps : string list }
  (* [target_sources(... FILE_SET ...)] richer form. See tiny_target_sources_item. *)
  | ECmakeTargetSourcesFs of {
      target : expr;
      items : tiny_target_sources_item list;
    }
  (* [target_precompile_headers(<target> <visibility> <headers>)] same
     shape as ECmakeTargetSources. *)
  | ECmakeTargetPrecompileHeaders of {
      target : expr;
      visibility : string;
      headers : expr list;
    }

let eval_case ~eval env = function
  | ECmakeAddExecutable { name; sources } ->
    let env, name = eval_string ~eval env name in
    let env, _sources = eval_string_list ~eval env sources in
    Some (declare_target ~kind:TargetExecutable env name, VUnit)
  | ECmakeAddLibrary { name; type_; sources } ->
    let env, name = eval_string ~eval env name in
    let env, _sources = eval_string_list ~eval env sources in
    Some (declare_target ~kind:(TargetLibrary type_) env name, VUnit)
  | ECmakeTargetSources { target; visibility; sources } ->
    let env, target = eval_string ~eval env target in
    let env, sources = eval_string_list ~eval env sources in
    Some (add_target_sources env target ~visibility sources, VUnit)
  | ECmakeTargetLinkLibraries { target; visibility; items } ->
    let env, target = eval_string ~eval env target in
    let env, items = eval_string_list ~eval env items in
    Some (add_target_links env target ~visibility items, VUnit)
  | ECmakeTargetIncludeDirectories { target; visibility; dirs; _ } ->
    let env, target = eval_string ~eval env target in
    let env, dirs = eval_string_list ~eval env dirs in
    Some (add_target_include_dirs env target ~visibility dirs, VUnit)
  | ECmakeTargetCompileDefinitions { target; visibility; definitions } ->
    let env, target = eval_string ~eval env target in
    let env, definitions = eval_string_list ~eval env definitions in
    Some (add_target_compile_definitions env target ~visibility definitions, VUnit)
  | ECmakeTargetCompileOptions { target; visibility; options_; _ } ->
    let env, target = eval_string ~eval env target in
    let env, options_ = eval_string_list ~eval env options_ in
    Some (add_target_compile_options env target ~visibility options_, VUnit)
  | ECmakeTargetCompileFeatures { target; visibility; features } ->
    let env, target = eval_string ~eval env target in
    let env, features = eval_string_list ~eval env features in
    Some (add_target_compile_features env target ~visibility features, VUnit)
  | ECmakeTargetLinkOptions { target; visibility; options_; _ } ->
    let env, target = eval_string ~eval env target in
    let env, options_ = eval_string_list ~eval env options_ in
    Some (add_target_link_options env target ~visibility options_, VUnit)
  | ECmakeTargetLinkDirectories { target; visibility; dirs; _ } ->
    let env, target = eval_string ~eval env target in
    let env, dirs = eval_string_list ~eval env dirs in
    Some (add_target_link_directories env target ~visibility dirs, VUnit)
  | ECmakeAddCustomTarget { name; all; commands; depends; comment } ->
    let env, name = eval_string ~eval env name in
    let env, depends = eval_string_list ~eval env depends in
    Some
      ( set_custom_target env
          { name; all; commands; depends; comment },
        VUnit )
  | ECmakeAddCustomCommand { outputs; commands; depends; comment; verbatim } ->
    let env, outputs = eval_string_list ~eval env outputs in
    let env, depends = eval_string_list ~eval env depends in
    Some
      ( set_custom_command env
          { outputs; commands; depends; comment; verbatim },
        VUnit )
  | ECmakeTargetExists target ->
    let env, target = eval_string ~eval env target in
    Some (env, VBool (target_exists env target))
  | ECmakeAddLibraryAlias { name; target = _ } ->
    (* The alias is recorded as another target with no sources; the
       linker plumbing is left to cmake. *)
    Some (declare_target ~kind:(TargetLibrary (Some "INTERFACE")) env name, VUnit)
  | ECmakeAddExecutableAlias { name; target = _ } ->
    Some (declare_target ~kind:TargetExecutable env name, VUnit)
  | ECmakeAddLibraryImported { name; lib_type; global = _ } ->
    let env, name = eval_string ~eval env name in
    Some (declare_target ~kind:(TargetLibrary lib_type) env name, VUnit)
  | ECmakeAddDependencies _ ->
    Some (env, VUnit)
  | ECmakeTargetSourcesFs { target; items } ->
    let env, target = eval_string ~eval env target in
    (* Walk each item, evaluating inner exprs for side effects. Only the
       plain-source pieces feed into env.target_sources; file-set
       headers are emit-only at this slice. *)
    let env =
      List.fold items ~init:env ~f:(fun env -> function
        | Tsi_plain { visibility; items } ->
          let env, items = eval_string_list ~eval env items in
          add_target_sources env target ~visibility items
        | Tsi_file_set { base_dirs; files; _ } ->
          let env, _ = eval_string_list ~eval env base_dirs in
          let env, _ = eval_string_list ~eval env files in
          env)
    in
    Some (env, VUnit)
  | ECmakeTargetPrecompileHeaders { target; visibility; headers } ->
    let env, target = eval_string ~eval env target in
    let env, _headers = eval_string_list ~eval env headers in
    Some (add_target_sources env target ~visibility [], VUnit)
  | _ -> None
