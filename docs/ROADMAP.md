# Roadmap

The build order. Each milestone ends with something playable and lists acceptance criteria. IDs refer to [Requirements.md](../Requirements.md).

The GitHub repo is public at `git@github.com:ShadowXCC/nOSS.git` since M1.

---

## M0: Foundations

**Goal:** an empty but working project skeleton.

- Install the pinned Godot 4.x and build tools (SCons, compiler). Record everything in `INSTALLED_SOFTWARE.md`.
- `project.godot`: Forward+, Jolt, 120 Hz physics, physics interpolation, custom user dir `nOSS`.
- Folder layout from [ARCHITECTURE.md §3](ARCHITECTURE.md#3-repo-layout-created-in-m0).
- `native/`: godot-cpp and SDL3 submodules. A "hello" `noss_core` GDExtension builds on Linux.
- Test setup: gdUnit4 (headless) and doctest (native).
- `LICENSE` (GPL-3.0), an asset license note (CC-BY-SA 4.0), a `CREDITS.md` stub.
- JSON schemas: platform, package, fit, paint.

**Acceptance:**
- [x] `godot --headless` runs the test suite and it passes.
- [x] `noss_core` loads, and a GDScript call into it returns.
- [x] The game boots to a title screen reading "nOSS".

## M1: First demo, track free-drive

**Goal:** drive one of your FM4 cars on a platform, on a test track.

- `tools/fm4_to_noss.py` (PKG-09) converts the FM4 rips into the local garage.
- Runtime package loader with validation, GLB load, fit, paint and LODs (PKG-01, PKG-08).
- One platform: **Track / GT** (PLT-01, PLT-02).
- VehicleSim v1 (PLT-07):
  - suspension and Pacejka-lite tires
  - engine, auto and sequential gearbox, LSD, brakes and ABS, basic aero
  - TCS and auto-gearbox assists (INP-07)
- **Proving Ground** test track with `retro_ps2` profile v0: fog, sky, low-res textures (AV-01).
- Lap timer with sectors and best lap. Reset car (MODE-01).
- Input: keyboard, controller, and wheel + pedals with basic FFB (rack force + damper) (INP-01…03, INP-05).
  - **SDL3 coexistence spike** ([DECISIONS.md](DECISIONS.md) risk R1).
- Cameras: chase and cockpit (AV-04). One placeholder engine sound.
- Debug menu: switch between converted cars on the fly (hotswap prototype).
- Settings: graphics preset, basic bindings, units, camera shake and head movement (ACC-04).
- Every UI control gets an accessible name and focus order from the start (ACC-03 groundwork).

**Acceptance:**
- [x] ACU_NSX_97 and at least 3 other FM4 cars load as `.noss` and drive on Track / GT at 60+ fps on the dev machine (RTX 3080, Linux). *All 8 converted cars load in about 2 s; 165 fps at 1080p (vsync-capped).*
- [x] The lap timer counts valid laps. *The autopilot laps the Proving Ground in about 1:09; shortcuts and resets invalidate a lap.*
- [ ] A wheel with FFB is usable on Linux, and a Windows build boots and drives. *Deferred: wheel input and FFB are implemented but no wheel is available to test them yet. The Windows build boots and drives under Wine 10; a test on Windows itself comes later.*
- [x] A swap between two cars mid-drive keeps the car moving. *NSX → Saleen S7 at about 200 km/h kept its speed.*
- [x] Docs updated, then **the public GitHub repo is created** and the demo is tagged `v0.1.0-demo` (no ripped content).

## M2: Garage and Fitting Bay

- Fitting Bay: GLB/FBX import, orientation, wheel detection and manual anchors, scale, paint slots, eye point, engine sound pick and tuning, preview, save (PKG-02…04, PKG-07, AV-06).
- Garage UI and hotswap in session (PKG-05, PKG-06).
- Platforms: Track Touring/Prototype/Formula, Kart Medium (prototype), Highway Street (PLT-03).
- Handling normalization and the **conformance runner** (PLT-05, PLT-06).
- Hood and bumper cameras. 4 built-in engine sound profiles (AV-05). LOD generation (meshoptimizer).

**Acceptance:**
- [ ] A non-FM4 CC0 car model with no Blender prep becomes drivable in under 2 minutes in the Fitting Bay.
- [ ] Conformance passes (±2%) for every official platform across its geometry grid.

## M3: Local multiplayer

- 4 player slots, press-to-join, multi-device claiming, profiles, shared keyboard (LOC-01, LOC-04, INP-06).
- Splitscreen layouts and multi-monitor windows, which can be mixed (LOC-02, LOC-03).
- Per-viewport HUD, render scale, audio mix.
- Per-player accessibility settings and HUD scale. Hold/toggle, one-handed presets, two devices for one car (ACC-01, ACC-02, ACC-06).

**Acceptance:**
- [ ] 4 players (2 controllers, a wheel and a keyboard) drive together across two monitors (2+2 and 1+3 layouts).
- [ ] 60 fps at 1080p per monitor on the dev machine.
- [ ] The GTX 1060-class target is measured and recorded.

## M4: Track racing

- Practice, qualifying, race, time trial with ghosts. Timing, track limits, flags, results (MODE-02).
- Racing AI v1: line following, braking points, overtaking and defending, skill 0–100, same physics (AI-01, AI-05).
- Tuning UI and setups (PLT-04). All assists (INP-07).
- H-shifter, clutch, handbrake, button boxes, multi-device (INP-04). Full FFB effects (INP-05).
- Accessibility: colorblind palettes, screen reader and narration, spotter, audio cues, access assists, game speed, first-boot screen (ACC-02, ACC-03, ACC-05, ACC-07…ACC-09).

**Acceptance:**
- [ ] 1 human and 11 AI race 5 laps on Proving Ground with no AI pile-ups.
- [ ] Setups save and load.
- [ ] A ghost replays the best lap.
- [ ] Boot → race → results works with a screen reader, with controller only, and with keyboard only.

## M5: Online

- Listen server and headless dedicated server, ENet, UPnP, LAN discovery (MP-01, MP-02, MP-04).
- 16 players including splitscreen guests (MP-03, LOC-05).
- Content transfer with cache and placeholders (MP-05). Server rules and caps (MP-06). Chat, kick, ban (MP-07).
- Custom platforms over the network. Own engine sound recordings: record/import in the garage and transfer online (PLT-09, AV-06).
- Plausibility checks.

**Acceptance:**
- [ ] 16 clients, using headless bot clients for load testing, race on a dedicated server.
- [ ] A fresh client with an empty cache sees every real car within 60 s on a 50 Mbit link.
- [ ] Playable at 150 ms simulated RTT.

## M6: Track editor and 3D-scene import

- Spline roads, terrain, paint, props, race setup, automatic AI line (EDT-01…03, EDT-05).
- Test-drive, undo/redo, autosave, validation (EDT-06).
- `.nosstrack` save, load and online transfer (EDT-07).
- Track Fitting for glTF/FBX scenes (EDT-08).
- Decide on Terrain3D vs. our own terrain.

**Acceptance:**
- [ ] A 3 km circuit can be built from scratch in under 30 minutes.
- [ ] AI races it, and it transfers to a client online.
- [ ] An imported glTF track scene is fitted and raced.

## M7: Highway

- Highway map with ramps that closes into a two-way loop, so one map serves every sub-mode (EDT-10). Traffic AI, server-seeded, persistent on the loop (AI-03).
- Cruise, score attack, runs, loop (MODE-03). Police v1 with heat, pursuit, bust and evade (MODE-04, AI-04).
- Highway Super and Interceptor platforms. Original traffic vehicle set.
- "Reduce flashing" covers police lights (ACC-04).

**Acceptance:**
- [ ] 16 players plus 150 traffic cars stay in sync online at 60 fps on mid-range hardware.
- [ ] A score attack combo banks and loses as specified.
- [ ] On the loop, players going opposite ways pass each other every lap, and the same traffic cars come round again.

## M8: Kart

- `kart_arcade` layer: drift-boost, air control, self-righting (PLT-07).
- 9 items with position-based odds (MODE-05). Kart AI with items (AI-02).
- Kart classes. `open` family including karts and 3-wheelers (PLT-08).
- Stunt pieces in the editor (EDT-04). Battle mode and arenas. Cups.
- Item assist (ACC-07). "Reduce flashing" covers item effects (ACC-04).

**Acceptance:**
- [ ] An 8-player kart race (mixed human and AI) on a stunt track and on a normal track.
- [ ] A battle match runs to completion.

## M9: Endless and environment

- Procedural seeded roads, biomes, traffic, autodrive, minimal UI (MODE-06).
- Floating origin. Multiplayer convoy.
- Day/night and weather for every mode, with wet grip (ENV-01…03).

**Acceptance:**
- [ ] A 2-hour drive with no precision artifacts and stable memory.
- [ ] A seed reproduces the same road on two machines.
- [ ] Rain measurably lowers grip.

## M10+: Backlog (order to be decided)

| Item | IDs |
|---|---|
| Cosmetic and mechanical damage | AV-07, PLT-10 |
| Light career | MODE-07 |
| Livery editor | PKG-10 |
| Replays and photo mode | AV-08 |
| UDP telemetry out | AV-10 |
| VR (OpenXR) | AV-09 |
| Heavy trucks (multi-axle) | PLT-08 |
| Motorcycles | PLT-08 |
| `modern` style profile | AV-02 |
| Real-world OSM + DEM import | EDT-09 |
| Self-hostable lobby / server list | MP-08 |
| Pit stops, tire wear, fuel | — |
| Players as police | — |
| Flatpak, itch.io, Steam | — |
| Localization | NFR-07 |
