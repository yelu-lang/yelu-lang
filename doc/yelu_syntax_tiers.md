# Yelu-Cmake Concrete Syntax — Complete Design & Tiers

Concrete syntax names are derived 1:1 from the OCaml DSL in
`lang_yelu_utils.ml`. Drop the `yc_`/`ys_`/`yl_`/`yf_`/`yp_`/`yd_`/`yr_`
prefix; use space-separated args and `:keyword` for labeled args.

## Tier 0 — Core (done, 35 tests)

### control side

| OCaml DSL                             | Concrete syntax                     | Status |
| ------------------------------------- | ----------------------------------- | ------ |
| `ylet x (target "T")`                 | `let x = Target T in body`          | ✅      |
| `ylet x : target = ...`               | `let x : target = Target T in body` | ✅      |
| `yif cond then_ else_`                | `if cond then { } else { }`         | ✅      |
| `ycmd_of_list [...]`                  | `{ stmt; stmt }`                    | ✅      |
| `yc_foreach lv items cmds`            | `foreach x in [a, b] { }`           | ✅      |
| `yc_foreach_range lv start stop cmds` | `foreach i in RANGE 1..10 { }`      | ✅      |
| `yc_function name args body`          | `fun name(args) { }`                | ✅      |

### cond

| OCaml name             | Concrete syntax   | Status |
| ---------------------- | ----------------- | ------ |
| `ytruthy e`            | `e`               | ✅      |
| `yis_target e`         | `target e`        | ✅      |
| `yis_defined e`        | `defined e`       | ✅      |
| `ynot c`               | `not c`           | ✅      |
| `yand a b`             | `a and b`         | ✅      |
| `yor a b`              | `a or b`          | ✅      |
| `ystrequal a b`        | `str_eq a b`      | ✅      |
| `ystrless a b`         | `str_lt a b`      | ✅      |
| `ystrgreater a b`      | `str_gt a b`      | ✅      |
| `yequal a b`           | `eq a b`          | ✅      |
| `yless a b`            | `lt a b`          | ✅      |
| `ygreater a b`         | `gt a b`          | ✅      |
| `ymatches e regex`     | `match e "regex"` | ✅      |
| `yversion_less a b`    | `ver_lt a b`      | ✅      |
| `yversion_greater a b` | `ver_gt a b`      | ✅      |
| `yversion_equal a b`   | `ver_eq a b`      | ✅      |
| `yin_list e list`      | `list_in e list`  | ✅      |
| `yexists e`            | `exists e`        | ✅      |
| `yis_directory e`      | `is_dir e`        | ✅      |
| `yis_absolute e`       | `is_abs e`        | ✅      |
| `ypolicy_defined id`   | `policy CMPxxxx`  | ✅      |

### var

| OCaml DSL                    | Concrete syntax            | Status |
| ---------------------------- | -------------------------- | ------ |
| `yc_set cvar [a; b]`         | `VAR := a, b`              | ✅      |
| `yc_option ~value ~msg cvar` | `cache VAR := ON ; 'msg'`  | ✅      |
| `yc_set_cache cvar vals`     | `cache VAR := val ; 'doc'` | ✅      |
| `yc_unset_cache cvar`        | `unset cache VAR`          | —      |
| `yc_set_env var val`         | `env VAR := val`           | —      |
| `yc_unset_env var`           | `unset env VAR`            | —      |

### cmake_op (partial)

| OCaml DSL                   | Concrete syntax                 | Status |
| --------------------------- | ------------------------------- | ------ |
| `yc_minimum_required_s min` | `cmake_minimum_required "3.20"` | ✅      |
| `yc_project name`           | `project "Name" :version "1.0"` | ✅      |
| `yc_message texts`          | `message "text"`                | ✅      |
| `yc_policy_set id`          | `policy CMPxxxx :new`           | —      |
| `yc_include_guard scope`    | `include_guard :global`         | —      |
| `yc_enable_language langs`  | `enable_language CXX :optional` | —      |

### test (partial)

| OCaml DSL                   | Concrete syntax               | Status |
| --------------------------- | ----------------------------- | ------ |
| `yc_enable_testing`         | `enable_testing`              | ✅      |
| `yc_add_test name cmd args` | `add_test "Name" "Cmd" "arg"` | ✅      |

### find (partial)

