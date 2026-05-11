(* Translation between Yelu1 (cmake-shaped surface) and Yelu2 (theory-side
   idealized) IR. Pure syntactic rewrites — no env, no eval — they walk
   the IR replacing each form with its counterpart in the other bundle.

   [lift_yelu1_to_yelu2]  : Yelu1 -> Yelu2.
     Each [ECmake*] surface form maps to its theory counterpart. Core
     nodes (EVar, ESetVar, ESeq, ELet, …) pass through with recursion.
     CMake-specific patterns translate to compositional theory forms
     (e.g. [ECmakeListAppend] becomes [ESetVar (..., EListAppend ...)]).

   [lower_yelu2_to_yelu1] : Yelu2 -> Yelu1.
     The reverse rewrite. Has special pattern-matched cases for
     [ESetVar] wrapping common theory effects (e.g.
     [ESetVar (out, EStringConcat ...)] becomes
     [ECmakeStringConcat { out; inputs }]).

   The two functions together form an *almost*-roundtrip: lift then
   lower should produce IR with the same observable cmake emission as
   the original. The roundtrip property is exercised by the
   [yelu1_lift_lower_roundtrip] tests. *)

(* Public surface: short re-export names for the split evaluators so that
   tests and library users don't have to spell out three module prefixes
   for what used to be one [Yelu_tiny_eval] interface. *)
let eval_yelu1_expr env expr = Yelu_tiny_yelu1.eval_expr env expr
let eval_yelu2_expr env expr = Yelu_tiny_yelu2.eval_expr env expr

open Base
open Yelu_tiny
open Yelu_theory_store
open Yelu_surface_cmake_store
open Yelu_theory_bool
open Yelu_theory_int
open Yelu_theory_list
open Yelu_surface_cmake_list
open Yelu_theory_path
open Yelu_surface_cmake_path
open Yelu_theory_file
open Yelu_surface_cmake_file
open Yelu_theory_target
open Yelu_surface_cmake_target
open Yelu_theory_install
open Yelu_surface_cmake_install
open Yelu_surface_cmake_string
open Yelu_theory_string
open Yelu_surface_cmake_if
open Yelu_theory_if
open Yelu_theory_cmake_op
open Yelu_surface_cmake_cmake_op
open Yelu_theory_dir
open Yelu_surface_cmake_dir
open Yelu_theory_test
open Yelu_surface_cmake_test
open Yelu_theory_property
open Yelu_surface_cmake_property
open Yelu_theory_find
open Yelu_surface_cmake_find
open Yelu_theory_try
open Yelu_surface_cmake_try

