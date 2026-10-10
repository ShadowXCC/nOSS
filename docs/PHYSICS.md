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
- **Optional, per platform (off by default):** temperature grip window and wear (for endurance, later).

### Surfaces

The surface type comes from the collider (track material tag).

| Surface | Grip × | Extra |
|---|---|---|
| Asphalt | 1.00 | — |
| Concrete | 0.97 | — |
| Curb | 0.90 | Vibration in FFB and audio |
| Painted line | 0.95 (wet 0.75) | — |
| Grass | 0.60 | Rolling drag ↑ |
| Gravel | 0.55 | Heavy drag, spray |
| Dirt | 0.70 | — |
| Sand | 0.40 | Very heavy drag |
| Snow | 0.35 | — |
| Ice | 0.12 | — |

**Wet:** grip × (1 − 0.25 · wetness) on sealed surfaces, with wetness 0–1 from weather ([GAMEMODES.md](GAMEMODES.md), ENV-02). Puddles and aquaplaning come later.

## 5. Drivetrain

- **Engine:** torque from the RPM table × throttle. Engine braking and friction off-throttle. An idle controller and a rev limiter (fuel cut). EV platforms: flat torque, then power-limited, single-speed, optional regen.
- **Clutch:** coupling limited by torque capacity. **Auto-clutch** (default on for keyboard and controller) handles launch and stall prevention.
- **Gearbox:**
  - `manual_h`: needs the clutch unless auto-clutch is on. Supports an H-shifter.
  - `sequential`: up/down paddles.
  - `auto`: shifts by RPM and throttle.
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
- **Slipstream:** if another car is within a cone behind it (≤ 30 m, ±1.5 m lateral), drag is reduced by up to 30%. The effect fades with distance. On or off per mode.

## 8. Steering and assists

- **Steering:** `δ_road = δ_input · δ_max_ref`, the same on every fit, because grip forces act at the reference wheelbase ([PLATFORMS.md §4.2](PLATFORMS.md#42-invariants-that-keep-performance-equal), D44). Ackermann factor from the reference proportions.
- **Steer aid** (controller and keyboard): speed-sensitive lock reduction, plus counter-steer help that nudges toward the slip angle.
- **TCS:** limits driven-wheel slip by reducing torque. It also reacts to the combined slip, since a tire that's busy cornering breaks away before its slip ratio alone looks high.
- **Auto-gearbox reverse:** holding the brake at a standstill selects reverse, and the brake pedal then drives backwards; throttle returns to first. Off throttle, it only upshifts near the redline.
- **Stability control:** compares the target yaw rate (from steering and speed) with the measured rate, then brakes individual wheels.
- **Auto-gearbox, auto-clutch, ABS:** see above.
- **Racing line:** visual only (from the track's AI line), colored by target speed.
- **Access assists:** auto-throttle, brake assist and steering assist follow the AI line ([ACCESSIBILITY.md §5.2](ACCESSIBILITY.md#52-driving-assists-for-access)).
- Each assist is allowed and defaulted per platform, then mode, then server ([PLATFORMS.md §3](PLATFORMS.md#3-mode-overrides-and-tuning)).

## 9. Mode layers

**`kart_arcade`** (M8). Modifiers on the same core, not a separate sim:
- Grip × 1.25 and a stronger steer aid.
- **Drift:** holding the drift button lowers rear lateral grip and adds controllable yaw torque. Charge tiers at 0.6 / 1.2 / 2.0 s give a boost on release.
- **Boost:** extra drive force, capped by a speed limit.
- **Air control:** pitch, roll and yaw torque while airborne. Trick input on ramps gives a landing boost.
- **Self-righting** after 1.5 s upside down. Walls bounce elastically.
- **Item effects:** spin-out (temporary grip loss plus a yaw impulse), slow (power cut), knock-back impulse.

**Highway and endless** use the core unchanged. Endless defaults to assists on.

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
- **Update path:** the sim publishes the target force each tick (with substep detail). The native FFB thread runs at ~500 Hz, interpolates, and updates an SDL3 `SDL_HAPTIC_CONSTANT` effect. Periodic and condition effects (`SPRING`, `DAMPER`) are used for rumble and centering.
- **Soft lock:** the wheel's rotation range matches the platform's steering lock (`steering.wheel_rotation_deg`).
- **Settings and diagnostics:** a clipping meter and a test button in settings.

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
