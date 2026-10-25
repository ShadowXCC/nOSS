# Gamemodes

Rules and flow for each mode. Every mode uses the same vehicle core ([PHYSICS.md](PHYSICS.md)). Each mode offers its own platform classes ([PLATFORMS.md §6](PLATFORMS.md#6-starter-classes)). Requirements: MODE-01…MODE-07, AI-01…AI-05, ENV-01…ENV-03.

---

## 0. Common to all modes

- **Flow:** Lobby → (Practice) → (Qualifying) → Main session → Results. Single player goes straight to the session.
- **Before a session:** each player picks a **class** (platform), a **car** (package) and **assists**.
- **AI** fills empty slots where the mode supports it, with skill 0–100.
- **Other players (D199):** name tags float over other players' cars (splitscreen and online, never bots) within 400 m: their name, how far, and a triangle down at the car. The HUD's "Name tags" element hides them.
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
- **Race weekend (M4):** the Race menu picks practice and qualifying (off or a few minutes), race length (laps or minutes), AI cars (0–15) and skill, start, grid (qualifying, reverse, random), collisions, track limits, and whether AI cars come from the garage or the built-ins.
- **Drafting (D208):** with Drafting on, a car close behind another meets less air (up to 30% less drag), and the car in front a little less; heavy, draggy classes like the Stock Car feel it most. Online each game drafts its own cars and the server allows the faster top speed and laps it gives.
- **Pack racing (D213):** on a track that suggests it (Piedmont Speedway), with Drafting on, the AI races in grooves: three lanes 3.8 m apart round the racing line. Each car follows the one ahead in its groove close in the draft. With a free groove beside it, it closes right up and pulls out to pass (a run), and drops back in behind if the run dies. Cars hold their grooves side by side, and a car with a run coming at it may move over to block it (as likely as it's skilled).
- **Fuel and tires (D209):** with Fuel use or Tire wear on, cars burn fuel and wear their tires (times the car's own rates: at 1× a Stock Car runs about 59 laps of Piedmont Speedway on a tank). Worn tires grip less (to 85% of new); a car out of fuel only coasts. The HUD shows "Fuel 12 laps" (litres until a lap has been measured) and "Tires 86%" (a "Fuel and tires" element in the HUD settings), says "Fuel low" under two laps and "Out of fuel". Pit stops (D210) fill up and fit tires.
- **Pit stops (D210):** on a track with a pit lane. Set the next stop's service while driving (Pit fuel: Full, Finish, Half, No fuel; Pit tires: 4, 2, none; keys in [INPUT.md](INPUT.md), or the pause menu); it locks as you enter the lane. Between the limit lines the limiter holds you to the lane's speed. Stop in your box (boxes in grid order; your panel counts down to it) and the crew works: the longer of the fuel (6 L a second) and the tires (11 s for four, 6 s for two), plus 0.8 s; then "Go". Repairs wait for a damage system. With neither fuel use nor tire wear on the lane is a drive-through. The AI pits when its fuel won't last much more than two laps, or its tires are worn with laps to go, asking for enough fuel to finish. Online each game runs its own cars' stops.
- **Track-suggested rules (D207):** Start, Drafting, Fuel use and Tire wear each default to **"Track's"**: whatever the track suggests in its `rules` (shown in the row, "Track's (Rolling)"), or an event's own (Standing/Rolling; Off/On; Off or 1×–10× the car's own rate). A track that suggests nothing races as tracks always have: standing start, no drafting, no fuel use or tire wear. The session races a copy with the track's choices put in; the remembered setup keeps "Track's" for the next track. A setup saved before this, with a standing start, moves to "Track's" once. Piedmont Speedway suggests a rolling start, drafting on, fuel and tires at 5×, and pack racing for the AI. Dev flags: `--race-start`, `--race-draft`, `--race-fuel`, `--race-tyres`. When practice or qualifying time is up, cars finish the lap they're on. After the leader finishes, the others finish their lap (60 s at most); finished cars, players' included, take a cool-down lap driven by the AI. The pause menu offers Restart, End session (practice, qualifying) and Setup (not during races).
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

**Start:** main menu → Local Drive → Highway → the track → what to do (mode, traffic Off/75/150/250/400, police, which way round: clockwise, anticlockwise or both ways in turn; the run for Runs) → the class (Street or Super) → players. Players start in single file on the hard shoulder behind the lap line. Online, the host picks "Highway cruise" in the host menu.

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

The police are one core shared with the endless road (`game/modes/police/`, D192).

- A unit waits at each **speed trap**, parked on the shoulder, and **patrol cars** ride in the traffic (2%). Only what a unit or patrol sees counts (within 250–350 m by heat, in line of sight): speeding 20 km/h over the limit (+1 heat every 2 s), a near miss (+1), a close miss (+2), a crash (+3), ramming a unit (+5).
- **Heat 1–5** (from 1, 6, 15, 30 and 50 points): that many units after you, a patrol nearby joining where it is, the rest sent in from behind out of sight, sirens and light bars on. More heat, faster and harder: they close 10–22 m/s faster than you. At heat 1 they go at most 1.6× the limit, so you can outrun them; from heat 2 nothing caps them but the bends and the car, and they take bends and brake harder as heat rises (half their tyres' grip at heat 1, up to 0.88 at heat 5). They never sit back behind you as if you were traffic (D201).
  - Up close each unit has a role: at heat 1 they **tail** you; at 2–3 they **ram** your rear quarter and one gets ahead to **block** (never slower than 40% of your speed); at 4–5 they try the **PIT** from either side (line up on your rear wheels, turn in, back off) and block. Stop, and they **box you in**: every unit noses up to you, or backs into you if you're behind it, until one touches (D201).
  - From heat 3 **spike strips** on a straight 300–450 m ahead (every 45 s at 3, down to 25 s at 5), half a lane left open: a flat tyre grips about half as well for 30 s or until a reset. Offline only for now: online the server can't flatten a tyre on a car another game drives.
  - From heat 4 a **roadblock** ahead: every lane but the outer one closed, two units across, light bars on.
  - From heat 2, **units wait ahead** on top of the chasers: one (two at heat 4–5) parked on the shoulder out of sight ahead, light bar on, and "Police ahead" shows. It pulls out as you come, timed to your speed (going about three quarters of it as you reach it), blocks while it's in front of you and, once you're past, rams (heat 2–3) or tries the PIT (4–5). Left 450 m behind, it goes ahead to wait again, so at two one waits while the other chases. None goes ahead while you're getting away (the evade meter filling) (D201).
  - Traffic **moves over** for a siren: the lane sim moves its cars out of the unit's lane, and physics cars slow.
- **Busted:** under 10 km/h with a unit touching you or within 0.6 m for 3 s. You lose the unbanked score and the heat, and start again on the shoulder.
- **Evaded:** out of every unit's sight and over 300 m from them all for 8 s + 4 s per heat level.
- Police drive **Interceptors**: a Super's pace (power for its weight, top speed, grip) at 1700 kg (D201). The HUD shows the heat (pips and the word) and how close you are to losing them; sirens show on the sound arrows. With Reduce flashing the light bars flash at most three times a second (D116). Players as police come later (M10+).

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

**Start:** main menu → Local Drive → Endless → the road (a road code, or New road), the biome it starts in, lanes (2 or 4), the side traffic drives on (Right or Left), traffic (Light, Normal, Heavy or Off), garage cars in the traffic, oncoming traffic, speed traps, police, what happens when players on this PC drift apart, and the sky (Morning, 30×, Changing by default) → the class (Cruiser or Sport) → players. The last setup is remembered. Online, the host picks "Endless road" in the host menu.

- **The road (D152):** a road made 2 m at a time from the seed, in integers only, so every machine makes the same road.
  - **Lanes (D190):** one or two each way, driven on the right or the left. The edges are solid white; one each way has a dashed centre line, two each way a double solid one and dashed lane lines. The centre line is yellow driving on the right and white on the left. Lanes and side don't change the road code: the road is the same, only its lanes differ.
  - Bends are clothoids picked per biome, never tighter than the biome allows. The road keeps within 75° of a main direction picked from the seed, so it never crosses itself (no hairpins).
  - The height follows the ground ahead within the biome's grade and crest limits. Where the road runs well above the ground it's a bridge with pillars; where the ground drops away beside it, a guard rail. Tight bends get chevrons.
  - **Limits (D193):** each biome has its own (80 km/h on the coast, in the forest and in autumn, 100 on farmland and in the canyon, 60 in the Alps and the snow), two steps lower round tight bends. Signs stand where the limit changes, in km/h or mph as your settings say.
  - It comes in 240 m chunks, made about 3 km ahead and dropped about 1 km behind. Any chunk can be made again exactly (driving back, a player joining far along).
- **Biomes (D156):** coast, forest, farmland, desert canyon, alpine, snow and autumn follow each other every 4–7 km, blending over 1.5 km. Inspired by GT4-era places (Amalfi, Deep Forest, the Grand Canyon, the Swiss Alps, Autumn Ring), built from original assets. Each has its own ground, paint, road, props, sky and fog tints, sounds (birds, crickets, surf) and weather odds. Its name shows as you enter it.
- **The world (D156):** the ground in 256 m tiles near the road (shaped to it, with props scattered from the seed), coarse 1 km tiles out to the horizon, and the sea along the coast. It's all made on worker threads and added a little each frame, and dropped behind you, so memory stays flat however far you drive. Cuttings are painted and planted as they're cut, the far ground stays under the near ground, and the ground stays under a bridge's deck (D187).
- **Off the road (D188):** the ground drives like a dirt road, whatever it's painted (grass, sand, snow), so you can climb back up a bank; falling snow still makes it slippery.
- **Floating origin (D155):** the scene moves back every 2 km, so positions stay precise ([ARCHITECTURE.md §8](ARCHITECTURE.md#8-floating-origin)). Measured: 162 km in 2 hours, with the same precision in the last 10 minutes as in the first.
- **Traffic (D158):** light, normal or heavy (a car every 48, 20 or 8 s a lane, D189), both ways; oncoming traffic can be turned off. With four lanes the passing lane runs quicker than the edge lane, and trucks and buses keep out of it (D190). Where every car is comes from a schedule worked out from the seed and the clock, so the same cars are in the same places on every game and no two in a lane ever meet. Within 140 m of a player a car becomes a physics car that keeps to its slot unless something's in the way. Knocked hard, rolled, or left 25 m behind its slot, it leaves the slot for good (a knocked car stops with its hazards on), and goes once nobody's near.
  - **Garage cars (D191, on by default):** most hatchbacks, saloons and SUVs (and vans, if one fits) are your own cars, in their own paints. Online everyone sees the host's.
- **Autodrive:** the pause menu or the Autodrive key (O on the keyboard) hands the car to the AI and back. It keeps to the lane traffic keeps to, slows for bends and wet roads, follows traffic and overtakes: in the passing lane with four lanes, in the oncoming lane on clear straights when nothing's coming with two.
- **Minimal HUD:** speed, gear and the RPM bar (D189), and the limit with speed traps or police on; Hide HUD in the pause menu hides them. Laps and places never show. Captions and messages always do.
- **Speed traps (D193, off by default):** cameras on poles and patrol cars parked on the verge, about one every 5 km. Going past one shows your speed ("Trap: 142 km/h"), and " · Best" when it's your best through that trap on this road code. A camera flashes (never with Reduce flashing). The pause menu shows how many you've passed and your top speed.
- **Police (D194, off by default):** as on highways (heat, units, rams, PITs, blocks, units waiting ahead on the verge, spike strips, roadblocks, traffic moving over), plus a camera's snap over the limit (+2 heat). Patrols ride in the traffic and the traps' parked patrols watch; either joins a chase where it is. Roadblocks close your lane with two lanes, or both lanes your way with four, leaving the shoulder. **Busted:** pulled over onto the shoulder, held a few seconds, then "Drive on"; the heat clears. Each player on one screen has their own heat.
- **Music:** your own OGG and MP3 files from the music folder (`user://music/`), shuffled; otherwise original ambient pieces made from the seed, each played twice before the next fades in.
- **Sharing:** a road code, the start biome and the seed, e.g. `FOREST-0007K2Q` (Crockford base 32; case and O-for-0 typos don't matter). The pause menu copies it.
- **Resets** put the car back in its lane where it last was, ghosted for 3 s.
- **Players on one PC** stay on one stretch of road. Past 2.5 km apart they're warned; past 3 km the event's rule acts: **Bring up the one behind**, or **Hold the leader back**.
- **Online (D159):** everyone drives the same road. Each game builds the road round its own players and keeps its own origin, so players spread out freely; **Join** in the pause menu puts you just behind another player, at their speed. At the start everyone lines up in single file in the roster's order; a joiner starts just behind whoever's furthest along. Online cars start ghosted for 3 s. One game drives each traffic car near players and the others show it; a slot used up on one game is used up on all. The server checks the road chunks each game made against its own. Each game runs the police for its own players (D195); everyone sees everyone's units, sirens and all, and their spike strips and roadblocks.

## 5. Sumo Wrestling

*Mini Games. D162–D166.*

Shove everyone else off a floating platform. It plays on **generated platforms**, not a track: the arena is built from the match's own settings, so there is nothing to pick, nothing to download and nothing of it on the wire. From the main menu: **Local Drive → Mini Games → Sumo Wrestling**.

- **The arena (D162, D184):** 1 to 5 discs stacked on one centre inside a rock pit, with lava or acid at the bottom. The top one is 24 m across the radius, each one below is wider (36, 48, 60, 72 m) and 18 m further down, so a car knocked off lands on the next rather than sailing past it (D163). The platforms have a sloped rim that catches a car landing on the edge; the rim is not floor to drive on. The pool sits 5 m under the lowest platform and the pit wall stands 45 m out, which is what puts the goo in view past the rim rather than hidden behind it — and the band of it widens as the platform shrinks, so it closes in on the eye as well as underfoot.
- **The shrink:** the top platform starts shrinking when the lights go out; a lower one only once a car has actually landed on it, so the tiers below stay full size until they are needed. A platform takes **Short (60 s), Normal (90 s) or Long (150 s)** to go, and shrinks one of three ways:
  - **Smooth:** the edge creeps in steadily. Nothing is marked: every edge is going at once.
  - **Stepped:** a whole ring goes every sixth of the time, marked 1.5 s before it goes.
  - **Crumbling (D182):** the floor comes off a piece at a time instead. Each platform is 16 wedges, and a bite out of one of them — a sixth of the radius deep, by a 22.5° arc — goes about once a second, in a shuffled order that takes every wedge once a step. The rim goes ragged without ever being more than one bite out of round, so there is no slot to fall down and no spike to trip on. The last step comes off as a whole ring. Each bite's lumps tumble into the goo, calving round the piece rather than bursting off it.
- **What is about to go (D182, D183):** the floor that is leaving lights up before it does — the whole doomed ring on a stepped platform, the one wedge next in line on a crumbling one, which keeps a band marching round the rim so there is always somewhere to look. It is the goo's own colour, laid over exactly the floor that will vanish, so the position says what it means and the colour is not carrying the message on its own; it pulses twice a second, and holds steady with **Reduce flashing** on. Smooth marks nothing, since it shrinks evenly everywhere.
- **Falling:** nothing tows you back. Knocked off the top platform you fall to the next one; off the bottom one you are in the goo. Air control works on the way down, so the fall can be steered.
- **The goo:** touch the lava or acid and you are **out** — a splash, the car sinks over a second and drives on no more. The moment of contact is what counts, not the sinking.
- **Winning:** the **last car not in the goo**. The platforms are the extra lives, not ranks: a survivor down on the third beats everyone already in. Cars that are out are ranked by when they went in, the last one first — so with the floor vanishing under the last two, whoever holds on a fraction longer wins. A whole ring going at once can drop two in on the same physics tick; the one less far under the surface got there later, and ranks ahead (D167).
- **Sudden death (off by default):** the bottom platform stops at a 6 m pillar instead of going altogether. It holds for 25 s and then gives way too, so two cautious drivers cannot stall a match for ever.
- **Ram boost (D164):** a rechargeable lunge on its own **Ram** button (about 5 s to charge, shown as a bar). It only fires while you are moving, so it is a shove and not a standing start. There are no items.
- **The drift (D181), a setting:** the kart's hop-and-slide, in three modes. **Drift** (the default) is the slide with no reward at the end of it; **Drift + boost** gives a long drift the kart's own boost when you let go; **Off** takes the button away altogether and hands the handbrake back (on a keyboard that is the same key). There is no drift spark, flame or boost meter here — a sumo match has no kart HUD.
- **In the goo (D185):** going in ends your match, not the match. The camera leaves your sunken car and goes up over the arena, following the fight, and the **Camera** button cycles a chase on each car still in. The HUD says "Out", how many are left, and who you are watching. The car itself stays where the goo took it.
- **The class:** one class, **Sumo** — 900 kg, all-wheel drive, heavy brakes and a modest top speed, so every car shoves the same. **Any model may be mounted**, car, open-wheeler, truck or bike; an oversized one is scaled down as karts do (D150). Mass and grip come from the class, never the model, so nobody wins by bringing a lorry. **AI models** is a setting (D180): **Garage** (the default) fields the bots in your own cars as well as the built-in ones, **Built-in** keeps them in the nOSS Box.
- **HUD:** cars left, which platform you are on and how much of it is left, and the ram's charge. No laps, sectors, places or flags. Short lines only: "Tier 2", "Shrinking", "Out", "Last one", "Winner".
- **AI (D165):** bots hunt the nearest car on their own platform, break off when the edge gets close (the better the driver, the later), and spend their ram when the target is close, lined up, and nearer the edge than they are.
- **Local players:** up to 4 in splitscreen, each with their own car.
- **Online (D166, D183):** the server shrinks the platforms and rules on who is in the goo. Only each platform's radius, the wedges it has marked and how deep each wedge has been bitten, plus each car's platform, out and ram charge, go over (protocol 10) — the arena itself needs no syncing, since the same settings build the same platforms everywhere. The mark travels because a client never shrinks a platform of its own and so has no clock to work it out from. A ring-out is sent at once so the splash lands on the tick it happened. Nobody joins a match in progress; they are in the next one.
- **Results:** the platform each car reached and how long it lasted, with the winner shown as "Won".

## 6. Drag Strip

*Mini Games. D168–D179.*

Two cars, two lanes, one straight line. It plays on a **generated strip**, not a track: the strip is built from the match's own settings, so there is nothing to pick, nothing to download and nothing of it on the wire. From the main menu: **Local Drive → Mini Games → Drag Strip**.

- **The strip (D168):** two 5 m lanes 8 m apart, with a painted centreline down the gap between them, a water box and the staging lanes behind the line, and past the finish a **shutdown as long again as the strip** (250–700 m) ending in **sand** for anyone who never got on the brakes. Lengths: **1/8 mile (201 m), 1/4 mile (402 m) or 1/2 mile (805 m)** — named in miles or in metres, whichever the player's units are set to.
- **A pass, in order:**
  - **Your turn (D177):** a card names you, the controls in your hands and what the pass wants of you. It waits for you — nothing stages until you have locked in — so a turn never arrives while you are still watching somebody else's run.
  - **Burnout** (optional): **eight seconds** in the water box. Throttle against the brake heats the tires and buys grip at the launch; the best of it is about two seconds, and cooking them past about four means you have thrown it away (D172).
  - **Staging:** both cars are set on the line and held. With the **two-step** on, hold the revs in the band on the tach — low bogs the launch, high roasts the tires.
  - **The tree (D169):** pre-stage, stage, three ambers half a second apart, green. Your **reaction time** is measured and shown to the thousandth, and **leaving before the green is a red light**: the pass is lost. With the tree off it is a plain countdown and nothing is timed.
  - **Down the strip:** shift on the needle (below), spend the bottle when it suits you, and hold your lane.
  - **The line:** the **elapsed time from the launch** (not from the green — the reaction is its own number, as a real strip has it) and the **trap speed**. Then room to stop.
- **The fake tachometer (D169):** the needle is **the mode's own, not the engine's**. It sweeps every gear at one fixed rate for every car, class and model, so nobody times their shifts better by what they brought. The real gearbox still shifts and still loses drive out of its band — **the needle only says when**. Each gear has a window that sits later and narrower than the last:
  - **Perfect** (inside half a window of its centre): a short surge of power.
  - **Good** (inside a whole window): nothing either way.
  - **Missed:** a grind, the throttle cut for a moment, and whatever the engine makes of being out of its band on top.
- **The chain:** perfect shifts in a row build the surge, up to four deep; one bad shift breaks it.
- **Money shift:** sitting past the end of the needle loses power, and far enough past it the engine lets go — smoke, and the pass is over. **Top gear costs nothing**: there is nothing left to shift into, so the needle simply rests at its end.
- **Tire shake:** a launch that lights the tires up opens a brief window to **feather it** — ease off (or stab the clutch, if there is one) and you save the run; miss it and it costs you a tenth or three. Once a pass, caught or not.
- **Boost:** **0 to 3 bottles** each (one by default), each a surge of about a second, spent whenever the driver likes. It is a force scaled by mass, so the change in speed is the same whatever the car weighs (as the sumo ram is, D164).
- **The lane (D171):** you steer the car. **Crossing the centreline loses the pass**, as it does on a real strip; a setting makes it forgiving instead, leaving the walls to bounce off. Leaving the deck altogether, stopping on the strip or taking a reset all lose the pass too.
- **Winning (D170):** an **elimination ladder**. The field is drawn into pairs, two cars run a pass, the winner goes through, and the last car standing takes the match. A field that is not a power of two gives **byes** in the first round; a bye does not run a pass. A one-car field runs a single **shakedown** pass. Pairs run **back to back**, so in splitscreen you watch the others' passes and are told when your turn is next. The pass goes to the clean run over the foul, the lower time over the higher, and with neither car through the lights to whoever got furthest; two red lights go to the **later** one, since the first to leave is the one who lost it.
- **Watching the others (D176):** waiting your turn, the camera goes on the pass that is running — above and behind the leading car, over the centreline, with both lanes in frame — and your camera button cycles that view and a chase on either car. Your own car stays out of play; it is the camera that moves.
- **Skipping a pass of bots (D178):** when there is no player in the pass, the **Boost** input hurries it along at four times the speed; press it again to watch at the normal pace. It is the real pass, run faster, so the times it sets are the same ones it would have set. Offline only — online the clock belongs to the server.
- **Restarting (D179):** **Restart event** in the pause menu asks first, then runs the same ladder again, with the field drawn into the same pairs in the same order.
- **No automatic gearbox.** `auto_gearbox` is not an allowed assist here — an automatic would play the game for you. Nor are the assists that drive the car but never shift it (auto throttle, brake assist, autodrive). **Auto clutch stays**, and is forced on for anyone without a clutch pedal, so a pad or a keyboard drives it fine. ABS, TCS, stability and steering assist are all allowed.
- **The prompts follow the device (D169):** a prompt never says "press the button" — it names the input the driver is actually holding, from what they last drove with and what they have bound. A keyboard reads "Release Space", a pad reads "A" or "RB", a wheel with a clutch reads "Release the clutch", and an H-shifter is told which **gate** to take ("3rd gate") instead of "shift up".
- **The classes:** three, and everyone in a match drives the same one — **Street** (6 gears, 265 kW), **Pro** (5 gears, 470 kW) and **Top Fuel** (4 gears, 620 kW), so the class and the length together decide how busy a pass is. **Any model may be mounted**, car, open-wheeler, truck or bike; an oversized one is scaled down as karts are (D150). Mass, power and gearing come from the class, never the model.
- **The setup screen:** more settings than fit a screen, so they scroll, and the scroll follows the focus — a controller or a keyboard scrolls it by moving down the rows. **Next** and **Back** sit outside the scroll, on screen whatever the settings are scrolled to.
- **HUD:** the tach with its window, the gear, the chain, the bottles left, the prompt, and the pass's numbers. No laps, sectors, places or flags. Short lines only: "Stage", "Go", "Perfect", "Missed it", "Red light", "Shake", "Won it".
- **AI (D174):** bots heat their tires, hold the revs on the line, leave on the green with a reaction of their own (a poor one now and then goes red), shift against the same needle the players read with an error their skill sets, spend their bottle and hold their lane. No pathfinding — it is a straight line.
- **Local players:** up to 4 in splitscreen, each with their own car; they are drawn into the ladder with the bots.
- **Results:** the round each car reached, its best reaction, its best time through the lights and the speed it did it at.

## 7. Light career

*MODE-07. Milestone M10.*

- **Everything is playable from the start.** Career is optional structure on top.
- **Event ladders per mode:**
  - Track: Touring Cup → GT Series → Prototype Endurance → Formula Championship.
  - Kart: 4-track cups per class.
  - Highway: score and run challenges.
  - Endless: distance and biome milestones.
- **Rewards are cosmetic only:** paint finishes, decals (once the livery editor exists), nameplates, HUD themes, horn sounds.
- Progress is saved locally. Online play is unranked.

## 8. Leaderboards

- **Local:** per track, platform and mode.
- **Per server:** kept by the host or dedicated server.
- **Recorded entries** store the platform id and hash, the track hash and the game version. Only `official.*` platforms count as "official" ([PLATFORMS.md §2](PLATFORMS.md#2-platform-file)).
- **Global leaderboards** need a central service, which is out of scope (NFR-11). A self-hostable option could come later.
