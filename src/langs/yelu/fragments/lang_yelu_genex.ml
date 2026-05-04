open Base

(* Generator expressions — cmake's functional sublanguage.
   Composed at configure-time, evaluated lazily at build-time.
   Pure and applicative; structurally distinct from both statement-level
   theories (cond, string) and cmake meta/scripting (Make_cmake_op). *)

type yelu_genex =
  (* logical *)
  | Yge_config of string          (* $<CONFIG:cfg> *)
  | Yge_not of yelu_genex         (* $<NOT:g> *)
  | Yge_and of yelu_genex list    (* $<AND:g1,g2,...> *)
  | Yge_or of yelu_genex list     (* $<OR:g1,g2,...> *)
  | Yge_if of yelu_genex * yelu_genex * yelu_genex (* $<IF:cond,t,f> *)
  | Yge_bool of string            (* $<BOOL:s> *)
  (* target *)
  | Yge_target_file of string     (* $<TARGET_FILE:tgt> *)
  | Yge_target_file_dir of string (* $<TARGET_FILE_DIR:tgt> *)
  | Yge_target_property of string * string (* $<TARGET_PROPERTY:tgt,prop> *)
  (* interface *)
  | Yge_install_interface of yelu_genex (* $<INSTALL_INTERFACE:...> *)
  | Yge_build_interface of yelu_genex   (* $<BUILD_INTERFACE:...> *)
  (* string ops *)
  | Yge_strequal of string * string  (* $<STREQUAL:a,b> *)
  | Yge_lower_case of yelu_genex     (* $<LOWER_CASE:...> *)
  | Yge_upper_case of yelu_genex     (* $<UPPER_CASE:...> *)
  (* platform / language *)
  | Yge_compile_language of string   (* $<COMPILE_LANGUAGE:lang> *)
  | Yge_platform_id of string        (* $<PLATFORM_ID:id> *)
  (* escape hatch *)
  | Yge_raw of string                (* $<raw> — user supplies full inner content *)

let rec genex_to_string = function
  | Yge_config cfg -> Printf.sprintf "$<CONFIG:%s>" cfg
  | Yge_not g -> Printf.sprintf "$<NOT:%s>" (genex_to_string g)
  | Yge_and gs -> Printf.sprintf "$<AND:%s>" (String.concat ~sep:"," (List.map gs ~f:genex_to_string))
  | Yge_or gs -> Printf.sprintf "$<OR:%s>" (String.concat ~sep:"," (List.map gs ~f:genex_to_string))
  | Yge_if (c, t, f) -> Printf.sprintf "$<IF:%s,%s,%s>" (genex_to_string c) (genex_to_string t) (genex_to_string f)
  | Yge_bool s -> Printf.sprintf "$<BOOL:%s>" s
  | Yge_target_file tgt -> Printf.sprintf "$<TARGET_FILE:%s>" tgt
  | Yge_target_file_dir tgt -> Printf.sprintf "$<TARGET_FILE_DIR:%s>" tgt
  | Yge_target_property (tgt, prop) -> Printf.sprintf "$<TARGET_PROPERTY:%s,%s>" tgt prop
  | Yge_install_interface g -> Printf.sprintf "$<INSTALL_INTERFACE:%s>" (genex_to_string g)
  | Yge_build_interface g -> Printf.sprintf "$<BUILD_INTERFACE:%s>" (genex_to_string g)
  | Yge_strequal (a, b) -> Printf.sprintf "$<STREQUAL:%s,%s>" a b
  | Yge_lower_case g -> Printf.sprintf "$<LOWER_CASE:%s>" (genex_to_string g)
  | Yge_upper_case g -> Printf.sprintf "$<UPPER_CASE:%s>" (genex_to_string g)
  | Yge_compile_language lang -> Printf.sprintf "$<COMPILE_LANGUAGE:%s>" lang
  | Yge_platform_id id -> Printf.sprintf "$<PLATFORM_ID:%s>" id
  | Yge_raw s -> s
