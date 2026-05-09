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
    "target.custom_target";
  ]

type expr +=
  | ECmakeAddExecutable of { name : string; sources : expr list }
  | ECmakeTargetSources of { target : string; visibility : string; sources : expr list }
  | ECmakeTargetLinkLibraries of { target : string; visibility : string; items : expr list }
  | ECmakeTargetIncludeDirectories of { target : string; visibility : string; dirs : expr list }
  | ECmakeAddCustomTarget of {
      name : string;
      all : bool;
      commands : build_command list;
      depends : expr list;
      comment : string option;
    }
  | ECmakeTargetExists of string

let eval_string ~eval env expr =
  let env, value = eval env expr in
  env, expect_string value

let eval_case ~eval env = function
  | ECmakeAddExecutable { name; sources } ->
    let env, _sources =
      List.fold sources ~init:(env, []) ~f:(fun (env, sources) source ->
        let env, source = eval_string ~eval env source in
        env, source :: sources)
    in
    Some (declare_target env name, VUnit)
  | ECmakeTargetSources { target; visibility; sources } ->
    let env, sources =
      List.fold sources ~init:(env, []) ~f:(fun (env, sources) source ->
        let env, source = eval_string ~eval env source in
        env, source :: sources)
    in
    Some (add_target_sources env target ~visibility (List.rev sources), VUnit)
  | ECmakeTargetLinkLibraries { target; visibility; items } ->
    let env, items =
      List.fold items ~init:(env, []) ~f:(fun (env, items) item ->
        let env, item = eval_string ~eval env item in
        env, item :: items)
    in
    Some (add_target_links env target ~visibility (List.rev items), VUnit)
  | ECmakeTargetIncludeDirectories { target; visibility; dirs } ->
    let env, dirs =
      List.fold dirs ~init:(env, []) ~f:(fun (env, dirs) dir ->
        let env, dir = eval_string ~eval env dir in
        env, dir :: dirs)
    in
    Some (add_target_include_dirs env target ~visibility (List.rev dirs), VUnit)
  | ECmakeAddCustomTarget { name; all; commands; depends; comment } ->
    let env, depends =
      List.fold depends ~init:(env, []) ~f:(fun (env, depends) depend ->
        let env, depend = eval_string ~eval env depend in
        env, depend :: depends)
    in
    Some
      ( set_custom_target env
          { name; all; commands; depends = List.rev depends; comment },
        VUnit )
  | ECmakeTargetExists name ->
    Some (env, VBool (target_exists env name))
  | _ -> None
