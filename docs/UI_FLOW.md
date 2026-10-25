# UI flow

The menus and how players move through them: the spec for the UI overhaul (D214, which supersedes
D160). The overhaul is built in phases P0-P11, each in its own session; every phase reads this file
first and builds on the pages the phases before it made. Progress is in
[ROADMAP.md](ROADMAP.md#ui-overhaul).

The text in quotes here is the exact text in the game. Tests and `tools/a11y_check.py` find
controls by it, so a change to a string starts here, then goes to the code and the tests together.

---

## 1. Everywhere

- **Every step is a full-screen page.** Nothing opens as a popup over the main menu.
- **Breadcrumb:** each page shows where you are, the names joined by " › " (U+203A with a space
  each side): "Local Drive › Racing › Regular › Settings".
- **Steps:** a page in an event's flow shows "Step 2 of 4" and the step names in a row, joined by
  " · ", with the current one in the accent colour: "Event · Settings · Class · Players". The
  count follows the type: Stock Car, Kart, Sumo Wrestling and Kart Battle have no Class step.
  Pages outside an event's flow (Drive Online, Join, Garage, Settings) have a breadcrumb and no
  step row.
- **Prompt bar:** a strip at the bottom of each page shows what the buttons do, as glyphs for the
  last-used device (Xbox, PlayStation or keyboard; §10.2). In a player's view it uses that
  player's device. The Players screen keeps its own hints (§5.7).
- **Back:** cancel (Esc, B) goes back one page from anywhere on a page. Pages also keep a "Back"
  button at the bottom for the mouse and for screen readers.
- **One page at a time:** only the page on top is shown. Pages under it are hidden, so a screen
  reader never reads them, and focus comes back to where it was when the page on top closes.
- **The look:** the same colours and theme as today (`UiKit.ACCENT`, `PANEL`, `BUTTON`), with
  bigger text and buttons, more space, and the same layout on every page (§2).
- **Short text** in the game ([CLAUDE.md](../CLAUDE.md)): "Starting in 3", not "The race will
  start in 3 seconds".
- **Names:** the per-player settings are "Driving Settings" everywhere. The main menu is the "main
  menu" in every button and description (never "title").

## 2. Look and sizes

Sizes are in logical pixels at text scale 1.0 (the 1920×1080 canvas). Bigger menu text scales the
whole canvas as today (`Players.menu_text_scale()`).

| Part | Size |
|---|---|
| Main menu buttons | 480×96, 40 px text, 24 px between them |
| Page margins | 64 on every side |
| Breadcrumb | 26 px, muted (`Color(0.62, 0.62, 0.68)`) |
| Step row | 26 px, muted; the current step in the accent colour |
| Page title | 56 px |
| Rows (buttons, spinners, checks, sliders, text fields) | 72 tall, 34 px text |
| Gap between rows | 12 |
| Tab row | 64 tall, 30 px text; the current tab underlined in the accent colour (4 px) |
| Help line (settings) | 26 px, muted, up to 2 lines |
| Prompt bar | 64 tall; glyphs 40 px, labels 26 px; 32 px between entries |
| Right pane (track map, car) | 45% of the body's width; hidden below 1100 px logical width |
| Body without a pane | rows at most 1100 px wide, centred |

- The page background is the main menu's (`Color(0.07, 0.07, 0.09)`), full screen: no dimmed
  backdrop.
- With the pane hidden (text scale 2.0, a small splitscreen view), the body takes the whole width.
- The page theme is a variation in `UiKit` (bigger fonts, the row height); the base theme stays as
  it is for menus not yet moved to pages.

## 3. Main menu

The logo stays on the left with "Bring your own car." under it. The buttons sit on the right, as a
group centred vertically, in this order:

| Button | Node | Description (screen readers) |
|---|---|---|
| "Local Drive" | `LocalDriveButton` | "Races, time trials, endless, highway, mini games and free drive on this PC" |
| "Drive Online" | `DriveOnlineButton` | "Host or join a game over the network" |
| "Garage" | `GarageButton` | "Your cars and the Fitting Bay" |
| "Track Editor" | `TrackEditorButton` | "Build tracks" |
| "Settings" | `SettingsButton` | "Display, sound, splitscreen and players" |
| "Exit Game" | `ExitButton` | "Close nOSS" |

- Focus starts on Local Drive, and down goes through them in the order shown, wrapping.
- At text scale 1.0 all six fit (696 px of 1080). With bigger text they scroll, and the focused
  button is always shown.
- The Fitting Bay is not on the main menu: it opens from the Garage (§8).

## 4. Pages: the shared parts

Built in P2 (`game/ui/page/`) and P3 (tabs).

- **`MenuPage`:** a full-screen page: breadcrumb, step row, title, a scrolling body, an optional
  right pane, and a `PromptBar`. It scrolls to the focused control itself (on
  `gui_focus_changed`), so scrolling follows the focus inside a `PlayerView` too, where
  `follow_focus` doesn't.
- **`MenuStack`:** push and pop. Only the top page is visible. Popping gives the focus back to the
  control that had it.
- **`ConfirmPage`:** a question with the safe answer focused first (promoted from the pause menu's
  `ConfirmMenu`). Its title is the question; its buttons are given (e.g. "Keep" and "Reset").
- **`TabRow`:** a row of tabs (toggle buttons). `ui_tab_prev` and `ui_tab_next` switch tabs from
  anywhere on the page, only while its page is on top and not while a text field is being typed
  in. Left and right on the tab row switch too.
- **`TabbedPage`:** a `MenuPage` with a `TabRow`, a help line at the bottom, and a "Reset to
  defaults" button at the end of each tab that has settings (§9).
- **`TrackPane`:** the right pane on a settings page: the track's map (as the track picker draws
  it), its name, its length in the player's units ("2.44 km", "1.52 mi"), and a line of what it
  is ("Oval · Real-world", "Kart", "Highway").
