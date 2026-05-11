open Base
open Lang_yelu_type

module Make_try_op (T : LANG_TYPES) = struct
  type yelu_try_stmt =
    | Ytry_compile of {
        result_var : T.var;
        sources : T.expr list;
        compile_definitions : T.expr list;
        link_libraries : T.expr list;
        link_options : T.expr list;
        output_variable : T.var option;
        no_cache : bool;
        c_standard : string option;
        cxx_standard : string option;
      }
    | Ytry_run of {
        run_result_var : T.var;
        compile_result_var : T.var;
        sources : T.expr list;
        compile_definitions : T.expr list;
        link_libraries : T.expr list;
        compile_output_variable : T.var option;
        run_output_variable : T.var option;
        args : T.expr list;
      }
end

module Make_try_check (T : LANG_TYPES) = struct
  include Make_try_op (T)
  let stage = Stage_typecheck

  (* Returns (errors, output bindings): try_compile/try_run bind result vars
     to known types regardless of whether compilation succeeds. *)
  let check ~(type_of : T.expr -> yelu_type)
      : yelu_try_stmt -> type_error list * (T.var * yelu_type) list =
    let paths es ctx = List.concat_map es ~f:(fun e -> check_compat ~context:ctx Ty_path (type_of e)) in
    let strs es ctx = List.concat_map es ~f:(fun e -> check_compat ~context:ctx Ty_string (type_of e)) in
    let opt_out v ty = Option.to_list (Option.map v ~f:(fun x -> (x, ty))) in
    function
    | Ytry_compile { result_var; sources; compile_definitions; link_libraries;
                     link_options; output_variable; _ } ->
      let errs =
        paths sources "try_compile sources"
        @ strs compile_definitions "try_compile defs"
        @ strs link_libraries "try_compile libs"
        @ strs link_options "try_compile opts"
      in
      errs, (result_var, Ty_bool) :: opt_out output_variable Ty_string
    | Ytry_run { run_result_var; compile_result_var; sources; compile_definitions;
                 link_libraries; compile_output_variable; run_output_variable; args } ->
      let errs =
        paths sources "try_run sources"
        @ strs compile_definitions "try_run defs"
        @ strs link_libraries "try_run libs"
        @ strs args "try_run args"
      in
      let outs =
        (compile_result_var, Ty_bool)
        :: (run_result_var, Ty_int)
        :: opt_out compile_output_variable Ty_string
        @ opt_out run_output_variable Ty_string
      in
      errs, outs
end
