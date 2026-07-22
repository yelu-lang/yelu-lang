# yelu-lang

One bird, every shape.

<img width="658" height="658" alt="image" src="https://github.com/user-attachments/assets/e3b34c1e-42f8-43c9-9ce6-f95fbda2beb9" />

Yelu is a programmable configuration shell language for studying whether a
regular surface, explicit namespaces, canonical forms, and local verification
improve model-driven generation and repair. CMake is the first target.

The current milestone is a complete yelu-cmake version of the real-world
[{fmt}](probes/fmt/README.md) project: 11/11 `.yc` files compile and all 24
option cells match upstream across cache, File API codemodel, and CTest
definitions.

- [Documentation map](doc/README.md)
- [Architecture and shipped milestones](doc/project_overview.md)
- [Current work](doc/status.md)
- [`.yc` syntax](doc/yelu_cmake/surface/yc_syntax.md)
- [Generated command reference](doc/yelu_cmake/surface/yc_command_reference.md)

```sh
eval $(opam env) && dune test
dune exec src/bin/yelu/yelu.exe -- compile probes/fmt/main.yc
dune exec src/bin/yelu/yelu.exe -- hybrid probes/fmt
```
