(* Backward-compatibility shim. The interpreter and translation logic
   used to live in this single file but is now split:

   - {!Yelu_tiny_yelu1}    Yelu1 (cmake-shaped surface) interpreter
   - {!Yelu_tiny_yelu2}    Yelu2 (theory-side idealized) interpreter
   - {!Yelu_tiny_translate} lift_yelu1_to_yelu2 / lower_yelu2_to_yelu1

   Existing call sites that [open Yelu_langs.Yelu_tiny_eval] continue
   to find [eval_yelu1_expr], [eval_yelu2_expr], [lift_yelu1_to_yelu2],
   and [lower_yelu2_to_yelu1] here unchanged. New code should reference
   the split modules directly. *)

let lift_yelu1_to_yelu2 = Yelu_tiny_translate.lift_yelu1_to_yelu2
let lower_yelu2_to_yelu1 = Yelu_tiny_translate.lower_yelu2_to_yelu1

let cmake_string_to_better = lift_yelu1_to_yelu2
let better_to_cmake_string = lower_yelu2_to_yelu1

let eval_yelu1_expr env expr = Yelu_tiny_yelu1.eval_expr env expr
let eval_yelu2_expr env expr = Yelu_tiny_yelu2.eval_expr env expr

module Yelu1 = struct
  let eval_expr = Yelu_tiny_yelu1.eval_expr
end

module Yelu2 = struct
  let eval_expr = Yelu_tiny_yelu2.eval_expr
end
