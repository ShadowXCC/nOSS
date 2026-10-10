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

**M0 (foundations) is done:** the project skeleton, the `noss_core` C++ extension, tests and JSON schemas. The game boots to a title screen. Next up is **M1**, the first drivable demo ([roadmap](docs/ROADMAP.md)).

## Development (Linux)

Needs `git`, `curl`, `unzip`, `python3` (with `venv`) and a C++20 compiler (GCC or Clang).

```sh
git clone --recursive <repo>       # or: git submodule update --init --recursive
tools/setup_dev.sh                 # pinned Godot in .tools/, SCons in .venv/ (nothing system-wide)
tools/build_native.sh              # builds noss_core into native/bin/
tools/run_tests.sh                 # native, schema and GDScript tests, plus a boot check
tools/godot.sh                     # runs the game; add -e for the editor
```

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
