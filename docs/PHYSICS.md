# Vehicle physics

The sim-cade driving model: one core for every mode, with parameters set entirely by the platform ([PLATFORMS.md](PLATFORMS.md)). It is implemented in C++ in `noss_core/src/vehicle/`. Requirements: PLT-01, PLT-06, PLT-07, PLT-10, INP-05, INP-07.

---

## 1. Goals

- **Sim-cade, like GT and Forza Motorsport.** Believable weight transfer and tire behavior. Fun on a controller, rewarding on a wheel.
- **One model, platform-parameterized.** No per-car code.
- **Stable** at 120 Hz with 4 substeps, from 0 to 400 km/h, over curbs, jumps and collisions.
- **Repeatable:** the same build with the same inputs and state gives the same result. Bit-exact results across platforms are not required.
- **SI units** internally (m, kg, s, N, rad).

## 2. Structure

```
VehicleSim (per vehicle, C++)
├─ Wheel[n]        suspension state, contact, tire state, spin ω
├─ Engine          torque table, idle, limiter, inertia
├─ Clutch          torque-capacity coupling
├─ Gearbox         H / sequential / auto, shift timing
├─ Differentials   per driven axle, plus center diff for AWD
├─ Brakes          per-wheel torque, bias, handbrake, ABS
├─ Aero            drag, downforce per axle, slipstream
├─ Assists         TCS, stability, steer aid, auto-clutch, auto-gearbox
├─ Damage          zone damage state and mechanical effects
├─ Layers          optional mode modifiers (e.g. kart_arcade)
└─ Outputs         telemetry, FFB rack force, audio params
```

**Per 120 Hz tick:**
1. Read controls from the VehicleController (already filtered and assisted).
2. Read the chassis state from Jolt.
3. Shape-cast each wheel.
4. Run 4 substeps:
   - suspension forces
   - tire slip and forces
   - drivetrain and wheel spin integration
   - brakes
5. Apply the averaged forces and torques to the rigid body.
6. Publish outputs.

## 3. Suspension

- **Contact:** per-wheel **shape cast** (a cylinder, or a sphere as fallback) along the suspension axis from the hub's top-of-travel. Contact gives the normal, penetration, the collider's surface type and its velocity (for moving platforms). *v1 casts one ray per wheel, starting a wheel radius above the top of travel so deep bumps still hit (D36). Surfaces come from the collider's `noss_surface` meta.*
- **Springs:** `F = k·x` with `k` derived from the platform's natural frequency ([PLATFORMS.md §4.2](PLATFORMS.md#42-invariants-that-keep-performance-equal)), plus progressive bump stops in the last 15% of travel.
- **Dampers:** separate bump and rebound damping ratios (linear in v1, with a fast/slow knee later). The compression rate is the hub's speed toward the ground along the contact normal, so driving along a flat road never compresses the springs, even with the body pitched.
- **Anti-roll bars:** `F = k_arb · (x_L − x_R)` per axle, sized to hit the target roll gradient and front share (negative if the springs alone are too stiff, D45). A roll damping bar does the same for damping.
- **Kart sub-type** (`suspension.type: "rigid"`): no visible suspension travel. The front/rear `freq_hz` (4 Hz or more) and `travel_m` (0.04 m or less) describe a stiff contact spring; pair it with a `spool` rear axle.
- **Stability caps:** springs are integrated once per 120 Hz tick, so stiff ones are capped at `ω·dt ≤ 0.8` (spring at half that), and the bump stop's zone widens until its stiffness fits. Karts and hard landings stay stable; GT-like platforms are below the caps.

## 4. Tires: "Pacejka-lite"

