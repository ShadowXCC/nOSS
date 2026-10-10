# Decisions, risks, open questions

Append-only log. To change a decision, add a new row that supersedes the old one rather than editing it.

---

## Decision log

| # | Date | Question | Decision | Why |
|---|---|---|---|---|
| D1 | 2026-10-09 | Engine / language | **Godot 4** (≥4.5, pinned in M0). GDScript for gameplay, UI and editors. **C++ GDExtension** (`noss_core`) for the vehicle sim, FFB and hot loops. | Open-source license (MIT) fits nOSS. Runtime glTF/FBX loading, Jolt, multi-window, ENet, a strong UI toolkit, exports for all 3 OSes. Fastest path to a demo. Bevy: no editor, unstable API. Custom engine: years of work. Comparison in [ARCHITECTURE.md §1](ARCHITECTURE.md#1-engine-godot-4). |
| D2 | 2026-10-09 | Project goal | Public open-source project, free to play | Owner's choice |
| D3 | 2026-10-09 | License | **GPL-3.0-or-later** code, **CC-BY-SA 4.0** assets | Copyleft keeps forks open. Common for OSS games (SuperTuxKart, Speed Dreams). |
| D4 | 2026-10-09 | Physics fidelity | Sim-cade core, one model, platform-parameterized. Kart is an arcade layer on top. | Good on all inputs. One codebase. |
| D5 | 2026-10-09 | Platform structure | Several classes per mode. Limited tuning, with knobs set by the platform and narrowed by mode and server. | Fairness within a class, variety across classes |
| D6 | 2026-10-09 | Model/platform size mismatch | Platform adapts within its ranges. Handling normalization keeps performance equal. Scaled outside the ranges. `strict` server option. | Cars look right without giving anyone an advantage ([PLATFORMS.md §4](PLATFORMS.md#4-fitting-and-handling-normalization)) |
| D7 | 2026-10-09 | Vehicle families | Cars/light trucks, heavy trucks/buses, karts/open-wheel/oddities, motorcycles (all planned) | Owner's choice. Motorcycles and multi-axle trucks come last (M10+). |
| D8 | 2026-10-09 | Model prep | Tagged (hub nodes) or untagged both work, via the in-game Fitting Bay | Lowest barrier. FM4 rips already follow the tagged convention. |
| D9 | 2026-10-09 | Online hosting | "P2P self-hosted" = player-hosted listen server, plus an optional dedicated headless build of the same code. No central infrastructure. | Owner's wording. A single authority is needed for items, police and traffic. |
| D10 | 2026-10-09 | Custom car visibility online | Auto-transfer on join, cached by content hash, placeholder until loaded | Everyone sees real cars. No workshop to host. |
| D11 | 2026-10-09 | Lobby size | Up to 16, including splitscreen guests | Good race grids. Manageable netcode. |
| D12 | 2026-10-09 | First demo | Track free-drive with an FM4 car as `.noss`, one platform, one test track | Proves import, fitting, physics and input first |
| D13 | 2026-10-09 | Kart mode | Items on any track, plus stunt tracks with editor pieces | Owner's choice |
| D14 | 2026-10-09 | Highway mode | Score attack, cruise, point-to-point runs, police | Owner's choice (all four) |
| D15 | 2026-10-09 | Track editor | Spline roads + terrain + snap-in stunt pieces | Realistic roads and kart fun from one tool |
| D16 | 2026-10-09 | Map import | (1) glTF/FBX scenes with Track Fitting. (2) OpenStreetMap + elevation. | Owner's choice. Other games' track formats excluded (legal risk, format work). |
| D17 | 2026-10-09 | Art direction | `retro_ps2` world, built as the first of several swappable style profiles. **Cars always at full detail.** | Owner: the world is retro for now and should eventually support different quality levels and styles, since the game is about customization |
| D18 | 2026-10-09 | Damage | Cosmetic on all models. Mechanical effects toggled per platform and mode. | Works with any model. Fairness stays configurable. |
| D19 | 2026-10-09 | Engine sound | Built-in profiles plus custom sound packs in `.noss` (auto-transferred, server can disable) | Personal expression without affecting performance |
| D20 | 2026-10-09 | Progression | Sandbox plus light career (cosmetic unlocks) | Everything open from the start |
| D21 | 2026-10-09 | AI | Racing AI (track, kart) plus traffic AI (highway, endless) | Owner's choice |
| D22 | 2026-10-09 | Min spec | Steam Deck / iGPU single player. Mid-range GPU for 4P splitscreen. | Retro world makes this realistic |
| D23 | 2026-10-09 | Environment | Dynamic day/night and weather, wet grip through the tire model | Owner's choice |
| D24 | 2026-10-09 | Wheel FFB | Required on Windows and Linux through SDL3 haptics. Best effort on macOS. | macOS wheel FFB support is poor industry-wide |
| D25 | 2026-10-09 | Community platforms | Platforms are data. Servers can ship custom ones. Official leaderboards and career use `official.*` only. | Moddability without diluting official results |
| D26 | 2026-10-09 | Later extras | Livery editor, replays/photo, VR (OpenXR), UDP telemetry | Owner's choice (M10+) |
| D27 | 2026-10-09 | Ripped reference content | FM4 models and GT4 textures are local-only, for testing and reference. Never committed or shipped. | Copyright. GPL/CC-BY-SA project. |
| D28 | 2026-10-09 | Engine sound customization (extends D19) | Players tune a built-in profile or add their own recordings. Either way it is saved in the car's `.noss` and travels with it. Servers can turn off own recordings only. | Owner's choice. Tuned built-ins are tiny and use shipped samples, so they're always safe to allow. |
| D29 | 2026-10-09 | Highway loop (extends D14) | Add a **Loop** sub-mode: a closed two-way highway with persistent traffic. The first highway map is a loop with ramps, so it serves every sub-mode. | Owner's choice. Meeting the same players and cars again makes the world feel lived-in. |
| D30 | 2026-10-09 | Accessibility | Own doc and `ACC` requirements. Settings are per player. Servers can't restrict what only changes what you see, hear or press. Access assists follow the normal assist rules. | Owner's choice. Fairness rules should only touch what changes driving. |
| D31 | 2026-10-09 | Godot version (Q1) | **Godot 4.7.2-stable**, standard (non-.NET) build. Native code targets the 4.7 API (godot-cpp **10.0.0**, `api_version=4.7`). | Latest stable at M0. godot-cpp 10 is versioned separately from Godot and builds against a chosen API level. |
| D32 | 2026-10-09 | Native build system (Q2) | **SCons** | godot-cpp's primary build. The project is small, and CMake brings no clear win. |
| D33 | 2026-10-09 | Dev tools | Project-local and pinned: Godot in `.tools/godot/` (self-contained mode), SCons and jsonschema in `.venv/`, all set up by `tools/setup_dev.sh`. Third-party code is pinned by submodule tag. | Nothing installed system-wide, so it's easy to remove. Everyone builds with the same versions. |
| D34 | 2026-10-10 | Physics thread (Q3) | **Main thread** (Godot's default) for M1. | One player and one car run far above budget (165 fps, vsync-capped, on the dev machine). Revisit in M3 if 4 players or AI need it. |
| D35 | 2026-10-10 | SDL3 for wheels (R1 spike) | `noss_core` **loads SDL3 at runtime** (no link-time dependency) and only opens **non-gamepad** devices, with HIDAPI off. Godot keeps gamepads. Linux uses the system `libSDL3.so.0`; Windows ships the official `SDL3.dll` next to the game. Without SDL3, wheels are off and everything else works. | No CMake build of SDL needed. Godot doesn't export its own SDL symbols, so the two copies can't clash, and splitting devices by class means they never fight over one. Spike result in [INPUT.md §2](INPUT.md#2-input-sources). |
| D36 | 2026-10-10 | Wheel contact in VehicleSim v1 | One **ray per wheel** from above the top of travel, with the compression rate taken along the ground normal. Shape casts come later. | Simple and robust on the flat Proving Ground. Curb edges are a known v1 roughness. |
| D37 | 2026-10-10 | Track file before the editor | Interim `noss.track/0` JSON: centreline control points (closed centripetal Catmull-Rom), width, start, sectors, a few set pieces. The builder makes road, curbs, terrain, barriers and scenery at load time. | Enough for the Proving Ground until `.nosstrack` arrives with the editor in M6. |
| D38 | 2026-10-10 | Platform `brakes.max_torque_nm` | Total brake torque at full pedal, split by `bias_front`. Track / GT raised to 6000 Nm. | 3400 Nm total only gave 0.8 g. 6000 Nm can lock the tires, so ABS matters. |
| D39 | 2026-10-10 | FM4 eye point | Seat's lowest point + 0.75 m, capped 0.17 m below the roof, 0.30 m forward of the seat back, in line with the steering wheel. The driver's side comes from the steering wheel's position (`--rhd`/`--lhd` override). | The spec's "seatL + 0.65 m" put the eye above the roof (FM4 seat pivots are mid-seat). Checked in-car on the NSX. |
| D40 | 2026-10-10 | Texture limit | The 256 MB package limit counts decoded RGBA pixels of all LODs, **without** mipmaps. | Matches "decoded texture memory". With mipmaps counted, the Mustang (220 MB decoded) was rejected. |
| D41 | 2026-10-10 | Import cache | Runtime load step 6 (machine-generated `.scn` cache) deferred. | A 200k-triangle FM4 car loads in about 2 s with GPU uploads, well under NFR-04's 5 s. |
| D42 | 2026-10-10 | Windows builds | Cross-compiled on Linux with **LLVM MinGW** (pinned, project-local), exported with Godot's Windows template. Tested under Wine 10 with Vulkan. | No Windows machine needed for CI-style builds. The DLL only imports KERNEL32 and the Universal CRT. |
| D43 | 2026-10-10 | Conformance runner (PLT-06) | **Native maneuvers, GDScript orchestration.** GDScript loads platforms and fits synthetic `fit.json`s with the game's own `PlatformLoader` and `Fitting`; `NossConformance.run_batch` runs the maneuvers on a flat-ground harness on all threads. The scripted driver follows paths with the CoM and commands curvature through the reference wheelbase. Metrics are interpolated between ticks; pass = ±2% of the reference config (yaw rise time: or 4 ms). An engine check compares the harness with Jolt (±5%). | No C++ copies of the loader or fitting to drift. About 2 s per platform, so it runs with every test. Jolt and the harness agree within 0.4%. |
| D44 | 2026-10-10 | Yaw normalization (supersedes the steering rule in PLATFORMS §4.2) | **Grip forces act at the reference arms.** Tire slip velocities and the yaw moment of the tires' ground-plane forces use the hub positions scaled to `L_ref` and `T_ref`. Yaw inertia and steering are the reference's (`δ` no longer scales with `L`). | Scaling steering by `L/L_ref` can't keep yaw dynamics equal: the bicycle model's stability term goes with `1/L`. Measured on GT: step-steer rise time ±9%, slalom −3.3%. After: < 0.3%. Cost: slight wheel scrub in tight turns on cars far from the reference wheelbase. |
| D45 | 2026-10-10 | Vertical normalization (R2) | Extra pitch moment so longitudinal load transfer keeps the reference's `h/L`. Effective track weighted by roll share; per-axle roll stiffness `share · (T_ax/T) · K_φ` with a signed bar (no clamp at 0); roll inertia `∝ T · T_ref`; a roll damping bar; CoG measured from where the wheels touch down. | Before: 0–100 km/h −8.8%, 100–0 m +4.8% at the grid corners (the known residual R2). After: < 0.35%. Wide geometry ranges stay, so few models get scaled. |
| D46 | 2026-10-10 | TCS at a standing start | TCS ignores wheelspin while the clutch is slipping. | Found by the runner: on some fits TCS cut the throttle at launch, the engine couldn't rev past idle, the auto clutch never engaged and the car sat still. |
| D47 | 2026-10-10 | AWD and per-axle diffs | `differential.center` (`open`/`viscous`/`locked`, `front_share`) under `differential`, with `front`/`rear` overrides for the axles. Drive torque reaches each driven wheel by its share; each axle's LSD locks on the torque that axle gets. | Keeps all diff settings in one block, so tuning paths like `differential.center.front_share` work. Fixed on the way: each axle's LSD used to see the whole input torque. |
| D48 | 2026-10-10 | Kart chassis and stiff springs | `suspension.type: "rigid"` (stiff contact spring, no visible travel) instead of a separate physics path. Springs, dampers, bump stops and over-travel rates are capped for the 120 Hz tick. Wheel inertia from the platform or `0.0085 · m · r²`. | Same code path, so normalization and conformance apply to karts too. A fixed 1.2 kg·m² wheel inertia was like 245 kg of extra mass on a 170 kg kart. |

## Risks

| # | Risk | Impact | Mitigation | When |
|---|---|---|---|---|
| R1 | Godot's built-in SDL3 (joypads) and our SDL3 (wheels/FFB) both open the same device | Wheel input or FFB breaks | Done in M1 (D35): the native layer owns non-gamepad devices from the start, and Godot's gamepad buttons only listen to the chosen gamepad. Coexistence confirmed on Linux with a gamepad attached; wheel FFB awaits a hardware test. | M1 |
| R2 | Handling normalization leaves residual differences (longitudinal load transfer) | Unfair classes | Done in M2 (D43–D45): conformance runner at ±2% on every official platform; normalization brought the residuals under 1%. `strict` fitting remains for servers. | M2 |
| R3 | Runtime FBX import quality varies; OBJ has no runtime loader | Some models fail to import | GLB first. FBX through `FBXDocument`. Document Blender export. OBJ loader only if demand appears. | M2 |
| R4 | Untrusted model and track files (parser bugs, decompression bombs) | Crashes, exploits | Pre-parse limits, worker thread with timeout, no Godot resource formats, hash checks | M1+ |
| R5 | Client-authoritative car contact feels mushy or exploitable | Bad online racing | Bounded contact impulses, ghosting option, plausibility checks | M5 |
| R6 | macOS wheel FFB | Mac sim users get no FFB | Best effort only, documented (D24) | M4 |
| R7 | Float precision in endless and large maps | Jitter, physics glitches | Floating origin, sector-based network positions | M9 |
| R8 | 4-player splitscreen performance on mid-range GPUs | Below 60 fps | Retro style, per-viewport render scale, LOD bias | M3 |
| R9 | 200k-triangle player cars × 16 online plus 4 viewports | GPU and memory pressure | Distance LODs (provided or generated), shared caches, server package caps | M5 |
| R10 | Scope: 4 modes, editor, online, 4 vehicle families | Never finishing | Strict milestone order. Each milestone ships something playable. | always |

## Open questions

| # | Question | Decide by |
|---|---|---|
| Q1 | ~~Exact Godot version to pin (latest stable at M0)~~ Decided: D31 | M0 |
| Q2 | ~~SCons vs. CMake for `noss_core`~~ Decided: D32 | M0 |
| Q3 | ~~Run physics on Godot's separate physics thread?~~ Decided: D34 | M1 |
| Q4 | Terrain: Terrain3D addon vs. our own | M6 |
| Q5 | macOS signing and notarization (needs an Apple developer account) | First public release |
| Q6 | macOS test hardware | M1–M5 |
| Q7 | Final names for kart items, modes and classes | M8 |
| Q8 | Default network port (47800 for now) | M5 |
