open Base
open Yelu_cmake

let name = "tiny_cmake_find"
let requires = [ "core.string" ]
let provides = [ "find.find_package" ]

type expr +=
  | ECmakeFindPackage of
      { package_name : string;
        version : string option;
        exact : bool;
        quiet : bool;
        config_mode : bool;
        required : bool;
        components : string list;
        optional_components : string list;
      }
  (* find_library / find_path / find_program / find_file — same shape,
     different cmake command. Eval stub: bind out_var to placeholder
     (real path search happens at cmake configure). *)
  | ECmakeFindLibrary of {
      out : string; names : expr list; paths : expr list;
      hints : expr list; required : bool
    }
  | ECmakeFindPath of {
      out : string; names : expr list; paths : expr list;
      hints : expr list; required : bool
    }
  | ECmakeFindProgram of {
      out : string; names : expr list; paths : expr list;
      hints : expr list; required : bool
    }
  | ECmakeFindFile of {
      out : string; names : expr list; paths : expr list;
      hints : expr list; required : bool
    }

(* Packages we hard-code as "found" with no version (Threads is the
   poster child — UNIX systems all have pthread, real cmake's
   FindThreads.cmake almost always succeeds). For these, find_package()
   writes `FIND_PACKAGE_MESSAGE_DETAILS_<pkg>` to cache with the same
   "[TRUE][v()]" format real cmake's FindPackageHandleStandardArgs uses
   on success.

   Other packages stay bookkeeping-only — predicting "found" for a
   package that isn't installed would create pred-only divergences;
   predicting "not found" for one that is installed would create
   mismatches. The whitelist is the conservative path: extend as
   specific projects need it. *)
let assumed_found_packages = [ "Threads" ]

let eval_case ~eval:_ env = function
  | ECmakeFindPackage { package_name; required; _ } ->
    let env = add_find_package env { package_name; required } in
    let env =
      if List.mem assumed_found_packages package_name ~equal:String.equal
      then
        let key = "FIND_PACKAGE_MESSAGE_DETAILS_" ^ package_name in
        set_cache_var env ~key ~data:(VString "[TRUE][v()]")
      else env
    in
    Some (env, VUnit)
  | ECmakeFindLibrary { out; _ }
  | ECmakeFindPath { out; _ }
  | ECmakeFindProgram { out; _ }
  | ECmakeFindFile { out; _ } ->
    (* Safe stub: assume the binary/library/path/file isn't found.
       Writes `<OUT>-NOTFOUND` to BOTH the local var (so subsequent
       `if(<OUT>)` reads see the NOTFOUND state) AND the cache (real
       cmake writes find_program results to cache so re-configures
       don't re-search). Wrong direction when the target IS installed
       — that'd flip to a mismatch instead of a real-only entry.
       Matches matrix probe environment where common dev tools like
       doxygen aren't installed. *)
    let value = out ^ "-NOTFOUND" in
    let env = set_var env ~key:out ~data:(VString value) in
    let env = set_cache_var env ~key:out ~data:(VString value) in
    Some (env, VUnit)
  | _ -> None
