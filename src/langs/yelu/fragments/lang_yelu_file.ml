open Base
open Lang_yelu_type

(* File IO operations: file(READ/WRITE/GLOB/STRINGS/...) and configure_file.
   Path manipulation (cmake_path GET/APPEND/...) lives in lang_yelu_path.ml. *)

module Make_file_io_op (T : LANG_TYPES) = struct
  type yelu_file_io_stmt =
    (* file() IO *)
    | Yfile_read of {
        out : T.var;
        file : T.expr;
        offset : int option;
        limit : int option;
        hex : bool;
      }
    | Yfile_write of { file : T.expr; append : bool; content : T.expr list }
    | Yfile_strings of {
        out : T.var;
        file : T.expr;
        regex : string option;
        encoding : string option;
        limit_count : int option;
      }
    (* file() filesystem *)
    | Yfile_touch of { files : T.expr list; nocreate : bool }
    | Yfile_make_directory of { dirs : T.expr list }
    | Yfile_rename of {
        old_ : T.expr;
        new_ : T.expr;
        result : T.var option;
        no_replace : bool;
      }
    | Yfile_remove of { files : T.expr list; recurse : bool }
    | Yfile_copy of {
        input : T.expr;
        output : T.expr;
        result : T.var option;
        only_if_different : bool;
      }
    (* file() path queries *)
    | Yfile_real_path of {
        out : T.var;
        path : T.expr;
        base_dir : T.expr option;
        expand_tilde : bool;
      }
    | Yfile_size of { out : T.var; file : T.expr }
    | Yfile_read_symlink of { out : T.var; link : T.expr }
    | Yfile_timestamp of {
        out : T.var;
        file : T.expr;
        format : string option;
        utc : bool;
      }
    (* Note: var is T.expr (cmake variable name as string), not T.var — design inconsistency *)
    | Yfile_relative_path of { var : T.expr; base : T.expr; file : T.expr }
    | Yfile_glob of {
        out : T.var;
        recurse : bool;
        relative : T.expr option;
        configure_depends : bool;
        patterns : T.expr list;
      }
    | Yfile_configure of { input : T.expr; output : T.expr }
end

module Make_file_io_check (T : LANG_TYPES) = struct
  include Make_file_io_op (T)
  let stage = Stage_typecheck

  let check ~(type_of : T.expr -> yelu_type)
      : yelu_file_io_stmt -> type_error list * (T.var * yelu_type) list =
    let path e ctx = check_compat ~context:ctx Ty_path (type_of e) in
    let paths es ctx = List.concat_map es ~f:(fun e -> path e ctx) in
    let opt_path e ctx = Option.value_map e ~default:[] ~f:(fun x -> path x ctx) in
    let opt_var v ty = Option.to_list (Option.map v ~f:(fun x -> (x, ty))) in
    function
    | Yfile_read { out; file; _ } ->
      path file "file_read", [(out, Ty_string)]
    | Yfile_write { file; content; _ } ->
      path file "file_write" @ paths content "file_write content", []
    | Yfile_strings { out; file; _ } ->
      path file "file_strings", [(out, Ty_string)]
    | Yfile_touch { files; _ } -> paths files "file_touch", []
    | Yfile_make_directory { dirs } -> paths dirs "file_make_directory", []
    | Yfile_rename { old_; new_; result; _ } ->
      path old_ "file_rename old" @ path new_ "file_rename new",
      opt_var result Ty_bool
    | Yfile_remove { files; _ } -> paths files "file_remove", []
    | Yfile_copy { input; output; result; _ } ->
      path input "file_copy input" @ path output "file_copy output",
      opt_var result Ty_bool
    | Yfile_real_path { out; path = p; base_dir; _ } ->
      path p "file_real_path" @ opt_path base_dir "file_real_path base",
      [(out, Ty_path)]
    | Yfile_size { out; file } -> path file "file_size", [(out, Ty_int)]
    | Yfile_read_symlink { out; link } -> path link "file_read_symlink", [(out, Ty_path)]
    | Yfile_timestamp { out; file; _ } -> path file "file_timestamp", [(out, Ty_string)]
    | Yfile_relative_path { var; base; file } ->
      check_compat ~context:"file_relative_path var" Ty_string (type_of var)
      @ path base "file_relative_path base"
      @ path file "file_relative_path file",
      []
    | Yfile_glob { out; relative; patterns; _ } ->
      opt_path relative "file_glob relative" @ paths patterns "file_glob patterns",
      [(out, Ty_list Ty_path)]
    | Yfile_configure { input; output } ->
      path input "file_configure input" @ path output "file_configure output", []
end
