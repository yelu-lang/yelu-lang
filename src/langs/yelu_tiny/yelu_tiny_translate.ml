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
  | ECmakeUnsetVarCache name -> ECmakeUnsetVarCache name
  | ECmakeVarDefined name -> EVarDefined name
  | ECmakeSetParentScope { name; value } ->
    ECmakeSetParentScope
      { name; value = lift_yelu1_to_yelu2 value }
  | ECmakeSetEnvVar { name; value } ->
    ECmakeSetEnvVar { name; value = lift_yelu1_to_yelu2 value }
  | ECmakeUnsetEnvVar name -> ECmakeUnsetEnvVar name
  | ECmakeOption { name; value; _ } ->
    ESetVar (name, lift_yelu1_to_yelu2 value)
  | ECmakeSetCache { name; values; cache_type; docstring; force } ->
    ECmakeSetCache
      { name;
        values = List.map values ~f:lift_yelu1_to_yelu2;
        cache_type; docstring; force }
  | ECmakeMatches { expr_; regex } ->
    ECmakeMatches { expr_ = lift_yelu1_to_yelu2 expr_; regex }
  | ECmakeInList { item; list_ } ->
    ECmakeInList
      { item = lift_yelu1_to_yelu2 item;
        list_ = lift_yelu1_to_yelu2 list_ }
  | ECmakeIsDirectory path ->
    ECmakeIsDirectory (lift_yelu1_to_yelu2 path)
  | ECmakePolicyCheck p -> ECmakePolicyCheck p

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
  | ELibraryAlias { name; target } -> ELibraryAlias { name; target }
  | EExecutableAlias { name; target } -> EExecutableAlias { name; target }
  | EAddDependencies { target; dep } -> EAddDependencies { target; dep }
  | ELibraryImported { name; lib_type; global } ->
    ELibraryImported
      { name = lift_yelu1_to_yelu2 name; lib_type; global }
  | ETargetSourcesFs { target; items } ->
    let lift_item = function
      | Tsi_plain { visibility; items } ->
        Tsi_plain
          { visibility; items = List.map items ~f:lift_yelu1_to_yelu2 }
      | Tsi_file_set { kind; type_; base_dirs; files } ->
        Tsi_file_set
          { kind; type_;
            base_dirs = List.map base_dirs ~f:lift_yelu1_to_yelu2;
            files = List.map files ~f:lift_yelu1_to_yelu2 }
    in
    ETargetSourcesFs
      { target = lift_yelu1_to_yelu2 target;
        items = List.map items ~f:lift_item }
  | ETargetPrecompileHeaders { target; visibility; headers } ->
    ETargetPrecompileHeaders
      { target = lift_yelu1_to_yelu2 target;
        visibility;
        headers = List.map headers ~f:lift_yelu1_to_yelu2 }

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
  (* Additional list() subcommands — surface-only passthrough. *)
  | ECmakeListPrepend { list; items } ->
    ECmakeListPrepend
      { list; items = List.map items ~f:lift_yelu1_to_yelu2 }
  | ECmakeListInsert { list; index; items } ->
    ECmakeListInsert
      { list; index; items = List.map items ~f:lift_yelu1_to_yelu2 }
  | ECmakeListRemoveItem { list; items } ->
    ECmakeListRemoveItem
      { list; items = List.map items ~f:lift_yelu1_to_yelu2 }
  | ECmakeListRemoveAt _ | ECmakeListRemoveDuplicates _
  | ECmakeListReverse _ | ECmakeListSort _ | ECmakeListFilter _
  | ECmakeListSublist _ | ECmakeListPopBack _ | ECmakeListPopFront _
  | ECmakeListTransform _ as e -> e
  | ECmakeListFind { list; value; out } ->
    ECmakeListFind
      { list; value = lift_yelu1_to_yelu2 value; out }

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
  (* Generalized cmake_path subcommands lift as passthrough — they are
     surface-only constructs at this slice; the eval-stubs live in the
     surface fragment. *)
  | ECmakePathGet _ | ECmakePathHas _
  | ECmakePathIsAbsolute _ | ECmakePathIsRelative _ | ECmakePathIsPrefix _
  | ECmakePathCompare _
  | ECmakePathAppend _ | ECmakePathAppendString _
  | ECmakePathRemoveFilename _ | ECmakePathReplaceFilename _
  | ECmakePathRemoveExtension _ | ECmakePathReplaceExtension _
  | ECmakePathRelativePath _ | ECmakePathAbsolutePath _
  | ECmakePathNativePath _
  | ECmakePathConvertToCmake _ | ECmakePathConvertToNative _
  | ECmakePathHash _ as e -> e

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
  | ECmakeFileRelativePath { var; base; file } ->
    ECmakeFileRelativePath
      { var;
        base = lift_yelu1_to_yelu2 base;
        file = lift_yelu1_to_yelu2 file }
  | ECmakeFileGlob { out; recurse; relative; configure_depends; patterns } ->
    ECmakeFileGlob
      { out; recurse;
        relative = Option.map relative ~f:lift_yelu1_to_yelu2;
        configure_depends;
        patterns = List.map patterns ~f:lift_yelu1_to_yelu2 }
  (* Additional file() subcommands — surface-only passthrough. *)
  | ECmakeFileWriteAppend { path; content } ->
    ECmakeFileWriteAppend
      { path = lift_yelu1_to_yelu2 path;
        content = List.map content ~f:lift_yelu1_to_yelu2 }
  | ECmakeFileReadFull { path; out; offset; limit; hex } ->
    ECmakeFileReadFull
      { path = lift_yelu1_to_yelu2 path; out; offset; limit; hex }
  | ECmakeFileStrings { out; path; regex; encoding; limit_count } ->
    ECmakeFileStrings
      { out; path = lift_yelu1_to_yelu2 path; regex; encoding; limit_count }
  | ECmakeFileTouch { files; nocreate } ->
    ECmakeFileTouch
      { files = List.map files ~f:lift_yelu1_to_yelu2; nocreate }
  | ECmakeFileMakeDirectory { dirs } ->
    ECmakeFileMakeDirectory
      { dirs = List.map dirs ~f:lift_yelu1_to_yelu2 }
  | ECmakeFileRename { old_; new_; result; no_replace } ->
    ECmakeFileRename
      { old_ = lift_yelu1_to_yelu2 old_;
        new_ = lift_yelu1_to_yelu2 new_;
        result; no_replace }
  | ECmakeFileRemove { files; recurse } ->
    ECmakeFileRemove
      { files = List.map files ~f:lift_yelu1_to_yelu2; recurse }
  | ECmakeFileCopy { input; output; result; only_if_different } ->
    ECmakeFileCopy
      { input = lift_yelu1_to_yelu2 input;
        output = lift_yelu1_to_yelu2 output;
        result; only_if_different }
  | ECmakeFileRealPath { out; path; base_dir; expand_tilde } ->
    ECmakeFileRealPath
      { out; path = lift_yelu1_to_yelu2 path;
        base_dir = Option.map base_dir ~f:lift_yelu1_to_yelu2;
        expand_tilde }
  | ECmakeFileSize { out; path } ->
    ECmakeFileSize { out; path = lift_yelu1_to_yelu2 path }
  | ECmakeFileReadSymlink { out; link } ->
    ECmakeFileReadSymlink { out; link = lift_yelu1_to_yelu2 link }
  | ECmakeFileTimestamp { out; path; format; utc } ->
    ECmakeFileTimestamp
      { out; path = lift_yelu1_to_yelu2 path; format; utc }
  | ECmakeStringRegexReplace { regex; replace; out; inputs } ->
    ECmakeStringRegexReplace
      { regex;
        replace = lift_yelu1_to_yelu2 replace;
        out;
        inputs = List.map inputs ~f:lift_yelu1_to_yelu2 }
  (* Additional string() subcommands — surface-only passthrough. *)
  | ECmakeStringTolower { input; out } ->
    ECmakeStringTolower { input = lift_yelu1_to_yelu2 input; out }
  | ECmakeStringStrip { input; out } ->
    ECmakeStringStrip { input = lift_yelu1_to_yelu2 input; out }
  | ECmakeStringRegexMatch { regex; out; inputs } ->
    ECmakeStringRegexMatch
      { regex; out; inputs = List.map inputs ~f:lift_yelu1_to_yelu2 }
  | ECmakeStringRegexMatchAll { regex; out; inputs } ->
    ECmakeStringRegexMatchAll
      { regex; out; inputs = List.map inputs ~f:lift_yelu1_to_yelu2 }
  | ECmakeStringRegexQuote { out; inputs } ->
    ECmakeStringRegexQuote
      { out; inputs = List.map inputs ~f:lift_yelu1_to_yelu2 }
  | ECmakeStringAppend { cvar; inputs } ->
    ECmakeStringAppend
      { cvar; inputs = List.map inputs ~f:lift_yelu1_to_yelu2 }
  | ECmakeStringPrepend { cvar; inputs } ->
    ECmakeStringPrepend
      { cvar; inputs = List.map inputs ~f:lift_yelu1_to_yelu2 }
  | ECmakeStringJoin { glue; out; inputs } ->
    ECmakeStringJoin
      { glue = lift_yelu1_to_yelu2 glue; out;
        inputs = List.map inputs ~f:lift_yelu1_to_yelu2 }
  | ECmakeStringFind { string; substring; out; reverse } ->
    ECmakeStringFind
      { string = lift_yelu1_to_yelu2 string;
        substring = lift_yelu1_to_yelu2 substring; out; reverse }
  | ECmakeStringSubstring { string; begin_; length; out } ->
    ECmakeStringSubstring
      { string = lift_yelu1_to_yelu2 string; begin_; length; out }
  | ECmakeStringRepeat { string; count; out } ->
    ECmakeStringRepeat
      { string = lift_yelu1_to_yelu2 string; count; out }
  | ECmakeStringGenexStrip { input; out } ->
    ECmakeStringGenexStrip { input = lift_yelu1_to_yelu2 input; out }
  | ECmakeStringMakeCIdentifier { input; out } ->
    ECmakeStringMakeCIdentifier { input = lift_yelu1_to_yelu2 input; out }
  | ECmakeStringTimestamp _ as e -> e
  | ECmakeStringHex { input; out } ->
    ECmakeStringHex { input = lift_yelu1_to_yelu2 input; out }
  | ECmakeStringUuid _ as e -> e
  | ECmakeStringCompare { op; string1; string2; out } ->
    ECmakeStringCompare
      { op; string1 = lift_yelu1_to_yelu2 string1;
        string2 = lift_yelu1_to_yelu2 string2; out }
  | ECmakeStringJson { out; error_var; op_name; args } ->
    ECmakeStringJson
      { out; error_var; op_name;
        args = List.map args ~f:lift_yelu1_to_yelu2 }
  | ECmakeGetFilenameComponent { var; filename; mode } ->
    ECmakeGetFilenameComponent
      { var; filename = lift_yelu1_to_yelu2 filename; mode }
  | ECmakeMacro { name; params; body } ->
    ECmakeMacro
      { name = lift_yelu1_to_yelu2 name;
        params;
        body = lift_yelu1_to_yelu2 body }
  | ECmakeForeach { loop_var; items; body } ->
    ECmakeForeach
      { loop_var;
        items = List.map items ~f:lift_yelu1_to_yelu2;
        body = lift_yelu1_to_yelu2 body }
  | ECmakeForeachRange { loop_var; start; stop; step; body } ->
    ECmakeForeachRange
      { loop_var; start; stop; step;
        body = lift_yelu1_to_yelu2 body }
  | ECmakeForeachZip { loop_vars; lists; body } ->
    ECmakeForeachZip
      { loop_vars; lists; body = lift_yelu1_to_yelu2 body }
  | ECmakeForeachInList { loop_var; lists; items; body } ->
    ECmakeForeachInList
      { loop_var; lists;
        items = List.map items ~f:lift_yelu1_to_yelu2;
        body = lift_yelu1_to_yelu2 body }
  | ECmakeSeparateArguments { var; mode; input } ->
    ECmakeSeparateArguments
      { var; mode; input = Option.map input ~f:lift_yelu1_to_yelu2 }
  | ECmakeWhile { cond; body } ->
    ECmakeWhile
      { cond = lift_yelu1_to_yelu2 cond;
        body = lift_yelu1_to_yelu2 body }
  | ECmakeBreak -> ECmakeBreak
  | ECmakeContinue -> ECmakeContinue
  | ECmakeBlock { scope_vars; propagate; body } ->
    ECmakeBlock
      { scope_vars; propagate; body = lift_yelu1_to_yelu2 body }
  | ECmakeReturn { propagate_vars } ->
    ECmakeReturn { propagate_vars }

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
  | ECmakeTargetIncludeDirectories
      { target; visibility; before = _; system = _; dirs } ->
    (* Yelu2 theory drops cmake-specific BEFORE / SYSTEM flags; the
       round-trip preserves them only via the Yelu1 surface, which is
       where they belong. Lower fills with [false] (the legacy default). *)
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
  | ECmakeTargetCompileOptions { target; visibility; before = _; options_ } ->
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
  | ECmakeTargetLinkOptions { target; visibility; before = _; options_ } ->
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
  | ECmakeTargetLinkDirectories { target; visibility; before = _; dirs } ->
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
  | ECmakeAddLibraryAlias { name; target } ->
    ELibraryAlias { name; target }
  | ECmakeAddExecutableAlias { name; target } ->
    EExecutableAlias { name; target }
  | ECmakeAddDependencies { target; dep } ->
    EAddDependencies { target; dep }
  | ECmakeAddLibraryImported { name; lib_type; global } ->
    ELibraryImported
      { name = lift_yelu1_to_yelu2 name; lib_type; global }
  | ECmakeTargetSourcesFs { target; items } ->
    let lift_item = function
      | Tsi_plain { visibility; items } ->
        Tsi_plain
          { visibility; items = List.map items ~f:lift_yelu1_to_yelu2 }
      | Tsi_file_set { kind; type_; base_dirs; files } ->
        Tsi_file_set
          { kind; type_;
            base_dirs = List.map base_dirs ~f:lift_yelu1_to_yelu2;
            files = List.map files ~f:lift_yelu1_to_yelu2 }
    in
    ETargetSourcesFs
      { target = lift_yelu1_to_yelu2 target;
        items = List.map items ~f:lift_item }
  | ECmakeTargetPrecompileHeaders { target; visibility; headers } ->
    ETargetPrecompileHeaders
      { target = lift_yelu1_to_yelu2 target;
        visibility;
        headers = List.map headers ~f:lift_yelu1_to_yelu2 }
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
  | ECmakeVersionLess (a, b) ->
    ECmakeVersionLess (lift_yelu1_to_yelu2 a, lift_yelu1_to_yelu2 b)
  | ECmakeVersionGreater (a, b) ->
    ECmakeVersionGreater (lift_yelu1_to_yelu2 a, lift_yelu1_to_yelu2 b)
  | ECmakeVersionEqual (a, b) ->
    ECmakeVersionEqual (lift_yelu1_to_yelu2 a, lift_yelu1_to_yelu2 b)
  | ECmakeVersionLessEqual (a, b) ->
    ECmakeVersionLessEqual (lift_yelu1_to_yelu2 a, lift_yelu1_to_yelu2 b)
  | ECmakeVersionGreaterEqual (a, b) ->
    ECmakeVersionGreaterEqual (lift_yelu1_to_yelu2 a, lift_yelu1_to_yelu2 b)
  | ECmakeMath { exp; out } -> ECmakeMath { exp; out }
  (* Additional cmake_op subcommands — surface-only passthrough. *)
  | ECmakeEnableLanguage _ | ECmakePolicySet _
  | ECmakeLanguageEval _ | ECmakeLanguageGetLogLevel _
  | ECmakeVariableWatch _ | ECmakeIncludeGuard _
  | ECmakeQuoteCmd _ as e -> e
  | ECmakeLanguageCall { cmd; args } ->
    ECmakeLanguageCall
      { cmd; args = List.map args ~f:lift_yelu1_to_yelu2 }
  | ECmakeExecuteProcess r ->
    ECmakeExecuteProcess
      { commands = List.map r.commands
            ~f:(List.map ~f:lift_yelu1_to_yelu2);
        working_directory =
          Option.map r.working_directory ~f:lift_yelu1_to_yelu2;
        timeout = r.timeout;
        result_variable = r.result_variable;
        output_variable = r.output_variable;
        error_variable = r.error_variable;
        input_file = Option.map r.input_file ~f:lift_yelu1_to_yelu2;
        output_file = Option.map r.output_file ~f:lift_yelu1_to_yelu2;
        error_file = Option.map r.error_file ~f:lift_yelu1_to_yelu2;
        output_quiet = r.output_quiet;
        error_quiet = r.error_quiet;
        output_strip_trailing_whitespace =
          r.output_strip_trailing_whitespace;
        error_strip_trailing_whitespace =
          r.error_strip_trailing_whitespace;
        command_error_is_fatal = r.command_error_is_fatal }
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
  | ECmakeIncludeDirectories { dirs; before; system } ->
    ECmakeIncludeDirectories
      { dirs = List.map dirs ~f:lift_yelu1_to_yelu2; before; system }
  | ECmakeAddCompileDefinitions defs ->
    ECmakeAddCompileDefinitions (List.map defs ~f:lift_yelu1_to_yelu2)
  | ECmakeAddCompileOptions opts ->
    ECmakeAddCompileOptions (List.map opts ~f:lift_yelu1_to_yelu2)
  | ECmakeAddLinkOptions opts ->
    ECmakeAddLinkOptions (List.map opts ~f:lift_yelu1_to_yelu2)
  | ECmakeAddDefinitions defs ->
    ECmakeAddDefinitions (List.map defs ~f:lift_yelu1_to_yelu2)
  | ECmakeLinkDirectories { dirs; before } ->
    ECmakeLinkDirectories
      { dirs = List.map dirs ~f:lift_yelu1_to_yelu2; before }

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
  | ECmakeSetProperty { targets; append; properties } ->
    ESetProperty
      { targets = List.map targets ~f:lift_yelu1_to_yelu2;
        append;
        properties = List.map properties ~f:(fun (p, v) -> p, lift_yelu1_to_yelu2 v) }
  | ECmakeSetGlobalProperty { properties } ->
    ECmakeSetGlobalProperty
      { properties = List.map properties ~f:(fun (p, v) -> p, lift_yelu1_to_yelu2 v) }
  (* Additional property subcommands — surface-only passthrough. *)
  | ECmakeGetProperty { var; target; property; set_form } ->
    ECmakeGetProperty
      { var; target = lift_yelu1_to_yelu2 target; property; set_form }
  | ECmakeGetDirectoryProperty _ | ECmakeGetGlobalProperty _
  | ECmakeDefineProperty _ as e -> e
  | ECmakeSetDirectoryProperty { property; append; values } ->
    ECmakeSetDirectoryProperty
      { property; append; values = List.map values ~f:lift_yelu1_to_yelu2 }
  | ECmakeSetSourceProperty { file; property; values } ->
    ECmakeSetSourceProperty
      { file = lift_yelu1_to_yelu2 file; property;
        values = List.map values ~f:lift_yelu1_to_yelu2 }

  (* CMake find surface -> Yelu find theory. The cmake-specific
     attributes (version / exact / quiet / config_mode / components /
     optional_components) drop at lift since Yelu2's idealized theory
     doesn't model them; lower fills with conservative defaults. *)
  | ECmakeFindPackage
      { package_name; required;
        version = _; exact = _; quiet = _; config_mode = _;
        components = _; optional_components = _ } ->
    EFindPackage { package_name; required }
  | ECmakeFindLibrary { out; names; paths; hints; required } ->
    ECmakeFindLibrary
      { out;
        names = List.map names ~f:lift_yelu1_to_yelu2;
        paths = List.map paths ~f:lift_yelu1_to_yelu2;
        hints = List.map hints ~f:lift_yelu1_to_yelu2;
        required }
  | ECmakeFindPath { out; names; paths; hints; required } ->
    ECmakeFindPath
      { out;
        names = List.map names ~f:lift_yelu1_to_yelu2;
        paths = List.map paths ~f:lift_yelu1_to_yelu2;
        hints = List.map hints ~f:lift_yelu1_to_yelu2;
        required }
  | ECmakeFindProgram { out; names; paths; hints; required } ->
    ECmakeFindProgram
      { out;
        names = List.map names ~f:lift_yelu1_to_yelu2;
        paths = List.map paths ~f:lift_yelu1_to_yelu2;
        hints = List.map hints ~f:lift_yelu1_to_yelu2;
        required }
  | ECmakeFindFile { out; names; paths; hints; required } ->
    ECmakeFindFile
      { out;
        names = List.map names ~f:lift_yelu1_to_yelu2;
        paths = List.map paths ~f:lift_yelu1_to_yelu2;
        hints = List.map hints ~f:lift_yelu1_to_yelu2;
        required }

  (* CMake try surface -> Yelu try theory. *)
  | ECmakeTryCompile { result_var; sources } ->
    ETryCompile { result_var; sources = List.map sources ~f:lift_yelu1_to_yelu2 }
  | ECmakeTryCompileEx r ->
    ECmakeTryCompileEx
      { result_var = r.result_var;
        sources = List.map r.sources ~f:lift_yelu1_to_yelu2;
        compile_definitions =
          List.map r.compile_definitions ~f:lift_yelu1_to_yelu2;
        link_libraries =
          List.map r.link_libraries ~f:lift_yelu1_to_yelu2;
        link_options =
          List.map r.link_options ~f:lift_yelu1_to_yelu2;
        output_variable = r.output_variable;
        no_cache = r.no_cache;
        c_standard = r.c_standard;
        cxx_standard = r.cxx_standard }
  | ECmakeTryRun r ->
    ECmakeTryRun
      { run_result_var = r.run_result_var;
        compile_result_var = r.compile_result_var;
        sources = List.map r.sources ~f:lift_yelu1_to_yelu2;
        compile_definitions =
          List.map r.compile_definitions ~f:lift_yelu1_to_yelu2;
        link_libraries =
          List.map r.link_libraries ~f:lift_yelu1_to_yelu2;
        compile_output_variable = r.compile_output_variable;
        run_output_variable = r.run_output_variable;
        args = List.map r.args ~f:lift_yelu1_to_yelu2 }
  | _ -> fail "cannot translate unknown Yelu1 expression"
let rec lower_yelu2_to_yelu1 = function
  (* Core/store cases shared by both bundles. *)
  | EVar name -> EVar name
  | EString s -> EString s
  | EBool b -> EBool b
  | EInt n -> EInt n
  | EUnit -> EUnit
  | EUnsetVar name -> ECmakeUnsetVar name
  | ECmakeUnsetVarCache name -> ECmakeUnsetVarCache name
  | ECmakeSetParentScope { name; value } ->
    ECmakeSetParentScope
      { name; value = lower_yelu2_to_yelu1 value }
  | ECmakeSetEnvVar { name; value } ->
    ECmakeSetEnvVar { name; value = lower_yelu2_to_yelu1 value }
  | ECmakeUnsetEnvVar name -> ECmakeUnsetEnvVar name
  | EVarDefined name -> ECmakeVarDefined name
  | ECmakeSetCache { name; values; cache_type; docstring; force } ->
    ECmakeSetCache
      { name;
        values = List.map values ~f:lower_yelu2_to_yelu1;
        cache_type; docstring; force }
  | ECmakeMatches { expr_; regex } ->
    ECmakeMatches { expr_ = lower_yelu2_to_yelu1 expr_; regex }
  | ECmakeInList { item; list_ } ->
    ECmakeInList
      { item = lower_yelu2_to_yelu1 item;
        list_ = lower_yelu2_to_yelu1 list_ }
  | ECmakeIsDirectory path ->
    ECmakeIsDirectory (lower_yelu2_to_yelu1 path)
  | ECmakePolicyCheck p -> ECmakePolicyCheck p

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
            before = false; system = false;
            dirs = List.map dirs ~f:lower_yelu2_to_yelu1 };
        ETarget name;
      ]
  | ETargetIncludeDirectories { target; visibility; dirs } ->
    ECmakeTargetIncludeDirectories
      {
        target = lower_yelu2_to_yelu1 target;
        visibility;
        before = false; system = false;
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
            before = false;
            options_ = List.map options_ ~f:lower_yelu2_to_yelu1;
          };
        ETarget name;
      ]
  | ETargetCompileOptions { target; visibility; options_ } ->
    ECmakeTargetCompileOptions
      {
        target = lower_yelu2_to_yelu1 target;
        visibility;
        before = false;
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
            before = false;
            options_ = List.map options_ ~f:lower_yelu2_to_yelu1;
          };
        ETarget name;
      ]
  | ETargetLinkOptions { target; visibility; options_ } ->
    ECmakeTargetLinkOptions
      {
        target = lower_yelu2_to_yelu1 target;
        visibility;
        before = false;
        options_ = List.map options_ ~f:lower_yelu2_to_yelu1;
      }
  | ETargetLinkDirectories { target = ETarget name; visibility; dirs } ->
    ESeq
      [
        ECmakeTargetLinkDirectories
          {
            target = ETarget name;
            visibility;
            before = false;
            dirs = List.map dirs ~f:lower_yelu2_to_yelu1;
          };
        ETarget name;
      ]
  | ETargetLinkDirectories { target; visibility; dirs } ->
    ECmakeTargetLinkDirectories
      {
        target = lower_yelu2_to_yelu1 target;
        visibility;
        before = false;
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
  | ELibraryAlias { name; target } ->
    ECmakeAddLibraryAlias { name; target }
  | EExecutableAlias { name; target } ->
    ECmakeAddExecutableAlias { name; target }
  | EAddDependencies { target; dep } ->
    ECmakeAddDependencies { target; dep }
  | ELibraryImported { name; lib_type; global } ->
    ECmakeAddLibraryImported
      { name = lower_yelu2_to_yelu1 name; lib_type; global }
  | ETargetSourcesFs { target; items } ->
    let lower_item = function
      | Tsi_plain { visibility; items } ->
        Tsi_plain
          { visibility; items = List.map items ~f:lower_yelu2_to_yelu1 }
      | Tsi_file_set { kind; type_; base_dirs; files } ->
        Tsi_file_set
          { kind; type_;
            base_dirs = List.map base_dirs ~f:lower_yelu2_to_yelu1;
            files = List.map files ~f:lower_yelu2_to_yelu1 }
    in
    ECmakeTargetSourcesFs
      { target = lower_yelu2_to_yelu1 target;
        items = List.map items ~f:lower_item }
  | ETargetPrecompileHeaders { target; visibility; headers } ->
    ECmakeTargetPrecompileHeaders
      { target = lower_yelu2_to_yelu1 target;
        visibility;
        headers = List.map headers ~f:lower_yelu2_to_yelu1 }
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
  (* Additional list() subcommands — surface-only passthrough. *)
  | ECmakeListPrepend { list; items } ->
    ECmakeListPrepend
      { list; items = List.map items ~f:lower_yelu2_to_yelu1 }
  | ECmakeListInsert { list; index; items } ->
    ECmakeListInsert
      { list; index; items = List.map items ~f:lower_yelu2_to_yelu1 }
  | ECmakeListRemoveItem { list; items } ->
    ECmakeListRemoveItem
      { list; items = List.map items ~f:lower_yelu2_to_yelu1 }
  | ECmakeListRemoveAt _ | ECmakeListRemoveDuplicates _
  | ECmakeListReverse _ | ECmakeListSort _ | ECmakeListFilter _
  | ECmakeListSublist _ | ECmakeListPopBack _ | ECmakeListPopFront _
  | ECmakeListTransform _ as e -> e
  | ECmakeListFind { list; value; out } ->
    ECmakeListFind
      { list; value = lower_yelu2_to_yelu1 value; out }

  (* Yelu path theory -> CMake path surface. *)
  | ESetVar (name, EPathFilename (EVar path)) ->
    ECmakePathGetFilename { path; out = name }
  | ESetVar (name, EPathNormalize (EVar path)) when String.equal name path ->
    ECmakePathNormalPath { path; out = None }
  | ESetVar (name, EPathNormalize (EVar path)) ->
    ECmakePathNormalPath { path; out = Some name }
  | ESetVar (name, EPathNormalize expr) ->
    ECmakePathSet { path = name; input = lower_yelu2_to_yelu1 expr; normalize = true }
  (* Generalized cmake_path subcommands: surface-only, passthrough. *)
  | ECmakePathGet _ | ECmakePathHas _
  | ECmakePathIsAbsolute _ | ECmakePathIsRelative _ | ECmakePathIsPrefix _
  | ECmakePathCompare _
  | ECmakePathAppend _ | ECmakePathAppendString _
  | ECmakePathRemoveFilename _ | ECmakePathReplaceFilename _
  | ECmakePathRemoveExtension _ | ECmakePathReplaceExtension _
  | ECmakePathRelativePath _ | ECmakePathAbsolutePath _
  | ECmakePathNativePath _
  | ECmakePathConvertToCmake _ | ECmakePathConvertToNative _
  | ECmakePathHash _ as e -> e

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
  | ECmakeFileRelativePath { var; base; file } ->
    ECmakeFileRelativePath
      { var;
        base = lower_yelu2_to_yelu1 base;
        file = lower_yelu2_to_yelu1 file }
  | ECmakeFileGlob { out; recurse; relative; configure_depends; patterns } ->
    ECmakeFileGlob
      { out; recurse;
        relative = Option.map relative ~f:lower_yelu2_to_yelu1;
        configure_depends;
        patterns = List.map patterns ~f:lower_yelu2_to_yelu1 }
  (* Additional file() subcommands — surface-only passthrough. *)
  | ECmakeFileWriteAppend { path; content } ->
    ECmakeFileWriteAppend
      { path = lower_yelu2_to_yelu1 path;
        content = List.map content ~f:lower_yelu2_to_yelu1 }
  | ECmakeFileReadFull { path; out; offset; limit; hex } ->
    ECmakeFileReadFull
      { path = lower_yelu2_to_yelu1 path; out; offset; limit; hex }
  | ECmakeFileStrings { out; path; regex; encoding; limit_count } ->
    ECmakeFileStrings
      { out; path = lower_yelu2_to_yelu1 path; regex; encoding; limit_count }
  | ECmakeFileTouch { files; nocreate } ->
    ECmakeFileTouch
      { files = List.map files ~f:lower_yelu2_to_yelu1; nocreate }
  | ECmakeFileMakeDirectory { dirs } ->
    ECmakeFileMakeDirectory
      { dirs = List.map dirs ~f:lower_yelu2_to_yelu1 }
  | ECmakeFileRename { old_; new_; result; no_replace } ->
    ECmakeFileRename
      { old_ = lower_yelu2_to_yelu1 old_;
        new_ = lower_yelu2_to_yelu1 new_;
        result; no_replace }
  | ECmakeFileRemove { files; recurse } ->
    ECmakeFileRemove
      { files = List.map files ~f:lower_yelu2_to_yelu1; recurse }
  | ECmakeFileCopy { input; output; result; only_if_different } ->
    ECmakeFileCopy
      { input = lower_yelu2_to_yelu1 input;
        output = lower_yelu2_to_yelu1 output;
        result; only_if_different }
  | ECmakeFileRealPath { out; path; base_dir; expand_tilde } ->
    ECmakeFileRealPath
      { out; path = lower_yelu2_to_yelu1 path;
        base_dir = Option.map base_dir ~f:lower_yelu2_to_yelu1;
        expand_tilde }
  | ECmakeFileSize { out; path } ->
    ECmakeFileSize { out; path = lower_yelu2_to_yelu1 path }
  | ECmakeFileReadSymlink { out; link } ->
    ECmakeFileReadSymlink { out; link = lower_yelu2_to_yelu1 link }
  | ECmakeFileTimestamp { out; path; format; utc } ->
    ECmakeFileTimestamp
      { out; path = lower_yelu2_to_yelu1 path; format; utc }
  | ECmakeStringRegexReplace { regex; replace; out; inputs } ->
    ECmakeStringRegexReplace
      { regex;
        replace = lower_yelu2_to_yelu1 replace;
        out;
        inputs = List.map inputs ~f:lower_yelu2_to_yelu1 }
  (* Additional string() subcommands — surface-only passthrough. *)
  | ECmakeStringTolower { input; out } ->
    ECmakeStringTolower { input = lower_yelu2_to_yelu1 input; out }
  | ECmakeStringStrip { input; out } ->
    ECmakeStringStrip { input = lower_yelu2_to_yelu1 input; out }
  | ECmakeStringRegexMatch { regex; out; inputs } ->
    ECmakeStringRegexMatch
      { regex; out; inputs = List.map inputs ~f:lower_yelu2_to_yelu1 }
  | ECmakeStringRegexMatchAll { regex; out; inputs } ->
    ECmakeStringRegexMatchAll
      { regex; out; inputs = List.map inputs ~f:lower_yelu2_to_yelu1 }
  | ECmakeStringRegexQuote { out; inputs } ->
    ECmakeStringRegexQuote
      { out; inputs = List.map inputs ~f:lower_yelu2_to_yelu1 }
  | ECmakeStringAppend { cvar; inputs } ->
    ECmakeStringAppend
      { cvar; inputs = List.map inputs ~f:lower_yelu2_to_yelu1 }
  | ECmakeStringPrepend { cvar; inputs } ->
    ECmakeStringPrepend
      { cvar; inputs = List.map inputs ~f:lower_yelu2_to_yelu1 }
  | ECmakeStringJoin { glue; out; inputs } ->
    ECmakeStringJoin
      { glue = lower_yelu2_to_yelu1 glue; out;
        inputs = List.map inputs ~f:lower_yelu2_to_yelu1 }
  | ECmakeStringFind { string; substring; out; reverse } ->
    ECmakeStringFind
      { string = lower_yelu2_to_yelu1 string;
        substring = lower_yelu2_to_yelu1 substring; out; reverse }
  | ECmakeStringSubstring { string; begin_; length; out } ->
    ECmakeStringSubstring
      { string = lower_yelu2_to_yelu1 string; begin_; length; out }
  | ECmakeStringRepeat { string; count; out } ->
    ECmakeStringRepeat
      { string = lower_yelu2_to_yelu1 string; count; out }
  | ECmakeStringGenexStrip { input; out } ->
    ECmakeStringGenexStrip { input = lower_yelu2_to_yelu1 input; out }
  | ECmakeStringMakeCIdentifier { input; out } ->
    ECmakeStringMakeCIdentifier { input = lower_yelu2_to_yelu1 input; out }
  | ECmakeStringTimestamp _ as e -> e
  | ECmakeStringHex { input; out } ->
    ECmakeStringHex { input = lower_yelu2_to_yelu1 input; out }
  | ECmakeStringUuid _ as e -> e
  | ECmakeStringCompare { op; string1; string2; out } ->
    ECmakeStringCompare
      { op; string1 = lower_yelu2_to_yelu1 string1;
        string2 = lower_yelu2_to_yelu1 string2; out }
  | ECmakeStringJson { out; error_var; op_name; args } ->
    ECmakeStringJson
      { out; error_var; op_name;
        args = List.map args ~f:lower_yelu2_to_yelu1 }
  | ECmakeGetFilenameComponent { var; filename; mode } ->
    ECmakeGetFilenameComponent
      { var; filename = lower_yelu2_to_yelu1 filename; mode }
  | ECmakeMacro { name; params; body } ->
    ECmakeMacro
      { name = lower_yelu2_to_yelu1 name;
        params;
        body = lower_yelu2_to_yelu1 body }
  | ECmakeForeach { loop_var; items; body } ->
    ECmakeForeach
      { loop_var;
        items = List.map items ~f:lower_yelu2_to_yelu1;
        body = lower_yelu2_to_yelu1 body }
  | ECmakeForeachRange { loop_var; start; stop; step; body } ->
    ECmakeForeachRange
      { loop_var; start; stop; step;
        body = lower_yelu2_to_yelu1 body }
  | ECmakeForeachZip { loop_vars; lists; body } ->
    ECmakeForeachZip
      { loop_vars; lists; body = lower_yelu2_to_yelu1 body }
  | ECmakeForeachInList { loop_var; lists; items; body } ->
    ECmakeForeachInList
      { loop_var; lists;
        items = List.map items ~f:lower_yelu2_to_yelu1;
        body = lower_yelu2_to_yelu1 body }
  | ECmakeSeparateArguments { var; mode; input } ->
    ECmakeSeparateArguments
      { var; mode; input = Option.map input ~f:lower_yelu2_to_yelu1 }
  | ECmakeWhile { cond; body } ->
    ECmakeWhile
      { cond = lower_yelu2_to_yelu1 cond;
        body = lower_yelu2_to_yelu1 body }
  | ECmakeBreak -> ECmakeBreak
  | ECmakeContinue -> ECmakeContinue
  | ECmakeBlock { scope_vars; propagate; body } ->
    ECmakeBlock
      { scope_vars; propagate; body = lower_yelu2_to_yelu1 body }
  | ECmakeReturn { propagate_vars } ->
    ECmakeReturn { propagate_vars }

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
  | ECmakeVersionLess (a, b) ->
    ECmakeVersionLess (lower_yelu2_to_yelu1 a, lower_yelu2_to_yelu1 b)
  | ECmakeVersionGreater (a, b) ->
    ECmakeVersionGreater (lower_yelu2_to_yelu1 a, lower_yelu2_to_yelu1 b)
  | ECmakeVersionEqual (a, b) ->
    ECmakeVersionEqual (lower_yelu2_to_yelu1 a, lower_yelu2_to_yelu1 b)
  | ECmakeVersionLessEqual (a, b) ->
    ECmakeVersionLessEqual (lower_yelu2_to_yelu1 a, lower_yelu2_to_yelu1 b)
  | ECmakeVersionGreaterEqual (a, b) ->
    ECmakeVersionGreaterEqual (lower_yelu2_to_yelu1 a, lower_yelu2_to_yelu1 b)
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
  (* Additional cmake_op subcommands — surface-only passthrough on lower. *)
  | ECmakeEnableLanguage _ | ECmakePolicySet _
  | ECmakeLanguageEval _ | ECmakeLanguageGetLogLevel _
  | ECmakeVariableWatch _ | ECmakeIncludeGuard _
  | ECmakeQuoteCmd _ as e -> e
  | ECmakeLanguageCall { cmd; args } ->
    ECmakeLanguageCall
      { cmd; args = List.map args ~f:lower_yelu2_to_yelu1 }
  | ECmakeExecuteProcess r ->
    ECmakeExecuteProcess
      { commands = List.map r.commands
            ~f:(List.map ~f:lower_yelu2_to_yelu1);
        working_directory =
          Option.map r.working_directory ~f:lower_yelu2_to_yelu1;
        timeout = r.timeout;
        result_variable = r.result_variable;
        output_variable = r.output_variable;
        error_variable = r.error_variable;
        input_file = Option.map r.input_file ~f:lower_yelu2_to_yelu1;
        output_file = Option.map r.output_file ~f:lower_yelu2_to_yelu1;
        error_file = Option.map r.error_file ~f:lower_yelu2_to_yelu1;
        output_quiet = r.output_quiet;
        error_quiet = r.error_quiet;
        output_strip_trailing_whitespace =
          r.output_strip_trailing_whitespace;
        error_strip_trailing_whitespace =
          r.error_strip_trailing_whitespace;
        command_error_is_fatal = r.command_error_is_fatal }

  (* Yelu dir theory -> CMake dir surface. *)
  | EAddSubdirectory path -> ECmakeAddSubdirectory (lower_yelu2_to_yelu1 path)
  | ECmakeIncludeDirectories { dirs; before; system } ->
    ECmakeIncludeDirectories
      { dirs = List.map dirs ~f:lower_yelu2_to_yelu1; before; system }
  | ECmakeAddCompileDefinitions defs ->
    ECmakeAddCompileDefinitions (List.map defs ~f:lower_yelu2_to_yelu1)
  | ECmakeAddCompileOptions opts ->
    ECmakeAddCompileOptions (List.map opts ~f:lower_yelu2_to_yelu1)
  | ECmakeAddLinkOptions opts ->
    ECmakeAddLinkOptions (List.map opts ~f:lower_yelu2_to_yelu1)
  | ECmakeAddDefinitions defs ->
    ECmakeAddDefinitions (List.map defs ~f:lower_yelu2_to_yelu1)
  | ECmakeLinkDirectories { dirs; before } ->
    ECmakeLinkDirectories
      { dirs = List.map dirs ~f:lower_yelu2_to_yelu1; before }

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
  | ESetProperty { targets; append; properties } ->
    ECmakeSetProperty
      { targets = List.map targets ~f:lower_yelu2_to_yelu1;
        append;
        properties = List.map properties ~f:(fun (p, v) -> p, lower_yelu2_to_yelu1 v) }
  | ECmakeSetGlobalProperty { properties } ->
    ECmakeSetGlobalProperty
      { properties = List.map properties ~f:(fun (p, v) -> p, lower_yelu2_to_yelu1 v) }
  (* Additional property subcommands — surface-only passthrough. *)
  | ECmakeGetProperty { var; target; property; set_form } ->
    ECmakeGetProperty
      { var; target = lower_yelu2_to_yelu1 target; property; set_form }
  | ECmakeGetDirectoryProperty _ | ECmakeGetGlobalProperty _
  | ECmakeDefineProperty _ as e -> e
  | ECmakeSetDirectoryProperty { property; append; values } ->
    ECmakeSetDirectoryProperty
      { property; append; values = List.map values ~f:lower_yelu2_to_yelu1 }
  | ECmakeSetSourceProperty { file; property; values } ->
    ECmakeSetSourceProperty
      { file = lower_yelu2_to_yelu1 file; property;
        values = List.map values ~f:lower_yelu2_to_yelu1 }

  (* Yelu find theory -> CMake find surface. *)
  | EFindPackage { package_name; required } ->
    ECmakeFindPackage
      { package_name; required;
        version = None; exact = false; quiet = false; config_mode = false;
        components = []; optional_components = [] }
  | ECmakeFindLibrary { out; names; paths; hints; required } ->
    ECmakeFindLibrary
      { out;
        names = List.map names ~f:lower_yelu2_to_yelu1;
        paths = List.map paths ~f:lower_yelu2_to_yelu1;
        hints = List.map hints ~f:lower_yelu2_to_yelu1;
        required }
  | ECmakeFindPath { out; names; paths; hints; required } ->
    ECmakeFindPath
      { out;
        names = List.map names ~f:lower_yelu2_to_yelu1;
        paths = List.map paths ~f:lower_yelu2_to_yelu1;
        hints = List.map hints ~f:lower_yelu2_to_yelu1;
        required }
  | ECmakeFindProgram { out; names; paths; hints; required } ->
    ECmakeFindProgram
      { out;
        names = List.map names ~f:lower_yelu2_to_yelu1;
        paths = List.map paths ~f:lower_yelu2_to_yelu1;
        hints = List.map hints ~f:lower_yelu2_to_yelu1;
        required }
  | ECmakeFindFile { out; names; paths; hints; required } ->
    ECmakeFindFile
      { out;
        names = List.map names ~f:lower_yelu2_to_yelu1;
        paths = List.map paths ~f:lower_yelu2_to_yelu1;
        hints = List.map hints ~f:lower_yelu2_to_yelu1;
        required }

  (* Yelu try theory -> CMake try surface. *)
  | ETryCompile { result_var; sources } ->
    ECmakeTryCompile
      { result_var; sources = List.map sources ~f:lower_yelu2_to_yelu1 }
  | ECmakeTryCompileEx r ->
    ECmakeTryCompileEx
      { result_var = r.result_var;
        sources = List.map r.sources ~f:lower_yelu2_to_yelu1;
        compile_definitions =
          List.map r.compile_definitions ~f:lower_yelu2_to_yelu1;
        link_libraries =
          List.map r.link_libraries ~f:lower_yelu2_to_yelu1;
        link_options =
          List.map r.link_options ~f:lower_yelu2_to_yelu1;
        output_variable = r.output_variable;
        no_cache = r.no_cache;
        c_standard = r.c_standard;
        cxx_standard = r.cxx_standard }
  | ECmakeTryRun r ->
    ECmakeTryRun
      { run_result_var = r.run_result_var;
        compile_result_var = r.compile_result_var;
        sources = List.map r.sources ~f:lower_yelu2_to_yelu1;
        compile_definitions =
          List.map r.compile_definitions ~f:lower_yelu2_to_yelu1;
        link_libraries =
          List.map r.link_libraries ~f:lower_yelu2_to_yelu1;
        compile_output_variable = r.compile_output_variable;
        run_output_variable = r.run_output_variable;
        args = List.map r.args ~f:lower_yelu2_to_yelu1 }

  | ESetVar (name, expr) -> ESetVar (name, lower_yelu2_to_yelu1 expr)
  | ESeq exprs -> ESeq (List.map exprs ~f:lower_yelu2_to_yelu1)
  | ELet { var; value; body } ->
    ELet
      { var;
        value = lower_yelu2_to_yelu1 value;
        body = lower_yelu2_to_yelu1 body }
  | _ -> fail "cannot translate unknown Yelu2 expression"
