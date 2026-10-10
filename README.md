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

**M3 (`v0.3.0`): local multiplayer.** Up to four players on one PC. Press any button to join, each player with their own profile, controls, car and settings. Splitscreen in one window (two players stacked or side by side, three with a wide view or a track map, four in quarters), or a fullscreen window per monitor, mixed as you like (1+3, 2+2). Two players can share the keyboard (one side each). Every view has its own HUD, menus and pause, and players can drop in and out mid-drive. Per player: HUD size, menu text size, high-contrast HUD, a clear font, brightness, hold or toggle, one-handed control layouts, full rebinding, and two devices for one car. Four players with 200k-triangle cars run at about 300 fps at 1080p on the dev PC.

**M2 (`v0.2.0`):** bring your own car. The **Fitting Bay** turns a GLB, glTF or FBX into a car with no preparation: it finds the wheels (even when they're part of the body), works out which way is up and forward, scales it, and picks up paint slots, lights and the cockpit. Save and drive, or adjust each step. The **Garage** lists your cars with thumbnails: drive, edit, paint, tune the engine sound, copy, delete. Six classes now: Track Touring, GT, Prototype and Formula, Kart Medium, and Highway Street, each checked by the conformance runner so every model drives exactly the same. Also new: hood and bumper cameras, four synthesized engine sounds you can tune per car, generated LODs. Next up is **M4**, track racing ([roadmap](docs/ROADMAP.md)).

## Playing

- **Free Drive** on the title screen: pick a class (how the car drives), then the **Players** screen. Press any button on a keyboard, controller or wheel to join (up to 4). Each player picks their profile and car (how it looks) on their own card with their own device, and sets their monitor, keyboard side, extra devices and settings there. Ready starts the drive once everyone is ready. The original **nOSS Box** and **nOSS Open** always work; your own cars come from the garage (`~/.local/share/nOSS/garage/` on Linux, `%APPDATA%\nOSS\garage` on Windows).
- **Sharing the keyboard:** set a player's Keyboard to Left side (WASD, Space, Q/E, C, X, R, Tab, Esc) and the right side (arrows, `/` handbrake, `,`/`.` shift, `;` camera, `'` look back, `]` reset, `[` change car, Backspace pause) becomes free for another player.
- **Mid-drive:** a free controller or wheel joins by pressing a button. Pause opens in your own view; Leave drops you out. Splitscreen options (layouts, whose sound you hear, auto resolution) are in Settings.
- **Fitting Bay** on the title screen: Browse to a `.glb`, `.gltf` or `.fbx` (or drop files in the `import` folder next to the garage) and press **Save and drive**. The steps (Orient, Wheels, Scale, Paint, Cockpit, Sound, Save) adjust what it found; Save also offers a test drive that comes back to the bay.
- **Garage** on the title screen: your cars and the built-in ones.
- **Keys** (whole keyboard): arrows or WASD to drive, Space handbrake, E/Q shift, C camera (chase near and far, hood, bumper, cockpit), B look back, R reset car, Tab change car while driving, Esc pause, F3 frame rate. **Controller:** left stick, triggers, A handbrake, bumpers shift, Y camera, R3 look back, View reset, D-pad up change car, Start pause. Every action on every device can be rebound per player (Settings → Buttons and keys); one-handed controller layouts are there too.
- **Wheel:** a player's Settings → Wheel setup. Pick the device, set its rotation, detect steering and pedals by moving them (pedals can be a separate device: add it on the Players screen), tune and test force feedback. Linux needs the system SDL3 (`libsdl3-0` on Ubuntu); Windows builds ship it.
- **Player settings** (each player's own): assists (ABS, traction control, auto gearbox, steer aid), comfort (camera shake, head movement, speed FOV, horizon lock), HUD size, menu text, high-contrast HUD, font, brightness, hold or toggle for throttle, brake, handbrake and look back, menu repeat. With the auto gearbox, holding the brake at a standstill selects reverse.

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

**Dev options** go after `--`, e.g. `tools/godot.sh -- --drive --autodrive --camera=cockpit`: `--drive`, `--car=<path>`, `--platform=<id>`, `--autodrive` (the line follower drives), `--camera=<chase_near|chase_far|hood|bumper|cockpit>`, `--shot=<file.png> --shot-at=<s>`, `--quit-at=<s>`, `--fps`, `--log-drive`, `--swap-car=<path> --swap-at=<s>`, `--menu=<classes|players|settings>`, `--join=<n>` (Players screen: n devices join), `--garage`, `--bay`, `--import=<model>`, `--bay-auto` (save and drive as soon as the import is in), `--bay-step=<step>`.

Local multiplayer: `--players=<n>` (extra players driven by the line follower), `--screens=0,0,1,1` (monitor per player), `--split=<stacked|side>`, `--three=<wide|map>`, `--ai-car=<path>`, `--ai-profile=<json>` (options for those players, e.g. `'{"hud_scale": 1.5}'`), `--pause-at=<s>`, `--perf` (frame, CPU, physics and per-view GPU times), `--fullscreen`, `--no-vsync`. `--shot` saves one PNG per window.

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
