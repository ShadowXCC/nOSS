# Platforms

A **platform** is the mechanical identity of a vehicle: everything that decides how it drives. A player's model only decides how it looks. Requirements: PLT-01…PLT-10.

---

## 1. Concepts

- **Platform:** a JSON file (`*.platform.json`) validated against `data/schemas/platform.schema.json`.
- **Class:** the player-facing name of a platform within a mode (e.g. *Track / GT*). One class corresponds to one platform file.
- **Mode file:** `data/modes/<mode>.mode.json`. Lists the classes a mode offers and narrows tuning, assists and damage.
- **Family:** decides the wheel layout and physics module, and which models can mount the platform.

| Family | Layout | Physics module | Examples |
|---|---|---|---|
| `car` | 2 axles, 4 wheels | core | sedans, sports cars, pickups, SUVs, GT and touring racers |
| `open` | 2 axles, 3–4 wheels, exposed | core (kart sub-type: no suspension, spool axle) | karts, formula cars, 3-wheelers, oddities |
| `truck` | 2–4 axles, dual wheels | core with multi-axle support | buses, semis, race trucks (M10) |
| `moto` | 2 wheels in line | moto module | motorcycles (M10+) |

**Who decides what:**

| Decided by the platform | Decided by the model |
|---|---|
| Mass, inertia, CoG | Body shape and look |
| Engine, gearbox, diff | Visual wheel size and position (within limits) |
| Tires, suspension, brakes, aero | Paint slots, lights, interior |
| Allowed tuning and assists | Engine sound (tuned built-in or own recordings) |
| Damage effects | Collision envelope (clamped) |

## 2. Platform file

Example: an official Track/GT platform. All values are illustrative and get tuned during M1–M4.

```json
{
  "schema": "noss.platform/1",
  "id": "official.track.gt",
  "name": "GT",
  "version": "1.0.0",
  "family": "car",
  "modes": ["track"],
  "accepts_families": ["car"],

  "layout": {
    "drive": "rwd",
    "axles": [
      { "steer": true,  "driven": false, "wheels": 2 },
      { "steer": false, "driven": true,  "wheels": 2 }
    ]
  },

  "geometry": {
    "wheelbase_m":    { "ref": 2.60, "min": 2.30, "max": 2.95 },
    "track_m":        { "ref": 1.60, "min": 1.45, "max": 1.75 },
    "ride_height_m":  { "ref": 0.09, "min": 0.06, "max": 0.14 },
    "wheel_radius_m": { "ref": 0.33, "min": 0.29, "max": 0.37 },
    "envelope_m": {
      "length": [3.8, 4.9], "width": [1.70, 2.05], "height": [1.00, 1.45]
    }
  },

  "mass": {
    "kg": 1300,
    "front_weight": 0.47,
    "cog_height_over_track": 0.28,
    "yaw_dynamic_index": 0.95
  },

  "engine": {
    "torque_curve_nm": [[1000, 280], [3000, 430], [5000, 540], [6000, 560], [7500, 480], [8200, 420]],
    "idle_rpm": 950, "redline_rpm": 8000, "limiter_rpm": 8200,
    "inertia_kgm2": 0.14, "engine_brake_nm": 70
  },
  "gearbox": {
    "type": "sequential",
    "ratios": [3.10, 2.25, 1.75, 1.42, 1.19, 1.02],
    "reverse": 3.0, "final_drive": 3.70, "shift_time_s": 0.07
  },
  "differential": { "type": "lsd_clutch", "preload_nm": 80, "power_lock": 0.45, "coast_lock": 0.25 },
  "brakes": { "max_torque_nm": 6000, "bias_front": 0.62 },
  "suspension": {
    "front": { "freq_hz": 2.8, "damping_bump": 0.55, "damping_rebound": 0.75, "travel_m": 0.08 },
    "rear":  { "freq_hz": 2.6, "damping_bump": 0.55, "damping_rebound": 0.75, "travel_m": 0.09 },
    "roll_gradient_deg_per_g": 0.9,
    "roll_stiffness_front_share": 0.55
  },
  "steering": { "max_road_angle_deg": 28, "wheel_rotation_deg": 540 },
  "aero": { "cd_a": 0.80, "cl_a_front": -0.40, "cl_a_rear": -0.60, "slipstream": true },
  "tires": {
    "model": "pacejka_lite", "compound": "semi_slick",
    "mu_peak": 1.40, "load_sensitivity": 0.08,
    "peak_slip_ratio": 0.10, "peak_slip_angle_deg": 7.5,
    "relaxation_length_m": 0.25, "rolling_resistance": 0.012,
    "wear": false, "temperature": false
  },

  "assists_allowed": ["abs", "tcs", "stability", "auto_gearbox", "auto_clutch", "steer_aid", "racing_line"],
  "damage": { "cosmetic": true, "mechanical": ["alignment", "aero", "engine", "suspension"] },

  "tunable": {
    "gearbox.final_drive":               { "min": 3.20, "max": 4.30, "step": 0.05 },
    "gearbox.ratios":                    { "mode": "per_gear", "min": 0.80, "max": 3.60, "step": 0.01 },
    "brakes.bias_front":                 { "min": 0.52, "max": 0.70, "step": 0.01 },
    "suspension.front.freq_hz":          { "min": 2.4, "max": 3.2, "step": 0.05 },
    "suspension.rear.freq_hz":           { "min": 2.2, "max": 3.0, "step": 0.05 },
    "suspension.roll_stiffness_front_share": { "min": 0.45, "max": 0.65, "step": 0.01 },
    "aero.cl_a_rear":                    { "min": -0.80, "max": -0.40, "step": 0.05 },
    "differential.power_lock":           { "min": 0.20, "max": 0.80, "step": 0.05 }
  },

  "ffb": { "reference_rack_nm": 9.0 }
}
```

