# Installed packages / software

Things added for this project that you may want to remove later.

## System packages (apt / pip / etc.)
None. Everything below lives inside the project folder.

## Downloaded / vendored into the project

| What | Where | Why | Remove with |
|---|---|---|---|
| Godot 4.7.2-stable (Linux x86_64, ~140 MB) | `.tools/godot/` (gitignored) | Engine and editor. Self-contained mode (`._sc_`), so editor settings and cache stay in `.tools/godot/editor_data/`. | `rm -rf .tools/` |
| Python venv: SCons 4.11.1, jsonschema 4.26.0 (+ deps) | `.venv/` (gitignored) | Build `noss_core`; check JSON schemas | `rm -rf .venv/` |
| godot-cpp 10.0.0-stable | `native/thirdparty/godot-cpp` (submodule) | C++ bindings for `noss_core` | `git submodule deinit -f native/thirdparty/godot-cpp` |
| SDL 3.4.18 | `native/thirdparty/SDL` (submodule) | Wheels and FFB (built from M1) | `git submodule deinit -f native/thirdparty/SDL` |
| doctest 2.5.3 | `native/thirdparty/doctest` (submodule) | Native unit tests | `git submodule deinit -f native/thirdparty/doctest` |
| gdUnit4 6.2.2 | `addons/gdUnit4/` (committed) | GDScript unit tests | `rm -rf addons/gdUnit4` and remove it from `project.godot` `[editor_plugins]` |

Build output (safe to delete any time): `native/bin/`, `native/build/`, `.godot/`, `reports/`.
