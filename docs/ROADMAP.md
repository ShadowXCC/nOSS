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
- [ ] A wheel with FFB is usable on Linux, and a Windows build boots and drives. *Deferred: wheel input and FFB are implemented but no wheel is available to test them yet. The Windows build boots and drives under Wine 10, and on real Windows (a GTX 1060 PC, in the M5 LAN test). Only the wheel is still to test.*
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
- [x] 16 clients, using headless bot clients for load testing, race on a dedicated server. *`tools/net_check.py --clients 12 --quad 1 --event race --laps 3`: 12 bots and one bot with 4 splitscreen players (16 players) raced 3 laps on the dedicated server. All classified, no pile-ups, about 43 KB/s down per client (target 64), remote cars within 1–3 cm of where their owners had them. Memory: about 240 MB per bot, 230 MB for the server.*
- [x] A fresh client with an empty cache sees every real car within 60 s on a 50 Mbit link. *`--fresh --rate 50mbit` with 15 AI cars from the garage (all 11 garage cars, the 8 FM4 cars among them; personal-use cars are sent only to a bot on the same PC, with `--share-personal`): placeholders at once, previews of all in 2.5 s, every car whole in 22.7 s at 20 ms; 3.3 s and 25.0 s at 150 ms.*
- [x] Playable at 150 ms simulated RTT. *Simulated: at 150 ms with 10 ms jitter and 1% loss, 11 cars raced 2 laps, all classified, no contacts, remote cars within 2 cm (median) and 12 cm (95%). Driven by hand through `tools/net_sim.py` (75 ms each way, 5 ms jitter, 1% loss): it behaves as it should for the lag.*

**Notes:** Played by hand: two copies on one PC (`--instance`; chat, car picks, free drive, a race with AI, contacts, kick, leaving mid-race); a Windows PC with a GTX 1060 on the LAN joining a Linux host (the first run on real Windows; 60 fps the whole time); and an internet game with two friends, smooth apart from a little lag at the start. Cheat bots (`--cheat=speed|teleport|time`) are caught and flagged or kicked. Content moves on our own ARQ over unreliable ENet rather than reliable ENet, which managed about 0.4 MB/s at 150 ms against about 4 MB/s (D80). Own engine recordings are imported from files; recording from a microphone isn't done (D88). DTLS is deferred (D82). Exported builds raced together: the Linux dedicated server with a Linux client and the Windows client under Wine (one lap with an AI car, all classified).

## M6: Track editor and 3D-scene import

- Spline roads, terrain, paint, props, race setup, automatic AI line (EDT-01…03, EDT-05).
- Test-drive, undo/redo, autosave, validation (EDT-06).
- `.nosstrack` save, load and online transfer (EDT-07).
- Track Fitting for glTF/FBX scenes (EDT-08).
- Decide on Terrain3D vs. our own terrain. *Our own (D91).*

