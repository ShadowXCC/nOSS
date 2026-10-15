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

**M7 (`v0.7.0`): highway.** The **Lumen Ring**, an 8.3 km city ring expressway: three lanes each way, a river viaduct, a tunnel, three interchanges and four flyovers that switch carriageway, towers all round. **Traffic** (150 cars by default, up to 400) keeps to its lanes, signals, changes lanes, takes exits and comes back on later, so the same cars come round again. Near a player a car becomes a full physics car that can be hit, spun and wrecked; wrecks close the lane until they're towed. Online, every game runs the same traffic from the server's seed and checks it every second. Four ways to drive: **Cruise**, **Score attack** (near misses over 120 km/h build a combo that banks after 5 s quiet; a touch loses it), **Runs** (rolling start, checkpoints, results) and **Loop** (laps either way, boards per direction). **Police** (optional): speed traps, heat from 1 to 5, pursuits that ram and box in, roadblocks from heat 4; stop with a unit on you and you're busted, get far and out of sight and you've evaded. Two new classes, Highway Super and the police Interceptor, and an original traffic set (hatch, saloon, SUV, van, truck, bus). Horn and headlight flash, name plates, sirens on the sound arrows, and Reduce flashing calms the light bars. The editor builds highways too: lanes, median and shoulders, exits, entries and flyovers, runs, speed traps and zones. Checked with 16 headless players, 150 traffic cars and police online for 10 minutes (no traffic disagreements, under 40 KB/s for most players), at 150 ms with loss, with matching traffic on Linux and Windows builds, and with two players driving opposite ways meeting every lap, about 90% of the traffic coming round again.