- **`PromptBar` entries** (glyph, then label):

| When | Entry |
|---|---|
| Always | confirm "Select", cancel "Back" |
| Focus on a spinner | left/right "Change" |
| Focus on a text field | confirm "Type" |
| A tabbed page | tab prev/next "Tabs" |
| The Racing page | tab prev/next "Race / Time Trial" |

## 5. Local Drive

### 5.1 The flow

Event type → the event's settings → the class (only if needed) → the players.

| Context | Steps |
|---|---|
| Local Drive | "Event · Settings · Class · Players" |
| Hosting | "Host · Event · Settings · Class · Lobby" |
| Changing the event from the lobby | "Event · Settings · Class · Lobby" |

The Class step drops out when the class is fixed (Stock Car, Sumo Wrestling) or picked on each
player's card (Kart, Kart Battle). The Event step covers the event type page and, for Racing and
Mini Games, the page after it. On the event type pages, before a type is picked, the step row
shows the steps of the focused type.

### 5.2 Event type page

Title "Local Drive", breadcrumb "Local Drive".

| Button | Description |
|---|---|
| "Drive again" | what it repeats, as "Regular race · Piedmont Speedway · GT" |
| "Racing" | "Races and time trials: Regular, Stock Car, Kart and Custom" |
| "Endless" | "A calm drive down a road that never ends" |
| "Highway" | "Cruise, score attack, runs and laps through traffic" |
| "Mini Games" | "Sumo Wrestling, Drag Strip and Kart Battle" |
| "Free Drive" | "Any class on any track" |
| "Back" | "Back to the main menu" |

- **Drive again** shows only when there is a last event and its track and class still exist. It
  repeats the last type, settings and class, and goes straight to the Players page; Back from
  there comes to that event's Settings page.
- Focus starts on the first button (Drive again when it's there).

### 5.3 Racing page

Title "Racing", breadcrumb "Local Drive › Racing". A **Race | Time Trial** switch sits above the
four types: a `TabRow` with "Race" and "Time Trial". LB/RB (Q/E) switch it from anywhere on the
page, and left/right on the switch itself. The descriptions follow the switch:

| Button | Race | Time Trial |
|---|---|---|
| "Regular" | "Laps against AI, simple settings" | "Laps against your ghost" |
| "Stock Car" | "Pack racing on ovals: drafting, fuel and tires" | "Hot laps of an oval" |
| "Kart" | "Kart races and cups with items" | "Kart laps against your ghost" |
| "Custom" | "Every setting, any class, saved presets" | "Any class, any circuit, your ghost" |
| "Back" | "Back to Local Drive" | "Back to Local Drive" |

"NASCAR" is a trademark: the type is "Stock Car" everywhere in the game.

### 5.4 Mini Games page

Title "Mini Games", breadcrumb "Local Drive › Mini Games".

| Button | Description |
|---|---|
| "Sumo Wrestling" | "Shove the others off a shrinking platform" |
| "Drag Strip" | "Time the lights, the shifts and the bottle" |
| "Kart Battle" | "Items in an arena" |
| "Back" | "Back to Local Drive" |

### 5.5 Settings page

Title: the event's name (§6), breadcrumb ending "› Settings". The rows on the left (each one a
spinner, check, text field or button as today), the `TrackPane` on the right for types with a
track. The **Track** row steps through the tracks in place: there is no separate track picker.

