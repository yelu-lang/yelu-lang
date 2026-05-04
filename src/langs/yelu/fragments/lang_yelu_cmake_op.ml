open Base
open Lang_yelu_type

module Make_cmake_op (T : LANG_TYPES) = struct
  type yelu_cmake_stmt =
    | Ycmake_minimum_required of {
        min : Lang_cmake.version;
        max : Lang_cmake.version option;
      }
    | Ycmake_project of {
        name : string;
        version : Lang_cmake.version option;
        languages : Lang_cmake.supported_lang list;
      }
    | Ycmake_enable_language of { langs : string list; optional : bool }
    | Ycmake_policy_set of { id : string; new_ : bool }
    | Ycmake_language_call of { cmd : string; args : T.expr list }
    | Ycmake_language_eval of { code : string }
    | Ycmake_language_get_log_level of { out : T.var }
    | Ycmake_math of {
        exp : string;
        out : T.var;
        output_format : Lang_cmake.math_output_format;
      }
    | Ycmake_variable_watch of { var : T.var; command : string option }
    | Ycmake_execute_process of {
        commands : T.expr list list;
        working_directory : T.expr option;
        timeout : float option;
        result_variable : T.var option;
        output_variable : T.var option;
        error_variable : T.var option;
        input_file : T.expr option;
        output_file : T.expr option;
        error_file : T.expr option;
        output_quiet : bool;
        error_quiet : bool;
        output_strip_trailing_whitespace : bool;
        error_strip_trailing_whitespace : bool;
        command_error_is_fatal : string option;
      }
    | Ycmake_include_guard of { scope : Lang_cmake.include_guard_scope }
    | Ycmake_message of { mode : Lang_cmake.message_mode; texts : string list }
    (* cmake escape hatches — raw injection, outside the typed language *)
    | Ycmake_quote_cmd of string
    | Ycmake_at_var of string
end

module Make_cmake_op_check (T : LANG_TYPES) = struct
  include Make_cmake_op (T)
  let stage = Stage_typecheck

  (* Typed outputs:
     - math: out → Ty_int
     - get_log_level: out → Ty_string
     - execute_process: result_variable → Ty_int, output/error_variable → Ty_string
     All other constructors take no T.expr inputs and produce no typed outputs. *)
  let check ~(type_of : T.expr -> yelu_type)
      : yelu_cmake_stmt -> type_error list * (T.var * yelu_type) list =
    let opt_out v ty = Option.to_list (Option.map v ~f:(fun x -> (x, ty))) in
    let path_opt e ctx = Option.value_map e ~default:[] ~f:(fun x -> check_compat ~context:ctx Ty_path (type_of x)) in
    function
    | Ycmake_language_get_log_level { out } -> [], [(out, Ty_string)]
    | Ycmake_math { out; _ } -> [], [(out, Ty_int)]
    | Ycmake_execute_process { commands; working_directory; result_variable;
                               output_variable; error_variable;
                               input_file; output_file; error_file; _ } ->
      let errs =
        List.concat_map commands ~f:(fun cmd ->
          List.concat_map cmd ~f:(fun e ->
            check_compat ~context:"execute_process cmd" Ty_string (type_of e)))
        @ path_opt working_directory "execute_process workdir"
        @ path_opt input_file "execute_process input_file"
        @ path_opt output_file "execute_process output_file"
        @ path_opt error_file "execute_process error_file"
      in
      errs,
      opt_out result_variable Ty_int
      @ opt_out output_variable Ty_string
      @ opt_out error_variable Ty_string
    | _ -> [], []
end