**Acceptance:**
- [x] A 3 km circuit can be built from scratch in under 30 minutes. *By hand: the owner built, saved, reloaded and edited tracks; a 13.5 km track passed the checks and was saved 6 minutes after the editor opened ("first valid save" in the log). Judged good enough for now. Headless: `tools/track_check.sh` builds a 3 km track with the editor's own commands (14 points, a hill under the road, a banked corner, gravel run-off, armco, paint, 1500 trees, grandstands, a pit building, a 16-car grid, 3 sectors, an AI pin): no check errors, saved and loaded back unchanged.*
- [x] AI races it, and it transfers to a client online. *The same track: 8 AI cars raced a lap, all finished, no pile-ups (`race_check`); a bot with an empty cache got it from the dedicated server in about 0.15 s and raced (`net_check --fresh`, 4 garage cars whole in 14 s).*
- [x] An imported glTF track scene is fitted and raced. *A circuit made from the Kenney Racing Kit (CC0, 771 m) is imported, tagged (rules, plus the kit's grey edges as curbs), clicked along, its widths measured, its start and grid set; it checks clean, saves and loads back, and 6 AI cars raced a lap on it with no resets (`track_fitting_test`, `race_check`). Test-driven from the editor (autodrive) and back.*

**Notes:** The Proving Ground is unchanged to the millimetre through every change to the track code (a golden test). Editor timings on the 3 km track: opens in 0.4 s; dragging a point updates in about 18 ms, and the ground catches up in about 0.2 s when you let go; a brush dab 1.3 ms. Four splitscreen views on it: about 165 fps, 2.4 ms GPU. The screen-reader walk covers the editor. Found and fixed on the way: road clicks past the road's end snapping back onto it, editor picks missing the view's world, a lost last ack stalling transfers, AI cars taking off over crests, and the acceleration check flagging landings. From the owner's hands-on run: the Road tool's width, banking and lane fields and the Props tool's turn and scale fields failed (their callbacks took the value as the key; a test now changes every field of every tool), and menu presses that change screens left errors behind (D105). The screen-reader walk needs the game's window to keep the keyboard for its 5 minutes; it says so when another window takes it.

## M7: Highway

- Highway map with ramps that closes into a two-way loop, so one map serves every sub-mode (EDT-10). Traffic AI, server-seeded, persistent on the loop (AI-03).
- Cruise, score attack, runs, loop (MODE-03). Police v1 with heat, pursuit, bust and evade (MODE-04, AI-04).
- Highway Super and Interceptor platforms. Original traffic vehicle set.
- "Reduce flashing" covers police lights (ACC-04).

**Acceptance:**
- [x] 16 players plus 150 traffic cars stay in sync online at 60 fps on mid-range hardware. *In sync, on one PC: `tools/net_check.py --event highway --clients 12 --quad 1 --traffic 150 --police --duration 600` (12 bots and one with 4 players, police on, 10 minutes on the dedicated server): 0 checksum disagreements in about 600 checks per bot, 22–39 KB/s down per bot (54 KB/s for the 4-player bot; target 64), remote players within 0.03–0.06 m and traffic within 0.06–0.13 m (95%), lane sims at 18–20 ticks a second, no plausibility flags, about 1100 promotions, 45 pursuits and 59 roadblocks. net_check still counts 2 three-car pile-ups (two light touches between bots pulling off the shoulder together at the start, and a police ram). At 150 ms with 1% loss (4 bots, 150 cars): 0 disagreements; a game put out of step resyncs once. Exported builds: the Linux dedicated server on a highway with police, an exported Linux bot and the Windows export (under Wine) as a bot: 0 disagreements. The GTX 1060 PC (i7-7700) joined a 16-player run with police at 35–41 fps: physics at 120 Hz couldn't keep up. A client's script time was cut from about 450 to 280 ms a second on the dev PC (D126). Measured again on the GTX 1060 PC, joining 15 bot players with 150 traffic cars and police on the LAN (`--perf-log`, 3½ minutes): 59.7 fps on average at the monitor's 60 Hz, p99 frames 16.7–16.9 ms after the first half-minute (31 ms while loading), the slowest physics step about 9 ms a second on average. Four players in splitscreen on the dev PC (Ryzen 7 7700X, RTX 3080): 164 fps (the monitor's 165 Hz) with 150 and with 400 traffic cars, all four views about 2 ms of GPU, p99 frames 6.1–7.2 ms. The screen-reader walk covers the highway menus, the Ramps tool and a highway pause menu.*
- [x] A score attack combo banks and loses as specified. *`highway_score_test`: the player's car rolls past lane cars placed beside it at 180 km/h: a near miss scores 100 × 1.5, a close one 200 × 1.5 with the combo up to ×1.25 (563 unbanked), five quiet seconds bank it, and a knock into a slow car loses the next chain. `score_attack_test` covers the table (speed steps, nothing under 120 km/h, splits, the wrong way).*
- [x] On the loop, players going opposite ways pass each other every lap, and the same traffic cars come round again. *Offline (`tools/highway_check.sh --scenario=loop` on the Lumen Ring, also at 1.6 × the limit): 2–3 meetings a lap, 91–94% of the traffic met on the other carriageway one lap met again the next. Online (`net_check --clients 2 --dirs opposite --speed-factor 1.6 --duration 700`): 3 and 2 meetings on the two whole laps, 91% of the traffic came round again, both players' laps counted by the server; with 16 players and police, 2 meetings a lap and 88–92%.*

