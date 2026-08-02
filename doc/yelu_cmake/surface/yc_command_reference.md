# yc command reference (generated — do not edit)

> Regenerate with `dune exec src/bin/yelu/yelu.exe -- command-reference`.
> A dune `(diff)` rule fails `dune test` if this file drifts from the
> code; fix with `dune promote`. Derived from `Yc_primitives.command_names`,
> `Yc_cst_lower.family_of`, `Yc_primitives.command_kwargs` and
> `takes_out_var` — so every row is true by construction.
>
> **Coverage is 100% by construction too**: the command-coverage lock in
> `test/test-yelu/test_yelu_cmake_parse.ml` requires a parse+emit case for
> every command below, and the dispatch lock in `test_yc_manifest.ml`
> requires each to be owned by a family `_inner` (never the raw fallback).

**142 commands.**

## target (21)

| command | `~out` | accepted `~labels` |
| --- | --- | --- |
| `add_custom_command` |  | `~command=` `~command_expand_lists=` `~commands=` `~comment=` `~depends=` `~output=` `~verbatim=` |
| `add_custom_target` |  | `~all=` `~command=` `~commands=` `~comment=` `~depends=` `~sources=` |
| `add_dependencies` |  | — |
| `add_exe` |  | — |
| `add_exe_alias` |  | `~alias_of=` |
| `add_lib` |  | `~type=` |
| `add_lib_alias` |  | `~alias_of=` |
| `add_lib_imported` |  | `~global=` `~type=` |
| `compile_defs` |  | — |
| `compile_feats` |  | — |
| `compile_opts` |  | `~before=` |
| `include_dirs` |  | `~before=` `~system=` |
| `link_dirs` |  | `~before=` |
| `link_lib` |  | — |
| `link_opts` |  | `~before=` |
| `precompile_headers` |  | — |
| `target_compile_definitions` |  | — |
| `target_compile_options` |  | `~before=` |
| `target_include_directories` |  | `~before=` `~system=` |
| `target_link_libraries` |  | — |
| `target_sources` |  | — |

## string (23)

| command | `~out` | accepted `~labels` |
| --- | --- | --- |
| `string_append` | ✓ | — |
| `string_compare` | ✓ | — |
| `string_concat` | ✓ | — |
| `string_find` | ✓ | — |
| `string_genex_strip` | ✓ | — |
| `string_hex` | ✓ | — |
| `string_join` | ✓ | — |
| `string_json` | ✓ | — |
| `string_length` | ✓ | — |
| `string_make_c_identifier` | ✓ | — |
| `string_prepend` | ✓ | — |
| `string_regex_match` | ✓ | — |
| `string_regex_matchall` | ✓ | — |
| `string_regex_quote` | ✓ | — |
| `string_regex_replace` | ✓ | — |
| `string_repeat` | ✓ | — |
| `string_replace` | ✓ | — |
| `string_strip` | ✓ | — |
| `string_substring` | ✓ | — |
| `string_timestamp` | ✓ | — |
| `string_tolower` | ✓ | — |
| `string_toupper` | ✓ | — |
| `string_uuid` | ✓ | — |

## list (17)

| command | `~out` | accepted `~labels` |
| --- | --- | --- |
| `list_append` | ✓ | — |
| `list_filter` | ✓ | — |
| `list_find` | ✓ | — |
| `list_get` | ✓ | — |
| `list_insert` | ✓ | — |
| `list_join` | ✓ | — |
| `list_length` | ✓ | — |
| `list_pop_back` | ✓ | — |
| `list_pop_front` | ✓ | — |
| `list_prepend` | ✓ | — |
| `list_remove_at` | ✓ | — |
| `list_remove_duplicates` | ✓ | — |
| `list_remove_item` | ✓ | — |
| `list_reverse` | ✓ | — |
| `list_sort` | ✓ | — |
| `list_sublist` | ✓ | — |
| `list_transform` | ✓ | `~prepend=` |

## path (21)

| command | `~out` | accepted `~labels` |
| --- | --- | --- |
| `get_filename_component` | ✓ | `~mode=` |
| `path_absolute_path` | ✓ | — |
| `path_append` | ✓ | — |
| `path_append_string` | ✓ | — |
| `path_compare` | ✓ | — |
| `path_convert_to_cmake` | ✓ | — |
| `path_convert_to_native` | ✓ | — |
| `path_get` | ✓ | — |
| `path_has` | ✓ | — |
| `path_hash` | ✓ | — |
| `path_is_absolute` | ✓ | — |
| `path_is_prefix` | ✓ | — |
| `path_is_relative` | ✓ | — |
| `path_native_path` | ✓ | — |
| `path_normal_path` | ✓ | — |
| `path_relative_path` | ✓ | — |
| `path_remove_extension` | ✓ | — |
| `path_remove_filename` | ✓ | — |
| `path_replace_extension` | ✓ | — |
| `path_replace_filename` | ✓ | — |
| `path_set` | ✓ | — |

