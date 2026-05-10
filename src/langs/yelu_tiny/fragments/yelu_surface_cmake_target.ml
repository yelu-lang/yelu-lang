open Base
open Yelu_tiny
open Yelu_theory_target

let name = "tiny_cmake_target"
let requires = [ "core.string"; "core.path"; "core.bool" ]
let provides =
  [
    "target.add_executable";
    "target.add_library";
    "target.exists";
    "target.sources";
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

(* Phase 2b: target-name fields are now [expr] rather than [string] so that
   ELet bindings can flow through emit-time substitution into target-name
   positions. Eval extracts the string via [eval_string]; emit consults
   the substitution env via the new [target_arg] helper. *)
type expr +=
  | ECmakeAddExecutable of { name : expr; sources : expr list }
  | ECmakeAddLibrary of { name : expr; type_ : string option; sources : expr list }
  | ECmakeTargetSources of { target : expr; visibility : string; sources : expr list }
  | ECmakeTargetLinkLibraries of { target : expr; visibility : string; items : expr list }
  | ECmakeTargetIncludeDirectories of { target : expr; visibility : string; dirs : expr list }
  | ECmakeTargetCompileDefinitions of { target : expr; visibility : string; definitions : expr list }
  | ECmakeTargetCompileOptions of { target : expr; visibility : string; options_ : expr list }
  | ECmakeTargetCompileFeatures of { target : expr; visibility : string; features : expr list }
  | ECmakeTargetLinkOptions of { target : expr; visibility : string; options_ : expr list }
  | ECmakeTargetLinkDirectories of { target : expr; visibility : string; dirs : expr list }
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
  | ECmakeTargetIncludeDirectories { target; visibility; dirs } ->
    let env, target = eval_string ~eval env target in
    let env, dirs = eval_string_list ~eval env dirs in
    Some (add_target_include_dirs env target ~visibility dirs, VUnit)
  | ECmakeTargetCompileDefinitions { target; visibility; definitions } ->
    let env, target = eval_string ~eval env target in
    let env, definitions = eval_string_list ~eval env definitions in
    Some (add_target_compile_definitions env target ~visibility definitions, VUnit)
  | ECmakeTargetCompileOptions { target; visibility; options_ } ->
    let env, target = eval_string ~eval env target in
    let env, options_ = eval_string_list ~eval env options_ in
    Some (add_target_compile_options env target ~visibility options_, VUnit)
  | ECmakeTargetCompileFeatures { target; visibility; features } ->
    let env, target = eval_string ~eval env target in
    let env, features = eval_string_list ~eval env features in
    Some (add_target_compile_features env target ~visibility features, VUnit)
  | ECmakeTargetLinkOptions { target; visibility; options_ } ->
    let env, target = eval_string ~eval env target in
    let env, options_ = eval_string_list ~eval env options_ in
    Some (add_target_link_options env target ~visibility options_, VUnit)
  | ECmakeTargetLinkDirectories { target; visibility; dirs } ->
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
  | _ -> None
