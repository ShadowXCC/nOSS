# Architecture

How nOSS is put together: engine, languages, code layout and the main runtime systems. Requirement IDs refer to [Requirements.md](../Requirements.md).

---

## 1. Engine: Godot 4

**Godot 4.7.2** (pinned in M0, [DECISIONS.md](DECISIONS.md) D31).

### Why Godot (short version of the comparison)

| Need | Godot 4 | Bevy (Rust) | Custom engine |
|---|---|---|---|
| Runtime model import | `GLTFDocument`, `FBXDocument` built in | Excellent glTF | Build or integrate it ourselves |
| Physics | Jolt built in (4.4+) | Avian/Rapier crates | Integrate Jolt |
| Splitscreen + multi-monitor | SubViewports + native multi-window | Native multi-window/camera | Build it ourselves |
| Networking | ENet high-level API, headless export | Third-party crates | Build it ourselves |
| Editor UIs (track editor, Fitting Bay) | Mature UI toolkit (Godot's own editor is built with it) | Immature UI (egui workable) | Build it ourselves |
| Linux/Windows/macOS | One-click exports | Good | Metal/Vulkan/D3D work |
| Stability | Stable 4.x API | Breaking release every ~3–4 months | Ours to keep stable |
| License | MIT | MIT/Apache | — |
| Time to first demo | Fastest | ~2–3× | Years |

### Known Godot gaps and how we cover them

| Gap | Answer |
|---|---|
| Built-in `VehicleBody3D` is basic | Own vehicle sim in C++ ([PHYSICS.md](PHYSICS.md)) |
| No wheel FFB (rumble only) | Native SDL3 haptics inside `noss_core` ([INPUT.md](INPUT.md)) |
| Single-precision coordinates | Floating origin (§8) |
| High-end visuals trail Unreal | The retro world style comes first; profiles scale up later (§7) |
| GDScript too slow for physics inner loops | C++ GDExtension |

## 2. Language split

| Layer | Language | Contents |
|---|---|---|
| Gameplay and UI | **GDScript** | Game flow, modes, menus, HUD, track editor, Fitting Bay, networking glue, high-level AI behavior |
| Native core: `noss_core` | **C++20** GDExtension (godot-cpp) | Vehicle sim (tires, suspension, drivetrain, aero), conformance maneuvers, wheel input and FFB (SDL3), package validation, mesh work (LODs, connected parts, principal axes; meshoptimizer), engine and tire sound synthesis, terrain (heightfield brushes, paint, the road's bed, chunk data, 16-bit PNG, the surface map), traffic bulk update |
| Tools | **Python 3** (stdlib only) | `fm4_to_noss.py`, packers, conformance report tools |

**Rule:** start in GDScript and move code to C++ once profiling shows it's hot, or when it needs a native library. The vehicle sim is C++ from day one.

**Build:** SCons, matching godot-cpp's primary build (D32). Third-party code is pulled in as git submodules under `native/thirdparty/`.

## 3. Repo layout (created in M0)

```
nOSS/
├─ project.godot
├─ game/                  GDScript + scenes
│  ├─ app/                boot, settings, save paths, style profiles
│  ├─ players/            local player slots, device join, viewports and windows
│  ├─ vehicles/           platform loader, package loader and writer, fitting, visual rig,
│  │                      cameras; import/ (model import, analysis, LODs)
│  ├─ modes/              common/, track/, kart/, highway/, endless/, sumo/
│  ├─ world/              track data and format, track packages (load, write, library), the
│  │                      track builder (road, props, scenes), terrain/, props/, checks,
│  │                      kart/ (kart pieces: layout, stunt builder), arena/ (outline, floor, wall),
│  │                      env/ (time of day, weather, lightning), endless/ (road window, world,
│  │                      ground, biomes), the floating origin
│  ├─ ai/                 racing, kart, battle (arena nav), item policy, traffic, police, endless
│  ├─ net/                server, client, lobby, chat, content transfer, car states, race sync
│  ├─ editor/             track_editor/ (draft and history, view, gizmos, preview, tools/:
│  │                      road, ramps, stunts, surfaces, terrain, paint, props, race, check), fitting_bay/
│  ├─ audio/              engine sound player, SFX, music
│  └─ ui/                 menus, HUD, themes, garage
├─ native/                C++ GDExtension "noss_core"
│  ├─ src/core/  src/vehicle/  src/input/  src/package/  src/traffic/  src/mesh/  src/audio/
│  │  src/endless/        the endless road generator, landscape and biomes (M9)
│  │  src/world/          terrain heightfield, PNG16, surface map (M6)
│  ├─ thirdparty/         godot-cpp, SDL3, doctest, meshoptimizer (M2) (submodules)
│  └─ SConstruct
├─ data/
│  ├─ platforms/<mode>/<class>.platform.json   official platforms
│  ├─ modes/<mode>.mode.json                   mode rules and overrides
│  ├─ items/                                   kart item odds
│  ├─ cups/                                    built-in kart cups
│  ├─ endless/biomes/                          how each endless biome looks and sounds
│  ├─ sound_profiles/                          built-in engine sounds
│  ├─ input_presets/                           device presets
│  ├─ tire_sounds/                             built-in tire profiles
│  └─ schemas/                                 JSON schemas (platform, package, fit, paint, sound, track,
│                                              track package, terrain, scene tags, server, input presets)
├─ content/               original CC-BY-SA assets: default cars, tracks/<id>/ (built-in tracks as folders)
├─ tools/                 dev setup, build and test scripts; fm4_to_noss.py, conformance runner, packers
├─ addons/gdUnit4/        GDScript test framework (vendored)
├─ tests/
│  ├─ game/               gdUnit4 tests, mirroring game/
│  ├─ editor/             track_check: the M6 acceptance build (a scene, run by tools/track_check.sh)
│  ├─ race/               race_check: the AI race soak
│  ├─ endless/            endless_check: the long drive (tools/endless_check.sh)
│  ├─ native/             doctest tests for noss_core
│  └─ schemas/            JSON schema checks and fixtures
└─ docs/
```

## 4. Runtime overview

```
 Devices ──► Input layer ──────────► PlayerSlot ──► VehicleController (assists)
 (Godot InputMap for KB/pad,                               │ controls
  noss_core SDL3 for wheels)                               ▼
                         Platform (data) ──► VehicleSim  (C++, 480 Hz substeps)
                         Fitting (geometry) ─►   │   ▲
                                                 ▼   │ contacts and casts
                                    Jolt rigid body + shape casts (120 Hz)
                                                 │
     ┌───────────────┬──────────────┬────────────┼──────────────┬──────────────┐
     ▼               ▼              ▼            ▼              ▼              ▼
  VisualRig       Cameras        Audio         FFB         Telemetry        Mode
  (wheels, lights, (per player   (engine       (native     (HUD, UDP out)   (rules, scoring,
   steering wheel)  viewport)     profile)      thread)                     events)
                                                                              ▲
                                       Net (ENet) ◄──────────────────────────┘
                              vehicle states, session state, content transfer
```

### Vehicle node structure

```
Vehicle (RigidBody3D, Jolt)       mass, inertia, CoG from platform (never from the model)
├─ CollisionShape3D               convex hull of the fitted envelope, clamped to platform limits
├─ VehicleSim (GDExtension)       wheels, suspension, drivetrain as data, not nodes
├─ VisualRoot                     model transform: scale and offset from fit.json
│  └─ <package scene>             hub_* nodes driven by the sim (spin, steer, bounce)
├─ CameraMounts                   chase, hood, bumper, cockpit eye point
├─ AudioEmitters                  engine, exhaust, intake, tires
└─ LightRig                       head, brake, reverse, indicator (from fit.json mapping)
```

## 5. Physics tick

*Requirement: NFR-03.*

- Godot physics runs at **120 Hz** (`physics/common/physics_ticks_per_second = 120`) using Jolt.
- Inside each tick, `VehicleSim` runs **4 substeps (480 Hz)** for wheel spin, tire forces, drivetrain and clutch, since stiff wheel dynamics need a small dt. The chassis state is integrated by Jolt; the sim applies the substep-averaged forces and torques.
- **Physics interpolation** is on, so rendering is smooth at any frame rate.
- Player vehicles never sleep, and they use Jolt's linear-cast motion quality to prevent tunneling at speed.

## 6. Local players: splitscreen and multi-monitor

*Requirements: LOC-01…LOC-05. Built in M3 (decisions D54–D61).*

- **Players** (autoload, `game/players/players.gd`): up to 4 **PlayerSlots**, each with a profile, the devices it claimed, a car and a monitor. While joining is open, the first press on a free device claims the next slot; "Add device" gives a slot another one. Which profile a device belongs to and each profile's monitor are remembered in `user://players.json`.
- **Devices** (autoload): lists what can be claimed: the keyboard (whole, or its left and right sides, D55), Godot's gamepads (by GUID) and noss_core's sim devices.
- **PlayerInput** (one per slot): polls only that player's devices through presets and overrides (D54). Each physics tick it gives analog values and edges; each frame, menu navigation with repeat, pushed into the player's own viewport as `InputEventAction`.
- **ViewManager** (per session): one **PlayerView** per player. A view is a `SubViewport` showing the shared `World3D`, with the player's camera, HUD layer, menu layer and focus cursor (D57). Each window is split by **SplitLayout**:
  - 1 player: full window.
  - 2 players: stacked or side by side (a setting).
  - 3 players: one wide view on top and two below, or 2×2 with a **track map** in the spare quarter.
  - 4 players: 2×2.
- **Multi-monitor:** a player can pick a monitor. Each monitor in use, other than the main window's, gets a native borderless fullscreen `Window` split the same way, so 1+3 or 2+2 across two monitors works (D56).
- **Scaling:** views render at the window's real pixel size. Their 2D is laid out for 1080p and scaled to the view (more in half views than in quarters), then by the player's HUD size or menu text size.
- **Performance:** each view has its own render scale. With auto resolution on, it steps down to 0.5 while frames are slower than 60 fps. Car LODs switch closer with more views (D60).
- **Audio:** each view listens; car sound is scaled by 1/√views, or only P1's view listens (a setting, D58). The volume groups are buses (`OwnEngines`, `OtherEngines`, `Tires` under `Cars`, which takes the 1/√views; `Effects`, `Ambience`, `Music`, `UI` under Master); mono is a stereo enhancer with no side signal on Master. Speech (narration, spotter) goes through the OS text-to-speech (`Narrator` autoload), with its own volumes.
- **Menus:** shared menus (title, class, game settings) use the main window and any device; their text size is the largest of the joined players'. Each player's own menus (Players screen card, pause, car picker, their settings) open in their view and take only their input. Pause stops everyone and belongs to whoever paused.
- **Racer** (`game/modes/common/`, M4): one car in a session: car loading and hotswap, lap timer, reset spot and safe rejoin, race state (held, finished, penalties, flag). **SessionPlayer** adds a player's controller, camera rig, HUD and menus; **AiRacer** is a computer driver (RacingAI) with no view. The **TrackSession** keeps the shared parts (track, platform, views, grid, pause) and handles drop-in and drop-out.
- **RaceField** projects every car onto the track once per tick before anyone drives; drivers, the spotter, flags and standings read it. **RaceControl** runs the event's sessions (practice, qualifying, race, time trial, free drive): grid, countdown, standings, flags, track limits, finish and results (D63, D67).
- **Physics order per tick:** player input (−90) → RaceField (−60) → RaceControl (−55) → drivers (−50) → vehicles (0).
- **Karts** (`game/modes/kart/`, M8, D129): a class whose mode has the `kart_arcade` layer adds **KartControl** (tow drone, slipstream, beached karts) with **KartBoxes**, **KartItems** (slots, roulette, uses, hits; the authority offline), **KartEntities** (Bolts, Seekers, the Hunter, Slicks), **KartEffects**, **KartHud** and **KartSounds**; a battle adds **BattleControl** (lives, hits, out, the end); a cup is a **CupRun** kept by Game between its races. The layer itself is native (`native/src/vehicle/kart_layer.*`, PHYSICS.md §9). AI: **KartAI** (the racing AI with drifts, loops, boxes and Slicks) and **BattleAI** (ArenaNav paths), both using **ItemPolicy** (also the item assist). Order: KartControl and KartItems (−57) → BattleControl (−53) → drivers (−50).
- **Highways** (`game/modes/highway/`, M7, D113): a highway event adds **HighwayField** (where each car is: road or ramp, carriageway, lane; wrong way), **TrafficManager** (the native lane sim `NossTraffic` in `native/src/traffic/`: stepping it, drawing distant traffic with one MultiMesh per type, turning cars near players into physics **TrafficCar**s and back, wrecks and tows, solid boxes past the cap), **HighwayControl** (starts, portals, resets, turning round, Join, loop boards, name plates) and, by sub-mode, **HighwayScore** (ScoreAttack rules and NearMiss), **RunControl** and **PoliceControl** (Heat; PoliceRacer units driven by PoliceAI, which drives the lanes like the autodrive's **HighwayDriver**). Order: HighwayField (−59) → TrafficManager (−58) → HighwayControl (−56) → drivers and traffic cars (−50) → RunControl (−45) → PoliceControl (−44) → HighwayScore (−40).
- **The sky** (`game/world/env/`, M9, D153): every session has an **EnvDirector** (−58). **EnvState** is a pure function of the event's sky settings and the session's clock (hour, sun and moon, the weather front, wetness and snow cover in closed form), so a late joiner gets the same sky. The director puts it on the world a few times a second: one DirectionalLight3D (sun by day, moon by night), the sky shader's uniforms, fog, ambient light and exposure from the style's palettes, the shader globals `env_wetness`, `env_snow` and `env_night` (wet shine, settled snow, lamps), headlights and beams, and each car's grip conditions. Every PlayerView owns an Environment copy kept in step, for its brightness and its own lightning. Each player has a **WeatherBox** (rain or snow streaks wrapped round their camera by `weather.gdshader`, on their own render layer, 17–20) and **Ambience** plays rain, wind, thunder and the biome's sounds (native synth, `native/src/audio/weather_synth.*`).
- **Endless** (`game/modes/endless/`, `game/world/endless/`, M9, D152–D158): the road is native (**NossRoadGen**, `native/src/endless/`: integer maths, 240 m chunks with checkpoints, the landscape and biomes). An endless event adds a **FloatingOrigin** (−98, §8), an **EndlessWorld** (a **RoadWindow** — a TrackData of the road from about 1 km behind the last player to 3 km ahead of the first, with absolute distances — the road's meshes and collision chunk by chunk, **EndlessGround** tiles, far tiles, props and the sea, made on workers and added within 2.5 ms a frame), **EndlessControl** (−56: spawns, resets, the local spread rule, the HUD, biome weather and sounds, pause items, Join), **EndlessTraffic** (−58: the schedule, **EndlessTrafficCar** physics cars near players, MultiMeshes) and **EndlessMusic**. **EndlessDriver** drives for the autodrive and bots. Order: FloatingOrigin (−98) → … → EnvDirector and EndlessTraffic (−58) → EndlessNet (−57) → EndlessControl (−56) → drivers and traffic cars (−50).
- **Sumo** (`game/modes/sumo/`, `game/world/arena/`, D162–D166): a sumo event builds no track. `TrackSession._load_sumo` makes a stand-in TrackData whose `arena` is a **SumoLayout** (1–3 stacked discs from the event's settings: radii, heights, the shrink and the goo's level), and **SumoBuilder** (a Node3D in the scene) makes the discs, the pit round them and the goo's surface and Area3D, remaking a disc's mesh and collision as it shrinks and throwing off crumbling rings. **SumoControl** (−53) holds the rules: arming a platform when a car lands, the goo, the ram boost, the standings and the end of a match; **SumoHud** and **SumoPanel** draw it and **SumoSounds** plays the shoves and splashes. **SumoAI** drives bots (no ArenaNav: a disc needs no pathfinding). Order: SumoControl (−53) → SumoNet (−52) → drivers (−50).

## 6b. Online

*Requirements: MP-01…MP-07, LOC-05. Built in M5 (decisions D78–D89); the protocol is in [NETWORKING.md](NETWORKING.md).*

- **Net** (autoload, `game/net/net.gd`): this game's role. Hosting, it holds a **NetServer** (ENet, join checks, players, kicks and bans), a **NetHost** (lobby, chat and commands, rotation, AI fill, discovery, UPnP) and a **NetContent**; joined, a **NetClient** and a NetContent. Menus make the same calls either way; the lobby and chat come back as the same messages.
- **NetContent** (per role) decides who fetches which car, track and platform; one **NetTransfer** per link moves files by hash (zstd, unreliable chunks, own acks and rate control); **ContentStore** is the hash-addressed cache and **ContentIndex** what this game may send.
- **In a session**, the TrackSession gets a **NetSession** (car states out and in, clock sync, contact relay, plausibility on the server) and a **NetRace** (the server's race state, grid, results and notes to clients, whose RaceControl only follows). Every car not driven here is a **NetRacer**: a kinematic Vehicle moved by its **MotionBuffer** to where its states put it now.
- **The dedicated server** (`ServerMain`) runs the same code with no players of its own, no views, no sound and no car models.
- **Highways online:** a **HighwayNet** (−59) keeps every game's lane sim on the server's ticks: the server's events and heartbeats out, and on clients the full state when they join or fall out of step (D109); traffic cars a game drives go out with its car states, and other games' show as proxies (D110). **RelayScheduler** picks which states each client gets, nearest first within a byte budget (D111).
- **Endless online:** an **EndlessNet** (−57) carries who drives each traffic car, slots used up, where every player is on the road and the road chunks' checksums (D159, NETWORKING.md §12). Car states carry world positions, so each game keeps its own floating origin.
- **Karts online:** a **KartNet** (−56, after the items move) carries the server's word on boxes, uses, hits and lives, and its 5 Hz snapshot of how things stand; each game shows its own items at once (D141, NETWORKING.md §11).
- **Physics order per tick** online: devices (−100) → network poll (−95) → lobby (−94) → content (−93) → player input (−90) → car states (−80) → remote cars (−70) → RaceField (−60) → highway traffic sync (−59) → kart items (−57) → kart sync (−56) → RaceControl (−55) → NetRace (−54) → drivers (−50) → vehicles (0).

## 7. Render style profiles

*Requirements: AV-01…AV-03.*

- A **StyleProfile** is a data bundle containing:
  - Environment: fog, sky, tonemap, glow.
  - World shader parameters.
  - Max texture size and filtering, LOD bias, shadow settings, post-process chain.
  - Car reflection mode.
- World materials use a shared `noss_world` shader that reads style uniforms, so tracks never hard-code their look.
- **`retro_ps2`** is the default. **`modern`** and others come later. See [ART_AUDIO.md](ART_AUDIO.md).
- **Cars are not affected by style limits.** They always render at full PBR detail. The style only picks the reflection source.
- **Renderer:** Forward+ (Vulkan / D3D12 / Metal). Mobile is a low-end fallback if the Steam Deck needs it.
- **Shareable style profiles are data-only.** A profile that includes custom shader code is local-only and opt-in, never auto-transferred.

## 8. Floating origin

*Built in M9 (D155, risk R7).* Endless roads (and later large real-world maps) go far beyond what 32-bit floats hold precisely: about 0.25 mm within 2 km, but 2 cm at 150 km.

- **FloatingOrigin** (`game/world/floating_origin.gd`, an endless session's node) keeps the world point the scene's origin is at as 64-bit floats. When what it watches gets **2 km** from it (this game's players' centroid; the convoy's on a dedicated server), the origin moves there and everything in the scene moves back by as much, in one physics tick, first in the tick (−98), so cameras and Doppler see no jump.
- **XZ only:** heights stay as they are. The origin snaps to **1500 m**, the least common multiple of every world texture's period (2, 3, 4, 5, 6 and 250 m), so world-mapped textures don't jump.
- **What moves:** every node in the group `origin_shift` gets `origin_shifted(delta)`: vehicles (keeping their speed and spin, no teleport flag), the road window and its chunks, ground tiles and their native maps (`set_origin`), remote cars' and traffic proxies' buffered states, racers' spawn and last good spots, the network's kept states and the server's checks. Physics interpolation is reset on whatever moved.
- **Local players** stay on one stretch of road: the event's spread rule brings the one behind up or holds the leader back past 3 km ([GAMEMODES.md §4](GAMEMODES.md#4-endless)).
- **Online** each game keeps its own origin round its own players. Car states carry world positions in millimetres wrapped to 32 bits; each game adds its origin going out and takes back the world point nearest it coming in (D159).
- **Measured** (`tools/endless_check.sh --minutes=120`, autodrive in normal traffic): 162 km, 83 moves; the car's step-to-step error 0.033 mm (RMS) in the last 10 minutes as in the first; the worst speed jump at a move 0.05 m/s. With the origin held still the same check fails within 30 minutes (0.75 mm at 37 km).

## 9. Threading

| Thread | Work |
|---|---|
| Main | Game logic, UI, scene tree, render submission |
| Physics | Godot physics plus `VehicleSim`, on the main thread for now (D34) |
| Worker pool | Package and track validation and loading, model and scene import, LOD generation; the track editor's AI line and checks, autosave encoding; content transfer decode; endless road meshes, ground tiles, far tiles and scatter (meshes on the main thread when headless: the stand-in renderer's mesh store isn't thread-safe); ambient music |
| Native FFB | ~500 Hz loop that mixes the latest FFB inputs (`native/src/ffb/`) and updates SDL3 haptic effects |

## 10. Data and save locations

*Requirement: NFR-09.*

`user://` maps to the standard per-OS location. A custom user dir is enabled, so the folder is named `nOSS`:
- Linux: `~/.local/share/nOSS`
- Windows: `%APPDATA%\nOSS`
- macOS: `~/Library/Application Support/nOSS`

```
user://
├─ settings.cfg
├─ profiles/<player>.json      bindings, assists, FFB, preferred cameras, HUD and comfort options
├─ players.json                which profile each device belongs to, each profile's monitor
├─ garage/<id>.noss            player car packages
├─ tracks/<name>.nosstrack     player tracks; .autosave/<id>/ (drafts, a note beside each)
├─ platforms/                  custom and downloaded platforms
├─ setups/<platform>/<track>.json
├─ ghosts/<track>/<platform>/   best.json and ghosts from friends
├─ leaderboards/<track>.json    local boards: time-trial laps, highway scores, runs and loop laps;
│                              server/ (a server's own boards of what it measured, M7)
├─ replays/
├─ identity/key.pem            this install's online key (fingerprint = SHA-256 of its public key)
├─ cache/content/              downloaded cars and tracks (unpacked), platforms, by hash; hosted/ (a
│                              server's bare track.json as a package); tmp/
├─ instances/<n>/              settings, profiles and key of a second copy on one PC (--instance)
├─ music/                      your own OGG and MP3 files for the endless road (you make it; the game only reads it)
└─ logs/                       server.log (dedicated server)
```

**Security rule:** Godot resource formats (`.tscn`, `.scn`, `.tres`, `.res`) are never loaded from packages or the network, because they can embed scripts. The import cache may hold `.scn` files only if this machine generated them.

## 11. Testing

- **Run everything:** `tools/run_tests.sh` (native build, doctest, schemas, gdUnit4 headless, conformance, an AI race and one in the rain, a kart race, a 10-minute endless drive, a highway with 400 traffic cars, online checks (a race, a highway, karts, a battle, an endless convoy), the track editor's 3 km acceptance build, boot smoke test).
- **Endless:** `tools/endless_check.sh --minutes=N` drives the autodrive headless (15× real time) and checks precision (the car's step-to-step error against its speed, speed changes at origin moves), memory (growth after warm-up, objects, nodes, built against freed), stuck time and frame times; `--no-rebase` is the negative control. `tools/endless_determinism.sh` compares the Linux and Windows builds' roads (`--endless-selftest`: 200 km of road and ground for four seeds).
- **Highways:** `tools/highway_check.sh` runs a highway session headless (`--scenario=cruise`: nothing stuck, a constant population; `--scenario=loop`: players going opposite ways meet every lap and the traffic comes round again). `tools/traffic_determinism.sh` compares the Linux and Windows builds' lane sims. `--traffic-selftest` prints a lane sim's checksum.
- **Track editor:** `tools/track_check.sh` builds a 3 km track headless with the editor's own commands, checks, saves and reloads it, races 8 AI cars on it and sends it to a fresh bot online. The Proving Ground has a golden test (samples, curbs, AI line, lap time, grid, pieces) that every change to the track code must keep.
- **GDScript:** gdUnit4, run headless (`godot --headless`).
- **Native:** doctest unit tests for tire, suspension and drivetrain math.
- **Platform conformance:** `tools/run_conformance.sh` drives standard maneuvers across each platform's geometry range on a native flat-ground harness, and checks the harness against Jolt ([PLATFORMS.md §5](PLATFORMS.md#5-conformance-tests)).
- **Network:** gdUnit4 tests run real ENet on 127.0.0.1 and a simulated lossy link for transfers. `tools/net_check.py` runs the dedicated server with headless bot clients (16 players), optionally through `tools/net_sim.py` (delay, jitter, loss, bandwidth); `run_tests.sh` includes a one-lap race at 150 ms.
- **CI (after the GitHub repo exists):** GitHub Actions builds `noss_core` for Linux, Windows and macOS, runs all tests, and exports builds.

## 12. Build and distribution

*Requirement: NFR-01.*

- Godot export templates: Linux x86_64, Windows x86_64, macOS universal.
- **Dedicated server:** the "Linux Server" export preset (dedicated server mode; it runs headless on its own), `tools/export.sh server` → `export/server/noss_server.x86_64`; see [NETWORKING.md §9](NETWORKING.md#9-dedicated-server).
- Releases on GitHub first. itch.io, Flatpak and Steam are later options.
- macOS signing and notarization need an Apple developer account. Until then, builds ship unsigned with instructions (open question in [DECISIONS.md](DECISIONS.md)).
