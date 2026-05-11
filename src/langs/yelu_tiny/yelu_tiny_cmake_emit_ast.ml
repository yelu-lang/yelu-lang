(* Phase 1 of retirement: lower Yelu1 IR to Lang_cmake.exp (the cmake
   syntax AST), then let the existing [lang_cmake_pp] render to text.
   See [doc/yelu_tiny/retirement_plan.md] for context.

   This module exists alongside [yelu_tiny_cmake_emit.ml] (the direct-
   text emit). Phase 1 closes coverage here until parity is reached;
   then the direct-text emit is demoted to a diagnostic / diff aid. *)

open Base
open Yelu_tiny
open Yelu_surface_cmake_store
open Yelu_theory_bool
open Yelu_theory_int
open Yelu_theory_list
open Yelu_surface_cmake_file
open Yelu_surface_cmake_string
open Yelu_surface_cmake_target
open Yelu_surface_cmake_if
open Yelu_surface_cmake_cmake_op
open Yelu_theory_target

(* Many other surface modules are opened transitively via [expr] match
   arms as Phase 1.3 expands coverage; keep [open]s narrow for now to
   avoid unused-open warnings. *)

module C = Lang_cmake

(* ========================================================================
   Erasure helpers — Yelu1 expr → cmake AST positional shapes.

   Four distinct erasures are needed; each gets its own helper:

   1. expr → C.arg              for command-arg positions (Bare/Quoted/Bracket)
   2. expr → string             for target / cvar / file-name positions
   3. bool expr → C.cond        for if-conditions (flat token list)
   4. ELet substitution         threaded through 1/2/3 via [subst]
   ======================================================================== *)

type subst = expr Map.M(String).t

let empty_subst : subst = Map.empty (module String)

(* Mirror [lang_yelu_compile.erase_arg]'s quoting policy: quote when cmake
   would otherwise mis-tokenize (empty / whitespace / genex / backslash);
   keep bare otherwise. EVar resolves through subst lazily; unresolved
   EVar renders as ${name} (cmake deref). *)
let rec arg ?(env = empty_subst) (e : expr) : C.arg =
  match e with
  | EVar name ->
    (match Map.find env name with
     | Some replacement -> arg ~env replacement
     | None -> C.Bare ("${" ^ name ^ "}"))
  | EString s ->
    if String.is_empty s
    || String.exists s ~f:Char.is_whitespace
    || String.is_substring s ~substring:"$<"
    || String.exists s ~f:(Char.equal '\\')
    then C.Quoted s
    else C.Bare s
  | EInt n -> C.Bare (Int.to_string n)
  | EBool true -> C.Bare "ON"
  | EBool false -> C.Bare "OFF"
  | ETarget name -> C.Bare name
  | _ -> fail "emit_ast: cannot erase expression to cmake arg"

(* Target / cvar / file-name positions: cmake convention is unquoted
   identifier. Resolve via subst; unresolved EVar renders as ${name}. *)
let rec target_arg ?(env = empty_subst) (e : expr) : string =
  match e with
  | EVar name ->
    (match Map.find env name with
     | Some replacement -> target_arg ~env replacement
     | None -> "${" ^ name ^ "}")
  | EString s -> s
  | ETarget name -> name
  | _ -> fail "emit_ast: cannot erase expression to target name"

(* Tokens for cond-position rendering. cmake [cond = string list] composes
   into the parenthesized argument list of [if(...)]. Token rendering
   mirrors [yelu_tiny_cmake_emit.cond] but emits a list rather than a
   joined string. *)
let arg_token ?(env = empty_subst) e : string =
  match arg ~env e with
  | C.Bare s -> s
  | C.Quoted s -> "\"" ^ s ^ "\""
  | C.Bracket s -> s

