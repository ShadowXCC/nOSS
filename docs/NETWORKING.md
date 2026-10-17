# Networking

Online play is self-hosted. There are no accounts and no central servers. Requirements: MP-01…MP-08, LOC-05, PLT-09, AV-06, NFR-05, NFR-11. Built in M5 (decisions D78–D89); the code is in `game/net/`.

---

## 1. Topology

**Client-server, where the server is a player's own game.** This is what "P2P self-hosted" means for nOSS. One player hosts from the menu and everyone else connects to them.

| Server kind | How |
|---|---|
| **Listen server** (MP-01) | Online → Host. The host plays while serving. |
| **Dedicated server** (MP-02) | The same project exported as a Linux headless build (`noss_server`), run from a config file on any machine or VPS (§9) |

Both run identical server code (`NetServer` for connections, `NetHost` for the lobby, chat and rotation). A true mesh (no host) was ruled out because kart items, police and traffic need a single authority.

## 2. Transport

- **ENet** (UDP) through Godot's `ENetMultiplayerPeer`, polled by our own `SceneMultiplayer`. Default port **UDP 47800**, configurable (D83).
- **Protocol version 6** (M9: world positions in car states, knocks relative to the car, the sky and endless roads, D159; version 5, M8: the kart word in car states and kart items, D142; version 4: the start waits for every game's cars, D127; version 3, M7: 16-bit car ids, a second flags byte, highway traffic, D112; version 2 brought the track by hash, D98). A client and server must match it and the game version ("Version mismatch").
- **No RPCs** (D78). Every message is raw bytes (`send_bytes`): one type byte, then either a `var_to_bytes` Dictionary (control messages; never objects; size-checked before decoding, field-checked after) or a packed binary layout (car states, race state, content).
- **Channels:**

| Ch | Mode | Traffic |
|---|---|---|
| 0 | Reliable, ordered | Control: join, lobby, chat, sessions, results, notes, content requests |
| 1 | Unreliable, sequenced | Car states, race state, clock pings, contact relay |
| 2 | Unreliable, sequenced | Content chunks and their acks |
| 3 | Reliable, ordered | Highway traffic events and heartbeats (D109) |

- **ENet settings** (D79): unreliable packets are always sequenced (unsequenced ones from client to server were lost even on a perfect link). Every peer gets `throttle_configure(100, 32, 0)` as soon as ENet connects, so ENet's own throttle never drops car states. A connection gives up after about 3.5 s ("Server not found"), or 15 s once joined ("Connection lost").
- **Encryption:** DTLS is **deferred** (D82). The password never travels (§4).

## 3. Finding and joining games

- **Direct:** Online → Address (`host`, `host:port` or `[ipv6]:port`). Hosts get automatic **UPnP** port mapping (Godot `UPNP`, on a thread, leased for 2 hours and renewed hourly, removed when hosting stops). If it fails: "Port closed. Forward UDP 47800." The host's lobby shows the addresses to share, IPv6 included.
- **LAN discovery** (D83): each server answers on its game port + 1. Clients broadcast a query to ports 47801–47816 (to 255.255.255.255 and each /24 network) and also ask 127.0.0.1, so two servers or two games on one PC all show up. The list shows name, players, class, track and whether there's a password.
- **Later (MP-08):** an optional, self-hostable **nOSS Lobby** service for server lists, invite codes and NAT punch-through. It's never required.

## 4. Identity and moderation

- Each install has an **RSA-2048 key** in `user://identity/key.pem` (owner-only). The SHA-256 of the public key is the player's **fingerprint**: what bans, whitelists and admin lists hold. A display name sits on top. No accounts (D81).
- **Joining:** the server sends a nonce. The client answers with its public key, the nonce signed with it (so nobody can claim someone else's fingerprint) and, if the server has a password, an HMAC of the nonce keyed with the password's hash. Game and protocol versions must match. A refusal says why ("Wrong password", "Server full", "Banned", "Version mismatch (server 0.5.0)", "Already on this server").
- **Host tools:** kick, ban (by fingerprint, saved to the config), password, whitelist, admins (fingerprints in the config; a listen server's host is always admin), and the server rules (§8).
- **Chat:** text only, 200 characters, five lines per five seconds per connection, mute per player (on each player's own game). Controller players have quick lines. Admin commands: `/kick name`, `/ban name`, `/start`, `/next`, `/restart`, `/time dawn|morning|noon|afternoon|dusk|night|track`, `/weather clear|cloudy|rain|storm|fog|snow|changing|track`, `/help`. Chat shows in the lobby and as captions in sessions (read out with a player's race narration), and the pause menu has a Chat screen.
- **Two copies on one PC** (testing): `--instance=N` keeps each copy's settings, profiles and key apart.

## 5. Session flow

```
connect ─► join checks (versions, key, password, bans, room)
        ─► lobby: everyone's players, track (by hash), class, event, chat; each player picks a car
           (and on kart classes, their own class: D149)
        ─► a client without the track gets it first ("Getting track 40%"); then Ready
        ─► the server fetches each picked car from its owner (§7); clients fetch everyone's
        ─► start (host, admin /start, or the dedicated server once all are ready)
        ─► SESSION: track (hash, id, name, size; "endless" for an endless road), class (and its hash), event, rules,
           roster in grid order, the sky (environment: time, rate, weather, seed, t0) and an endless road's
           clock and where everyone is (endless: t0, at)
        ─► each game builds its session: its own players drive, every other car is remote
        ─► the start waits until every game has the session's cars ("Syncing 2/3"; 3–30 s, D127)
        ─► races: the server runs the event, clients follow (§6); results; next session
        ─► back to the lobby (host, last session over, or everyone gone)
```

- **Splitscreen online** (LOC-05): one connection carries up to 4 local players, each with their own id. All count toward the **16-player** cap (MP-03).
- **Joining mid-session:** free drive takes newcomers at once (first free grid spot); an endless road starts them just behind whoever's furthest along. A race weekend doesn't; they wait in the lobby for the next event ("Race on: you're in the next one").
- **Leaving mid-session:** in a race weekend the car stays in the results as out, until the next session.
- **Online the game never pauses** and runs at full speed (D85). A player's pause menu opens just for them.
- **Hotswap** (PKG-06): allowed by the server's rule (outside races by default); the new car hash reaches everyone and travels like any car.

## 6. Server-owned simulation

| Thing | Authority | Method |
|---|---|---|
| **Player cars** | Owning client | The client simulates its own car. The server checks it's plausible (§8). |
| AI cars | Server | The server's AI drives them; sent like player cars (D88), each with its paint job in the roster (D128) |
| Session state, timing, results | Server | `RaceControl` on the server; clients mirror its state (below) |
| Kart items | Server | (M8) The server spawns item entities. The victim's client reports a hit; the server validates it. |
| Police | Server | The server runs the police units (ids from 300), sent like player cars; clients know them by their first state. Heat, busts and evades go to each player's game (HW_EVENT, D115). |
| Traffic | Server (seed + events) | Every game runs the same lane sim from the session's seed by the server's clock; the server's events change it (below, D109). Cars near players are physics cars driven by their owner's game (D110). |
| Weather, time | Server (settings + clock) | Every game works the sky out from the event's settings, the server's seed for the weather's fronts and its clock (SESSION's `environment`), so nothing more is sent; an admin's `/time` or `/weather` sends ENV with a new start (D159) |
| Endless road | Seed | Every game makes the same road from the event's seed (integers only, D152); the server checks the chunks games made against its own (§12) |
| Endless traffic | Seed + clock; owners from the server | Every game works out the same schedule; a physics car near players is driven by one game, the others show it (§12, D159) |

### Car states

- **Rate:** each game sends its own cars 30 times a second (60 when its round trip is under 30 ms), and the traffic cars it drives 20 times a second. The server relays each car to each client by priority (D111): up to 60 a second within 150 m of that client's players, 30 within 400 m, 15 within 800 m, else 5; traffic past 600 m isn't sent (the client shows its lane-sim shadow); at most 56 KB/s, the most overdue (time since last sent × rate) and placed cars first, so in a crowd every car keeps its share.
- **Contents:** 48 bytes (`CarState`, D112, D142): a 16-bit id, server time (ms), position (millimetres; X and Z in the world, wrapped to 32 bits, D159), rotation (smallest three, 32 bits), linear and angular velocity (half floats), front steer, wheel lift, throttle, brake, gear, rpm, flags (brake lights, ghosted, waiting, placed, handbrake, knocked) and flags2 (horn, light flash, indicators, siren, light bar; a traffic car's wrecked and on-the-line), and the kart word (drift side and tier, boost, shield, spun, slowed, magnet, trick, towed, out of a battle, airborne; 0 for other cars). Ids: players 1–199, the server's AI 200–299, police 300–399, traffic 1000 + its lane-sim index (on an endless road, 1000 + its slot, §12). The pose is the car's ground reference, so a placeholder and the real car line up.
- **World positions** (D159): a game whose scene origin has moved (an endless road's floating origin, [ARCHITECTURE.md §8](ARCHITECTURE.md#8-floating-origin)) adds it going out and takes back the world point nearest it coming in, so every game keeps its own origin and 32 bits of millimetres reach ±2147 km from wherever it is. With no origin (every track) the bytes are what they were. The server passes states on as they came, so a car's position isn't rounded through the server's scene.
- **Remote cars are shown at the present time** (D84, `MotionBuffer`): extrapolated from their newest state to now (velocity, acceleration from the last two states, turn rate, at most 0.5 s ahead). A correction fades out over 0.15 s; a placed car (a reset, the grid) snaps. Locally they're **kinematic** bodies. Clients keep the server's clock with pings (the fastest recent round trip wins).
- **Car-to-car contact** (D86): a remote car is kinematic, as heavy as a wall, so after a knock the local car gets back the share an equal-mass collision wouldn't have given it. The knock also goes through the server (checked: owner, within 8 m of the car, at most 10 a second per pair, at most 3 m/s of speed) to the other car's game, which uses it only if it didn't feel that knock itself. Its point is sent from the knocked car's position (D159), so it lands on the car whatever each game's origin.
- **Ghosting:** the event can turn car-to-car contact off; online races are ghosted until the lights go out; with the server's `ghost_bad_links` rule (on by default), a car whose link is over 250 ms or 5% loss for 3 s races ghosted.

### Highway traffic (D109, D110)

- **The lane sim:** every game runs `NossTraffic` from SESSION's `highway` (seed, count, t0), stepped to tick (server time − t0) × 20. It's integers throughout, so every build gives the same result (Linux and Windows agree, `tools/traffic_determinism.sh`).
- **Events** (24 bytes each, raw message 110 on channel 3): promote, demote, wreck, tow, reshadow, close, open, and handover. Only the server makes them, `lead` ticks ahead (half the worst round trip plus 0.15 s, 0.25–0.6 s); every game applies them at that tick, rolling back and replaying (up to 64 ticks) if one comes late.
- **Heartbeat** (raw 105, once a second): a tick and the server's checksum of the lane sim then. Three disagreements running, joining, or an event too old to replay: the client asks (RESYNC) and gets TRAFFIC_FULL: the state (zstd), the events still to land, and who owns each physics car.
- **Physics cars:** a lane car near a player becomes a physics car on the nearest player's game (its owner), which sends its states; other games show a kinematic proxy, which follows its shadow until states come. The owner's flags (wrecked, on the line) let the server rule on it like its own. Handover after a second of another player being clearly nearer; an owner leaving hands over at once. Knocks with a traffic car go to its owner like any car's (D86).
- **Measured** (one PC, `net_check.py --event highway`): 0 checksum disagreements with 16 players and 150 cars, and at 150 ms RTT with 1% loss; a game put out of step on purpose resyncs once and stays in step.
- **Not yet:** a game whose lane graph differs from the server's (a different build of the track code) keeps its own traffic and warns; fetching the server's graph (TRAFFIC_GRAPH), clients reporting how many physics cars they can take (HW_CAP), and a touch promoting a lane car on the spot (TOUCH) are left for later.

### Race state (D85)

- The server's `RaceControl` decides everything; `NetRace` sends what clients need: the grid when a session begins (each game puts its own cars there), the race state 10 times a second (21 bytes a car, a 16-bit id then: held, flag, laps, best, last, penalty, warnings, finish, position; the phase, clock, the scheduled lights-out, and how many games have the session's cars), the results, and notes for one driver ("Track limits: warning").
- **The start waits for the files** (D127): an event's first session holds every car while each game reports `SYNCED {have, of}` (its own cars spawned, everyone else's as whole as it fetches them, refused ones counted as here), at least 3 s and at most 30 s. Then a race forms its grid and shows five lights; any other session shows three, one a second, and goes. Players joining later aren't held.
- **Fair timing:** the server times every car from where it shows it now; remote cars are extrapolated to the present, so a laggy player isn't timed late. **Lights-out** is a server time; each game releases its own cars when its clock reaches it.
- Clients mirror the state; a player's own lap timer still drives their HUD.

## 7. Content transfer

*Requirements: MP-05, PLT-09, AV-06. D80.*

- **Everything is addressed by content hash:** cars (with their engine sounds), tracks, platforms. A car's hash is its manifest's; each file is checked against the manifest's hash for it.
- **Cache:** `user://cache/content/` — `cars/<hex>/` and `tracks/<hex>/` (unpacked packages, filled file by file; a track is used once it's whole), `platforms/<hex>.json`, `hosted/` (a server's bare `track.json` made into a package so it can be sent), `tmp/` (files being written, and partial downloads to resume). Files are renamed into place, so several games can share one cache. Content is never downloaded twice.
- **Transfer** (`NetTransfer`): a file is asked for by hash; the sender compresses it with zstd and offers it (size, compressed size, chunk size); 4 KB chunks go as unreliable packets, acked with the next missing chunk plus each chunk just received; lost chunks (48 later sends acked, or a timeout) are sent again. The rate grows while the round trip stays near its best and holds or drains when a queue builds, so car states always get through (NFR-05). About one round trip of data is in flight. Limits per server: 2 MB/s per file, 8 MB/s per client (configurable). A broken transfer resumes from what's in `tmp/`.
  - Acks are unreliable too. A receiver acks a file it has finished again if its chunks still come (the sender missed the last ack), and a sender that hears nothing for 15 s stops; the receiver asks again if it still wants the file (D104). Before this, a lost last ack kept the sender resending for ever and held its rate at the floor.
  - Reliable ENet was measured and ruled out: its 64 KB window caps a transfer at about 0.4 MB/s at 150 ms.
- **Order and placeholders:**
  1. **Track and platforms** must arrive before the session starts. A track goes whole (manifest, then every file it lists, ahead of any car), checked file by file, into the cache, where the game finds it by hash. Ready waits for it; a session that starts meanwhile waits too. A server's own platform travels by hash.
  2. **Cars** stream in tiers, each tier for every car before the next: data (manifest, `fit.json`, `paint.json`, `sound/profile.json`), then each car's smallest LOD, then the rest, then own recordings if the server allows them.
  3. Until a car arrives it's the class's built-in car in the player's colour; with its data, a box its size on stock wheels (the right collision hull from the first second); then its smallest LOD; then the full model.
- **Server caps** (MP-06): max package size (the files' total; a car over it stays a placeholder, "Car too large for this server"), max track size (`caps.max_track_mb`, up to 100; a bigger track in the rotation gives way to the Proving Ground, "Track too large" in the log), own sound recordings on/off (tuned built-in sounds always play), custom platforms on/off. A client refuses a track over 100 MB ("Track too large").
- **Personal-use cars and tracks stay offline** (Requirements §6). A package marked `personal-use-only` (the FM4 converter's) isn't listed in the online car picker ("Personal-use cars stay offline"), is never an AI car and is never sent, even if asked for. A personal-use track isn't offered in the Host menu, and a server given one runs the Proving Ground instead ("Personal-use tracks stay offline"). Dev only: `--share-personal` lets a server send them to its own bots on the same PC (`tools/net_check.py --fresh`).
- **The host relays.** It fetches each player's car from its owner as soon as it's picked and sends it on, so clients never connect to each other.
- Measured (M6): a fresh bot got a 3 km editor track (terrain, 1500 trees; 0.1 MB) in about 0.15 s on one PC, then 4 garage cars whole in 14 s (`tools/track_check.sh`).
- Measured (acceptance 2, one PC): a fresh bot fetched 11 real cars (8 FM4 rips of 13–18 MB, sent to the bot with `--share-personal`, and 3 small CC0 cars) through a simulated 50 Mbit link: all as previews in 2.5 s and whole in 22.7 s at 20 ms; 3.3 s and 25.0 s at 150 ms.

## 8. Rules, cheating and fairness

- **Server rules** (MP-06): the event rotation (track: an id, a `.nosstrack`, a track folder or a `track.json`; class; event), allowed assists (narrowing the platform's and mode's), setups allowed or locked, normal or strict fitting, car swaps (outside races, never or always), collisions and track limits (per event), package size cap, own recordings, custom platforms.
- **Platform data comes from the server**, identified by hash. An official class must be the same file as the client's; a server's own platform is sent and used from the cache (never as `official.*`).
- **Plausibility checks** (D87, `Plausibility`) on every remote car's states:
  - speed above the platform's top speed (peak power against drag) plus 15% and 8 m/s
  - acceleration along the ground beyond 45 m/s², away from contacts and resets (landing off a crest or a kerb's knock is up and down, so it doesn't count, D104)
  - moving further between states than its speed allows (a teleport not marked as a reset)
  - a reset that jumps more than 40 m ahead along the track (not on an endless road, where Join takes a car anywhere)
  - states stamped more than 0.5 s ahead of the server's clock or 5 s behind
  - a lap faster than 97% of the racing line's ideal for the platform
  - karts (D142): the top speed is the class's geared top × the boost cap; no lap check (boosts beat the line); a towed kart is left alone; take-offs, landings, loops and knocks (an item's too) get the knock's grace, and a knocked kart may gain up to 6 m/s (bumps bounce)
- **Responses:** three strikes within 10 s trigger the server's choice: warn (a note to the driver), flag (the result shows "flagged"; flagged laps never reach leaderboards) or kick. Default: flag. Tested with cheating bots (`--cheat=speed|teleport|time`): each cheat is caught, honest cars never are.
- **Moderation and trust:** host moderation (§4), plus whitelisted servers for friends.

## 9. Dedicated server

- **Build:** `tools/export.sh server` → `export/server/noss_server.x86_64` (the "Linux Server" preset: dedicated server mode, runs headless on its own). From the project: `tools/godot.sh --headless -- --server --config=server.json`.
- **Run:** `noss_server --config server.json [--port N]`. Example config: `data/server.example.json` (schema `data/schemas/server.schema.json`): name, port, password, max players (≤16), MOTD, admins, whitelist, bans, LAN discovery, UPnP, car-state rate, event rotation, rules, caps, plausibility response.
- **Running:** it starts the event once everyone in the lobby is ready (after 5 s), runs the event's sessions with 15 s of results between them, goes on to the next event in the rotation, and goes back to the lobby when the last player leaves.
- **Console** (stdin, a terminal or a pipe): `players`, `kick <name>`, `ban <name>`, `say <text>`, `start`, `next`, `restart`, `time <…>`, `weather <…>`, `quit`. Logs go to stdout and `user://logs/server.log`.
- **No GPU needed:** physics only; cars load without models; no sound. On an endless road it builds no world: a short stretch at the start, its own floating origin round the convoy, and the road chunks it checks.

## 10. Targets and measurements

| Metric | Target | Measured (M5, one PC, `tools/net_check.py`) |
|---|---|---|
| Players | 16 per session, including splitscreen players | 16 (12 bots + one bot with 4 players) raced 3 laps on the dedicated server: all classified, no pile-ups |
| Latency | Playable at ≤150 ms RTT | At 150 ms with 10 ms jitter and 1% loss: remote cars within 2 cm (median), 12 cm (95%); 11 cars raced 2 laps, all classified, no contacts |
| Steady bandwidth | ≤64 KB/s per client | About 43 KB/s down, 3.4 KB/s up per player, with 16 cars |
| New player with an empty cache | Sees every real car within 60 s on a 50 Mbit link | 11 real cars whole in 22.7 s (20 ms), 25.0 s (150 ms) |
| Highway, 16 players and 150 traffic cars (M7) | In step, ≤64 KB/s | 0 checksum disagreements; 26–44 KB/s down; remote players within 0.03 m, traffic within 0.06 m (95%); lane sims at 19–20 ticks a second |
| Highway at 150 ms, 1% loss (M7) | In step | 4 bots, 150 cars: 0 disagreements, late events rolled back (up to 9 a minute), traffic within 0.1 m (95%) |
| Highway, 10 minutes with police (M7) | In step, ≤64 KB/s, the server on time | 16 players, 150 cars: 0 disagreements in about 600 checks each; 22–39 KB/s down (54 KB/s for 4 players on one connection); remote players within 0.06 m, traffic within 0.13 m (95%); no plausibility flags; the server's scripts about 340 ms a second (D125) |
| Loop online (M7) | Players each way meet every lap; the traffic comes round | 2 players each way at 1.6 × the limit: 2–3 meetings a lap, 91% of the traffic met one lap met again the next |
| Exported builds (M7) | Linux and Windows in step | The Linux dedicated server, an exported Linux bot and the Windows export under Wine: 0 disagreements |
| Endless convoy (M9) | The same road; remote cars where they are with each game's own origin | 3 bots, one joining 40 s late, 150 s (about 3.6 km and 2 origin moves each): 41–43 road chunks checked, none differed; remote cars within 0.01 m (95%), within 0.05 m at 150 ms RTT with 1% loss; the late bot started 40 m behind the leader; traffic shown from another game on every bot (13–22 handovers); 4–8 KB/s down |
| Endless, exported builds (M9) | Linux and Windows make the same road | The Linux dedicated server, an exported Linux bot and the Windows export under Wine: 25 chunks checked, none differed; remote cars within 0.02 m (95%) |

- **Tools:** `tools/net_sim.py` (a UDP proxy adding delay, jitter, loss and a bandwidth cap, no root needed) and `tools/net_check.py` (a dedicated server, headless bot clients, optionally `net_sim`; reports bandwidth, remote-car error, contacts and pile-ups, memory, race results, and a fresh client's download times). `tools/run_tests.sh` runs a one-lap race with 3 bots and an AI car at 150 ms, a highway with 3 bots and 60 traffic cars at 150 ms, one put out of step on purpose, a kart race and a battle with 3 bots and an AI kart at 150 ms, and an endless convoy of 3 bots (one joining 40 s late) at 150 ms. Endless options: `--event endless --seed N --late S`; the verdicts add no road chunk differing from the server's, remote cars within 1 m (95%), every bot driving and moving its origin, traffic shown from another game, and the late bot starting just behind the leader. `--exported` runs the exported server and bots taking turns between the Linux export and the Windows export under Wine. Kart options: `--event kart|battle --rule standing|hits --minutes N` (Gearworks or the Crate Yard and the Medium kart unless given); the verdicts add items within 0.5 m of the server's (Bolts and Slicks, 95%), under 5% of hit reports turned down and no item use turned down. Highway options: `--event highway --traffic N --dirs same|opposite --sub cruise|score|loop --police --speed-factor X --desync --open`. With `--dirs opposite` the server watches the first player each way round (the same `LoopWatch` as `highway_check --scenario=loop`): they must pass every lap, at least 60% of the traffic met one lap must come round the next, and the server must count the other player's laps too.

## 11. Kart items (D141, D142)

The server rules on items; each game shows its own at once.

- **Boxes:** a game takes boxes for the cars it drives and says so (`PICK`); the server checks the box is there and near, rolls (by place, D140) and tells everyone (`GOT`; the 1.2 s roulette hides the trip). Taken and back boxes go to everyone too (`BOX_TAKEN`, `BOX_BACK`).
- **Uses:** a game uses an item at once and tells the server where, which way, when and its use number (`USE`); a Bolt, Slick or Seeker it lets go flies at once under a temporary id. The server checks the car holds that item, 0.25 s since its last use, near where the server sees it and on time, then lets it go from that pose and time and sends `SPAWN` (the user's game takes the server's id; a refused use gets `REJECT` and goes). Self items (Nitro, Shield, Magnet) act at once on the user's game. EMPs are the server's to call: it sends who they reached, by its view (`HIT`, and `PULSE` for the ring).
- **Flying:** every game flies every item from where and when it was let go, caught up by its age.
- **Hits:** the game that drives a car finds the hits on it, applies them and reports (`HIT`); the server checks the item is there and near the car (3 m plus 0.1 s at its speed), removes it and tells everyone. A battle counts only these. A hit the server sees twice running that nobody reports within the round trip and 0.25 s is forced on the car's game (the backstop).
- **How things stand:** 5 times a second the server sends every box, every car's slot, lives and hits, and every item with its age (`KART_STATE`, unreliable). A game's item more than 2 m from where the server's is at the same age is put there (a Seeker's place on the road too); one it hasn't heard of appears (a joiner's); one the server no longer has goes.

| Message | Way | Contents |
|---|---|---|
| Raw 106 `KART_STATE` | server → clients, 5 Hz, unreliable | time u32 · boxes u16 + bitmask · cars u8 × {id u16, item u8, count u8, lives u8, hits u8, shield ds u8, flags u8} · items u8 × {id u16, kind u8, owner u16, target u16, pos i32 ×3 mm, vel f16 ×3, bounces u8, age u16 ms} |
| Raw 111 `KART_EVENTS` | server → clients, reliable (events channel) | 32-byte records: kind u8 · use number u16 · time u32 · item id u16 · car u16 · other u16 · item u8 · extra u8 · pos i32 ×3 · yaw i16 · pitch i16 · spare. Kinds: SPAWN, GONE, BOX_TAKEN, BOX_BACK, GOT, HIT, USE, PULSE, LIFE, OUT, REJECT |
| Raw 112 `KART_REPORT` | client → server, reliable | the same records: PICK, USE, HIT |

Measured (one PC, `tools/net_check.py --event kart|battle`, 2–4 bots with AI): Bolts and Slicks within 0.01–0.17 m of the server's (95%), at 150 ms with 1% loss too; Seekers within 1–4 m (they home on each game's own view of their target, and are corrected); hits validated, none turned down; 5–10 KB/s down per bot.

## 12. Endless roads (D159)

Every game makes the same road and the same traffic schedule from the event's seed and the server's clock, and builds the world round its own players with its own floating origin. Players spread out freely; **Join** in the pause menu puts a game's players 40 m behind another player, at their speed (the game moves its origin there and makes the road before they land).

- **Traffic owners:** a game with a player within 140 m of a scheduled car makes it a physics car at once and asks for it. The first game to ask drives it and sends its states (id 1000 + its slot, 20 a second); the others get the owner and show a kinematic proxy, which goes on along its slot until states come. When the owner lets it go (nobody of its own near), the next game still asking takes it over where it is, at its speed; a game that leaves hands its cars on the same way. The owner's flags2 say whether the car is wrecked or has left its slot.
- **Slots used up:** a car knocked out of its slot (or left behind) is never drawn from the schedule again on any game: the owner reports it, the server tells everyone.
- **Where everyone is:** once a second each game reports its players' road distances and speeds; the server sends everyone the lot (for Join, and in SESSION for joiners, who start just behind whoever's furthest along).
- **The road checked:** each game reports the checksum of every chunk it made; the server makes the same chunk and compares (none may differ, M9's "a seed reproduces the same road").
- **The server** builds no world (§9) and doesn't place cars on the road: it relays states, rules on owners and checks chunks.

| Message | Way | Contents |
|---|---|---|
| `ENDLESS` (53) | client → server, reliable, at once for changes and once a second | `want`, `drop`, `gone`: slots (2 × car index + lane) · `at`: {car id: [distance m, speed m/s]} for its own players only · `sums`: {chunk: checksum} |
| `ENDLESS_STATE` (54) | server → clients, reliable | `owners`: {slot: car id of a player in the driving game, or −1} · `gone`: slots · `at`: {car id: [distance, server time, speed]} · `full` (the whole state, to a game when it first reports) |
| `ENV` (55) | server → clients, reliable | time, time rate, weather, seed, t0: the sky from now on |

Measured: see §10 (Endless convoy).

**Replays and ghosts** can reuse the same car-state format (AV-08).
