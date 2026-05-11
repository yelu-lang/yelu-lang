open Base

module type LANG_TYPES = sig
  type var
  type expr
  type target
end

(* Yelu type universe — first-class type values that annotate the AST.
   Global definition for the first cut; future direction is compositional
   (each theory contributes its own type fragment, mirroring how each
   Make_xxx functor contributes its statement group). *)

type yelu_type =
  | Ty_string
  | Ty_bool
  | Ty_int
  | Ty_path
  | Ty_version
  | Ty_target
  | Ty_list of yelu_type
  | Ty_any (* untyped / unknown — compatible with any expected type *)
[@@deriving equal, sexp_of]

type type_error =
  | Type_mismatch of { expected : yelu_type; got : yelu_type; context : string }
[@@deriving sexp_of]

let rec compatible expected got =
  match expected, got with
  | Ty_any, _ | _, Ty_any -> true
  | Ty_list a, Ty_list b -> compatible a b
  | e, g -> equal_yelu_type e g

let check_compat ~context expected got =
  if compatible expected got then []
  else [ Type_mismatch { expected; got; context } ]

type checking_stage =
  | Stage_typecheck (* expression-level type constraints — per-theory Make_*_check functors *)
  | Stage_wellform  (* name binding: cvar/target declarations and cross-theory reference checks *)
  | Stage_effect    (* cmake execution-mode constraints: target_* only in configure mode *)
  | Stage_lower     (* AST → cmake: structural validity during lowering *)

(* Every Make_*_check functor output must satisfy this.
   A pack's integration module enforces it via a first-class module list. *)
module type CHECKER_BASE = sig
  val stage : checking_stage
end