| OCaml DSL              | Concrete syntax        | Status |
| ---------------------- | ---------------------- | ------ |
| `yc_find_package name` | `find_package "Boost"` | ✅      |

### target (partial)

| OCaml DSL                     | Concrete syntax              | Status |
| ----------------------------- | ---------------------------- | ------ |
| `add_exe name`                | `add_exe Target Foo`         | ✅      |
| `add_lib name`                | `add_lib Target Foo`         | ✅      |
| `link_lib targets items`      | `link_lib tgt { }`           | ✅      |
| `include_dirs tgt items`      | `include_dirs tgt { }`       | ✅      |
| `compile_defs tgt items`      | `compile_defs tgt { }`       | ✅      |
| `compile_opts tgt items`      | `compile_opts tgt { }`       | ✅      |
| `yc_target_sources tgt items` | `target_sources tgt { }`     | ✅      |

### dir (partial)

| OCaml DSL                         | Concrete syntax                   | Status |
| --------------------------------- | --------------------------------- | ------ |
| `yc_add_subdirectory dir`         | `add_subdirectory "dir"`          | ✅      |
| `yc_link_libraries items`         | `link_libraries "a" "b"`          | ✅      |
| `yc_add_compile_definitions defs` | `add_compile_definitions "-DFOO"` | ✅      |

### file (partial)

| OCaml DSL                         | Concrete syntax             | Status |
| --------------------------------- | --------------------------- | ------ |
| `yc_configure_file ~input output` | `configure_file "in" "out"` | ✅      |

---

## Tier 1 — target (complete, 12 new)

Names match the OCaml DSL. Drop `target_` prefix; first arg is always a target.

| OCaml DSL                                          | Concrete syntax                                              |
| -------------------------------------------------- | ------------------------------------------------------------ |
| `compile_feats tgt features`                       | `compile_feats tgt { :public { cxx_std_11 } }`       |
| `yc_target_link_options ~before tgt items`         | `link_opts tgt :before { :private { "-pie" } }`      |
| `yc_target_link_directories ~before tgt items`     | `link_dirs tgt :before { :private { "/opt/lib" } }`  |
| `yc_target_precompile_headers tgt items`           | `precompile_headers tgt { :private { "pch.h" } }`    |
| `yc_target_sources_fs tgt items`                   | `sources_fs tgt { :headers :public { :base_dirs ["src"] } }` |
| `add_lib_imported name`                            | `add_lib_imported name :type STATIC :global`          |
| `add_lib_alias ~alias_of name`                     | `add_lib_alias name alias_of`                         |
| `add_exe_alias ~alias_of name`                     | `add_exe_alias name alias_of`                         |
| `yc_add_custom_target ~all ~depends name`          | `add_custom_target name :all`                         |
| `yc_add_dependencies tgt dep`                      | `add_dependencies tgt dep`                            |
| `yc_add_custom_command ~outputs ~depends cmds`     | `add_custom_command :outputs ["out"] "cmd" :depends ["dep"]` |
| `yc_add_custom_command_target ~target ~when_ cmds` | `add_custom_command_target name :pre_build "cmd"`    |

## Tier 2 — string (complete, 14 new)

| OCaml DSL                                       | Concrete syntax                                     |
| ----------------------------------------------- | --------------------------------------------------- |
| `yc_string_toupper s out`                       | `string_toupper s :out out`                         |
| `yc_string_tolower s out`                       | `string_tolower s :out out`                         |
| `yc_string_length s out`                        | `string_length s :out out`                          |
| `yc_string_strip s out`                         | `string_strip s :out out`                           |
| `yc_string_concat out inputs`                   | `string_concat :out out "a" "b"`                    |
| `yc_string_replace match repl out inputs`       | `string_replace "match" "repl" input :out out`      |
| `yc_string_regex_match regex out inputs`        | `string_regex_match "pat" input :out out`           |
| `yc_string_regex_matchall regex out inputs`     | `string_regex_matchall "pat" input :out out`        |
| `yc_string_regex_replace regex repl out inputs` | `string_regex_replace "pat" "repl" input :out out`  |
| `yc_string_regex_quote out inputs`              | `string_regex_quote input :out out`                 |
| `yc_string_append cvar inputs`                  | `string_append cvar "a" "b"`                        |
| `yc_string_prepend cvar inputs`                 | `string_prepend cvar "a"`                           |
| `yc_string_join glue out inputs`                | `string_join "glue" :out out "a" "b"`               |
| `yc_string_find ~reverse s sub out`             | `string_find "sub" s :out out`                      |
| `yc_string_substring s beg ~length out`         | `string_substring s 0 5 :out out`                   |
| `yc_string_repeat s count out`                  | `string_repeat s 3 :out out`                        |
| `yc_string_genex_strip s out`                   | `string_genex_strip s :out out`                     |
| `yc_string_compare op s1 s2 out`                | `string_compare s1 :equal s2 :out out`              |
| `yc_string_make_c_identifier s out`             | `string_make_c_identifier s :out out`               |
| `yc_string_timestamp ~utc ?format out`          | `string_timestamp :out out :utc`                    |
| `yc_string_hex s out`                           | `string_hex s :out out`                             |
| `yc_string_uuid ~ns ~name ~type_ out`           | `string_uuid :out out :ns "ns" :name "n" :type "t"` |
| `yc_string_json_get ~out json`                  | `string_json_get json "path" :out out`              |
| `yc_string_json_set ~out ~value json`           | `string_json_set json "path" = "val" :out out`      |
| `yc_string_json_equal ~out j1 j2`               | `string_json_equal j1 j2 :out out`                  |

