open Base
open Yelu_cmake

let name = "tiny_cmake_string"
let requires = [ "core.string"; "core.int" ]
let provides =
  [ "string.concat"; "string.upper"; "string.replace"; "string.length"; "string.equal" ]

type expr +=
  | ECmakeStringConcat of { inputs : expr list; out : string }
  | ECmakeStringToupper of { input : expr; out : string }
  | ECmakeStringReplace of {
      match_ : expr;
      replace : expr;
      input : expr;
      out : string;
    }
  | ECmakeStringLength of { input : expr; out : string }
  | ECmakeStringEqual of expr * expr
  (* Cmake's version-aware string comparisons: [if(A VERSION_LESS B)] etc.
     Eval is a no-op (returns VBool false) — proper semver comparison
     belongs in a dedicated version theory; emit renders the cmake form. *)
  | ECmakeVersionLess of expr * expr
  | ECmakeVersionGreater of expr * expr
  | ECmakeVersionEqual of expr * expr
  | ECmakeVersionLessEqual of expr * expr
  | ECmakeVersionGreaterEqual of expr * expr
  (* [string(REGEX REPLACE <regex> <replace> <out> <input>...)]. Eval stub:
     concat the inputs and bind to out (no regex matching performed in
     tiny — cmake handles it at configure time). *)
  | ECmakeStringRegexReplace of {
      regex : string;
      replace : expr;
      out : string;
      inputs : expr list;
    }
  (* Additional string() subcommands — emit-faithful, eval-stub. *)
  | ECmakeStringTolower of { input : expr; out : string }
  | ECmakeStringStrip of { input : expr; out : string }
  | ECmakeStringRegexMatch of {
      regex : string; out : string; inputs : expr list
    }
  | ECmakeStringRegexMatchAll of {
      regex : string; out : string; inputs : expr list
    }
  | ECmakeStringRegexQuote of { out : string; inputs : expr list }
  | ECmakeStringAppend of { cvar : string; inputs : expr list }
  | ECmakeStringPrepend of { cvar : string; inputs : expr list }
  | ECmakeStringJoin of { glue : expr; out : string; inputs : expr list }
  | ECmakeStringFind of {
      string : expr; substring : expr; out : string; reverse : bool
    }
  | ECmakeStringSubstring of {
      string : expr; begin_ : int; length : int option; out : string
    }
  | ECmakeStringRepeat of { string : expr; count : int; out : string }
  | ECmakeStringGenexStrip of { input : expr; out : string }
  | ECmakeStringMakeCIdentifier of { input : expr; out : string }
  | ECmakeStringTimestamp of {
      out : string; format : string option; utc : bool
    }
  | ECmakeStringHex of { input : expr; out : string }
  | ECmakeStringUuid of {
      out : string; namespace : string; name : string;
      type_ : string; upper : bool
    }
  (* string(JSON ...) — placeholder; we record the operation as opaque
     and let cmake do the work. Eval stub binds [out] to empty. *)
  | ECmakeStringJson of {
      out : string;
      error_var : string option;
      op_name : string;
      args : expr list;
    }
  (* [string(COMPARE <op> <s1> <s2> <out>)] for non-EQUAL ops. EQUAL is
     handled as ECmakeStringEqual (boolean expr); the other ops bind
     [out] to a boolean. *)
  | ECmakeStringCompare of {
      op : string; string1 : expr; string2 : expr; out : string
    }
  (* Additional cond expressions (R6 attrition). Emit-only at the cond
     level; eval stub returns false. *)
  | ECmakeMatches of { expr_ : expr; regex : string }
  | ECmakeInList of { item : expr; list_ : expr }
  | ECmakeIsDirectory of expr
  | ECmakeIsAbsolute of expr
  | ECmakePolicyCheck of string
  (* Minimal genex placeholder: carries the verbatim `$<...>` source
     so the bridge stops conflating generator expressions with plain
     var-deref strings (which both flow through Ycs_eval). No internal
     structure or eval semantics — those are R3 (the genex first slice
     proper). Emit renders identically to a Quoted EString to preserve
     byte-equality with legacy compile. *)
  | ECmakeGenex of string

let replace_all ~match_ ~replace ~input =
  String.substr_replace_all input ~pattern:match_ ~with_:replace

let eval_string ~eval env expr =
  let env, value = eval env expr in
  env, expect_string value

let eval_strings ~eval env exprs =
  List.fold exprs ~init:(env, []) ~f:(fun (env, rev_strings) expr ->
    let env, string = eval_string ~eval env expr in
    env, string :: rev_strings)
  |> fun (env, rev_strings) -> env, List.rev rev_strings

