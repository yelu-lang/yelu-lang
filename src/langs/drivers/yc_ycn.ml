(* ─── Pipeline: yc ↔ ycn ───────────────────────
   yc → Yc_driver.to_ycn → ycn
   ycn → Ycn_driver.compile_to_yc → yc

   Pure syntactic rewrites via Yelu_cmake_convert.
   ─────────────────────────────────────────────── *)

let to_ycn = Yc_driver.to_ycn

let from_ycn = Ycn_driver.compile_to_yc