## Tier 3 — list (complete, 12 new)

| OCaml DSL                                         | Concrete syntax                              |
| ------------------------------------------------- | -------------------------------------------- |
| `yc_list_append cvar vals`                        | `list_append cvar "a" "b"`                   |
| `yc_list_length cvar out`                         | `list_length cvar :out out`                  |
| `yc_list_get cvar indices out`                    | `list_get cvar 0 :out out`                   |
| `yc_list_remove_item cvar vals`                   | `list_remove_item cvar "a"`                  |
| `yc_list_remove_duplicates cvar`                  | `list_remove_duplicates cvar`                |
| `yc_list_reverse cvar`                            | `list_reverse cvar`                          |
| `yc_list_sort ~order ~compare ~case cvar`         | `list_sort cvar :order DESC :compare STRING` |
| `yc_list_filter mode regex cvar`                  | `list_filter cvar :include "regex"`          |
| `yc_list_join cvar glue out`                      | `list_join cvar "glue" :out out`             |
| `yc_list_sublist cvar beg len out`                | `list_sublist cvar 0 5 :out out`             |
| `yc_list_find cvar val out`                       | `list_find cvar "val" :out out`              |
| `yc_list_prepend cvar vals`                       | `list_prepend cvar "a"`                      |
| `yc_list_insert cvar idx vals`                    | `list_insert cvar 0 "a"`                     |
| `yc_list_remove_at cvar indices`                  | `list_remove_at cvar 0 1`                    |
| `yc_list_pop_back ~out_vars cvar`                 | `list_pop_back cvar :out [a, b]`             |
| `yc_list_pop_front ~out_vars cvar`                | `list_pop_front cvar :out [a, b]`            |
| `yc_list_transform ~selector ~output cvar action` | `list_transform cvar :append "_sfx"`         |

## Tier 4 — file & path (complete, 25 new)

### file

| OCaml DSL                                             | Concrete syntax                          |
| ----------------------------------------------------- | ---------------------------------------- |
| `yc_file_read ~offset ~limit ~hex out file`           | `file_read "f.txt" :out out`             |
| `yc_file_write ~append file content`                  | `file_write "f.txt" "content"`           |
| `yc_file_strings ~regex out file`                     | `file_strings "f.txt" :out out`          |
| `yc_file_touch ~nocreate files`                       | `file_touch "f.txt"`                     |
| `yc_file_make_directory dirs`                         | `file_make_directory "dir"`              |
| `yc_file_rename ~result ~no_replace old_ new_`        | `file_rename "old" "new" :result out`    |
| `yc_file_remove ~recurse files`                       | `file_remove "f.txt" :recurse`           |
| `yc_file_copy_file ~result ~only_if_different in out` | `file_copy "src" "dst" :result out`      |
| `yc_file_real_path ~base_dir ~expand_tilde out path`  | `file_real_path "f.txt" :out out`        |
| `yc_file_size out file`                               | `file_size "f.txt" :out out`             |
| `yc_file_read_symlink out link`                       | `file_read_symlink "link" :out out`      |
| `yc_file_timestamp ~format ~utc out file`             | `file_timestamp "f.txt" :out out :utc`   |
| `yc_file_relative_path ~var ~base file`               | `file_relative_path "f.txt" :base "dir"` |
| `yc_file_glob ~recurse ~relative out pats`            | `file_glob :out out "*.cxx" :recurse`    |

