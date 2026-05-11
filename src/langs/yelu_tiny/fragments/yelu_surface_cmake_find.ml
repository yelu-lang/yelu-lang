open Yelu_tiny

let name = "tiny_cmake_find"
let requires = [ "core.string" ]
let provides = [ "find.find_package" ]

type expr +=
  | ECmakeFindPackage of { package_name : string; required : bool }
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

let eval_case ~eval:_ env = function
  | ECmakeFindPackage { package_name; required } ->
    Some (add_find_package env { package_name; required }, VUnit)
  | ECmakeFindLibrary { out; _ }
  | ECmakeFindPath { out; _ }
  | ECmakeFindProgram { out; _ }
  | ECmakeFindFile { out; _ } ->
    Some (set_var env ~key:out ~data:(VString (out ^ "-NOTFOUND")), VUnit)
  | _ -> None
