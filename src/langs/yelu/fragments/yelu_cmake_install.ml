open Base
open Yelu_cmake
open Yelu_cmake_normal_target

let name = "tiny_cmake_install"
let requires = [ "core.string"; "target.add_executable" ]
let provides =
  [ "install.targets";
    "install.files";
    "install.export";
    "install.export_export";
    "install.configure_package_config_file";
    "install.write_basic_package_version_file";
  ]

type expr +=
  | ECmakeInstallTargets of {
      targets : expr list;
      destination : expr;
      export : expr option;
    }
  | ECmakeInstallFiles of {
      files : expr list;
      destination : expr;
    }
  | ECmakeInstallExport of {
      export : expr;
      destination : expr;
      file : expr option;
      namespace : string option;
    }
  | ECmakeExportExport of {
      name : expr;
      file : expr option;
    }
  | ECmakeExportTargets of {
      targets : expr list;
      namespace : string option;
      file : expr option;
    }
  | ECmakeConfigurePackageConfigFile of {
      install_dest : expr;
      input : expr;
      output : expr;
      no_set_and_check_macro : bool;
      no_check_required_components_macro : bool;
    }
  | ECmakeWriteBasicPackageVersionFile of {
      file : expr;
      version : expr option;
      compatibility : string;
      arch_independent : bool;
    }

let eval_optional_string ~eval env = function
  | None -> env, None
  | Some e ->
    let env, s = eval_string ~eval env e in
    env, Some s

let eval_case ~eval env = function
  | ECmakeInstallTargets { targets; destination; export } ->
    let env, targets = eval_string_list ~eval env targets in
    let env, destination = eval_string ~eval env destination in
    let env, export =
      match export with
      | None -> env, None
      | Some export ->
        let env, export = eval_string ~eval env export in
        env, Some export
    in
    Some (add_install_rule env (InstallTargets { targets; destination; export }), VUnit)
  | ECmakeInstallFiles { files; destination } ->
    let env, files = eval_string_list ~eval env files in
    let env, destination = eval_string ~eval env destination in
    Some (add_install_rule env (InstallFiles { files; destination }), VUnit)
  | ECmakeInstallExport { export; destination; file; namespace } ->
    let env, export = eval_string ~eval env export in
    let env, destination = eval_string ~eval env destination in
    let env, file = eval_optional_string ~eval env file in
    Some
      ( add_install_rule env
          (InstallExport { export; destination; file; namespace }),
        VUnit )
  | ECmakeExportExport { name; file } ->
    let env, name = eval_string ~eval env name in
    let env, file = eval_optional_string ~eval env file in
    Some (add_install_rule env (ExportExport { name; file }), VUnit)
  | ECmakeExportTargets _ -> Some (env, VUnit)
  | ECmakeConfigurePackageConfigFile
      { install_dest; input; output;
        no_set_and_check_macro; no_check_required_components_macro } ->
    let env, install_dest = eval_string ~eval env install_dest in
    let env, input = eval_string ~eval env input in
    let env, output = eval_string ~eval env output in
    Some
      ( add_install_rule env
          (ConfigurePackageConfigFile
             { install_dest; input; output;
               no_set_and_check_macro; no_check_required_components_macro }),
        VUnit )
  | ECmakeWriteBasicPackageVersionFile
      { file; version; compatibility; arch_independent } ->
    let env, file = eval_string ~eval env file in
    let env, version = eval_optional_string ~eval env version in
    Some
      ( add_install_rule env
          (WriteBasicPackageVersionFile
             { file; version; compatibility; arch_independent }),
        VUnit )
  | _ -> None
