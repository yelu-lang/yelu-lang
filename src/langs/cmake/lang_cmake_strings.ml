(* CMake enum → string converters.

   Each cmake_* enum type in [Lang_cmake] has a canonical cmake-text
   spelling. Centralised here so callers (both the legacy-to-yelu
   bridge and the yelu_cmake ctor module) share one source of truth.

   The functions are pure exhaustive matches; they panic at compile
   time if a new ctor lands in [Lang_cmake] without a corresponding
   case here. *)

open Base

let of_cmake_path_get_field : Lang_cmake.cmake_path_get_field -> string =
  function
  | Cpf_root_name -> "ROOT_NAME"
  | Cpf_root_directory -> "ROOT_DIRECTORY"
  | Cpf_root_path -> "ROOT_PATH"
  | Cpf_filename -> "FILENAME"
  | Cpf_extension last_only ->
    if last_only then "EXTENSION LAST_ONLY" else "EXTENSION"
  | Cpf_stem last_only ->
    if last_only then "STEM LAST_ONLY" else "STEM"
  | Cpf_relative_part -> "RELATIVE_PART"
  | Cpf_parent_path -> "PARENT_PATH"

let of_cmake_path_has_field : Lang_cmake.cmake_path_has_field -> string =
  function
  | Cph_root_name -> "HAS_ROOT_NAME"
  | Cph_root_directory -> "HAS_ROOT_DIRECTORY"
  | Cph_root_path -> "HAS_ROOT_PATH"
  | Cph_filename -> "HAS_FILENAME"
  | Cph_extension -> "HAS_EXTENSION"
  | Cph_stem -> "HAS_STEM"
  | Cph_relative_part -> "HAS_RELATIVE_PART"
  | Cph_parent_path -> "HAS_PARENT_PATH"

let of_cmake_path_compare_op : Lang_cmake.cmake_path_compare_op -> string =
  function
  | Cpco_equal -> "EQUAL"
  | Cpco_not_equal -> "NOT_EQUAL"

let of_version (v : Lang_cmake.version) =
  let patch = if String.length v.patch = 0 then "" else "." ^ v.patch in
  Fmt.str "%d.%d%s" v.major v.minor patch

let of_supported_lang : Lang_cmake.supported_lang -> string = function
  | Lang_none -> "NONE"
  | Lang_c -> "C"
  | Lang_cxx -> "CXX"
  | Lang_csharp -> "CSharp"
  | Lang_cuda -> "CUDA"
  | Lang_objc -> "OBJC"
  | Lang_objcxx -> "OBJCXX"
  | Lang_fortran -> "Fortran"
  | Lang_hipy -> "HIP"
  | Lang_ispc -> "ISPC"
  | Lang_swift -> "Swift"
  | Lang_asm -> "ASM"
  | Lang_asm_nasm -> "ASM_NASM"
  | Lang_asm_marmasm -> "ASM_MARMASM"
  | Lang_asm_masm -> "ASM_MASM"
  | Lang_asm_att -> "ASM-ATT"

let of_message_mode : Lang_cmake.message_mode -> string = function
  | Mm_none -> ""
  | Mm_status -> "STATUS"
  | Mm_notice -> "NOTICE"
  | Mm_verbose -> "VERBOSE"
  | Mm_debug -> "DEBUG"
  | Mm_trace -> "TRACE"
  | Mm_warning -> "WARNING"
  | Mm_author_warning -> "AUTHOR_WARNING"
  | Mm_check_start -> "CHECK_START"
  | Mm_check_pass -> "CHECK_PASS"
  | Mm_check_fail -> "CHECK_FAIL"
  | Mm_send_error -> "SEND_ERROR"
  | Mm_fatal_error -> "FATAL_ERROR"
  | Mm_deprecation -> "DEPRECATION"

let of_compatibility : Lang_cmake.compatibility -> string = function
  | Any_newer_version -> "AnyNewerVersion"
  | Same_major_version -> "SameMajorVersion"
  | Same_minor_version -> "SameMinorVersion"
  | Exact_version -> "ExactVersion"