let rec cond_tokens ?(env = empty_subst) (e : expr) : string list =
  match e with
  | EBool true -> [ "TRUE" ]
  | EBool false -> [ "FALSE" ]
  | ENot e -> "NOT" :: cond_atom ~env e
  | EAnd (l, r) -> cond_atom ~env l @ [ "AND" ] @ cond_atom ~env r
  | EOr (l, r) -> cond_atom ~env l @ [ "OR" ] @ cond_atom ~env r
  | EIntLess (l, r) -> [ arg_token ~env l; "LESS"; arg_token ~env r ]
  | EIntEqual (l, r) -> [ arg_token ~env l; "EQUAL"; arg_token ~env r ]
  | EIntGreater (l, r) -> [ arg_token ~env l; "GREATER"; arg_token ~env r ]
  | EIntLessEqual (l, r) -> [ arg_token ~env l; "LESS_EQUAL"; arg_token ~env r ]
  | EIntGreaterEqual (l, r) -> [ arg_token ~env l; "GREATER_EQUAL"; arg_token ~env r ]
  | ECmakeStringEqual (l, r) -> [ arg_token ~env l; "STREQUAL"; arg_token ~env r ]
  | ECmakeVersionLess (a, b) -> [ arg_token ~env a; "VERSION_LESS"; arg_token ~env b ]
  | ECmakeVersionGreater (a, b) -> [ arg_token ~env a; "VERSION_GREATER"; arg_token ~env b ]
  | ECmakeVersionEqual (a, b) -> [ arg_token ~env a; "VERSION_EQUAL"; arg_token ~env b ]
  | ECmakeVersionLessEqual (a, b) -> [ arg_token ~env a; "VERSION_LESS_EQUAL"; arg_token ~env b ]
  | ECmakeVersionGreaterEqual (a, b) -> [ arg_token ~env a; "VERSION_GREATER_EQUAL"; arg_token ~env b ]
  | ECmakeVarDefined name -> [ "DEFINED"; name ]
  | ECmakeTargetExists t -> [ "TARGET"; target_arg ~env t ]
  | ECmakeFileExists p -> [ "EXISTS"; arg_token ~env p ]
  | ECmakeMatches { expr_; regex } -> [ arg_token ~env expr_; "MATCHES"; "\"" ^ regex ^ "\"" ]
  | ECmakeInList { item; list_ } -> [ arg_token ~env item; "IN_LIST"; arg_token ~env list_ ]
  | ECmakeIsDirectory p -> [ "IS_DIRECTORY"; arg_token ~env p ]
  | ECmakePolicyCheck p -> [ "POLICY"; p ]
  | _ -> [ arg_token ~env e ]

(* Parenthesize And/Or sub-conditions so that operator precedence stays
   explicit when nested inside a higher-level AND/OR. *)
and cond_atom ?(env = empty_subst) (e : expr) : string list =
  match e with
  | EAnd _ | EOr _ -> ("(" :: cond_tokens ~env e) @ [ ")" ]
  | _ -> cond_tokens ~env e

(* ========================================================================
   Top-level emit: Yelu1 expr → cmake AST [exp].

   ESeq → Exp_list, ELet extends [subst] before recursing into body,
   matched ECmake* constructors map to their cmake AST counterparts.

   Phase 1.1 scope: skeleton + a small set of commands. Subsequent
   commits expand coverage until parity with [yelu_tiny_cmake_emit].
   ======================================================================== *)

let message_mode_of_string = function
  | "" | "NONE" -> C.Mm_none
  | "STATUS" -> C.Mm_status
  | "NOTICE" -> C.Mm_notice
  | "VERBOSE" -> C.Mm_verbose
  | "DEBUG" -> C.Mm_debug
  | "TRACE" -> C.Mm_trace
  | "WARNING" -> C.Mm_warning
  | "AUTHOR_WARNING" -> C.Mm_author_warning
  | "CHECK_START" -> C.Mm_check_start
  | "CHECK_PASS" -> C.Mm_check_pass
  | "CHECK_FAIL" -> C.Mm_check_fail
  | "SEND_ERROR" -> C.Mm_send_error
  | "FATAL_ERROR" -> C.Mm_fatal_error
  | "DEPRECATION" -> C.Mm_deprecation
  | other -> fail "emit_ast: unknown message mode %S" other

