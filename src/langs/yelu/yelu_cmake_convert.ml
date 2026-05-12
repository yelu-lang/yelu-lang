(* Translation between yelu_cmake (CMake-command-faithful form) and
   yelu_cmake_normal (normalized form). Pure syntactic rewrites —
   no env, no eval — they walk the IR replacing each form with its
   counterpart in the other language.

   [to_normal]  : yelu_cmake -> yelu_cmake_normal.
     Each [ECmake*] yelu_cmake form maps to its yelu_cmake_normal
     counterpart. Core nodes (EVar, ESetVar, ESeq, ELet, …) pass
     through with recursion. CMake-specific patterns translate to
     normalized forms (e.g. [ECmakeListAppend] becomes
     [ESetVar (..., EListAppend ...)]).

   [from_normal] : yelu_cmake_normal -> yelu_cmake.
     The reverse rewrite. Has special pattern-matched cases for
     [ESetVar] wrapping common normal-form effects (e.g.
     [ESetVar (out, EStringConcat ...)] becomes
     [ECmakeStringConcat { out; inputs }]).

   The two functions together form an *almost*-roundtrip:
   to_normal then from_normal should produce IR with the same
   observable cmake emission as the original. The roundtrip
   property is exercised by the lift/lower tests in
   [test_yelu_lift_lower.ml] (still using the older "lift_lower"
   identifier names). *)

(* Public surface: short re-export names for the split evaluators so
   that tests and library users don't have to spell out three module
   prefixes for what used to be one combined eval interface. *)
let eval_yelu_cmake_expr env expr = Yelu_cmake_eval.eval_expr env expr
let eval_yelu_cmake_normal_expr env expr = Yelu_cmake_normal_eval.eval_expr env expr

open Base
open Yelu_cmake
open Yelu_cmake_normal_store
open Yelu_cmake_store
open Yelu_cmake_normal_bool
open Yelu_cmake_normal_int
open Yelu_cmake_normal_list
open Yelu_cmake_list
open Yelu_cmake_normal_path
open Yelu_cmake_path
open Yelu_cmake_normal_file
open Yelu_cmake_file
open Yelu_cmake_normal_target
open Yelu_cmake_target
open Yelu_cmake_normal_install
open Yelu_cmake_install
open Yelu_cmake_string
open Yelu_cmake_normal_string
open Yelu_cmake_if
open Yelu_cmake_normal_if
open Yelu_cmake_normal_cmake_op
open Yelu_cmake_cmake_op
open Yelu_cmake_normal_dir
open Yelu_cmake_dir
open Yelu_cmake_normal_test
open Yelu_cmake_test
open Yelu_cmake_normal_property
open Yelu_cmake_property
open Yelu_cmake_normal_find
open Yelu_cmake_find
open Yelu_cmake_normal_try
open Yelu_cmake_try

