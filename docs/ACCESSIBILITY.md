# Accessibility

Everyone should be able to drive. This doc covers options for vision, hearing, motion comfort, motor and input, and pacing. Requirements: ACC-01…ACC-09, NFR-08.

**Built so far:**
- M1: comfort options, accessible names and focus order.
- M3: every setting per player in their profile (ACC-01). From ACC-02: HUD size 50–200% and menu text 100–200%, high-contrast HUD, the Clear font (Atkinson Hyperlegible), brightness per view. From ACC-06: hold or toggle, one-handed layouts (`pad_left_hand`, `pad_right_hand`; `kb_left` and `kb_right` for one hand on the keyboard), two devices driving one car, menus with directions + confirm + cancel only (choices step with left and right), adjustable menu repeat.
- M4: colourblind palettes (Default, Deuteranopia, Protanopia, Tritanopia, Custom) checked by simulation; narration through the OS text-to-speech for menus and race events; spotter with markers or voice; captions for every spoken line; volume groups and mono; shift light under 3 flashes a second, slip indicator, close-car arrows; HUD presets and per-element hiding; Reduce flashing; access assists (auto-throttle, brake assist, steering assist, autodrive); game speed; the first-boot screen; screen readers follow menus inside players' views; boot → race → results checked over AT-SPI (`tools/a11y_check.py`) and keyboard-only and controller-only by tests.
- M7: police light bars drawn twice, so each player sees the full pattern or, with Reduce flashing, at most three flashes a second at lower contrast (D116; a test samples it at 1 kHz); sirens on the sound arrows; the heat meter in pips and words; banked and lost points, heat, busted and evaded read out and captioned; name plates over other players' cars; the highway menus and the Ramps tool named and in the focus order.
- Not yet: rewind, haptic cue patterns, audio-only racing (§10); flashing kart items (M8).

---

## 1. Principles

- **Per player.** Every setting is saved in the player's profile (`user://profiles/`) and follows that player. In splitscreen, each viewport uses its own player's settings (ACC-01).
- **Available from the start.** On first boot an accessibility screen opens before any other menu (§7). The same settings are in the pause menu mid-session.
- **Servers can't restrict them.** Settings that only change what you see, hear or press are never sent to a server and can't be turned off by one. Only options that change how the car drives (§5.2) follow assist rules.
- **Never color alone, never sound alone.** Every color cue also has a shape, icon or text. Every important sound also has a visual cue.
- **Short text** (NFR-06) helps everyone, including screen-reader users and translated play.

## 2. Vision

*Requirement: ACC-02, ACC-03.*

