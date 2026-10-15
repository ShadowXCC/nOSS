# Gamemodes

Rules and flow for each mode. Every mode uses the same vehicle core ([PHYSICS.md](PHYSICS.md)). Each mode offers its own platform classes ([PLATFORMS.md §6](PLATFORMS.md#6-starter-classes)). Requirements: MODE-01…MODE-07, AI-01…AI-05, ENV-01…ENV-03.

---

## 0. Common to all modes

- **Flow:** Lobby → (Practice) → (Qualifying) → Main session → Results. Single player goes straight to the session.
- **Before a session:** each player picks a **class** (platform), a **car** (package) and **assists**.
- **AI** fills empty slots where the mode supports it, with skill 0–100.
- **Environment:** time of day and weather are set per event, or progress continuously (endless).
  - Day/night changes lighting only.
  - Weather sets road wetness (grip, [PHYSICS.md §4](PHYSICS.md#4-tires-pacejka-lite)), fog density and rain particles.
  - Presets: Clear, Cloudy, Fog, Light rain, Heavy rain. Snow surfaces belong to the track, not the weather.
- **In-game text is short.** Examples: "Lap 2/5", "P3", "+0.42", "Best lap", "Track limits", "Busted", "Combo ×4".

## 1. Track racing

*MODE-01 (free-drive, M1), MODE-02 (full, M4), AI-01.*

| Session | Rules |
|---|---|
| Free-drive / Practice | Unlimited driving. Hotswap, setup changes and car reset allowed. |
| Qualifying | Timed. The best valid lap sets the grid. |
| Race | Laps or time. Standing or rolling start. Grid from qualifying, reverse, or random. |
| Time trial | Solo. Ghost of your best lap, plus ghosts loaded from files or friends. Local and per-server leaderboards. *M4: the best lap per class is saved in `user://ghosts/<track>/<platform>/best.json`; other ghost files in that folder can be picked in the pause menu; the local leaderboard is `user://leaderboards/<track>.json` (D69).* |

- **Timing:** the start/finish line plus 3 sectors. Invisible checkpoints every ~100 m along the track spline. A lap only counts if every checkpoint is passed in order. A live delta bar shows the gap to the best lap (or to the ghost, if faster) at every 10 m.
- **Track limits:** a check is made when all four wheels are past the track edge (spline width plus the curb allowance).
  - Practice and qualifying: the lap is invalidated.
  - Race: a warning, then a time penalty if the cut gained time: +2 s (lenient) or +5 s (strict). A cut gained time if that stretch was driven faster than 98% of the AI line's best time for it; strict also counts cuts that gained nothing (D67).
  - Strictness: off / lenient / strict, set per event (online: the server's event rotation).
- **Flags** (an icon and a word each): green (start, and when a yellow clears), yellow (a stopped or slow car within 250 m ahead), blue (a car most of a lap up within 100 m behind; shown only), checkered (Finish).
- **Wrong way:** a warning, then after 5 s a respawn facing the right way.
- **Start:** the grid forms two staggered columns behind the line (12 m to pole, 13 m between cars in a column), held on the handbrake. Standing start: five lights, one a second, out after a short random wait. Rolling start: the field forms 220 m further back and runs at 80 km/h without passing; green comes 60 m before the line.
- **Race weekend (M4):** the Race menu picks practice and qualifying (off or a few minutes), race length (laps or minutes), AI cars (0–15) and skill, start, grid (qualifying, reverse, random), collisions, track limits, and whether AI cars come from the garage or the built-ins. When practice or qualifying time is up, cars finish the lap they're on. After the leader finishes, the others finish their lap (60 s at most); finished cars, players' included, take a cool-down lap driven by the AI. The pause menu offers Restart, End session (practice, qualifying) and Setup (not during races).
- **Resets in traffic:** with AI or in a race, a reset car waits off the track until nothing is coming within 4 s, then rejoins at the road's edge, see-through and without contact for 3 s (D66).
- **Free-drive (M1):** a car reset puts the car back on the track at the last valid spot and stops the current lap counting. Jumping ahead along the track (cutting across) does the same.
- **Local players (M3):** up to 4, one class for everyone, each with their own car, view, timer and reset spot. Cars start from a two-column grid behind the line; a reset steps back along the track if another car is on the spot. Players drop in with a free device and drop out from their pause menu; pause stops everyone.
- **Collisions:** on, or **ghosted** (no car-to-car contact), set per event; online the event comes from the server's rotation.
- **Online (M5):** the server runs the weekend: its grid, lights, flags, penalties and results; each game drives its own cars and follows the server's state. The server fills the grid with AI up to the event's count (16 cars at most). Players who join during a race weekend wait in the lobby for the next one; a player who leaves is out of the results until the next session. Nobody can pause.
- **Results:** position, total time, best lap, gaps, laps, penalties and the assists each player drove with (ACC-07). Championship points in career events.
- **Pit lane, repairs, tire wear:** later (M10).

## 2. Kart

*MODE-05, AI-02, EDT-04. Milestone M8.*

Your own cars, with an arcade physics layer and items. It plays on **any track**; if a track has no item boxes, rows are placed automatically about every third of a lap. It also plays on purpose-built **stunt tracks** that use editor pieces.

### Items

Original names and effects. Each racer holds one item, and triple items count as one slot.

| Item | Effect |
|---|---|
| **Nitro** | Short boost |
| **Nitro ×3** | Three short boosts |
| **Oil Slick** | Dropped behind. Anyone who drives over it spins out. |
| **Bolt** | Fires straight ahead. Bounces off walls up to 3 times. Spins out the car it hits. |
| **Seeker** | Homes in on the next car ahead along the track spline |
| **Leader Hunter** | Travels the racing line to the race leader (rare; only for the back of the field) |
| **Shield** | Blocks one hit. Lasts 8 s. |
| **EMP** | A pulse around you. Nearby cars lose power for 2 s. |
| **Magnet** | Pulls you toward the car ahead (×3 slipstream) for 3 s |

- **Item odds** depend on race position (stronger items for those further back). They are defined in `data/items/odds.json`. This is the only catch-up mechanic: no grip or speed rubber-banding (AI-05).
- **Drift-boost** tiers: blue at 0.6 s, orange at 1.2 s, purple at 2.0 s.
- **Falling off the track:** the tow drone returns you to the last spline point, costing 1.5 s.
- **Classes:** Light, Medium, Heavy. Trade-offs between acceleration, top speed and weight (heavier wins bumps).
- **Battle mode:** arena tracks (editor type `arena`). Each player has 3 lives, and only items deal damage. Last one standing wins, or most hits in a timed match.
- **Cups:** 4-track playlists with points (career).

## 3. Highway

*MODE-03, MODE-04, AI-03, AI-04, EDT-10. Milestone M7 (D106–D124).*

High-speed driving through traffic on a multi-lane highway that closes into a loop, with on and off ramps. The first map, the **Lumen Ring** (8.3 km, D121), is made with the track editor; open-ended highways and a generator come with Endless (M9).

**Start:** title → Highway → the track → what to do (mode, traffic Off/75/150/250/400, police, which way round: clockwise, anticlockwise or both ways in turn; the run for Runs) → the class (Street or Super) → players. Players start in single file on the hard shoulder behind the lap line. Online, the host picks "Highway cruise" in the host menu.

### Traffic

- Every game runs the same traffic from the session's seed (D108, D109): hatchbacks, saloons, SUVs, vans, trucks and buses (an original low-poly set, D117), each with its own speed spread.
- Cars keep to lanes, signal for 1.5 s before changing lanes, keep right unless overtaking (trucks and buses stay in their lanes), slow for corners and the tunnel's limit, take exits and join from entries. The same cars come round again: a car that leaves at an exit comes back later out of a portal.
- Near a player a car becomes a full physics car (D110): it can be hit, spun and wrecked. A wreck stays where it stopped until nobody is near, then it's towed. Further away cars are drawn from the lane sim.
- Not yet: density by time of day (with the day–night cycle, M9).

### Sub-modes

| Sub-mode | Description |
|---|---|
| **Cruise** | Free roam. No score. Chat. "Join" in the pause menu puts you behind another player. |
| **Score attack** | Near-miss scoring with combos (below) |
| **Runs** | A sprint between two marks through traffic: lanes closed behind the start (a traffic break), a rolling start at 90 km/h, each player's clock starting at the line, a checkpoint every 400 m (an exit or a flyover is out of the run), results and a board. Solo or splitscreen head-to-head; online runs come later. |
| **Loop** | Lap times each way round (below) |
| **Police** | A toggle on top of any sub-mode (below) |

### Score attack

| Event | Points |
|---|---|
| Near miss | 100: under 1.0 m hull to hull while passing 30 km/h faster or more |
| Close miss | 200: under 0.5 m |
| Lane split | +300: two close passes either side within 0.6 s |
| Speed multiplier | Nothing under 120 km/h; ×1 from 120, ×1.5 from 160, ×2 from 200, ×3 from 250 |
| Combo | Each event within 5 s of the last grows it: ×1 for the first, +0.25 for each after, at most ×5 |

- **Banking:** the chain's points × the combo bank once 5 s pass with no event. Any contact over 20 N·s with traffic, police or a wall **loses what isn't banked**. Going the wrong way scores nothing.
- **HUD:** the banked score, the chain and its multiplier, a bar for the time left before it banks, the speed step, and a line for each pass ("Close miss +300", "Combo ×4", "Banked 2500", "Lost 1200"); banked and lost are read out with race narration and captioned.
- **Leaderboards:** each player's best of a session on the local board; online the server scores every player itself and keeps its own boards (D114, D118).

### Police

- A unit waits at each **speed trap**, parked on the shoulder. Only what a unit sees counts (within 250 m, in line of sight): speeding 20 km/h over the limit (+1 heat every 2 s), a near miss (+1), a close miss (+2), a crash (+3), ramming a unit (+5).
- **Heat 1–5** (from 1, 6, 15, 30 and 50 points): that many units after you, sent in from behind out of sight, sirens and light bars on. From heat 4 a **roadblock** ahead: every lane but the outer one closed, two units across. Not yet: spike strips, traffic pulling over for sirens, and patrols cruising in traffic (units wait at the traps or come in when sent).
- **Busted:** under 10 km/h with a unit touching you or within 0.6 m for 3 s. You lose the unbanked score and the heat, and start again on the shoulder.
- **Evaded:** out of every unit's sight and over 300 m from them all for 8 s + 4 s per heat level.
- Police drive **Interceptors**. The HUD shows the heat (pips and the word) and how close you are to losing them; sirens show on the sound arrows. With Reduce flashing the light bars flash at most three times a second (D116). Players as police come later (M10+).

### Loop

A highway that closes on itself, like a city ring expressway. The world feels lived-in: the same players, cars and landmarks come round again.

- **Map:** a `highway` track whose main road is a closed loop ([TRACK_EDITOR.md §1](TRACK_EDITOR.md#1-track-types)), with a carriageway each way split by a barrier, plus ramps.
- **Direction:** picked before the start (or both ways, in turn). Switch at a flyover crossover, or with "Change direction" in the pause menu.
- **Other players:** going the other way they pass you across the barrier, so you keep seeing them (measured on the Lumen Ring: 2–6 times a lap). Names float over other players' cars within 400 m, across the barrier too; the horn and a light flash work as greetings.
- **Persistent traffic:** the whole population keeps going round; a few cars leave and join at the ramps (measured: 92–94% of the cars met on the other carriageway one lap are met again the next).
- **Fixed sights:** skyline, flyovers, the tunnel and signs stay put, so laps become familiar.
- **Lap time:** a lap each way has its own board; a direction change, a portal or a reset makes it no lap. Online the server times the laps for its boards.
- **Wrong way:** ramps are one-way. Driving against the traffic shows "Wrong way" and stops the score.

## 4. Endless

*MODE-06, ENV-01…ENV-03. Milestone M9.*

A calm, never-ending drive, like Slow Roads.

- **Road generation:** chunks of ~250 m are generated ahead and removed behind, from a **seed**.
  - Curvature and elevation come from noise, constrained to stay drivable (max grade, minimum radius for the class speed).
  - Bridges and cuttings smooth out extreme terrain.
- **Biomes** change every few km with smooth transitions: coast, forest, farmland, desert canyon, alpine, snow, autumn. They are inspired by GT4-era environments (Grand Canyon, Swiss Alps, Deep Forest, Autumn Ring, Amalfi) but built from original assets.
- **Traffic:** light, in both directions. Oncoming traffic can be turned off.
- **Environment:** day/night and weather advance continuously. Time scale is adjustable (real time to fast).
- **Minimal UI:** the HUD is hidden by default. Ambient music.
- **Autodrive:** toggle, and the AI drives while you watch.
- **Sharing:** a "seed + start biome" code.
- **Multiplayer:** everyone drives the same seeded road as a convoy. If players drift far apart, those ahead are kept within one shared section of road. Floating origin ([ARCHITECTURE.md §8](ARCHITECTURE.md#8-floating-origin)).

## 5. Light career

*MODE-07. Milestone M10.*

- **Everything is playable from the start.** Career is optional structure on top.
- **Event ladders per mode:**
  - Track: Touring Cup → GT Series → Prototype Endurance → Formula Championship.
  - Kart: 4-track cups per class.
  - Highway: score and run challenges.
  - Endless: distance and biome milestones.
- **Rewards are cosmetic only:** paint finishes, decals (once the livery editor exists), nameplates, HUD themes, horn sounds.
- Progress is saved locally. Online play is unranked.

## 6. Leaderboards

- **Local:** per track, platform and mode.
- **Per server:** kept by the host or dedicated server.
- **Recorded entries** store the platform id and hash, the track hash and the game version. Only `official.*` platforms count as "official" ([PLATFORMS.md §2](PLATFORMS.md#2-platform-file)).
- **Global leaderboards** need a central service, which is out of scope (NFR-11). A self-hostable option could come later.
