(* Cmake_stdlib_names — runtime API for the cmake-stdlib name set.

   First instance of the discovered-cache pattern
   (doc/yelu_cmake/discovered_cache.md). The pattern:

   1. discover  — generate the TSV (one-time, against cmake's Modules/)
   2. cache     — commit tool/cmake_text/cmake_stdlib_names.tsv with a
                  version fingerprint in the header
   3. embed     — dune rule produces Cmake_stdlib_names_data.ml with
                  the names + fingerprint as compile-time constants
   4. validate  — on demand, report the fingerprint so the user can
                  decide whether to regenerate (option (d) — no
                  automatic file-system check; cmake is a build-time
                  requirement only, not a runtime one)

   Used by Yc_wellform.check_unknown_command to silence false-positive
   warnings on legitimate cmake-stdlib calls (cmake_parse_arguments,
   check_language, …) without forcing yc_raw. Also enables closed-world
   escalation on files that use these calls — the file is still
   closed-world (no opening construct), so a stdlib-known name is silent
   but an unknown name escalates to fatal. *)

open Base

let names_set : Set.M(String).t =
  Set.of_array (module String) Cmake_stdlib_names_data.names

(* Case-insensitive lookup matches cmake's call semantics. *)
let mem (name : string) : bool =
  Set.mem names_set (String.lowercase name)

(* For diagnostics / `yelu manifest` / docs. *)
let cmake_version_at_cache : string =
  Cmake_stdlib_names_data.cmake_version_at_cache

let generated_date : string =
  Cmake_stdlib_names_data.generated_date

let count : int = Set.length names_set
