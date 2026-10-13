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
- **Protocol version 2** (M6: the track travels by hash, D98). A client and server must match it and the game version ("Version mismatch").
- **No RPCs** (D78). Every message is raw bytes (`send_bytes`): one type byte, then either a `var_to_bytes` Dictionary (control messages; never objects; size-checked before decoding, field-checked after) or a packed binary layout (car states, race state, content).
- **Channels:**

| Ch | Mode | Traffic |
|---|---|---|
| 0 | Reliable, ordered | Control: join, lobby, chat, sessions, results, notes, content requests |
| 1 | Unreliable, sequenced | Car states, race state, clock pings, contact relay |
| 2 | Unreliable, sequenced | Content chunks and their acks |

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
- **Chat:** text only, 200 characters, five lines per five seconds per connection, mute per player (on each player's own game). Controller players have quick lines. Admin commands: `/kick name`, `/ban name`, `/start`, `/next`, `/restart`, `/help`. Chat shows in the lobby and as captions in sessions (read out with a player's race narration), and the pause menu has a Chat screen.
- **Two copies on one PC** (testing): `--instance=N` keeps each copy's settings, profiles and key apart.

## 5. Session flow

```
connect ─► join checks (versions, key, password, bans, room)
        ─► lobby: everyone's players, track (by hash), class, event, chat; each player picks a car
        ─► a client without the track gets it first ("Getting track 40%"); then Ready
        ─► the server fetches each picked car from its owner (§7); clients fetch everyone's
        ─► start (host, admin /start, or the dedicated server once all are ready)
        ─► SESSION: track (hash, id, name, size), class (and its hash), event, rules, roster in grid order
        ─► each game builds its session: its own players drive, every other car is remote
        ─► races: the server runs the event, clients follow (§6); results; next session
        ─► back to the lobby (host, last session over, or everyone gone)
```

- **Splitscreen online** (LOC-05): one connection carries up to 4 local players, each with their own id. All count toward the **16-player** cap (MP-03).
- **Joining mid-session:** free drive takes newcomers at once (first free grid spot). A race weekend doesn't; they wait in the lobby for the next event ("Race on: you're in the next one").
- **Leaving mid-session:** in a race weekend the car stays in the results as out, until the next session.
- **Online the game never pauses** and runs at full speed (D85). A player's pause menu opens just for them.
- **Hotswap** (PKG-06): allowed by the server's rule (outside races by default); the new car hash reaches everyone and travels like any car.

## 6. Server-owned simulation

| Thing | Authority | Method |
|---|---|---|
| **Player cars** | Owning client | The client simulates its own car. The server checks it's plausible (§8). |
| AI cars | Server | The server's AI drives them; sent like player cars (D88) |
| Session state, timing, results | Server | `RaceControl` on the server; clients mirror its state (below) |
| Kart items | Server | (M8) The server spawns item entities. The victim's client reports a hit; the server validates it. |
| Police | Server | (M7) The server runs police AI cars, sent like player cars |
| Traffic | Server (seed + events) | (M7) A seed plus spawn/despawn events; every client advances traffic deterministically |
| Weather, time | Server | (M9) Broadcast every few seconds |

### Car states

- **Rate:** each game sends its own cars 30 times a second (60 when its round trip is under 30 ms); the server sends every client every other car's freshest state 60 times a second.
- **Contents:** 44 bytes (`CarState`): id, server time (ms), position (millimetres), rotation (smallest three, 32 bits), linear and angular velocity (half floats), front steer, wheel lift, throttle, brake, gear, rpm and flags (brake lights, ghosted, waiting, placed). The pose is the car's ground reference, so a placeholder and the real car line up. Measured: about 40 KB/s down per client with 16 cars.
- **Remote cars are shown at the present time** (D84, `MotionBuffer`): extrapolated from their newest state to now (velocity, acceleration from the last two states, turn rate, at most 0.5 s ahead). A correction fades out over 0.15 s; a placed car (a reset, the grid) snaps. Locally they're **kinematic** bodies. Clients keep the server's clock with pings (the fastest recent round trip wins).
- **Car-to-car contact** (D86): a remote car is kinematic, as heavy as a wall, so after a knock the local car gets back the share an equal-mass collision wouldn't have given it. The knock also goes through the server (checked: owner, distance, at most 10 a second per pair, at most 3 m/s of speed) to the other car's game, which uses it only if it didn't feel that knock itself.
- **Ghosting:** the event can turn car-to-car contact off; online races are ghosted until the lights go out; with the server's `ghost_bad_links` rule (on by default), a car whose link is over 250 ms or 5% loss for 3 s races ghosted.

