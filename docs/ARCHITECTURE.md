# Architecture

How nOSS is put together: engine, languages, code layout and the main runtime systems. Requirement IDs refer to [Requirements.md](../Requirements.md).

---

## 1. Engine: Godot 4

**Godot 4**, on the latest stable release ≥ 4.5. The exact version is pinned in M0 and recorded in [DECISIONS.md](DECISIONS.md).

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
| Native core: `noss_core` | **C++20** GDExtension (godot-cpp) | Vehicle sim (tires, suspension, drivetrain, aero), wheel input and FFB (SDL3), package validation and hashing, traffic bulk update, procedural road and terrain mesh generation, LOD generation (meshoptimizer) |
| Tools | **Python 3** (stdlib only) | `fm4_to_noss.py`, packers, conformance report tools |

**Rule:** start in GDScript and move code to C++ once profiling shows it's hot, or when it needs a native library. The vehicle sim is C++ from day one.

**Build:** SCons, matching godot-cpp's primary build. CMake is acceptable if it is clearly better at M0. Third-party code is pulled in as git submodules under `native/thirdparty/`.

## 3. Repo layout (created in M0)

```
nOSS/
├─ project.godot
├─ game/                  GDScript + scenes
│  ├─ app/                boot, settings, save paths, style profiles
│  ├─ players/            local player slots, device join, viewports and windows
│  ├─ vehicles/           platform loader, package loader, fitting, visual rig, cameras
│  ├─ modes/              common/, track/, kart/, highway/, endless/
│  ├─ world/              track runtime, terrain, procedural gen, weather, time of day
│  ├─ ai/                 racing, traffic, police
│  ├─ net/                session, replication, content transfer
│  ├─ editor/             track editor, Fitting Bay, Track Fitting
│  ├─ audio/              engine sound player, SFX, music
│  └─ ui/                 menus, HUD, themes
├─ native/                C++ GDExtension "noss_core"
│  ├─ src/vehicle/  src/input/  src/package/  src/traffic/  src/mesh/
│  ├─ thirdparty/         godot-cpp, SDL3, meshoptimizer (submodules)
│  └─ SConstruct
├─ data/
│  ├─ platforms/<mode>/<class>.platform.json   official platforms
│  ├─ modes/<mode>.mode.json                   mode rules and overrides
│  ├─ items/                                   kart items
│  ├─ sound_profiles/                          built-in engine sounds
│  ├─ input_presets/                           device presets
│  └─ schemas/                                 JSON schemas (platform, package, track, sound)
├─ content/               original CC-BY-SA assets: default car, test tracks, props, textures
├─ tools/                 fm4_to_noss.py, conformance runner, packers
├─ tests/                 gdUnit4 tests, native doctest tests, conformance scenes
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

*Requirements: LOC-01…LOC-05.*

- **PlayerSlot (1–4):** holds the player's devices, profile, chosen car and camera.
- **ViewManager:** gives each slot a `SubViewport` showing the shared `World3D`, with its own camera and HUD.
- **Layouts inside one window:** 1 = full screen. 2 = horizontal or vertical split (player's choice). 3 = one wide panel plus two below, or 2×2 with a map in the spare quarter. 4 = 2×2.
- **Multi-monitor:** each slot can be assigned a monitor, which creates a borderless fullscreen `Window` (`current_screen = n`). Each window can hold 1–4 slots in its own split layout, so 1+3 or 2+2 across two monitors works.
- **Performance:** each viewport has its own render scale, and quality steps down automatically to hold the frame rate.
- **Audio:** each viewport's camera has a listener. The mix is normalized, and other players' engines are attenuated. A "P1 focus" option is available.
- **Menus:** shared menus show on the primary window; in-race HUDs are per viewport.

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

Endless mode and large real-world maps go far beyond single-precision range.

- When the local player passes **2 km** from the origin, the world shifts back to the origin: physics bodies, nodes, particles, audio.
- With several local players, the origin follows the players' centroid. Players who drift far apart are kept within one shared section of road (see [GAMEMODES.md](GAMEMODES.md)).
- **Network positions** are sent as `(sector_x, sector_z)` int32 plus a float32 local offset, so every client can rebase on its own.

## 9. Threading

| Thread | Work |
|---|---|
| Main | Game logic, UI, scene tree, render submission |
| Physics | Godot physics plus `VehicleSim` (Godot's physics-thread option, decided in M1) |
| Worker pool | Package validation, import and LOD generation; procedural chunk and terrain mesh builds; content transfer decode |
| Native FFB | ~500 Hz loop that interpolates the latest FFB target and updates SDL3 haptic effects |

## 10. Data and save locations

*Requirement: NFR-09.*

`user://` maps to the standard per-OS location. A custom user dir is enabled, so the folder is named `nOSS`:
- Linux: `~/.local/share/nOSS`
- Windows: `%APPDATA%\nOSS`
- macOS: `~/Library/Application Support/nOSS`

```
user://
├─ settings.cfg
├─ profiles/<player>.json      bindings, assists, FFB, preferred cameras
├─ garage/<id>.noss            player car packages
├─ tracks/<id>.nosstrack       player tracks (+ .autosave/)
├─ platforms/                  custom and downloaded platforms
├─ setups/<platform>/<track>.json
├─ replays/
├─ cache/<sha256>/             unpacked and imported content (own and downloaded)
└─ logs/
```

**Security rule:** Godot resource formats (`.tscn`, `.scn`, `.tres`, `.res`) are never loaded from packages or the network, because they can embed scripts. The import cache may hold `.scn` files only if this machine generated them.

## 11. Testing

- **GDScript:** gdUnit4, run headless (`godot --headless`).
- **Native:** doctest unit tests for tire, suspension and drivetrain math.
- **Platform conformance:** headless scenes drive standard maneuvers across each platform's geometry range ([PLATFORMS.md §5](PLATFORMS.md#5-conformance-tests)).
- **Network:** headless bot clients load-test 16-player sessions.
- **CI (after the GitHub repo exists):** GitHub Actions builds `noss_core` for Linux, Windows and macOS, runs all tests, and exports builds.

## 12. Build and distribution

*Requirement: NFR-01.*

- Godot export templates: Linux x86_64, Windows x86_64, macOS universal.
- **Dedicated server:** Linux headless export (`dedicated_server` feature tag), see [NETWORKING.md](NETWORKING.md).
- Releases on GitHub first. itch.io, Flatpak and Steam are later options.
- macOS signing and notarization need an Apple developer account. Until then, builds ship unsigned with instructions (open question in [DECISIONS.md](DECISIONS.md)).
