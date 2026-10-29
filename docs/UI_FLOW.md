# UI flow

The menus and how players move through them: the spec for the UI overhaul (D214, which supersedes
D160). The overhaul was built in phases P0-P11 (done 2026-10-26), each in its own session; every
phase read this file first and built on the pages the phases before it made. Progress is in
[ROADMAP.md](ROADMAP.md#ui-overhaul). Changes since go here first, as before.

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
- **A short page** (under 800 logical px tall: text 1.5 and up, a small view; D217) keeps room for
  its rows: 24 px margins above and below, and the header (crumbs, step row, title, tabs) at the top
  of the scroll, so it scrolls away with the rows. The action bar, help line and prompt bar stay.
- A labelled row (a slider, a text field) has its labels at the rows' 34 px; a slider's row is
  outlined in the accent colour while it has the focus, as a button row is.
- A spinner's value too long for its row ends in "…"; the row's name keeps its width. The track
  pane's map shrinks to as little as 120 px, so the pane fits beside the rows at text 1.5.
- The Garage follows the menu text size too; the Fitting Bay and the track editor don't yet.
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
  `follow_focus` doesn't. A page's main action ("Next") sits in an **action bar** under the body,
  "Back" on its left, always on screen however long the body (P4): down from the last row goes to
  it, then Back; left and right go along the bar. Godot 4.7.2 leaves a row that starts out of the
  scroll's view out of the screen-reader tree until it has the focus, so a Next at the end of a long
  body was out of reach of the checks (which can't send keys) and of a screen reader's review.
- **Back's description:** a page's own ("Back to the main menu"), or else "Back to" the crumb before
  this page's ("Back to Settings"; "Pause", "Players" and "Lobby" read "the pause menu", "the
  players", "the lobby"). An event's Settings page says the page its type was picked on ("Back to
  Racing", "Back to Mini Games", "Back to Local Drive", hosting "Back to the event types"). Every
  control on a settings page has a description (`descriptions_test`).
- **`MenuStack`:** push and pop. Only the top page is visible. Popping gives the focus back to the
  control that had it. Drive Online's old menus ran on the main menu's stack too (P2) until P8 made
  them pages.
- **`ConfirmPage`:** a question with the safe answer focused first (promoted from the pause menu's
  `ConfirmMenu`). Its title is the question; its buttons are given (e.g. "Keep" and "Reset").
- **`TabRow`:** a row of tabs (toggle buttons). `ui_tab_prev` and `ui_tab_next` switch tabs from
  anywhere on the page, only while its page is on top and not while a text field is being typed
  in, wrapping at the ends. Left and right on the tab row switch too. Switched from a row, the
  focus goes to the new tab's first row; from the tab row it stays on the row (the new tab). Up
  from a tab's first row reaches the tab row. The row scrolls sideways when the tabs don't fit. A
  tab can be off (Join's Official, P8): it shows dimmed, its name then why ("Official · Coming
  soon"), its accessible name the name alone and why its description; it can't take the focus,
  and the tab keys and left and right skip it.
- **`TabbedPage`:** a `MenuPage` with a `TabRow`, a help line at the bottom, and a "Reset to
  defaults" button at the end of each tab that has settings (§9). It builds one tab's rows at a
  time; a page opens another over itself with `open_over()` (on its `MenuStack`, or in its place in
  a player's view and the pause menu).
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

- **Test hooks:** `Game.hold_events` with `event_requested` (an event is reported, not started),
  `Game.hold_scenes` with `scene_requested` (a screen change is reported, not made: where Exit or
  Back leads; P1), `PlayersMenu.countdown_s` and `NetHost.countdown_s` (tests set them near 0).

## 5. Local Drive

### 5.1 The flow

Event type → the event's settings → the class (only if needed) → the players.

| Context | Steps |
|---|---|
| Local Drive | "Event · Settings · Class · Players" |
| Hosting | "Host · Event · Settings · Class · Lobby" |
| Changing the event from the lobby | "Event · Settings · Class · Lobby" |

The Class step drops out when the class is fixed (Stock Car, Sumo Wrestling) or picked on each
player's card (Kart, Kart Battle). Changing the event from the lobby (P9), the last page's confirm
is "Done" ("Back to the lobby with this event"), or the class picked. The Event step covers the event type page and, for Racing and
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
  there comes to that event's Settings page (Next focused), then the Racing page, then Local Drive.
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

Every type has its time trial (P6), with the race's Players step: splitscreen, each player with
their own ghost (§5.10).

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
track. The **Track** row steps through the tracks in place: there is no separate track picker. Its
lengths are in the player's units, as the pane's ("Proving Ground · 1.6 mi").

Under the rows, in the action bar: "Back" and "Next". Next is off until the event can go: a kart
race needs a track, a battle an arena, a cup every one of its tracks. A line under the rows says what
a row has to say ("Not a road code"). Next's description says what comes next:
"Pick the class", "The players: each picks a car", "The players: each picks a car and a class",
or, when hosting with no Class step,
Next reads "Start hosting" ("Start the server and open the lobby").

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
- Confirm on a class goes on: to Players, or to the lobby when hosting (it hosts).
- At the bottom: "Back".
- **The Garage's Drive** (P5) uses it too, without an event: breadcrumb "Garage › <car> › Class"
  (P7b), every class that takes the Garage's car (any mode's), that car on the turntable, and Back
  ("Back to <car>"). A pick drives it.

### 5.7 Players page

The Players screen stays as it is (a redesign is out of scope), but the start changes: once
everyone is Ready, a **3-second countdown** runs in the hint line, "Starting in 3", "Starting in
2", "Starting in 1", and it stops (the hint goes back to "Press any button to join. …") if anyone
un-readies or joins. When someone leaves it stops too, and if everyone left is ready it starts
again from 3. `PlayersMenu.countdown_s` (3.0; tests set it near 0).

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

### 5.10 Time trials

Built in P6.

- Every Racing type has one: Regular, Stock Car, Kart and Custom. The steps are the race's, Players
  included. Up to four players drive at once in splitscreen, and players can drop in and out
  mid-drive as in any local session.
- The cars are ghosted to each other (`RaceEvent.time_trial()` has no collisions): no contact, and
  no drafting or slipstream off another player.
- Each player has their own lane (`TimeTrial.Lane`): their laps recorded, their best saved per
  profile in `user://ghosts/<track>/<class>/best_<profile>.json`, their own ghost and their own live
  delta. P1 still reads the `best.json` from before until they beat it.
- Each ghost shows only in its player's view: the lanes' ghosts sit on visual layers 2-5, one
  each, and each player's camera hides the others'.
- The pause menu's "Ghost" row lists "Your best", the folder's other ghosts (the other players'
  bests among them: "Ana 1:23.456") and "Off". Its "Leaderboard" is the player's class's.
- **Kart:** each player picks their class on their card, and their ghosts are kept under that
  class. The kart rules run (the tow drone, drifts and boosts) with no items.

## 6. Types

| Type | Name (title) | Crumbs to Settings | Steps (local) | Tracks | Class | Memory (old keys) | Start | Online | Phase |
|---|---|---|---|---|---|---|---|---|---|
| Regular | "Regular race" | Local Drive › Racing › Regular | Event · Settings · Class · Players | every circuit | Track-mode classes | `racing/regular` (`Settings.race_event`, `last_track`, `last_platform`) | `start_event` | P8 | P4 |
| Regular TT | "Regular time trial" | Local Drive › Racing › Regular Time Trial | Event · Settings · Class · Players | every circuit | Track-mode classes | `racing/regular/tt` (`last_track`, `last_platform`) | `start_event(RaceEvent.time_trial())` | P10 | P4, P6 |
| Stock Car | "Stock Car race" | Local Drive › Racing › Stock Car | Event · Settings · Players | circuits tagged `oval` | fixed: `official.track.stock_car` | `racing/stock_car` (`Settings.race_event`) | `start_event` | P8 | P4 |
| Stock Car TT | "Stock Car time trial" | Local Drive › Racing › Stock Car Time Trial | Event · Settings · Players | circuits tagged `oval` | fixed | `racing/stock_car/tt` | `start_event(RaceEvent.time_trial())` | P10 | P4, P6 |
| Kart | "Kart race" or "Kart cup" | Local Drive › Racing › Kart | Event · Settings · Players | every circuit, kart-tagged first | each player's card | `racing/kart` (`last_kart`, `last_kart_platform`) | `start_event`; `start_cup_race` | race P8, cups P10 | P5 |
| Kart TT | "Kart time trial" | Local Drive › Racing › Kart Time Trial | Event · Settings · Players | every circuit, kart-tagged first | each player's card | `racing/kart/tt` | `start_event(RaceEvent.time_trial())` | P10 | P5, P6 |
| Custom | "Custom race" | Local Drive › Racing › Custom | Event · Settings · Class · Players | every circuit | any class of any mode | `racing/custom` (`Settings.race_event`) | `start_event` | P8 | P5 |
| Custom TT | "Custom time trial" | Local Drive › Racing › Custom Time Trial | Event · Settings · Class · Players | every circuit | any class of any mode | `racing/custom/tt` | `start_event(RaceEvent.time_trial())` | P10 | P5, P6 |
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
- **Free Drive on a highway** (P5): checked first that the other modes' classes can drive one
  (`game.gd` forces a highway class on a test drive). With `tools/highway_check.sh` (60 s on the
  Lumen Ring, autodriven) Track GT, Kart Medium, Endless Cruiser and Sumo went 1.4-1.6 km, as far as
  Highway Street; Drag Street never moved: Drag allows no automatic gearbox, and the highway's
  autodrive doesn't shift. So on a highway the class list leaves out Drag's classes. A highway in
  Free Drive drives as a Cruise, its traffic on or off.

### 6.1 Rows per type

The sky rows are "Time", "Time runs" and "Weather" (`SkyRows`), at the end of every type's rows.

| Type | Rows |
|---|---|
| Regular | "Track", "Practice", "Qualifying", "Laps", "AI cars", "AI skill", "Collisions", sky. Everything else uses the track's rules or the defaults: grid from qualifying, lenient track limits, garage cars for the AI, and the track's start, drafting, fuel and tires. |
| Stock Car | The same rows as Regular. The track's rules apply: rolling start, drafting, fuel and tires, pack racing. |
| Regular, Stock Car TT | "Track", sky. Hosting adds "Minutes" (§7.7). |
| Kart | "Play" ("Race" or "Cup"), then for a race "Track", "Laps", "AI karts", "AI skill", "Items"; for a cup "Cup", its races, "Change this cup", "Delete this cup", "New cup", "AI karts", "AI skill", "Items"; then sky. The cup builder is a page of its own (title "Cup builder"). |
| Kart TT | "Track", sky. Items are off. Hosting adds "Minutes" (§7.7). |
| Custom | "Preset", "Save preset", "Delete preset", then today's Race menu: "Track", "Practice", "Qualifying", "Race length", "Race", "AI cars", "AI skill", "AI cars look", "Start", "Drafting", "Fuel use", "Tire wear", "Restrictor", "Grid", "Collisions", "Track limits", then "Items" (description "Kart classes only"), sky. |
| Custom TT | "Preset", "Save preset", "Delete preset", "Track", "Track limits", sky. Hosting adds "Minutes" (§7.7). |
| Endless | Today's: "Road code", "New road", "Start in", "Lanes", "Drive on", "Traffic", "Garage cars", "Oncoming", "Speed traps", "Police", "Far apart", sky. |
| Highway | "Highway" (the highway itself), then today's: "Mode", "Traffic", "Police", "Way round" (or "Run" for a run), sky. |
| Sumo Wrestling | Today's: "Platforms", "Underneath", "Shrink", "Length", "Sudden death", "Drift", "AI cars", "AI skill", "AI models", sky. |
| Drag Strip | Today's without "Class" (it moves to the Class step): "Length", "Boost", "Timing shifts", "Quick time events", the "Gimmicks" rows, the "Field" rows, sky. |
| Kart Battle | "Arena", "Rule", "Hits to win" (Most hits only), "Minutes", "AI karts", "AI skill", sky. |
| Free Drive | "Track", then on a circuit "AI cars", "AI skill", "AI cars look", "Collisions", "Track limits"; on a highway "Traffic" ("Off" or "On") in their place; then sky. |

- **Presets** (Custom, P5): "Save preset" asks for a name (a page titled "Save preset": "Name",
  and "Save" in the action bar) and saves the settings and the class as
  `user://event_presets/<slug>.json` (a time trial's `<slug>_tt.json`; the folder follows
  `Settings.use_folder`). A name already there is replaced. "Preset" steps through "None" and the
  saved names (a race's and a time trial's are listed apart); picking one fills the rows. "Delete
  preset" (off with None) asks first: "Delete Sprint?", "Keep" ("Leave it", focused) and "Delete".
- **Cups** (Kart, P5): "Delete this cup" asks first the same way. The Cup builder page has "Name",
  "Race 1" to "Race 4" and their laps, "Save" in the action bar, and Back ("Without saving"); saved,
  it's the cup picked.
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

- Local players join in the lobby's "This PC" (§7.5). The "Players" button that set them up first
  (P8) went in P9, with the Players screen's online mode.
- Hosting or joining, **the lobby takes the place of the pages on the way** (Host and the event
  pages, or Join and Password): Back or Leave in the lobby comes back here, with the focus where
  it was.

### 7.2 Host

Title "Host", breadcrumb "Drive Online › Host", "Step 1 of 5".

Rows: "Name", "Password", "Players", "Port", "LAN discovery", "Open port" (today's Host rows, with
the same descriptions; LAN discovery and Open port are On/Off spinners). At the bottom: "Next"
("Choose the event") and "Back" ("Back to Drive Online").

Then the same Event, Settings and Class pages as Local Drive (in the "host" context), and the
lobby. The last page before the lobby hosts: its confirm is "Start hosting", and it builds the
`ServerConfig` for `Net.host(...)`.

- **The Event page:** title "Event", breadcrumb "Drive Online › Host › Event", "Step 2 of 5": the
  Local Drive types without Drive again, with their descriptions. Back is "Back to Host"; Racing's
  and Mini Games' Back is "Back to the event types".
- **Racing** has its Race | Time Trial switch, as on Local Drive (P10; P8 left it out).
- **Rows left out when hosting:** Free Drive's "AI cars", "AI skill" and "AI cars look" (a free
  drive online has no AI). A time trial gets "Minutes" (§7.7). Kart's "Play" (a cup, §7.9) and
  Highway's "Mode" (§7.8) are there since P10.
- **The last page:** a type with no Class step (Stock Car, Kart, Sumo Wrestling, Kart Battle) has
  "Start hosting" ("Start the server and open the lobby") for its Next; the others host on the
  class picked. If the port is taken, a line under the rows says "Can't open UDP 47800" and the
  page stays.
- **The server:** the Host page's options with the event as its one rotation item (a kart cup: its
  races, §7.9): the track (Endless: "endless"; Sumo and Drag, which make their own ground: the
  default track), the class (Kart and Kart Battle: Medium, each player picking theirs in the
  lobby) and the event. The options are kept in `Settings.net_host` without the password, and
  `--host` hosts them again.

Every type can be hosted. Regular, Stock Car, Custom, Kart races, Kart Battle, Endless, Highway
Cruise, Sumo Wrestling, Drag Strip and Free Drive needed only the pages (P8); time trials (§7.7),
Highway Score attack, Run and Loop (§7.8) and Kart cups (§7.9) came with their network code in P10.

### 7.3 Join

Title "Join", breadcrumb "Drive Online › Join". Tabs "On your network | Direct | Official".

- **On your network:** the servers found on the LAN, as today ("Name   2/16   class, track
  (password)"). "None found" when there are none; then the focus starts on the tab row.
- **Direct:** "Favourites" first (pinned at the top, each named by you), then "Recent" (the last 8
  servers joined), then "Address", "Password" and "Join". A heading shows only with something
  under it.
  - Each server row reads "Name   address" ("Ana's PC   192.168.1.20:47800"), its description
    "Join this server". Right reaches the button beside it; up and down go where the row does.
  - A favourite's row joins it; beside it, "Edit" ("Rename or remove Ana's PC") opens a page titled
    with its name (breadcrumb "Drive Online › Join › Ana's PC") with "Name", "Address", "Remove"
    and "Back". Name and Address are kept as typed (an address that isn't one is not); Remove
    takes it off at once.
  - A recent row joins it; beside it, "Save" ("Add Ana's game to your favourites") adds it to the
    favourites, named after the server. On a server that's a favourite already it's off ("In your
    favourites").
  - New settings keys: `net_recent` and `net_favourites` (`settings.cfg`, `[online]`), each a list
    of `{name, address}`. A recent server is named by the server's own name from its answer.
- **Official:** off, reading "Official · Coming soon" (its description "Coming soon").
- A line under the rows says how a join goes: "Joining 192.168.1.20:47800", "Enter an address",
  "Can't reach …", "Server not found", or the server's refusal.
- A **locked server asks for its password before** trying to join (§7.4). A direct join that
  fails with "Password needed" asks, then tries again.

### 7.4 Password page

Title "Password", breadcrumb "Drive Online › Join › Password". The line "<server> needs a
password.", then "Password" (hidden as typed), and "Join" ("Join <server>") and "Back" ("Back to
Join") in the action bar; Enter in the field joins too. An empty one says "Type the password". A
wrong one shows "Wrong password" and keeps the page up. A direct join's server is named by its
address here.

### 7.5 Lobby

Title: the server's name. Breadcrumb "Drive Online › Lobby"; when hosting, the last step of the
step row: "Step 5 of 5" ("Step 4 of 4" for a type with no Class step). Built in P9 (`LobbyPage`).

- **The event line** at the top: "Race, 5 laps   Proving Ground   GT   2/16 players" ("Time trial,
  10 min", "Highway run", "Spark Cup, race 2 of 4, 3 laps"); when hosting, "Join at
  192.168.1.20:47800" under it. With a kart cup, a line under it has the standings (§7.9).
- **Left, the roster** (heading "Players"): everyone in the game. Each row: their colour, a car
  thumbnail (a placeholder until the car is here), the device they play with (a glyph: the arrow
  keys for a keyboard, a stick for a controller; a "Wheel" chip), their assists as chips ("ABS",
  "TCS", "Aid"…), their ping ("42 ms"; "host" for the host's own players) and "Ready". A row's
  accessible name says it all: "Ana, Saleen S7, controller, ABS, 42 ms, ready", then ", admin" and
  ", muted" where they apply. A row of another PC's player opens their page (title their name):
  "Mute" (or "Unmute"), and for admins "Kick" and "Ban". P1's own row ("Your car and the rest are
  under This PC") goes to their Profile row, This PC scrolled into view.
- **Right, chat**, as before: "Say", "Quick chat", "Send quick". Below 1100 px logical width (no
  room for the pane) it sits under This PC.
- **Host only**, under the roster: "Change event" ("Pick another event to run next") and "Playlist"
  ("Events to run one after another"); admins also get "Force start" ("Start now, ready or not").
- **"This PC"**: P1's rows on the page, under their tag and name: "Profile", "Car: Saleen S7" ("Pick
  your car"), a kart lobby's "Class", "Controls" and "Driving Settings"; P1's "Ready" is in the
  action bar beside "Leave", always on screen. Each other player here has a card at the bottom of
  the page, in their own `PlayerView`, driven by their own devices: the same rows, "Ready" and
  "Leave" ("Stop playing on this PC"). Then a "Press to join" place while there's
  room (a line while P1 is alone, a card's height once others have joined). Cancel on a card
  un-readies, then leaves.
  - **P1's card is the page's own rows** (D215): the main window is P1's, as on every page,
    so P1 reaches the roster, chat, the host's buttons and their own rows in one focus order. The
    keys and pads of the other players here, and pads nobody has yet (pressed to join), don't move
    the window's focus; their presses reach their own card.
  - "Controls": with a controller, its layout ("Standard", "Left hand", "Right hand"); on the
    keyboard, its side ("Whole keyboard", "Left side", "Right side"), so two can share it.
  - P1's Car and Driving Settings open over the lobby; another player's open full screen in their
    own view, and their card comes back when they close.
  - Each player starts with their last car, if the class takes it, else the class's own. Their
    device and assists (the ones the class allows) go to the server for everyone's roster.
- **Ready is per player:** each local player readies on their own (P1 in the action bar, the others
  on their cards). A PC is ready when all of its players are. Ready waits for the track ("Getting
  track 40%").
- **Change event** runs the Event, Settings and Class pages again (the "change" context: crumbs
  "Drive Online › Lobby › Event", steps "Event · Settings · Class · Lobby", hosting's types, tracks
  and rows; Back on the Event page is "Back to the lobby"), and comes back to the lobby with the
  event, everyone to ready again.
- **Playlist** page (title "Playlist", breadcrumb "Drive Online › Lobby › Playlist"): the events in
  order, as toggle buttons ("1. Regular race · Piedmont Speedway · GT", with ", up now" on the one
  up; no track for events that make their own ground, no class where each kart picks its own), then
  "Add event" ("Another event at the end": the event pages, as Change event's), "Remove", "Move up"
  and "Move down" (each on the event picked; the one up stays up) and "Back" ("Back to the lobby").
  The playlist moves on after each session.
- At the bottom, the action bar: "Leave" ("Leave this game", or "Close the server" when hosting) and
  P1's "Ready" ("Tell the others you're ready"; "Ready ✓" once ready). Cancel leaves too.
- **A status line:** the server's notices, "Starting in 3", "Start held: not everyone's ready",
  "Track here".

### 7.6 Start

- Once everyone is ready (and the server has its fewest players: the dedicated server's
  `--min-players`), the server counts down: "Starting in 3" in chat and on the status line (the
  lobby carries the seconds left, `starting`). It stops ("Start held: not everyone's ready") if
  anyone un-readies or a new player joins. The host's "Force start" starts at once.
- The dedicated server uses the same 3 s countdown (it waited 5 s before P9); `countdown_s` in the
  server config changes it. `NetHost.countdown_s` (tests set it).

### 7.7 Online time trial (P10)

A timed session: the host sets the minutes. Everyone hot-laps ghosted, a live board shows the best
laps, and the results come at the end.

- **Hosting:** Racing's Time Trial switch, then any of the four types; the Settings page adds
  "Minutes" ("How long the session runs; the best laps win"): "5 min", "10 min" (first), "15 min",
  "20 min", "30 min". A time trial on Local Drive has no end and no Minutes row.
- **The start:** as any event's first session online: everyone's cars, then three lights.
- **Driving:** each player has their own ghost and live delta, as on Local Drive (§5.10); the other
  cars are ghosted. The HUD's top line counts down: "Time trial  9:42".
- **The live board:** the server times every lap and keeps each driver's best (`TimeTrialNet`, BOARD
  "live"). It shows in the HUD's standings ("1 Ana  1:23.456", "» 2 Bo  1:24.010", the top three and
  the places round yours) with "P2/5" once you have a lap, and as the pause menu's "Leaderboard"
  ("<track> · this session").
- **Joining:** players who join during the session drop straight in and hot-lap (unlike a race).
- **The end:** when time's up, each car finishes the lap it's on; then the results ("Time trial":
  best laps, fastest first), and back to the lobby as after any event. Each driver's new bests go on
  the server's board for the track; a car the server flagged (D87) doesn't.

### 7.8 Highway modes online (P10)

Score attack, Run and Loop host like a Cruise, with the Mode row.

- **Score attack and Loop** run as a cruise does online, the server scoring every player and timing
  the laps for its own boards (D114, D118): the pause menu's Leaderboard is the server's.
- **A run** is the event's "run" session, the server in charge: every game lines up the cars it
  drives on their spots by the session's grid (so they agree), rolls them to the start and lets them
  go at the line; the server times each car from where it shows it, rules on the checkpoints
  ("Off the run", "Wrong way": a note to that driver) and the finish ("Finish 1:06.450"), and its
  results ("Run results") are everyone's. The HUD's top line says "Rolling", then the run's clock
  ("Run 0:42.300"), its time once through, or "Out". Players who join during a run wait in the
  lobby: "Run on: you're in the next one". The host's Restart lines everyone up again.

### 7.9 Kart cups online (P10)

- **Hosting:** Racing → Kart → "Play": "Cup", then the cup, as on Local Drive. The server's playlist
  is the cup's races in order, each named "Spark Cup, race 1 of 4" (Change event and the Playlist's
  Add event put in all four); everything else about the playlist stays (the host can reorder it).
- **The standings** are the server's (`NetHost.cup`): points as offline (15, 12, 10, 8, 6, 4, 2, 1),
  each player by their id on the server, the AI by name; the AI field stays the same through the
  cup; the later races start in reverse order of the standings. A restarted race's results take
  the place of the first go's.
- **The lobby** names the race up ("Spark Cup, race 2 of 4, 3 laps") and shows the standings under
  the event line: "After race 1 of 4: Ana 15, Bo 12, …" (the top five), and once it's over "Spark
  Cup final: 1st Ana 45, 2nd Bo 40, 3rd Cy 30". The cup's first race up again starts a new cup;
  another event clears them.

## 8. Garage and Fitting Bay

The Garage is pages (P7b), on a page stack of its own: the grid, a car's page over it, and Paint,
Copy sound to and Delete over that. One turntable shows the car, in the pane of whichever page is
up; it waits about 150 ms after the focus stops before loading a car.

| Page | Title; breadcrumb | Rows | Pane | Bar; prompts |
|---|---|---|---|---|
| Grid | "Garage"; "Garage" | tabs "My cars", "Built-in"; the cards; a status line | the turntable, the focused car's name, "By GTA V · version 1", "Car · Unknown · 85,721 triangles" | "Fitting Bay" ("Import and fit your own car"), "Traffic cars" ("Pick which cars drive in traffic"), "Back" ("Back to the main menu"); Select, Tabs, Back |
| Grid in Traffic cars | as the grid | tabs; the cards, no New car; the status line "33 of 34 in traffic" | as the grid, and "In traffic", "Out of traffic" or "Doesn't fit traffic" | "All on" ("Every car on this tab in traffic"), "All off" ("No car on this tab in traffic"), "Done" ("Back to the cars"); Select, Tabs, Back |
| A car | its name; "Garage › <car>" | "Drive" ("Pick a class and drive this car"), "Edit" ("Open in the Fitting Bay", " as a copy" for a built-in car), "Paint" ("Change its colours"), "Sound" ("Tune its engine and tire sounds"), "Duplicate" ("Make a copy in the garage"), "Copy sound to…" ("Give another car these sounds"), "Export…" ("Write this car out as a .noss file"), "Delete" ("Delete this car"); a status line | the turntable, "By …", "Car · …" | "Back" ("Back to the Garage") |
| Class | "Choose class"; "Garage › <car> › Class" | §5.6 | its own turntable | "Back" ("Back to <car>") |
| Paint | "Paint"; "Garage › <car> › Paint" | its presets ("Its colours on every slot"), then per slot "Primary colour" and "Primary finish" (a spinner), and so on | the turntable, as the colours change | "Save" ("Save the paint"), "Back" ("Without saving") |
| Copy sound to | "Copy sound to"; "Garage › <car> › Copy sound to" | the player's other cars ("Give it the sounds of <car>"); none: "No other cars in the garage" | the turntable | "Back" ("Without copying") |
| Delete | "Delete <car>?"; "Garage › <car> › Delete" | "Keep" ("Leave it", focused), "Delete" ("Delete it now") | | |

- **The grid:** a **"New car"** card first, a big "+" its picture (description "Import a model in
  the Fitting Bay"), then the tab's cars, 272×178 with their names at 26 px. As many columns as fit:
  3 at text 1.0, 2 at 1.5 (beside the pane) and at 2.0 (no pane). The Garage's **"Downloads" became
  "Fitting Bay"** (P7), in the action bar. New car and Fitting Bay open the bay. The "+" is a
  picture, not text: Godot 4.7.2 reads a button whose name and text differ as both ("New car: + New
  car").
- **Tabs** over the grid: "My cars | Built-in" (a `TabRow`: LB/RB or Q/E, left and right on the
  row; not while a page is over the grid). The Garage opens on My cars, or on Built-in when the
  player has no cars of their own. Each tab comes back to the car last picked on it.
- **Focus:** up from the grid's top row reaches the tabs; down from its last row, "Fitting Bay",
  then "Traffic cars", then "Back" (left of them in the bar), then round to the tabs. Confirm on a car opens its page;
  cancel there comes back to its card. A built-in car's Paint, Sound and Delete are off.
- **Traffic cars** (D222) is a mode of the grid, for picking which cars drive in endless traffic.
  Each card shows its state: a border in the player's palette's good colour and an "In traffic"
  tag, its bad colour and "Out", or greyed with "Doesn't fit" (no traffic type takes it as it is).
  The yellow focus ring sits outside the border. Confirm on a car that fits switches it (it's a
  toggle button: screen readers say on or off); on one that doesn't, the status line says
  "Doesn't fit traffic". "All on" and "All off" switch the shown tab's cars. The status line counts
  every car that fits, on both tabs. Back (or "Done") leaves the mode, the focus on "Traffic
  cars"; a second Back leaves the Garage. Focus goes tabs → cards → All on → All off → Done →
  tabs. Every car is in until switched off; the list is this PC's (online, the host's counts).
- **After an action:** Duplicate goes back to the grid on the copy (My cars), "Copy made"; Delete
  (once asked) back to the grid, "Deleted"; Paint's Save back to the car's page, "Paint saved";
  Copy sound to back to it, "Sound copied to <car>"; Export… stays, "Exported to <file>". Paint's
  Back leaves the car's colours as they were.
- **The bay** stays its own screen, with a breadcrumb ("Garage › Fitting Bay", or "Fitting Bay"
  when not opened from the Garage) and a prompt bar (Select, "Steps", Back): LB/RB (Q/E) go to the
  previous or next step that's on, wrapping (only Import before a car is in), not while a field is
  being typed in. The step's panel scrolls to follow the focus, on a pad too; a change that builds
  the step again (a Paint dropdown, Lift clear) leaves the focus on its row, or the row above if
  that went. `Game.open_fitting_bay(..., from)` sets `Game.bay_from`: "garage" from the grid
  (New car, Fitting Bay), "car" from a car's page (Edit, Sound; `Game.bay_car`). **"Exit" and Back
  return to the Garage** ("Back to the Garage"): on the car being fitted, on its page when a car's
  page opened the bay (the car it came from when nothing was saved). A test drive's "Back to
  Fitting Bay" keeps that. Opened any other way, they go to the main menu.
- **Downloads move into the bay's Import step** as a "From online games" list, under the import
  folder's files. Each car there ("Skyline R34 · by Kaz · 14 MB") has "Save to garage" ("Keep
  Skyline R34 in your garage"), "Export…" ("Write Skyline R34 out as a .noss file") and "Open in
  bay" ("Fit Skyline R34 before saving it", `FittingDraft.from_package`).
  - Save to garage asks when the garage has that car already: "Skyline R34 is already in your
    garage.", "Replace my copy", "Keep both" and "Cancel". Exit then goes to the Garage on the car
    just saved.
  - Open in bay works as a `.noss` import does: the cache is never written to, and saving makes a
    garage car (asking first when the garage has it).
  - A part-finished download is listed ("still downloading") with its buttons off. With none: "None
    yet. Cars from games you join land here."
- Downloaded tracks stay in the Track Editor's File menu (`DownloadsMenu`, now tracks only).

## 9. Settings and Driving Settings

Both are `TabbedPage`s. LB/RB (Q/E on the keyboard) switch tabs from anywhere on the page; up and
down move within the tab. The scroll follows the focus, on a controller too and inside players'
views. The help line at the bottom shows the focused control's description, without "Left and
right to change" or "Enter to type" (the prompt bar shows those).

### 9.1 Settings

Title "Settings", breadcrumb "Settings" (in a session: "Pause › Settings").

| Tab | Rows |
|---|---|
| "Display" | "Graphics" ("Detail and smoothing. Low runs fastest"), "Fullscreen" |
| "Sound" | "Volume", "Own engine", "Other engines", "Tires and wind", "Effects", "Ambience", "Music", "Menus", "Spotter voice", "Narration", "Mono" |
| "Splitscreen" | "2 players", "3 players", "Sound from", "Auto resolution" ("Lowers each view's detail to hold the frame rate") |
| "General" | "Units" ("Speeds and distances"), "Discord status", "Clear downloads" ("Cars and tracks from online games") |
| "Players" | "Driving Settings" ("<name>: assists, comfort, HUD and controls"), "Profiles" ("Rename, add or delete players") |

- "Graphics" and "Units" are spinners (they were drop-down lists), like every other choice.
- **F11** (macOS: also Cmd+Ctrl+F) toggles Fullscreen from anywhere; an open Display tab's row follows (D232).
- The Players tab is hidden during a session.
- **"Clear downloads"** shows the size ("Clear downloads (12.3 MB)", "0 MB" when empty, "1.20 GB"
  past a gigabyte; from `ContentStore.size_bytes()`), asks first, then calls
  `ContentStore.clear()`. It is off while online ("Not while online"). The question: title "Clear
  downloads?", the line "12.3 MB of cars and tracks from online games. They download again when
  needed.", "Keep" ("Leave them", focused) and "Clear" ("Delete them now").
- Each tab but Players ends with "Reset to defaults" ("Sound settings back to their defaults"). It
  asks first: a `ConfirmPage` titled "Reset Sound?" (the tab's name), breadcrumb "Settings › Reset
  Sound", with "Keep" ("Leave them as they are", focused) and "Reset". After either, the focus is
  back on "Reset to defaults".

### 9.2 Driving Settings

Title "Driving Settings · <name>" ("Driving Settings · Ana"). Opened from Settings, the Players
screen's cards, the Profiles page, the pause menu, first boot and the lobby (P9), which all call it
"Driving Settings" (until P3: "Player settings", "Settings", "More settings"). Its breadcrumb says
where it came from: "Settings › Driving Settings", "Players › Driving Settings", "Settings ›
Profiles › Driving Settings", "Pause › Driving Settings", "Accessibility › Driving Settings",
"Drive Online › Lobby › Driving Settings". The card's button reads "Driving Settings" ("Assists,
comfort, HUD and controls"); the Settings tab's says whose ("Ana: assists, comfort, HUD and
controls").

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
- "Buttons and keys", "Wheel setup" and "Profiles" are pages (the wheel's gains a scroll area),
  titled so, their breadcrumbs ending "› Buttons and keys" and so on. Buttons and keys lists the
  menu actions under a "Menus" heading, "Previous tab" and "Next tab" among them; its status line
  and the wheel's ("Turn the wheel from centre to full lock", the live readings) sit under the
  rows, always in view. Each profile on the Profiles page has "Name", "Driving Settings" ("Driving
  Settings of Ana") and "Delete".

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
  CREDITS.md and LICENSE-ASSETS.md (the CC0 exception to CC-BY-SA). Version 1.5, downloaded in P2.
  An Xbox pad's L3 and R3 are its "LS" and "RS" glyphs.
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

Protocol 15 today (D221: Haunted changed roads through the forest and autumn; nothing in the menus).

- **13 (P9), the lobby:** READY is `{player, ready}` (Ready per player); PLAYER_INFO carries
  `{player, device, assists, name, color}` per local player; the lobby's players carry `device`,
  `assists` and `ping` (from `rtt_ms`, measured every 2 s, sent when it changes by more than 5 ms)
  and the lobby `starting`; local players join and leave mid-lobby (`Net.add_local`,
  `remove_local`; the server closes up the others' local indexes, and games match players by local
  index and slot index, not list order: `Net.id_of`, `local_of`); the countdown runs in `NetHost`
  (moved from `server_main.gd`); `set_rotation` and `set_event` for the playlist and Change event;
  a rotation item may carry a `name` ("Regular race").
- **14 (P10), new events online:** time trials (a timed session, the event's `tt_min`, with a live
  BOARD "live" of best laps, `{id, name, car, time, laps}`, and results at the end,
  `game/net/time_trial_net.gd`); Highway Score attack and Loop as before, and Run with the server in
  charge (`run_control.gd`'s `authority`, "run" in `NetRace.KINDS`, a run's own session); Kart cups
  as playlist items carrying `cup` `{id, name, race, races}`, the standings kept on the server and
  sent in the lobby (`cup`: the race up, and the standings `{cup, run, of, standings}`).
- Older games are turned away by the version check, as today.

## 12. Screen-reader routes

`tools/a11y_check.py` (run with the system `python3`, the desktop awake) walks the menus over
AT-SPI. Each phase updates its routes:

| Phase | Routes |
|---|---|
| P1 | Every route: "Solo Drive" becomes "Local Drive", "Online" becomes "Drive Online", "Quit" becomes "Exit Game". |
| P2 | Every route still passes with the page stack. A page under the top one is not showing. |
| P3 | New `--settings-only`: Settings → every tab → Players → Driving Settings → every tab, and back. |
| P4 | The main route: Local Drive → Racing → Regular → Settings ("Next") → "Track GT" → Players ("Ready") → the race → results ("Main menu"), then `--racing-only`'s route. New `--racing-only`: Stock Car (no Class step) → Players and back, the Time Trial switch → Regular → the class and back. The kart route goes through Racing. |
| P5 | Rewrite `--highway-only`, `--kart-only`, `--endless-only`, `--sumo-only` and `--drag-only` for the pages; `--racing-only` adds Custom; new `--free-only`. |
| P6 | `--racing-only` adds the time trials' Players step: Regular's (after the class) and Kart's. |
| P7 | New `--garage-only`: Garage → "Built-in" and "My cars" → Fitting Bay → the Import step ("From online games") → Exit → the Garage → Back. |
| P7b | `--garage-only` opens "nOSS Box"'s page from Built-in (the grid hidden under it) and comes back before My cars. |
| P8 | The online route (also `--online-only`): Drive Online → Host → "Next" → Racing → Regular → Settings → Class → the lobby → "Leave"; Join → each tab → Back. Official can't take the focus and says "Coming soon" (Godot 4.7.2 doesn't tell AT-SPI a button is disabled). |
| P9 | The online route's lobby: "Ready" (not pressed: the countdown would start), "Change event", "Playlist" and "Force start"; Change event (the lobby hidden under it) and back, Playlist (its events) and back; P1's own roster row to This PC's "Profile", "Car", "Controls" and "Driving Settings" (rows that start below the fold are out of the screen-reader tree until focused: the row press makes them again in view); Driving Settings and back, then "Leave". |
| P10 | The online route: on the host's Racing page, the "Time Trial" switch → Regular → its Settings page has "Minutes" → back, "Race" again → Regular as before. |
| P11 | The final routes, one table in the script (`ROUTES`, then the own-game walks): the race adds the results' "Event menu" back to the Settings page and out, then Drive again → Players and out; `--settings-only` adds Reset to defaults and Clear downloads asking first (Keep) and Profiles; `--garage-only` adds a car's Drive → the class page; the pause walk adds the pause menu's Driving Settings in a player's view; new `--first-boot-only`: the Accessibility screen, its Driving Settings, Done. `--<route>-only` takes any route's name. |

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
| P7b | The Garage as pages (a car's page, Paint, Copy sound to, Delete); the bay's breadcrumb, prompt bar and LB/RB steps. |
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
