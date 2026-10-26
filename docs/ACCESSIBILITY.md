# Accessibility

Everyone should be able to drive. This doc covers options for vision, hearing, motion comfort, motor and input, and pacing. Requirements: ACC-01…ACC-09, NFR-08.

**Built so far:**
- M1: comfort options, accessible names and focus order.
- M3: every setting per player in their profile (ACC-01). From ACC-02: HUD size 50–200% and menu text 100–200%, high-contrast HUD, the Clear font (Atkinson Hyperlegible), brightness per view. From ACC-06: hold or toggle, one-handed layouts (`pad_left_hand`, `pad_right_hand`; `kb_left` and `kb_right` for one hand on the keyboard), two devices driving one car, menus with directions + confirm + cancel only (choices step with left and right), adjustable menu repeat.
- M4: colourblind palettes (Default, Deuteranopia, Protanopia, Tritanopia, Custom) checked by simulation; narration through the OS text-to-speech for menus and race events; spotter with markers or voice; captions for every spoken line; volume groups and mono; shift light under 3 flashes a second, slip indicator, close-car arrows; HUD presets and per-element hiding; Reduce flashing; access assists (auto-throttle, brake assist, steering assist, autodrive); game speed; the first-boot screen; screen readers follow menus inside players' views; boot → race → results checked over AT-SPI (`tools/a11y_check.py`) and keyboard-only and controller-only by tests.
- M7: police light bars drawn twice, so each player sees the full pattern or, with Reduce flashing, at most three flashes a second at lower contrast (D116; a test samples it at 1 kHz); sirens on the sound arrows; the heat meter in pips and words; banked and lost points, heat, busted and evaded read out and captioned; name plates over other players' cars; the highway menus and the Ramps tool named and in the focus order.
- M8: kart item effects (drift sparks, boost flame, shield, EMP ring) drawn twice through `Flash`, so Reduce flashing keeps each under 3 flashes a second and above 35% (D146; a test samples every effect at 1 kHz); the item roulette says "Rolling" instead of cycling names; item slots in palette colours plus the item's name, drift tiers as pips and a word, battle lives as pips and a number; incoming Seekers and the Hunter on the edge arrows and read out; item, hit, shield, tow and battle news ("Lost a life", "Out", "Winner") captioned and read out; the item assist; the Kart menus, cup builder and standings, and the Stunts tool named and in the focus order (`tools/a11y_check.py --kart-only`).
- Not yet: rewind, haptic cue patterns, audio-only racing (§10).

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
| Reduce flashing | Caps flashes at 3 per second and lowers their contrast (WCAG 2.3.1). Covers police lights, lightning, boost and item effects (EMP, Shield), countdown lights and the sumo warning band (D182: it pulses twice a second, and holds steady and dimmer with this on). An endless road's speed cameras (D193) don't flash at all while any player on the PC has it on. Lightning (M9, D153) becomes one soft pulse at most a third as bright (at most one a second) and its bolt isn't drawn; it's per view, so a splitscreen player without the option still sees the full flicker. |

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
| Menus | Fully usable with directions, confirm and cancel only. A mouse is never required. Repeat delay and rate are adjustable. Settings and Driving Settings are in tabs ([UI_FLOW.md](UI_FLOW.md) §9): LB and RB (Q and E; a player's own Previous and Next tab) switch from anywhere on the page, and left and right on the tab row do too, so a layout with no Previous tab (the left-hand pad) still gets round. The page scrolls to the focus on every device and in every player's view, and a help line at the bottom shows the focused setting's description. |
| Button prompts | Each page ([UI_FLOW.md](UI_FLOW.md) §4) ends in a prompt bar: what confirm, back and left/right do there, with the glyphs of the device last used (keyboard, Xbox or PlayStation). In splitscreen each player's prompts show their own device and their own bindings, so a left-hand pad shows LB for confirm. A wheel's buttons, or any input without a glyph, show as their name in a box ("Button 3"). Every glyph is named for screen readers. |
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
| Autodrive | All of the above. The car drives itself. On endless roads it's on hand from the pause menu or the Autodrive key (M9). |

- **Rules:** these change driving, so they are allowed and defaulted per platform, then mode, then server, like every other assist ([PLATFORMS.md §3](PLATFORMS.md#3-mode-overrides-and-tuning)). They are allowed by default in single player, local play, cruise and endless.
- **Results** and leaderboard entries show which assists were on.

## 6. Pacing and clarity

*Requirement: ACC-08.*

| Feature | Details |
|---|---|
| Pause | Pause at any time in single player and local play. Online sessions can't pause. |
| Game speed | 50–100% sim speed in offline single player. Those results don't count toward leaderboards. |
| HUD presets | Full, Minimal, Off. Any HUD element can be hidden on its own. Endless shows the speed, gear and RPM bar until you hide them from the pause menu (D189); captions and messages always show (M9). With speed traps or police on, the limit shows by the speedometer as a road sign with its number in your units, which a screen reader reads as "Limit 50 mph" (D193). Name tags over other players' cars are an element too: Off hides them, Minimal keeps them (D199). |
| Navigation | Checkpoint arrows on highway runs. "Wrong way" warnings in every mode. |
| Pit stops (D210) | The pit panel says it in words ("Pit: Full · 4 tires", "Locked · Box 120 m", "Service 8.1", "Go"), as a polite live region; each change ("Pit: Finish · 2 tires", "Locked", "Go") is spoken with race narration and captioned. The lane's limiter does the speed for you, and the limit sign shows the pit road's limit while it holds. The service can also be set in the pause menu, so no extra buttons are needed. |
| Difficulty | AI skill 0–100, traffic density, police on/off ([GAMEMODES.md §0](GAMEMODES.md#0-common-to-all-modes)) |

## 7. First boot

*Requirement: ACC-09.*

1. **Accessibility screen**, before anything else. It is narrated if the OS screen reader is running, or after any key press.
2. **Quick presets** set sensible defaults in one step: Vision, Hearing, Motion, One-handed, Minimal input. They can be combined and fine-tuned later.
3. **Photosensitivity notice** with a one-press "Reduce flashing" toggle.

Each new local player who joins (press-to-join, [INPUT.md §3](INPUT.md#3-joining-and-device-assignment)) can open the same screen for their own profile.

## 8. Splitscreen and online

- **Per viewport:** HUD scale, palette, camera, shake, flashing and brightness follow that viewport's player.
- **Who's who (D199):** a name tag over each other player's car pairs their colour with their name (never colour alone, §1). It follows the viewing player's HUD size, font and high contrast (a solid plate that fades less).
- **Shared menus** (primary window) use P1's font and the largest text size of any joined player (M3; the game can't tell which player is navigating a shared menu).
- **One audio output:** in local play, audio settings (volumes, mono, spotter) are shared and any player can change them.
- **Online:** presentation and input settings stay local. Only assist use is sent, for rules and results (M5).
- **Online menus (M5):** Online, Host and the lobby follow the menu rules (names, descriptions, focus order set by hand, directions and confirm are enough). Text fields wait for confirm before taking typing, so up and down still move between rows. New chat lines are announced to screen readers (a live region) and read out with menu narration; in a session they're captions and are read with race narration. Controller players have quick chat lines.

## 9. Testing

- **Every milestone:** the main flow works with controller only and with keyboard only.
- **From M4:** the main flow (boot → race → results) works with a screen reader.
- **Colorblind check:** a test simulates each palette's colour vision (Machado 2009) and requires the colours that must differ to stay apart (CIE76 ΔE ≥ 20). For review, `tools/cvd_shots.gd` turns screenshots (taken with a display; headless can't render) into deuteranopia, protanopia and tritanopia versions.
- **Screen reader:** `tools/a11y_check.py` walks boot → race → results over AT-SPI in a private session (accessible names, focus on every screen). From M5 it also walks Drive Online → Host → lobby, and from M6 the track editor: every tool, a new oval's race setup and checks, and out (`--editor-only` for just that). From M7: Highway → a highway → its menu → the class → Players and back out a screen at a time (focus on each), the highway editor's Ramps tool, and a highway session's pause menu (opened with `--pause-at`) with Join a friend (`--highway-only` for those). From M8 the kart menus, the cup builder and the Stunts tool (`--kart-only`). From M9 every drive mode is reached through Local Drive (Solo Drive until the UI overhaul, D214), and the walk goes Local Drive → Endless → its menu (the road code, biome, traffic, spread rule and the sky rows) → the class → Players and back out (`--endless-only`). From Mini Games: the Sumo menu (`--sumo-only`) and the Drag Strip menu (`--drag-only`), each through Mini Games to Players and back out. A drag pass says in words whatever its colours show — "Shift now", "Over-revving", "Engine gone", the chain and the bottles left — and names the input the driver is holding rather than a glyph alone (D169), so a prompt reads "Release Space", "A" or "3rd gate" depending on the device. The test drive and back are covered by unit tests: AT-SPI can't send the driving keys here (on Wayland, no keys at all). Since the UI overhaul's page stack (P2, D214), only the screen on top shows: the main menu's buttons and the screens under the current one are hidden, so a screen reader's review mode can't reach them, and the walk checks that on its way into a race. From P3 it also walks Settings → every tab → Players → Driving Settings → every tab and back out (`--settings-only`); the tabs are toggle buttons, named and in the focus order (up from the first row reaches them). From P4 the race goes Local Drive → Racing → Regular → its Settings page → the class → Players, and `--racing-only` walks Stock Car (no class step) to Players and back, then the Time Trial switch (a toggle button) → Regular → the class and back. A long page's Next sits in an action bar under its rows: Godot 4.7.2 leaves a row that starts below the fold out of the screen-reader tree until it's focused (arrowing down reads it; a review mode or the check couldn't reach it). From P5 every Local Drive type is pages: `--highway-only`, `--endless-only`, `--sumo-only`, `--drag-only` (with its Class step) and the new `--free-only` each walk the type's Settings page → the class (where there is one) → Players and back out a page at a time; `--kart-only` walks Kart's race, its cup and the Cup builder, then Mini Games → Kart Battle; `--racing-only` adds Custom and its Save preset page. From P6 time trials have a Players step: `--racing-only` walks Regular's time trial on to Players and Kart's too, and back out. From P7 `--garage-only` walks the Garage's tabs (My cars and Built-in, toggle buttons), the Fitting Bay's Import step with its "From online games" list, Exit back to the Garage, and Back. Building it showed that a screen made inside Godot's own scene change left the first control of a row under a scroll out of the screen-reader tree (the Garage's first tab and first card; the Garage before P7 had the same gap on its first card); the game now puts new screens in itself (ARCHITECTURE §1).
- **Flash check:** with Reduce flashing on, police lights (M7), kart items (M8) and lightning (M9) stay at or under 3 flashes per second.
- **Feedback:** once the GitHub repo exists, issues get an `accessibility` label.

## 10. Later

| Extra | Notes |
|---|---|
| Rewind | Single player: rewind a few seconds after a mistake (M10+) |
| Haptic cues | Controller rumble patterns for shift points and spotter warnings |
| Audio-only racing | Spotter, beacons and line cues detailed enough to race without sight. Research item. |