**Design notes:**
- `brakes.max_torque_nm` is the total brake torque at full pedal, split by `bias_front` (D38).
- `differential` holds the driven axles' diff; `differential.front` / `.rear` override it per axle, and `differential.center` (`open`, `viscous` or `locked`, with `front_share`) splits AWD torque. A center needs two driven axles.
- `suspension.type: "rigid"` makes a kart-style chassis (stiff contact spring, no visible travel).
- `tires.wheel_inertia_kgm2` is optional; the default scales with mass and wheel radius.
- `geometry.ride_height_m` is not used yet: in M1 the model's own ground line sets the static ride height.
- Suspension is specified as **natural frequency and damping ratio**, not spring rates. Rates are derived from sprung mass, so they don't depend on geometry (§4).
- A missing optional block uses a family default (`data/platforms/_defaults/<family>.json`: `car` and `open` so far). An official platform must end up with every physics block after that merge, so none falls back to the sim's built-in numbers.
- `id` namespaces: `official.*` is reserved and loads only from the game's own `data/`. Custom platforms use `<author>.<name>`.
- Results, ghosts and leaderboards store the platform `id` and its **content hash**, so a modified file never counts as official.

## 3. Mode overrides and tuning

```json
{
  "schema": "noss.mode/1",
  "id": "kart",
  "classes": ["official.kart.light", "official.kart.medium", "official.kart.heavy"],
  "tuning": { "allow": [] },
  "assists": { "allowed": ["auto_gearbox", "steer_aid", "item_assist"], "defaults": ["auto_gearbox"] },
  "damage": { "cosmetic": true, "mechanical": false },
  "default_car": "res://content/cars/noss_kart",
  "physics_layer": "kart_arcade",
  "arcade": { "grip": 1.25, "drift": { "min_speed": 8.0, "tiers_s": [0.6, 1.2, 2.0], "boost_s": [0.5, 0.9, 1.4] },
              "boost": { "accel": 6.0, "cap": 1.25, "pad_s": 0.8 }, "…": "air, stick, bounce, spin, slow, slipstream, tow" }
}
```

