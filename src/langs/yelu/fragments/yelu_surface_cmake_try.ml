open Yelu_cmake_ir
open Yelu_theory_target

let name = "tiny_cmake_try"
let requires = [ "core.string"; "path" ]
let provides = [ "try.try_compile" ]

type expr +=
  | ECmakeTryCompile of { result_var : string; sources : expr list }
  (* Extended try_compile carrying the full keyword-arg payload. Eval
     stub: bind result_var to true, output_variable to "" if present. *)
  | ECmakeTryCompileEx of {
      result_var : string;
      sources : expr list;
      compile_definitions : expr list;
      link_libraries : expr list;
      link_options : expr list;
      output_variable : string option;
      no_cache : bool;
      c_standard : string option;
      cxx_standard : string option;
    }
  | ECmakeTryRun of {
      run_result_var : string;
      compile_result_var : string;
      sources : expr list;
      compile_definitions : expr list;
      link_libraries : expr list;
      compile_output_variable : string option;
      run_output_variable : string option;
      args : expr list;
    }

let eval_case ~eval env = function
  | ECmakeTryCompile { result_var; sources } ->
    let env, sources = eval_string_list ~eval env sources in
    let env = add_try_compile env { result_var; sources } in
    Some (set_var env ~key:result_var ~data:(VBool true), VUnit)
  | ECmakeTryCompileEx { result_var; output_variable; _ } ->
    let env = set_var env ~key:result_var ~data:(VBool true) in
    let env = match output_variable with
      | Some v -> set_var env ~key:v ~data:(VString "")
      | None -> env
    in
    Some (env, VUnit)
  | ECmakeTryRun
      { run_result_var; compile_result_var;
        compile_output_variable; run_output_variable; _ } ->
    let env = set_var env ~key:compile_result_var ~data:(VBool true) in
    let env = set_var env ~key:run_result_var ~data:(VInt 0) in
    let env = match compile_output_variable with
      | Some v -> set_var env ~key:v ~data:(VString "")
      | None -> env
    in
    let env = match run_output_variable with
      | Some v -> set_var env ~key:v ~data:(VString "")
      | None -> env
    in
    Some (env, VUnit)
  | _ -> None