let rec to_normal = function
  (* Core/store cases shared by both bundles. *)
  | EVar name -> EVar name
  | EString s -> EString s
  | ECmakeGenex s -> ECmakeGenex s
  | EBool b -> EBool b
  | EInt n -> EInt n
  | EUnit -> EUnit
  | ESetVar (name, expr) -> ESetVar (name, to_normal expr)
  | EUnsetVar name -> EUnsetVar name
  | EVarDefined name -> EVarDefined name
  | ESeq exprs -> ESeq (List.map exprs ~f:to_normal)
  | ELet { var; value; body } ->
    ELet
      { var;
        value = to_normal value;
        body = to_normal body }

  (* CMake store surface -> Yelu store theory. *)
  | ECmakeUnsetVar name -> EUnsetVar name
  | ECmakeUnsetVarCache name -> ECmakeUnsetVarCache name
  | ECmakeVarDefined name -> EVarDefined name
  | ECmakeSetParentScope { name; value } ->
    ECmakeSetParentScope
      { name; value = to_normal value }
  | ECmakeSetEnvVar { name; value } ->
    ECmakeSetEnvVar { name; value = to_normal value }
  | ECmakeUnsetEnvVar name -> ECmakeUnsetEnvVar name
  | ECmakeOption { name; value; _ } ->
    ESetVar (name, to_normal value)
  | ECmakeSetCache { name; values; cache_type; docstring; force } ->
    ECmakeSetCache
      { name;
        values = List.map values ~f:to_normal;
        cache_type; docstring; force }
  | ECmakeMatches { expr_; regex } ->
    ECmakeMatches { expr_ = to_normal expr_; regex }
  | ECmakeInList { item; list_ } ->
    ECmakeInList
      { item = to_normal item;
        list_ = to_normal list_ }
  | ECmakeIsDirectory path ->
    ECmakeIsDirectory (to_normal path)
  | ECmakeIsAbsolute path ->
    ECmakeIsAbsolute (to_normal path)
  | ECmakePolicyCheck p -> ECmakePolicyCheck p

  (* Shared bool theory. *)
  | ENot expr -> ENot (to_normal expr)
  | EAnd (left, right) ->
    EAnd (to_normal left, to_normal right)
  | EOr (left, right) ->
    EOr (to_normal left, to_normal right)

  (* Shared int theory. *)
  | EIntAdd (left, right) ->
    EIntAdd (to_normal left, to_normal right)
  | EIntLess (left, right) ->
    EIntLess (to_normal left, to_normal right)
  | EIntEqual (left, right) ->
    EIntEqual (to_normal left, to_normal right)

  (* Shared list theory. *)
  | EList exprs -> EList (List.map exprs ~f:to_normal)
  | EListAppend (list_expr, value_expr) ->
    EListAppend (to_normal list_expr, to_normal value_expr)
  | EListGet (list_expr, index_expr) ->
    EListGet (to_normal list_expr, to_normal index_expr)
  | EListLength expr -> EListLength (to_normal expr)

  (* Shared path theory. *)
  | EPathFilename expr -> EPathFilename (to_normal expr)
  | EPathNormalize expr -> EPathNormalize (to_normal expr)

  (* Shared file theory. *)
  | EFileWrite { path; content } ->
    EFileWrite
      { path = to_normal path; content = to_normal content }
  | EFileRead path -> EFileRead (to_normal path)
  | EFileExists path -> EFileExists (to_normal path)

  (* Shared target theory. *)
  | ETarget name -> ETarget name
  | EExecutable { name; sources } ->
    EExecutable
      { name = to_normal name; sources = List.map sources ~f:to_normal }
  | ELibrary { name; type_; sources } ->
    ELibrary
      {
        name = to_normal name;
        type_;
        sources = List.map sources ~f:to_normal;
      }
  | ETargetExists target -> ETargetExists (to_normal target)
  | ETargetAddSources { target; visibility; sources } ->
    ETargetAddSources
      {
        target = to_normal target;
        visibility;
        sources = List.map sources ~f:to_normal;
      }
  | ETargetLinkLibraries { target; visibility; items } ->
    ETargetLinkLibraries
      {
        target = to_normal target;
        visibility;
        items = List.map items ~f:to_normal;
      }
  | ETargetIncludeDirectories { target; visibility; dirs } ->
    ETargetIncludeDirectories
      {
        target = to_normal target;
        visibility;
        dirs = List.map dirs ~f:to_normal;
      }
  | ETargetCompileDefinitions { target; visibility; definitions } ->
    ETargetCompileDefinitions
      {
        target = to_normal target;
        visibility;
        definitions = List.map definitions ~f:to_normal;
      }
  | ETargetCompileOptions { target; visibility; options_ } ->
    ETargetCompileOptions
      {
        target = to_normal target;
        visibility;
        options_ = List.map options_ ~f:to_normal;
      }
  | ETargetCompileFeatures { target; visibility; features } ->
    ETargetCompileFeatures
      {
        target = to_normal target;
        visibility;
        features = List.map features ~f:to_normal;
      }
  | ETargetLinkOptions { target; visibility; options_ } ->
    ETargetLinkOptions
      {
        target = to_normal target;
        visibility;
        options_ = List.map options_ ~f:to_normal;
      }
  | ETargetLinkDirectories { target; visibility; dirs } ->
    ETargetLinkDirectories
      {
        target = to_normal target;
        visibility;
        dirs = List.map dirs ~f:to_normal;
      }
  | ECustomTarget { name; all; commands; depends; comment } ->
    ECustomTarget
      { name; all; commands; depends = List.map depends ~f:to_normal; comment }
  | ECustomCommand { outputs; commands; depends; comment; verbatim } ->
    ECustomCommand
      {
        outputs = List.map outputs ~f:to_normal;
        commands;
        depends = List.map depends ~f:to_normal;
        comment;
        verbatim;
      }
  | ELibraryAlias { name; target } -> ELibraryAlias { name; target }
  | EExecutableAlias { name; target } -> EExecutableAlias { name; target }
  | EAddDependencies { target; dep } -> EAddDependencies { target; dep }
  | ELibraryImported { name; lib_type; global } ->
    ELibraryImported
      { name = to_normal name; lib_type; global }
  | ETargetSourcesFs { target; items } ->
    let lift_item = function
      | Tsi_plain { visibility; items } ->
        Tsi_plain
          { visibility; items = List.map items ~f:to_normal }
      | Tsi_file_set { kind; type_; base_dirs; files } ->
        Tsi_file_set
          { kind; type_;
            base_dirs = List.map base_dirs ~f:to_normal;
            files = List.map files ~f:to_normal }
    in
    ETargetSourcesFs
      { target = to_normal target;
        items = List.map items ~f:lift_item }
  | ETargetPrecompileHeaders { target; visibility; headers } ->
    ETargetPrecompileHeaders
      { target = to_normal target;
        visibility;
        headers = List.map headers ~f:to_normal }

  (* Shared install theory. *)
  | EInstallTargets { targets; destination; export } ->
    EInstallTargets
      {
        targets = List.map targets ~f:to_normal;
        destination = to_normal destination;
        export = Option.map export ~f:to_normal;
      }
  | EInstallFiles { files; destination } ->
    EInstallFiles
      {
        files = List.map files ~f:to_normal;
        destination = to_normal destination;
      }
  | EInstallExport { export; destination; file; namespace } ->
    EInstallExport
      {
        export = to_normal export;
        destination = to_normal destination;
        file = Option.map file ~f:to_normal;
        namespace;
      }
  | EExportExport { name; file } ->
    EExportExport
      { name = to_normal name;
        file = Option.map file ~f:to_normal }
  | EConfigurePackageConfigFile r ->
    EConfigurePackageConfigFile
      { r with
        install_dest = to_normal r.install_dest;
        input = to_normal r.input;
        output = to_normal r.output }
  | EWriteBasicPackageVersionFile r ->
    EWriteBasicPackageVersionFile
      { r with
        file = to_normal r.file;
        version = Option.map r.version ~f:to_normal }

  (* CMake list surface -> Yelu list/string theories. *)
  | ECmakeListAppend { list; items } ->
    items
    |> List.map ~f:(fun item ->
      ESetVar (list, EListAppend (EVar list, to_normal item)))
    |> ESeq
  | ECmakeListLength { list; out } ->
    ESetVar (out, EListLength (EVar list))
  | ECmakeListGet { list; indices; out } ->
    (* yelu_cmake_normal EListGet takes a single index expr. For multi-index lifts
       we project the first index; semantics-preserving multi-index
       requires a future yelu_cmake_normal ctor. *)
    let i = match indices with
      | [ i ] -> EInt i
      | _ -> EInt 0
    in
    ESetVar (out, EListGet (EVar list, i))
  | ECmakeListJoin { list; glue; out } ->
    ESetVar (out, EStringJoin { sep = to_normal glue; items = EVar list })
  (* Additional list() subcommands — surface-only passthrough. *)
  | ECmakeListPrepend { list; items } ->
    ECmakeListPrepend
      { list; items = List.map items ~f:to_normal }
  | ECmakeListInsert { list; index; items } ->
    ECmakeListInsert
      { list; index; items = List.map items ~f:to_normal }
  | ECmakeListRemoveItem { list; items } ->
    ECmakeListRemoveItem
      { list; items = List.map items ~f:to_normal }
  | ECmakeListRemoveAt _ | ECmakeListRemoveDuplicates _
  | ECmakeListReverse _ | ECmakeListSort _ | ECmakeListFilter _
  | ECmakeListSublist _ | ECmakeListPopBack _ | ECmakeListPopFront _
  | ECmakeListTransform _ as e -> e
  | ECmakeListFind { list; value; out } ->
    ECmakeListFind
      { list; value = to_normal value; out }

  (* CMake path surface -> Yelu path theory. *)
  | ECmakePathSet { path; input; normalize } ->
    ESetVar
      ( path,
        if normalize
        then EPathNormalize (to_normal input)
        else to_normal input )
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
            path = to_normal path;
            content = EStringConcat (List.map content ~f:to_normal);
          };
        EUnit;
      ]
  | ECmakeFileRead { path; out } ->
    ESetVar (out, EFileRead (to_normal path))
  | ECmakeFileExists path ->
    EFileExists (to_normal path)
  | ECmakeConfigureFile { input; output } ->
    EConfigureFile
      { input = to_normal input; output = to_normal output }
  | ECmakeFileRelativePath { var; base; file } ->
    ECmakeFileRelativePath
      { var;
        base = to_normal base;
        file = to_normal file }
  | ECmakeFileGlob { out; recurse; relative; configure_depends; patterns } ->
    ECmakeFileGlob
      { out; recurse;
        relative = Option.map relative ~f:to_normal;
        configure_depends;
        patterns = List.map patterns ~f:to_normal }
  (* Additional file() subcommands — surface-only passthrough. *)
  | ECmakeFileWriteAppend { path; content } ->
    ECmakeFileWriteAppend
      { path = to_normal path;
        content = List.map content ~f:to_normal }
  | ECmakeFileReadFull { path; out; offset; limit; hex } ->
    ECmakeFileReadFull
      { path = to_normal path; out; offset; limit; hex }
  | ECmakeFileStrings { out; path; regex; encoding; limit_count } ->
    ECmakeFileStrings
      { out; path = to_normal path; regex; encoding; limit_count }
  | ECmakeFileTouch { files; nocreate } ->
    ECmakeFileTouch
      { files = List.map files ~f:to_normal; nocreate }
  | ECmakeFileMakeDirectory { dirs } ->
    ECmakeFileMakeDirectory
      { dirs = List.map dirs ~f:to_normal }
  | ECmakeFileRename { old_; new_; result; no_replace } ->
    ECmakeFileRename
      { old_ = to_normal old_;
        new_ = to_normal new_;
        result; no_replace }
  | ECmakeFileRemove { files; recurse } ->
    ECmakeFileRemove
      { files = List.map files ~f:to_normal; recurse }
  | ECmakeFileCopy { input; output; result; only_if_different } ->
    ECmakeFileCopy
      { input = to_normal input;
        output = to_normal output;
        result; only_if_different }
  | ECmakeFileRealPath { out; path; base_dir; expand_tilde } ->
    ECmakeFileRealPath
      { out; path = to_normal path;
        base_dir = Option.map base_dir ~f:to_normal;
        expand_tilde }
  | ECmakeFileSize { out; path } ->
    ECmakeFileSize { out; path = to_normal path }
  | ECmakeFileReadSymlink { out; link } ->
    ECmakeFileReadSymlink { out; link = to_normal link }
  | ECmakeFileTimestamp { out; path; format; utc } ->
    ECmakeFileTimestamp
      { out; path = to_normal path; format; utc }
  | ECmakeStringRegexReplace { regex; replace; out; inputs } ->
    ECmakeStringRegexReplace
      { regex;
        replace = to_normal replace;
        out;
        inputs = List.map inputs ~f:to_normal }
  (* Additional string() subcommands — surface-only passthrough. *)
  | ECmakeStringTolower { input; out } ->
    ECmakeStringTolower { input = to_normal input; out }
  | ECmakeStringStrip { input; out } ->
    ECmakeStringStrip { input = to_normal input; out }
  | ECmakeStringRegexMatch { regex; out; inputs } ->
    ECmakeStringRegexMatch
      { regex; out; inputs = List.map inputs ~f:to_normal }
  | ECmakeStringRegexMatchAll { regex; out; inputs } ->
    ECmakeStringRegexMatchAll
      { regex; out; inputs = List.map inputs ~f:to_normal }
  | ECmakeStringRegexQuote { out; inputs } ->
    ECmakeStringRegexQuote
      { out; inputs = List.map inputs ~f:to_normal }
  | ECmakeStringAppend { cvar; inputs } ->
    ECmakeStringAppend
      { cvar; inputs = List.map inputs ~f:to_normal }
  | ECmakeStringPrepend { cvar; inputs } ->
    ECmakeStringPrepend
      { cvar; inputs = List.map inputs ~f:to_normal }
  | ECmakeStringJoin { glue; out; inputs } ->
    ECmakeStringJoin
      { glue = to_normal glue; out;
        inputs = List.map inputs ~f:to_normal }
  | ECmakeStringFind { string; substring; out; reverse } ->
    ECmakeStringFind
      { string = to_normal string;
        substring = to_normal substring; out; reverse }
  | ECmakeStringSubstring { string; begin_; length; out } ->
    ECmakeStringSubstring
      { string = to_normal string; begin_; length; out }
  | ECmakeStringRepeat { string; count; out } ->
    ECmakeStringRepeat
      { string = to_normal string; count; out }
  | ECmakeStringGenexStrip { input; out } ->
    ECmakeStringGenexStrip { input = to_normal input; out }
  | ECmakeStringMakeCIdentifier { input; out } ->
    ECmakeStringMakeCIdentifier { input = to_normal input; out }
  | ECmakeStringTimestamp _ as e -> e
  | ECmakeStringHex { input; out } ->
    ECmakeStringHex { input = to_normal input; out }
  | ECmakeStringUuid _ as e -> e
  | ECmakeStringCompare { op; string1; string2; out } ->
    ECmakeStringCompare
      { op; string1 = to_normal string1;
        string2 = to_normal string2; out }
  | ECmakeStringJson { out; error_var; op_name; args } ->
    ECmakeStringJson
      { out; error_var; op_name;
        args = List.map args ~f:to_normal }
  | ECmakeGetFilenameComponent { var; filename; mode } ->
    ECmakeGetFilenameComponent
      { var; filename = to_normal filename; mode }
  | ECmakeMacro { name; params; body } ->
    ECmakeMacro
      { name = to_normal name;
        params;
        body = to_normal body }
  | ECmakeForeach { loop_var; items; body } ->
    ECmakeForeach
      { loop_var;
        items = List.map items ~f:to_normal;
        body = to_normal body }
  | ECmakeForeachRange { loop_var; start; stop; step; body } ->
    ECmakeForeachRange
      { loop_var; start; stop; step;
        body = to_normal body }
  | ECmakeForeachZip { loop_vars; lists; body } ->
    ECmakeForeachZip
      { loop_vars; lists; body = to_normal body }
  | ECmakeForeachInList { loop_var; lists; items; body } ->
    ECmakeForeachInList
      { loop_var; lists;
        items = List.map items ~f:to_normal;
        body = to_normal body }
  | ECmakeSeparateArguments { var; mode; input } ->
    ECmakeSeparateArguments
      { var; mode; input = Option.map input ~f:to_normal }
  | ECmakeWhile { cond; body } ->
    ECmakeWhile
      { cond = to_normal cond;
        body = to_normal body }
  | ECmakeBreak -> ECmakeBreak
  | ECmakeContinue -> ECmakeContinue
  | ECmakeBlock { scope_vars; propagate; body } ->
    ECmakeBlock
      { scope_vars; propagate; body = to_normal body }
  | ECmakeReturn { propagate_vars } ->
    ECmakeReturn { propagate_vars }

  (* CMake target surface -> Yelu target theory. Keep statement result as unit.
     Phase 2b: surface target-name fields are now [expr], so [lift] just
     recurses (no more EString wrapping). *)
  | ECmakeAddExecutable { name; sources } ->
    ESeq
      [
        EExecutable
          { name = to_normal name;
            sources = List.map sources ~f:to_normal };
        EUnit;
      ]
  | ECmakeAddLibrary { name; type_; sources } ->
    ESeq
      [
        ELibrary
          {
            name = to_normal name;
            type_;
            sources = List.map sources ~f:to_normal;
          };
        EUnit;
      ]
  | ECmakeTargetSources { target; visibility; sources } ->
    ESeq
      [
        ETargetAddSources
          { target = to_normal target;
            visibility;
            sources = List.map sources ~f:to_normal };
        EUnit;
      ]
  | ECmakeTargetLinkLibraries { target; visibility; items } ->
    ESeq
      [
        ETargetLinkLibraries
          { target = to_normal target;
            visibility;
            items = List.map items ~f:to_normal };
        EUnit;
      ]
  | ECmakeTargetIncludeDirectories
      { target; visibility; before = _; system = _; dirs } ->
    (* yelu_cmake_normal theory drops cmake-specific BEFORE / SYSTEM flags; the
       round-trip preserves them only via the yelu_cmake surface, which is
       where they belong. Lower fills with [false] (the legacy default). *)
    ESeq
      [
        ETargetIncludeDirectories
          { target = to_normal target;
            visibility;
            dirs = List.map dirs ~f:to_normal };
        EUnit;
      ]
  | ECmakeTargetCompileDefinitions { target; visibility; definitions } ->
    ESeq
      [
        ETargetCompileDefinitions
          {
            target = to_normal target;
            visibility;
            definitions = List.map definitions ~f:to_normal;
          };
        EUnit;
      ]
  | ECmakeTargetCompileOptions { target; visibility; before = _; options_ } ->
    ESeq
      [
        ETargetCompileOptions
          {
            target = to_normal target;
            visibility;
            options_ = List.map options_ ~f:to_normal;
          };
        EUnit;
      ]
  | ECmakeTargetCompileFeatures { target; visibility; features } ->
    ESeq
      [
        ETargetCompileFeatures
          {
            target = to_normal target;
            visibility;
            features = List.map features ~f:to_normal;
          };
        EUnit;
      ]
  | ECmakeTargetLinkOptions { target; visibility; before = _; options_ } ->
    ESeq
      [
        ETargetLinkOptions
          {
            target = to_normal target;
            visibility;
            options_ = List.map options_ ~f:to_normal;
          };
        EUnit;
      ]
  | ECmakeTargetLinkDirectories { target; visibility; before = _; dirs } ->
    ESeq
      [
        ETargetLinkDirectories
          {
            target = to_normal target;
            visibility;
            dirs = List.map dirs ~f:to_normal;
          };
        EUnit;
      ]
  | ECmakeAddCustomTarget { name; all; commands; depends; comment } ->
    ESeq
      [
        ECustomTarget
          { name = to_normal name;
            all;
            commands;
            depends = List.map depends ~f:to_normal;
            comment };
        EUnit;
      ]
  | ECmakeAddCustomCommand { outputs; commands; depends; comment; verbatim } ->
    ESeq
      [
        ECustomCommand
          {
            outputs = List.map outputs ~f:to_normal;
            commands;
            depends = List.map depends ~f:to_normal;
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
      { name = to_normal name; lib_type; global }
  | ECmakeTargetSourcesFs { target; items } ->
    let lift_item = function
      | Tsi_plain { visibility; items } ->
        Tsi_plain
          { visibility; items = List.map items ~f:to_normal }
      | Tsi_file_set { kind; type_; base_dirs; files } ->
        Tsi_file_set
          { kind; type_;
            base_dirs = List.map base_dirs ~f:to_normal;
            files = List.map files ~f:to_normal }
    in
    ETargetSourcesFs
      { target = to_normal target;
        items = List.map items ~f:lift_item }
  | ECmakeTargetPrecompileHeaders { target; visibility; headers } ->
    ETargetPrecompileHeaders
      { target = to_normal target;
        visibility;
        headers = List.map headers ~f:to_normal }
  | ECmakeInstallTargets { targets; destination; export } ->
    ESeq
      [
        EInstallTargets
          {
            targets = List.map targets ~f:to_normal;
            destination = to_normal destination;
            export = Option.map export ~f:to_normal;
          };
        EUnit;
      ]
  | ECmakeInstallFiles { files; destination } ->
    ESeq
      [
        EInstallFiles
          {
            files = List.map files ~f:to_normal;
            destination = to_normal destination;
          };
        EUnit;
      ]
  | ECmakeInstallExport { export; destination; file; namespace } ->
    EInstallExport
      {
        export = to_normal export;
        destination = to_normal destination;
        file = Option.map file ~f:to_normal;
        namespace;
      }
  | ECmakeExportExport { name; file } ->
    EExportExport
      { name = to_normal name;
        file = Option.map file ~f:to_normal }
  | ECmakeConfigurePackageConfigFile r ->
    EConfigurePackageConfigFile
      { install_dest = to_normal r.install_dest;
        input = to_normal r.input;
        output = to_normal r.output;
        no_set_and_check_macro = r.no_set_and_check_macro;
        no_check_required_components_macro = r.no_check_required_components_macro }
  | ECmakeWriteBasicPackageVersionFile r ->
    EWriteBasicPackageVersionFile
      { file = to_normal r.file;
        version = Option.map r.version ~f:to_normal;
        compatibility = r.compatibility;
        arch_independent = r.arch_independent }
  | ECmakeTargetExists target ->
    ETargetExists (to_normal target)

  (* CMake string surface -> Yelu string theory. *)
  | ECmakeStringEqual (left, right) ->
    EStringEqual (to_normal left, to_normal right)
  | ECmakeVersionLess (a, b) ->
    ECmakeVersionLess (to_normal a, to_normal b)
  | ECmakeVersionGreater (a, b) ->
    ECmakeVersionGreater (to_normal a, to_normal b)
  | ECmakeVersionEqual (a, b) ->
    ECmakeVersionEqual (to_normal a, to_normal b)
  | ECmakeVersionLessEqual (a, b) ->
    ECmakeVersionLessEqual (to_normal a, to_normal b)
  | ECmakeVersionGreaterEqual (a, b) ->
    ECmakeVersionGreaterEqual (to_normal a, to_normal b)
  | ECmakeMath { exp; out } -> ECmakeMath { exp; out }
  (* Additional cmake_op subcommands — surface-only passthrough. *)
  | ECmakeEnableLanguage _ | ECmakePolicySet _
  | ECmakeLanguageEval _ | ECmakeLanguageGetLogLevel _
  | ECmakeVariableWatch _ | ECmakeIncludeGuard _
  | ECmakeQuoteCmd _ as e -> e
  | ECmakeLanguageCall { cmd; args } ->
    ECmakeLanguageCall
      { cmd; args = List.map args ~f:to_normal }
  | ECmakeExecuteProcess r ->
    ECmakeExecuteProcess
      { commands = List.map r.commands
            ~f:(List.map ~f:to_normal);
        working_directory =
          Option.map r.working_directory ~f:to_normal;
        timeout = r.timeout;
        result_variable = r.result_variable;
        output_variable = r.output_variable;
        error_variable = r.error_variable;
        input_file = Option.map r.input_file ~f:to_normal;
        output_file = Option.map r.output_file ~f:to_normal;
        error_file = Option.map r.error_file ~f:to_normal;
        output_quiet = r.output_quiet;
        error_quiet = r.error_quiet;
        output_strip_trailing_whitespace =
          r.output_strip_trailing_whitespace;
        error_strip_trailing_whitespace =
          r.error_strip_trailing_whitespace;
        command_error_is_fatal = r.command_error_is_fatal }
  | ECmakeStringConcat { inputs; out } ->
    ESetVar (out, EStringConcat (List.map inputs ~f:to_normal))
  | ECmakeStringToupper { input; out } ->
    ESetVar (out, EStringUpper (to_normal input))
  | ECmakeStringReplace { match_; replace; input; out } ->
    ESetVar
      ( out,
        EStringReplaceAll
          {
            needle = to_normal match_;
            replacement = to_normal replace;
            haystack = to_normal input;
          } )
  | ECmakeStringLength { input; out } ->
    ESetVar (out, EStringLen (to_normal input))

  (* CMake if surface -> Yelu if theory. *)
  | ECmakeIfStmt { cond; then_; else_ } ->
    EIfExpr
      {
        cond = to_normal cond;
        then_ = to_normal then_;
        else_ =
          (match else_ with
           | Some else_ -> to_normal else_
           | None -> EUnit);
      }

  (* CMake cmake_op surface -> Yelu cmake_op theory. *)
  | ECmakeProject { name; languages; version } ->
    EProject { name; languages; version }
  | ECmakeMinimumRequired version -> EMinVersion version
  | ECmakeMessage { mode; texts } ->
    EMessage { mode; texts = List.map texts ~f:to_normal }
  | ECmakeFunction { name; params; body } ->
    EDynFunction
      {
        name = to_normal name;
        params;
        body = to_normal body;
      }
  | ECmakeApply { name; args } ->
    EApply
      {
        name = to_normal name;
        args = List.map args ~f:to_normal;
      }
  | ECmakeInclude { file; optional } ->
    EInclude { file = to_normal file; optional }
  | ECmakeAtVar key -> EAtVar key

  (* CMake dir surface -> Yelu dir theory. *)
  | ECmakeAddSubdirectory path -> EAddSubdirectory (to_normal path)
  | ECmakeIncludeDirectories { dirs; before; system } ->
    ECmakeIncludeDirectories
      { dirs = List.map dirs ~f:to_normal; before; system }
  | ECmakeAddCompileDefinitions defs ->
    ECmakeAddCompileDefinitions (List.map defs ~f:to_normal)
  | ECmakeAddCompileOptions opts ->
    ECmakeAddCompileOptions (List.map opts ~f:to_normal)
  | ECmakeAddLinkOptions opts ->
    ECmakeAddLinkOptions (List.map opts ~f:to_normal)
  | ECmakeAddDefinitions defs ->
    ECmakeAddDefinitions (List.map defs ~f:to_normal)
  | ECmakeLinkDirectories { dirs; before } ->
    ECmakeLinkDirectories
      { dirs = List.map dirs ~f:to_normal; before }

  (* CMake test surface -> Yelu test theory. *)
  | ECmakeEnableTesting -> EEnableTesting
  | ECmakeAddTest { name; command; args } ->
    EAddTest
      {
        name = to_normal name;
        command = to_normal command;
        args = List.map args ~f:to_normal;
      }

  (* CMake property surface -> Yelu property theory. *)
  | ECmakeSetTargetProperty { target; property; value } ->
    ESetTargetProperty
      { target = to_normal target;
        property;
        value = to_normal value }
  | ECmakeGetTargetProperty { var; target; property } ->
    EGetTargetProperty
      { var; target = to_normal target; property }
  | ECmakeSetTestsProperties { tests; properties } ->
    ESetTestsProperties
      {
        tests = List.map tests ~f:to_normal;
        properties =
          List.map properties ~f:(fun (property, value) ->
            property, to_normal value);
      }
  | ECmakeSetProperty { targets; append; properties } ->
    ESetProperty
      { targets = List.map targets ~f:to_normal;
        append;
        properties = List.map properties ~f:(fun (p, v) -> p, to_normal v) }
  | ECmakeSetGlobalProperty { properties } ->
    ECmakeSetGlobalProperty
      { properties = List.map properties ~f:(fun (p, v) -> p, to_normal v) }
  (* Additional property subcommands — surface-only passthrough. *)
  | ECmakeGetProperty { var; target; property; set_form } ->
    ECmakeGetProperty
      { var; target = to_normal target; property; set_form }
  | ECmakeGetDirectoryProperty _ | ECmakeGetGlobalProperty _
  | ECmakeDefineProperty _ as e -> e
  | ECmakeSetDirectoryProperty { property; append; values } ->
    ECmakeSetDirectoryProperty
      { property; append; values = List.map values ~f:to_normal }
  | ECmakeSetSourceProperty { file; property; values } ->
    ECmakeSetSourceProperty
      { file = to_normal file; property;
        values = List.map values ~f:to_normal }

  (* CMake find surface -> Yelu find theory. The cmake-specific
     attributes (version / exact / quiet / config_mode / components /
     optional_components) drop at lift since yelu_cmake_normal's idealized theory
     doesn't model them; lower fills with conservative defaults. *)
  | ECmakeFindPackage
      { package_name; required;
        version = _; exact = _; quiet = _; config_mode = _;
        components = _; optional_components = _ } ->
    EFindPackage { package_name; required }
  | ECmakeFindLibrary { out; names; paths; hints; required } ->
    ECmakeFindLibrary
      { out;
        names = List.map names ~f:to_normal;
        paths = List.map paths ~f:to_normal;
        hints = List.map hints ~f:to_normal;
        required }
  | ECmakeFindPath { out; names; paths; hints; required } ->
    ECmakeFindPath
      { out;
        names = List.map names ~f:to_normal;
        paths = List.map paths ~f:to_normal;
        hints = List.map hints ~f:to_normal;
        required }
  | ECmakeFindProgram { out; names; paths; hints; required } ->
    ECmakeFindProgram
      { out;
        names = List.map names ~f:to_normal;
        paths = List.map paths ~f:to_normal;
        hints = List.map hints ~f:to_normal;
        required }
  | ECmakeFindFile { out; names; paths; hints; required } ->
    ECmakeFindFile
      { out;
        names = List.map names ~f:to_normal;
        paths = List.map paths ~f:to_normal;
        hints = List.map hints ~f:to_normal;
        required }

  (* CMake try surface -> Yelu try theory. *)
  | ECmakeTryCompile { result_var; sources } ->
    ETryCompile { result_var; sources = List.map sources ~f:to_normal }
  | ECmakeTryCompileEx r ->
    ECmakeTryCompileEx
      { result_var = r.result_var;
        sources = List.map r.sources ~f:to_normal;
        compile_definitions =
          List.map r.compile_definitions ~f:to_normal;
        link_libraries =
          List.map r.link_libraries ~f:to_normal;
        link_options =
          List.map r.link_options ~f:to_normal;
        output_variable = r.output_variable;
        no_cache = r.no_cache;
        c_standard = r.c_standard;
        cxx_standard = r.cxx_standard }
  | ECmakeTryRun r ->
    ECmakeTryRun
      { run_result_var = r.run_result_var;
        compile_result_var = r.compile_result_var;
        sources = List.map r.sources ~f:to_normal;
        compile_definitions =
          List.map r.compile_definitions ~f:to_normal;
        link_libraries =
          List.map r.link_libraries ~f:to_normal;
        compile_output_variable = r.compile_output_variable;
        run_output_variable = r.run_output_variable;
        args = List.map r.args ~f:to_normal }
  | _ -> fail "cannot translate unknown yelu_cmake expression"
let rec from_normal = function
  (* Core/store cases shared by both bundles. *)
  | EVar name -> EVar name
  | EString s -> EString s
  | ECmakeGenex s -> ECmakeGenex s
  | EBool b -> EBool b
  | EInt n -> EInt n
  | EUnit -> EUnit
  | EUnsetVar name -> ECmakeUnsetVar name
  | ECmakeUnsetVarCache name -> ECmakeUnsetVarCache name
  | ECmakeSetParentScope { name; value } ->
    ECmakeSetParentScope
      { name; value = from_normal value }
  | ECmakeSetEnvVar { name; value } ->
    ECmakeSetEnvVar { name; value = from_normal value }
  | ECmakeUnsetEnvVar name -> ECmakeUnsetEnvVar name
  | EVarDefined name -> ECmakeVarDefined name
  | ECmakeSetCache { name; values; cache_type; docstring; force } ->
    ECmakeSetCache
      { name;
        values = List.map values ~f:from_normal;
        cache_type; docstring; force }
  | ECmakeMatches { expr_; regex } ->
    ECmakeMatches { expr_ = from_normal expr_; regex }
  | ECmakeInList { item; list_ } ->
    ECmakeInList
      { item = from_normal item;
        list_ = from_normal list_ }
  | ECmakeIsDirectory path ->
    ECmakeIsDirectory (from_normal path)
  | ECmakeIsAbsolute path ->
    ECmakeIsAbsolute (from_normal path)
  | ECmakePolicyCheck p -> ECmakePolicyCheck p

  (* Shared bool theory. *)
  | ENot expr -> ENot (from_normal expr)
  | EAnd (left, right) ->
    EAnd (from_normal left, from_normal right)
  | EOr (left, right) ->
    EOr (from_normal left, from_normal right)

  (* Shared int theory. *)
  | EIntAdd (left, right) ->
    EIntAdd (from_normal left, from_normal right)
  | EIntLess (left, right) ->
    EIntLess (from_normal left, from_normal right)
  | EIntEqual (left, right) ->
    EIntEqual (from_normal left, from_normal right)

  (* Shared list theory. *)
  | EList exprs -> EList (List.map exprs ~f:from_normal)
  | EListAppend (list_expr, value_expr) ->
    EListAppend (from_normal list_expr, from_normal value_expr)
  | EListGet (list_expr, index_expr) ->
    EListGet (from_normal list_expr, from_normal index_expr)
  | EListLength expr -> EListLength (from_normal expr)

  (* Shared path theory. *)
  | EPathFilename expr -> EPathFilename (from_normal expr)
  | EPathNormalize expr -> EPathNormalize (from_normal expr)

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
            sources = List.map sources ~f:from_normal };
        ETarget target_name;
      ]
  | EExecutable { name; sources } ->
    ECmakeAddExecutable
      { name = from_normal name;
        sources = List.map sources ~f:from_normal }
  | ELibrary { name = EString target_name; type_; sources } ->
    ESeq
      [
        ECmakeAddLibrary
          { name = EString target_name;
            type_;
            sources = List.map sources ~f:from_normal };
        ETarget target_name;
      ]
  | ELibrary { name; type_; sources } ->
    ECmakeAddLibrary
      {
        name = from_normal name;
        type_;
        sources = List.map sources ~f:from_normal;
      }
  | ETargetExists target ->
    ECmakeTargetExists (from_normal target)
  | ETargetAddSources { target = ETarget name; visibility; sources } ->
    ESeq
      [
        ECmakeTargetSources
          { target = ETarget name;
            visibility;
            sources = List.map sources ~f:from_normal };
        ETarget name;
      ]
  | ETargetAddSources { target; visibility; sources } ->
    ECmakeTargetSources
      {
        target = from_normal target;
        visibility;
        sources = List.map sources ~f:from_normal;
      }
  | ETargetLinkLibraries { target = ETarget name; visibility; items } ->
    ESeq
      [
        ECmakeTargetLinkLibraries
          { target = ETarget name;
            visibility;
            items = List.map items ~f:from_normal };
        ETarget name;
      ]
  | ETargetLinkLibraries { target; visibility; items } ->
    ECmakeTargetLinkLibraries
      {
        target = from_normal target;
        visibility;
        items = List.map items ~f:from_normal;
      }
  | ETargetIncludeDirectories { target = ETarget name; visibility; dirs } ->
    ESeq
      [
        ECmakeTargetIncludeDirectories
          { target = ETarget name;
            visibility;
            before = false; system = false;
            dirs = List.map dirs ~f:from_normal };
        ETarget name;
      ]
  | ETargetIncludeDirectories { target; visibility; dirs } ->
    ECmakeTargetIncludeDirectories
      {
        target = from_normal target;
        visibility;
        before = false; system = false;
        dirs = List.map dirs ~f:from_normal;
      }
  | ETargetCompileDefinitions { target = ETarget name; visibility; definitions } ->
    ESeq
      [
        ECmakeTargetCompileDefinitions
          {
            target = ETarget name;
            visibility;
            definitions = List.map definitions ~f:from_normal;
          };
        ETarget name;
      ]
  | ETargetCompileDefinitions { target; visibility; definitions } ->
    ECmakeTargetCompileDefinitions
      {
        target = from_normal target;
        visibility;
        definitions = List.map definitions ~f:from_normal;
      }
  | ETargetCompileOptions { target = ETarget name; visibility; options_ } ->
    ESeq
      [
        ECmakeTargetCompileOptions
          {
            target = ETarget name;
            visibility;
            before = false;
            options_ = List.map options_ ~f:from_normal;
          };
        ETarget name;
      ]
  | ETargetCompileOptions { target; visibility; options_ } ->
    ECmakeTargetCompileOptions
      {
        target = from_normal target;
        visibility;
        before = false;
        options_ = List.map options_ ~f:from_normal;
      }
  | ETargetCompileFeatures { target = ETarget name; visibility; features } ->
    ESeq
      [
        ECmakeTargetCompileFeatures
          {
            target = ETarget name;
            visibility;
            features = List.map features ~f:from_normal;
          };
        ETarget name;
      ]
  | ETargetCompileFeatures { target; visibility; features } ->
    ECmakeTargetCompileFeatures
      {
        target = from_normal target;
        visibility;
        features = List.map features ~f:from_normal;
      }
  | ETargetLinkOptions { target = ETarget name; visibility; options_ } ->
    ESeq
      [
        ECmakeTargetLinkOptions
          {
            target = ETarget name;
            visibility;
            before = false;
            options_ = List.map options_ ~f:from_normal;
          };
        ETarget name;
      ]
  | ETargetLinkOptions { target; visibility; options_ } ->
    ECmakeTargetLinkOptions
      {
        target = from_normal target;
        visibility;
        before = false;
        options_ = List.map options_ ~f:from_normal;
      }
  | ETargetLinkDirectories { target = ETarget name; visibility; dirs } ->
    ESeq
      [
        ECmakeTargetLinkDirectories
          {
            target = ETarget name;
            visibility;
            before = false;
            dirs = List.map dirs ~f:from_normal;
          };
        ETarget name;
      ]
  | ETargetLinkDirectories { target; visibility; dirs } ->
    ECmakeTargetLinkDirectories
      {
        target = from_normal target;
        visibility;
        before = false;
        dirs = List.map dirs ~f:from_normal;
      }
  | ECustomTarget { name; all; commands; depends; comment } ->
    ECmakeAddCustomTarget
      { name = from_normal name;
        all;
        commands;
        depends = List.map depends ~f:from_normal;
        comment }
  | ECustomCommand { outputs; commands; depends; comment; verbatim } ->
    ECmakeAddCustomCommand
      {
        outputs = List.map outputs ~f:from_normal;
        commands;
        depends = List.map depends ~f:from_normal;
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
      { name = from_normal name; lib_type; global }
  | ETargetSourcesFs { target; items } ->
    let lower_item = function
      | Tsi_plain { visibility; items } ->
        Tsi_plain
          { visibility; items = List.map items ~f:from_normal }
      | Tsi_file_set { kind; type_; base_dirs; files } ->
        Tsi_file_set
          { kind; type_;
            base_dirs = List.map base_dirs ~f:from_normal;
            files = List.map files ~f:from_normal }
    in
    ECmakeTargetSourcesFs
      { target = from_normal target;
        items = List.map items ~f:lower_item }
  | ETargetPrecompileHeaders { target; visibility; headers } ->
    ECmakeTargetPrecompileHeaders
      { target = from_normal target;
        visibility;
        headers = List.map headers ~f:from_normal }
  | EInstallTargets { targets; destination; export } ->
    ECmakeInstallTargets
      {
        targets = List.map targets ~f:from_normal;
        destination = from_normal destination;
        export = Option.map export ~f:from_normal;
      }
  | EInstallFiles { files; destination } ->
    ECmakeInstallFiles
      {
        files = List.map files ~f:from_normal;
        destination = from_normal destination;
      }
  | EInstallExport { export; destination; file; namespace } ->
    ECmakeInstallExport
      {
        export = from_normal export;
        destination = from_normal destination;
        file = Option.map file ~f:from_normal;
        namespace;
      }
  | EExportExport { name; file } ->
    ECmakeExportExport
      { name = from_normal name;
        file = Option.map file ~f:from_normal }
  | EConfigurePackageConfigFile r ->
    ECmakeConfigurePackageConfigFile
      { install_dest = from_normal r.install_dest;
        input = from_normal r.input;
        output = from_normal r.output;
        no_set_and_check_macro = r.no_set_and_check_macro;
        no_check_required_components_macro = r.no_check_required_components_macro }
  | EWriteBasicPackageVersionFile r ->
    ECmakeWriteBasicPackageVersionFile
      { file = from_normal r.file;
        version = Option.map r.version ~f:from_normal;
        compatibility = r.compatibility;
        arch_independent = r.arch_independent }

  (* Yelu list/string theories -> CMake list surface. *)
  | ESetVar (name, EListAppend (EVar list, item)) when String.equal name list ->
    ECmakeListAppend { list; items = [ from_normal item ] }
  | ESetVar (name, EListLength (EVar list)) ->
    ECmakeListLength { list; out = name }
  | ESetVar (name, EListGet (EVar list, index)) ->
    let indices = match index with
      | EInt i -> [ i ]
      | _ -> [ 0 ]
    in
    ECmakeListGet { list; indices; out = name }
  | ESetVar (name, EStringJoin { sep; items = EVar list }) ->
    ECmakeListJoin { list; glue = from_normal sep; out = name }
  (* Additional list() subcommands — surface-only passthrough. *)
  | ECmakeListPrepend { list; items } ->
    ECmakeListPrepend
      { list; items = List.map items ~f:from_normal }
  | ECmakeListInsert { list; index; items } ->
    ECmakeListInsert
      { list; index; items = List.map items ~f:from_normal }
  | ECmakeListRemoveItem { list; items } ->
    ECmakeListRemoveItem
      { list; items = List.map items ~f:from_normal }
  | ECmakeListRemoveAt _ | ECmakeListRemoveDuplicates _
  | ECmakeListReverse _ | ECmakeListSort _ | ECmakeListFilter _
  | ECmakeListSublist _ | ECmakeListPopBack _ | ECmakeListPopFront _
  | ECmakeListTransform _ as e -> e
  | ECmakeListFind { list; value; out } ->
    ECmakeListFind
      { list; value = from_normal value; out }

  (* Yelu path theory -> CMake path surface. *)
  | ESetVar (name, EPathFilename (EVar path)) ->
    ECmakePathGetFilename { path; out = name }
  | ESetVar (name, EPathNormalize (EVar path)) when String.equal name path ->
    ECmakePathNormalPath { path; out = None }
  | ESetVar (name, EPathNormalize (EVar path)) ->
    ECmakePathNormalPath { path; out = Some name }
  | ESetVar (name, EPathNormalize expr) ->
    ECmakePathSet { path = name; input = from_normal expr; normalize = true }
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
      { path = from_normal path; content = [ from_normal content ] }
  | ESetVar (name, EFileRead path) ->
    ECmakeFileRead { path = from_normal path; out = name }
  | EFileExists path ->
    ECmakeFileExists (from_normal path)
  | EConfigureFile { input; output } ->
    ECmakeConfigureFile
      { input = from_normal input; output = from_normal output }
  | ECmakeFileRelativePath { var; base; file } ->
    ECmakeFileRelativePath
      { var;
        base = from_normal base;
        file = from_normal file }
  | ECmakeFileGlob { out; recurse; relative; configure_depends; patterns } ->
    ECmakeFileGlob
      { out; recurse;
        relative = Option.map relative ~f:from_normal;
        configure_depends;
        patterns = List.map patterns ~f:from_normal }
  (* Additional file() subcommands — surface-only passthrough. *)
  | ECmakeFileWriteAppend { path; content } ->
    ECmakeFileWriteAppend
      { path = from_normal path;
        content = List.map content ~f:from_normal }
  | ECmakeFileReadFull { path; out; offset; limit; hex } ->
    ECmakeFileReadFull
      { path = from_normal path; out; offset; limit; hex }
  | ECmakeFileStrings { out; path; regex; encoding; limit_count } ->
    ECmakeFileStrings
      { out; path = from_normal path; regex; encoding; limit_count }
  | ECmakeFileTouch { files; nocreate } ->
    ECmakeFileTouch
      { files = List.map files ~f:from_normal; nocreate }
  | ECmakeFileMakeDirectory { dirs } ->
    ECmakeFileMakeDirectory
      { dirs = List.map dirs ~f:from_normal }
  | ECmakeFileRename { old_; new_; result; no_replace } ->
    ECmakeFileRename
      { old_ = from_normal old_;
        new_ = from_normal new_;
        result; no_replace }
  | ECmakeFileRemove { files; recurse } ->
    ECmakeFileRemove
      { files = List.map files ~f:from_normal; recurse }
  | ECmakeFileCopy { input; output; result; only_if_different } ->
    ECmakeFileCopy
      { input = from_normal input;
        output = from_normal output;
        result; only_if_different }
  | ECmakeFileRealPath { out; path; base_dir; expand_tilde } ->
    ECmakeFileRealPath
      { out; path = from_normal path;
        base_dir = Option.map base_dir ~f:from_normal;
        expand_tilde }
  | ECmakeFileSize { out; path } ->
    ECmakeFileSize { out; path = from_normal path }
  | ECmakeFileReadSymlink { out; link } ->
    ECmakeFileReadSymlink { out; link = from_normal link }
  | ECmakeFileTimestamp { out; path; format; utc } ->
    ECmakeFileTimestamp
      { out; path = from_normal path; format; utc }
  | ECmakeStringRegexReplace { regex; replace; out; inputs } ->
    ECmakeStringRegexReplace
      { regex;
        replace = from_normal replace;
        out;
        inputs = List.map inputs ~f:from_normal }
  (* Additional string() subcommands — surface-only passthrough. *)
  | ECmakeStringTolower { input; out } ->
    ECmakeStringTolower { input = from_normal input; out }
  | ECmakeStringStrip { input; out } ->
    ECmakeStringStrip { input = from_normal input; out }
  | ECmakeStringRegexMatch { regex; out; inputs } ->
    ECmakeStringRegexMatch
      { regex; out; inputs = List.map inputs ~f:from_normal }
  | ECmakeStringRegexMatchAll { regex; out; inputs } ->
    ECmakeStringRegexMatchAll
      { regex; out; inputs = List.map inputs ~f:from_normal }
  | ECmakeStringRegexQuote { out; inputs } ->
    ECmakeStringRegexQuote
      { out; inputs = List.map inputs ~f:from_normal }
  | ECmakeStringAppend { cvar; inputs } ->
    ECmakeStringAppend
      { cvar; inputs = List.map inputs ~f:from_normal }
  | ECmakeStringPrepend { cvar; inputs } ->
    ECmakeStringPrepend
      { cvar; inputs = List.map inputs ~f:from_normal }
  | ECmakeStringJoin { glue; out; inputs } ->
    ECmakeStringJoin
      { glue = from_normal glue; out;
        inputs = List.map inputs ~f:from_normal }
  | ECmakeStringFind { string; substring; out; reverse } ->
    ECmakeStringFind
      { string = from_normal string;
        substring = from_normal substring; out; reverse }
  | ECmakeStringSubstring { string; begin_; length; out } ->
    ECmakeStringSubstring
      { string = from_normal string; begin_; length; out }
  | ECmakeStringRepeat { string; count; out } ->
    ECmakeStringRepeat
      { string = from_normal string; count; out }
  | ECmakeStringGenexStrip { input; out } ->
    ECmakeStringGenexStrip { input = from_normal input; out }
  | ECmakeStringMakeCIdentifier { input; out } ->
    ECmakeStringMakeCIdentifier { input = from_normal input; out }
  | ECmakeStringTimestamp _ as e -> e
  | ECmakeStringHex { input; out } ->
    ECmakeStringHex { input = from_normal input; out }
  | ECmakeStringUuid _ as e -> e
  | ECmakeStringCompare { op; string1; string2; out } ->
    ECmakeStringCompare
      { op; string1 = from_normal string1;
        string2 = from_normal string2; out }
  | ECmakeStringJson { out; error_var; op_name; args } ->
    ECmakeStringJson
      { out; error_var; op_name;
        args = List.map args ~f:from_normal }
  | ECmakeGetFilenameComponent { var; filename; mode } ->
    ECmakeGetFilenameComponent
      { var; filename = from_normal filename; mode }
  | ECmakeMacro { name; params; body } ->
    ECmakeMacro
      { name = from_normal name;
        params;
        body = from_normal body }
  | ECmakeForeach { loop_var; items; body } ->
    ECmakeForeach
      { loop_var;
        items = List.map items ~f:from_normal;
        body = from_normal body }
  | ECmakeForeachRange { loop_var; start; stop; step; body } ->
    ECmakeForeachRange
      { loop_var; start; stop; step;
        body = from_normal body }
  | ECmakeForeachZip { loop_vars; lists; body } ->
    ECmakeForeachZip
      { loop_vars; lists; body = from_normal body }
  | ECmakeForeachInList { loop_var; lists; items; body } ->
    ECmakeForeachInList
      { loop_var; lists;
        items = List.map items ~f:from_normal;
        body = from_normal body }
  | ECmakeSeparateArguments { var; mode; input } ->
    ECmakeSeparateArguments
      { var; mode; input = Option.map input ~f:from_normal }
  | ECmakeWhile { cond; body } ->
    ECmakeWhile
      { cond = from_normal cond;
        body = from_normal body }
  | ECmakeBreak -> ECmakeBreak
  | ECmakeContinue -> ECmakeContinue
  | ECmakeBlock { scope_vars; propagate; body } ->
    ECmakeBlock
      { scope_vars; propagate; body = from_normal body }
  | ECmakeReturn { propagate_vars } ->
    ECmakeReturn { propagate_vars }

  (* Yelu target theory -> CMake target surface. *)
  | ESetVar (var, EExecutable { name = EString target_name; sources }) ->
    ESeq
      [
        ECmakeAddExecutable
          { name = EString target_name;
            sources = List.map sources ~f:from_normal };
        ESetVar (var, ETarget target_name);
      ]
  | ESetVar (var, ELibrary { name = EString target_name; type_; sources }) ->
    ESeq
      [
        ECmakeAddLibrary
          { name = EString target_name;
            type_;
            sources = List.map sources ~f:from_normal };
        ESetVar (var, ETarget target_name);
      ]

  (* Yelu string theory -> CMake string surface. *)
  | EStringEqual (left, right) ->
    ECmakeStringEqual (from_normal left, from_normal right)
  | ECmakeVersionLess (a, b) ->
    ECmakeVersionLess (from_normal a, from_normal b)
  | ECmakeVersionGreater (a, b) ->
    ECmakeVersionGreater (from_normal a, from_normal b)
  | ECmakeVersionEqual (a, b) ->
    ECmakeVersionEqual (from_normal a, from_normal b)
  | ECmakeVersionLessEqual (a, b) ->
    ECmakeVersionLessEqual (from_normal a, from_normal b)
  | ECmakeVersionGreaterEqual (a, b) ->
    ECmakeVersionGreaterEqual (from_normal a, from_normal b)
  | ESetVar (name, EStringConcat exprs) ->
    ECmakeStringConcat { inputs = List.map exprs ~f:from_normal; out = name }
  | ESetVar (name, EStringUpper expr) ->
    ECmakeStringToupper { input = from_normal expr; out = name }
  | ESetVar (name, EStringReplaceAll { needle; replacement; haystack }) ->
    ECmakeStringReplace
      {
        match_ = from_normal needle;
        replace = from_normal replacement;
        input = from_normal haystack;
        out = name;
      }
  | ESetVar (name, EStringLen expr) ->
    ECmakeStringLength { input = from_normal expr; out = name }
  | ESetVar (name, EStringJoin { sep; items }) ->
    ESetVar
      ( name,
        EStringJoin
          { sep = from_normal sep; items = from_normal items } )

  (* Bundle-level if/store interaction: a value-producing Yelu if saved to a
     name lowers to a statement-style CMake if whose branches save that name. *)
  | ESetVar (name, EIfExpr { cond; then_; else_ }) ->
    ECmakeIfStmt
      {
        cond = from_normal cond;
        then_ = from_normal (ESetVar (name, then_));
        else_ = Some (from_normal (ESetVar (name, else_)));
      }

  (* Yelu if theory -> CMake if surface. This is valid when branch expressions
     already lower to effectful/unit-shaped CMake surface expressions. *)
  | EIfExpr { cond; then_; else_ } ->
    ECmakeIfStmt
      {
        cond = from_normal cond;
        then_ = from_normal then_;
        else_ = Some (from_normal else_);
      }

  (* Yelu cmake_op theory -> CMake cmake_op surface. *)
  | EProject { name; languages; version } ->
    ECmakeProject { name; languages; version }
  | EMinVersion version -> ECmakeMinimumRequired version
  | EMessage { mode; texts } ->
    ECmakeMessage { mode; texts = List.map texts ~f:from_normal }
  | EDynFunction { name; params; body } ->
    ECmakeFunction
      {
        name = from_normal name;
        params;
        body = from_normal body;
      }
  | EApply { name; args } ->
    ECmakeApply
      {
        name = from_normal name;
        args = List.map args ~f:from_normal;
      }
  | EInclude { file; optional } ->
    ECmakeInclude { file = from_normal file; optional }
  | EAtVar key -> ECmakeAtVar key
  (* Additional cmake_op subcommands — surface-only passthrough on lower. *)
  | ECmakeEnableLanguage _ | ECmakePolicySet _
  | ECmakeLanguageEval _ | ECmakeLanguageGetLogLevel _
  | ECmakeVariableWatch _ | ECmakeIncludeGuard _
  | ECmakeQuoteCmd _ as e -> e
  | ECmakeLanguageCall { cmd; args } ->
    ECmakeLanguageCall
      { cmd; args = List.map args ~f:from_normal }
  | ECmakeExecuteProcess r ->
    ECmakeExecuteProcess
      { commands = List.map r.commands
            ~f:(List.map ~f:from_normal);
        working_directory =
          Option.map r.working_directory ~f:from_normal;
        timeout = r.timeout;
        result_variable = r.result_variable;
        output_variable = r.output_variable;
        error_variable = r.error_variable;
        input_file = Option.map r.input_file ~f:from_normal;
        output_file = Option.map r.output_file ~f:from_normal;
        error_file = Option.map r.error_file ~f:from_normal;
        output_quiet = r.output_quiet;
        error_quiet = r.error_quiet;
        output_strip_trailing_whitespace =
          r.output_strip_trailing_whitespace;
        error_strip_trailing_whitespace =
          r.error_strip_trailing_whitespace;
        command_error_is_fatal = r.command_error_is_fatal }

  (* Yelu dir theory -> CMake dir surface. *)
  | EAddSubdirectory path -> ECmakeAddSubdirectory (from_normal path)
  | ECmakeIncludeDirectories { dirs; before; system } ->
    ECmakeIncludeDirectories
      { dirs = List.map dirs ~f:from_normal; before; system }
  | ECmakeAddCompileDefinitions defs ->
    ECmakeAddCompileDefinitions (List.map defs ~f:from_normal)
  | ECmakeAddCompileOptions opts ->
    ECmakeAddCompileOptions (List.map opts ~f:from_normal)
  | ECmakeAddLinkOptions opts ->
    ECmakeAddLinkOptions (List.map opts ~f:from_normal)
  | ECmakeAddDefinitions defs ->
    ECmakeAddDefinitions (List.map defs ~f:from_normal)
  | ECmakeLinkDirectories { dirs; before } ->
    ECmakeLinkDirectories
      { dirs = List.map dirs ~f:from_normal; before }

  (* Yelu test theory -> CMake test surface. *)
  | EEnableTesting -> ECmakeEnableTesting
  | EAddTest { name; command; args } ->
    ECmakeAddTest
      {
        name = from_normal name;
        command = from_normal command;
        args = List.map args ~f:from_normal;
      }

  (* Yelu property theory -> CMake property surface. *)
  | ESetTargetProperty { target; property; value } ->
    ECmakeSetTargetProperty
      { target = from_normal target;
        property;
        value = from_normal value }
  | EGetTargetProperty { var; target; property } ->
    ECmakeGetTargetProperty
      { var; target = from_normal target; property }
  | ESetTestsProperties { tests; properties } ->
    ECmakeSetTestsProperties
      {
        tests = List.map tests ~f:from_normal;
        properties =
          List.map properties ~f:(fun (property, value) ->
            property, from_normal value);
      }
  | ESetProperty { targets; append; properties } ->
    ECmakeSetProperty
      { targets = List.map targets ~f:from_normal;
        append;
        properties = List.map properties ~f:(fun (p, v) -> p, from_normal v) }
  | ECmakeSetGlobalProperty { properties } ->
    ECmakeSetGlobalProperty
      { properties = List.map properties ~f:(fun (p, v) -> p, from_normal v) }
  (* Additional property subcommands — surface-only passthrough. *)
  | ECmakeGetProperty { var; target; property; set_form } ->
    ECmakeGetProperty
      { var; target = from_normal target; property; set_form }
  | ECmakeGetDirectoryProperty _ | ECmakeGetGlobalProperty _
  | ECmakeDefineProperty _ as e -> e
  | ECmakeSetDirectoryProperty { property; append; values } ->
    ECmakeSetDirectoryProperty
      { property; append; values = List.map values ~f:from_normal }
  | ECmakeSetSourceProperty { file; property; values } ->
    ECmakeSetSourceProperty
      { file = from_normal file; property;
        values = List.map values ~f:from_normal }

  (* Yelu find theory -> CMake find surface. *)
  | EFindPackage { package_name; required } ->
    ECmakeFindPackage
      { package_name; required;
        version = None; exact = false; quiet = false; config_mode = false;
        components = []; optional_components = [] }
  | ECmakeFindLibrary { out; names; paths; hints; required } ->
    ECmakeFindLibrary
      { out;
        names = List.map names ~f:from_normal;
        paths = List.map paths ~f:from_normal;
        hints = List.map hints ~f:from_normal;
        required }
  | ECmakeFindPath { out; names; paths; hints; required } ->
    ECmakeFindPath
      { out;
        names = List.map names ~f:from_normal;
        paths = List.map paths ~f:from_normal;
        hints = List.map hints ~f:from_normal;
        required }
  | ECmakeFindProgram { out; names; paths; hints; required } ->
    ECmakeFindProgram
      { out;
        names = List.map names ~f:from_normal;
        paths = List.map paths ~f:from_normal;
        hints = List.map hints ~f:from_normal;
        required }
  | ECmakeFindFile { out; names; paths; hints; required } ->
    ECmakeFindFile
      { out;
        names = List.map names ~f:from_normal;
        paths = List.map paths ~f:from_normal;
        hints = List.map hints ~f:from_normal;
        required }

  (* Yelu try theory -> CMake try surface. *)
  | ETryCompile { result_var; sources } ->
    ECmakeTryCompile
      { result_var; sources = List.map sources ~f:from_normal }
  | ECmakeTryCompileEx r ->
    ECmakeTryCompileEx
      { result_var = r.result_var;
        sources = List.map r.sources ~f:from_normal;
        compile_definitions =
          List.map r.compile_definitions ~f:from_normal;
        link_libraries =
          List.map r.link_libraries ~f:from_normal;
        link_options =
          List.map r.link_options ~f:from_normal;
        output_variable = r.output_variable;
        no_cache = r.no_cache;
        c_standard = r.c_standard;
        cxx_standard = r.cxx_standard }
  | ECmakeTryRun r ->
    ECmakeTryRun
      { run_result_var = r.run_result_var;
        compile_result_var = r.compile_result_var;
        sources = List.map r.sources ~f:from_normal;
        compile_definitions =
          List.map r.compile_definitions ~f:from_normal;
        link_libraries =
          List.map r.link_libraries ~f:from_normal;
        compile_output_variable = r.compile_output_variable;
        run_output_variable = r.run_output_variable;
        args = List.map r.args ~f:from_normal }

  | ESetVar (name, expr) -> ESetVar (name, from_normal expr)
  | ESeq exprs -> ESeq (List.map exprs ~f:from_normal)
  | ELet { var; value; body } ->
    ELet
      { var;
        value = from_normal value;
        body = from_normal body }
  | _ -> fail "cannot translate unknown yelu_cmake_normal expression"
