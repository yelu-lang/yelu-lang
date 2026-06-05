(* Raw cmake escape — Shape C lockup.

   ECmakeRaw carries verbatim cmake source text that bypasses the
   yelu IR. The emit lowering routes it through C.Quote (which the
   pretty printer dumps as-is, no quoting).

   Use sparingly: each occurrence is unmodeled surface that future
   IR work could replace. probes/fmt should document residual
   raw_cmake blocks in its status file. *)

open Yelu_cmake

type expr +=
  | ECmakeRaw of string

(* Eval is intentionally undefined: raw_cmake is a codegen-only
   escape. Programs that include it cannot be evaluated by the
   yelu_cmake interpreter — they must go straight to emit. *)
let eval_case ~eval:_ _env = function
  | ECmakeRaw _ ->
    Some (failwith "ECmakeRaw: codegen-only escape; cannot eval")
  | _ -> None
