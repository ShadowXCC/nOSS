# Installed packages / software

Things added for this project that you may want to remove later.

## System packages (apt / pip / etc.)
None. Everything below lives inside the project folder.

Already on the system and used, but not installed by this project: `libsdl3-0` (system SDL3, used for wheels on Linux) and `wine` (used to test the Windows build).

## Downloaded / vendored into the project

| What | Where | Why | Remove with |
|---|---|---|---|
| Godot 4.7.2-stable (Linux x86_64, ~140 MB) | `.tools/godot/` (gitignored) | Engine and editor. Self-contained mode (`._sc_`), so editor settings and cache stay in `.tools/godot/editor_data/`. | `rm -rf .tools/` |
| Godot 4.7.2 export templates, Linux and Windows only (~344 MB) | `.tools/godot/editor_data/export_templates/4.7.2.stable/` (gitignored) | Exporting builds (`tools/setup_export.sh`) | `rm -rf .tools/godot/editor_data/export_templates` |
| LLVM MinGW 20261006, UCRT (~618 MB) | `.tools/llvm-mingw/` (gitignored) | Cross-compiling `noss_core` for Windows (`tools/setup_export.sh`) | `rm -rf .tools/llvm-mingw` |
| SDL 3.4.18 for Windows (`SDL3.dll`, 2.8 MB) | `native/bin/SDL3.dll` (gitignored) | Shipped with Windows builds for wheels and FFB | `rm native/bin/SDL3.dll` |
| Test car models: Kenney Car Kit 3.1 (CC0, 4.8 MB zip, extracted) and Khronos ToyCar (CC0, 5.4 MB GLB) | `.tools/test_models/` (gitignored) | Fitting Bay import tests and the M2 acceptance run. A few Kenney files are also committed as test fixtures. | `rm -rf .tools/test_models` |
| Python venv: SCons 4.11.1, jsonschema 4.26.0 (+ deps) | `.venv/` (gitignored) | Build `noss_core`; check JSON schemas | `rm -rf .venv/` |
| godot-cpp 10.0.0-stable | `native/thirdparty/godot-cpp` (submodule) | C++ bindings for `noss_core` | `git submodule deinit -f native/thirdparty/godot-cpp` |
| SDL 3.4.18 (source) | `native/thirdparty/SDL` (submodule) | Headers for the runtime-loaded SDL3 | `git submodule deinit -f native/thirdparty/SDL` |
| meshoptimizer 1.3 | `native/thirdparty/meshoptimizer` (submodule) | LOD generation and mesh analysis (M2) | `git submodule deinit -f native/thirdparty/meshoptimizer` |
| doctest 2.5.3 | `native/thirdparty/doctest` (submodule) | Native unit tests | `git submodule deinit -f native/thirdparty/doctest` |
| gdUnit4 6.2.2 | `addons/gdUnit4/` (committed) | GDScript unit tests | `rm -rf addons/gdUnit4` and remove it from `project.godot` `[editor_plugins]` |

Build output (safe to delete any time): `native/bin/` (except you'd re-run `tools/setup_export.sh` for `SDL3.dll`), `native/build/`, `.godot/`, `reports/`, `export/`.
