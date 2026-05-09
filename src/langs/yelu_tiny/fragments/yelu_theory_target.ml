open Base
open Yelu_tiny

type expr +=
  | ETarget of string
  | EExecutable of { name : expr; sources : expr list }
  | ETargetExists of expr
  | ETargetAddSources of { target : expr; visibility : string; sources : expr list }
  | ETargetLinkLibraries of { target : expr; visibility : string; items : expr list }
  | ETargetIncludeDirectories of { target : expr; visibility : string; dirs : expr list }

let eval_string ~eval env expr =
  let env, value = eval env expr in
  env, expect_string value

let declare_target env name =
  match find_target env name with
  | Some _ -> env
  | None -> set_target env (empty_target name)

let target_exists env name =
  Option.is_some (find_target env name)

let target_sources env name =
  match find_target env name with
  | None -> []
  | Some target -> target.sources

let add_target_sources env name ~visibility sources =
  if not (target_exists env name) then fail "unknown target %S" name;
  update_target env name ~f:(fun target ->
    {
      target with
      sources =
        target.sources
        @ List.map sources ~f:(fun source -> { visibility; source });
    })

let target_links env name =
  match find_target env name with
  | None -> []
  | Some target -> target.link_libraries

let add_target_links env name ~visibility items =
  if not (target_exists env name) then fail "unknown target %S" name;
  update_target env name ~f:(fun target ->
    {
      target with
      link_libraries =
        target.link_libraries
        @ List.map items ~f:(fun item -> { visibility; item });
    })

let target_include_dirs env name =
  match find_target env name with
  | None -> []
  | Some target -> target.include_directories

let add_target_include_dirs env name ~visibility dirs =
  if not (target_exists env name) then fail "unknown target %S" name;
  update_target env name ~f:(fun target ->
    {
      target with
      include_directories =
        target.include_directories
        @ List.map dirs ~f:(fun dir -> { visibility; dir });
    })

let eval_case ~eval env = function
  | ETarget name -> Some (env, VTarget name)
  | EExecutable { name; sources } ->
    let env, name = eval_string ~eval env name in
    let env, _sources =
      List.fold sources ~init:(env, []) ~f:(fun (env, sources) source ->
        let env, source = eval_string ~eval env source in
        env, source :: sources)
    in
    Some (declare_target env name, VTarget name)
  | ETargetExists target ->
    let env, target = eval env target in
    Some (env, VBool (target_exists env (expect_target target)))
  | ETargetAddSources { target; visibility; sources } ->
    let env, target = eval env target in
    let target = expect_target target in
    let env, sources =
      List.fold sources ~init:(env, []) ~f:(fun (env, sources) source ->
        let env, source = eval_string ~eval env source in
        env, source :: sources)
    in
    Some (add_target_sources env target ~visibility (List.rev sources), VTarget target)
  | ETargetLinkLibraries { target; visibility; items } ->
    let env, target = eval env target in
    let target = expect_target target in
    let env, items =
      List.fold items ~init:(env, []) ~f:(fun (env, items) item ->
        let env, item = eval_string ~eval env item in
        env, item :: items)
    in
    Some (add_target_links env target ~visibility (List.rev items), VTarget target)
  | ETargetIncludeDirectories { target; visibility; dirs } ->
    let env, target = eval env target in
    let target = expect_target target in
    let env, dirs =
      List.fold dirs ~init:(env, []) ~f:(fun (env, dirs) dir ->
        let env, dir = eval_string ~eval env dir in
        env, dir :: dirs)
    in
    Some (add_target_include_dirs env target ~visibility (List.rev dirs), VTarget target)
  | _ -> None
