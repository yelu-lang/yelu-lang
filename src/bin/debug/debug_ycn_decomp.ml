(* Exploratory probe: does the ycn theory decomposition *express* and *preserve*
   programs built directly on the AST (no concrete syntax)?

   For each hand-built ycn program:
     v1 = eval_ycn p                         (normalized eval)
     yc = from_normal p                       (bridge to cmake-faithful)
     v2 = eval_yc yc                          (dual-eval through the bridge)
     p' = to_normal yc                        (bridge back)
     v3 = eval_ycn p'                         (roundtrip stability)

   Reports value equality (v1=v2, v1=v3) and the emitted cmake text.
   Mismatches are findings, not failures: ycn is value-shaped where yc is
   statement-shaped, so value loss across the bridge is expected in some
   shapes — the probe names those seams.

   Run:  dune exec src/bin/debug/debug_ycn_decomp.exe
*)

open Base
open Yelu_langs.Yelu_cmake
open Yelu_langs.Yelu_cmake_convert
open Yelu_langs.Yelu_cmake_normal_string
open Yelu_langs.Yelu_cmake_normal_int
open Yelu_langs.Yelu_cmake_normal_bool
open Yelu_langs.Yelu_cmake_normal_list
open Yelu_langs.Yelu_cmake_normal_if
open Yelu_langs.Yelu_cmake_normal_store
open Yelu_langs.Yelu_cmake_normal_target
open Yelu_langs.Yelu_cmake_normal_install
open Yelu_langs.Yelu_cmake_normal_cmake_op

let rec string_of_value = function
  | VString s -> Printf.sprintf "VString %S" s
  | VBool b -> Printf.sprintf "VBool %b" b
  | VInt n -> Printf.sprintf "VInt %d" n
  | VList vs ->
    Printf.sprintf "VList [%s]"
      (String.concat ~sep:"; " (List.map vs ~f:string_of_value))
  | VTarget t -> Printf.sprintf "VTarget %S" t
  | VUnit -> "VUnit"

let show_var env name =
  match find_var env name with
  | Some v -> Printf.sprintf "%s=%s" name (string_of_value v)
  | None -> Printf.sprintf "%s=<unset>" name

let first_lines text n =
  List.take (String.split_lines text) n |> String.concat ~sep:" | "

let probe name prog =
  Stdio.printf "\n── %s\n" name;
  (* 1. ycn eval *)
  let v1, text1 =
    try
      let env, v = Yelu_langs.Yelu_cmake_normal_eval.eval_expr empty_env prog in
      ( `Ok v,
        Some (show_var env "OUT" ^ "  " ^ show_var env "TMP" ^ "  " ^ show_var env "J" ^ "  " ^ show_var env "X" ^ "  " ^ show_var env "B" ^ "  " ^ show_var env "N" ^ "  " ^ show_var env "CFG" ^ "  " ^ show_var env "HAS" ^ "  " ^ show_var env "FLAG") )
    with exn -> (`Exn (Exn.to_string exn), None)
  in
  (match v1 with
   | `Ok v -> Stdio.printf "  ycn eval      : %s\n" (string_of_value v)
   | `Exn e -> Stdio.printf "  ycn eval      : EXN %s\n" e);
  (* 2. bridge down + emit *)
  let lowered =
    try Some (from_normal prog)
    with exn -> (Stdio.printf "  from_normal   : EXN %s\n" (Exn.to_string exn); None)
  in
  (match lowered with
   | None -> ()
   | Some yc ->
     (try
        let text = Yelu_langs.Yelu_cmake_emit.emit_script yc in
        Stdio.printf "  emit (yc)     : %s\n" (first_lines text 2)
      with exn -> Stdio.printf "  emit (yc)     : EXN %s\n" (Exn.to_string exn));
     (* 3. dual-eval through bridge *)
     (match v1 with
      | `Ok v1v ->
        (try
           let _, v2 = eval_yelu_cmake_expr empty_env yc in
           Stdio.printf "  yc eval       : %s  (dual %s)\n"
             (string_of_value v2)
             (Bool.to_string (equal_value v1v v2))
         with exn -> Stdio.printf "  yc eval       : EXN %s\n" (Exn.to_string exn))
      | `Exn _ -> ());
     (* 4. bridge back + roundtrip stability *)
     (match v1 with
      | `Ok v1v ->
        (try
           let p' = to_normal yc in
           let _, v3 = Yelu_langs.Yelu_cmake_normal_eval.eval_expr empty_env p' in
           Stdio.printf "  roundtrip ycn : %s  (stable %s)\n"
             (string_of_value v3)
             (Bool.to_string (equal_value v1v v3))
         with exn -> Stdio.printf "  roundtrip ycn : EXN %s\n" (Exn.to_string exn))
      | `Exn _ -> ()));
  (match text1 with
   | Some t -> Stdio.printf "  env snapshot  : %s\n" t
   | None -> ())