**Notes:** The 10-minute run with police first fell behind real time: the server's scripts took 600+ ms a second (a 120 Hz tick has 8.3 ms), pooled police rejoined the road by themselves, the session-wide traffic cap stopped promotions at 24 for 16 players, and the relay starved some cars in a crowd. Fixed (D110, D111, D125); the server now takes about 340 ms a second and keeps time. Also found on the way: remote players' laps the other way round never counted on the server, two games on one PC fetching the same file clashed over its part file, the chase camera's slerp failed when a car was turned round, a player could spawn on a speed trap's unit, bots and autodrive had no way out when stuck or upset, and they queued into closed lanes at roadblocks. ENet's packet throttle fell to 1/32 once more for an exported Linux bot next to a Windows bot under Wine (M5's open question; the traffic stayed in step). By hand (the owner): driving the highway felt good; exits, entries and flyovers built in the editor worked; score attack's points, thresholds and HUD felt right; Reduce flashing calmed the police lights.

## M8: Kart

- `kart_arcade` layer: drift-boost, air control, self-righting (PLT-07). *Native, on the same core (D130–D133): drift with three tiers, boosts and pads, air control and tricks, righting, bouncy walls, stick gravity for wall-rides and loops, spin-outs; the classes pass conformance with it on.*
- 9 items with position-based odds (MODE-05). Kart AI with items (AI-02). *Nitro, Nitro ×3, Oil Slick, Bolt, Seeker, Leader Hunter, Shield, EMP, Magnet (D139, D140); KartAI drifts, takes loops from their lanes and uses items (D143).*
- Kart classes. `open` family including karts and 3-wheelers (PLT-08). *Light, Medium, Heavy and the nOSS Kart (D134). 3-wheelers are deferred.*
- Stunt pieces in the editor (EDT-04). Battle mode and arenas. Cups. *Boost pads, item rows, jumps, wall-rides, loops; arenas; Battle (two rules); cups with the Spark Cup built in and your own (D136–D138, D144, D145). Five new tracks (D147).*
- Item assist (ACC-07). "Reduce flashing" covers item effects (ACC-04). *D146.*
- *Also: kart races and battles online (protocol 5, D141, D142).*

