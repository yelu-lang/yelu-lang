# Syntax Surface Audit Report — June 2026

> **CLOSED (2026-07-16).** Every finding below is resolved — see the
> 2026-06-25 and 2026-07-16 entries in
> [`worklog_2026_06.md`](worklog_2026_06.md) for the fix-by-fix record:
> honest emit (`a57bcf4` + `88320dd`), Unknown_kwarg (`a5d33ae`),
> find/add_test/property-stub labeled-only (`3618e9e`), world-aware
> Function_def_typo + reserved-decl coverage (`c28860e`), and the file-api
> matrix supplement (`6aae29a`) that plugged the CMakeCache blind spot this
> report kept running into (its first run also exposed a contaminated
> `vendor/fmt/CMakeLists.txt` and a never-ported posix-mock/os-test block,
> `c49e626`).

Request: [`syntax_audit_request_2026-06.md`](syntax_audit_request_2026-06.md)

Scope: current `.yc` syntax surface, parser/wellform pipeline, formatter, LSP-facing diagnostics, and corpus gate behavior. This was a read-only audit; no project files were modified.

## Verification

Commands run:

```sh
eval $(opam env) && dune build
eval $(opam env) && dune test
eval $(opam env) && dune exec src/bin/yelu/yelu.exe -- compile-corpus probes/fmt
```

All passed. Targeted `/tmp/*.yc` probes were also run for the prior audit findings. Formatter idempotence and fail-safe behavior were checked on `probes/fmt/main.yc` plus a failing positional-keyword probe.

## Summary

The shared `.yc` pipeline is substantially improved: CLI compile, formatter, LSP diagnostics, and corpus gate all route through `Yc_driver.parse_and_check`, so the broad B1 claim is mostly true for `.yc` inputs. The formatter is idempotent on `probes/fmt/main.yc`, and `fmt -w` did not overwrite a file when wellform failed.

The main remaining problem is not broad pipeline drift; it is uneven enforcement of the labeled-only contract. Several known command families still accept positional CMake keyword forms by falling through to raw/misclassified output instead of producing `Positional_form`. Some of these cases silently drop arguments.

## Findings

### High

**H1 confirmed: `link_lib ~public=[...]` silently drops libraries.**

Probe:

```yc
link_lib foo ~public=['bar','baz'];
```

Output:

```cmake
target_link_libraries(foo PRIVATE )
```

The CST lowerer flattens `Kw_list` into repeated kwargs, but the target parser branch for `link_lib` only groups positional visibility keywords and ignores `public`/`private`/`interface` kwargs. Relevant code: `src/langs/yelu/yelu_parse.ml`, target-family branch around `p_target_command_y1_inner`; `src/langs/yelu/yc_cst_lower.ml`, `convert_args`.

**Labeled-only contract is not uniform across known command families.**

These positional CMake keyword forms compiled instead of rejecting:

```yc
find_library mylib NAMES foo;
find_path mypath NAMES foo;
find_program myprog NAMES foo;
find_file myfile NAMES foo;
set_directory_property PROPERTY FOO bar;
set_global_property PROPERTY FOO bar;
set_test_properties mytest PROPERTIES FOO bar;
```

The emitted CMake often treats uppercase CMake keywords as variable references, e.g. `${NAMES}`, `${PROPERTY}`, `${PROPERTIES}`. The find parser handles labeled `~names`/`~paths`, but unrecognized positional keyword forms fall through.

**`find_package COMPONENTS` silently drops data.**

Probe:

```yc
find_package ZLIB COMPONENTS zlib;
```

Output:

```cmake
find_package(ZLIB)
```

The current parser preserves positional `REQUIRED` but does not preserve `COMPONENTS` in this path.

### Medium

**Quoted literal equal to a CMake keyword is over-rejected in `install_files`.**

Probe:

```yc
install_files 'lib' 'DESTINATION';
```