- **Pure slip:** a simplified Magic Formula, `F = D · sin(C · atan(B·s − E·(B·s − atan(B·s))))`, for longitudinal slip ratio κ and lateral slip angle α. The coefficients are derived from the platform's `mu_peak`, `peak_slip_ratio` and `peak_slip_angle_deg`.
- **Combined slip:** normalized slip vector σ = √((κ/κ_peak)² + (α/α_peak)²). Force direction follows the slip vector, which gives a friction ellipse.
- **Load sensitivity:** `μ = μ_peak · (1 − ls · (Fz/Fz0 − 1))`.
- **Relaxation length:** lateral slip lags on the scale of `relaxation_length_m`, which stabilizes low speeds and gives natural turn-in.
- **Low-speed blend:** below ~3 m/s, the slip-based model blends into a damped static-friction model. Cars stop and hold on slopes instead of jittering.
- **Self-aligning torque** `Mz = −t(α) · Fy`, where pneumatic trail `t` falls off past the slip peak. Drives FFB (§11).
- **Rolling resistance:** `C_rr · Fz`.
- **Optional, per platform (off by default):** temperature grip window (later).
- **Fuel and tire wear (D209):** with an event's fuel use or tire wear on (1×–10×), `CarWear` counts what each car's sim did (`VehicleSim.take_wear`, ten times a second): the engine's work burns fuel at the platform's `fuel.l_per_kwh` times the multiplier from its `fuel.tank_l`, and each tire's sliding work (|F| × slip speed) wears it, a whole `tires.life_mj` (÷ the multiplier) taking it from new to its `tires.worn_grip`. Worn tires grip less (`set_wheel_grip`, a share per wheel on μ); out of fuel the engine makes no power (`set_power_scale` 0) and the car only coasts. A class without its own figures takes 70 L, 0.32 L/kWh, 60 MJ and 0.85. The car's mass stays the same as its fuel burns, so conformance and the online checks hold. At 1× a Stock Car on Piedmont Speedway burns about 1.16 L a lap (about 59 laps a tank) and a set of tires lasts about 84 laps. With full power and new tires the sim is bit for bit what it was.

### Surfaces

The surface type comes from the collider (track material tag).

| Surface | Grip × | Wet | Under snow | Extra |
|---|---|---|---|---|
| Asphalt | 1.00 | 0.75 | 0.45 | — |
| Concrete | 0.97 | 0.7275 | 0.45 | — |
| Curb | 0.90 | 0.675 | 0.45 | Vibration in FFB and audio |
| Painted line | 0.95 | 0.7125 | 0.45 | — |
| Grass | 0.60 | 0.60 | 0.35 | Rolling drag ↑ |
| Gravel | 0.55 | 0.55 | 0.35 | Heavy drag, spray |
| Dirt | 0.70 | 0.70 | 0.35 | — |
| Sand | 0.40 | 0.40 | 0.35 | Very heavy drag |
| Snow | 0.35 | 0.35 | 0.35 | — |
| Ice | 0.12 | 0.12 | 0.12 | — |

**Wet and snowy roads (D153):** sealed surfaces lose a quarter of their grip wet (grip × (1 − 0.25 · wetness)); under snow they pack down to 0.45, and loose ones go to snow's 0.35. With wetness w and snow cover c (0–1, from the weather, [GAMEMODES.md §0](GAMEMODES.md#0-common-to-all-modes)): `g_w = g + (wet − g) · w`, then `g_w + (snow − g_w) · c`. Each car gets its road's conditions a few times a second (`VehicleSim.set_conditions`); a car in a tunnel stays dry. With both at 0 the model is bit for bit what it was. The ESC's grip limit follows the same factor, and the AI's speed profiles use it (rounded to 0.05). Measured on the conformance harness, fully wet: the GT class's skidpad 0.75× dry and braking from 100 km/h 1.26× the distance (every class: 0.73–0.78× and 1.10–1.32×, `tools/run_conformance.sh`'s weather lines); in the game an AI race in the rain laps about 15% slower than dry, with no pile-ups. Puddles and aquaplaning come later.

## 5. Drivetrain

