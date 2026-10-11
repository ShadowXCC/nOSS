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
  - Strictness: off / lenient / strict, set per event (per server in M5).
- **Flags** (an icon and a word each): green (start, and when a yellow clears), yellow (a stopped or slow car within 250 m ahead), blue (a car most of a lap up within 100 m behind; shown only), checkered (Finish).
- **Wrong way:** a warning, then after 5 s a respawn facing the right way.
- **Start:** the grid forms two staggered columns behind the line (12 m to pole, 13 m between cars in a column), held on the handbrake. Standing start: five lights, one a second, out after a short random wait. Rolling start: the field forms 220 m further back and runs at 80 km/h without passing; green comes 60 m before the line.
- **Race weekend (M4):** the Race menu picks practice and qualifying (off or a few minutes), race length (laps or minutes), AI cars (0–15) and skill, start, grid (qualifying, reverse, random), collisions, track limits, and whether AI cars come from the garage or the built-ins. When practice or qualifying time is up, cars finish the lap they're on. After the leader finishes, the others finish their lap (60 s at most); finished cars, players' included, take a cool-down lap driven by the AI. The pause menu offers Restart, End session (practice, qualifying) and Setup (not during races).
- **Resets in traffic:** with AI or in a race, a reset car waits off the track until nothing is coming within 4 s, then rejoins at the road's edge, see-through and without contact for 3 s (D66).
- **Free-drive (M1):** a car reset puts the car back on the track at the last valid spot and stops the current lap counting. Jumping ahead along the track (cutting across) does the same.
- **Local players (M3):** up to 4, one class for everyone, each with their own car, view, timer and reset spot. Cars start from a two-column grid behind the line; a reset steps back along the track if another car is on the spot. Players drop in with a free device and drop out from their pause menu; pause stops everyone.
- **Collisions:** on, or **ghosted** (no car-to-car contact), set per server.
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

*MODE-03, MODE-04, AI-03, AI-04, EDT-10. Milestone M7.*

High-speed driving through traffic on long multi-lane highways with on/off ramps, either open-ended or a closed loop. The first map is built with the editor; a procedural highway generator comes later.

### Traffic

- Spawned by the server from a seed and density settings ([NETWORKING.md §6](NETWORKING.md#6-server-owned-simulation)).
- Lane-following AI that signals before changing lanes, with a speed spread per lane.
- Vehicle types: cars, vans, trucks, buses (original low-poly set).
- Density follows time of day: rush hour, quiet nights.

### Sub-modes

| Sub-mode | Description |
|---|---|
| **Cruise** | Free roam. No score. Chat. "Join friend" teleports you to a friend. |
| **Score attack** | Near-miss scoring with combos (below) |
| **Runs** | Point-to-point between exits or markers through traffic. Rolling start, checkpoints. Solo time attack or head-to-head. |
| **Loop** | A closed highway driven both ways. You keep meeting the same players and traffic each lap (below). |
| **Police** | Toggle that layers on top of any sub-mode (below) |

### Score attack

| Event | Points |
|---|---|
| Near miss | Gap < 1.0 m (hull to hull) while passing at > 30 km/h relative speed |
| Close miss | Gap < 0.5 m. Double points. |
| Lane split | Passing between two side-by-side vehicles. Bonus. |
| Speed multiplier | ×1 at 120 km/h, ×1.5 at 160, ×2 at 200, ×3 at 250+ |
| Combo | Grows with each near miss within a 5 s window |

- **Banking:** points stay unbanked while the combo runs. They bank once the combo ends cleanly (no events for 5 s). Any contact with traffic or a wall **loses all unbanked points**.
- **Leaderboards:** per server and local best.

### Police

- **Heat 1–5** rises with speeding in view of police, near misses and crashes. Higher heat brings more units, then roadblocks (heat 4+), then spike strips (heat 5, later).
- **Busted:** police contact while your speed stays under 10 km/h for 3 s. You lose unbanked score and heat, and respawn.
- **Evade:** break line of sight and keep > 300 m away until the cooldown ends.
- Police drive **Interceptor** platforms. Players as police comes later (M10+).

### Loop

A highway that closes on itself, like a city ring expressway. The world feels lived-in: the same players, cars and landmarks come round again.

- **Map:** a `highway` track whose main road forms a closed loop ([TRACK_EDITOR.md §1](TRACK_EDITOR.md#1-track-types)), with two carriageways (clockwise and counter-clockwise) split by a barrier, plus ramps.
- **Direction:** pick one when you spawn. Switch at any interchange, or pick again when you respawn.
- **Other players:** players going the other way pass you head-on across the barrier, so you keep seeing them. At similar speeds, two players going opposite ways meet about twice per lap. Players going your way are caught or catch you. Nameplates show across the barrier, and horn and light flashes work as greetings.
- **Persistent traffic:** the loop's whole traffic population keeps circulating instead of despawning behind you, so you pass the same cars again. A few vehicles leave and join at ramps so it never feels frozen.
  - Every traffic car on the loop is a lightweight lane follower in `noss_core`. Only cars near a player become full vehicles.
  - Online, the server still sends just a seed plus ramp spawn and exit events ([NETWORKING.md §6](NETWORKING.md#6-server-owned-simulation)).
- **Fixed sights:** skyline, bridges, tunnels and signs stay put, so laps become familiar.
- **Lap time:** optional. A gantry marks the lap line and each direction has its own best time. Local and per-server leaderboards.
- **Wrong way:** ramps are one-way. Driving against traffic shows "Wrong way" and pauses scoring.
- **Combines with:** cruise, score attack and police all run on a loop map.

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