### path

| OCaml DSL                                            | Concrete syntax                                       |
| ---------------------------------------------------- | ----------------------------------------------------- |
| `yc_path_get pv field out`                           | `path_get pv :filename :out out`                      |
| `yc_path_has pv field out`                           | `path_has pv :filename :out out`                      |
| `yc_path_is_absolute pv out`                         | `path_is_absolute pv :out out`                        |
| `yc_path_is_relative pv out`                         | `path_is_relative pv :out out`                        |
| `yc_path_is_prefix ~normalize pv in out`             | `path_is_prefix pv "input" :out out`                  |
| `yc_path_compare in1 op in2 out`                     | `path_compare p1 :equal p2 :out out`                  |
| `yc_path_set ~normalize pv in`                       | `path_set pv "val"`                                   |
| `yc_path_append ~out pv ins`                         | `path_append pv "sub" :out out`                       |
| `yc_path_append_string ~out pv ins`                  | `path_append_string pv "str" :out out`                |
| `yc_path_remove_filename ~out pv`                    | `path_remove_filename pv :out out`                    |
| `yc_path_replace_filename ~out pv in`                | `path_replace_filename pv "new" :out out`             |
| `yc_path_remove_extension ~last_only ~out pv`        | `path_remove_extension pv :out out`                   |
| `yc_path_replace_extension ~last_only ~out pv in`    | `path_replace_extension pv "ext" :out out`            |
| `yc_path_normal_path ~out pv`                        | `path_normal_path pv :out out`                        |
| `yc_path_relative_path ~base_dir ~out pv`            | `path_relative_path pv :base "dir" :out out`          |
| `yc_path_absolute_path ~base_dir ~normalize ~out pv` | `path_absolute_path pv :base "dir" :out out`          |
| `yc_path_native_path ~normalize pv out`              | `path_native_path pv :out out`                        |
| `yc_path_convert_to_cmake ~normalize in out`         | `path_convert_to_cmake "in" :out out`                 |
| `yc_path_convert_to_native ~normalize in out`        | `path_convert_to_native "in" :out out`                |
| `yc_path_hash pv out`                                | `path_hash pv :out out`                               |
| `yc_get_filename_component ~mode var file`           | `get_filename_component "file" :mode "PATH" :out var` |

## Tier 5 — find & install (complete, 10 new)

### find

| OCaml DSL                                   | Concrete syntax                                 |
| ------------------------------------------- | ----------------------------------------------- |
| `yc_find_library ~names ~paths ~hints cvar` | `find_library VAR :names "m" :paths "/usr/lib"` |
| `yc_find_path ~names ~paths ~hints cvar`    | `find_path VAR :names "foo.h"`                  |
| `yc_find_program ~names ~paths ~hints cvar` | `find_program VAR :names "git"`                 |
| `yc_find_file ~names ~paths ~hints cvar`    | `find_file VAR :names "config"`                 |

### install

| OCaml DSL                                                           | Concrete syntax                                                                   |
| ------------------------------------------------------------------- | --------------------------------------------------------------------------------- |
| `yc_install_targets ?export tgts dest`                              | `install_targets [tgt1] "lib" :export "MyTargets"`                                |
| `yc_install_files files dest`                                       | `install_files ["f.h"] "include"`                                                 |
| `yc_install_export ?file ?namespace exp dest`                       | `install_export name "lib/cmake" :file "targets.cmake"`                           |
| `yc_export_export ?file name`                                       | `export name :file "targets.cmake"`                                               |
| `yc_configure_package_config_file dest in out`                      | `configure_package_config_file "dest" "in" "out"`                                 |
| `yc_write_basic_package_version_file ~compat ~arch_indep ?ver file` | `write_basic_package_version_file "file" :version "1.0" :compat SameMajorVersion` |

## Tier 6 — scripting (complete, 11 new)

