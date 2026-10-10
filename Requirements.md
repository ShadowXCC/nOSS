# nOSS: Requirements

**nOSS**: NOS + Open Source Software. Bring your own car; the platform decides how it drives.

Status: design spec v0.1 (2026-10-09), before any code. The spec lives in [`docs/`](docs/). Decisions and their reasons are in [`docs/DECISIONS.md`](docs/DECISIONS.md). Build order is in [`docs/ROADMAP.md`](docs/ROADMAP.md).

---

## 1. Vision

nOSS is a free, open-source racing game. Your car can look like anything you bring: a classic you ripped from an old game, your own Blender build, a city bus. It always drives like the **platform** you mount it on. Platforms are standardized per gamemode and class, so a race stays fair no matter whose model looks best.

## 2. Pillars

1. **The model is cosmetic and the platform is performance.** Nothing in a model file changes how a car drives.
2. **Bring anything.** Any reasonable 3D model works with little or no prep.
3. **Play together.** Up to 4 players locally (splitscreen or one monitor each) and 16 online, on servers players host themselves.
4. **Every input is first-class.** Keyboard, controller, and wheel with force feedback.
5. **Open and moddable.** GPL code, data-driven platforms, shareable cars and tracks.
6. **Runs anywhere.** Linux, Windows and macOS, down to Steam Deck-class hardware.

## 3. Glossary

| Term | Meaning |
|---|---|
| **Platform** | Data file that defines a vehicle's mechanics: dimension ranges, mass, engine, gearbox, tires, aero, allowed tuning. The only source of driving behavior. |
| **Class** | A named platform tier within a mode, e.g. *Track / GT*. |
| **Family** | Wheel layout plus physics module: `car`, `open` (karts, open-wheelers, 3-wheelers, oddities), `truck` (multi-axle), `moto`. |
| **Package (`.noss`)** | A player's vehicle: model, fitting data, paint and optional sound pack, identified by content hash. |
| **Fitting** | Mapping a model onto a platform: wheel anchors, orientation, scale and adapted dimensions. |
| **Fitting Bay** | In-game tool that turns a model file into a package. |
| **Track package (`.nosstrack`)** | A track, built in the editor or imported from a 3D scene or real-world data. |
| **Track Fitting** | Tagging an imported 3D scene (surfaces, walls, grid, checkpoints) so it can be driven. |
| **Style profile** | A swappable look for the world (first one: `retro_ps2`). Cars always render at full detail. |
| **Content hash** | SHA-256 identity of a package. Used for caching and online transfer. |

## 4. Functional requirements

Each requirement has an ID and a target milestone (M0–M10, see [ROADMAP](docs/ROADMAP.md)). Code, issues and commits should cite IDs.

### 4.1 Platforms and vehicle behavior (`PLT`)

Detail: [PLATFORMS.md](docs/PLATFORMS.md), [PHYSICS.md](docs/PHYSICS.md)

| ID | Requirement | M |
|---|---|---|
| PLT-01 | A vehicle's driving behavior comes only from its platform plus allowed tuning. Model geometry, materials and file size never affect performance. | M1 |
| PLT-02 | Platforms are JSON data files validated against a published schema. | M1 |
| PLT-03 | Each mode offers several platform classes. Within a class, all vehicles are mechanically identical before tuning. | M2 |
| PLT-04 | Each platform declares which setup values are tunable, with ranges. Modes and servers can narrow or lock them further. | M4 |
| PLT-05 | Platform geometry (wheelbase, track, ride height, wheel radius, collision envelope) adapts to the fitted model within the platform's ranges. A model outside the ranges is scaled to fit. | M2 |
| PLT-06 | Handling normalization keeps performance equal across adapted geometry: ≤2% deviation in the automated conformance tests. | M2 |
| PLT-07 | One sim-cade physics core for all modes. Kart mode adds an arcade modifier layer on top. | M1 / M8 |
| PLT-08 | Families: `car` (M1), `open` incl. karts and 3-wheelers (M8), `truck` multi-axle (M10), `moto` (M10+). | M1–M10+ |
| PLT-09 | Community platforms: servers can ship custom platforms, which auto-transfer. Official leaderboards and career use official platforms only. | M5 |
| PLT-10 | Mechanical damage effects are switched on or off per platform and mode. | M10 |

