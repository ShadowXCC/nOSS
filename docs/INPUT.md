# Input

Keyboard, controller and sim rigs are all first-class. Requirements: INP-01…INP-07, LOC-04.

---

## 1. Actions

Each local player has their own set of actions:

| Group | Actions |
|---|---|
| Driving | `steer` (−1…1), `throttle`, `brake`, `clutch`, `handbrake` (0…1) |
| Gears | `shift_up`, `shift_down`, `gear_r`, `gear_n`, `gear_1`…`gear_7` (H-shifter) |
| View | `camera_next`, `look_back`, free look: `look_left`, `look_right`, `look_up`, `look_down` (0…1; the view turns while held and swings back to the camera when let go) |
| Car | `horn`, `lights`, `reset_car`, `hotswap_menu` |
| Kart | `use_item`, `throw_back` (hold), `drift` (hold) (M8, D135) |
| Mini games | `ram` (sumo: the shove, D164), `boost` (drag: the bottle, D173) |
| UI | `pause`, `chat`, `scoreboard`, `confirm`, `cancel`, `menu_tab_prev`, `menu_tab_next` (tabs on a page, [UI_FLOW.md](UI_FLOW.md) §10.1), `editor_back` (a test drive back to the track editor, M6), `autodrive` (endless: the car drives itself, and back, M9) |

**Defaults** come from presets (§7); every action, menus included, can be rebound per player on every device.

| Action | Keyboard (whole) | Keyboard left side | Keyboard right side | Controller |
|---|---|---|---|---|
| Steer | ← → / A D | A D | ← → | Left stick |
| Throttle, brake | ↑ ↓ / W S | W S | ↑ ↓ | Right, left trigger |
| Handbrake | Space | Space | / | A |
| Shift up, down | E, Q | E, Q | `.`, `,` | RB, LB |
| Camera | C | C | ; | Y |
| Look back | B | X | ' | R3 |
| Free look | — | — | — | Right stick |
| Reset car | R | R | ] | View |
| Change car | Tab | Tab | [ | D-pad up |
| Pause | Esc | Esc | Backspace | Start |
| Back to editor (test drives) | F5 | F5 | F8 | D-pad down |
| Horn, flash lights (M7) | H, L | V, T | M, L | L3, X |
| Kart: drift, use item, throw back (M8) | Space, E, B | Space, E, X | /, `.`, ' | RB, LB, R3 |
| Sumo: ram | E | E | `.` | LB |
| Drag: boost | Space | Space | / | A |
| Autodrive (M9) | O | — | — | — (the pause menu) |
| Pit fuel, pit tires (D210) | F, T | 1, 2 | 9, 0 | D-pad right, left |
| Menu confirm, back | Enter or Space, Esc or Backspace | Space or F, Esc or G | Enter, Backspace | A, B |
| Menu tabs: previous, next | Q, E | Q, E | `,`, `.` | LB, RB |
| Frame rate | F3 (any keyboard) | | | — |

One-handed controller layouts (`pad_left_hand`, `pad_right_hand`) put driving on one half of the pad; reset, change car and back to editor are then in the pause menu, and the horn, lights and free look are unbound (D119). Menu tabs: the left hand has Next tab on L3 and no Previous tab (left and right on the tab row do that), so its confirm is LB alone; the right hand has R3 and RB. In menus the tab keys don't shift: menus don't drive. Pit fuel and pit tires (`pit_fuel`, `pit_tyres`, D210) step the next stop's service on (fuel: Full, Finish, Half, No fuel; tires: 4, 2, none); the pad's D-pad right and left are free in Track mode. Every preset also has them in the pause menu ("Pit fuel", "Pit tires"), which is where the one-handed pads have them.

**Free look:** at full deflection a chase camera orbits up to 120° round the car (up to 10° lower, 25° higher), and the hood, bumper and cockpit views turn up to 100° to the side and 30° up or down. The stick uses the player's stick deadzone, straight. It works with Look back. Keyboards have it unbound; any keys can be bound to it. No two driving actions share an input on any preset (a test checks it), except the kart actions: they share with what kart sessions ignore (handbrake, the shifts, and look back for throw back), so the Kart row above reuses those keys. One-handed pads: drift L3, use item D-pad up, throw back D-pad left (left hand); R3, Y and B (right hand). The wheel preset binds none; bind them yourself. In a kart session the handbrake and shifts do nothing (the karts' gearbox is automatic). A sumo match's **Ram** (D164) shares in the same way: it sits on the shift-up input, since a sumo match has no gearbox to use it. A drag pass's **Boost** (D173) cannot go there — the shifts are its whole game — so it takes the **handbrake** instead, which a pass has no use for either (the hold on the line is the mode's, not the driver's). The same input **skips** a pass of bots while a driver waits their turn (D178), and the **Camera** button cycles what they watch it on (D176); neither does anything to a car that is running.

