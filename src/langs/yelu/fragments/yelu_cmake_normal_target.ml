open Base
open Yelu_cmake

type expr +=
  | ETarget of string
  | EExecutable of { name : expr; sources : expr list }
  | ELibrary of { name : expr; type_ : string option; sources : expr list }
  | ETargetExists of expr
  | ETargetAddSources of { target : expr; visibility : string; sources : expr list }
  | ETargetLinkLibraries of { target : expr; visibility : string; items : expr list }
  | ETargetIncludeDirectories of { target : expr; visibility : string; dirs : expr list }
  | ETargetCompileDefinitions of { target : expr; visibility : string; definitions : expr list }
  | ETargetCompileOptions of { target : expr; visibility : string; options_ : expr list }
  | ETargetCompileFeatures of { target : expr; visibility : string; features : expr list }
  | ETargetLinkOptions of { target : expr; visibility : string; options_ : expr list }
  | ETargetLinkDirectories of { target : expr; visibility : string; dirs : expr list }
  | ECustomTarget of {
      name : expr;
      all : bool;
      commands : build_command list;
      depends : expr list;
      comment : string option;
    }
  | ECustomCommand of {
      outputs : expr list;
      commands : build_command list;
      depends : expr list;
      comment : string option;
      verbatim : bool;
    }
  | ELibraryAlias of { name : string; target : string }
  | EExecutableAlias of { name : string; target : string }
  | ELibraryImported of {
      name : expr;
      lib_type : string option;
      global : bool;
    }
  | EAddDependencies of { target : string; deps : string list }
  (* See [tiny_target_sources_item] in [yelu_cmake.ml] for shape. *)
  | ETargetSourcesFs of {
      target : expr;
      items : tiny_target_sources_item list;
    }
  | ETargetPrecompileHeaders of {
      target : expr;
      visibility : string;
      headers : expr list;
    }

let eval_string ~eval env expr =
  let env, value = eval env expr in
  env, expect_string value

let eval_string_list ~eval env exprs =
  let env, items =
    List.fold exprs ~init:(env, []) ~f:(fun (env, acc) expr ->
      let env, item = eval_string ~eval env expr in
      env, item :: acc)
  in
  env, List.rev items

let declare_target ?(kind = TargetUnknown) env name =
  match find_target env name with
  | Some _ -> env
  | None -> set_target env (empty_target ~kind name)

let target_exists env name =
  Option.is_some (find_target env name)

let update_existing_target env name ~f =
  if not (target_exists env name) then fail "unknown target %S" name;
  update_target env name ~f

let target_sources env name =
  match find_target env name with
  | None -> []
  | Some target -> target.sources

