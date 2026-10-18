# Gamemodes

Rules and flow for each mode. Every mode uses the same vehicle core ([PHYSICS.md](PHYSICS.md)). Each mode offers its own platform classes ([PLATFORMS.md §6](PLATFORMS.md#6-starter-classes)). Requirements: MODE-01…MODE-07, AI-01…AI-05, ENV-01…ENV-03.

---

## 0. Common to all modes

- **Flow:** Lobby → (Practice) → (Qualifying) → Main session → Results. Single player goes straight to the session.
- **Before a session:** each player picks a **class** (platform), a **car** (package) and **assists**.
- **AI** fills empty slots where the mode supports it, with skill 0–100.
- **Environment (D153):** every event menu has three sky rows.
  - **Time:** Track's (the track's own fixed sun), Dawn, Morning, Noon, Afternoon, Dusk or Night.
  - **Time runs:** still, real time, or 10×, 30×, 60× or 120×.
  - **Weather:** Track's, Clear, Cloudy, Rain, Storm, Fog, Snow, or Changing (fronts of 4–12 minutes, blending over a minute).
  - Nothing changes unless you pick something. A track's `environment` block is the default; without one it's today's look (clear, a fixed sun).
  - The sun and moon share one light. At night: stars, a moon, lamps lit, headlights on (also in rain and fog), lit beams from the players' cars and the four nearest.
  - Rain soaks the road over about 90 s and it dries over 15 minutes; snow settles over 2½ minutes and melts over 30. A wet road shines and grips less, a snowy one turns white and grips much less ([PHYSICS.md §4](PHYSICS.md#surfaces)). Tunnels stay dry.
  - Rain and snow fall round each player's camera, with spray behind cars on wet roads, and sounds for rain, wind and thunder. Storms bring lightning: a soft pulse under Reduce flashing ([ACCESSIBILITY.md §4](ACCESSIBILITY.md#4-motion-comfort-and-flashing)).
  - The sky is worked out from the settings and the clock, so online every game shows the same one (the server's seed and clock, D159); admins change it with `/time` and `/weather`.
  - Leaderboards and ghosts record a wet or snowy road; such laps are tagged on the boards.
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
- **Start:** the grid forms two staggered columns behind the line (12 m to pole, 13 m between cars in a column), held on the handbrake. Standing start: five lights, one a second, out after a short random wait. Rolling start: the field forms 220 m further back and runs at 80 km/h without passing; green comes 60 m before the line. Each light beeps as it comes on; when they go out (or at the rolling green) they show green for a second with a higher tone. Online, an event's first session waits until every game has the cars ("Syncing 2/3", 3–30 s, D127); a race then starts as above, any other session with three lights.
- **Race weekend (M4):** the Race menu picks practice and qualifying (off or a few minutes), race length (laps or minutes), AI cars (0–15) and skill, start, grid (qualifying, reverse, random), collisions, track limits, and whether AI cars come from the garage or the built-ins. When practice or qualifying time is up, cars finish the lap they're on. After the leader finishes, the others finish their lap (60 s at most); finished cars, players' included, take a cool-down lap driven by the AI. The pause menu offers Restart, End session (practice, qualifying) and Setup (not during races).
- **Resets in traffic:** with AI or in a race, a reset car waits off the track until nothing is coming within 4 s, then rejoins at the road's edge, see-through and without contact for 3 s (D66).
- **Free-drive (M1):** a car reset puts the car back on the track at the last valid spot and stops the current lap counting. Jumping ahead along the track (cutting across) does the same. Free Drive's setup screen picks the track, AI cars (0–15) driving laps alongside, their skill and whether they come from the garage or the built-ins, collisions and track limits; the last setup is remembered.
- **AI paint (D128):** each AI car wears one of its car's paint presets or its own paint, at random; a car with no presets gets a common car colour. Online the server picks and every game shows the same.
- **Local players (M3):** up to 4, one class for everyone, each with their own car, view, timer and reset spot. Cars start from a two-column grid behind the line; a reset steps back along the track if another car is on the spot. Players drop in with a free device and drop out from their pause menu; pause stops everyone.
- **Collisions:** on, or **ghosted** (no car-to-car contact), set per event; online the event comes from the server's rotation.
- **Online (M5):** the server runs the weekend: its grid, lights, flags, penalties and results; each game drives its own cars and follows the server's state. The server fills the grid with AI up to the event's count (16 cars at most). Players who join during a race weekend wait in the lobby for the next one; a player who leaves is out of the results until the next session. Nobody can pause.
- **Results:** position, total time, best lap, gaps, laps, penalties and the assists each player drove with (ACC-07). Championship points in career events.
- **Pit lane, repairs, tire wear:** later (M10).

## 2. Kart

*MODE-05, AI-02, EDT-04. Milestone M8 (D129–D151).*

Your own cars on the kart classes, with an arcade physics layer and items. It plays on **any track**; if a track has no item boxes, rows go about every third of a lap. It also plays on purpose-built **stunt tracks** (Gearworks, Skyhop Ridge) and plain kart tracks (Marble Mile), and battles on **arenas** (Crate Yard, Dust Bowl). From the title: **Kart**, then Race, Battle or Cup, then the players, each with a car and a class.

- **Classes:** Light (160 kg, pulls hardest), Medium (200 kg), Heavy (260 kg, wins the bumps). Their top speeds are within 1% of each other, so lap times are within 2% at the same skill (D134). Every player picks their own class, and each AI kart picks its own (D149). The built-in car is the nOSS Kart; a bigger car is shrunk to kart size (D150).
- **Drift:** hold Drift while steering into a corner at 8 m/s or more. The longer it's held, the bigger the boost when you let go: blue at 0.6 s, orange at 1.2 s, purple at 2.0 s (0.5, 0.9 and 1.4 s of boost). Boost pads give 0.8 s.
- **Air:** off a jump, steer to turn and lean; press Drift just after take-off for a trick (a boost if you land upright). A kart left on its roof rights itself.
- **Falling off:** the tow drone takes you back to the road in 1.5 s and puts you down rolling, for a moment a ghost. So does Reset, and a kart left stuck on another.
- **Walls** bounce karts back; karts bump each other (the heavier wins).

### Items

Original names and effects. Each racer holds one item, and triple items count as one slot. A box rolls for 1.2 s; driving through one while holding an item breaks it for nothing; boxes come back after 3 s.

| Item | Effect |
|---|---|
| **Nitro** | A 1 s boost |
| **Nitro ×3** | Three 1 s boosts |
| **Oil Slick** | Dropped behind (with Throw back: thrown 15 m ahead). Anyone who drives over it spins out. |
| **Bolt** | Fires straight ahead (with Throw back: behind). Bounces off walls up to 3 times. Spins out the kart it hits; after a bounce, that can be yours. |
| **Seeker** | Follows the road to the next kart ahead and homes in on it |
| **Leader Hunter** | Travels the racing line to the leader, passing the rest (rare; only for the back half of a field of 4 or more; one at a time) |
| **Shield** | Blocks one hit of any kind. Lasts 8 s. |
| **EMP** | A pulse 18 m round you. Karts in it lose power for 2 s. |
| **Magnet** | Pulls you toward the kart ahead (×3 slipstream) for 3 s |

- **Item odds** depend on race position (stronger items further back), in `data/items/odds.json`. This is the only catch-up: no grip or speed rubber-banding (AI-05).
- A hit spins a kart out for 1.2 s. Karts behind another within 30 m get its slipstream.
- **Item assist** (Player settings): the game uses your item when it pays, as the AI would.

### Battle

On an arena (track type `arena`). Each kart has 3 lives; a Bolt, Seeker, Oil Slick or EMP hit takes one, and after a hit items pass the kart by for 2 s.
- **Last one standing:** a kart with no lives left is out (it drives on as a ghost, with no items). It ends with one kart left, or at the time limit; ranked by lives, then hits.
- **Most hits:** nobody goes out. The first to the hits target (10 by default; 5–20, or none) wins; otherwise at the time limit (3 minutes by default), ranked by hits, then fewest taken. The HUD shows your hits, the target, your place and the top of the table (D151).

### Cups

Four races for points (15, 12, 10, 8, 6, 4, 2, 1); ties go to the most wins, then the better last race. The first race's grid is random, then the standings reversed. The AI field stays the same through a cup. The built-in **Spark Cup**: Proving Ground (2 laps), Marble Mile, Gearworks, Skyhop Ridge (3 each). Make your own from any circuits under Kart → Cup → New cup (saved in `user://cups/`). Cups are offline (splitscreen too).

### Online

Kart races and battles run on servers (protocol 5): the server rules on boxes, items and hits, and each game shows its own items at once (D141, NETWORKING.md §11). Host → Event offers Kart battle. In a kart lobby your row picks your car and your class; the server's AI karts pick their own.

## 3. Highway

*MODE-03, MODE-04, AI-03, AI-04, EDT-10. Milestone M7 (D106–D124).*

High-speed driving through traffic on a multi-lane highway that closes into a loop, with on and off ramps. The first map, the **Lumen Ring** (8.3 km, D121), is made with the track editor; open-ended highways and a generator come with Endless (M9).

**Start:** title → Solo Drive → Highway → the track → what to do (mode, traffic Off/75/150/250/400, police, which way round: clockwise, anticlockwise or both ways in turn; the run for Runs) → the class (Street or Super) → players. Players start in single file on the hard shoulder behind the lap line. Online, the host picks "Highway cruise" in the host menu.

### Traffic

- Every game runs the same traffic from the session's seed (D108, D109): hatchbacks, saloons, SUVs, vans, trucks and buses (an original low-poly set, D117), each with its own speed spread.
- Cars keep to lanes, signal for 1.5 s before changing lanes, keep right unless overtaking (trucks and buses stay in their lanes), slow for corners and the tunnel's limit, take exits and join from entries. The same cars come round again: a car that leaves at an exit comes back later out of a portal.
- Near a player a car becomes a full physics car (D110): it can be hit, spun and wrecked. A wreck stays where it stopped until nobody is near, then it's towed. Further away cars are drawn from the lane sim.
- Not yet: density by time of day. The lane sim's population is fixed for the session, so the day–night cycle (M9) doesn't change it.

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

*MODE-06, ENV-01…ENV-03. Milestone M9 (D152–D159).*

A calm, never-ending drive, like Slow Roads.

**Start:** title → Solo Drive → Endless → the road (a road code, or New road), the biome it starts in, traffic (Light, Normal or Off), oncoming traffic, what happens when players on this PC drift apart, and the sky (Morning, 30×, Changing by default) → the class (Cruiser or Sport) → players. The last setup is remembered. Online, the host picks "Endless road" in the host menu.

- **The road (D152):** a two-lane road made 2 m at a time from the seed, in integers only, so every machine makes the same road.
  - Bends are clothoids picked per biome, never tighter than the biome allows. The road keeps within 75° of a main direction picked from the seed, so it never crosses itself (no hairpins).
  - The height follows the ground ahead within the biome's grade and crest limits. Where the road runs well above the ground it's a bridge with pillars; where the ground drops away beside it, a guard rail. Tight bends get chevrons.
  - It comes in 240 m chunks, made about 3 km ahead and dropped about 1 km behind. Any chunk can be made again exactly (driving back, a player joining far along).
- **Biomes (D156):** coast, forest, farmland, desert canyon, alpine, snow and autumn follow each other every 4–7 km, blending over 1.5 km. Inspired by GT4-era places (Amalfi, Deep Forest, the Grand Canyon, the Swiss Alps, Autumn Ring), built from original assets. Each has its own ground, paint, road, props, sky and fog tints, sounds (birds, crickets, surf) and weather odds. Its name shows as you enter it.
- **The world (D156):** the ground in 256 m tiles near the road (shaped to it, with props scattered from the seed), coarse 1 km tiles out to the horizon, and the sea along the coast. It's all made on worker threads and added a little each frame, and dropped behind you, so memory stays flat however far you drive.
- **Floating origin (D155):** the scene moves back every 2 km, so positions stay precise ([ARCHITECTURE.md §8](ARCHITECTURE.md#8-floating-origin)). Measured: 162 km in 2 hours, with the same precision in the last 10 minutes as in the first.
- **Traffic (D158):** light, both ways; oncoming traffic can be turned off. Where every car is comes from a schedule worked out from the seed and the clock, so the same cars are in the same places on every game and no two in a lane ever meet. Within 140 m of a player a car becomes a physics car that keeps to its slot unless something's in the way. Knocked hard, rolled, or left 25 m behind its slot, it leaves the slot for good (a knocked car stops with its hazards on), and goes once nobody's near.
- **Autodrive:** the pause menu or the Autodrive key (O on the keyboard) hands the car to the AI and back. It keeps to the right-hand lane, slows for bends and wet roads, follows traffic and overtakes on clear straights when nothing's coming.
- **Minimal HUD:** hidden until shown from the pause menu (speed, gear, assists); laps and places never show. Captions and messages always do.
- **Music:** your own OGG and MP3 files from the music folder (`user://music/`), shuffled; otherwise original ambient pieces made from the seed, each played twice before the next fades in.
- **Sharing:** a road code, the start biome and the seed, e.g. `FOREST-0007K2Q` (Crockford base 32; case and O-for-0 typos don't matter). The pause menu copies it.
- **Resets** put the car back in its lane where it last was, ghosted for 3 s.
- **Players on one PC** stay on one stretch of road. Past 2.5 km apart they're warned; past 3 km the event's rule acts: **Bring up the one behind**, or **Hold the leader back**.
- **Online (D159):** everyone drives the same road. Each game builds the road round its own players and keeps its own origin, so players spread out freely; **Join** in the pause menu puts you just behind another player, at their speed. At the start everyone lines up in single file in the roster's order; a joiner starts just behind whoever's furthest along. Online cars start ghosted for 3 s. One game drives each traffic car near players and the others show it; a slot used up on one game is used up on all. The server checks the road chunks each game made against its own.

## 5. Sumo Wrestling

*Mini Games. D162–D166.*

Shove everyone else off a floating platform. It plays on **generated platforms**, not a track: the arena is built from the match's own settings, so there is nothing to pick, nothing to download and nothing of it on the wire. From the title: **Solo Drive → Mini Games → Sumo Wrestling**.

- **The arena (D162):** 1 to 3 discs stacked on one centre inside a rock pit, with lava or acid at the bottom. The top one is 24 m across the radius, each one below is wider (36 m, 48 m) and 18 m further down, so a car knocked off lands on the next rather than sailing past it (D163). The platforms have a sloped rim that catches a car landing on the edge; the rim is not floor to drive on.
- **The shrink:** the top platform starts shrinking when the lights go out; a lower one only once a car has actually landed on it, so the tiers below stay full size until they are needed. A platform takes **Short (60 s), Normal (90 s) or Long (150 s)** to go, and shrinks one of three ways:
  - **Smooth:** the edge creeps in steadily.
  - **Stepped:** a whole ring goes every sixth of the time, with a warning just before.
  - **Crumbling:** the same, with the lost ring breaking into lumps that tumble into the goo.
- **Falling:** nothing tows you back. Knocked off the top platform you fall to the next one; off the bottom one you are in the goo. Air control works on the way down, so the fall can be steered.
- **The goo:** touch the lava or acid and you are **out** — a splash, the car sinks over a second and drives on no more. The moment of contact is what counts, not the sinking.
- **Winning:** the **last car not in the goo**. The platforms are the extra lives, not ranks: a survivor down on the third beats everyone already in. Cars that are out are ranked by when they went in, the last one first — so with the floor vanishing under the last two, whoever holds on a fraction longer wins.
- **Sudden death (off by default):** the bottom platform stops at a 6 m pillar instead of going altogether. It holds for 25 s and then gives way too, so two cautious drivers cannot stall a match for ever.
- **Ram boost (D164):** a rechargeable lunge on its own **Ram** button (about 5 s to charge, shown as a bar). It only fires while you are moving, so it is a shove and not a standing start. There are no items.
- **The class:** one class, **Sumo** — 900 kg, all-wheel drive, grippy and slow, so every car shoves the same. **Any model may be mounted**, car, open-wheeler, truck or bike; an oversized one is scaled down as karts do (D150). Mass and grip come from the class, never the model, so nobody wins by bringing a lorry.
- **HUD:** cars left, which platform you are on and how much of it is left, and the ram's charge. No laps, sectors, places or flags. Short lines only: "Tier 2", "Shrinking", "Out", "Last one", "Winner".
- **AI (D165):** bots hunt the nearest car on their own platform, break off when the edge gets close (the better the driver, the later), and spend their ram when the target is close, lined up, and nearer the edge than they are.
- **Local players:** up to 4 in splitscreen, each with their own car.
- **Online (D166):** the server shrinks the platforms and rules on who is in the goo. Only the radii and each car's platform, out and ram charge go over (protocol 7) — the arena itself needs no syncing, since the same settings build the same platforms everywhere. A ring-out is sent at once so the splash lands on the tick it happened. Nobody joins a match in progress; they are in the next one.
- **Results:** the platform each car reached and how long it lasted, with the winner shown as "Won".

## 6. Light career

*MODE-07. Milestone M10.*

- **Everything is playable from the start.** Career is optional structure on top.
- **Event ladders per mode:**
  - Track: Touring Cup → GT Series → Prototype Endurance → Formula Championship.
  - Kart: 4-track cups per class.
  - Highway: score and run challenges.
  - Endless: distance and biome milestones.
- **Rewards are cosmetic only:** paint finishes, decals (once the livery editor exists), nameplates, HUD themes, horn sounds.
- Progress is saved locally. Online play is unranked.

## 7. Leaderboards

- **Local:** per track, platform and mode.
- **Per server:** kept by the host or dedicated server.
- **Recorded entries** store the platform id and hash, the track hash and the game version. Only `official.*` platforms count as "official" ([PLATFORMS.md §2](PLATFORMS.md#2-platform-file)).
- **Global leaderboards** need a central service, which is out of scope (NFR-11). A self-hostable option could come later.