let () =
  Stdio.printf "ycn theory-decomposition probe (hand-built AST, no concrete syntax)\n";
  probe "1 string pipeline (upper -> concat)"
    (ESeq
       [ ESetVar ("TMP", EStringUpper (EString "b"));
         ESetVar ("OUT", EStringConcat [ EString "a"; EVar "TMP"; EString "c" ]);
         EVar "OUT" ]);
  probe "2 int + bool composition"
    (ESeq
       [ ESetVar ("B", EAnd (EIntLess (EInt 1, EInt 2), ENot (EIntEqual (EInt 4, EInt 5))));
         EVar "B" ]);
  probe "3 if statement, string-truthiness cond (var)"
    (ESeq
       [ ESetVar ("FLAG", EString "ON");
         ESetVar ("OUT", EIfExpr { cond = EVar "FLAG"; then_ = EString "on"; else_ = EString "off" });
         EVar "OUT" ]);
  probe "4 if value-shaped (no assignment) — expected value seam"
    (EIfExpr
       { cond = EStringEqual (EString "a", EString "a");
         then_ = EString "yes";
         else_ = EString "no" });
  probe "5 list literal -> string join"
    (ESeq
       [ ESetVar ("L", EList [ EString "a"; EString "b"; EString "c" ]);
         ESetVar ("J", EStringJoin { sep = EString "-"; items = EVar "L" });
         EVar "J" ]);
  probe "6 list append in-place -> join"
    (ESeq
       [ ESetVar ("L", EList [ EString "a" ]);
         ESetVar ("L", EListAppend (EVar "L", EString "b"));
         EStringJoin { sep = EString "+"; items = EVar "L" } ]);
  probe "7 list length + get"
    (ESeq
       [ ESetVar ("L", EList [ EInt 10; EInt 20; EInt 30 ]);
         ESetVar ("N", EListLength (EVar "L"));
         ESetVar ("X", EListGet (EVar "L", EInt 1));
         EVar "X" ]);
  probe "8 list get out of range — fault behavior"
    (ESeq
       [ ESetVar ("L", EList [ EInt 1 ]);
         ESetVar ("X", EListGet (EVar "L", EInt 5));
         EVar "X" ]);
  probe "9 cache first-write-wins"
    (ESeq
       [ ESetCache { name = "CFG"; values = [ EString "first" ]; cache_type = "STRING"; docstring = ""; force = false };
         ESetCache { name = "CFG"; values = [ EString "second" ]; cache_type = "STRING"; docstring = ""; force = false };
         EVar "CFG" ]);
  probe "10 cache FORCE overwrite"
    (ESeq
       [ ESetCache { name = "CFG"; values = [ EString "first" ]; cache_type = "STRING"; docstring = ""; force = false };
         ESetCache { name = "CFG"; values = [ EString "second" ]; cache_type = "STRING"; docstring = ""; force = true };
         EVar "CFG" ]);
  probe "11 target declare -> exists -> add sources (expr vs VTarget name)"
    (ESeq
       [ EExecutable { name = EString "app"; sources = [ EString "main.c" ] };
         ESetVar ("HAS", ETargetExists (EString "app"));
         ETargetAddSources { target = ETarget "app"; visibility = Vis_private; sources = [ EString "util.c" ] };
         EVar "HAS" ]);
  probe "12 function def + apply (cmake_op)"
    (ESeq
       [ EDynFunction
           { name = EString "greet";
             params = [ "WHO" ];
             body = EMessage { mode = "STATUS"; texts = [ EStringConcat [ EString "hello "; EVar "WHO" ] ] } };
         EApply { name = EString "greet"; args = [ EString "world" ] };
         EUnit ]);
  probe "13 project + min version + message"
    (ESeq
       [ EProject { name = "demo"; languages = [ "C" ]; version = Some "1.0" };
         EMinVersion "3.20";
         EMessage { mode = "STATUS"; texts = [ EString "built" ] };
         EUnit ]);
  probe "14 ELet lexical binding vs ESetVar"
    (ELet
       { var = "X";
         value = EString "inner";
         body = ESeq [ ESetVar ("OUT", EStringConcat [ EString "["; EVar "X"; EString "]" ]); EVar "OUT" ] });

  (* ── micro-probes: pin the exact bridge surface ── *)
  probe "15 int greater (no convert case, eval-only)"
    (ESetVar ("B", EIntGreater (EInt 2, EInt 1)));
  probe "16 install directory (no convert case, eval-only)"
    (EInstallDirectory
       { directory = EString "share"; destination = EString "share"; component = None; optional = false });
  probe "17 bare concat nested in message texts (value ctor in arg position)"
    (EMessage { mode = "STATUS"; texts = [ EStringConcat [ EString "a"; EString "b" ] ] });
  probe "18 ESetVar-wrapped concat (control)"
    (ESetVar ("OUT", EStringConcat [ EString "a"; EString "b" ]))