A mode's `default_car` is the car its classes start with (and the built-in AI field drives); `arcade` is the kart layer's numbers (`GameModes.arcade` fills defaults and clamps; PHYSICS.md §9).

**Precedence (narrowest wins):** platform `tunable` → mode `tuning.allow` → server settings (`allow`, `lock`). Each layer can only remove or narrow options; it can never widen them.

| Mode | Tuning allowed by default |
|---|---|
| Track | Everything the platform allows |
| Kart | Nothing |
| Highway | Final drive, brake bias |
| Endless | Nothing (assists only) |

**Setups:** `user://setups/<platform>/<track>.json` stores only changes from the defaults, and can be shared. They are validated against the platform's ranges when loaded: unknown paths and wrong types are dropped, numbers are clamped and snapped to the step, and gear ratios stay in order. The Setup menu (pause menu, not during races) has a slider per value; changes apply when it closes and the car keeps moving. A changed setup shows as "Setup" in results and leaderboards; the platform's hash stays the official one (D70). AI drive the default setup.

## 4. Fitting and handling normalization

*Requirements: PLT-05, PLT-06.*

### 4.1 Adapting geometry

When a package is mounted on a platform:

1. **Measure** the model: wheelbase `L_m`, average track `T_m` (hub centers), visual wheel radius `r_vis` and envelope (AABB), all from `fit.json`.
2. **Scale if needed:** if `L_m` is outside `wheelbase_m [min, max]`, apply the uniform scale `s` that brings it to the nearest bound. Every measurement is multiplied by `s`. A platform may also set `fit.wheelbase_max_m`: a longer model is scaled down to that even when the range would take it (the kart classes: 1.35 m, so a car becomes kart-sized; the Fitting Bay says "Kart size (52%)", D150).
3. **Clamp:** after scaling, clamp track to `track_m`. If the track had to be clamped, the visual wheels move in or out along the axle. The Fitting Bay reports this, e.g. "Wheels moved 4 cm in".
4. The resulting **fitted geometry** `L`, `T` and envelope are used below. The wheel radius is cosmetic (§4.2).

### 4.2 Invariants that keep performance equal

The sim uses the fitted geometry for contact points, vertical loads and collisions, and derives everything else so that handling stays the same as the reference. In the ground plane the tires act as if they were at the reference wheelbase and track (D44); vertically the springs sit at the fitted hubs and are normalized so load transfer matches the reference (D45).