let version_of_string s : C.version =
  match String.split s ~on:'.' with
  | [ maj; min ] ->
    { major = Int.of_string maj; minor = Int.of_string min; patch = "" }
  | [ maj; min; patch ] ->
    { major = Int.of_string maj; minor = Int.of_string min; patch }
  | _ -> { major = 3; minor = 20; patch = "" }

let rec emit_exp ~env (e : expr) : C.exp =
  match e with
  | EUnit -> C.Exp_list []
  | ESeq exprs ->
    C.Exp_list (List.map exprs ~f:(emit_exp ~env))
  | ELet { var; value; body } ->
    let env = Map.set env ~key:var ~data:value in
    emit_exp ~env body

  (* Store theory *)
  | ESetVar (name, EList exprs) ->
    C.Set { var = name; values = List.map exprs ~f:(arg ~env); parent_scope = false }
  | ESetVar (name, value) ->
    C.Set { var = name; values = [ arg ~env value ]; parent_scope = false }
  | ECmakeUnsetVar name ->
    C.Unset { var = name; cache = false; parent_scope = false }
  | ECmakeUnsetVarCache name ->
    C.Unset { var = name; cache = true; parent_scope = false }
  | ECmakeSetParentScope { name; value = EList exprs } ->
    C.Set { var = name; values = List.map exprs ~f:(arg ~env); parent_scope = true }
  | ECmakeSetParentScope { name; value } ->
    C.Set { var = name; values = [ arg ~env value ]; parent_scope = true }
  | ECmakeSetEnvVar { name; value } ->
    C.Set_env { var = name; value = arg ~env value }
  | ECmakeUnsetEnvVar name ->
    C.Unset_env { var = name }
  | ECmakeOption { name; message; value } ->
    C.Cmake_option { var = name; msg = message; value = arg ~env value }

  (* cmake_op: project metadata *)
  | ECmakeMinimumRequired version_s ->
    C.Cmake_cmd
      (C.Cmake_minimum_required { min = version_of_string version_s; max = None })
  | ECmakeMessage { mode; texts } ->
    C.Message
      { mode = message_mode_of_string mode;
        texts = List.map texts ~f:(target_arg ~env) }

  (* Control flow *)
  | ECmakeIfStmt { cond; then_; else_ } ->
    C.If
      { cond = cond_tokens ~env cond;
        then_ = emit_exp ~env then_;
        else_ = Option.map else_ ~f:(emit_exp ~env) }

  (* Diagnostic / result-message fallthroughs (kept compatible with
     [yelu_tiny_cmake_emit]: a bare value at statement position renders
     as a [message] for round-trip-observability). *)
  | EVar name when Map.mem env name ->
    emit_exp ~env (Map.find_exn env name)
  | EVar name ->
    C.Message { mode = C.Mm_none; texts = [ "RESULT=${" ^ name ^ "}" ] }
  | EString s ->
    C.Message { mode = C.Mm_none; texts = [ "RESULT=" ^ s ] }
  | EInt n ->
    C.Message { mode = C.Mm_none; texts = [ "RESULT=" ^ Int.to_string n ] }
  | EBool b ->
    C.Message { mode = C.Mm_none; texts = [ "RESULT=" ^ (if b then "ON" else "OFF") ] }
  | ETarget _ -> C.Exp_list []

  | _ -> fail "emit_ast: unsupported Yelu1 expression (phase 1 coverage gap)"

(* Public API. *)

let emit_ast ?(env = empty_subst) (e : expr) : C.exp = emit_exp ~env e

let emit_script (e : expr) : string =
  let ast = emit_ast e in
  Fmt.str "%a\n" Lang_cmake_pp.pp ast
