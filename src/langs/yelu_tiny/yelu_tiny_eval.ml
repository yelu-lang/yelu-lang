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
open Yelu_theory_target
open Yelu_surface_cmake_target
open Yelu_surface_cmake_string
open Yelu_theory_string
open Yelu_surface_cmake_if
open Yelu_theory_if

module Yelu1 = struct
  let rec eval_expr env = function
    | EVar name ->
      (match find_var env name with
       | Some value -> env, value
       | None -> fail "unbound variable %S" name)
    | EString s -> env, VString s
    | EBool b -> env, VBool b
    | EInt n -> env, VInt n
    | EUnit -> env, VUnit
    | ESetVar (name, expr) ->
      let env, value = eval_expr env expr in
      set_var env ~key:name ~data:value, VUnit
    | EUnsetVar name ->
      remove_var env name, VUnit
    | EVarDefined name ->
      env, VBool (var_defined env name)
    | ECmakeUnsetVar name ->
      remove_var env name, VUnit
    | ECmakeVarDefined name ->
      env, VBool (var_defined env name)
    | ESeq exprs ->
      List.fold exprs ~init:(env, VUnit) ~f:(fun (env, _last) expr ->
        eval_expr env expr)
    | expr ->
      (match Yelu_theory_bool.eval_case ~eval:eval_expr env expr with
       | Some value -> value
       | None ->
      match Yelu_theory_int.eval_case ~eval:eval_expr env expr with
       | Some value -> value
       | None ->
      match Yelu_theory_list.eval_case ~eval:eval_expr env expr with
       | Some value -> value
       | None ->
      match Yelu_surface_cmake_list.eval_case ~eval:eval_expr env expr with
       | Some value -> value
       | None ->
      match Yelu_surface_cmake_path.eval_case ~eval:eval_expr env expr with
       | Some value -> value
       | None ->
      match Yelu_theory_target.eval_case ~eval:eval_expr env expr with
       | Some value -> value
       | None ->
      match Yelu_surface_cmake_target.eval_case ~eval:eval_expr env expr with
       | Some value -> value
       | None ->
      match Yelu_surface_cmake_if.eval_case ~eval:eval_expr env expr with
       | Some value -> value
       | None ->
      match Yelu_surface_cmake_string.eval_case ~eval:eval_expr env expr with
       | Some value -> value
       | None -> fail "unknown expression in Yelu1")
end

module Yelu2 = struct
  let rec eval_expr env = function
    | EVar name ->
      (match find_var env name with
       | Some value -> env, value
       | None -> fail "unbound variable %S" name)
    | EString s -> env, VString s
    | EBool b -> env, VBool b
    | EInt n -> env, VInt n
    | EUnit -> env, VUnit
    | ESetVar (name, expr) ->
      let env, value = eval_expr env expr in
      set_var env ~key:name ~data:value, VUnit
    | EUnsetVar name ->
      remove_var env name, VUnit
    | EVarDefined name ->
      env, VBool (var_defined env name)
    | ESeq exprs ->
      List.fold exprs ~init:(env, VUnit) ~f:(fun (env, _last) expr ->
        eval_expr env expr)
    | expr ->
      (match Yelu_theory_bool.eval_case ~eval:eval_expr env expr with
       | Some value -> value
       | None ->
      match Yelu_theory_int.eval_case ~eval:eval_expr env expr with
       | Some value -> value
       | None ->
      match Yelu_theory_list.eval_case ~eval:eval_expr env expr with
       | Some value -> value
       | None ->
      match Yelu_theory_path.eval_case ~eval:eval_expr env expr with
       | Some value -> value
       | None ->
      match Yelu_theory_target.eval_case ~eval:eval_expr env expr with
       | Some value -> value
       | None ->
      match Yelu_theory_if.eval_case ~eval:eval_expr env expr with
       | Some value -> value
       | None ->
      match Yelu_theory_string.eval_case ~eval:eval_expr env expr with
       | Some value -> value
       | None -> fail "unknown expression in Yelu2")