### Race state (D85)

- The server's `RaceControl` decides everything; `NetRace` sends what clients need: the grid when a session begins (each game puts its own cars there), the race state 10 times a second (20 bytes a car: held, flag, laps, best, last, penalty, warnings, finish, position; the phase, clock and the scheduled lights-out), the results, and notes for one driver ("Track limits: warning").
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
  - a reset that jumps more than 40 m ahead along the track
  - states stamped more than 0.5 s ahead of the server's clock or 5 s behind
  - a lap faster than 97% of the racing line's ideal for the platform
- **Responses:** three strikes within 10 s trigger the server's choice: warn (a note to the driver), flag (the result shows "flagged"; flagged laps never reach leaderboards) or kick. Default: flag. Tested with cheating bots (`--cheat=speed|teleport|time`): each cheat is caught, honest cars never are.
- **Moderation and trust:** host moderation (§4), plus whitelisted servers for friends.

## 9. Dedicated server

- **Build:** `tools/export.sh server` → `export/server/noss_server.x86_64` (the "Linux Server" preset: dedicated server mode, runs headless on its own). From the project: `tools/godot.sh --headless -- --server --config=server.json`.
- **Run:** `noss_server --config server.json [--port N]`. Example config: `data/server.example.json` (schema `data/schemas/server.schema.json`): name, port, password, max players (≤16), MOTD, admins, whitelist, bans, LAN discovery, UPnP, car-state rate, event rotation, rules, caps, plausibility response.
- **Running:** it starts the event once everyone in the lobby is ready (after 5 s), runs the event's sessions with 15 s of results between them, goes on to the next event in the rotation, and goes back to the lobby when the last player leaves.
- **Console** (stdin, a terminal or a pipe): `players`, `kick <name>`, `ban <name>`, `say <text>`, `start`, `next`, `restart`, `quit`. Logs go to stdout and `user://logs/server.log`.
- **No GPU needed:** physics only; cars load without models; no sound.

## 10. Targets and measurements

| Metric | Target | Measured (M5, one PC, `tools/net_check.py`) |
|---|---|---|
| Players | 16 per session, including splitscreen players | 16 (12 bots + one bot with 4 players) raced 3 laps on the dedicated server: all classified, no pile-ups |
| Latency | Playable at ≤150 ms RTT | At 150 ms with 10 ms jitter and 1% loss: remote cars within 2 cm (median), 12 cm (95%); 11 cars raced 2 laps, all classified, no contacts |
| Steady bandwidth | ≤64 KB/s per client | About 43 KB/s down, 3.4 KB/s up per player, with 16 cars |
| New player with an empty cache | Sees every real car within 60 s on a 50 Mbit link | 11 real cars whole in 22.7 s (20 ms), 25.0 s (150 ms) |

- **Tools:** `tools/net_sim.py` (a UDP proxy adding delay, jitter, loss and a bandwidth cap, no root needed) and `tools/net_check.py` (a dedicated server, headless bot clients, optionally `net_sim`; reports bandwidth, remote-car error, contacts and pile-ups, memory, race results, and a fresh client's download times). `tools/run_tests.sh` runs a one-lap race with 3 bots and an AI car at 150 ms.

**Replays and ghosts** can reuse the same car-state format (AV-08).
