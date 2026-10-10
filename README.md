# nOSS

**Bring your own car. The platform decides how it drives.**

nOSS (NOS + Open Source Software) is a free, open-source racing game. You can import almost any 3D vehicle model and mount it on a standardized **platform**. The platform, chosen by gamemode and class, controls all performance and handling, so races stay fair no matter what you bring.

- **Modes:** track racing, kart (with items), highway traffic runs (score attack, two-way loop, police), endless scenic drive
- **Local play:** up to 4 players in splitscreen or one monitor each
- **Online:** up to 16 players on self-hosted servers. Cars and tracks auto-transfer.
- **Input:** keyboard, controller, wheel/pedals/shifter with force feedback
- **Tools:** in-game track editor, plus 3D scene and real-world map import
- **Accessibility:** per-player vision, hearing, motion and input options, plus screen-reader menus
- **Platforms:** Linux, Windows, macOS. Built with Godot 4 + C++.

## Status

**M2 (`v0.2.0`) is done:** bring your own car. The **Fitting Bay** turns a GLB, glTF or FBX into a car with no preparation: it finds the wheels (even when they're part of the body), works out which way is up and forward, scales it, and picks up paint slots, lights and the cockpit. Save and drive, or adjust each step. The **Garage** lists your cars with thumbnails: drive, edit, paint, tune the engine sound, copy, delete. Six classes now: Track Touring, GT, Prototype and Formula, Kart Medium, and Highway Street, each checked by the conformance runner so every model drives exactly the same. Also new: hood and bumper cameras, four synthesized engine sounds you can tune per car, generated LODs. Next up is **M3**, local multiplayer ([roadmap](docs/ROADMAP.md)).

## Playing

- **Free Drive** on the title screen: pick a class (how the car drives), then a car (how it looks). The original **nOSS Box** and **nOSS Open** always work; your own cars come from the garage (`~/.local/share/nOSS/garage/` on Linux, `%APPDATA%\nOSS\garage` on Windows).
- **Fitting Bay** on the title screen: Browse to a `.glb`, `.gltf` or `.fbx` (or drop files in the `import` folder next to the garage) and press **Save and drive**. The steps (Orient, Wheels, Scale, Paint, Cockpit, Sound, Save) adjust what it found; Save also offers a test drive that comes back to the bay.
- **Garage** on the title screen: your cars and the built-in ones.
- **Keys:** arrows or WASD to drive, Space handbrake, E/Q shift, C camera (chase near and far, hood, bumper, cockpit), B look back, R reset car, Tab change car while driving, Esc pause, F3 frame rate. Keys can be rebound in Settings. Controllers work out of the box.
- **Wheel:** Settings → Wheel setup. Pick the device, set its rotation, detect steering and pedals by moving them, tune and test force feedback. Linux needs the system SDL3 (`libsdl3-0` on Ubuntu); Windows builds ship it.
- **Assists** (ABS, traction control, auto gearbox, steer aid) and comfort options (camera shake, head movement, speed FOV, horizon lock) are in Settings. With the auto gearbox, holding the brake at a standstill selects reverse.

### Converting FM4 rips (local use only)

```sh
python3 tools/fm4_to_noss.py "<...>/Forza Motorsport 4/models"   # every car folder inside, into the garage
```

Converted packages are marked `personal-use-only` and must never be shared or committed ([Requirements §6](Requirements.md#6-content-and-legal-policy)).

## Development (Linux)

Needs `git`, `curl`, `unzip`, `python3` (with `venv`) and a C++20 compiler (GCC or Clang).

```sh
git clone --recursive https://github.com/ShadowXCC/nOSS.git   # or: git submodule update --init --recursive
tools/setup_dev.sh                 # pinned Godot in .tools/, SCons in .venv/ (nothing system-wide)
tools/build_native.sh              # builds noss_core into native/bin/
tools/run_tests.sh                 # native, schema, tools, GDScript and conformance tests, boot check
tools/run_conformance.sh           # platform conformance only; report in tests/conformance/out/
tools/godot.sh                     # runs the game; add -e for the editor
```

**Exports** (Linux and Windows, cross-compiled with LLVM MinGW):

```sh
tools/setup_export.sh              # pinned export templates, LLVM MinGW, SDL3.dll (all project-local)
tools/export.sh                    # builds release noss_core and exports to export/linux, export/windows
```

**Dev options** go after `--`, e.g. `tools/godot.sh -- --drive --autodrive --camera=cockpit`: `--drive`, `--car=<path>`, `--platform=<id>`, `--autodrive` (the line follower drives), `--camera=<chase_near|chase_far|hood|bumper|cockpit>`, `--shot=<file.png> --shot-at=<s>`, `--quit-at=<s>`, `--fps`, `--log-drive`, `--swap-car=<path> --swap-at=<s>`, `--menu=<classes|cars|settings>`, `--garage`, `--bay`, `--import=<model>`, `--bay-auto` (save and drive as soon as the import is in), `--bay-step=<step>`.

## Docs

| Doc | Contents |
|---|---|
| [Requirements](Requirements.md) | Vision, requirement IDs, non-functional targets, content policy |
| [Architecture](docs/ARCHITECTURE.md) | Engine, languages, layout, runtime systems |
| [Platforms](docs/PLATFORMS.md) | Platform format, classes, fitting and handling normalization |
| [Vehicle packages](docs/VEHICLE_PACKAGE.md) | `.noss` format, model conventions, Fitting Bay, FM4 converter |
| [Physics](docs/PHYSICS.md) | Suspension, tires, drivetrain, assists, FFB |
| [Gamemodes](docs/GAMEMODES.md) | Track, kart, highway, endless, career |
| [Track editor](docs/TRACK_EDITOR.md) | Editor tools, `.nosstrack`, map import |
| [Networking](docs/NETWORKING.md) | Hosting, replication, content transfer |
| [Input](docs/INPUT.md) | Devices, joining, wheels, FFB |
| [Art & audio](docs/ART_AUDIO.md) | Style profiles, cameras, UI, engine sound |
| [Accessibility](docs/ACCESSIBILITY.md) | Vision, hearing, motion, motor and input, pacing |
| [Roadmap](docs/ROADMAP.md) | Milestones and acceptance criteria |
| [Decisions](docs/DECISIONS.md) | Decision log, risks, open questions |

## License

Code is [GPL-3.0-or-later](LICENSE). Original assets are [CC-BY-SA 4.0](LICENSE-ASSETS.md). Third-party credits are in [CREDITS.md](CREDITS.md).