let rec lift_yelu1_to_yelu2 = function
  (* Core/store cases shared by both bundles. *)
  | EVar name -> EVar name
  | EString s -> EString s
  | EBool b -> EBool b
  | EInt n -> EInt n
  | EUnit -> EUnit
  | ESetVar (name, expr) -> ESetVar (name, lift_yelu1_to_yelu2 expr)
  | EUnsetVar name -> EUnsetVar name
  | EVarDefined name -> EVarDefined name
  | ESeq exprs -> ESeq (List.map exprs ~f:lift_yelu1_to_yelu2)
  | ELet { var; value; body } ->
    ELet
      { var;
        value = lift_yelu1_to_yelu2 value;
        body = lift_yelu1_to_yelu2 body }

  (* CMake store surface -> Yelu store theory. *)
  | ECmakeUnsetVar name -> EUnsetVar name
  | ECmakeVarDefined name -> EVarDefined name
  | ECmakeOption { name; value; _ } ->
    ESetVar (name, lift_yelu1_to_yelu2 value)

  (* Shared bool theory. *)
  | ENot expr -> ENot (lift_yelu1_to_yelu2 expr)
  | EAnd (left, right) ->
    EAnd (lift_yelu1_to_yelu2 left, lift_yelu1_to_yelu2 right)
  | EOr (left, right) ->
    EOr (lift_yelu1_to_yelu2 left, lift_yelu1_to_yelu2 right)

  (* Shared int theory. *)
  | EIntAdd (left, right) ->
    EIntAdd (lift_yelu1_to_yelu2 left, lift_yelu1_to_yelu2 right)
  | EIntLess (left, right) ->
    EIntLess (lift_yelu1_to_yelu2 left, lift_yelu1_to_yelu2 right)
  | EIntEqual (left, right) ->
    EIntEqual (lift_yelu1_to_yelu2 left, lift_yelu1_to_yelu2 right)

  (* Shared list theory. *)
  | EList exprs -> EList (List.map exprs ~f:lift_yelu1_to_yelu2)
  | EListAppend (list_expr, value_expr) ->
    EListAppend (lift_yelu1_to_yelu2 list_expr, lift_yelu1_to_yelu2 value_expr)
  | EListGet (list_expr, index_expr) ->
    EListGet (lift_yelu1_to_yelu2 list_expr, lift_yelu1_to_yelu2 index_expr)
  | EListLength expr -> EListLength (lift_yelu1_to_yelu2 expr)

  (* Shared path theory. *)
  | EPathFilename expr -> EPathFilename (lift_yelu1_to_yelu2 expr)
  | EPathNormalize expr -> EPathNormalize (lift_yelu1_to_yelu2 expr)

  (* Shared file theory. *)
  | EFileWrite { path; content } ->
    EFileWrite
      { path = lift_yelu1_to_yelu2 path; content = lift_yelu1_to_yelu2 content }
  | EFileRead path -> EFileRead (lift_yelu1_to_yelu2 path)
  | EFileExists path -> EFileExists (lift_yelu1_to_yelu2 path)

  (* Shared target theory. *)
  | ETarget name -> ETarget name
  | EExecutable { name; sources } ->
    EExecutable
      { name = lift_yelu1_to_yelu2 name; sources = List.map sources ~f:lift_yelu1_to_yelu2 }
  | ELibrary { name; type_; sources } ->
    ELibrary
      {
        name = lift_yelu1_to_yelu2 name;
        type_;
        sources = List.map sources ~f:lift_yelu1_to_yelu2;
      }
  | ETargetExists target -> ETargetExists (lift_yelu1_to_yelu2 target)
  | ETargetAddSources { target; visibility; sources } ->
    ETargetAddSources
      {
        target = lift_yelu1_to_yelu2 target;
        visibility;
        sources = List.map sources ~f:lift_yelu1_to_yelu2;
      }
  | ETargetLinkLibraries { target; visibility; items } ->
    ETargetLinkLibraries
      {
        target = lift_yelu1_to_yelu2 target;
        visibility;
        items = List.map items ~f:lift_yelu1_to_yelu2;
      }
  | ETargetIncludeDirectories { target; visibility; dirs } ->
    ETargetIncludeDirectories
      {
        target = lift_yelu1_to_yelu2 target;
        visibility;
        dirs = List.map dirs ~f:lift_yelu1_to_yelu2;
      }
  | ETargetCompileDefinitions { target; visibility; definitions } ->
    ETargetCompileDefinitions
      {
        target = lift_yelu1_to_yelu2 target;
        visibility;
        definitions = List.map definitions ~f:lift_yelu1_to_yelu2;
      }
  | ETargetCompileOptions { target; visibility; options_ } ->
    ETargetCompileOptions
      {
        target = lift_yelu1_to_yelu2 target;
        visibility;
        options_ = List.map options_ ~f:lift_yelu1_to_yelu2;
      }
  | ETargetCompileFeatures { target; visibility; features } ->
    ETargetCompileFeatures
      {
        target = lift_yelu1_to_yelu2 target;
        visibility;
        features = List.map features ~f:lift_yelu1_to_yelu2;
      }
  | ETargetLinkOptions { target; visibility; options_ } ->
    ETargetLinkOptions
      {
        target = lift_yelu1_to_yelu2 target;
        visibility;
        options_ = List.map options_ ~f:lift_yelu1_to_yelu2;
      }
  | ETargetLinkDirectories { target; visibility; dirs } ->
    ETargetLinkDirectories
      {
        target = lift_yelu1_to_yelu2 target;
        visibility;
        dirs = List.map dirs ~f:lift_yelu1_to_yelu2;
      }
  | ECustomTarget { name; all; commands; depends; comment } ->
    ECustomTarget
      { name; all; commands; depends = List.map depends ~f:lift_yelu1_to_yelu2; comment }
  | ECustomCommand { outputs; commands; depends; comment; verbatim } ->
    ECustomCommand
      {
        outputs = List.map outputs ~f:lift_yelu1_to_yelu2;
        commands;
        depends = List.map depends ~f:lift_yelu1_to_yelu2;
        comment;
        verbatim;
      }

  (* Shared install theory. *)
  | EInstallTargets { targets; destination; export } ->
    EInstallTargets
      {
        targets = List.map targets ~f:lift_yelu1_to_yelu2;
        destination = lift_yelu1_to_yelu2 destination;
        export = Option.map export ~f:lift_yelu1_to_yelu2;
      }
  | EInstallFiles { files; destination } ->
    EInstallFiles
      {
        files = List.map files ~f:lift_yelu1_to_yelu2;
        destination = lift_yelu1_to_yelu2 destination;
      }
  | EInstallExport { export; destination; file; namespace } ->
    EInstallExport
      {
        export = lift_yelu1_to_yelu2 export;
        destination = lift_yelu1_to_yelu2 destination;
        file = Option.map file ~f:lift_yelu1_to_yelu2;
        namespace;
      }
  | EExportExport { name; file } ->
    EExportExport
      { name = lift_yelu1_to_yelu2 name;
        file = Option.map file ~f:lift_yelu1_to_yelu2 }
  | EConfigurePackageConfigFile r ->
    EConfigurePackageConfigFile
      { r with
        install_dest = lift_yelu1_to_yelu2 r.install_dest;
        input = lift_yelu1_to_yelu2 r.input;
        output = lift_yelu1_to_yelu2 r.output }
  | EWriteBasicPackageVersionFile r ->
    EWriteBasicPackageVersionFile
      { r with
        file = lift_yelu1_to_yelu2 r.file;
        version = Option.map r.version ~f:lift_yelu1_to_yelu2 }

  (* CMake list surface -> Yelu list/string theories. *)
  | ECmakeListAppend { list; items } ->
    items
    |> List.map ~f:(fun item ->
      ESetVar (list, EListAppend (EVar list, lift_yelu1_to_yelu2 item)))
    |> ESeq
  | ECmakeListLength { list; out } ->
    ESetVar (out, EListLength (EVar list))
  | ECmakeListGet { list; index; out } ->
    ESetVar (out, EListGet (EVar list, lift_yelu1_to_yelu2 index))
  | ECmakeListJoin { list; glue; out } ->
    ESetVar (out, EStringJoin { sep = lift_yelu1_to_yelu2 glue; items = EVar list })

  (* CMake path surface -> Yelu path theory. *)
  | ECmakePathSet { path; input; normalize } ->
    ESetVar
      ( path,
        if normalize
        then EPathNormalize (lift_yelu1_to_yelu2 input)
        else lift_yelu1_to_yelu2 input )
  | ECmakePathGetFilename { path; out } ->
    ESetVar (out, EPathFilename (EVar path))
  | ECmakePathNormalPath { path; out } ->
    let out = Option.value out ~default:path in
    ESetVar (out, EPathNormalize (EVar path))

  (* CMake file surface -> Yelu file theory. *)
  | ECmakeFileWrite { path; content } ->
    ESeq
      [
        EFileWrite
          {
            path = lift_yelu1_to_yelu2 path;
            content = EStringConcat (List.map content ~f:lift_yelu1_to_yelu2);
          };
        EUnit;
      ]
  | ECmakeFileRead { path; out } ->
    ESetVar (out, EFileRead (lift_yelu1_to_yelu2 path))
  | ECmakeFileExists path ->
    EFileExists (lift_yelu1_to_yelu2 path)
  | ECmakeConfigureFile { input; output } ->
    EConfigureFile
      { input = lift_yelu1_to_yelu2 input; output = lift_yelu1_to_yelu2 output }

  (* CMake target surface -> Yelu target theory. Keep statement result as unit.
     Phase 2b: surface target-name fields are now [expr], so [lift] just
     recurses (no more EString wrapping). *)
  | ECmakeAddExecutable { name; sources } ->
    ESeq
      [
        EExecutable
          { name = lift_yelu1_to_yelu2 name;
            sources = List.map sources ~f:lift_yelu1_to_yelu2 };
        EUnit;
      ]
  | ECmakeAddLibrary { name; type_; sources } ->
    ESeq
      [
        ELibrary
          {
            name = lift_yelu1_to_yelu2 name;
            type_;
            sources = List.map sources ~f:lift_yelu1_to_yelu2;
          };
        EUnit;
      ]
  | ECmakeTargetSources { target; visibility; sources } ->
    ESeq
      [
        ETargetAddSources
          { target = lift_yelu1_to_yelu2 target;
            visibility;
            sources = List.map sources ~f:lift_yelu1_to_yelu2 };
        EUnit;
      ]
  | ECmakeTargetLinkLibraries { target; visibility; items } ->
    ESeq
      [
        ETargetLinkLibraries
          { target = lift_yelu1_to_yelu2 target;
            visibility;
            items = List.map items ~f:lift_yelu1_to_yelu2 };
        EUnit;
      ]
  | ECmakeTargetIncludeDirectories { target; visibility; dirs } ->
    ESeq
      [
        ETargetIncludeDirectories
          { target = lift_yelu1_to_yelu2 target;
            visibility;
            dirs = List.map dirs ~f:lift_yelu1_to_yelu2 };
        EUnit;
      ]
  | ECmakeTargetCompileDefinitions { target; visibility; definitions } ->
    ESeq
      [
        ETargetCompileDefinitions
          {
            target = lift_yelu1_to_yelu2 target;
            visibility;
            definitions = List.map definitions ~f:lift_yelu1_to_yelu2;
          };
        EUnit;
      ]
  | ECmakeTargetCompileOptions { target; visibility; options_ } ->
    ESeq
      [
        ETargetCompileOptions
          {
            target = lift_yelu1_to_yelu2 target;
            visibility;
            options_ = List.map options_ ~f:lift_yelu1_to_yelu2;
          };
        EUnit;
      ]
  | ECmakeTargetCompileFeatures { target; visibility; features } ->
    ESeq
      [
        ETargetCompileFeatures
          {
            target = lift_yelu1_to_yelu2 target;
            visibility;
            features = List.map features ~f:lift_yelu1_to_yelu2;
          };
        EUnit;
      ]
  | ECmakeTargetLinkOptions { target; visibility; options_ } ->
    ESeq
      [
        ETargetLinkOptions
          {
            target = lift_yelu1_to_yelu2 target;
            visibility;
            options_ = List.map options_ ~f:lift_yelu1_to_yelu2;
          };
        EUnit;
      ]
  | ECmakeTargetLinkDirectories { target; visibility; dirs } ->
    ESeq
      [
        ETargetLinkDirectories
          {
            target = lift_yelu1_to_yelu2 target;
            visibility;
            dirs = List.map dirs ~f:lift_yelu1_to_yelu2;
          };
        EUnit;
      ]
  | ECmakeAddCustomTarget { name; all; commands; depends; comment } ->
    ESeq
      [
        ECustomTarget
          { name = lift_yelu1_to_yelu2 name;
            all;
            commands;
            depends = List.map depends ~f:lift_yelu1_to_yelu2;
            comment };
        EUnit;
      ]
  | ECmakeAddCustomCommand { outputs; commands; depends; comment; verbatim } ->
    ESeq
      [
        ECustomCommand
          {
            outputs = List.map outputs ~f:lift_yelu1_to_yelu2;
            commands;
            depends = List.map depends ~f:lift_yelu1_to_yelu2;
            comment;
            verbatim;
          };
        EUnit;
      ]
  | ECmakeInstallTargets { targets; destination; export } ->
    ESeq
      [
        EInstallTargets
          {
            targets = List.map targets ~f:lift_yelu1_to_yelu2;
            destination = lift_yelu1_to_yelu2 destination;
            export = Option.map export ~f:lift_yelu1_to_yelu2;
          };
        EUnit;
      ]
  | ECmakeInstallFiles { files; destination } ->
    ESeq
      [
        EInstallFiles
          {
            files = List.map files ~f:lift_yelu1_to_yelu2;
            destination = lift_yelu1_to_yelu2 destination;
          };
        EUnit;
      ]
  | ECmakeInstallExport { export; destination; file; namespace } ->
    EInstallExport
      {
        export = lift_yelu1_to_yelu2 export;
        destination = lift_yelu1_to_yelu2 destination;
        file = Option.map file ~f:lift_yelu1_to_yelu2;
        namespace;
      }
  | ECmakeExportExport { name; file } ->
    EExportExport
      { name = lift_yelu1_to_yelu2 name;
        file = Option.map file ~f:lift_yelu1_to_yelu2 }
  | ECmakeConfigurePackageConfigFile r ->
    EConfigurePackageConfigFile
      { install_dest = lift_yelu1_to_yelu2 r.install_dest;
        input = lift_yelu1_to_yelu2 r.input;
        output = lift_yelu1_to_yelu2 r.output;
        no_set_and_check_macro = r.no_set_and_check_macro;
        no_check_required_components_macro = r.no_check_required_components_macro }
  | ECmakeWriteBasicPackageVersionFile r ->
    EWriteBasicPackageVersionFile
      { file = lift_yelu1_to_yelu2 r.file;
        version = Option.map r.version ~f:lift_yelu1_to_yelu2;
        compatibility = r.compatibility;
        arch_independent = r.arch_independent }
  | ECmakeTargetExists target ->
    ETargetExists (lift_yelu1_to_yelu2 target)

  (* CMake string surface -> Yelu string theory. *)
  | ECmakeStringEqual (left, right) ->
    EStringEqual (lift_yelu1_to_yelu2 left, lift_yelu1_to_yelu2 right)
  | ECmakeStringConcat { inputs; out } ->
    ESetVar (out, EStringConcat (List.map inputs ~f:lift_yelu1_to_yelu2))
  | ECmakeStringToupper { input; out } ->
    ESetVar (out, EStringUpper (lift_yelu1_to_yelu2 input))
  | ECmakeStringReplace { match_; replace; input; out } ->
    ESetVar
      ( out,
        EStringReplaceAll
          {
            needle = lift_yelu1_to_yelu2 match_;
            replacement = lift_yelu1_to_yelu2 replace;
            haystack = lift_yelu1_to_yelu2 input;
          } )
  | ECmakeStringLength { input; out } ->
    ESetVar (out, EStringLen (lift_yelu1_to_yelu2 input))

  (* CMake if surface -> Yelu if theory. *)
  | ECmakeIfStmt { cond; then_; else_ } ->
    EIfExpr
      {
        cond = lift_yelu1_to_yelu2 cond;
        then_ = lift_yelu1_to_yelu2 then_;
        else_ =
          (match else_ with
           | Some else_ -> lift_yelu1_to_yelu2 else_
           | None -> EUnit);
      }

  (* CMake cmake_op surface -> Yelu cmake_op theory. *)
  | ECmakeProject { name; languages; version } ->
    EProject { name; languages; version }
  | ECmakeMinimumRequired version -> EMinVersion version
  | ECmakeMessage { mode; texts } ->
    EMessage { mode; texts = List.map texts ~f:lift_yelu1_to_yelu2 }
  | ECmakeFunction { name; params; body } ->
    EDynFunction
      {
        name = lift_yelu1_to_yelu2 name;
        params;
        body = lift_yelu1_to_yelu2 body;
      }
  | ECmakeApply { name; args } ->
    EApply
      {
        name = lift_yelu1_to_yelu2 name;
        args = List.map args ~f:lift_yelu1_to_yelu2;
      }
  | ECmakeInclude { file; optional } ->
    EInclude { file = lift_yelu1_to_yelu2 file; optional }
  | ECmakeAtVar key -> EAtVar key

  (* CMake dir surface -> Yelu dir theory. *)
  | ECmakeAddSubdirectory path -> EAddSubdirectory (lift_yelu1_to_yelu2 path)

  (* CMake test surface -> Yelu test theory. *)
  | ECmakeEnableTesting -> EEnableTesting
  | ECmakeAddTest { name; command; args } ->
    EAddTest
      {
        name = lift_yelu1_to_yelu2 name;
        command = lift_yelu1_to_yelu2 command;
        args = List.map args ~f:lift_yelu1_to_yelu2;
      }

  (* CMake property surface -> Yelu property theory. *)
  | ECmakeSetTargetProperty { target; property; value } ->
    ESetTargetProperty
      { target = lift_yelu1_to_yelu2 target;
        property;
        value = lift_yelu1_to_yelu2 value }
  | ECmakeGetTargetProperty { var; target; property } ->
    EGetTargetProperty
      { var; target = lift_yelu1_to_yelu2 target; property }
  | ECmakeSetTestsProperties { tests; properties } ->
    ESetTestsProperties
      {
        tests = List.map tests ~f:lift_yelu1_to_yelu2;
        properties =
          List.map properties ~f:(fun (property, value) ->
            property, lift_yelu1_to_yelu2 value);
      }

  (* CMake find surface -> Yelu find theory. *)
  | ECmakeFindPackage { package_name; required } ->
    EFindPackage { package_name; required }

  (* CMake try surface -> Yelu try theory. *)
  | ECmakeTryCompile { result_var; sources } ->
    ETryCompile { result_var; sources = List.map sources ~f:lift_yelu1_to_yelu2 }
  | _ -> fail "cannot translate unknown Yelu1 expression"
