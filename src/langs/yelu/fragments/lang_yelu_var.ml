open Base
open Lang_yelu_type

(* ============================================================
   Variable & Cache Theory — cmake namespace semantics

   cmake has three overlapping namespaces for named values:
     Variable  — set(NAME val), ${NAME}, if(DEFINED NAME)
     Cache     — set(NAME val CACHE TYPE "doc"), -DNAME=val, $CACHE{NAME}
     Env       — set(ENV{NAME} val), $ENV{NAME}

   Write-once persistent binding.  "Cache" is misleading — it is not a cache
   (you cannot recompute).  It is a write-once persistent value: once set (by
   the program, or by -D), the program cannot change it.  Only -D (user
   override) or -U / deleting CMakeCache.txt can reset it.

   Dual-write trap.  On first configure, set(...CACHE...) writes to BOTH the
   Cache and Variable namespaces.  On re-configure (cache entry already
   exists), it is a no-op for BOTH — the variable is NOT re-set.  This means
   the same program text has different behavior depending on whether a build
   directory already exists.  The dual-write is an implementation artifact:
   it makes the persistent value visible to ${NAME} without requiring
   $CACHE{NAME} everywhere.  But it creates non-idempotent semantics.

   Decision tree (verified against cmake 4.3.1, 15 tests in test_set.ml):

   Write
     set(NAME val CACHE ...)
     ├── cache entry exists? → NO-OP (writes nothing)
     └── no                 → write NAME=val to BOTH Cache AND Variable
     set(NAME val)           → always writes Variable
     -DNAME=val              → always writes Cache only
     unset(NAME)             → removes Variable  only
     unset(NAME CACHE)       → removes BOTH Cache AND Variable

   Read
     ${NAME} / if(DEFINED NAME)
     ├── Variable has NAME (non-empty)? → return it / true
     └── no → Cache has NAME?           → return it / true  [fallback]
                                   └── no → "" / false
     $CACHE{NAME} / if(DEFINED CACHE{NAME})
     └── Cache has NAME? → return it / true, else "" / false

   Equivalences (provable):
     option(VAR "msg" ON)  ≡ set(VAR ON  CACHE BOOL "msg")
     option(VAR "msg" OFF) ≡ set(VAR OFF CACHE BOOL "msg")

   Future split.  The six constructors below mix three namespaces.  A clean
   split would move Yvar_option / Yvar_set_cache / Yvar_unset_cache into a
   separate `cache` theory owning the write-once semantics, the dual-write
   behavior, and the persistence model.  See doc/cmake_cache_semantics.md.
   ============================================================ *)

module Make_var_op (T : LANG_TYPES) = struct
  type yelu_var_stmt =
    (* Variable namespace: set(), if(DEFINED), ${} *)
    | Yvar_set of { cvar : T.var; values : T.expr list; parent_scope : bool }
    | Yvar_option of { cvar : T.var; msg : string; value : T.expr }
    | Yvar_set_cache of {
        cvar : T.var;
        values : T.expr list;
        cache_type : Lang_cmake.cache_type;
        docstring : string;
        force : bool;
      }
    | Yvar_unset_cache of { cvar : T.var }
    (* Env namespace: $ENV{}, set(ENV{}) *)
    | Yvar_set_env of { var : string; value : T.expr }
    | Yvar_unset_env of { var : string }
end

module Make_var_check (T : LANG_TYPES) = struct
  include Make_var_op (T)
  let stage = Stage_typecheck

  let cache_type_to_yelu_type = function
    | Lang_cmake.Ct_bool -> Ty_bool
    | Lang_cmake.Ct_path | Lang_cmake.Ct_filepath -> Ty_path
    | Lang_cmake.Ct_string | Lang_cmake.Ct_internal -> Ty_string

  let check ~(type_of : T.expr -> yelu_type)
      : yelu_var_stmt -> type_error list * (T.var * yelu_type) list =
    let strs es ctx =
      List.concat_map es ~f:(fun e -> check_compat ~context:ctx Ty_string (type_of e))
    in
    function
    | Yvar_set { cvar; values; _ } ->
      strs values "var_set", [(cvar, Ty_string)]
    | Yvar_option { cvar; value; _ } ->
      check_compat ~context:"option" Ty_bool (type_of value), [(cvar, Ty_bool)]
    | Yvar_set_cache { cvar; values; cache_type; _ } ->
      strs values "set_cache", [(cvar, cache_type_to_yelu_type cache_type)]
    | _ -> [], []
end