| Feature | Details |
|---|---|
| Colorblind palettes | Presets for deuteranopia, protanopia and tritanopia, plus custom colors. Covers UI states, delta, flags, racing line, heat and item slots. |
| Non-color cues | Delta shows `+`/`−`. Flags show an icon and a word ("Yellow", "Blue"). The racing line adds chevrons in braking zones. Minimap players are numbered. |
| HUD and text scale | HUD 50–200% per viewport. Menu text 100–200%. |
| High-contrast HUD | Solid backplates behind HUD text and thicker outlines on markers. |
| Font | The retro theme font, or a plain high-legibility font (Atkinson Hyperlegible, OFL). |
| Brightness and gamma | Per viewport. Helps at night and in fog. |
| Retro effects | Scanlines, dithering and downsampling are off by default ([ART_AUDIO.md §2](ART_AUDIO.md#2-retro_ps2-style-profile-default)). |
| Screen reader | Menus expose names, roles and values through Godot's AccessKit support (4.5+): Narrator and NVDA on Windows, VoiceOver on macOS, Orca on Linux. |
| Narration | Optional built-in speech through the OS text-to-speech (Godot `DisplayServer.tts_speak`). Reads menus and, if wanted, race events: "P3", "Final lap", "Busted". |
| Spotter | Optional voice callouts: "Car left", "Car right", "Three wide", "Clear". Useful for everyone, essential for low vision. |

**Build rule (from M1):** every UI control gets an accessible name and description, and focus order is set by hand. Retrofitting this later is far more work.

**Linux note (documentation only; the game makes no system changes):** narration needs `speech-dispatcher`, and screen reading needs Orca with AT-SPI. Most desktops ship both. The game prints which voice it uses ("Speech: …") at startup; without one, captions still show.

**Menus inside players' views** (pause, player cards): Godot tells the screen reader about one focused control per window, so two proxy controls in the main window stand in for the view's focused control while a screen reader runs (D72).

## 3. Hearing

*Requirement: ACC-05.*

| Feature | Details |
|---|---|
| Volume groups | Master, own engine, other engines, tires, effects, ambience, music, UI, spotter and narration |
| Mono audio | Downmixes everything to mono, for hearing in one ear or a single speaker |
| Shift light | RPM bar flash and shift light, for players who shift by ear |
| Slip indicator | Tire icons light up when sliding or locking, matching the squeal |
| Sound direction | Edge-of-screen arrows for police sirens, horns, close cars and incoming kart items (Seeker, Leader Hunter) |
| Captions | Every spoken line (spotter, narration) is also shown as text. No information is voice-only. |
| Chat | Online chat is text-only ([NETWORKING.md](NETWORKING.md)) |

## 4. Motion comfort and flashing

*Requirement: ACC-04.*

| Feature | Details |
|---|---|
| Camera shake | 0–100%: collisions, curbs, speed rumble |
| Head movement | Cockpit g-force head movement 0–100% ([ART_AUDIO.md §4](ART_AUDIO.md#4-cameras)) |
| Horizon lock | Chase and cockpit cameras keep the horizon level (no roll) |
| Speed FOV | Speed-based FOV change can be turned off. FOV is fixed per camera. |
| Motion blur | None in `retro_ps2`. Every future style profile must have an off switch. |
| Reduce flashing | Caps flashes at 3 per second and lowers their contrast (WCAG 2.3.1). Covers police lights, lightning, boost and item effects (EMP, Shield) and countdown lights. |

The first-boot screen includes a short photosensitivity notice.

## 5. Motor and input

*Requirements: ACC-06, ACC-07. Device details: [INPUT.md](INPUT.md).*

### 5.1 Controls

| Feature | Details |
|---|---|
| Full rebinding | Every action on every device, including menus ([INPUT.md §7](INPUT.md#7-profiles-and-presets)). Gap: the track editor's own shortcuts can't be rebound yet (D103); every one of them is also a button in its panel. |
| Hold or toggle | Every hold action can be a toggle: throttle, brake, handbrake, look back, free look, throw back, scoreboard |
| One-handed presets | Controller left-hand, controller right-hand and one-hand keyboard, in `data/input_presets/` |
| Analog tuning | Deadzones, curves and sensitivity on every axis. Smoothing turns digital inputs (keys, switches) into steady analog values. |
| Two devices, one car | "Add device" ([INPUT.md §3](INPUT.md#3-joining-and-device-assignment)) lets two devices drive one car at once, e.g. the player steers with an adaptive controller while a helper handles pedals. Axes combine: the larger value wins. |
| Adaptive controllers | The Xbox Adaptive Controller and similar devices show up as standard controllers. Switches can be bound to any action. |
| Menus | Fully usable with directions, confirm and cancel only. A mouse is never required. Repeat delay and rate are adjustable. |
| No mashing, no timers | No action needs rapid repeated presses. Menus never time out. |

### 5.1b Track editor (M6)

The editor works with a mouse, the keyboard alone, or a controller (D95):
- **Crosshair:** with keys or a controller the view works round a crosshair in its middle (move, turn, zoom). Grabbing and dropping is a toggle, never a hold, and brushes are switched on and off ("Brush on").
- **Everything is also in the panel:** every view action has a button ("Add point at cursor", "Start at cursor", "Place at cursor", Previous and Next, Delete), and every value a field. Tab, F6 or B moves between the view and the panel.
- **Spoken status:** what each action did ("Point 4 picked up", "Undone: Move point", "Not a road surface") goes to a status line read out politely; the Check tab says how many problems there are, and each problem is a button that shows where it is.
- **Colour is never alone:** points, pins, the AI line and grid boxes are told apart by shape and label as well as colour.

### 5.2 Driving assists for access

These build on the standard assists (steer aid, ABS, TCS, stability, auto-gearbox, auto-clutch, [PHYSICS.md §8](PHYSICS.md#8-steering-and-assists)). They follow the track's AI line, or the lanes on highway and endless roads.

| Assist | Effect |
|---|---|
| Auto-throttle | Holds the AI line's target speed. You steer. |
| Brake assist | Brakes for corners and slow traffic ahead. Strength 0–100%. |
| Steering assist | Follows the AI line. You control speed. Strength 0–100%, so it can just nudge. |
| Item assist (kart) | Uses your item at a good moment |
| Autodrive | All of the above. The car drives itself (already in endless). |

- **Rules:** these change driving, so they are allowed and defaulted per platform, then mode, then server, like every other assist ([PLATFORMS.md §3](PLATFORMS.md#3-mode-overrides-and-tuning)). They are allowed by default in single player, local play, cruise and endless.
- **Results** and leaderboard entries show which assists were on.

## 6. Pacing and clarity

*Requirement: ACC-08.*

| Feature | Details |
|---|---|
| Pause | Pause at any time in single player and local play. Online sessions can't pause. |
| Game speed | 50–100% sim speed in offline single player. Those results don't count toward leaderboards. |
| HUD presets | Full, Minimal, Off. Any HUD element can be hidden on its own. |
| Navigation | Checkpoint arrows on highway runs. "Wrong way" warnings in every mode. |
| Difficulty | AI skill 0–100, traffic density, police on/off ([GAMEMODES.md §0](GAMEMODES.md#0-common-to-all-modes)) |

## 7. First boot

*Requirement: ACC-09.*

1. **Accessibility screen**, before anything else. It is narrated if the OS screen reader is running, or after any key press.
2. **Quick presets** set sensible defaults in one step: Vision, Hearing, Motion, One-handed, Minimal input. They can be combined and fine-tuned later.
3. **Photosensitivity notice** with a one-press "Reduce flashing" toggle.

Each new local player who joins (press-to-join, [INPUT.md §3](INPUT.md#3-joining-and-device-assignment)) can open the same screen for their own profile.

## 8. Splitscreen and online

- **Per viewport:** HUD scale, palette, camera, shake, flashing and brightness follow that viewport's player.
- **Shared menus** (primary window) use P1's font and the largest text size of any joined player (M3; the game can't tell which player is navigating a shared menu).
- **One audio output:** in local play, audio settings (volumes, mono, spotter) are shared and any player can change them.
- **Online:** presentation and input settings stay local. Only assist use is sent, for rules and results (M5).
- **Online menus (M5):** Online, Host and the lobby follow the menu rules (names, descriptions, focus order set by hand, directions and confirm are enough). Text fields wait for confirm before taking typing, so up and down still move between rows. New chat lines are announced to screen readers (a live region) and read out with menu narration; in a session they're captions and are read with race narration. Controller players have quick chat lines.

## 9. Testing

- **Every milestone:** the main flow works with controller only and with keyboard only.
- **From M4:** the main flow (boot → race → results) works with a screen reader.
- **Colorblind check:** a test simulates each palette's colour vision (Machado 2009) and requires the colours that must differ to stay apart (CIE76 ΔE ≥ 20). For review, `tools/cvd_shots.gd` turns screenshots (taken with a display; headless can't render) into deuteranopia, protanopia and tritanopia versions.
- **Screen reader:** `tools/a11y_check.py` walks boot → race → results over AT-SPI in a private session (accessible names, focus on every screen). From M5 it also walks Online → Host → lobby, and from M6 the track editor: every tool, a new oval's race setup and checks, and out (`--editor-only` for just that). From M7: Highway → a highway → its menu → the class → Players and back out a screen at a time (focus on each), the highway editor's Ramps tool, and a highway session's pause menu (opened with `--pause-at`) with Join a friend (`--highway-only` for those). The test drive and back are covered by unit tests: AT-SPI can't send the driving keys here (on Wayland, no keys at all). Known: menus left open behind the current one (and the title's buttons) are still reported to screen readers as on screen; focus stays on the current menu, but a screen reader's review mode could reach them. The walk presses the newest screen's Back for that reason.
- **Flash check:** with Reduce flashing on, police lights (M7) and kart items (M8) stay at or under 3 flashes per second.
- **Feedback:** once the GitHub repo exists, issues get an `accessibility` label.

## 10. Later

| Extra | Notes |
|---|---|
| Rewind | Single player: rewind a few seconds after a mistake (M10+) |
| Haptic cues | Controller rumble patterns for shift points and spotter warnings |
| Audio-only racing | Spotter, beacons and line cues detailed enough to race without sight. Research item. |
