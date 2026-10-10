# Input

Keyboard, controller and sim rigs are all first-class. Requirements: INP-01…INP-07, LOC-04.

---

## 1. Actions

Each local player has their own set of actions:

| Group | Actions |
|---|---|
| Driving | `steer` (−1…1), `throttle`, `brake`, `clutch`, `handbrake` (0…1) |
| Gears | `shift_up`, `shift_down`, `gear_R`, `gear_N`, `gear_1`…`gear_7` (H-shifter) |
| View | `camera_next`, `look_left`, `look_right`, `look_back`, `free_look` (mouse or right stick) |
| Car | `horn`, `lights`, `reset_car`, `hotswap_menu` |
| Kart | `use_item`, `throw_back` (hold), `drift` |
| UI | `pause`, `chat`, `scoreboard`, `confirm`, `cancel` |

## 2. Input sources

| Devices | Path |
|---|---|
| Keyboard, mouse | Godot `InputMap` |
| Standard controllers (Xbox, PlayStation, Switch Pro, Steam Deck…) | Godot joypads (SDL3-based in 4.5+) |
| Wheels, pedals, shifters, handbrakes, button boxes | **`noss_core` native SDL3 joystick**: all axes at full resolution, any number of buttons, plus **haptics** for FFB |

**Risk** (tracked in [DECISIONS.md](DECISIONS.md)): Godot's built-in SDL3 and our SDL3 may both try to open the same wheel.
- **M1 spike:** confirm they can coexist.
- **Fallback:** the native layer owns wheel-class devices exclusively, and Godot ignores them, filtered by GUID.

## 3. Joining and device assignment

*Requirements: LOC-04.*

- **Join screen:** "Press any button to join". The first input from any device claims a free player slot.
- **Combining devices:** after joining, "Add device" lets a player claim more devices, e.g. a wheel plus separate pedals plus a shifter.
- **Remembered assignments:** saved by device GUID and name, then restored next time.
- **Shared keyboard:** two players can split one keyboard (WASD vs. arrows). Godot can't tell two keyboards apart, so each player needs separate keys.
- **Mouse steering** is only available to one player (there's one mouse).

## 4. Keyboard and controller

### Keyboard (INP-01)
- **Steering:** digital steering with smoothing. Rise and fall rates depend on speed. Counter-steer returns faster.
- **Mouse steering (optional):** horizontal mouse movement sets steering position, with optional auto-centering.

### Controller (INP-02)
- **Sticks:** inner and outer deadzone, linearity curve, speed-sensitive steering reduction, steering smoothing.
- **Triggers:** throttle and brake, with their own deadzones and curves.
- **Rumble** (Godot `start_joy_vibration`): tire slip, ABS, curbs, collisions.

## 5. Wheels, pedals, shifters

*Requirements: INP-03, INP-04.*

- **Calibration wizard:** wheel center and full lock. Pedal min and max, inverted pedals, combined-axis pedals. Handbrake axis or button.
- **Rotation range:**
  - Set the wheel's hardware range in settings.
  - The game applies a **soft lock** that matches the platform's `steering.wheel_rotation_deg` ([PHYSICS.md §11](PHYSICS.md#11-force-feedback)).
- **Pedals:** response curves, deadzones, brake pressure scale (for load cells).
- **Shifters:** H-pattern gate mapping (one button per gear) and sequential paddles or stick.
- **Button boxes:** any action can be bound.

## 6. Force feedback

*Requirements: INP-05. Signal design in [PHYSICS.md §11](PHYSICS.md#11-force-feedback).*

| Setting | Purpose |
|---|---|
| Overall gain | Master strength |
| Wheel max torque (Nm) | Normalizes forces for belt, gear and direct-drive wheels |
| Effect gains | Road, curbs, slip, collisions, engine |
| Min force | Overcomes the deadband on gear and belt wheels |
| Damping, friction | Added weight and smoothness |
| Smoothing | Filters noise on direct-drive wheels |
| Invert | Fixes reversed devices |
| Clipping meter + test button | Tuning aids |

**Platform support:**

| OS | Status | Notes |
|---|---|---|
| **Windows** | Required | DirectInput FFB through SDL3 |
| **Linux** | Required | Kernel evdev FF through SDL3 (see below) |
| **macOS** | Best effort | Few wheels have macOS FFB drivers. Supported devices are listed as they're confirmed. |

### Linux notes (documentation only; the game makes no system changes)

| Wheel | Kernel driver |
|---|---|
| Logitech G29 / G920 / G923 | `hid-logitech-hidpp`; `new-lg4ff` for fuller effects |
| Thrustmaster | `hid-tmff2` (out-of-tree) |
| Fanatec | `hid-fanatecff` (out-of-tree) |
| Many direct-drive wheels (e.g. Moza, Simagic) | `hid-pidff` / universal PIDFF drivers |

- **Permissions:** read and write access to `/dev/input/event*` (and `hidraw` for some devices) may need a udev rule.
- **Steam Input** may capture wheels and should be turned off for them.

## 7. Profiles and presets

*Requirements: INP-06.*

- **Per-player profiles** in `user://profiles/`: bindings, curves, FFB, assists, preferred cameras.
- **Device presets** in `data/input_presets/*.json`, matched by USB VID/PID. Community-contributed. Initial targets:
  - Wheels: Logitech G29/G920/G923; Thrustmaster T150/T248/T300/TX; Fanatec CSL DD / GT DD Pro; Moza R5/R9/R12; Simagic; Simucube; Cammus.
  - Controllers: Xbox, PlayStation, Switch Pro, Steam Deck.
- **Full rebinding** of every action on every device (NFR-08).

## 8. Assists (summary)

ABS, TCS, stability control, steer aid, auto-clutch, automatic gearbox and racing line ([PHYSICS.md §8](PHYSICS.md#8-steering-and-assists)).
- **Defaults by device:** keyboard and controller default to steer aid, auto-clutch and the automatic gearbox. Wheels default to none of those.
- What can be enabled is limited by the platform, mode and server rules.
- **Access assists** (auto-throttle, brake and steering assist), hold/toggle and one-handed presets: [ACCESSIBILITY.md §5](ACCESSIBILITY.md#5-motor-and-input).