- **Engine:** torque from the RPM table × throttle. Engine braking and friction off-throttle. An idle controller and a rev limiter (fuel cut). EV platforms: flat torque, then power-limited, single-speed, optional regen.
- **Clutch:** coupling limited by torque capacity. **Auto-clutch** (default on for keyboard and controller) handles launch and stall prevention.
- **Gearbox:**
  - `manual_h`: needs the clutch (pedal past half) unless auto-clutch is on; neutral always works. A refused change grinds (a sound and "Clutch" on the HUD). Supports an H-shifter: the gate held selects that gear, no gate is neutral.
  - `sequential`: up/down paddles.
  - `auto`: always shifts by RPM and throttle; paddles do nothing.
  - The auto-gearbox assist shifts `manual_h` and `sequential` boxes too.
  - All types use the platform's `shift_time_s`.
- **Differentials:** per axle `open`, `lsd_clutch` (preload plus power/coast lock ramps on the torque that axle receives) or `locked`/`spool`. `differential.front` and `.rear` override the shared settings.
- **Center diff (AWD):** `differential.center` with `front_share`. `open` splits the torque by that share; `viscous` adds a coupling torque `preload + c · |Δω|` between the axles' mean speeds; `locked` holds them together. Solved as torque-limited impulses like the axle diffs.
- **Layouts:** FWD, RWD and AWD. Trucks choose which axles are driven (e.g. 6×4).
- **Wheel spin integration:** `I_w · dω/dt = T_drive − T_brake − Fx · r_ref` at 480 Hz. `I_w` is the platform's `tires.wheel_inertia_kgm2`, or `0.0085 · m · r_ref²` (1.2 kg·m² on GT, 0.03 on a kart).

## 6. Brakes

- Per-axle maximum torque, with the platform's front bias (tunable).
- **Handbrake:** rear axle, high torque, can lock the wheels.
- **ABS:** slip-ratio target controller per wheel. Allowed and defaulted per platform and mode.

## 7. Aero

- **Drag:** `½ρ · CdA · v²` at the CoG.
- **Downforce:** `½ρ · ClA · v²`, front and rear, applied at the axles (fixed balance).
- **Slipstream:** if another car is within a cone behind it (≤ 30 m, ±1.5 m lateral), drag is reduced by up to 30%. The effect fades with distance. On or off per mode. Built for karts in M8 (`KartControl`, 30 times a second; a Magnet triples it, D139).
- **Drafting (Track, D208):** with an event's drafting on, every Track class whose platform has `aero.slipstream` drafts (`DraftControl`, 30 times a second, on the cars each game drives). Tucked in behind another car within 40 m and 1.2 m of its line, drag drops by up to 30% (more the closer, nothing behind a car under 20 m/s); the car in front of one within 10 m loses up to 4% too. The sim multiplies its drag by `VehicleModel::drag_scale` (1: the platform's own, the sim exactly). The tuning is the Track mode's `draft`. The AI keeps the speed a tow gives it, up to the line's ceiling (corners and braking, power aside).

## 8. Steering and assists

