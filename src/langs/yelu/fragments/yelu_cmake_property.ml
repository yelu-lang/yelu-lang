open Base
open Yelu_cmake
open Yelu_cmake_normal_target

let name = "tiny_cmake_property"
let requires = [ "core.string"; "target" ]
let provides =
  [ "property.set_target"; "property.get_target"; "property.set_tests";
    "property.set_property" ]

(* Scope sum for [set_property] — one-to-one with Lang_cmake.set_property_scope
   but carrying yc [expr] payloads (vs cmake's resolved string/arg). *)
type set_property_scope =
  | Sps_global
  | Sps_directory of expr option                  (* DIRECTORY [<dir>] *)
  | Sps_target of expr list                       (* TARGET <t>... *)
  | Sps_source of {
      sources : expr list;
      directories : expr list;                    (* DIRECTORY <d>... *)
      target_directories : expr list;             (* TARGET_DIRECTORY <t>... *)
    }
  | Sps_install of expr list                      (* INSTALL <f>... *)
  | Sps_test of { tests : expr list; directories : expr list }
  | Sps_cache of expr list                        (* CACHE <e>... *)

(* Scope sum for [get_property] — mirrors Lang_cmake.get_property_scope.
   Differences vs set_property: single-name per scope (not list), plus the
   extra VARIABLE scope for reading scope-less yc variables as properties. *)
type get_property_scope =
  | Gps_global
  | Gps_directory of expr option                  (* DIRECTORY [<dir>] *)
  | Gps_target of expr                            (* TARGET <t> *)
  | Gps_source of {
      source : expr;
      directory : expr option;                    (* DIRECTORY <d> *)
      target_directory : expr option;             (* TARGET_DIRECTORY <t> *)
    }
  | Gps_install of expr                           (* INSTALL <f> *)
  | Gps_test of { test : expr; directory : expr option }
  | Gps_cache of expr                             (* CACHE <e> *)
  | Gps_variable                                  (* VARIABLE — unique to get *)

(* Output mode of get_property — mirrors Lang_cmake.get_property_mode.
   Default is Gpm_value (the property's value); other modes return TRUE/FALSE
   depending on whether the property is set/defined/has docstrings. *)
type get_property_mode =
  | Gpm_value         (* default — emit value *)
  | Gpm_set           (* SET *)
  | Gpm_defined       (* DEFINED *)
  | Gpm_brief_docs    (* BRIEF_DOCS *)
  | Gpm_full_docs     (* FULL_DOCS *)

type expr +=
  | ECmakeSetTargetProperty of { target : expr; property : string; value : expr }
  | ECmakeGetTargetProperty of { var : string; target : expr; property : string }
  | ECmakeSetTestsProperties of {
      tests : expr list;
      properties : (string * expr) list;
    }
  (* Unified [set_property] — mirrors Lang_cmake.Set_property exactly.
     The 4-way constructor split (TARGET/SOURCE/CACHE/GLOBAL) collapsed
     2026-06-13: it carried no compile-time constraint that a [scope] field
     doesn't, and adding [append_string] / DIRECTORY / INSTALL / TEST scopes
     became a 4-way fan-out. The scope sum mirrors the cmake AST's
     [set_property_scope] one-to-one. Eval still discriminates on scope (only
     TARGET has real semantics today). *)
  | ECmakeSetProperty of {
      scope : set_property_scope;
      append : bool;
      append_string : bool;
      properties : (string * expr) list;
    }
  (* Unified [get_property] — mirrors Lang_cmake.Get_property exactly.
     The legacy TARGET-only / single-bool shape collapsed 2026-06-14 in
     parallel with the set_property unification (see
     doc/lang/object_value_design.md). Pos3 entity dispatch produces the
     scope sum; the mode enum replaces the prior [set_form : bool]. *)
  | ECmakeGetProperty of {
      var : string;
      scope : get_property_scope;
      property : string;
      mode : get_property_mode;
    }
  | ECmakeGetDirectoryProperty of { var : string; property : string }
  | ECmakeSetDirectoryProperty of {
      property : string; append : bool; values : expr list
    }
  | ECmakeSetSourceProperty of {
      file : expr; property : string; values : expr list
    }
  | ECmakeSetSourceFilesProperties of {
      files : expr list;
      properties : (string * expr) list;
    }
  | ECmakeGetGlobalProperty of { var : string; property : string }
  | ECmakeDefineProperty of {
      mode : string; property_name : string; inherited : bool;
      brief_docs : string list; full_docs : string list;
      initialize_from : string option;
    }

let eval_case ~eval env = function
  | ECmakeSetTargetProperty { target; property; value } ->
    let env, target = eval_string ~eval env target in
    let env, value = eval_string ~eval env value in
    Some (set_target_property env ~target ~property ~value, VUnit)
  | ECmakeGetTargetProperty { var; target; property } ->
    let env, target = eval_string ~eval env target in
    let value =
      match find_target_property env ~target ~property with
      | Some v -> v
      | None -> property ^ "-NOTFOUND"
    in
    Some (set_var env ~key:var ~data:(VString value), VUnit)
  | ECmakeSetTestsProperties _ -> Some (env, VUnit)
  | ECmakeSetProperty { scope; append = _; append_string = _; properties } ->
    (* Only TARGET scope has real eval semantics today; the other scopes
       (GLOBAL/DIRECTORY/SOURCE/INSTALL/TEST/CACHE) are eval-stubs because
       no env models those property bags. Preserves prior behavior. *)
    (match scope with
     | Sps_target targets ->
       let env, targets = eval_string_list ~eval env targets in
       let env =
         List.fold targets ~init:env ~f:(fun env target ->
           List.fold properties ~init:env ~f:(fun env (property, value) ->
             let env, value = eval_string ~eval env value in
             set_target_property env ~target ~property ~value))
       in
       Some (env, VUnit)
     | Sps_global | Sps_directory _ | Sps_source _
     | Sps_install _ | Sps_test _ | Sps_cache _ -> Some (env, VUnit))
  | ECmakeGetProperty { var; _ }
  | ECmakeGetDirectoryProperty { var; _ }
  | ECmakeGetGlobalProperty { var; _ } ->
    Some (set_var env ~key:var ~data:(VString ""), VUnit)
  | ECmakeSetDirectoryProperty _ | ECmakeSetSourceProperty _
  | ECmakeDefineProperty _ ->
    Some (env, VUnit)
  | _ -> None