At the bottom: "Next" and "Back". Next's description says what comes next: "Pick the class",
"The players: each picks a car", "The players: each picks a car and a class", or, when hosting
with no Class step, Next reads "Start hosting" ("Start the server and open the lobby").

The rows of each type are in §6.1. Rows keep today's names and values unless §6.1 says otherwise.

### 5.6 Class page

Title "Choose class", breadcrumb ending "› Class".

- The class list on the left, the classes of the type (§6), each row "Name   description" as
  today. A row's accessible name is "<Mode> <Class>" ("Track GT", "Highway Street"), with ", last
  used" on the last one used. The list scrolls to follow the focus (the Free Drive bug in
  Changes.md).
- On the right, P1's last car on a turntable, fitted to the highlighted class. A car that can't
  fit the class (`Fitting.compatible`) shows the class's default car (`GameModes.default_car`).
  The fit waits about 150 ms after the focus stops moving.
- Confirm on a class goes on: to Players, to the lobby when hosting (it hosts), or straight to
  the drive for a time trial before P6.
- At the bottom: "Back".

### 5.7 Players page

The Players screen stays as it is (a redesign is out of scope), but the start changes: once
everyone is Ready, a **3-second countdown** runs in the hint line, "Starting in 3", "2", "1", and
it stops (the hint goes back to "Press any button to join.") if anyone un-readies, joins or
leaves. `PlayersMenu.countdown_s` (3.0; tests set it near 0).

The card's "Settings" button becomes "Driving Settings".

### 5.8 Memory

- Each type remembers its last settings in the profile key `event_memory`, under
  "type/variant(/tt)": "racing/regular", "racing/regular/tt", "racing/stock_car", "endless",
  "mini/drag", "free". A value holds `event` (a `RaceEvent` dict), `track`, `class_id` and `cup`.
- Until a type has its own entry, it reads the old keys (§6, Memory column). Nothing writes the
  old keys after the type moves.
- Drive again reads `last_drive`: the type, variant, tt, event, track, class and cup of the last
  event started from Local Drive.
- Hosting keeps its own memory under "online/…" ("online/racing/regular"), so a local setup and a
  hosted one don't overwrite each other.

### 5.9 After an event

