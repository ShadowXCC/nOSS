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

## Risks

| # | Risk | Impact | Mitigation | When |
|---|---|---|---|---|
| R1 | Godot's built-in SDL3 (joypads) and our SDL3 (wheels/FFB) both open the same device | Wheel input or FFB breaks | Spike in M1. Fallback: native layer owns wheel-class devices, Godot ignores them by GUID. | M1 |
| R2 | Handling normalization leaves residual differences (longitudinal load transfer) | Unfair classes | Conformance tests at ±2%, tight geometry ranges, `strict` fitting option | M2 |
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
| Q1 | Exact Godot version to pin (latest stable at M0) | M0 |
| Q2 | SCons vs. CMake for `noss_core` | M0 |
| Q3 | Run physics on Godot's separate physics thread? | M1 |
| Q4 | Terrain: Terrain3D addon vs. our own | M6 |
| Q5 | macOS signing and notarization (needs an Apple developer account) | First public release |
| Q6 | macOS test hardware | M1–M5 |
| Q7 | Final names for kart items, modes and classes | M8 |
| Q8 | Default network port (47800 for now) | M5 |