**M6 (`v0.6.0`): track editor.** Build your own tracks in the game: drag out a road (widths, banking, heights, curbs, barriers, run-off, bridges over the ground), shape and paint the terrain (it's ours, no addon), place and scatter props, and set the start, grid, sectors and checkpoints. The AI works out its own line, which you can pin by dragging, and the lap it would do; checks show what's wrong and where. Test-drive from the cursor and come back to the same view with undo intact; autosave every 2 minutes. Tracks save as `.nosstrack` files and go to players who don't have them when they join online. **Track Fitting** turns a GLB, glTF or FBX scene into a track: tag its surfaces (rules by name, or material by material), click along the road, measure its widths, race it. Works with mouse, keyboard or controller, and with a screen reader. Checked with a 3 km track built through the editor's own commands, raced by 8 AI cars and sent online, and a circuit made from the Kenney Racing Kit, fitted and raced.

**`v0.5.1`: playtest fixes.** The pause menu closes again (online too, and with the mouse), menu arrows step both ways with the mouse, the title and Garage paint menus fit the screen, the Garage works by keyboard and controller (confirm on a car for its actions, back to return), the Online Players screen is clearer, and tire sounds can be picked per car: the new **Squeal** (default) or **Classic**, or your own loop.

**M5 (`v0.5.0`): online.** Host from the menu and play (a listen server), or run the headless **dedicated server** from a config file. Up to 16 players per game, splitscreen guests included (up to 4 per connection). Join by address or from the LAN list; the host's router port opens itself (UPnP). Each install has its own key, so kicks, bans and admins stick without accounts; an optional password never travels. Lobby with chat (quick lines for controllers), car picks, ready, kick and ban. Free drive and race weekends online: the server runs the event and fills the grid with AI, cars are shown at the present time, contacts are shared between players, and bad links are ghosted. Cars, custom classes and recordings transfer by hash into a cache; a new player sees every real car in about 25 s (placeholders in the right shape first). Server rules: classes, assists, tuning lock, strict fitting, own sounds, size caps; plausibility checks flag or kick cheats. **Own engine recordings** (OGG or WAV) in the Fitting Bay's Sound step. Checked with 16 headless bots on the dedicated server and at 150 ms simulated round trip, and played over the internet and between Linux and Windows on a LAN.

**M4 (`v0.4.0`): track racing.** Race weekends against up to 15 AI drivers: practice, qualifying and the race (laps or minutes), standing or rolling starts, a grid from qualifying, reversed or random, flags, track limits with warnings and time penalties, and results with each driver's assists. The AI drives the same cars on the same physics as you, follows a racing line, passes, defends, lets faster cars by and keeps out of pile-ups (checked over hundreds of simulated race laps). **Time trial** with a ghost of your best lap and a local leaderboard. **Setups** per class and track. Every assist (stability control new), plus access assists: auto-throttle, brake and steering assist, autodrive. H-shifter, clutch, handbrake levers and button boxes and full force feedback (not yet tried on real hardware); controller rumble. Accessibility: colourblind palettes, narration and a spotter (with captions), volume groups and mono, game speed, HUD presets, a first-boot accessibility screen, and menus that work with a screen reader, keyboard alone or a controller alone.

**M3 (`v0.3.0`): local multiplayer.** Up to four players on one PC. Press any button to join, each player with their own profile, controls, car and settings. Splitscreen in one window (two players stacked or side by side, three with a wide view or a track map, four in quarters), or a fullscreen window per monitor, mixed as you like (1+3, 2+2). Two players can share the keyboard (one side each). Every view has its own HUD, menus and pause, and players can drop in and out mid-drive. Per player: HUD size, menu text size, high-contrast HUD, a clear font, brightness, hold or toggle, one-handed control layouts, full rebinding, and two devices for one car. Four players with 200k-triangle cars run at about 300 fps at 1080p on the dev PC.

**M2 (`v0.2.0`):** bring your own car. The **Fitting Bay** turns a GLB, glTF or FBX into a car with no preparation: it finds the wheels (even when they're part of the body), works out which way is up and forward, scales it, and picks up paint slots, lights and the cockpit. Save and drive, or adjust each step. The **Garage** lists your cars with thumbnails: drive, edit, paint, tune the engine sound, copy, delete. Six classes now: Track Touring, GT, Prototype and Formula, Kart Medium, and Highway Street, each checked by the conformance runner so every model drives exactly the same. Also new: hood and bumper cameras, four synthesized engine sounds you can tune per car, generated LODs. Next up is **M4**, track racing ([roadmap](docs/ROADMAP.md)).

## Playing

- **Race** on the title screen: pick a class, then the race (practice, qualifying, length, AI cars and skill, start, grid, collisions, track limits), then the players. Results show after each session; Continue goes on to the next.
- **Time Trial**: pick a class and drive laps alone. Your best lap becomes a ghost and goes on the local leaderboard (pause menu → Leaderboard); ghost files from friends dropped in `~/.local/share/nOSS/ghosts/proving_ground/<class>/` can be picked in the pause menu.
- **Highway** on the title screen: pick a highway, then the mode (Cruise, Score attack, Run, Loop), traffic (off to 400 cars), police, which way round (or the run), the class and the players. The pause menu turns you round onto the other carriageway or puts you behind a friend; Loop and Score attack boards are under Leaderboard. **H** sounds the horn and **L** flashes the headlights (controller: left stick press and X).
- **Setup** (pause menu, not during races): gearing, brake balance, springs, roll balance, wings, diff, as the class allows. Saved per class and track.
- **Free Drive** on the title screen: pick a class (how the car drives), then the **Players** screen. Press any button on a keyboard, controller or wheel to join (up to 4). Each player picks their profile and car (how it looks) on their own card with their own device, and sets their monitor, keyboard side, extra devices and settings there. Ready starts the drive once everyone is ready. The original **nOSS Box** and **nOSS Open** always work; your own cars come from the garage (`~/.local/share/nOSS/garage/` on Linux, `%APPDATA%\nOSS\garage` on Windows).
- **Sharing the keyboard:** set a player's Keyboard to Left side (WASD, Space, Q/E, C, X, R, Tab, Esc) and the right side (arrows, `/` handbrake, `,`/`.` shift, `;` camera, `'` look back, `]` reset, `[` change car, Backspace pause) becomes free for another player.
- **Mid-drive:** a free controller or wheel joins by pressing a button. Pause opens in your own view; Leave drops you out. Splitscreen options (layouts, whose sound you hear, auto resolution) are in Settings.
- **Fitting Bay** on the title screen: Browse to a `.glb`, `.gltf` or `.fbx` (or drop files in the `import` folder next to the garage) and press **Save and drive**. The steps (Orient, Wheels, Scale, Paint, Cockpit, Sound, Save) adjust what it found; Save also offers a test drive that comes back to the bay.
- **Garage** on the title screen: your cars and the built-in ones.
- **Track Editor** on the title screen: start from a template (File → New track) or Import scene, then work through the tools left to right: Road, (Surfaces), Terrain, Paint, Props, Race, Check, File. F5 test-drives from the cursor (F5 again, or the pause menu, comes back); Ctrl+Z undoes. Save puts the track in your tracks (File → Show track files); the track pickers (Free Drive, Race, Time Trial, Host) list it. Mouse, keys or controller: [docs/TRACK_EDITOR.md](docs/TRACK_EDITOR.md#2-editor-tools).
- **Keys** (whole keyboard): arrows or WASD to drive, Space handbrake, E/Q shift, C camera (chase near and far, hood, bumper, cockpit), B look back, R reset car, Tab change car while driving, Esc pause, F3 frame rate. **Controller:** left stick, triggers, A handbrake, bumpers shift, Y camera, R3 look back, View reset, D-pad up change car, Start pause. Every action on every device can be rebound per player (Settings → Buttons and keys); one-handed controller layouts are there too.
- **Wheel:** a player's Settings → Wheel setup. Pick the device, set its rotation, detect steering and pedals by moving them (pedals can be a separate device: add it on the Players screen), tune and test force feedback. Linux needs the system SDL3 (`libsdl3-0` on Ubuntu); Windows builds ship it.
- **Player settings** (each player's own): assists (ABS, traction and stability control; auto gearbox, auto clutch and steer aid as Auto, On or Off, where Auto follows the device; racing line) and access assists (auto-throttle, brake assist, steering assist, autodrive); vision (colours for colourblind players, Reduce flashing, narration, spotter); hearing (captions, shift light, slip indicator, close-car arrows); HUD (Full, Minimal, Off, or element by element); game speed (one player); comfort; HUD size, menu text, high contrast, font, brightness; controls (hold or toggle, menu repeat, controller rumble, rebinding including clutch, gear gates and levers on any device). With the auto gearbox, holding the brake at a standstill selects reverse. Each player's card on the Players screen has **Access** for quick accessibility presets; the same screen opens on first boot.
- **Online** on the title screen. **Players** sets who plays on this PC (up to 4 share one connection). **Host** starts a game others can join: name, password, size, class, free drive or a race weekend, LAN discovery and the router port; the lobby shows the addresses to share. **Join** by address (`host`, `host:port` or `[ipv6]:port`) or pick a game under *On your network*. In the lobby pick your car and press Ready; the host (or an admin) can Start, and kick or ban from a player's row. Chat in the lobby and from the pause menu; controllers have quick lines. The default port is UDP 47800; if the router won't open it, forward it by hand.
- **Dedicated server:** `noss_server --config server.json` (start from [`data/server.example.json`](data/server.example.json)), or from the project `tools/godot.sh --headless -- --server --config=server.json`. Admins, bans, rules and the event rotation live in the config; type `help` in its console. See [Networking §9](docs/NETWORKING.md#9-dedicated-server).
- **Own engine recordings:** Fitting Bay → Sound → Own recordings. Mono OGG or 16-bit WAV at 44.1 or 48 kHz, one loop per rpm (on and off load) for the engine, exhaust or intake, plus start, limiter and backfire sounds. They travel with the car; servers can turn them off. **Tires** (same step): Squeal or Classic, **Skid** to hear them, or your own tire loop (For: Tires).
- **Game settings:** graphics, units, sound by group (own engine, other engines, tires, effects, music, menus, spotter, narration) and mono, splitscreen.

### Converting FM4 rips (local use only)

```sh
python3 tools/fm4_to_noss.py "<...>/Forza Motorsport 4/models"   # every car folder inside, into the garage
```

Converted packages are marked `personal-use-only` and must never be shared or committed; the game keeps them offline (online car lists leave them out) ([Requirements §6](Requirements.md#6-content-and-legal-policy)).

## Development (Linux)

Needs `git`, `curl`, `unzip`, `python3` (with `venv`) and a C++20 compiler (GCC or Clang).

```sh
git clone --recursive https://github.com/ShadowXCC/nOSS.git   # or: git submodule update --init --recursive
tools/setup_dev.sh                 # pinned Godot in .tools/, SCons in .venv/ (nothing system-wide)
tools/build_native.sh              # builds noss_core into native/bin/
tools/run_tests.sh                 # native, schema, tools, GDScript and conformance tests, a short AI race, boot check
tools/run_conformance.sh           # platform conformance only; report in tests/conformance/out/
tools/race_check.sh --laps=5       # 12-car AI race soak (--seed, --skill=40-100, --bad=stall|early_brake|spin, --platform, --track=<id|file>)
tools/net_check.py --clients 12 --quad 1 --event race --laps 3   # dedicated server + 16 bot players (--rtt, --jitter, --loss, --rate, --fresh, --cheat, --track)
tools/net_sim.py --listen 47820 --to 127.0.0.1:47800 --delay 75   # UDP proxy (75 ms each way):: delay, jitter, loss, bandwidth cap (no root)
tools/a11y_check.py                # boot -> race -> results, the online menus and the track editor, over AT-SPI (needs a display; private D-Bus session)
tools/track_check.sh               # M6: a 3 km track built with the editor's commands, raced by AI, sent online to a fresh bot
tools/highway_check.sh --scenario=loop --laps=3   # M7: two players opposite ways round the Lumen Ring (meetings, traffic coming round); default: cruise (--players, --traffic=400)
tools/net_check.py --event highway --clients 12 --quad 1 --traffic 150 --police   # 16 players and traffic online (--dirs opposite, --sub, --desync, --open)
tools/traffic_determinism.sh       # the Linux and Windows builds step the same traffic (Windows under Wine)
tools/traffic_bench.sh             # physics cost of full, lite and kinematic cars
tools/godot.sh --headless -s res://tools/make_kenney_circuit.gd   # the Track Fitting test circuit (needs the Kenney Racing Kit, see the script)
tools/godot.sh --headless -s res://tools/cvd_shots.gd -- shot.png   # colour-blind versions of a screenshot
tools/godot.sh                     # runs the game; add -e for the editor
```

**Exports** (Linux and Windows, cross-compiled with LLVM MinGW):

```sh
tools/setup_export.sh              # pinned export templates, LLVM MinGW, SDL3.dll (all project-local)
tools/export.sh                    # builds release noss_core and exports to export/linux, export/windows
tools/export.sh server             # the headless dedicated server: export/server/noss_server.x86_64
```

**Dev options** go after `--`, e.g. `tools/godot.sh -- --drive --autodrive --camera=cockpit`: `--drive`, `--car=<path>`, `--platform=<id>`, `--autodrive` (the line follower drives), `--camera=<chase_near|chase_far|hood|bumper|cockpit>`, `--shot=<file.png> --shot-at=<s>`, `--quit-at=<s>`, `--fps`, `--log-drive`, `--swap-car=<path> --swap-at=<s>`, `--menu=<classes|players|settings>`, `--join=<n>` (Players screen: n devices join), `--garage`, `--bay`, `--import=<model>`, `--bay-auto` (save and drive as soon as the import is in), `--bay-step=<step>`.

Racing: `--race` (the last race set up; `--race-laps=<n>`, `--race-ai=<n>`, `--race-practice=<min>`, `--race-quali=<min>`, `--race-start=rolling`, `--race-grid=<qualifying|reverse|random>`), `--time-trial`, `--ai=<n>` (AI racers in free drive; `--ai-skill=<0-100>`, `--ai-builtin`), `--auto-continue`, `--quit-after-results`, `--log-ghost`. Checks: `--no-save`, `--skip-first-boot`, `--screen-reader`, `--p1-profile=<json>`, `--voices`, `--menu=<classes|event|players|settings|online|online-players|tracks>`, `--pause-menu=setup`; `--shot-at` takes a list (`5,30,90`).

Highway: `--highway` (the first highway, or `--track`; `--sub=<cruise|score|run|loop>`, `--traffic=<cars>`, `--traffic-seed=<n>`, `--police`, `--direction=<-1|both>`, `--run=<id>`, `--players=<n>`), `--speed-factor=<0.5-2>` (autodrive past the limit), `--perf-log` (a frame-time summary every 30 s and at exit), `--traffic-selftest` (step a highway's traffic and print its checksum).

Tracks: `--track=<id|file>` (for `--drive`, `--race`, `--time-trial`), `--editor` (`--editor-track=<id|file>`, `--editor-template=<empty|oval|circuit|figure8>`, `--editor-import=<file>`, `--editor-tool=<road|surfaces|terrain|paint|props|race|check|file>`). With `--perf` the editor prints how long it takes to open, update, brush and autosave.

Online: `--host` (host with the last settings), `--connect=<address>`, `--password=<p>`, `--port=<n>`, `--no-upnp`, `--instance=<n>` (a second copy on one PC with its own settings and key), `--cache=<dir>`, `--net-debug`; dedicated server `--server --config=<file>` (`--min-players=<n>`); headless bot clients `--bot` (used by `tools/net_check.py`).

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
