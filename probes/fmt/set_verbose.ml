(* Hybrid yelu-cmake pilot — fmt's set_verbose + join helpers.

   Reproduces fmt's helpers (CMakeLists.txt lines 18-39) in yelu IR;
   [Yelu_cmake_emit.emit_ast] lowers to Lang_cmake.exp; Lang_cmake_pp
   prints cmake text. Goal: byte-equivalent output (modulo gersemi
   whitespace normalization) to the original fmt block.

   This is step 1.a of the hybrid pilot — text-level codegen only,
   no build oracle. See doc/yelu_cmake/hybrid_strategy.md § "Pilot
   path". *)

open Yelu_langs.Yelu_cmake
open Yelu_langs.Yelu_cmake_utils
open Yelu_langs.Yelu_cmake_store

let helpers =
  ESeq [
    (* function (join result_var)
         set(result "")
         foreach (arg ${ARGN})
           set(result "${result}${arg}")
         endforeach ()
         set(${result_var} "${result}" PARENT_SCOPE)
       endfunction () *)
    (* Note on quoting: EVar "X" renders bare as `${X}` in arg position;
       EString "${X}" renders quoted as `"${X}"`. Fmt's source uses bare
       form, so we use EVar for var refs in arg positions. The
       EString "${result}${arg}" stays quoted because it's an interpolated
       template, which matches fmt's quoted form. *)
    yc_function (ystr "join") ["result_var"] [
      yc_set (ycvar "result") [ystr ""];
      yc_foreach ~items:[EVar "ARGN"] (ycvar "arg") (
        yc_set (ycvar "result") [ystr "${result}${arg}"]);
      (* Use EString here, not EVar — fmt's source has `"${result}"`
         quoted in this position (vs bare in set_verbose's `${value}`).
         Inconsistent within fmt's own source, so we match per-line. *)
      yc_set ~parent_scope:true (ycvar "${result_var}") [ystr "${result}"];
    ];

    (* function (set_verbose variable value _cache type)
         join(doc ${ARGN})
         set(${variable}
             ${value}
             CACHE ${type} ${doc})
       endfunction () *)
    yc_function
      (ystr "set_verbose")
      ["variable"; "value"; "_cache"; "type"]
      [
        yc_apply (ystr "join") [ystr "doc"; EVar "ARGN"];
        ECmakeSetCache {
          name = "${variable}";
          values = [EVar "value"];
          cache_type = "${type}";
          docstring = "${doc}";
          force = false;
        };
      ];
  ]

let () = Yelu_langs.Yelu_emit_main.print helpers