**Acceptance:**
- [x] An 8-player kart race (mixed human and AI) on a stunt track and on a normal track. *Online at 150 ms with 10 ms jitter and 1% loss, 4 bot players and 4 AI, 3 laps (`net_check --event kart --clients 4 --ai 4 --laps 3`): on Gearworks (stunt: pads, a jump, the wall-ride and the loop) all 8 classified, the bots' Bolts and Slicks within 0.03–0.04 m of the server's (95%), Seekers within 0.9 m, 9 hits validated and none turned down, 14–16 KB/s down per bot, no plausibility flags; on Marble Mile (plain) all 8 classified, items within 0.11–0.35 m, no hit report turned down, no flags or pile-ups. (The first runs flagged a bot on the wall-ride and counted two 3-kart pile-ups: karts now have their own grace on stick surfaces, and kart_check's pile-up rule of 4.) Offline (`kart_check`, 8 AI karts, 12 seeds a track): Gearworks 9 of 12 and Marble Mile 8 of 12 at first, the rest failing on two karts jammed against a barrier, one loop taken slowly after a crash, 3 tows or a 4-kart pile-up; the jam is fixed (D143), the checks' loop rule allows one failure, and the Marble Mile seeds that failed pass when run again (the AI isn't deterministic run to run).*
- [x] A battle match runs to completion. *Online at 150 ms, 4 bots and 4 AI on the Crate Yard: last one standing ended with a winner (10 hits validated, none turned down; items within 0.17 m); most hits ran its 3 minutes (34 hits validated, 3 contested by two karts at once). With 3 bots and an AI kart (`run_tests.sh`): items within 0.01–0.02 m once a Bolt isn't compared across a bounce it took between two snapshots. Offline, `kart_check --battle` (8 AI) ends under both rules on the arena fixture, the Crate Yard and the Dust Bowl, lives lost matching hits taken.*

**Notes:** The plan's class tops (92/100/109 km/h) gave a 13% lap spread, since boosts cap at 1.25× top; they're now within 1% of each other and the spread is 1.1–1.6% (D134). Steering by the angle to a target wove karts out of the loop into spins; drifts into a 16 m hairpin ran wide; a wall-ride on a corner's inside threw karts over it, and without a lip and narrowing ends karts climbed over or ran off its end (D137, D143). Online, items compared by the clock looked a tick behind; item ages fixed it (D141); the honest bots were flagged in loops, on landings, on wall-rides and in bumps until karts got their own checks (D142). Also found: a reference cycle between a track and its kart and arena layouts (never freed), a race between car-loading threads in the schema cache (a bot crashed), battle karts pinned by EMP after EMP (D144). Eight AI finish a last-one-standing battle in 1–1.5 minutes; the length is for the owner to judge. Performance (dev PC, headless): the kart AI first projected every item box onto the road at each plan, taking 8 ms of physics a frame (95%) with 8 karts against 1.7 ms for 8 GT cars; with boxes and Slicks placed once it's 2.5 ms (16 karts: 3.6 ms, GT 3.1 ms; 12 on Gearworks 2.8 ms; a 12-kart battle 2.7 ms). Cars without the kart layer are untouched (its null path is pinned by a doctest; the traffic bench's lite cars 14.0 µs each, as in M7). Exports: Linux, Windows and the dedicated server; the exported server ran a kart race and battle rotation with exported Linux bots and the Windows export under Wine as a bot: every hit validated, no flags. Still to measure: splitscreen karts on the GTX 1060 PC. The screen-reader walk covers the Kart menus, the cup builder and the Stunts tool (names checked; its focus checks need the game's window to have the keyboard). By hand (the owner): drift, the class differences, items, the HUD and Reduce flashing, building a stunt track, both battle rules, the menus and the Spark Cup. From those checks: each kart picks its own class, online too (D149); cars come down to kart size (D150); most hits has a target and a table on the HUD (D151); run-off over flat ground no longer flickers through the grass (Gearworks' is concrete now). Still to do: a LAN game with the GTX 1060 PC.

## M9: Endless and environment

- Procedural seeded roads, biomes, traffic, autodrive, minimal UI (MODE-06). *An integer road generator from a seed (D152): seven biomes with their own bends, hills, props, sounds and weather; bridges, guard rails, chevrons and the sea (D156). Traffic from a schedule worked out from the seed and the clock, physics cars near players (D158). The autodrive (EndlessDriver, the **O** key), a hidden HUD, ambient music made from the seed or your own files, road codes to share (D157). Under **Solo Drive** on the title, with every other way to drive on one PC (D160).*
- Floating origin. Multiplayer convoy. *A floating origin snapped to 1500 m (D155); online every game keeps its own, with world positions on the wire (protocol 6), Join, one owner per traffic car and the road checked against the server's (D159).*
- Day/night and weather for every mode, with wet grip (ENV-01…03). *Time of day, how fast it runs and the weather (clear, cloudy, rain, storm, fog, snow, changing) on every event menu and the track editor's Race tool; the sun and moon, stars, headlights and beams, rain and snow round each camera, spray, lightning (a soft pulse with Reduce flashing), rain, wind and thunder; wet and snowy grip per car (D153).*

**Acceptance:**
- [x] A 2-hour drive with no precision artifacts and stable memory. *`tools/endless_check.sh --minutes=120 --traffic=normal` (the autodrive in normal traffic, headless at 120 Hz, about 15× real time): 162 km, 83 origin moves; the car's step-to-step error against its speed 0.0325 mm (RMS) in the first 10 minutes and 0.0331 mm in the last 10, the worst speed change at a move 0.049 m/s; static memory 245.7 MB at 10 minutes and 247.0 MB at the end (3.0 MB/h), and the road chunks, tiles and far tiles built less those freed are exactly those still in use; frames 0.58 ms on average, p99 1.13 ms. The negative control (origin held still, 30 minutes) fails: 0.25 mm in the first 10 minutes and 0.75 mm in the last, 37 km from the origin. Drawn in a window for 60 minutes (85 km, 44 moves): static memory 2.6 MB/h and video memory 0.2 MB/h after 10 minutes, textures 220.8 → 221.8 MB, frames 6.1 ms (p99 6.4 ms). `run_tests.sh` drives 10 minutes.*
- [x] A seed reproduces the same road on two machines. *`tools/endless_determinism.sh`: the exported Linux build and the Windows build (under Wine) print the same checksums for 200 km of road and of the ground along it, on four seeds and start biomes. Online, every road chunk a bot made matched the server's: 41–43 chunks in a 3-bot convoy (one joining late), and 25 with the exported Linux server, an exported Linux bot and the Windows export as a bot.*
- [x] Rain measurably lowers grip. *On the conformance harness, every class's reference car fully wet (`tools/run_conformance.sh`, all 16 classes): cornering grip 0.73–0.78× dry, braking 1.10–1.32× the distance (cars 1.12–1.32×, karts 1.10×), laps 1.06–1.15× as long; under snow, grip 0.41–0.49× and braking 1.64–2.13×. Every class still passes its dry conformance unchanged. In the game, the same 6-car, 3-lap AI race on the Proving Ground (GT): best lap 69.31 s dry and 79.23 s in the rain (+14.3%), race 213.3 s and 244.1 s (+14.4%), no contacts in the rain. `run_tests.sh` races a lap in the rain.*

**Notes:** A 2-hour run first crashed after 15 minutes: Godot's headless stand-in renderer has a mesh store that isn't thread-safe, and two worker threads making meshes at once corrupted it; headless, meshes are now made on the main thread (D156). The planned sector-plus-float network positions became world millimetres wrapped to 32 bits, so car states keep their size and tracks are bit for bit the same (D159). Remote cars outside a game's stretch of road made it search the whole road every tick; they're now left unplaced there. PHYSICS.md's "wet 0.75" for painted lines was the table's slip; its formula gives 0.7125 (D153). Online convoy (`net_check.py --event endless --clients 3 --late 40`): remote cars within 0.01 m (95%), 0.05 m at 150 ms with 1% loss; every bot's origin moved and every bot showed traffic another game drove (13–22 handovers); the late bot started 40 m behind the leader; 4–8 KB/s down. Exports: Linux, Windows and the dedicated server. The screen-reader walk covers Solo Drive and the endless menus. The full `run_tests.sh` (576 GDScript tests, 105 native) passes apart from the known engine check (it can't compile under `-s` since M7) and the highway online flake; once, the endless convoy's late bot saw ENet's throttle fall to 1/32 (M5's open question; two reruns were clean). Not done: highway traffic density by time of day (the lane sim's population is fixed). By hand (the owner): a long endless drive (biomes, night, a storm, snow, the HUD, a road code on a second PC), splitscreen with both spread rules, rain and night in a race and on the Lumen Ring, Reduce flashing in a storm, your own music files and the Solo Drive menu by controller all worked. A LAN convoy with the GTX 1060 PC kept a steady frame rate with the same road and traffic on both, but the two cars started on one spot and one landed on the other: each game placed its own first player first. Players now line up by their place in the roster, online cars start ghosted for 3 s, and `net_check --event endless` fails if two bots start within 10 m of each other (the old code: 0 m and 6 contacts; now 18 m apart and none). Checked again on the LAN: both cars start in single file.

## Mini Games: Sumo Wrestling

*A new Solo Drive category for short matches that aren't races, and the first game in it (D162-D166).*

- **Sumo Wrestling** (`game/modes/sumo/`, `game/world/arena/`, D162-D167): 1-3 floating platforms stacked over lava or acid, each lower one wider than the one above. The top one shrinks from the green light, a lower one once a car lands on it; the last car not in the goo wins. Three shrink styles (smooth, crumbling, stepped), a sudden-death pillar, and a rechargeable ram boost on its own action. One class, **Sumo**, that any model may mount. The arena is generated from the match settings, so there is no track file, nothing to download and nothing of it on the wire.
- **Mini Games** on Solo Drive, built to take more games (a Drag Strip is next).
- Online (protocol 7): the server shrinks the platforms and rules on the goo.
- Also fixed: a Kart Battle no longer shows lap times or a delta bar, which it has no use for (Changes.md).

**Acceptance:**
- [x] A sumo match runs to a single winner on every shrink style and every number of platforms. *`tools/sumo_check.sh` (6 AI cars, 60 s a platform): all 54 of 1, 2 and 3 platforms x smooth, crumbling and stepped x with and without sudden death x three seeds. Each ends with exactly one car still up, no platform shrinking before a car has stood on it, no car stuck, and no two cars out on the same tick. A 1-platform smooth match runs about 45 s, a 3-platform one about 75-110 s. The check's own work costs 24-30 µs a tick.*
- [x] A car knocked off a platform lands on the one below. *The check counts every fall that had a platform still standing beneath it and fails if more than a third miss. With 8 m radius steps a car thrown off by a whole ring going at once cleared the platform below; the steps are 12 m (24/36/48 m) and the rate now stays under the limit on every style (D163).*
- [x] A sumo match online. *`tools/net_check.py --event sumo --clients 3 --ai 2 --tiers 2 --platform-secs 40 --rtt 150 --jitter 10 --loss 1`: 3 bots and 2 AI, all 5 classified with staggered times out (9.0-37.1 s) and one winner; remote cars within 0.17-0.19 m (95%), 10.7-10.8 KB/s down per bot, no plausibility flags. One car went in from the top platform without reaching the one below, which the rules allow (D163). With one platform, the same run ends with every car's time out recorded and the last one standing declared. The pile-up rule is off for sumo as it is for a battle: shoving is the whole match.*

**Notes:** Whether a car is in the goo is a height test, not the hazard's Area3D: an area watches the default collision layer rather than the one cars are on, and more to the point a dedicated server holds every player's car as a kinematic remote that the physics never really touches, so only a height test rules the same way everywhere. Online, the server's word kept being undone: NetRacer takes a car's `out` from the states its owner's game sends, so one still in flight when the server put the car out cleared the flag again, and with no time limit to fall back on the match simply never ended (a battle's timer hides the same race). The authority now re-asserts it each tick, and a remote car is sunk by its own game rather than here. The first build had the platforms armed by any car passing through their height band, so the lower ones were half gone before anyone reached them and every fall went straight into the goo; a platform now only starts when a car is within 2.5 m of its floor and under 2 m/s vertically (D162). The goo's Area3D watched the default collision layer, not the one cars are on, so nothing ever went out. Sudden death deadlocked with three cars circling a 6 m pillar: the AI counted every spot on it as "near the edge" and never hunted, so the edge term is now capped at part of the platform's radius (D165), and the pillar gives way after 25 s so a match always ends. A stepped or crumbling platform drops two cars in on one tick every time a whole ring goes under both, which "last one in wins" cannot separate: they are now ranked by how deep each was when the authority saw them (D167), since that is what the clock is too coarse to measure. The class first failed its weather conformance (braking wet 1.00x, lap wet 1.01x): its brakes were too weak to lock the wheels and its grip too high ever to bind, so wet and dry came out the same; with stronger brakes, less grip and a higher top it brakes wet 1.29x and laps wet 1.07x, in line with every other class. Drawn in a window the arena needed three fixes no headless check could catch: the pit wall was wound the other way from the rest of the builder and so was culled from inside; the goo's noise sampled less than one cell across the whole pool and came out flat near-black; and the pool was far enough under a wide platform that its own rim hid it from any camera on it, so the pit is wider and the goo shallower. The `--sumo` dev flag itself did nothing at first: boot.gd keeps its own list of the flags that start an event, and sumo was not on it. Still to do by hand (the owner): the lava and acid in a window, splitscreen, and a LAN match with the GTX 1060 PC.

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
