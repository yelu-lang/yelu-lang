(* Cache variable name classification — implements the classifier
   from doc/cmake/cache_var_namespacing.md.

   Distinguishes:
   - cmake-emitted (CMAKE_*, CTEST_*, CPACK_*, HAVE_*, …)
   - build-convention (BUILD_SHARED_LIBS, BUILD_TESTING)
   - project-declared (matches a name from cache_vars.exe output)
   - unknown (everything else — either a static-walker miss or a
     dynamically-emitted decl)

   Used by the eval-vs-real-cmake oracle to filter out cmake's
   ~150 housekeeping cache entries and surface the ~10-20
   project entries as the comparison signal. *)

open Base

type tier =
  | Project           (* in the project-declared namelist *)
  | Reserved_cmake    (* matches `cmake --help-variable-list` or known prefix *)
  | Reserved_build    (* BUILD_SHARED_LIBS / BUILD_TESTING convention *)
  | Unknown           (* neither — either bridge gap or dynamic decl *)
[@@deriving equal, sexp_of]

(* Hand-curated short list: build-convention vars that ARE
   user-settable options but live outside any project's
   declaration set. Extend as we hit more. *)
let build_conventions =
  [ "BUILD_SHARED_LIBS"; "BUILD_TESTING" ]

(* Prefix patterns for the cmake-emitted namespace. These cover the
   bulk of `cmake --help-variable-list` plus probe-emitted names
   like HAVE_FNO_EXCEPTIONS_FLAG that aren't in the list but follow
   convention. *)
let reserved_prefixes =
  [ "CMAKE_"; "CTEST_"; "CPACK_";
    "HAVE_"; "CMAKE_HAVE_";
    "FETCHCONTENT_" ]

(* Suffix patterns: cmake's _FOUND / _INTERNAL / _PRIVATE
   conventions for probe / module results. *)
let reserved_suffixes =
  [ "_FOUND"; "_INTERNAL"; "_PRIVATE" ]

let has_prefix s prefix = String.is_prefix s ~prefix
let has_suffix s suffix = String.is_suffix s ~suffix

(* Substitute `<PROJECT-NAME>` and `<PackageName>` placeholders in
   the reserved list with the current project name. The result is
   the per-project reserved name set. *)
let expand_placeholders ~project_name names =
  List.concat_map names ~f:(fun n ->
    if String.is_substring n ~substring:"<PROJECT-NAME>" then
      [ String.substr_replace_all n
          ~pattern:"<PROJECT-NAME>" ~with_:project_name ]
    else if String.is_substring n ~substring:"<PackageName>" then
      (* For find_package'd names we don't know the substitution
         here — skip for now. (Caveat in doc § 7.) *)
      []
    else [ n ])

(* The classifier. Precedence:
   project > reserved-by-name > build-convention > reserved-by-pattern > unknown.

   Project FIRST so a project can shadow a reserved name (rare but
   possible; matches project intent). *)
let classify ~project ~reserved name =
  let proj_set =
    Set.of_list (module String) project
  in
  let res_set =
    Set.of_list (module String) reserved
  in
  if Set.mem proj_set name then Project
  else if Set.mem res_set name then Reserved_cmake
  else if List.mem build_conventions name ~equal:String.equal then
    Reserved_build
  else if List.exists reserved_prefixes ~f:(has_prefix name) then
    Reserved_cmake
  else if List.exists reserved_suffixes ~f:(has_suffix name) then
    Reserved_cmake
  else
    Unknown

let tier_to_string = function
  | Project -> "project"
  | Reserved_cmake -> "reserved-cmake"
  | Reserved_build -> "reserved-build"
  | Unknown -> "unknown"

(* Helper: load the reserved name list from `cmake --help-variable-list`
   output captured in a TSV / line-per-name file. Falls back to an
   empty list if the file doesn't exist (the prefix patterns still
   apply). *)
let load_reserved_from_file path : string list =
  if not (Stdlib.Sys.file_exists path) then []
  else begin
    let ic = Stdlib.open_in path in
    let lines = ref [] in
    (try while true do
       let l = String.strip (Stdlib.input_line ic) in
       if not (String.is_empty l) then lines := l :: !lines
     done with End_of_file -> ());
    Stdlib.close_in ic;
    List.rev !lines
  end

(* Helper: load the project name list from cache_vars.exe TSV
   output. The TSV is one decl per line; the first column is the
   name. *)
let load_project_from_tsv path : string list =
  if not (Stdlib.Sys.file_exists path) then []
  else begin
    let ic = Stdlib.open_in path in
    let names = ref [] in
    (try while true do
       let line = Stdlib.input_line ic in
       match String.lsplit2 line ~on:'\t' with
       | Some (name, _) when not (String.is_empty name) ->
         names := name :: !names
       | _ -> ()
     done with End_of_file -> ());
    Stdlib.close_in ic;
    List.rev !names
  end