end

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

  (* CMake store surface -> Yelu store theory. *)
  | ECmakeUnsetVar name -> EUnsetVar name
  | ECmakeVarDefined name -> EVarDefined name

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

  (* Shared target theory. *)
  | ETarget name -> ETarget name
  | EExecutable { name; sources } ->
    EExecutable
      { name = lift_yelu1_to_yelu2 name; sources = List.map sources ~f:lift_yelu1_to_yelu2 }
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
  | ECustomTarget { name; all; commands; depends; comment } ->
    ECustomTarget
      { name; all; commands; depends = List.map depends ~f:lift_yelu1_to_yelu2; comment }

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

  (* CMake target surface -> Yelu target theory. Keep statement result as unit. *)
  | ECmakeAddExecutable { name; sources } ->
    ESeq
      [
        EExecutable { name = EString name; sources = List.map sources ~f:lift_yelu1_to_yelu2 };
        EUnit;
      ]
  | ECmakeTargetSources { target; visibility; sources } ->
    ESeq
      [
        ETargetAddSources
          { target = ETarget target; visibility; sources = List.map sources ~f:lift_yelu1_to_yelu2 };
        EUnit;
      ]
  | ECmakeTargetLinkLibraries { target; visibility; items } ->
    ESeq
      [
        ETargetLinkLibraries
          { target = ETarget target; visibility; items = List.map items ~f:lift_yelu1_to_yelu2 };
        EUnit;
      ]
  | ECmakeTargetIncludeDirectories { target; visibility; dirs } ->
    ESeq
      [
        ETargetIncludeDirectories
          { target = ETarget target; visibility; dirs = List.map dirs ~f:lift_yelu1_to_yelu2 };
        EUnit;
      ]
  | ECmakeAddCustomTarget { name; all; commands; depends; comment } ->
    ESeq
      [
        ECustomTarget
          { name; all; commands; depends = List.map depends ~f:lift_yelu1_to_yelu2; comment };
        EUnit;
      ]
  | ECmakeTargetExists name ->
    ETargetExists (ETarget name)

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

  (* Shared target theory. *)
  | ETarget name -> ETarget name
  | EExecutable { name = EString target_name; sources } ->
    ESeq
      [
        ECmakeAddExecutable
          { name = target_name; sources = List.map sources ~f:lower_yelu2_to_yelu1 };
        ETarget target_name;
      ]
  | EExecutable { name; sources } ->
    EExecutable
      { name = lower_yelu2_to_yelu1 name; sources = List.map sources ~f:lower_yelu2_to_yelu1 }
  | ETargetExists (ETarget name) ->
    ECmakeTargetExists name
  | ETargetExists target ->
    ETargetExists (lower_yelu2_to_yelu1 target)
  | ETargetAddSources { target = ETarget name; visibility; sources } ->
    ESeq
      [
        ECmakeTargetSources
          { target = name; visibility; sources = List.map sources ~f:lower_yelu2_to_yelu1 };
        ETarget name;
      ]
  | ETargetAddSources { target; visibility; sources } ->
    ETargetAddSources
      {
        target = lower_yelu2_to_yelu1 target;
        visibility;
        sources = List.map sources ~f:lower_yelu2_to_yelu1;
      }
  | ETargetLinkLibraries { target = ETarget name; visibility; items } ->
    ESeq
      [
        ECmakeTargetLinkLibraries
          { target = name; visibility; items = List.map items ~f:lower_yelu2_to_yelu1 };
        ETarget name;
      ]
  | ETargetLinkLibraries { target; visibility; items } ->
    ETargetLinkLibraries
      {
        target = lower_yelu2_to_yelu1 target;
        visibility;
        items = List.map items ~f:lower_yelu2_to_yelu1;
      }
  | ETargetIncludeDirectories { target = ETarget name; visibility; dirs } ->
    ESeq
      [
        ECmakeTargetIncludeDirectories
          { target = name; visibility; dirs = List.map dirs ~f:lower_yelu2_to_yelu1 };
        ETarget name;
      ]
  | ETargetIncludeDirectories { target; visibility; dirs } ->
    ETargetIncludeDirectories
      {
        target = lower_yelu2_to_yelu1 target;
        visibility;
        dirs = List.map dirs ~f:lower_yelu2_to_yelu1;
      }
  | ECustomTarget { name; all; commands; depends; comment } ->
    ECmakeAddCustomTarget
      { name; all; commands; depends = List.map depends ~f:lower_yelu2_to_yelu1; comment }

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

  (* Yelu target theory -> CMake target surface. *)
  | ESetVar (var, EExecutable { name = EString target_name; sources }) ->
    ESeq
      [
        ECmakeAddExecutable
          { name = target_name; sources = List.map sources ~f:lower_yelu2_to_yelu1 };
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

  | ESetVar (name, expr) -> ESetVar (name, lower_yelu2_to_yelu1 expr)
  | ESeq exprs -> ESeq (List.map exprs ~f:lower_yelu2_to_yelu1)
  | _ -> fail "cannot translate unknown Yelu2 expression"

let cmake_string_to_better = lift_yelu1_to_yelu2
let better_to_cmake_string = lower_yelu2_to_yelu1

let eval_yelu1_expr env expr = Yelu1.eval_expr env expr
let eval_yelu2_expr env expr = Yelu2.eval_expr env expr