let eval_case ~eval env = function
  | ECmakeStringConcat { inputs; out } ->
    let env, strings = eval_strings ~eval env inputs in
    Some
      (set_var env ~key:out ~data:(VString (String.concat strings)), VUnit)
  | ECmakeStringToupper { input; out } ->
    let env, string = eval_string ~eval env input in
    Some (set_var env ~key:out ~data:(VString (String.uppercase string)), VUnit)
  | ECmakeStringReplace { match_; replace; input; out } ->
    let env, match_string = eval_string ~eval env match_ in
    let env, replace_string = eval_string ~eval env replace in
    let env, input_string = eval_string ~eval env input in
    Some
      ( set_var env ~key:out
          ~data:
            (VString
               (replace_all
                  ~match_:match_string
                  ~replace:replace_string
                  ~input:input_string)),
        VUnit )
  | ECmakeStringLength { input; out } ->
    let env, string = eval_string ~eval env input in
    Some (set_var env ~key:out ~data:(VInt (String.length string)), VUnit)
  | ECmakeStringEqual (left, right) ->
    let env, left = eval_string ~eval env left in
    let env, right = eval_string ~eval env right in
    Some (env, VBool (String.equal left right))
  | ECmakeVersionLess _ | ECmakeVersionGreater _
  | ECmakeVersionEqual _ | ECmakeVersionLessEqual _
  | ECmakeVersionGreaterEqual _ ->
    (* Eval is a no-op stub at this slice; the cond is decided by cmake.
       A future yelu_theory_version would implement semver compare. *)
    Some (env, VBool false)
  | ECmakeStringRegexReplace { regex = _; replace = _; out; inputs } ->
    let env, strings = eval_strings ~eval env inputs in
    Some
      (set_var env ~key:out ~data:(VString (String.concat strings)), VUnit)
  (* Additional string() subcommands — eval stubs. *)
  | ECmakeStringTolower { input; out } ->
    let env, s = eval_string ~eval env input in
    Some (set_var env ~key:out ~data:(VString (String.lowercase s)), VUnit)
  | ECmakeStringStrip { input; out } ->
    let env, s = eval_string ~eval env input in
    Some (set_var env ~key:out ~data:(VString (String.strip s)), VUnit)
  | ECmakeStringRegexMatch { out; inputs; _ }
  | ECmakeStringRegexMatchAll { out; inputs; _ } ->
    let env, strings = eval_strings ~eval env inputs in
    Some
      (set_var env ~key:out ~data:(VString (String.concat strings)), VUnit)
  | ECmakeStringRegexQuote { out; inputs } ->
    let env, strings = eval_strings ~eval env inputs in
    Some
      (set_var env ~key:out ~data:(VString (String.concat strings)), VUnit)
  | ECmakeStringAppend { cvar; inputs } ->
    let env, strings = eval_strings ~eval env inputs in
    let existing =
      match find_var env cvar with Some (VString s) -> s | _ -> ""
    in
    Some
      (set_var env ~key:cvar
         ~data:(VString (existing ^ String.concat strings)),
       VUnit)
  | ECmakeStringPrepend { cvar; inputs } ->
    let env, strings = eval_strings ~eval env inputs in
    let existing =
      match find_var env cvar with Some (VString s) -> s | _ -> ""
    in
    Some
      (set_var env ~key:cvar
         ~data:(VString (String.concat strings ^ existing)),
       VUnit)
  | ECmakeStringJoin { glue; out; inputs } ->
    let env, glue = eval_string ~eval env glue in
    let env, strings = eval_strings ~eval env inputs in
    Some
      (set_var env ~key:out
         ~data:(VString (String.concat ~sep:glue strings)),
       VUnit)
  | ECmakeStringFind { string; substring; out; reverse = _ } ->
    let env, s = eval_string ~eval env string in
    let env, sub = eval_string ~eval env substring in
    let idx =
      match String.substr_index s ~pattern:sub with
      | Some i -> i | None -> -1
    in
    Some (set_var env ~key:out ~data:(VInt idx), VUnit)
  | ECmakeStringSubstring { string; begin_; length; out } ->
    let env, s = eval_string ~eval env string in
    let pos = if begin_ < 0 then 0 else begin_ in
    let avail = String.length s - pos in
    let len =
      match length with
      | Some n when n >= 0 && n <= avail -> n
      | _ -> max 0 avail
    in
    let result = if pos >= String.length s then "" else String.sub s ~pos ~len in
    Some (set_var env ~key:out ~data:(VString result), VUnit)
  | ECmakeStringRepeat { string; count; out } ->
    let env, s = eval_string ~eval env string in
    let buf = Buffer.create (String.length s * max 0 count) in
    for _ = 1 to count do Buffer.add_string buf s done;
    Some (set_var env ~key:out ~data:(VString (Buffer.contents buf)), VUnit)
  | ECmakeStringGenexStrip { input; out } ->
    let env, s = eval_string ~eval env input in
    Some (set_var env ~key:out ~data:(VString s), VUnit)
  | ECmakeStringMakeCIdentifier { input; out } ->
    let env, s = eval_string ~eval env input in
    Some (set_var env ~key:out ~data:(VString s), VUnit)
  | ECmakeStringTimestamp { out; _ } ->
    Some (set_var env ~key:out ~data:(VString ""), VUnit)
  | ECmakeStringHex { input; out } ->
    let env, s = eval_string ~eval env input in
    Some (set_var env ~key:out ~data:(VString s), VUnit)
  | ECmakeStringUuid { out; _ } ->
    Some (set_var env ~key:out ~data:(VString ""), VUnit)
  | ECmakeStringJson { out; _ } ->
    Some (set_var env ~key:out ~data:(VString ""), VUnit)
  | ECmakeStringCompare { out; _ } ->
    Some (set_var env ~key:out ~data:(VBool false), VUnit)
  | ECmakeMatches _ | ECmakeInList _
  | ECmakeIsDirectory _ | ECmakeIsAbsolute _ | ECmakePolicyCheck _ ->
    Some (env, VBool false)
  (* Genex eval: opaque value, returned as the verbatim source string.
     Real cmake expands at generate time; tiny doesn't model that. *)
  | ECmakeGenex s -> Some (env, VString s)
  | _ -> None
