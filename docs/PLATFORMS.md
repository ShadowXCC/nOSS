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
- `geometry.ride_height_m` is not used yet: in M1 the model's own ground line sets the static ride height.
- Suspension is specified as **natural frequency and damping ratio**, not spring rates. Rates are derived from sprung mass, so they don't depend on geometry (§4).
- A missing optional block uses a family default (`data/platforms/_defaults/<family>.json`).
- `id` namespaces: `official.*` is reserved and loads only from the game's own `data/`. Custom platforms use `<author>.<name>`.
- Results, ghosts and leaderboards store the platform `id` and its **content hash**, so a modified file never counts as official.

## 3. Mode overrides and tuning

```json
{
  "schema": "noss.mode/1",
  "id": "kart",
  "classes": ["official.kart.light", "official.kart.medium", "official.kart.heavy"],
  "tuning": { "allow": [] },
  "assists": { "allowed": ["auto_gearbox", "steer_aid"], "defaults": ["auto_gearbox"] },
  "damage": { "cosmetic": true, "mechanical": false },
  "physics_layer": "kart_arcade"
}
```

**Precedence (narrowest wins):** platform `tunable` → mode `tuning.allow` → server settings (`allow`, `lock`). Each layer can only remove or narrow options; it can never widen them.

| Mode | Tuning allowed by default |
|---|---|
| Track | Everything the platform allows |
| Kart | Nothing |
| Highway | Final drive, brake bias |
| Endless | Nothing (assists only) |

**Setups:** `user://setups/<platform>/<track>.json` stores only changes from the defaults, and can be shared. They are validated against the platform's ranges when loaded.

## 4. Fitting and handling normalization

*Requirements: PLT-05, PLT-06.*

### 4.1 Adapting geometry

When a package is mounted on a platform:

1. **Measure** the model: wheelbase `L_m`, average track `T_m` (hub centers), visual wheel radius `r_vis` and envelope (AABB), all from `fit.json`.
2. **Scale if needed:** if `L_m` is outside `wheelbase_m [min, max]`, apply the uniform scale `s` that brings it to the nearest bound. Every measurement is multiplied by `s`.
3. **Clamp:** after scaling, clamp track to `track_m`. If the track had to be clamped, the visual wheels move in or out along the axle. The Fitting Bay reports this, e.g. "Wheels moved 4 cm in".
4. The resulting **fitted geometry** `L`, `T` and envelope are used below. The wheel radius is cosmetic (§4.2).

### 4.2 Invariants that keep performance equal

The sim uses the fitted geometry for contact points and collisions, and derives everything else from it so that handling stays the same as the reference.

| Quantity | Rule | What stays equal |
|---|---|---|
| CoG position along the car | `b = w_f · L` (CoG to rear axle), `a = L − b` | Static weight distribution |
| CoG height | `h = κ_h · T`, with `κ_h = cog_height_over_track` | Lateral load-transfer ratio `2h/T` |
| Yaw inertia | `I_zz = DI · m · a · b` (scales with L²) | Transient yaw response (dynamic index) |
| Roll and pitch inertia | `I_xx ∝ T²`, `I_yy ∝ L²` from the reference | Roll and pitch response |
| Steering | `δ_road = δ_input · δ_max_ref · (L / L_ref)` | Low-speed yaw rate per input (`r = V·δ/L`) and turning circle |
| Understeer gradient | `K = W_f/Cα_f − W_r/Cα_r` | Independent of L, given fixed `w_f` and tires |
| Springs | `k = m_corner · (2π f)²` | Ride frequency |
| Roll stiffness | Total `K_φ` set so `roll_gradient_deg_per_g` holds. Springs give `k·T²/2` per axle and the ARB makes up the rest, keeping the front/rear share | Roll gradient and balance |
| Wheel radius | Drivetrain uses `r_ref` (effective rolling radius). `r_vis` is only used for rendering and the suspension contact offset. Visual spin = `ω · r_ref / r_vis` | Gearing and top speed; no visible tread slip |
| Aero | Forces from fixed `CdA`/`ClA`, applied at the axles with a fixed balance | Drag, downforce, balance |
| Mass | Fixed per platform | — |

