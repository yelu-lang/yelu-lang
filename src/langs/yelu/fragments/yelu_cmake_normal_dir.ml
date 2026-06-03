open Base
open Yelu_cmake
open Yelu_cmake_normal_target

let name = "tiny_dir"
let requires = [ "core.string"; "path" ]
let provides = [ "dir.add_subdirectory" ]

type expr +=
  | EAddSubdirectory of expr

(* Resolve [source_dir] (the literal arg from add_subdirectory()) against
   CMAKE_CURRENT_SOURCE_DIR. Absolute paths are kept as-is. Trailing
   slashes normalized away. *)
let resolve_subdir env source_dir =
  if Stdlib.Filename.is_relative source_dir then
    let current_source_dir =
      match find_var env "CMAKE_CURRENT_SOURCE_DIR" with
      | Some (VString s) when not (String.is_empty s) -> s
      | _ -> Stdlib.Sys.getcwd ()
    in
    Stdlib.Filename.concat current_source_dir source_dir
  else source_dir

let eval_case ~eval env = function
  | EAddSubdirectory path ->
    let env, path = eval_string ~eval env path in
    let env = add_subdirectory env path in
    (* I/O-free fallback: no loader registered → bookkeeping only.
       Pre-2026 behavior; tests that don't need real recursion don't
       have to opt in. *)
    (match env.subdir_loader with
     | None -> Some (env, VUnit)
     | Some loader ->
       let resolved = resolve_subdir env path in
       (* Cycle protection: share include_stack with include() since both
          chain through file loads. cmake itself errors on direct cycles;
          we soft-skip for predictor stability. *)
       if List.mem env.include_stack resolved ~equal:String.equal then
         Some (env, VUnit)
       else
         (match loader resolved with
          | None -> Some (env, VUnit)
          | Some subdir_expr ->
            (* cmake's directory scope: new variable frame inheriting
               parent's vars (push_frame), updated CMAKE_CURRENT_SOURCE_DIR
               + LIST_DIR. Cache writes still target the global cache_vars
               (they're not in the frame). At return: pop_frame discards
               local var changes, restores parent's path vars. *)
            let saved_source_dir = find_var env "CMAKE_CURRENT_SOURCE_DIR" in
            let saved_list_dir = find_var env "CMAKE_CURRENT_LIST_DIR" in
            let env =
              { env with include_stack = resolved :: env.include_stack }
            in
            let env = push_frame env in
            let env =
              set_var env ~key:"CMAKE_CURRENT_SOURCE_DIR"
                ~data:(VString resolved)
            in
            let env =
              set_var env ~key:"CMAKE_CURRENT_LIST_DIR"
                ~data:(VString resolved)
            in
            (* Soft-fail on eval errors inside the subdir. Real cmake
               directories often use commands we don't model (custom
               targets, file glob, target_*, etc.) — a crash here would
               abort the whole prediction. Errors get swallowed; what
               WAS evaluated (cache writes, etc.) before the error is
               retained because the env at the point of failure is lost.
               Predictor still moves forward on the parent. *)
            let env =
              try
                let env, _ = eval env subdir_expr in env
              with Eval_error _ -> env
            in
            let env = pop_frame env in
            let restore env key v =
              match v with
              | Some v -> set_var env ~key ~data:v
              | None -> remove_var env key
            in
            let env = restore env "CMAKE_CURRENT_SOURCE_DIR" saved_source_dir in
            let env = restore env "CMAKE_CURRENT_LIST_DIR" saved_list_dir in
            let env =
              { env with
                include_stack =
                  List.tl env.include_stack |> Option.value ~default:[] }
            in
            Some (env, VUnit)))
  | _ -> None