### 4.2 Vehicle packages and garage (`PKG`)

Detail: [VEHICLE_PACKAGE.md](docs/VEHICLE_PACKAGE.md)

| ID | Requirement | M |
|---|---|---|
| PKG-01 | Load glTF/GLB models at runtime. | M1 |
| PKG-02 | Import FBX at runtime; it is converted to GLB inside the package. | M2 |
| PKG-03 | Models with named hub nodes (FM4 convention, `hub_LF`…) are fitted automatically. For models without them, wheel anchors are placed in the Fitting Bay, or the platform's stock wheels are used. | M2 |
| PKG-04 | The Fitting Bay produces a `.noss` package. | M2 |
| PKG-05 | Store vehicle models in a garage: browse, preview, duplicate, delete. | M2 |
| PKG-06 | Hotswap: change the car model mid-session without reloading (free in practice, cruise and lobby; locked mid-race unless the server allows it). | M2 |
| PKG-07 | Recolorable paint slots (primary, secondary, tertiary) with finishes. | M2 |
| PKG-08 | Packages are validated (size, triangle count, texture size, file types) before parsing. No executable content is ever loaded. | M1 |
| PKG-09 | FM4 converter: turns a ripped FM4 car folder into a `.noss` (local use only). | M1 |
| PKG-10 | Livery editor: decals, vinyls, shareable liveries. | M10 |

### 4.3 Gamemodes (`MODE`)

Detail: [GAMEMODES.md](docs/GAMEMODES.md)

| ID | Requirement | M |
|---|---|---|
| MODE-01 | Track free-drive: single player, lap timer. | M1 |
| MODE-02 | Track racing: practice, qualifying, race, time trial with ghosts, track limits. | M4 |
| MODE-03 | Highway (No Hesi-style): cruise, score attack, point-to-point runs through traffic. | M7 |
| MODE-04 | Highway police: heat, pursuit, bust and evade. | M7 |
| MODE-05 | Kart: items, drift-boost, playable on any track, stunt tracks, battle arenas. | M8 |
| MODE-06 | Endless (Slow Roads-style): procedural infinite road, biomes, traffic, minimal UI, autodrive. | M9 |
| MODE-07 | Light career: event ladders and cosmetic unlocks. Everything is playable from the start. | M10 |

### 4.4 Local multiplayer (`LOC`)