| OCaml DSL                                 | Concrete syntax                                |
| ----------------------------------------- | ---------------------------------------------- |
| `yc_include ~optional file`               | `include "file" :optional`                     |
| `yc_macro name ~args body`                | `macro name(arg1, arg2) { }`                   |
| `yc_apply name args`                      | (implicit by function-call syntax)             |
| `yc_separate_arguments ~input ~mode cvar` | `separate_arguments VAR :unix ${args}`         |
| `yc_foreach_in ~lists ~items lv cmds`     | `foreach x in :lists [a, b] :items [x, y] { }` |
| `yc_foreach_zip lvs lists cmds`           | `foreach [x, y] in :zip [a, b] { }`            |
| `yc_while cond cmds`                      | `while cond { }`                               |
| `yc_break` / `yc_continue` / `yc_return`  | `break` / `continue` / `return`                |
| `yc_block ~scope_vars ~propagate body`    | `block :scope [a, b] { }`                      |
| `yc_extern_cvar s`                        | `extern 'VAR'`                                 |
| `yc_extern_target s`                      | `extern Target Foo`                            |

## Tier 7 — dir, property, cmake_op, try (complete, 23 new)

### dir

| OCaml DSL                                     | Concrete syntax                       |
| --------------------------------------------- | ------------------------------------- |
| `yc_include_directories ~before ~system dirs` | `include_directories :before "dir1"`  |
| `yc_add_compile_options opts`                 | `add_compile_options "-Wall"`         |
| `yc_add_link_options opts`                    | `add_link_options "-pie"`             |
| `yc_add_definitions defs`                     | `add_definitions "-DFOO"`             |
| `yc_link_directories ~before dirs`            | `link_directories :before "/opt/lib"` |

### property

| OCaml DSL                                                        | Concrete syntax                                 |
| ---------------------------------------------------------------- | ----------------------------------------------- |
| `yc_get_property ~set ~target prop var`                          | `get_target_property tgt PROP :out var`         |
| `yc_get_directory_property prop var`                             | `get_directory_property PROP :out var`          |
| `yc_set_directory_property ~append prop vals`                    | `set_directory_property PROP = "val"`           |
| `yc_set_tests_properties tests props`                            | `set_test_properties "test" { PROP = "val" }`   |
| `yc_set_target_properties tgt props`                             | `set_target_properties tgt { PROP = "val" }`    |
| `yc_set_property ~append ~targets props`                         | `set_property :targets [a, b] { PROP = "val" }` |
| `yc_set_source_property ~prop file vals`                         | `set_source_property "file.c" { PROP = "val" }` |
| `yc_set_global_property props`                                   | `set_global_property { PROP = "val" }`          |
| `yc_get_global_property ~property var`                           | `get_global_property PROP :out var`             |
| `yc_get_target_property var tgt prop`                            | `get_target_property tgt PROP :out var`         |
| `yc_define_property ~inherited ~brief_docs ~full_docs mode name` | `define_property :target PROP :inherited`       |

### cmake_op

| OCaml DSL                        | Concrete syntax                             |
| -------------------------------- | ------------------------------------------- |
| `yc_math ~output_format exp out` | `math out "1+2"`                            |
| `yc_language_call cmd args`      | `cmake_call fn "arg1"`                      |
| `yc_language_eval code`          | `cmake_eval "code"`                         |
| `yc_language_get_log_level out`  | `cmake_get_log_level :out var`              |
| `yc_execute_process ...`         | `execute_process ["cmd"] :out out :err err` |

### try

| OCaml DSL                                                 | Concrete syntax                                 |
| --------------------------------------------------------- | ----------------------------------------------- |
| `yc_try_compile ~compile_definitions ~link_libraries ...` | `try_compile :result r "src.c" :defs ["-DFOO"]` |
| `yc_try_run ~compile_definitions ~link_libraries ...`     | `try_run :run r :compile c "src.c"`             |

## Tier 8 — genex (5 new)

Already lex as `EVAL` tokens. Tests verify they appear in expression positions.

```
compile_options tgt { :private { $<${gcc_like}:-Wall> } }
install :files [$<TARGET_FILE:tgt>] "bin"
```

## Summary

| Tier                              | Done     | Total   |
| --------------------------------- | -------- | ------- |
| 0                                 | 35 tests | 35      |
| 1 target                          | 0        | 12      |
| 2 string                          | 0        | 25      |
| 3 list                            | 0        | 17      |
| 4 file + path                     | 0        | 35      |
| 5 find + install                  | 0        | 10      |
| 6 scripting                       | 0        | 11      |
| 7 dir + property + cmake_op + try | 0        | 23      |
| 8 genex                           | 0        | 5       |
| **Total**                         | **35**   | **173** |
