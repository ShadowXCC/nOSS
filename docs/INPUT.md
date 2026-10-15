# Input

Keyboard, controller and sim rigs are all first-class. Requirements: INP-01…INP-07, LOC-04.

---

## 1. Actions

Each local player has their own set of actions:

| Group | Actions |
|---|---|
| Driving | `steer` (−1…1), `throttle`, `brake`, `clutch`, `handbrake` (0…1) |
| Gears | `shift_up`, `shift_down`, `gear_r`, `gear_n`, `gear_1`…`gear_7` (H-shifter) |
| View | `camera_next`, `look_left`, `look_right`, `look_back`, `free_look` (mouse or right stick) |
| Car | `horn`, `lights`, `reset_car`, `hotswap_menu` |
| Kart | `use_item`, `throw_back` (hold), `drift` |
| UI | `pause`, `chat`, `scoreboard`, `confirm`, `cancel`, `editor_back` (a test drive back to the track editor, M6) |

**Defaults** come from presets (§7); every action, menus included, can be rebound per player on every device.

| Action | Keyboard (whole) | Keyboard left side | Keyboard right side | Controller |
|---|---|---|---|---|
| Steer | ← → / A D | A D | ← → | Left stick |
| Throttle, brake | ↑ ↓ / W S | W S | ↑ ↓ | Right, left trigger |
| Handbrake | Space | Space | / | A |
| Shift up, down | E, Q | E, Q | `.`, `,` | RB, LB |
| Camera | C | C | ; | Y |
| Look back | B | X | ' | R3 |
| Reset car | R | R | ] | View |
| Change car | Tab | Tab | [ | D-pad up |
| Pause | Esc | Esc | Backspace | Start |
| Back to editor (test drives) | F5 | F5 | F8 | D-pad down |
| Horn, flash lights (M7) | H, L | V, T | M, L | L3, X |
| Menu confirm, back | Enter or Space, Esc or Backspace | Space or F, Esc or G | Enter, Backspace | A, B |
| Frame rate | F3 (any keyboard) | | | — |

One-handed controller layouts (`pad_left_hand`, `pad_right_hand`) put driving on one half of the pad; reset, change car and back to editor are then in the pause menu, and the horn and lights are unbound (D119). No two driving actions share an input on any preset (a test checks it).

The **track editor** has its own controls for its view (mouse, keyboard or controller with a crosshair; [TRACK_EDITOR.md §2](TRACK_EDITOR.md#2-editor-tools)). They can't be rebound yet (D103).

## 2. Input sources

| Devices | Path |
|---|---|
| Keyboard, mouse | Godot `InputMap` |
| Standard controllers (Xbox, PlayStation, Switch Pro, Steam Deck…) | Godot joypads (SDL3-based in 4.5+) |
| Wheels, pedals, shifters, handbrakes, button boxes | **`noss_core` native SDL3 joystick**: all axes at full resolution, any number of buttons, plus **haptics** for FFB |

**Risk** (tracked in [DECISIONS.md](DECISIONS.md)): Godot's built-in SDL3 and our SDL3 may both try to open the same wheel.
- **M1 spike:** confirm they can coexist.
- **Fallback:** the native layer owns wheel-class devices exclusively, and Godot ignores them, filtered by GUID.

**Spike result (M1, D35):** the fallback became the design. `noss_core` loads SDL3 at runtime and opens only non-gamepad devices, with HIDAPI off. Godot keeps gamepads, and its gamepad buttons only listen to the chosen gamepad, so wheel buttons can't trigger actions. Godot doesn't export its own SDL symbols, so both copies run in one process. Confirmed on Linux (system SDL 3.4.2) with a gamepad attached, and on Windows under Wine (bundled SDL 3.4.18). Wheel FFB still needs a test on real hardware.

## 3. Joining and device assignment

*Requirements: LOC-04. Built in M3 (D54, D55).*

- **Players screen:** "Press any button to join". The first press on a free device claims the next player slot (Esc, Backspace, B, View and Guide never join; with nobody joined they go back). Each player then sets up their own card with their own device: profile, car, keyboard side, monitor, settings, Ready. Everyone ready starts the drive.
- **Mid-drive:** a free controller or wheel joins by pressing a button; the views re-flow. Leave in your pause menu drops out.
- **Combining devices:** "Add device" on a card claims the next device pressed, e.g. a wheel plus separate pedals, or a second controller for a helper (two devices, one car; the larger value wins).
- **Remembered assignments:** which profile each device belongs to, by GUID, in `user://players.json`. A remembered device joins with its profile.
- **Shared keyboard:** the keyboard joins whole. To share it, set that player's Keyboard to Left side (or Right side); the other side then joins like any free device. The two sides share no keys. Godot can't tell two keyboards apart, so each player needs separate keys.
- **Garage and Fitting Bay drives** are single-player: P1 drives with the keyboard, the first controller and every wheel or pedal set.
- **Mouse steering** (not built yet) will only be available to one player (there's one mouse).

## 4. Keyboard and controller

### Keyboard (INP-01)
- **Steering:** digital steering with smoothing. Rise and fall rates depend on speed. Counter-steer returns faster.
- **Mouse steering (optional):** horizontal mouse movement sets steering position, with optional auto-centering.

### Controller (INP-02)
- **Sticks:** inner and outer deadzone, linearity curve, speed-sensitive steering reduction, steering smoothing.
- **Triggers:** throttle and brake, with their own deadzones and curves.
- **Rumble** (Godot `start_joy_vibration`): tire slip, ABS, curbs, collisions. Strength per player (Settings → Controller rumble), M4.
- **Shared menus** (title, results) take the D-pad or stick, A to confirm and B to go back (D77).

## 5. Wheels, pedals, shifters

*Requirements: INP-03, INP-04.*

- **Calibration wizard:** wheel center and full lock. Pedal min and max, inverted pedals, combined-axis pedals. Handbrake axis or button. *M1: Settings → Wheel setup picks the device and detects each axis by moving it (steering from centre to full lock, pedals fully pressed). Rest and full positions are stored, so inverted pedals just work. Saved per player by device GUID. M3: detection looks at all of the player's wheels and pedals, so pedals on their own USB device work; each axis remembers its device.*
- **Rotation range:**
  - Set the wheel's hardware range in settings.
  - The game applies a **soft lock** that matches the platform's `steering.wheel_rotation_deg` ([PHYSICS.md §11](PHYSICS.md#11-force-feedback)).
- **Pedals:** response curves, deadzones, brake pressure scale (for load cells).
- **Shifters:** H-pattern gate mapping (one button per gear: bind Gear 1…7, Reverse, Neutral in Buttons and keys; the gate held selects that gear, no gate is neutral) and sequential paddles or stick. A clutch pedal or button can be bound too.
- **Handbrakes:** a lever on any of the player's devices: detect it in Wheel setup, or bind it in Buttons and keys.
- **Button boxes:** any action can be bound. Hats (and D-pads on button boxes) read as four extra buttons each, after the device's own.
- **Binding axes:** rebinding picks up a pedal or lever moved on any sim device and remembers where it rests, so it reads 0–1 over its travel.
- *M4: built and unit-tested with faked devices; a test on real hardware is deferred like the wheel (no hardware).*

## 6. Force feedback

*Requirements: INP-05. Signal design in [PHYSICS.md §11](PHYSICS.md#11-force-feedback).*

| Setting | Purpose |
|---|---|
| Overall gain | Master strength |
| Wheel max torque (Nm) | Normalizes forces for belt, gear and direct-drive wheels |
| Effect gains | Road, curbs, slip, collisions, engine, low-speed centering |
| Min force | Overcomes the deadband on gear and belt wheels |
| Damping, friction | Added weight and smoothness |
| Smoothing | Filters noise on direct-drive wheels |
| Invert | Fixes reversed devices |
| Clipping meter + test button | Tuning aids; the test plays each effect in turn |

All of these are in the player's Wheel setup (M4). Effects are mixed natively at ~500 Hz into one constant force (D76).

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

*Requirements: INP-06. Built in M3 (D54).*

- **Per-player profiles** in `user://profiles/<id>.json` (version 2): name, input presets and overrides, hold or toggle, menu repeat, curves, wheel calibration and FFB, assists, cameras, HUD and comfort options, last car. M1/M2 profiles are migrated on load.
- **Presets** in `data/input_presets/*.json` (`noss.input_preset/1`, schema `data/schemas/input_preset.schema.json`): the default bindings for one kind of device.
  - Keyboard: `kb_full`, `kb_left`, `kb_right`.
  - Controller: `pad_standard`, `pad_left_hand`, `pad_right_hand`.
  - Sim devices: `sim_generic`, which binds no buttons.
  - Refs name keys (`"W"`), buttons (`"a"` or a number) and axis directions (`{"axis": "left_x", "dir": -1}`).
- **Device presets** add `match` (USB vendor and product ids) and, for wheels, calibration (`rotation_deg`, steering and pedal axes). They're picked automatically for matching devices. Community-contributed; a preset is marked `verified` once tested on the real device. Initial targets:
  - Wheels: Logitech G29/G920/G923; Thrustmaster T150/T248/T300/TX; Fanatec CSL DD / GT DD Pro; Moza R5/R9/R12; Simagic; Simucube; Cammus.
  - Controllers: Xbox, PlayStation, Switch Pro, Steam Deck.
  - None are shipped yet: their axis layouts need checking on hardware.
- **Full rebinding** of every action on every device (NFR-08): Settings → Buttons and keys. Pick the device, then the action, then press the new input on that device. Overrides are saved per preset, and per device for wheels and pedals. On a shared keyboard the other side's keys can't be taken.

## 8. Assists (summary)

ABS, TCS, stability control, steer aid, auto-clutch, automatic gearbox and racing line ([PHYSICS.md §8](PHYSICS.md#8-steering-and-assists)).
- **Defaults by device:** keyboard and controller default to steer aid, auto-clutch and the automatic gearbox. Wheels default to none of those. *M4: these three are Auto / On / Off; Auto follows the device (auto-clutch: off with a clutch pedal or binding).*
- What can be enabled is limited by the platform, mode and server rules.
- **Access assists** (auto-throttle, brake and steering assist), hold/toggle and one-handed presets: [ACCESSIBILITY.md §5](ACCESSIBILITY.md#5-motor-and-input).