Detail: [ARCHITECTURE.md §6](docs/ARCHITECTURE.md#6-local-players-splitscreen-and-multi-monitor)

| ID | Requirement | M |
|---|---|---|
| LOC-01 | Up to 4 local players. | M3 |
| LOC-02 | Splitscreen layouts in one window. | M3 |
| LOC-03 | Multi-monitor: each player can be put on their own monitor (own fullscreen window), and this can be mixed with splitscreen. | M3 |
| LOC-04 | Press-to-join device assignment. Each player has their own profile, bindings and car. | M3 |
| LOC-05 | Local players can join an online session together. | M5 |

### 4.5 Online multiplayer (`MP`)

Detail: [NETWORKING.md](docs/NETWORKING.md)

| ID | Requirement | M |
|---|---|---|
| MP-01 | P2P self-hosted: any player can host from the menu, and their game acts as the server. | M5 |
| MP-02 | Optional headless dedicated server built from the same code, configured by file. | M5 |
| MP-03 | Up to 16 players per session, including local splitscreen players. | M5 |
| MP-04 | Join by IP or LAN discovery. UPnP port mapping for hosts. | M5 |
| MP-05 | Car, track and platform packages auto-transfer on join and are cached by hash. A placeholder shows until the real car arrives. | M5 |
| MP-06 | Server settings: mode, tracks, classes, tuning limits, assists, package size caps, custom sounds and custom platforms on/off, collisions on/off. | M5 |
| MP-07 | Text chat. Kick and ban for hosts. | M5 |
| MP-08 | Optional self-hostable server list / lobby service. The game never depends on a central server. | M10+ |

### 4.6 Input (`INP`)

Detail: [INPUT.md](docs/INPUT.md)

| ID | Requirement | M |
|---|---|---|
| INP-01 | Keyboard, with optional mouse steering. | M1 |
| INP-02 | Controllers, with steering filters (deadzone, linearity, speed sensitivity) and rumble. | M1 |
| INP-03 | Wheel and pedals. | M1 |
| INP-04 | Shifters (H-pattern and sequential), handbrakes and button boxes. One player can combine several USB devices. | M4 |
| INP-05 | Force feedback, required on Windows and Linux, best effort on macOS. Basic in M1, full effects in M4. | M1 / M4 |
| INP-06 | Full rebinding, calibration, per-player profiles, community device presets. | M3 |
| INP-07 | Assists: ABS, TCS, stability, steering aid, auto-clutch, automatic gearbox, racing line. | M1 / M4 |

### 4.7 Track editor and map import (`EDT`)

Detail: [TRACK_EDITOR.md](docs/TRACK_EDITOR.md)

| ID | Requirement | M |
|---|---|---|
| EDT-01 | In-game editor with spline roads (width, banking, lanes, surface) and automatic curbs and barriers. | M6 |
| EDT-02 | Terrain sculpting and painting. Roads conform to the terrain. | M6 |
| EDT-03 | Prop placement and scatter. | M6 |
| EDT-04 | Snap-in stunt pieces: boost pad, ramp, item-box row, wall-ride. A loop is a stretch goal. | M8 |
| EDT-05 | Race setup: start/finish, grid, sectors, checkpoints, automatic AI racing line. | M6 |
| EDT-06 | Instant test-drive, undo/redo, autosave. | M6 |
| EDT-07 | Save and share `.nosstrack` files. They auto-transfer online. | M6 |
| EDT-08 | Import 3D scenes (glTF/FBX) as tracks using Track Fitting. | M6 |
| EDT-09 | Real-world import: OpenStreetMap roads plus elevation data become an editable track. | M10+ |
| EDT-10 | Highway junctions and on/off ramps. | M7 |

### 4.8 AI (`AI`)

| ID | Requirement | M |
|---|---|---|
| AI-01 | Racing AI for track mode that fills empty grid slots, with a skill setting. | M4 |
| AI-02 | Racing AI for kart mode that uses items. | M8 |
| AI-03 | Traffic AI for highway and endless: lanes, lane changes, varied speeds and vehicle types. | M7 |
| AI-04 | Police AI. | M7 |
| AI-05 | AI drives the same platforms with the same physics. No grip or power cheats. Kart catch-up comes only from item odds. | M4 |

### 4.9 Art, audio, cameras (`AV`)

Detail: [ART_AUDIO.md](docs/ART_AUDIO.md)

| ID | Requirement | M |
|---|---|---|
| AV-01 | The world uses the `retro_ps2` style profile by default. | M1 |
| AV-02 | Style profiles are swappable; more are added later (e.g. `modern`). | M10 |
| AV-03 | Cars always render at full detail, with distance LODs only. | M1 |
| AV-04 | Cameras: chase and cockpit (M1); hood and bumper (M2); TV/replay (M10). | M1–M10 |
| AV-05 | Built-in engine sound profiles, chosen per car and driven by the platform's RPM and load. | M2 |
| AV-06 | Custom sound packs inside `.noss`. Servers can disable them. | M5 |
| AV-07 | Cosmetic damage: scratches, dirt, broken glass and lights. | M10 |
| AV-08 | Replays and photo mode. | M10 |
| AV-09 | VR (OpenXR) cockpit view. | M10+ |
| AV-10 | UDP telemetry output for SimHub, motion rigs and dashboards. | M10 |

### 4.10 Environment (`ENV`)

| ID | Requirement | M |
|---|---|---|
| ENV-01 | Dynamic time of day. | M9 |
| ENV-02 | Dynamic weather. Wet roads lower grip through the tire model. | M9 |
| ENV-03 | Environment set per event; in endless mode it progresses continuously. | M9 |

## 5. Non-functional requirements

| ID | Requirement |
|---|---|
| NFR-01 | **OS:** Linux x86_64 (primary dev), Windows 10+ x64, macOS 12+ universal (arm64 + x86_64). Same feature set everywhere, except FFB is best effort on macOS. |
| NFR-02 | **Performance:** Steam Deck 60 fps @ 1280×800, Low, single player. 4-player splitscreen 60 fps @ 1080p on a GTX 1060 / RX 580-class GPU. |
| NFR-03 | **Physics:** fixed 120 Hz tick; vehicle sim substeps 4× (480 Hz). |
| NFR-04 | **Import:** a 200k-triangle GLB car is drivable in under 5 s on mid-range hardware. Parsing never blocks the main thread. |
| NFR-05 | **Network:** playable at ≤150 ms RTT. Content transfer never stalls gameplay. Steady-state traffic ≤64 KB/s per client. |
| NFR-06 | **In-game text** is short and direct: "Lap 2/5", "Car loaded", "Busted". |
| NFR-07 | Strings are localizable; English first. |
| NFR-08 | **Accessibility:** full rebinding, assists, colorblind-safe UI, HUD scale. |
| NFR-09 | All user data lives under Godot `user://` (standard per-OS paths). |
| NFR-10 | **Security:** untrusted content (cars, tracks, platforms, sounds) never executes code. Limits are enforced before parsing. |
| NFR-11 | No central infrastructure is required to play, host or share. |

## 6. Content and legal policy

- **Licenses:** code is GPL-3.0-or-later; original assets are CC-BY-SA 4.0. Third-party assets must be license-compatible and credited in `CREDITS.md`.
- **Ripped content never ships.** The FM4 models and GT4 textures in the sibling folders, and any other game's assets, are for local testing and visual reference only. They are never committed, never included in releases, and never part of official content. The FM4 converter sets `license: "personal-use-only"` in the packages it makes.
- **The project never hosts or distributes third-party models.** Players are responsible for what they import and share.
- **Public builds ship only original placeholder content**: a default car and test tracks.
- **Real-world map data keeps its attribution**: © OpenStreetMap contributors (ODbL), plus the DEM source.
- **All names, items and UI are original.** No trademarks from Nintendo, Forza, Gran Turismo or Assetto Corsa in the game.

## 7. Traceability to the original notes

| Original note | Covered by |
|---|---|
| Online multiplayer, P2P self-hosted | MP-01…MP-08 |
| Local splitscreen up to 4; multiple monitors if possible | LOC-01…LOC-05 |
| Store and hotswap vehicle models | PKG-05, PKG-06 |
| In-game track creator/editor; import maps | EDT-01…EDT-10 |
| Keyboard & mouse / controller / wheel, pedals, shifter | INP-01…INP-07 |
| Endless procedural drive with traffic (Slow Roads) | MODE-06, AI-03 |
| No Hesi highway weaving | MODE-03, MODE-04, AI-03, AI-04 |
| Mario Kart-style power-ups | MODE-05, AI-02, EDT-04 |
| Track racing | MODE-01, MODE-02, AI-01 |
| Platforms control performance; Linux/Windows/macOS | PLT-01…PLT-10, NFR-01 |
| Open question "What language?" | Godot 4 + GDScript + C++. See [DECISIONS.md](docs/DECISIONS.md) |
