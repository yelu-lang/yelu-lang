open Base
open Lang_yelu_type

(* cmake_path operations: pure path manipulation (GET/HAS/APPEND/...).
   File IO (file(READ/WRITE/...)) lives in lang_yelu_file.ml.
   path_var inputs are T.var — not checkable via type_of (see yelu_typed_design.md). *)

module Make_path_op (T : LANG_TYPES) = struct
  type yelu_path_stmt =
    | Ypath_get of {
        path_var : T.var;
        field : Lang_cmake.cmake_path_get_field;
        out : T.var;
      }
    | Ypath_has of {
        path_var : T.var;
        field : Lang_cmake.cmake_path_has_field;
        out : T.var;
      }
    | Ypath_is_absolute of { path_var : T.var; out : T.var }
    | Ypath_is_relative of { path_var : T.var; out : T.var }
    | Ypath_is_prefix of {
        path_var : T.var;
        input : T.expr;
        normalize : bool;
        out : T.var;
      }
    | Ypath_compare of {
        input1 : T.expr;
        op : Lang_cmake.cmake_path_compare_op;
        input2 : T.expr;
        out : T.var;
      }
    | Ypath_set of { path_var : T.var; input : T.expr; normalize : bool }
    | Ypath_append of {
        path_var : T.var;
        inputs : T.expr list;
        out : T.var option;
      }
    | Ypath_append_string of {
        path_var : T.var;
        inputs : T.expr list;
        out : T.var option;
      }
    | Ypath_remove_filename of { path_var : T.var; out : T.var option }
    | Ypath_replace_filename of {
        path_var : T.var;
        input : T.expr;
        out : T.var option;
      }
    | Ypath_remove_extension of {
        path_var : T.var;
        last_only : bool;
        out : T.var option;
      }
    | Ypath_replace_extension of {
        path_var : T.var;
        last_only : bool;
        input : T.expr;
        out : T.var option;
      }
    | Ypath_normal_path of { path_var : T.var; out : T.var option }
    | Ypath_relative_path of {
        path_var : T.var;
        base_dir : T.expr option;
        out : T.var option;
      }
    | Ypath_absolute_path of {
        path_var : T.var;
        base_dir : T.expr option;
        normalize : bool;
        out : T.var option;
      }
    | Ypath_native_path of { path_var : T.var; normalize : bool; out : T.var }
    | Ypath_convert_to_cmake of {
        input : T.expr;
        normalize : bool;
        out : T.var;
      }
    | Ypath_convert_to_native of {
        input : T.expr;
        normalize : bool;
        out : T.var;
      }
    | Ypath_hash of { path_var : T.var; out : T.var }
    | Ypath_get_filename_component of {
        var : T.var;
        filename : T.expr;
        mode : string;
      }
end

module Make_path_check (T : LANG_TYPES) = struct
  include Make_path_op (T)
  let stage = Stage_typecheck

  let check ~(type_of : T.expr -> yelu_type)
      : yelu_path_stmt -> type_error list * (T.var * yelu_type) list =
    let path e ctx = check_compat ~context:ctx Ty_path (type_of e) in
    let paths es ctx = List.concat_map es ~f:(fun e -> path e ctx) in
    let opt_path e ctx = Option.value_map e ~default:[] ~f:(fun x -> path x ctx) in
    let opt_out v ty = Option.to_list (Option.map v ~f:(fun x -> (x, ty))) in
    function
    | Ypath_get { out; _ } -> [], [(out, Ty_path)]
    | Ypath_has { out; _ } -> [], [(out, Ty_bool)]
    | Ypath_is_absolute { out; _ } | Ypath_is_relative { out; _ } -> [], [(out, Ty_bool)]
    | Ypath_is_prefix { input; out; _ } ->
      path input "path_is_prefix input", [(out, Ty_bool)]
    | Ypath_compare { input1; input2; out; _ } ->
      path input1 "path_compare" @ path input2 "path_compare", [(out, Ty_bool)]
    | Ypath_set { input; _ } -> path input "path_set", []
    | Ypath_append { inputs; out; _ } ->
      paths inputs "path_append", opt_out out Ty_path
    | Ypath_append_string { inputs; out; _ } ->
      paths inputs "path_append_string", opt_out out Ty_path
    | Ypath_replace_filename { input; out; _ } ->
      path input "path_replace_filename", opt_out out Ty_path
    | Ypath_replace_extension { input; out; _ } ->
      path input "path_replace_extension", opt_out out Ty_path
    | Ypath_remove_filename { out; _ } | Ypath_remove_extension { out; _ }
    | Ypath_normal_path { out; _ } ->
      [], opt_out out Ty_path
    | Ypath_relative_path { base_dir; out; _ } ->
      opt_path base_dir "path_relative base", opt_out out Ty_path
    | Ypath_absolute_path { base_dir; out; _ } ->
      opt_path base_dir "path_absolute base", opt_out out Ty_path
    | Ypath_native_path { out; _ } -> [], [(out, Ty_path)]
    | Ypath_convert_to_cmake { input; out; _ } ->
      path input "convert_to_cmake", [(out, Ty_path)]
    | Ypath_convert_to_native { input; out; _ } ->
      path input "convert_to_native", [(out, Ty_path)]
    | Ypath_hash { out; _ } -> [], [(out, Ty_string)]
    | Ypath_get_filename_component { var; filename; _ } ->
      path filename "get_filename_component", [(var, Ty_string)]
end