Result: fatal `Positional_form`. This is too coarse if quoted literals should remain valid file operands; the branch treats both bare names and strings as positional keywords.

**Function-def typo check remains fatal in open-world files.**

Probe:

```yc
include 'Foo';
my_macro arg;
(message 'x');
```

Result: fatal `Function_def_typo`. The implementation intentionally treats adjacent unknown command plus standalone block as invalid regardless of open-world state. This is coherent if that CST shape is never valid; it is too strict if open-world macros may intentionally be followed by standalone blocks.

**Reserved command names are still valid variable declarations.**

Probe:

```yc
add_custom_target := 'x';
```

Output:

```cmake
set(add_custom_target x )
```

`check_reserved_names` flags variable references and function/macro names, while declaration checks only guard enum constructors. Command-name declarations are still allowed.

**Single-file compile still exposes emit exceptions as backtraces.**

Probe:

```yc
string_json BAD ~out:OUT;
```

Single-file compile raised an uncaught `Eval_error` and exited 2. `compile-corpus` caught the same failure and reported a clean `emit: ...` error. The corpus gate wraps emit exceptions; the single-file compile path does not.

**Bare target names still dereference in property/install target slots.**

Probes:

```yc
set_target_properties fmt ~properties={VERSION='1'};
install_targets fmt ~destination='lib';
```

Outputs:

```cmake
set_target_properties(${fmt} PROPERTIES VERSION 1)
install(TARGETS ${fmt} DESTINATION lib)
```

Target-family first arguments are coerced to `ETarget`, but property/install target slots still reach the emitter as unresolved `EVar`, which renders as `${name}`.

### Low / Documentation

**`Yc_primitives.command_names` still omits `add_custom_command`.**

`add_custom_target` is present; `add_custom_command` is absent. This weakens reserved-name and apply-shadow checks for a command with a typed surface branch.

**Docs still disagree on unit-test counts.**

Observed drift:

- `CLAUDE.md`: `~975` and `~994`
- `doc/project_overview.md`: `~991`
- `doc/yelu_cmake/status.md`: `1010`

**Some doc references are stale.**

`doc/yelu_cmake/driver.md` still names `Yelu_parse.parse_program_y1`; current code uses `parse_program_legacy`. `probes/fmt/README.md` says `main.yc` is about 450 lines; actual count was 297.

**Migration-status `.ml` links are now historical, not live.**

`probes/fmt/migration_status.md` now includes a historical note, so the prior finding is softened. It still contains retired `.ml` links by design.

## Clean Claims Checked

- **Formatter idempotence / fail-safe:** verified on `probes/fmt/main.yc`; a failing `fmt -w` probe left the input unchanged.
- **B1 one-path sharing:** mostly true for `.yc`; compile, fmt, LSP, and corpus gate use `Yc_driver.parse_and_check`. `.ml` compile remains a legacy subprocess path, outside this surface claim.
- **Corpus gate:** true for all files discovered under `probes/fmt`; it catches parse, fatal wellform, and emit failures. It does not cover unprobed syntax shapes such as `link_lib ~public=[...]`.
- **Labeled-only parser claim:** too strong today. Some command families reject correctly, but find/property/target examples above still accept or misemit positional CMake keyword forms.

## Suggested Priorities

1. Fix `link_lib`/target visibility kwargs first; it is silent semantic loss on a natural labeled form.
2. Add positional-keyword reject branches for find/property families, especially `NAMES`, `PATHS`, `PROPERTY`, and `PROPERTIES`.
3. Preserve or reject `find_package COMPONENTS`; silent dropping is worse than a hard error.
4. Wrap single-file emit in the same clean error handling used by `compile-corpus`.
5. Decide whether quoted keyword literals should be valid operands; then adjust positional-keyword detection to distinguish bare keyword tokens from quoted strings where needed.
6. Extend reserved declaration checks to command names, not only enum constructors.
7. Update count/path docs after the behavior fixes.