let add_target_sources env name ~visibility sources =
  update_existing_target env name ~f:(fun target ->
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
  update_existing_target env name ~f:(fun target ->
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
  update_existing_target env name ~f:(fun target ->
    {
      target with
      include_directories =
        target.include_directories
        @ List.map dirs ~f:(fun dir -> { visibility; dir });
    })

let target_compile_definitions env name =
  match find_target env name with
  | None -> []
  | Some target -> target.compile_definitions

let add_target_compile_definitions env name ~visibility definitions =
  update_existing_target env name ~f:(fun target ->
    {
      target with
      compile_definitions =
        target.compile_definitions
        @ List.map definitions ~f:(fun definition -> { visibility; definition });
    })

let target_compile_options env name =
  match find_target env name with
  | None -> []
  | Some target -> target.compile_options

let add_target_compile_options env name ~visibility options_ =
  update_existing_target env name ~f:(fun target ->
    {
      target with
      compile_options =
        target.compile_options
        @ List.map options_ ~f:(fun option_ -> { visibility; option_ });
    })

let target_compile_features env name =
  match find_target env name with
  | None -> []
  | Some target -> target.compile_features

let add_target_compile_features env name ~visibility features =
  update_existing_target env name ~f:(fun target ->
    {
      target with
      compile_features =
        target.compile_features
        @ List.map features ~f:(fun feature -> { visibility; feature });
    })

let target_link_options env name =
  match find_target env name with
  | None -> []
  | Some target -> target.link_options

let add_target_link_options env name ~visibility options_ =
  update_existing_target env name ~f:(fun target ->
    {
      target with
      link_options =
        target.link_options
        @ List.map options_ ~f:(fun link_option -> { visibility; link_option });
    })

let target_link_directories env name =
  match find_target env name with
  | None -> []
  | Some target -> target.link_directories

let add_target_link_directories env name ~visibility dirs =
  update_existing_target env name ~f:(fun target ->
    {
      target with
      link_directories =
        target.link_directories
        @ List.map dirs ~f:(fun link_directory -> { visibility; link_directory });
    })

let eval_target_visibility_items ~eval env target ~visibility items ~add =
  let env, target = eval env target in
  let target = expect_target target in
  let env, items = eval_string_list ~eval env items in
  add env target ~visibility items, target

let eval_case ~eval env = function
  | ETarget name -> Some (env, VTarget name)
  | EExecutable { name; sources } ->
    let env, name = eval_string ~eval env name in
    let env, _sources =
      List.fold sources ~init:(env, []) ~f:(fun (env, sources) source ->
        let env, source = eval_string ~eval env source in
        env, source :: sources)
    in
    Some (declare_target ~kind:TargetExecutable env name, VTarget name)
  | ELibrary { name; type_; sources } ->
    let env, name = eval_string ~eval env name in
    let env, _sources =
      List.fold sources ~init:(env, []) ~f:(fun (env, sources) source ->
        let env, source = eval_string ~eval env source in
        env, source :: sources)
    in
    Some (declare_target ~kind:(TargetLibrary type_) env name, VTarget name)
  | ETargetExists target ->
    let env, target = eval env target in
    Some (env, VBool (target_exists env (expect_target target)))
  | ETargetAddSources { target; visibility; sources } ->
    let env, name =
      eval_target_visibility_items ~eval env target ~visibility sources
        ~add:add_target_sources
    in
    Some (env, VTarget name)
  | ETargetLinkLibraries { target; visibility; items } ->
    let env, name =
      eval_target_visibility_items ~eval env target ~visibility items
        ~add:add_target_links
    in
    Some (env, VTarget name)
  | ETargetIncludeDirectories { target; visibility; dirs } ->
    let env, name =
      eval_target_visibility_items ~eval env target ~visibility dirs
        ~add:add_target_include_dirs
    in
    Some (env, VTarget name)
  | ETargetCompileDefinitions { target; visibility; definitions } ->
    let env, name =
      eval_target_visibility_items ~eval env target ~visibility definitions
        ~add:add_target_compile_definitions
    in
    Some (env, VTarget name)
  | ETargetCompileOptions { target; visibility; options_ } ->
    let env, name =
      eval_target_visibility_items ~eval env target ~visibility options_
        ~add:add_target_compile_options
    in
    Some (env, VTarget name)
  | ETargetCompileFeatures { target; visibility; features } ->
    let env, name =
      eval_target_visibility_items ~eval env target ~visibility features
        ~add:add_target_compile_features
    in
    Some (env, VTarget name)
  | ETargetLinkOptions { target; visibility; options_ } ->
    let env, name =
      eval_target_visibility_items ~eval env target ~visibility options_
        ~add:add_target_link_options
    in
    Some (env, VTarget name)
  | ETargetLinkDirectories { target; visibility; dirs } ->
    let env, name =
      eval_target_visibility_items ~eval env target ~visibility dirs
        ~add:add_target_link_directories
    in
    Some (env, VTarget name)
  | ECustomTarget { name; all; commands; depends; comment } ->
    let env, name = eval_string ~eval env name in
    let env, depends = eval_string_list ~eval env depends in
    Some
      ( set_custom_target env
          { name; all; commands; depends; comment },
        VUnit )
  | ECustomCommand { outputs; commands; depends; comment; verbatim } ->
    let env, outputs = eval_string_list ~eval env outputs in
    let env, depends = eval_string_list ~eval env depends in
    Some
      ( set_custom_command env
          { outputs; commands; depends; comment; verbatim },
        VUnit )
  | _ -> None