| Quantity | Rule | What stays equal |
|---|---|---|
| CoG position along the car | `b = w_f · L` (CoG to rear axle), `a = L − b` | Static weight distribution |
| Effective track | `T = Σ share_ax · T_ax`, weighted by each axle's share of roll stiffness | Per-axle lateral load transfer, also with front ≠ rear track |
| CoG height | `h = κ_h · T`, with `κ_h = cog_height_over_track`, above the plane where the wheels touch down | Lateral load-transfer ratio `2h/T` |
| Longitudinal load transfer | An extra pitch moment `−Δ · F_x` with `Δ = κ_h · (T_ref · L/L_ref − T)` | `h/L` as on the reference, so launch and braking match |
| Grip forces in the ground plane | Tire slip velocities and the yaw moment of `Fx`, `Fy` use the hub positions scaled to `L_ref` and `T_ref` | Yaw and lateral dynamics, diff and ABS yaw moments |
| Yaw inertia | `I_zz = DI · m · a_ref · b_ref` (the reference's) | Transient yaw response |
| Pitch inertia | `I_xx = 0.9 · DI · m · a · b` (fitted) | Pitch response (springs act at the fitted hubs) |
| Roll inertia | `I_zz,roll = m · 0.39² · T · T_ref` | Roll response, with roll stiffness ∝ T |
| Steering | `δ_road = δ_input · δ_max_ref`; Ackermann from `T_ref/L_ref` | Yaw rate per input and turning circle |
| Springs | `k = m_corner · (2π f)²` | Ride frequency |
| Roll stiffness | Total `K_φ` set so `roll_gradient_deg_per_g` holds. Each axle takes `share · (T_ax/T) · K_φ`: springs give `k·T_ax²/2` and the bar the rest, negative if needed | Roll gradient and balance |
| Roll damping | A damping bar per axle brings each wheel's roll damping to its value at `T_ref` | Transient load transfer |
| Wheel radius | Drivetrain uses `r_ref` (effective rolling radius). `r_vis` is only used for rendering and the suspension contact offset. Visual spin = `ω · r_ref / r_vis` | Gearing and top speed; no visible tread slip |
| Aero | Forces from fixed `CdA`/`ClA`, applied at the axles with a fixed balance | Drag, downforce, balance |
| Mass | Fixed per platform | — |

The conformance runner (§5) measures every official platform across its whole geometry grid. Since D44–D45 the residuals are well under 1%, so the ranges can stay wide. **Visual cost:** in very tight, slow turns a car far from the reference wheelbase scrubs its wheels slightly, because it turns like the reference. A server can set **`fitting: "strict"`**: physics then uses the reference geometry entirely and only the visuals adapt (wheels may sit slightly off their contact points).

### 4.3 Collision envelope

The convex hull of the model is clamped to `geometry.envelope_m` (length, width, height). Mass and inertia **never** come from the hull. In `strict` mode the reference box is used: the middle of each `envelope_m` range.

### 4.4 Model and platform compatibility

| Model | Platform family | Result |
|---|---|---|
| 4 wheels on 2 axles | `car`, `open` | Normal fit |
| 3 wheels | `car`, `open` | Physics uses the platform's layout. The single visual wheel sits on the axle centerline and shows both physics wheels of its axle, which take the other axle's track. |
| More axles than the platform has | any | Platform axle 1 is the model's first axle and the platform's last its last. Axles in between are visual only: they follow the nearest physics axle's spin and lift, with no forces. |
| Fewer axles than a `truck` platform | `truck` | Missing contact points are interpolated and invisible. |
| 2 inline wheels | `moto` only | Moto module |
| Not a 2-wheeler | `moto` | Rejected: "Needs a 2-wheel model" |

`accepts_families` on a platform can allow more, e.g. kart platforms accept `car`, `open` and `truck`, so a bus can enter a kart race.

## 5. Conformance tests

An automated, headless check that fitting never changes performance (PLT-06). `tools/run_conformance.sh` runs it, and so does `tools/run_tests.sh`.

- **Geometry grid:** wheelbase × track × wheel radius at `{min, ref, max}` = 27 configurations per platform, plus four edge cases: a model too small (scaled up), a track too wide (clamped), front ≠ rear track, and a `fit.json` ground line 3 cm off.
- **How it runs:** GDScript loads each official platform (validation and defaults), builds synthetic `fit.json`s and fits them with the game's own `Fitting`. The maneuvers run natively (`NossConformance.run_batch`) on a flat-ground harness at 120 Hz, on all CPU threads: about 2 s per platform.
- **Driver:** deterministic. It follows a path with the centre of mass and commands curvature through the platform's reference wheelbase and steering lock, so it never sees the fitted geometry. Assists: ABS, TCS, auto gearbox and clutch. The gear is frozen during held-speed maneuvers.
- **Maneuvers and metrics** (crossings interpolated between ticks):

| Test | Metric |
|---|---|
| Launch | 0–100 and 0–200 km/h times (not reached on both = pass) |
| Top speed | Speed after 60 s |
| Braking | 100–0 km/h distance from a steady 102 km/h, ABS on |
| Skidpad | Best 2 s of lateral g on a 60 m radius while the car holds the line (0.5 m) |
| Step steer | At 100 km/h, a 0.05 s ramp to the input that gives 0.4 g on the reference: yaw-rate rise time (10–90%) and peak/steady ratio |
| Slalom | Speed at which the path error through 10 gates 18 m apart reaches 1 m |
| Lap | Flying lap of the *Proving Ground* centreline at 75% of the tires' grip; off track fails |

- **Pass:** every metric is within **±2%** of the reference configuration (yaw rise time: or within 4 ms).
- **Engine check:** the reference configuration also runs on a real `Vehicle` with Jolt; launch and braking must match the harness within 5%.
- **Output:** `conformance.csv`, `summary.json` and `report.html` in `tests/conformance/out/` (gitignored).

## 6. Starter classes

Rough targets, tuned during development. Power figures are peak.

| Mode | Class | Family accepted | Drive | Power | Mass | Character |
|---|---|---|---|---|---|---|
| Track | Touring | car | FWD | 190 kW | 1250 kg | Street-sport tires, low aero, forgiving |
| Track | GT | car | RWD | 380 kW | 1300 kg | Semi-slicks, moderate aero |
| Track | Prototype | car | RWD | 480 kW | 1000 kg | Slicks, high aero |
| Track | Formula | open | RWD | 450 kW | 700 kg | Open-wheel, very high aero |
| Kart | Light / Medium / Heavy | car, open, truck | RWD | arcade | 160 / 200 / 260 kg | Top speeds within 1% (99.5 / 100 / 100.5 km/h geared); Light pulls 10% harder, Heavy 10% softer and wins the bumps (D134) |
| Highway | Street | car | AWD | 300 kW | 1500 kg | Stable at speed, street tires |
| Highway | Super | car | AWD | 500 kW | 1450 kg | Fast, demanding through traffic |
| Highway | Interceptor | car | AWD | 450 kW | 1700 kg | Police only (AI, and later players) |
| Endless | Cruiser | car, truck | RWD | 150 kW | 1400 kg | Calm, assists on |
| Endless | Sport | car | RWD | 260 kW | 1350 kg | Spirited |
| Drag | Street | car, open, truck, moto | RWD | 265 kW | 1400 kg | 6 gears: five shifts to time |
| Drag | Pro | car, open, truck, moto | RWD | 470 kW | 1150 kg | 5 gears, and it bites |
| Drag | Top Fuel | car, open, truck, moto | RWD | 620 kW | 1000 kg | 4 gears, no mistakes |
| Track (M10) | Race Truck | truck | RWD | 750 kW | 5300 kg | Truck racing |

**Shipped in M2:** Track Touring, GT, Prototype and Formula, Kart Medium (a prototype on the core sim), and Highway Street. **M8:** Kart Light and Heavy, and the `kart_arcade` layer on all three; they pass conformance with it on, with the `drift` and `boost` maneuvers too; their default car is the built-in **nOSS Kart**. **M7:** Highway Super (about 506 kW, 1450 kg) and Interceptor (about 449 kW, 1700 kg, police only), and the traffic platforms `official.traffic.car`, `van`, `truck` and `bus` (family car, highway only; trucks 9 t and buses 12 t), which drive the traffic near players (D117); the endless road's traffic uses them too. **M9:** Endless Cruiser (about 151 kW, 1400 kg) and Sport (about 260 kW, 1350 kg), both rear drive, with assists allowed and on, the autodrive included (`data/modes/endless.mode.json`). Every one passes conformance across its geometry grid (§5). The kart's ranges are wide (wheelbase 1.1–2.8 m) so cars, karts and trucks all fit without much scaling. Formula only takes `open` models; the built-in **nOSS Open** is its default car.

**Mini games:** **Sumo** (900 kg, all-wheel drive, one gear) and the three **Drag** classes, all of which any model may mount, so nobody wins a mini game by what they brought. The drag classes are sequential-box rear drive with real gearing, because timing the shifts is the game (D169) — the mode allows no automatic gearbox at all. Their gearing is set so the mode's fixed needle sweep lands near the real power band, and their power-to-weight is kept inside what the conformance lap can hold: Top Fuel is about 0.62 kW/kg, in Formula's neighbourhood, rather than the 0.82 it started at, which could not get round the Proving Ground at all.

Free Drive asks for the class first (how the car drives), then the car (how it looks); the car list only shows models the class accepts.
