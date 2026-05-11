open Base
open Lang_yelu_type

module Make_json_op (T : LANG_TYPES) = struct
  type yelu_json_op =
    | Yjop_get of { json : T.expr; path : string list }
    | Yjop_get_raw of { json : T.expr; path : string list }
    | Yjop_type of { json : T.expr; path : string list }
    | Yjop_length of { json : T.expr; path : string list }
    | Yjop_member of { json : T.expr; path : string list }
    | Yjop_remove of { json : T.expr; path : string list }
    | Yjop_set of { json : T.expr; path : string list; value : T.expr }
    | Yjop_equal of { json1 : T.expr; json2 : T.expr }
    | Yjop_string_encode of { value : T.expr }
end

module Make_string_op (T : LANG_TYPES) = struct
  include Make_json_op (T)

  type yelu_string_stmt =
    | Ystr_toupper of { string : T.expr; out : T.var }
    | Ystr_tolower of { string : T.expr; out : T.var }
    | Ystr_length of { string : T.expr; out : T.var }
    | Ystr_strip of { string : T.expr; out : T.var }
    | Ystr_concat of { out : T.var; inputs : T.expr list }
    | Ystr_replace of {
        match_string : T.expr;
        replace_string : T.expr;
        out : T.var;
        inputs : T.expr list;
      }
    | Ystr_regex_match of { regex : string; out : T.var; inputs : T.expr list }
    | Ystr_regex_matchall of {
        regex : string;
        out : T.var;
        inputs : T.expr list;
      }
    | Ystr_regex_replace of {
        regex : string;
        replace : T.expr;
        out : T.var;
        inputs : T.expr list;
      }
    | Ystr_regex_quote of { out : T.var; inputs : T.expr list }
    | Ystr_append of { cvar : T.var; inputs : T.expr list }
    | Ystr_prepend of { cvar : T.var; inputs : T.expr list }
    | Ystr_join of { glue : T.expr; out : T.var; inputs : T.expr list }
    | Ystr_find of {
        string : T.expr;
        substring : T.expr;
        out : T.var;
        reverse : bool;
      }
    | Ystr_substring of {
        string : T.expr;
        begin_ : int;
        length : int option;
        out : T.var;
      }
    | Ystr_repeat of { string : T.expr; count : int; out : T.var }
    | Ystr_genex_strip of { string : T.expr; out : T.var }
    | Ystr_compare of {
        op : Lang_cmake.string_compare_op;
        string1 : T.expr;
        string2 : T.expr;
        out : T.var;
      }
    | Ystr_make_c_identifier of { string : T.expr; out : T.var }
    | Ystr_timestamp of { out : T.var; format : string option; utc : bool }
    | Ystr_hex of { string : T.expr; out : T.var }
    | Ystr_uuid of {
        out : T.var;
        namespace : string;
        name : string;
        type_ : [ `Md5 | `Sha1 ];
        upper : bool;
      }
    | Ystr_json of {
        out : T.var;
        error_var : T.var option;
        op : yelu_json_op;
      }
end

module Make_string_check (T : LANG_TYPES) = struct
  include Make_string_op (T)
  let stage = Stage_typecheck

  (* Returns: (errors, output bindings) — each string op writes to an out var
     with a known type; the walker uses the bindings to extend the env. *)
  let check ~(type_of : T.expr -> yelu_type)
      : yelu_string_stmt -> type_error list * (T.var * yelu_type) list =
    let str e ctx = check_compat ~context:ctx Ty_string (type_of e) in
    let strs es ctx = List.concat_map es ~f:(fun e -> str e ctx) in
    function
    | Ystr_toupper { string; out } | Ystr_tolower { string; out }
    | Ystr_strip { string; out } | Ystr_genex_strip { string; out } ->
      str string "string op", [(out, Ty_string)]
    | Ystr_length { string; out } ->
      str string "str_length", [(out, Ty_int)]
    | Ystr_concat { out; inputs } ->
      strs inputs "str_concat", [(out, Ty_string)]
    | Ystr_append { cvar; inputs } | Ystr_prepend { cvar; inputs } ->
      strs inputs "str_append", [(cvar, Ty_string)]
    | Ystr_join { glue; out; inputs } ->
      str glue "str_join glue" @ strs inputs "str_join item", [(out, Ty_string)]
    | Ystr_replace { match_string; replace_string; out; inputs } ->
      str match_string "str_replace match"
      @ str replace_string "str_replace with"
      @ strs inputs "str_replace input",
      [(out, Ty_string)]
    | Ystr_regex_match { out; inputs; _ } | Ystr_regex_matchall { out; inputs; _ }
    | Ystr_regex_quote { out; inputs } ->
      strs inputs "str_regex", [(out, Ty_string)]
    | Ystr_regex_replace { replace; out; inputs; _ } ->
      str replace "str_regex_replace with" @ strs inputs "str_regex_replace input",
      [(out, Ty_string)]
    | Ystr_find { string; substring; out; _ } ->
      str string "str_find string" @ str substring "str_find sub", [(out, Ty_int)]
    | Ystr_substring { string; out; _ } ->
      str string "str_substring", [(out, Ty_string)]
    | Ystr_repeat { string; out; _ } ->
      str string "str_repeat", [(out, Ty_string)]
    | Ystr_compare { string1; string2; out; _ } ->
      str string1 "str_compare lhs" @ str string2 "str_compare rhs", [(out, Ty_bool)]
    | Ystr_make_c_identifier { string; out } ->
      str string "str_c_id", [(out, Ty_string)]
    | Ystr_hex { string; out } ->
      str string "str_hex", [(out, Ty_string)]
    | Ystr_timestamp { out; _ } -> [], [(out, Ty_string)]
    | Ystr_uuid { out; _ } -> [], [(out, Ty_string)]
    | Ystr_json { out; error_var; _ } ->
      let outs = (out, Ty_string) ::
        Option.to_list (Option.map error_var ~f:(fun v -> (v, Ty_string))) in
      [], outs
end
