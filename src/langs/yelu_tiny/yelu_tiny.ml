open Base

type expr = ..

type target_source = {
  visibility : string;
  source : string;
}
[@@deriving equal, sexp_of]

type target_link = {
  visibility : string;
  item : string;
}
[@@deriving equal, sexp_of]

type target_include_dir = {
  visibility : string;
  dir : string;
}
[@@deriving equal, sexp_of]

type target = {
  name : string;
  sources : target_source list;
  link_libraries : target_link list;
  include_directories : target_include_dir list;
}
[@@deriving equal, sexp_of]

type value =
  | VString of string
  | VBool of bool
  | VInt of int
  | VList of value list
  | VTarget of string
  | VUnit
[@@deriving equal, sexp_of]

type env = {
  vars : value Map.M(String).t;
  targets : target Map.M(String).t;
}

let empty_env : env =
  {
    vars = Map.empty (module String);
    targets = Map.empty (module String);
  }

let equal_env left right =
  Map.equal equal_value left.vars right.vars
  && Map.equal equal_target left.targets right.targets

let empty_target name =
  {
    name;
    sources = [];
    link_libraries = [];
    include_directories = [];
  }

let find_var env name = Map.find env.vars name

let set_var env ~key ~data =
  { env with vars = Map.set env.vars ~key ~data }

let remove_var env name =
  { env with vars = Map.remove env.vars name }

let var_defined env name =
  Map.mem env.vars name

let find_target env name = Map.find env.targets name

let set_target env target =
  { env with targets = Map.set env.targets ~key:target.name ~data:target }

let update_target env name ~f =
  match find_target env name with
  | None -> failwith ("unknown target " ^ name)
  | Some target -> set_target env (f target)

exception Eval_error of string

let fail fmt = Fmt.kstr (fun msg -> raise (Eval_error msg)) fmt

let rec string_of_value = function
  | VString s -> s
  | VBool b -> if b then "true" else "false"
  | VInt n -> Int.to_string n
  | VList values ->
    values
    |> List.map ~f:string_of_value
    |> String.concat ~sep:";"
  | VTarget name -> name
  | VUnit -> "()"

let expect_string = function
  | VString s -> s
  | v -> fail "expected string, got %s" (Sexp.to_string ([%sexp_of: value] v))

let expect_int = function
  | VInt n -> n
  | v -> fail "expected int, got %s" (Sexp.to_string ([%sexp_of: value] v))

let expect_list = function
  | VList values -> values
  | v -> fail "expected list, got %s" (Sexp.to_string ([%sexp_of: value] v))

let expect_target = function
  | VTarget name -> name
  | v -> fail "expected target, got %s" (Sexp.to_string ([%sexp_of: value] v))

type expr +=
  | EVar of string
  | EString of string
  | EBool of bool
  | EInt of int
  | EUnit
  | ESetVar of string * expr
  | ESeq of expr list
