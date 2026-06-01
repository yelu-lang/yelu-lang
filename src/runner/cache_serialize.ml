(** Serialize the [cache_vars] portion of a yelu_cmake [env] to a text
    file in a shape comparable to a real cmake-emitted CMakeCache.txt.

    This is the OUTPUT side of the predicted-vs-actual cache testing
    combination: both real cmake's CMakeCache.txt (parsed elsewhere)
    and yc-eval's [env.cache_vars] need to land on disk in comparable
    shapes so we can diff per-input.

    Eval-core (yelu_cmake.ml) stays I/O-free; this module owns disk
    side effects for the predicted cache. *)

open Base
module Yc = Yelu_langs.Yelu_cmake

let rec mkdirp path =
  if Stdlib.Sys.file_exists path then ()
  else begin
    mkdirp (Stdlib.Filename.dirname path);
    try Unix.mkdir path 0o755
    with Unix.Unix_error (Unix.EEXIST, _, _) -> ()
  end

(** Render a single [value] into the text form CMakeCache.txt would
    carry for a cache entry. Returns [None] for shapes that don't make
    sense as a cache entry (lists, unit, target handles) — caller emits
    a warning comment for those. *)
let cache_value_str (v : Yc.value) : string option =
  match v with
  | Yc.VString s -> Some s
  | Yc.VBool true -> Some "ON"
  | Yc.VBool false -> Some "OFF"
  | Yc.VInt n -> Some (Int.to_string n)
  | Yc.VList _ | Yc.VUnit | Yc.VTarget _ -> None

let write_predicted_cache ~(env : Yc.env) ~(path : string) : unit =
  mkdirp (Stdlib.Filename.dirname path);
  (* Iterate the cache map in name-sorted order. [Map.to_alist] on a
     [Map.M(String).t] yields ascending-key order by construction. *)
  let entries = Map.to_alist env.cache_vars in
  let rendered, skipped =
    List.partition_map entries ~f:(fun (name, v) ->
      match cache_value_str v with
      | Some s -> First (name, s)
      | None -> Second name)
  in
  let oc = Stdlib.open_out path in
  Stdlib.Fun.protect
    ~finally:(fun () -> Stdlib.close_out_noerr oc)
    (fun () ->
      Stdlib.Printf.fprintf oc "# yelu_cmake predicted cache (%d entries)\n"
        (List.length rendered);
      List.iter skipped ~f:(fun name ->
        Stdlib.Printf.fprintf oc
          "# warning: skipped non-cache-shaped entry %s\n" name);
      List.iter rendered ~f:(fun (name, value) ->
        Stdlib.Printf.fprintf oc "%s=%s\n" name value))