**Known residual:** longitudinal load transfer is `m·a_x·h/L`. With `h ∝ T`, it drifts when the fitted `T/L` ratio differs from the reference. Geometry ranges are chosen so that conformance (§5) stays within 2%. A server can set **`fitting: "strict"`**: physics then uses the reference geometry entirely and only the visuals adapt (wheels may sit slightly off their contact points).

### 4.3 Collision envelope

The convex hull of the model is clamped to `geometry.envelope_m` (length, width, height). Mass and inertia **never** come from the hull. In `strict` mode the reference box is used.

### 4.4 Model and platform compatibility

| Model | Platform family | Result |
|---|---|---|
| 4 wheels on 2 axles | `car`, `open` | Normal fit |
| 3 wheels | `car`, `open` | Physics uses the platform's layout. The single visual wheel sits on the axle centerline. |
| More axles than the platform has | any | Extra axles are visual only: they spin and follow the ground by raycast, with no forces. |
| Fewer axles than a `truck` platform | `truck` | Missing contact points are interpolated and invisible. |
| 2 inline wheels | `moto` only | Moto module |
| Not a 2-wheeler | `moto` | Rejected: "Needs a 2-wheel model" |

`accepts_families` on a platform can allow more, e.g. kart platforms accept `car`, `open` and `truck`, so a bus can enter a kart race.

## 5. Conformance tests

An automated, headless check that fitting never changes performance (PLT-06). It runs in CI on any change to a platform or the sim.

- **Geometry grid:** wheelbase × track × wheel radius at `{min, ref, max}` = 27 configurations per platform.
- **Driver:** a deterministic scripted controller with fixed assist settings per test.
- **Maneuvers and metrics:**

| Test | Metric |
|---|---|
| Launch | 0–100 km/h time, 0–200 km/h time (if reachable) |
| Top speed | Speed after 60 s on the straight |
| Braking | 100–0 km/h distance (ABS on) |
| Skidpad | Steady-state lateral g on a 60 m radius |
| Step steer | Yaw-rate rise time (10–90%) and overshoot at 100 km/h |
| Slalom | Max speed through 18 m cone spacing |
| Lap | Lap time on *Proving Ground* with the scripted line |

- **Pass:** every metric is within **±2%** of the reference configuration.
- **Output:** a CSV plus a short HTML report in `tests/conformance/out/`.

## 6. Starter classes

Rough targets, tuned during development. Power figures are peak.

| Mode | Class | Family accepted | Drive | Power | Mass | Character |
|---|---|---|---|---|---|---|
| Track | Touring | car | FWD | 190 kW | 1250 kg | Street-sport tires, low aero, forgiving |
| Track | GT | car | RWD | 380 kW | 1300 kg | Semi-slicks, moderate aero |
| Track | Prototype | car | RWD | 480 kW | 1000 kg | Slicks, high aero |
| Track | Formula | open | RWD | 450 kW | 700 kg | Open-wheel, very high aero |
| Kart | Light / Medium / Heavy | car, open, truck | RWD | arcade | 0.8× / 1× / 1.3× | Light accelerates fastest; Heavy wins bumps and has the highest top speed |
| Highway | Street | car | AWD | 300 kW | 1500 kg | Stable at speed, street tires |
| Highway | Super | car | AWD | 500 kW | 1450 kg | Fast, demanding through traffic |
| Highway | Interceptor | car | AWD | 450 kW | 1700 kg | Police only (AI, and later players) |
| Endless | Cruiser | car, truck | RWD | 150 kW | 1400 kg | Calm, assists on |
| Endless | Sport | car | RWD | 260 kW | 1350 kg | Spirited |
| Track (M10) | Race Truck | truck | RWD | 750 kW | 5300 kg | Truck racing |

M1 ships only **Track / GT**. The rest arrive in M2 and later milestones.
