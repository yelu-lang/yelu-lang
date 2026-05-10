open Base
open Yelu_tiny
open Yelu_theory_target

let name = "tiny_cmake_target"
let requires = [ "core.string"; "core.path"; "core.bool" ]
let provides =
  [
    "target.add_executable";
    "target.exists";
    "target.sources";
    "target.link_libraries";
    "target.include_directories";
    "target.compile_definitions";
    "target.compile_options";
    "target.link_options";
    "target.link_directories";
    "target.custom_target";
    "target.custom_command";
  ]

type expr +=
  | ECmakeAddExecutable of { name : string; sources : expr list }
  | ECmakeTargetSources of { target : string; visibility : string; sources : expr list }
  | ECmakeTargetLinkLibraries of { target : string; visibility : string; items : expr list }
  | ECmakeTargetIncludeDirectories of { target : string; visibility : string; dirs : expr list }
  | ECmakeTargetCompileDefinitions of { target : string; visibility : string; definitions : expr list }
  | ECmakeTargetCompileOptions of { target : string; visibility : string; options_ : expr list }
  | ECmakeTargetLinkOptions of { target : string; visibility : string; options_ : expr list }
  | ECmakeTargetLinkDirectories of { target : string; visibility : string; dirs : expr list }
  | ECmakeAddCustomTarget of {
      name : string;
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
  | ECmakeTargetExists of string

let eval_case ~eval env = function
  | ECmakeAddExecutable { name; sources } ->
    let env, _sources = eval_string_list ~eval env sources in
    Some (declare_target env name, VUnit)
  | ECmakeTargetSources { target; visibility; sources } ->
    let env, sources = eval_string_list ~eval env sources in
    Some (add_target_sources env target ~visibility sources, VUnit)
  | ECmakeTargetLinkLibraries { target; visibility; items } ->
    let env, items = eval_string_list ~eval env items in
    Some (add_target_links env target ~visibility items, VUnit)
  | ECmakeTargetIncludeDirectories { target; visibility; dirs } ->
    let env, dirs = eval_string_list ~eval env dirs in
    Some (add_target_include_dirs env target ~visibility dirs, VUnit)
  | ECmakeTargetCompileDefinitions { target; visibility; definitions } ->
    let env, definitions = eval_string_list ~eval env definitions in
    Some (add_target_compile_definitions env target ~visibility definitions, VUnit)
  | ECmakeTargetCompileOptions { target; visibility; options_ } ->
    let env, options_ = eval_string_list ~eval env options_ in
    Some (add_target_compile_options env target ~visibility options_, VUnit)
  | ECmakeTargetLinkOptions { target; visibility; options_ } ->
    let env, options_ = eval_string_list ~eval env options_ in
    Some (add_target_link_options env target ~visibility options_, VUnit)
  | ECmakeTargetLinkDirectories { target; visibility; dirs } ->
    let env, dirs = eval_string_list ~eval env dirs in
    Some (add_target_link_directories env target ~visibility dirs, VUnit)
  | ECmakeAddCustomTarget { name; all; commands; depends; comment } ->
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
  | ECmakeTargetExists name ->
    Some (env, VBool (target_exists env name))
  | _ -> None