- **Steering:** `δ_road = δ_input · δ_max_ref`, the same on every fit, because grip forces act at the reference wheelbase ([PLATFORMS.md §4.2](PLATFORMS.md#42-invariants-that-keep-performance-equal), D44). Ackermann factor from the reference proportions.
- **Steer aid** (controller and keyboard): speed-sensitive lock reduction, plus counter-steer help that nudges toward the slip angle.
- **TCS:** limits driven-wheel slip by reducing torque. It also reacts to the combined slip, since a tire that's busy cornering breaks away before its slip ratio alone looks high.
- **Auto-gearbox reverse:** holding the brake at a standstill selects reverse, and the brake pedal then drives backwards; throttle returns to first. Off throttle, it only upshifts near the redline.
- **Stability control:** compares the measured yaw rate with a neutral-steer target (steering and speed, capped at 90% of grip). Turning more than asked, or sliding past 4°, brakes the outside front wheel and trims the throttle; turning much less than an understeering car would (characteristic speed 25 m/s) brakes the inside rear (D68). Off by default and in the conformance driver.
- **Auto-gearbox, auto-clutch, ABS:** see above.
- **Racing line:** visual only: the AI line on the road, coloured by its target speed (fast, lift, brake, in the player's palette) with chevrons in braking zones. Each player sees only their own.
- **Access assists:** auto-throttle, brake assist and steering assist follow the AI line ([ACCESSIBILITY.md §5.2](ACCESSIBILITY.md#52-driving-assists-for-access)); a `RacingAI` running as a guide works out its controls and the player's are blended with them.
- Each assist is allowed per platform, then mode, then server ([PLATFORMS.md §3](PLATFORMS.md#3-mode-overrides-and-tuning)). Steer aid, auto gearbox and auto clutch can be **Auto**: on with keyboard or controller, off with a wheel (or a clutch pedal, for the clutch) (D74).

### AI line (AI-01)

- **Line:** a minimum-curvature path inside the road (1.3 m from the edge, 0.5 m onto curbs), found by relaxing the lateral offsets coarse to fine (D64).
- **Speeds:** per platform: the corner speed the tires allow (with downforce), a forward pass limited by power and traction, and a braking pass limited by grip and by the **brake balance** (the axle that runs out of grip first under load transfer).
- **Driving:** the AI and the access assists follow it with pure pursuit and the profile's speed, using only the assists a player could (AI-05). Traffic rules: D65.

## 9. Mode layers

**`kart_arcade`** (M8, D130–D133). Modifiers on the same core, not a separate sim: `native/src/vehicle/kart_layer.{h,cpp}`, an optional `KartLayer` in VehicleModel that gives `KartMods` each tick (grip, side force, the slip angle the tires see, wheel steer, drive power, drag, a free clutch, extra force and torque). With no layer the model runs exactly as before (a pinned trajectory hash). Every force is the car's mass × an acceleration or the reference yaw inertia × an angular acceleration, so the kart classes pass conformance at ±2% with it on. Its numbers are in `data/modes/kart.mode.json` (`arcade`).
- Grip × 1.25 and a stronger steer aid.
- **Drift** (hold at 8 m/s or more, steering 0.3 or more one way; the side locks): an arcade slide. A centripetal pull of 0.15–1.0 g set by the steering adds to the tires'; the tires see 0.3 of their slip angle, side grip × 0.35 and wheel steer × 0.3; the body is yawed toward the path's rate plus a slip of 0.25–0.45 rad (at most 12 rad/s²). Charge (2 wheels down, 8 m/s) reaches tiers at 0.6 / 1.2 / 2.0 s, giving boosts of 0.5 / 0.9 / 1.4 s on release; letting go blends grip and steer back over 0.4 s with the yaw steadied toward the path.
- **Boost:** +6 m/s² up to × 1.25 the class's geared top speed, the clutch free above the limiter. Boost pads (tag 1) give 0.8 s.
- **Air control** after 0.1 s with no wheel down: pitch, roll and yaw (3, 3, 2 rad/s²), levelled and damped. A trick (drift pressed within 0.35 s of leaving a jump, tag 2) gives a 0.6 s boost on an upright landing.
- **Stick gravity** (tag 4: wall-rides, loops): at 7 m/s or more gravity points into the surface, held 0.25 s after contact is lost (D133).
- **Self-righting** after 1.5 s on the roof or side. Walls bounce at 0.6 and karts at 0.3 (mass decides); stunt pieces don't bounce.
- **Item effects:** spin-out (1.2 s, grip × 0.35, about 1.3 turns, braking at 10 m/s²), slow (power cut), boost, cancel; a 3 m/s knock comes from the item.

**Highway and endless** use the core unchanged. Endless's classes (`data/modes/endless.mode.json`: Cruiser, 150 kW, 1400 kg, rear drive; Sport, 260 kW, 1350 kg) have assists allowed and on, the autodrive included, and no racing line.

## 10. Collisions and damage

- **Chassis collision:** the fitted envelope's convex hull, with low friction (0.3) and low restitution (0.1).
- **Reset:** a key or button returns the car to the last valid spline position, after a 1 s delay in races.
- **Damage zones:** front, rear, left, right and roof. Each accumulates impact energy from contact impulses.
  - **Cosmetic** (AV-07): sets a per-zone damage level for the visuals (scratch/dirt blend, broken glass and lights).
  - **Mechanical** (PLT-10, only if enabled for the platform and mode):

| Effect | Trigger | Result |
|---|---|---|
| `alignment` | Front impacts | Steering offset and toe change |
| `aero` | Front or rear | Downforce ↓, drag ↑ |
| `engine` | Front, heavy | Power ↓; limp mode at severe levels |
| `suspension` | Wheel-area impacts | Travel ↓, damping ↓ |

- Repair: reset or pit (M10), or full repair between sessions.

## 11. Force feedback

*Requirements: INP-05. Output path in [INPUT.md](INPUT.md).*

- **Rack force:** front tires' `Mz` plus `Fy` × mechanical trail (caster), summed through the steering geometry. It's normalized by the platform's `ffb.reference_rack_nm`, then scaled by the player's gain and the wheel's max torque.
- **Effects** (each with its own gain):
  - Road texture: surface noise from the contact patch.
  - Curb rumble: periodic, scaled by speed.
  - Collision jolts.
  - Slip vibration (optional).
  - Engine vibration (optional, off by default).
  - Low-speed centering spring and damper.
- **Update path:** each tick the game sends what the car is doing (rack force, speed, curbs and road under the front tires, front slip, rpm, collision impulse, wheel position). The native FFB thread runs a **mixer** at ~500 Hz (`native/src/ffb/`) and sends one `SDL_HAPTIC_CONSTANT` level; the device's own `DAMPER` effect is used when it has one, otherwise damping is mixed in too (D76).
- **Soft lock:** the wheel's rotation range matches the platform's steering lock (`steering.wheel_rotation_deg`), at full strength whatever the gain.
- **Settings and diagnostics:** overall gain, the wheel's torque (Nm), a gain per effect, damping, friction, smoothing, min force, invert, a clipping meter and a test that plays every effect.
- **Controllers** rumble from the same signals (slides and curbs on the small motor, knocks on the big one), with a strength setting.

## 12. Motorcycles (M10+)

A separate `moto` module, since lean dynamics don't fit the 4-wheel core:
- Two inline contacts. Lean angle is a state.
- **Player input sets a target lean.** An automatic counter-steer controller turns that into steering.
- Camber thrust dominates lateral force. Wheelie and stoppie limits. Crash threshold based on lean and slip.
- Fitting uses `hub_C1` and `hub_C2`.

## 13. Heavy trucks (M10)

- Multi-axle contact, where dual tires share one load and contact.
- Steer axles can be 1 or 2. Driven axles are configurable.
- Lift axles and trailers come later.

## 14. Implementation notes (v1)

- **Frames:** the body frame is the fitted model frame (+X left, +Y up, +Z forward). Steering input is +1 = right; road angles are + = left.
- **Within a tick** the chassis state from Jolt is fixed. The 4 substeps integrate wheel spin, the engine and the tire relaxation states; the averaged force and torque go to Jolt.
- **Wheel spin is implicit:** each tire's longitudinal force is linearized around the current slip, which adds an effective inertia, so stiff tires stay stable at any speed.
- **Driveline as constraints:** clutch, limited-slip diff and brakes are torque-limited velocity constraints, solved with sequential impulses (8 iterations per substep). This handles slipping and locking clutches, diff lock and brake lock-up the same way.
- **Lateral slip** uses the relaxation length as a carcass deflection state: it lags at speed and acts as a spring at a standstill, with extra damping below 3 m/s.
- **Tests:** `tests/native/vehicle_test.cpp` drives the model with its own rigid-body harness: 0–100 km/h about 3.9 s, 100–0 km/h about 31 m with ABS, about 1.3 g on a skidpad-like corner, and no spin with TCS at full throttle out of a tight corner.

## 15. Outputs

Published each tick for the HUD, audio, FFB, the network, replays and UDP telemetry (AV-10):
- Speed, RPM, gear, and throttle/brake/clutch/steer inputs.
- Per-wheel: load, slip ratio, slip angle, suspension travel, surface.
- g-forces, boost, active assists, damage levels.
