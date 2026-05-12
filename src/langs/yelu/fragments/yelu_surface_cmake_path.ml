open Base
open Yelu_cmake

let name = "tiny_cmake_path"
let requires = [ "core.string" ]
let provides = [ "path.set"; "path.filename"; "path.normalize" ]

type expr +=
  | ECmakePathSet of { path : string; input : expr; normalize : bool }
  | ECmakePathGetFilename of { path : string; out : string }
  | ECmakePathNormalPath of { path : string; out : string option }
  (* [get_filename_component(<var> <filename> <mode>)] — older cmake API.
     Mode is PATH / NAME / EXT / NAME_WE / DIRECTORY / ABSOLUTE / REALPATH.
     Eval stub: binds [var] to [filename] string (no actual path
     decomposition); cmake handles the real semantics at configure time. *)
  | ECmakeGetFilenameComponent of {
      var : string;
      filename : expr;
      mode : string;
    }
  (* Generalized cmake_path subcommands. The [field] / [op] strings carry
     the cmake keyword tokens directly (e.g. "ROOT_NAME", "EXTENSION LAST_ONLY",
     "EQUAL"). All eval cases are stubs at this slice — cmake resolves
     them at configure time. Out-var-optional cases write back to [path]
     when [out] is [None]. *)
  | ECmakePathGet of { path : string; field : string; out : string }
  | ECmakePathHas of { path : string; field : string; out : string }
  | ECmakePathIsAbsolute of { path : string; out : string }
  | ECmakePathIsRelative of { path : string; out : string }
  | ECmakePathIsPrefix of {
      path : string; input : expr; normalize : bool; out : string
    }
  | ECmakePathCompare of {
      input1 : expr; op : string; input2 : expr; out : string
    }
  | ECmakePathAppend of {
      path : string; inputs : expr list; out : string option
    }
  | ECmakePathAppendString of {
      path : string; inputs : expr list; out : string option
    }
  | ECmakePathRemoveFilename of { path : string; out : string option }
  | ECmakePathReplaceFilename of {
      path : string; input : expr; out : string option
    }
  | ECmakePathRemoveExtension of {
      path : string; last_only : bool; out : string option
    }
  | ECmakePathReplaceExtension of {
      path : string; last_only : bool; input : expr; out : string option
    }
  | ECmakePathRelativePath of {
      path : string; base_dir : expr option; out : string option
    }
  | ECmakePathAbsolutePath of {
      path : string;
      base_dir : expr option;
      normalize : bool;
      out : string option;
    }
  | ECmakePathNativePath of {
      path : string; normalize : bool; out : string
    }
  | ECmakePathConvertToCmake of {
      input : expr; normalize : bool; out : string
    }
  | ECmakePathConvertToNative of {
      input : expr; normalize : bool; out : string
    }
  | ECmakePathHash of { path : string; out : string }

let eval_string ~eval env expr =
  let env, value = eval env expr in
  env, expect_string value

let path_value env name =
  match find_var env name with
  | Some value -> expect_string value
  | None -> fail "unbound path variable %S" name

let eval_case ~eval env = function
  | ECmakePathSet { path; input; normalize = should_normalize } ->
    let env, input = eval_string ~eval env input in
    let data =
      VString (if should_normalize then Yelu_theory_path.normalize input else input)
    in
    Some (set_var env ~key:path ~data, VUnit)
  | ECmakePathGetFilename { path; out } ->
    Some
      ( set_var env ~key:out ~data:(VString (Yelu_theory_path.filename (path_value env path))),
        VUnit )
  | ECmakePathNormalPath { path; out } ->
    let normalized = VString (Yelu_theory_path.normalize (path_value env path)) in
    let key = Option.value out ~default:path in
    Some (set_var env ~key ~data:normalized, VUnit)
  | ECmakeGetFilenameComponent { var; filename; mode = _ } ->
    let env, filename = eval_string ~eval env filename in
    Some (set_var env ~key:var ~data:(VString filename), VUnit)
  (* New cmake_path subcommands — eval-stub for all. Each binds the
     output variable to a placeholder string ("" or the input string),
     leaving real path semantics to cmake at configure time. The
     emitted cmake faithfully renders the subcommand. *)
  | ECmakePathGet { path; field = _; out } ->
    Some (set_var env ~key:out ~data:(VString (path_value env path)), VUnit)
  | ECmakePathHas { out; _ } ->
    Some (set_var env ~key:out ~data:(VBool false), VUnit)
  | ECmakePathIsAbsolute { out; _ }
  | ECmakePathIsRelative { out; _ }
  | ECmakePathIsPrefix { out; _ } ->
    Some (set_var env ~key:out ~data:(VBool false), VUnit)
  | ECmakePathCompare { out; _ } ->
    Some (set_var env ~key:out ~data:(VBool false), VUnit)
  | ECmakePathAppend { path; out; _ }
  | ECmakePathAppendString { path; out; _ }
  | ECmakePathRemoveFilename { path; out; _ }
  | ECmakePathReplaceFilename { path; out; _ }
  | ECmakePathRemoveExtension { path; out; _ }
  | ECmakePathReplaceExtension { path; out; _ }
  | ECmakePathRelativePath { path; out; _ }
  | ECmakePathAbsolutePath { path; out; _ } ->
    let key = Option.value out ~default:path in
    Some (set_var env ~key ~data:(VString (path_value env path)), VUnit)
  | ECmakePathNativePath { path; out; _ } ->
    Some (set_var env ~key:out ~data:(VString (path_value env path)), VUnit)
  | ECmakePathConvertToCmake { out; _ }
  | ECmakePathConvertToNative { out; _ } ->
    Some (set_var env ~key:out ~data:(VString ""), VUnit)
  | ECmakePathHash { out; _ } ->
    Some (set_var env ~key:out ~data:(VString ""), VUnit)
  | _ -> None