let rec lower_yelu2_to_yelu1 = function
  (* Core/store cases shared by both bundles. *)
  | EVar name -> EVar name
  | EString s -> EString s
  | EBool b -> EBool b
  | EInt n -> EInt n
  | EUnit -> EUnit
  | EUnsetVar name -> ECmakeUnsetVar name
  | EVarDefined name -> ECmakeVarDefined name

  (* Shared bool theory. *)
  | ENot expr -> ENot (lower_yelu2_to_yelu1 expr)
  | EAnd (left, right) ->
    EAnd (lower_yelu2_to_yelu1 left, lower_yelu2_to_yelu1 right)
  | EOr (left, right) ->
    EOr (lower_yelu2_to_yelu1 left, lower_yelu2_to_yelu1 right)

  (* Shared int theory. *)
  | EIntAdd (left, right) ->
    EIntAdd (lower_yelu2_to_yelu1 left, lower_yelu2_to_yelu1 right)
  | EIntLess (left, right) ->
    EIntLess (lower_yelu2_to_yelu1 left, lower_yelu2_to_yelu1 right)
  | EIntEqual (left, right) ->
    EIntEqual (lower_yelu2_to_yelu1 left, lower_yelu2_to_yelu1 right)

  (* Shared list theory. *)
  | EList exprs -> EList (List.map exprs ~f:lower_yelu2_to_yelu1)
  | EListAppend (list_expr, value_expr) ->
    EListAppend (lower_yelu2_to_yelu1 list_expr, lower_yelu2_to_yelu1 value_expr)
  | EListGet (list_expr, index_expr) ->
    EListGet (lower_yelu2_to_yelu1 list_expr, lower_yelu2_to_yelu1 index_expr)
  | EListLength expr -> EListLength (lower_yelu2_to_yelu1 expr)

  (* Shared path theory. *)
  | EPathFilename expr -> EPathFilename (lower_yelu2_to_yelu1 expr)
  | EPathNormalize expr -> EPathNormalize (lower_yelu2_to_yelu1 expr)

  (* Shared target theory. Phase 2b: surface target-name fields take [expr]
     directly; lower preserves the let-resolvable structure. The literal
     [EString target_name] cases stay so that the surrounding ESetVar
     pattern can produce a literal [ETarget _] value. *)
  | ETarget name -> ETarget name
  | EExecutable { name = EString target_name; sources } ->
    ESeq
      [
        ECmakeAddExecutable
          { name = EString target_name;
            sources = List.map sources ~f:lower_yelu2_to_yelu1 };
        ETarget target_name;
      ]
  | EExecutable { name; sources } ->
    ECmakeAddExecutable
      { name = lower_yelu2_to_yelu1 name;
        sources = List.map sources ~f:lower_yelu2_to_yelu1 }
  | ELibrary { name = EString target_name; type_; sources } ->
    ESeq
      [
        ECmakeAddLibrary
          { name = EString target_name;
            type_;
            sources = List.map sources ~f:lower_yelu2_to_yelu1 };
        ETarget target_name;
      ]
  | ELibrary { name; type_; sources } ->
    ECmakeAddLibrary
      {
        name = lower_yelu2_to_yelu1 name;
        type_;
        sources = List.map sources ~f:lower_yelu2_to_yelu1;
      }
  | ETargetExists target ->
    ECmakeTargetExists (lower_yelu2_to_yelu1 target)
  | ETargetAddSources { target = ETarget name; visibility; sources } ->
    ESeq
      [
        ECmakeTargetSources
          { target = ETarget name;
            visibility;
            sources = List.map sources ~f:lower_yelu2_to_yelu1 };
        ETarget name;
      ]
  | ETargetAddSources { target; visibility; sources } ->
    ECmakeTargetSources
      {
        target = lower_yelu2_to_yelu1 target;
        visibility;
        sources = List.map sources ~f:lower_yelu2_to_yelu1;
      }
  | ETargetLinkLibraries { target = ETarget name; visibility; items } ->
    ESeq
      [
        ECmakeTargetLinkLibraries
          { target = ETarget name;
            visibility;
            items = List.map items ~f:lower_yelu2_to_yelu1 };
        ETarget name;
      ]
  | ETargetLinkLibraries { target; visibility; items } ->
    ECmakeTargetLinkLibraries
      {
        target = lower_yelu2_to_yelu1 target;
        visibility;
        items = List.map items ~f:lower_yelu2_to_yelu1;
      }
  | ETargetIncludeDirectories { target = ETarget name; visibility; dirs } ->
    ESeq
      [
        ECmakeTargetIncludeDirectories
          { target = ETarget name;
            visibility;
            dirs = List.map dirs ~f:lower_yelu2_to_yelu1 };
        ETarget name;
      ]
  | ETargetIncludeDirectories { target; visibility; dirs } ->
    ECmakeTargetIncludeDirectories
      {
        target = lower_yelu2_to_yelu1 target;
        visibility;
        dirs = List.map dirs ~f:lower_yelu2_to_yelu1;
      }
  | ETargetCompileDefinitions { target = ETarget name; visibility; definitions } ->
    ESeq
      [
        ECmakeTargetCompileDefinitions
          {
            target = ETarget name;
            visibility;
            definitions = List.map definitions ~f:lower_yelu2_to_yelu1;
          };
        ETarget name;
      ]
  | ETargetCompileDefinitions { target; visibility; definitions } ->
    ECmakeTargetCompileDefinitions
      {
        target = lower_yelu2_to_yelu1 target;
        visibility;
        definitions = List.map definitions ~f:lower_yelu2_to_yelu1;
      }
  | ETargetCompileOptions { target = ETarget name; visibility; options_ } ->
    ESeq
      [
        ECmakeTargetCompileOptions
          {
            target = ETarget name;
            visibility;
            options_ = List.map options_ ~f:lower_yelu2_to_yelu1;
          };
        ETarget name;
      ]
  | ETargetCompileOptions { target; visibility; options_ } ->
    ECmakeTargetCompileOptions
      {
        target = lower_yelu2_to_yelu1 target;
        visibility;
        options_ = List.map options_ ~f:lower_yelu2_to_yelu1;
      }
  | ETargetCompileFeatures { target = ETarget name; visibility; features } ->
    ESeq
      [
        ECmakeTargetCompileFeatures
          {
            target = ETarget name;
            visibility;
            features = List.map features ~f:lower_yelu2_to_yelu1;
          };
        ETarget name;
      ]
  | ETargetCompileFeatures { target; visibility; features } ->
    ECmakeTargetCompileFeatures
      {
        target = lower_yelu2_to_yelu1 target;
        visibility;
        features = List.map features ~f:lower_yelu2_to_yelu1;
      }
  | ETargetLinkOptions { target = ETarget name; visibility; options_ } ->
    ESeq
      [
        ECmakeTargetLinkOptions
          {
            target = ETarget name;
            visibility;
            options_ = List.map options_ ~f:lower_yelu2_to_yelu1;
          };
        ETarget name;
      ]
  | ETargetLinkOptions { target; visibility; options_ } ->
    ECmakeTargetLinkOptions
      {
        target = lower_yelu2_to_yelu1 target;
        visibility;
        options_ = List.map options_ ~f:lower_yelu2_to_yelu1;
      }
  | ETargetLinkDirectories { target = ETarget name; visibility; dirs } ->
    ESeq
      [
        ECmakeTargetLinkDirectories
          {
            target = ETarget name;
            visibility;
            dirs = List.map dirs ~f:lower_yelu2_to_yelu1;
          };
        ETarget name;
      ]
  | ETargetLinkDirectories { target; visibility; dirs } ->
    ECmakeTargetLinkDirectories
      {
        target = lower_yelu2_to_yelu1 target;
        visibility;
        dirs = List.map dirs ~f:lower_yelu2_to_yelu1;
      }
  | ECustomTarget { name; all; commands; depends; comment } ->
    ECmakeAddCustomTarget
      { name = lower_yelu2_to_yelu1 name;
        all;
        commands;
        depends = List.map depends ~f:lower_yelu2_to_yelu1;
        comment }
  | ECustomCommand { outputs; commands; depends; comment; verbatim } ->
    ECmakeAddCustomCommand
      {
        outputs = List.map outputs ~f:lower_yelu2_to_yelu1;
        commands;
        depends = List.map depends ~f:lower_yelu2_to_yelu1;
        comment;
        verbatim;
      }
  | EInstallTargets { targets; destination; export } ->
    ECmakeInstallTargets
      {
        targets = List.map targets ~f:lower_yelu2_to_yelu1;
        destination = lower_yelu2_to_yelu1 destination;
        export = Option.map export ~f:lower_yelu2_to_yelu1;
      }
  | EInstallFiles { files; destination } ->
    ECmakeInstallFiles
      {
        files = List.map files ~f:lower_yelu2_to_yelu1;
        destination = lower_yelu2_to_yelu1 destination;
      }
  | EInstallExport { export; destination; file; namespace } ->
    ECmakeInstallExport
      {
        export = lower_yelu2_to_yelu1 export;
        destination = lower_yelu2_to_yelu1 destination;
        file = Option.map file ~f:lower_yelu2_to_yelu1;
        namespace;
      }
  | EExportExport { name; file } ->
    ECmakeExportExport
      { name = lower_yelu2_to_yelu1 name;
        file = Option.map file ~f:lower_yelu2_to_yelu1 }
  | EConfigurePackageConfigFile r ->
    ECmakeConfigurePackageConfigFile
      { install_dest = lower_yelu2_to_yelu1 r.install_dest;
        input = lower_yelu2_to_yelu1 r.input;
        output = lower_yelu2_to_yelu1 r.output;
        no_set_and_check_macro = r.no_set_and_check_macro;
        no_check_required_components_macro = r.no_check_required_components_macro }
  | EWriteBasicPackageVersionFile r ->
    ECmakeWriteBasicPackageVersionFile
      { file = lower_yelu2_to_yelu1 r.file;
        version = Option.map r.version ~f:lower_yelu2_to_yelu1;
        compatibility = r.compatibility;
        arch_independent = r.arch_independent }

  (* Yelu list/string theories -> CMake list surface. *)
  | ESetVar (name, EListAppend (EVar list, item)) when String.equal name list ->
    ECmakeListAppend { list; items = [ lower_yelu2_to_yelu1 item ] }
  | ESetVar (name, EListLength (EVar list)) ->
    ECmakeListLength { list; out = name }
  | ESetVar (name, EListGet (EVar list, index)) ->
    ECmakeListGet { list; index = lower_yelu2_to_yelu1 index; out = name }
  | ESetVar (name, EStringJoin { sep; items = EVar list }) ->
    ECmakeListJoin { list; glue = lower_yelu2_to_yelu1 sep; out = name }

  (* Yelu path theory -> CMake path surface. *)
  | ESetVar (name, EPathFilename (EVar path)) ->
    ECmakePathGetFilename { path; out = name }
  | ESetVar (name, EPathNormalize (EVar path)) when String.equal name path ->
    ECmakePathNormalPath { path; out = None }
  | ESetVar (name, EPathNormalize (EVar path)) ->
    ECmakePathNormalPath { path; out = Some name }
  | ESetVar (name, EPathNormalize expr) ->
    ECmakePathSet { path = name; input = lower_yelu2_to_yelu1 expr; normalize = true }

  (* Yelu file theory -> CMake file surface. *)
  | EFileWrite { path; content } ->
    ECmakeFileWrite
      { path = lower_yelu2_to_yelu1 path; content = [ lower_yelu2_to_yelu1 content ] }
  | ESetVar (name, EFileRead path) ->
    ECmakeFileRead { path = lower_yelu2_to_yelu1 path; out = name }
  | EFileExists path ->
    ECmakeFileExists (lower_yelu2_to_yelu1 path)
  | EConfigureFile { input; output } ->
    ECmakeConfigureFile
      { input = lower_yelu2_to_yelu1 input; output = lower_yelu2_to_yelu1 output }

  (* Yelu target theory -> CMake target surface. *)
  | ESetVar (var, EExecutable { name = EString target_name; sources }) ->
    ESeq
      [
        ECmakeAddExecutable
          { name = EString target_name;
            sources = List.map sources ~f:lower_yelu2_to_yelu1 };
        ESetVar (var, ETarget target_name);
      ]
  | ESetVar (var, ELibrary { name = EString target_name; type_; sources }) ->
    ESeq
      [
        ECmakeAddLibrary
          { name = EString target_name;
            type_;
            sources = List.map sources ~f:lower_yelu2_to_yelu1 };
        ESetVar (var, ETarget target_name);
      ]

  (* Yelu string theory -> CMake string surface. *)
  | EStringEqual (left, right) ->
    ECmakeStringEqual (lower_yelu2_to_yelu1 left, lower_yelu2_to_yelu1 right)
  | ESetVar (name, EStringConcat exprs) ->
    ECmakeStringConcat { inputs = List.map exprs ~f:lower_yelu2_to_yelu1; out = name }
  | ESetVar (name, EStringUpper expr) ->
    ECmakeStringToupper { input = lower_yelu2_to_yelu1 expr; out = name }
  | ESetVar (name, EStringReplaceAll { needle; replacement; haystack }) ->
    ECmakeStringReplace
      {
        match_ = lower_yelu2_to_yelu1 needle;
        replace = lower_yelu2_to_yelu1 replacement;
        input = lower_yelu2_to_yelu1 haystack;
        out = name;
      }
  | ESetVar (name, EStringLen expr) ->
    ECmakeStringLength { input = lower_yelu2_to_yelu1 expr; out = name }
  | ESetVar (name, EStringJoin { sep; items }) ->
    ESetVar
      ( name,
        EStringJoin
          { sep = lower_yelu2_to_yelu1 sep; items = lower_yelu2_to_yelu1 items } )

  (* Bundle-level if/store interaction: a value-producing Yelu if saved to a
     name lowers to a statement-style CMake if whose branches save that name. *)
  | ESetVar (name, EIfExpr { cond; then_; else_ }) ->
    ECmakeIfStmt
      {
        cond = lower_yelu2_to_yelu1 cond;
        then_ = lower_yelu2_to_yelu1 (ESetVar (name, then_));
        else_ = Some (lower_yelu2_to_yelu1 (ESetVar (name, else_)));
      }

  (* Yelu if theory -> CMake if surface. This is valid when branch expressions
     already lower to effectful/unit-shaped CMake surface expressions. *)
  | EIfExpr { cond; then_; else_ } ->
    ECmakeIfStmt
      {
        cond = lower_yelu2_to_yelu1 cond;
        then_ = lower_yelu2_to_yelu1 then_;
        else_ = Some (lower_yelu2_to_yelu1 else_);
      }

  (* Yelu cmake_op theory -> CMake cmake_op surface. *)
  | EProject { name; languages; version } ->
    ECmakeProject { name; languages; version }
  | EMinVersion version -> ECmakeMinimumRequired version
  | EMessage { mode; texts } ->
    ECmakeMessage { mode; texts = List.map texts ~f:lower_yelu2_to_yelu1 }
  | EDynFunction { name; params; body } ->
    ECmakeFunction
      {
        name = lower_yelu2_to_yelu1 name;
        params;
        body = lower_yelu2_to_yelu1 body;
      }
  | EApply { name; args } ->
    ECmakeApply
      {
        name = lower_yelu2_to_yelu1 name;
        args = List.map args ~f:lower_yelu2_to_yelu1;
      }
  | EInclude { file; optional } ->
    ECmakeInclude { file = lower_yelu2_to_yelu1 file; optional }
  | EAtVar key -> ECmakeAtVar key

  (* Yelu dir theory -> CMake dir surface. *)
  | EAddSubdirectory path -> ECmakeAddSubdirectory (lower_yelu2_to_yelu1 path)

  (* Yelu test theory -> CMake test surface. *)
  | EEnableTesting -> ECmakeEnableTesting
  | EAddTest { name; command; args } ->
    ECmakeAddTest
      {
        name = lower_yelu2_to_yelu1 name;
        command = lower_yelu2_to_yelu1 command;
        args = List.map args ~f:lower_yelu2_to_yelu1;
      }

  (* Yelu property theory -> CMake property surface. *)
  | ESetTargetProperty { target; property; value } ->
    ECmakeSetTargetProperty
      { target = lower_yelu2_to_yelu1 target;
        property;
        value = lower_yelu2_to_yelu1 value }
  | EGetTargetProperty { var; target; property } ->
    ECmakeGetTargetProperty
      { var; target = lower_yelu2_to_yelu1 target; property }
  | ESetTestsProperties { tests; properties } ->
    ECmakeSetTestsProperties
      {
        tests = List.map tests ~f:lower_yelu2_to_yelu1;
        properties =
          List.map properties ~f:(fun (property, value) ->
            property, lower_yelu2_to_yelu1 value);
      }

  (* Yelu find theory -> CMake find surface. *)
  | EFindPackage { package_name; required } ->
    ECmakeFindPackage { package_name; required }

  (* Yelu try theory -> CMake try surface. *)
  | ETryCompile { result_var; sources } ->
    ECmakeTryCompile
      { result_var; sources = List.map sources ~f:lower_yelu2_to_yelu1 }

  | ESetVar (name, expr) -> ESetVar (name, lower_yelu2_to_yelu1 expr)
  | ESeq exprs -> ESeq (List.map exprs ~f:lower_yelu2_to_yelu1)
  | ELet { var; value; body } ->
    ELet
      { var;
        value = lower_yelu2_to_yelu1 value;
        body = lower_yelu2_to_yelu1 body }
  | _ -> fail "cannot translate unknown Yelu2 expression"