- The results offer **"Event menu"** ("Back to this event's settings": the main menu opens on that
  event's Settings page with Next focused) and **"Main menu"** ("Back to the main menu"). They
  replace "Title". The cup standings' "Title" becomes "Main menu" too.
- Pause → "Quit to main menu" (today "Quit to title") goes to the main menu.
- Online sessions still go back to the lobby.
- Starting an event saves `Game.flow_return` (the flow's context, type, variant, tt, event, track,
  class and cup). The main menu's `_ready` rebuilds the page stack from it when the player chose
  "Event menu".

## 6. Types

| Type | Name (title) | Crumbs to Settings | Steps (local) | Tracks | Class | Memory (old keys) | Start | Online | Phase |
|---|---|---|---|---|---|---|---|---|---|
| Regular | "Regular race" | Local Drive › Racing › Regular | Event · Settings · Class · Players | every circuit | Track-mode classes | `racing/regular` (`Settings.race_event`, `last_track`, `last_platform`) | `start_event` | P8 | P4 |
| Regular TT | "Regular time trial" | Local Drive › Racing › Regular Time Trial | Event · Settings · Class (· Players from P6) | every circuit | Track-mode classes | `racing/regular/tt` (`last_track`, `last_platform`) | `start_event(RaceEvent.time_trial())` | P10 | P4, P6 |
| Stock Car | "Stock Car race" | Local Drive › Racing › Stock Car | Event · Settings · Players | circuits tagged `oval` | fixed: `official.track.stock_car` | `racing/stock_car` (`Settings.race_event`) | `start_event` | P8 | P4 |
| Stock Car TT | "Stock Car time trial" | Local Drive › Racing › Stock Car Time Trial | Event · Settings (· Players from P6) | circuits tagged `oval` | fixed | `racing/stock_car/tt` | `start_event(RaceEvent.time_trial())` | P10 | P4, P6 |
| Kart | "Kart race" or "Kart cup" | Local Drive › Racing › Kart | Event · Settings · Players | every circuit, kart-tagged first | each player's card | `racing/kart` (`last_kart`, `last_kart_platform`) | `start_event`; `start_cup_race` | race P8, cups P10 | P5 |
| Kart TT | "Kart time trial" | Local Drive › Racing › Kart Time Trial | Event · Settings · Players | every circuit, kart-tagged first | each player's card | `racing/kart/tt` | `start_event(RaceEvent.time_trial())` | P10 | P5, P6 |
| Custom | "Custom race" | Local Drive › Racing › Custom | Event · Settings · Class · Players | every circuit | any class of any mode | `racing/custom` (`Settings.race_event`) | `start_event` | P8 | P5 |
| Custom TT | "Custom time trial" | Local Drive › Racing › Custom Time Trial | Event · Settings · Class (· Players from P6) | every circuit | any class of any mode | `racing/custom/tt` | `start_event(RaceEvent.time_trial())` | P10 | P5, P6 |
| Endless | "Endless" | Local Drive › Endless | Event · Settings · Class · Players | none (a road code) | Cruiser, Sport | `endless` (`last_endless`) | `start_event` | P8 | P5 |
| Highway | "Highway" | Local Drive › Highway | Event · Settings · Class · Players | highways | Street, Super | `highway` (`last_highway`, `last_track`) | `start_event` | Cruise P8; Score attack, Run, Loop P10 | P5 |
| Sumo Wrestling | "Sumo Wrestling" | Local Drive › Mini Games › Sumo Wrestling | Event · Settings · Players | none (made from the settings) | fixed: `official.sumo.standard` | `mini/sumo` (`last_sumo`) | `start_event` | P8 | P5 |
| Drag Strip | "Drag Strip" | Local Drive › Mini Games › Drag Strip | Event · Settings · Class · Players | none (made from the settings) | Street, Pro, Top Fuel | `mini/drag` (`last_drag`, `last_drag_class`) | `start_event` | P8 | P5 |
| Kart Battle | "Kart Battle" | Local Drive › Mini Games › Kart Battle | Event · Settings · Players | arenas | each player's card | `mini/kart_battle` (`last_kart`) | `start_event(RaceEvent.battle())` | P8 | P5 |
| Free Drive | "Free Drive" | Local Drive › Free Drive | Event · Settings · Class · Players | every circuit and every highway | every class of every mode | `free` (`last_free`, `last_track`, `last_platform`) | `start_free_drive`; on a highway `start_event(RaceEvent.highway("cruise", false, traffic))` | P8 | P5 |
| Drive again | (the event's) | (the event's) | Players | (the event's) | (the event's) | `last_drive` | (the event's) | no | P4 |

- **Every circuit** means every track of type `circuit`: plain circuits, ovals, kart and stunt
  tracks, and real-world tracks. Highways and arenas are not circuits.
- **Hosting** lists only tracks that can be shared (not personal-use ones), as the Host menu does
  today.
- A breadcrumb past Settings adds the step: "Local Drive › Racing › Regular › Class", "… ›
  Players". Hosting starts "Drive Online › Host" and ends at the lobby, "Drive Online › Lobby".
  Changing the event starts "Drive Online › Lobby".
- **Free Drive on a highway** (P5) first checks that non-highway classes can drive a highway
  (`game.gd` forces a highway class on a test drive); if they can't, the class list keeps to
  highway classes for a highway.

### 6.1 Rows per type

The sky rows are "Time", "Time runs" and "Weather" (`SkyRows`), at the end of every type's rows.

| Type | Rows |
|---|---|
| Regular | "Track", "Practice", "Qualifying", "Laps", "AI cars", "AI skill", "Collisions", sky. Everything else uses the track's rules or the defaults: grid from qualifying, lenient track limits, garage cars for the AI, and the track's start, drafting, fuel and tires. |
| Stock Car | The same rows as Regular. The track's rules apply: rolling start, drafting, fuel and tires, pack racing. |
| Regular, Stock Car TT | "Track", sky. |
| Kart | "Play" ("Race" or "Cup"), then for a race "Track", "Laps", "AI karts", "AI skill", "Items"; for a cup "Cup", its races, "Change this cup", "Delete this cup", "New cup", "AI karts", "AI skill", "Items"; then sky. The cup builder is a page of its own (title "Cup builder"). |
| Kart TT | "Track", sky. Items are off. |
| Custom | "Preset", "Save preset", "Delete preset", then today's Race menu: "Track", "Practice", "Qualifying", "Race length", "Race", "AI cars", "AI skill", "AI cars look", "Start", "Drafting", "Fuel use", "Tire wear", "Grid", "Collisions", "Track limits", then "Items" (description "Kart classes only"), sky. |
| Custom TT | "Preset", "Save preset", "Delete preset", "Track", "Track limits", sky. |
| Endless | Today's: "Road code", "New road", "Start in", "Lanes", "Drive on", "Traffic", "Garage cars", "Oncoming", "Speed traps", "Police", "Far apart", sky. |
| Highway | "Highway" (the highway itself), then today's: "Mode", "Traffic", "Police", "Way round" (or "Run" for a run), sky. |
| Sumo Wrestling | Today's: "Platforms", "Underneath", "Shrink", "Length", "Sudden death", "Drift", "AI cars", "AI skill", "AI models", sky. |
| Drag Strip | Today's without "Class" (it moves to the Class step): "Length", "Boost", "Timing shifts", "Quick time events", the "Gimmicks" rows, the "Field" rows, sky. |
| Kart Battle | "Arena", "Rule", "Hits to win" (Most hits only), "Minutes", "AI karts", "AI skill", sky. |
| Free Drive | "Track", then on a circuit "AI cars", "AI skill", "AI cars look", "Collisions", "Track limits"; on a highway "Traffic" ("Off" or "On") in their place; then sky. |

- **Presets** (Custom, P5): "Save preset" asks for a name and saves the settings as
  `user://event_presets/<slug>.json` (the folder follows `Settings.use_folder`). "Preset" steps
  through "None" and the saved names; picking one fills the rows. "Delete preset" asks first.
- **Defaults** (settled in this spec; the owner can change them): Regular 5 laps and 7 AI cars;
  Stock Car 10 laps and 11 AI cars; Kart as today's Kart menu.

## 7. Drive Online

### 7.1 Landing page

Title "Drive Online", breadcrumb "Drive Online".

| Button | Description |
|---|---|
| "Host" | "Start a game others can join" |
| "Join" | "Find a game on your network or by address" |
| "Back" | "Back to the main menu" |

A status line under the buttons says why the last game ended, when it did ("Kicked", "Server
closed").

### 7.2 Host

Title "Host", breadcrumb "Drive Online › Host", "Step 1 of 5".

Rows: "Name", "Password", "Players", "Port", "LAN discovery", "Open port" (today's Host rows, with
the same descriptions). At the bottom: "Next" ("Choose the event") and "Back".

Then the same Event, Settings and Class pages as Local Drive (in the "host" context), and the
lobby. The last page before the lobby hosts: its confirm is "Start hosting", and it builds the
`ServerConfig` for `Net.host(...)`.

Every type can be hosted. Regular, Stock Car, Custom, Kart races, Kart Battle, Endless, Highway
Cruise, Sumo Wrestling, Drag Strip and Free Drive need only the pages (P8). Time trials, Highway
Score attack, Run and Loop, and Kart cups need new network code first (P10); until then the
event pages leave them out when hosting.

### 7.3 Join

Title "Join", breadcrumb "Drive Online › Join". Tabs "On your network | Direct | Official".

- **On your network:** the servers found on the LAN, as today ("Name   2/16   class, track
  (password)"). "None found" when there are none.
- **Direct:** "Favourites" first (pinned at the top, each named by you), then "Recent" (the last 8
  servers joined), then "Address", "Password" and "Join".
  - A favourite's row joins it; beside it, "Edit" opens a page with "Name", "Address", "Remove" and
    "Back".
  - A recent row joins it; beside it, "Save" adds it to the favourites, named after the server.
  - New settings keys: `net_recent` and `net_favourites`.
- **Official:** disabled, reading "Coming soon" (its description too).
- A **locked server asks for its password before** trying to join (§7.4). A direct join that
  fails with "Password needed" asks, then tries again.

### 7.4 Password page

Title "Password", breadcrumb "Drive Online › Join › Password". The line "<server> needs a
password.", then "Password" (hidden as typed), "Join" and "Back". A wrong one shows "Wrong
password" and keeps the page up.

### 7.5 Lobby

Title: the server's name. Breadcrumb "Drive Online › Lobby"; when hosting, "Step 5 of 5".

- **Left, the roster:** everyone in the game. Each row: their colour, a car thumbnail (a
  placeholder until it arrives), an input device icon, assist icons, ping ("42 ms") and "Ready"
  when ready. A row's accessible name says it all: "Ana, Saleen S7, controller, ABS, 42 ms,
  ready".
- **Right, chat**, as today.
- **Bottom, "This PC":** a card per local player (in their own `PlayerView`): "Profile", "Car",
  "Controls", "Driving Settings", "Ready" and "Leave", and a "Press to join" slot for another local
  player.
- **Ready is per player:** each local player readies on their own card. A PC is ready when all of
  its players are.
- **Host only:** "Change event" (runs the Event, Settings and Class pages again and comes back to
  the lobby), "Playlist" and "Force start".
- **Playlist** page (title "Playlist"): the events in order ("1. Regular race · Piedmont Speedway
  · Stock Car"), "Add event", "Remove", "Move up", "Move down" and "Back". The playlist moves on
  after each session.
- At the bottom: "Leave" ("Leave this game", or "Close the server" when hosting).

### 7.6 Start

- Once everyone is ready, a **3-second countdown** runs, "Starting in 3", and it stops ("Start
  held: not everyone's ready") if anyone un-readies. The host's "Force start" starts at once.
- The dedicated server uses the same 3 s countdown (today it waits 5 s); `countdown_s` in the
  server config changes it. `NetHost.countdown_s` (tests set it near 0).

### 7.7 Online time trial (P10)

A timed session: the host sets the minutes. Everyone hot-laps ghosted, a live board shows the best
laps, and the results come at the end.

## 8. Garage and Fitting Bay

- The Garage's **"Downloads" becomes "Fitting Bay"** ("Import and fit your own car"), and a **"+
  New car"** card comes first in the grid (accessible name "New car", description "Import a model
  in the Fitting Bay"). Both open the bay. Until P7, P1 adds a "Fitting Bay" button beside
  Downloads.
- **Filter tabs** over the grid: "My cars | Built-in".
- The bay stays its own screen. When it was opened from the Garage (`Game.open_fitting_bay(...,
  from)` sets `Game.bay_from`), **"Exit" and Back return to the Garage** ("Back to the Garage"),
  and a test drive's "Back to Fitting Bay" keeps that. Opened any other way, they go to the main
  menu as today. The Garage's "Edit" and "Sound" open the bay from the Garage too.
- **Downloads move into the bay's Import step** as a "From online games" list. Each car there has
  "Save to garage", "Export…" and "Open in bay" (`FittingDraft.from_package`).
- Downloaded tracks stay in the Track Editor's File menu (`DownloadsMenu`).

## 9. Settings and Driving Settings

Both are `TabbedPage`s. LB/RB (Q/E on the keyboard) switch tabs from anywhere on the page; up and
down move within the tab. The scroll follows the focus, on a controller too and inside players'
views. The help line at the bottom shows the focused control's description, without "Left and
right to change".

### 9.1 Settings

Title "Settings", breadcrumb "Settings" (in a session: "Pause › Settings").

| Tab | Rows |
|---|---|
| "Display" | "Graphics", "Fullscreen" |
| "Sound" | "Volume", "Own engine", "Other engines", "Tires and wind", "Effects", "Ambience", "Music", "Menus", "Spotter voice", "Narration", "Mono" |
| "Splitscreen" | "2 players", "3 players", "Sound from", "Auto resolution" |
| "General" | "Units", "Discord status", "Clear downloads" |
| "Players" | "Driving Settings" ("<name>: assists, comfort, HUD and controls"), "Profiles" ("Rename, add or delete players") |

- The Players tab is hidden during a session.
- **"Clear downloads"** shows the size ("Clear downloads (12.3 MB)", from
  `ContentStore.size_bytes()`), asks first, then calls `ContentStore.clear()`. It is off while
  online ("Not while online").
- Each tab but Players ends with "Reset to defaults". It asks first: a `ConfirmPage` titled "Reset
  Sound?" (the tab's name) with "Keep" (focused) and "Reset".

### 9.2 Driving Settings

Title "Driving Settings · <name>" ("Driving Settings · Ana"). Opened from Settings, the Players
screen's cards, the Profiles page, the pause menu and first boot, which all call it "Driving
Settings" (today: "Player settings", "Settings", "More settings").

| Tab | Rows |
|---|---|
| "Assists" | "Assists": "ABS", "Traction control", "Stability control", "Auto gearbox", "Auto clutch", "Steer aid", "Racing line"; "Access assists": "Auto-throttle", "Brake assist", "Steering assist", "Autodrive", "Item assist" |
| "Comfort" | "Camera shake", "Head movement", "Speed FOV", "Horizon lock", "Game speed" |
| "Vision & Hearing" | "Colours" (and the custom colours), "Reduce flashing", "Narration", "Speech rate", "Spotter", "Captions", "Shift light", "Slip indicator", "Close-car arrows" |
| "HUD & Display" | "HUD size", "Menu text", "High-contrast HUD", "Font", "Brightness", "HUD", the "Show …" rows |
| "Controls" | "Keyboard", "Controller", "Controller rumble", "Stick deadzone", the "Toggle …" rows, "Menu repeat after", "Menu repeat speed", "Buttons and keys", "Wheel setup" |

- Controls stay here only.
- Every tab ends with "Reset to defaults", which asks first ("Reset Comfort?", "Keep", "Reset").
  On Controls it also resets custom buttons and keys, and its page says so: "Custom buttons and
  keys go too. Wheel setup stays." Wheel calibration is kept.
- A rebuild (a row that comes or goes) rebuilds only the current tab.
- "Buttons and keys", "Wheel setup" and "Profiles" are pages (the wheel's gains a scroll area).

## 10. Input

### 10.1 Tab actions

New actions `menu_tab_prev` ("Previous tab") and `menu_tab_next` ("Next tab") go in
`Bindings.MENU` and `MENU_EVENTS`, mapped to `ui_tab_prev` and `ui_tab_next`: that is how they
reach players' views. `Bindings.apply()` also gives the main window `ui_tab_prev` and
`ui_tab_next`: Q and E, and LB and RB on any pad.

| Preset | Previous tab | Next tab | Other changes |
|---|---|---|---|
| `kb_full` | Q | E | |
| `kb_left` | Q | E | |
| `kb_right` | Comma | Period | |
| `pad_standard` | LB | RB | |
| `pad_left_hand` | (none) | L3 | menu confirm is LB only (today LB and L3) |
| `pad_right_hand` | R3 | RB | |
| `sim_generic` | (none) | (none) | a wheel's menus come from its player's other devices |

With no previous-tab button (`pad_left_hand`), left and right on the tab row do that job. In
menus Q and E don't shift (menus don't drive).

### 10.2 Glyphs

- Three families: "keyboard", "xbox" and "playstation". The glyphs are Kenney *Input Prompts*
  (CC0), only the ones the game uses, in `content/ui/prompts/<family>/<id>.png`, credited in
  CREDITS.md and LICENSE-ASSETS.md (the CC0 exception to CC-BY-SA). P2 downloads them and records
  the version.
- **A pad's family:** PlayStation for Sony pads (USB vendor 0x054C, or a name with "PS",
  "DualShock" or "DualSense", any case). Xbox for every other pad, Switch pads included.
  `Devices.family_of_joy(device)`.
- **The main window** uses `Devices.last_family`, set from the last `InputEvent`: a key or the
  mouse makes it "keyboard", a pad its family.
- **A player's view** uses the device that fired that slot's last menu action
  (`PlayerInput`), and reads the button from that slot's preset: `pad_left_hand` shows LB for
  confirm. `PlayerSlot.glyph_family()`.
- A wheel or other sim device shows the binding's name as a text chip ("Button 3").
- **A missing texture** shows a text chip: the input's name in a rounded box ("LB", "Enter").
- Glyph ids, by family:

| Family | Ids |
|---|---|
| keyboard | `enter`, `space`, `escape`, `backspace`, `arrows`, `q`, `e`, `comma`, `period`, `w`, `a`, `s`, `d`, `f`, `g`, `tab` |
| xbox | `a`, `b`, `x`, `y`, `lb`, `rb`, `lt`, `rt`, `dpad`, `l3`, `r3`, `left_stick`, `right_stick`, `view`, `menu` |
| playstation | `cross`, `circle`, `square`, `triangle`, `l1`, `r1`, `l2`, `r2`, `dpad`, `l3`, `r3`, `left_stick`, `right_stick`, `share`, `options` |

## 11. Network protocol

Protocol 12 today.

- **13 (P9), the lobby:** PLAYER_INFO carries `{player, device, assists}` per local player; Ready
  is per player; the lobby list carries each player's ping (from `rtt_ms`, refreshed every 2 s);
  local players join and leave mid-lobby (`Net.add_local`, `remove_local`, matched by
  `local_index` and slot index, not list order); the countdown runs in `NetHost` (moved from
  `server_main.gd`); `set_rotation` and `set_event` for the playlist and Change event.
- **14 (P10), new events online:** time trials (a timed session with a live BOARD of best laps
  and results at the end, `game/net/time_trial_net.gd`); Highway Score attack, Run and Loop with
  the server in charge (`run_control.gd`, "run" in `NetRace.KINDS`); Kart cups as a playlist with
  the standings kept on the server.
- Older games are turned away by the version check, as today.

## 12. Screen-reader routes

`tools/a11y_check.py` (run with the system `python3`, the desktop awake) walks the menus over
AT-SPI. Each phase updates its routes:

| Phase | Routes |
|---|---|
| P1 | Every route: "Solo Drive" becomes "Local Drive", "Online" becomes "Drive Online", "Quit" becomes "Exit Game". |
| P2 | Every route still passes with the page stack. A page under the top one is not showing. |
| P3 | New `--settings-only`: Settings → every tab → Players → Driving Settings → every tab, and back. |
| P4 | The main route: Local Drive → Racing → Regular → Settings ("Next") → "Track GT" → Players ("Ready") → the race → results ("Main menu"). New `--racing-only`: Stock Car (no Class step) and the Time Trial switch, and back. |
| P5 | Rewrite `--highway-only`, `--kart-only`, `--endless-only`, `--sumo-only` and `--drag-only` for the pages; `--racing-only` adds Custom; new `--free-only`. |
| P6 | `--racing-only` adds a time trial's Players step. |
| P7 | New `--garage-only`: Garage → Fitting Bay → the Import step ("From online games") → Exit → the Garage → Back. |
| P8 | The online route: Drive Online → Host → "Next" → Racing → Regular → Settings → Class → the lobby → "Leave"; Join → each tab → Back. |
| P9 | The lobby: the "This PC" card's buttons, "Change event", "Playlist", "Leave". |
| P11 | The final routes and the docstring. |

## 13. Phases

Each runs in its own session. Every phase: reads this file first; builds on the pages before it;
leaves the game working with the touched tests passing; updates its `a11y_check.py` route and the
docs it changes; adds a dated Fixed entry to `Changes.md` (re-read first, only add); ticks its box
in [ROADMAP.md](ROADMAP.md#ui-overhaul); commits at sensible points.

| Phase | What |
|---|---|
| P0 | This spec, D214, the roadmap section. |
| P1 | Main menu: the new order and sizes; the Fitting Bay from the Garage. |
| P2 | Pages: `MenuPage`, `MenuStack`, `PromptBar`, glyphs, `ConfirmPage`; the old menus run on the stack. |
| P3 | Tabs, Settings and Driving Settings. |
| P4 | Local Drive: the event type, Racing, Settings and Class pages; Regular and Stock Car; Drive again; the Players countdown; after an event. |
| P5 | The other local types; the old menus go. |
| P6 | Time trials: every variant, splitscreen. |
| P7 | Garage and Fitting Bay. |
| P8 | Drive Online: landing, Host, Join, Password. |
| P9 | The lobby, protocol 13. |
| P10 | New online events, protocol 14. |
| P11 | The docs and accessibility sweep. |

## 14. Not now

- A Players screen redesign (beyond the countdown).
- Official servers (only the placeholder tab).
- Profiles stay in Settings.
- Remembering the last settings tab.
- Clickable wireframes: the owner reviews each phase in the game.
