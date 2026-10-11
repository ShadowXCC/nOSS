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
- [x] A non-FM4 CC0 car model with no Blender prep becomes drivable in under 2 minutes in the Fitting Bay. *The Khronos ToyCar (CC0: one merged mesh with the wheels inside, 4 cm long, standing on a cloth) fits with no input: wheels split out and found, cloth hidden, scaled ×108. Import 1.0 s, save with LODs and thumbnail 0.7 s, drivable about 2 s after the file is picked. Clicks: Fitting Bay, Browse, the file, Save and drive. Kenney CC0 cars (GLB with an external texture, FBX, a kart) take under 1 s each. The exported Windows build (under Wine) imports and drives an FBX.*
- [x] Conformance passes (±2%) for every official platform across its geometry grid. *All six platforms, 32 configurations each (the 27-point grid plus scaled, clamped, asymmetric, ground-offset and strict fits), 7 maneuvers: worst deviation 0.59%. The harness matches Jolt within 0.4%.*

**Notes:** manual wheel anchors are set with sliders (front and rear axle, track, radius, height); clicking points on the model is not done. The kart platform runs on the core sim; its arcade layer is M8. Own engine recordings are M5.

## M3: Local multiplayer

- 4 player slots, press-to-join, multi-device claiming, profiles, shared keyboard (LOC-01, LOC-04, INP-06).
- Splitscreen layouts and multi-monitor windows, which can be mixed (LOC-02, LOC-03).
- Per-viewport HUD, render scale, audio mix.
- Per-player accessibility settings and HUD scale. Hold/toggle, one-handed presets, two devices for one car (ACC-01, ACC-02, ACC-06).

**Acceptance:**
- [x] 4 players (2 controllers, a wheel and a keyboard) drive together across two monitors (2+2 and 1+3 layouts). *Played by hand with 2 controllers and the keyboard shared by two players (left and right sides), on both monitors (2560×1440 and 1920×1080) in 2+2 and 1+3. A keyboard side stood in for the wheel; the wheel itself is deferred like the M1 wheel test (no wheel to test with). Also covered by headless tests with simulated pads (join, drop in and out, per-player pause).*
- [x] 60 fps at 1080p per monitor on the dev machine. *4 players with FM4 cars (about 200k triangles each) across both monitors, vsync off: 155–210 fps at 2560×1440 + 1920×1080, total GPU 2.5 ms. 4 players in one 1080p window: about 330 fps, 1.6 ms GPU. Physics with 4 cars: about 1 ms per tick, so it stays on the main thread (D34).*
- [x] The GTX 1060-class target is measured and recorded. *Estimated, not measured on the card (none available): 4 players at 1080p take 1.6–1.7 ms of GPU on the RTX 3080; the 3080 is about 4.7× a GTX 1060 6 GB (3DMark Time Spy graphics), so about 8 ms, well inside 16.7 ms for 60 fps. CPU on the dev PC (Ryzen 7 7700X): about 3 ms per frame. A real GTX 1060 run comes later (D60).*

**Notes:** Players share the keyboard by setting one player's keyboard to one side, rather than by pressing a key on the other side (D55). Garage and Fitting Bay test drives are single-player. Colourblind palettes, the screen reader pass and the first-boot screen stay in M4 (ACC-02, ACC-03, ACC-09).

## M4: Track racing

- Practice, qualifying, race, time trial with ghosts. Timing, track limits, flags, results (MODE-02).
- Racing AI v1: line following, braking points, overtaking and defending, skill 0–100, same physics (AI-01, AI-05).
- Tuning UI and setups (PLT-04). All assists (INP-07).
- H-shifter, clutch, handbrake, button boxes, multi-device (INP-04). Full FFB effects (INP-05).
- Accessibility: colorblind palettes, screen reader and narration, spotter, audio cues, access assists, game speed, first-boot screen (ACC-02, ACC-03, ACC-05, ACC-07…ACC-09).

**Acceptance:**
- [x] 1 human and 11 AI race 5 laps on Proving Ground with no AI pile-ups. *Played by hand on a controller: 5 laps against 11 AI, through to the results. Also simulated: `tools/race_check.sh` runs 12 cars × 5 laps headless (about 9× real time); over 12 seeds, the four track classes, skills 0–100, garage and built-in cars and three misbehaving stand-ins for the human (stalls on the grid, brakes early into Turn 1, spins on lap 2), no pile-up (3 or more cars linked by contacts within 3 s), no car stuck and every car classified.*
- [x] Setups save and load. *Tests: save, load, clamping and snapping of a tampered file, gear order, mode narrowing, and a car driving with the setup applied.*
- [x] A ghost replays the best lap. *Recorded at 30 Hz, replayed with Hermite interpolation; with the same AI driving, the next lap stays within 0.2 m of the ghost of the best one.*
- [x] Boot → race → results works with a screen reader, with controller only, and with keyboard only. *Done by hand with Orca on, with the keyboard alone and with a controller alone. Also checked automatically: `tools/a11y_check.py` walks title → Race → class → event → players → a race → results → title over AT-SPI (what Orca reads): every focusable control named, focus reported on every screen, menus inside players' views included. Tests walk the same menus keyboard-only and controller-only.*

**Notes:** time trial ghosts, setups and controller rumble were also tried by hand. Wheel, H-shifter, clutch, handbrake lever, button box and the full FFB effects are built and unit-tested with faked devices; a test on real hardware is deferred like M1's wheel test (no hardware). The Windows build was checked under Wine (a race to results). Performance with 12 cars (11 AI in garage cars, FM4 models up to about 200k triangles) at 2560×1440 fullscreen, vsync off: about 390 fps on average and 300 at worst; physics about 1.8 ms per 120 Hz tick (3.3 ms at worst), so it stays on the main thread (D34, D59); GPU 1.3 ms.

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
