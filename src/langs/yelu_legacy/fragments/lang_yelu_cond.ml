open Lang_yelu_type

module Make_cond (T : LANG_TYPES) = struct
  type yelu_cond =
    | Ytruthy of T.expr
    | Ynot of yelu_cond
    | Yand of yelu_cond * yelu_cond
    | Yor of yelu_cond * yelu_cond
    | Yis_target of T.expr
    | Yis_defined of T.expr
    | Ystrequal of T.expr * T.expr
    | Ystrless of T.expr * T.expr
    | Ystrgreater of T.expr * T.expr
    | Ystrless_equal of T.expr * T.expr
    | Ystrgreater_equal of T.expr * T.expr
    | Yequal of T.expr * T.expr
    | Yless of T.expr * T.expr
    | Ygreater of T.expr * T.expr
    | Yless_equal of T.expr * T.expr
    | Ygreater_equal of T.expr * T.expr
    | Yin_list of T.expr * T.expr
    | Ymatches of T.expr * string
    | Yexists of T.expr
    | Yis_directory of T.expr
    | Yis_absolute of T.expr
    | Ypolicy_defined of string
    | Yversion_less of T.expr * T.expr
    | Yversion_greater of T.expr * T.expr
    | Yversion_equal of T.expr * T.expr
    | Yversion_less_equal of T.expr * T.expr
    | Yversion_greater_equal of T.expr * T.expr
end

module Make_cond_check (T : LANG_TYPES) = struct
  include Make_cond (T)
  let stage = Stage_typecheck

  let rec check ~(type_of : T.expr -> yelu_type) = function
    | Ytruthy e ->
      check_compat ~context:"truthy" Ty_string (type_of e)
    | Ynot c -> check ~type_of c
    | Yand (c1, c2) | Yor (c1, c2) ->
      check ~type_of c1 @ check ~type_of c2
    | Yis_target e ->
      check_compat ~context:"if(TARGET)" Ty_string (type_of e)
    | Yis_defined e ->
      check_compat ~context:"if(DEFINED)" Ty_string (type_of e)
    | Ystrequal (e1, e2) | Ystrless (e1, e2) | Ystrgreater (e1, e2)
    | Ystrless_equal (e1, e2) | Ystrgreater_equal (e1, e2) ->
      check_compat ~context:"str_cmp" Ty_string (type_of e1)
      @ check_compat ~context:"str_cmp" Ty_string (type_of e2)
    | Yequal (e1, e2) | Yless (e1, e2) | Ygreater (e1, e2)
    | Yless_equal (e1, e2) | Ygreater_equal (e1, e2) ->
      check_compat ~context:"num_cmp" Ty_int (type_of e1)
      @ check_compat ~context:"num_cmp" Ty_int (type_of e2)
    | Yin_list (e, lst) ->
      let lst_err = match type_of lst with
        | Ty_list _ | Ty_any -> []
        | got -> [ Type_mismatch { expected = Ty_list Ty_any; got; context = "IN_LIST list" } ]
      in
      check_compat ~context:"IN_LIST item" Ty_string (type_of e) @ lst_err
    | Ymatches (e, _) ->
      check_compat ~context:"MATCHES" Ty_string (type_of e)
    | Yexists e | Yis_directory e | Yis_absolute e ->
      check_compat ~context:"path_check" Ty_path (type_of e)
    | Ypolicy_defined _ -> []
    | Yversion_less (e1, e2) | Yversion_greater (e1, e2)
    | Yversion_equal (e1, e2) | Yversion_less_equal (e1, e2)
    | Yversion_greater_equal (e1, e2) ->
      check_compat ~context:"version_cmp" Ty_version (type_of e1)
      @ check_compat ~context:"version_cmp" Ty_version (type_of e2)
end