## file (14)

| command | `~out` | accepted `~labels` |
| --- | --- | --- |
| `configure_file` |  | — |
| `file_copy` | ✓ | — |
| `file_glob` | ✓ | — |
| `file_make_directory` | ✓ | — |
| `file_read` | ✓ | — |
| `file_read_symlink` | ✓ | — |
| `file_real_path` | ✓ | — |
| `file_remove` | ✓ | — |
| `file_rename` | ✓ | — |
| `file_size` | ✓ | — |
| `file_strings` | ✓ | — |
| `file_timestamp` | ✓ | — |
| `file_touch` | ✓ | — |
| `file_write` | ✓ | — |

## property (5)

| command | `~out` | accepted `~labels` |
| --- | --- | --- |
| `get_property` | ✓ | `~mode=` `~property=` |
| `get_target_property` | ✓ | — |
| `set_property` |  | `~append=` `~append_string=` `~property=` |
| `set_source_files_properties` |  | `~properties=` |
| `set_target_properties` |  | `~properties=` |

## install (7)

| command | `~out` | accepted `~labels` |
| --- | --- | --- |
| `configure_package_config_file` |  | `~install_destination=` `~no_check_required_components_macro=` `~no_set_and_check_macro=` |
| `export` |  | `~file=` `~namespace=` `~targets=` |
| `install_directory` |  | `~component=` `~destination=` `~optional=` |
| `install_export` |  | `~component=` `~destination=` `~file=` `~namespace=` |
| `install_files` |  | `~component=` `~destination=` |
| `install_targets` |  | `~component=` `~destination=` `~export=` · dotted `~<kind>.destination=` for library/archive/runtime/objects/framework/bundle/public_header/private_header/resource/file_set/cxx_modules_bmi |
| `write_basic_package_version_file` |  | `~compatibility=` `~version=` |

## find (5)

| command | `~out` | accepted `~labels` |
| --- | --- | --- |
| `find_file` |  | `~name=` `~names=` `~path=` `~paths=` |
| `find_library` |  | `~name=` `~names=` `~path=` `~paths=` |
| `find_package` |  | `~required=` |
| `find_path` |  | `~name=` `~names=` `~path=` `~paths=` |
| `find_program` |  | `~name=` `~names=` `~path=` `~paths=` |

## dir (7)

| command | `~out` | accepted `~labels` |
| --- | --- | --- |
| `add_compile_definitions` |  | — |
| `add_compile_options` |  | — |
| `add_definitions` |  | — |
| `add_link_options` |  | — |
| `add_subdirectory` |  | — |
| `include_directories` |  | — |
| `link_directories` |  | — |

## cmake_op (18)

| command | `~out` | accepted `~labels` |
| --- | --- | --- |
| `cmake_call` |  | — |
| `cmake_eval` |  | — |
| `cmake_get_log_level` | ✓ | — |
| `cmake_minimum_required` |  | — |
| `enable_language` |  | `~optional=` |
| `execute_process` |  | `~command=` `~command_error_is_fatal=` `~commands=` `~error_file=` `~error_quiet=` `~error_strip_trailing_whitespace=` `~error_variable=` `~input_file=` `~output_file=` `~output_quiet=` `~output_strip_trailing_whitespace=` `~output_variable=` `~result_variable=` `~timeout=` `~working_directory=` |
| `include` |  | `~optional=` |
| `include_guard` |  | `~global=` |
| `math` | ✓ | — |
| `message` |  | `~mode=` |
| `policy_get` |  | — |
| `policy_pop` |  | — |
| `policy_push` |  | — |
| `policy_set` |  | — |
| `policy_version` |  | — |
| `project` |  | `~version=` |
| `separate_arguments` |  | — |
| `yc_raw` |  | — |

## test (2)

| command | `~out` | accepted `~labels` |
| --- | --- | --- |
| `add_test` |  | `~command=` `~name=` |
| `enable_testing` |  | — |

## try (2)

| command | `~out` | accepted `~labels` |
| --- | --- | --- |
| `try_compile` |  | — |
| `try_run` |  | — |

