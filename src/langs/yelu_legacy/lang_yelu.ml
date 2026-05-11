(** Parametric AST shapes for yelu — aggregates all theory groups.

    [LANG_TYPES] and the type universe live in [Lang_yelu_type].
    All theory groups are split to [fragments/], each paired with its
    S0 type checker.
    [Make_stmt] bundles all theories at a given substrate; packs instantiate
    it once with [include Lang_yelu.Make_stmt (My_types)]. *)

module type LANG_TYPES = Lang_yelu_type.LANG_TYPES

(* [Make_stmt] is a functor application bundle — it [include]s every
   per-group functor at a given substrate [T] so a pack can pull all
   group types and constructors into its top-level namespace with one
   [include Lang_yelu.Make_stmt (My_types)].

   The top-level [yelu_stmt] sum type (which weaves group statements
   with cmake-specific scripting and control flow) does NOT live here —
   each pack composes its own statement type from these group bundles
   plus its pack-specific scripting vocabulary. *)
module Make_stmt (T : LANG_TYPES) = struct
  include Lang_yelu_string.Make_string_op (T)
  include Lang_yelu_target.Make_target_op (T)
  include Lang_yelu_file.Make_file_io_op (T)
  include Lang_yelu_path.Make_path_op (T)
  include Lang_yelu_list.Make_list_op (T)
  include Lang_yelu_var.Make_var_op (T)
  include Lang_yelu_property.Make_property_op (T)
  include Lang_yelu_find.Make_find_op (T)
  include Lang_yelu_install.Make_install_op (T)
  include Lang_yelu_test.Make_test_op (T)
  include Lang_yelu_try.Make_try_op (T)
  include Lang_yelu_dir.Make_dir_op (T)
  include Lang_yelu_cmake_op.Make_cmake_op (T)
end