## 1.1 Prompts that name the input (D169)

A mini-game that asks for a particular input names the one the driver is actually holding rather than saying "press the button". Three things decide it, and nothing new is needed for any of them:

- **Which device** they are on: `VehicleController.active_device` ("keyboard", "gamepad" or "wheel"), kept current from whatever they last steered or pressed.
- **What they have**: `PlayerInput.has_binding` for an action (the `gear_1`…`gear_7` gates mean an H-shifter), and `WheelInput.has_clutch` for a clutch pedal.
- **What to call it**: `Bindings.ref_label` through `PlayerInput.label_for`, which picks the binding on the device in their hands.

So the Drag Strip's launch prompt reads "Release Space" on a keyboard, "Release A" on a pad and "Release the clutch" on a wheel that has one, and its shift prompt names the **gate** ("3rd gate") for anyone with an H-shifter instead of "shift up". `DragPrompts` is the one place that puts those together.

The **track editor** has its own controls for its view (mouse, keyboard or controller with a crosshair; [TRACK_EDITOR.md §2](TRACK_EDITOR.md#2-editor-tools)). They can't be rebound yet (D103).

## 1.2 Menu prompts (UI overhaul)

Every page ends in a prompt bar: what confirm, back, left and right, and the tab keys do there, as
the glyphs of the device in hand (Kenney's Input Prompts, CC0). The main window shows the family of
the device last used (keyboard, Xbox or PlayStation: Sony pads by USB vendor or name, every other
pad Xbox); a player's view shows the device that player last used in a menu, with their own
preset's buttons, so a left-hand pad shows LB for confirm. A wheel's buttons, or any input without
a glyph, show as their name in a box ("Button 3"). Details: [UI_FLOW.md](UI_FLOW.md) §10.2.

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

- **Players screen:** "Press any button to join". The first press on a free device claims the next player slot (Esc, Backspace, B, View and Guide never join; with nobody joined they go back). Each player then sets up their own card with their own device: profile, car, keyboard side, monitor, settings, Ready. Once everyone is ready a 3-second countdown runs in the hint line ("Starting in 3"); anyone un-readying (back on a ready card) or joining stops it, and a leave starts it again from 3 for the rest ([UI_FLOW.md](UI_FLOW.md) §5.7).
- **Online lobby (UI overhaul P9, LOC-05):** local players join in the lobby's "This PC" the same way (press any button on a free device). The window is P1's, as on every page: P1's keys and pad move its focus (the roster, chat, the host's buttons and P1's own rows), while each other player's presses go to their own card (in their own view) and never move the window's; a pad nobody has yet only joins. A card's "Controls" sets the controller's layout, or the keyboard's side so two can share it ([UI_FLOW.md](UI_FLOW.md) §7.5).
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
- **Rumble** (Godot `start_joy_vibration`): tire slip, ABS, curbs, collisions. Strength per player (Driving Settings → Controls → Controller rumble), M4.
- **Shared menus** (the main menu's pages, results) take the D-pad or stick, A to confirm and B to go back (D77).

## 5. Wheels, pedals, shifters

*Requirements: INP-03, INP-04.*

- **Calibration wizard:** wheel center and full lock. Pedal min and max, inverted pedals, combined-axis pedals. Handbrake axis or button. *M1: Wheel setup (Driving Settings → Controls) picks the device and detects each axis by moving it (steering from centre to full lock, pedals fully pressed). Rest and full positions are stored, so inverted pedals just work. Saved per player by device GUID. M3: detection looks at all of the player's wheels and pedals, so pedals on their own USB device work; each axis remembers its device.*
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
- **Full rebinding** of every action on every device (NFR-08): Driving Settings → Controls → Buttons and keys. Pick the device, then the action, then press the new input on that device. Overrides are saved per preset, and per device for wheels and pedals. On a shared keyboard the other side's keys can't be taken.

## 8. Assists (summary)

ABS, TCS, stability control, steer aid, auto-clutch, automatic gearbox and racing line ([PHYSICS.md §8](PHYSICS.md#8-steering-and-assists)).
- **Defaults by device:** keyboard and controller default to steer aid, auto-clutch and the automatic gearbox. Wheels default to none of those. The **Drag Strip allows no automatic gearbox at all** (D169): timing the shifts is the game, so an automatic would play it for you. Auto-clutch stays, and is forced on without a clutch pedal, so a pad or a keyboard drives it fine. *M4: these three are Auto / On / Off; Auto follows the device (auto-clutch: off with a clutch pedal or binding).*
- What can be enabled is limited by the platform, mode and server rules.
- **Access assists** (auto-throttle, brake and steering assist), hold/toggle and one-handed presets: [ACCESSIBILITY.md §5](ACCESSIBILITY.md#5-motor-and-input).
