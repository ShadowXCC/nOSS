# Networking

Online play is self-hosted. There are no accounts and no central servers. Requirements: MP-01…MP-08, LOC-05, PLT-09, AV-06, NFR-05, NFR-11.

---

## 1. Topology

**Client-server, where the server is a player's own game.** This is what "P2P self-hosted" means for nOSS. One player hosts from the menu and everyone else connects to them.

| Server kind | How |
|---|---|
| **Listen server** (MP-01) | "Host" in the menu. The host plays while serving. |
| **Dedicated server** (MP-02) | The same project exported as a Linux headless build (`noss_server`), run from a config file on any machine or VPS |

Both run identical server code. A true mesh (no host) was ruled out because kart items, police and traffic need a single authority.

## 2. Transport

- **ENet** (UDP) through Godot's `ENetMultiplayerPeer`. Default port **UDP 47800**, configurable.
- **Channels:**

| Ch | Mode | Traffic |
|---|---|---|
| 0 | Reliable, ordered | Control RPCs: session state, chat, events, results |
| 1 | Unreliable, sequenced | Vehicle states |
| 2 | Reliable, ordered | Content transfer chunks |

- Godot high-level RPCs for control. **Custom packed binary** for vehicle states, for tight bandwidth.
- **Optional DTLS encryption** (ENet DTLS). Server passwords are checked by challenge and response, never sent in clear.

## 3. Finding and joining games

- **Direct:** IP:port. Hosts get automatic **UPnP** port mapping (Godot `UPNP`), with a clear message if it fails ("Port closed. Forward UDP 47800.").
- **LAN discovery:** UDP broadcast lists local servers.
- **Later (MP-08):** an optional, self-hostable **nOSS Lobby** service for server lists, invite codes and NAT punch-through. It's never required.

## 4. Identity and moderation

- Each install creates a local key pair (Godot `Crypto`). The public-key fingerprint is the player's identity for bans and whitelists, with a display name on top. No accounts.
- **Host tools:** kick, ban (by fingerprint), password, whitelist, and server rules (MP-06).
- **Chat:** text only. Mute per player.

## 5. Session flow

```
connect ─► handshake (game version, protocol version, password)
        ─► server sends content manifest: mode rules, track hash, platform hashes, caps
        ─► client replies with the hashes it lacks ─► download (§7)
        ─► client sends its car package hash + chosen class (per local player)
        ─► server fetches missing car packages from that client, relays them to others
        ─► spawn (placeholder body until the car arrives) ─► play
```

- **Splitscreen online** (LOC-05): one connection carries up to 4 local players. Each gets their own player id. All count toward the **16-player** cap (MP-03).
- **Hotswap mid-session** (PKG-06): sends the new car hash; the transfer runs as above.

## 6. Server-owned simulation

| Thing | Authority | Method |
|---|---|---|
| **Player cars** | Owning client | The client simulates its own car. The server checks it's plausible (§8). |
| Session state, timing, results | Server | Checkpoint crossings are validated against the received position stream |
| Kart items | Server | The server spawns item entities. The victim's client reports a hit; the server validates it and applies the effect. |
| Police | Server | The server runs police AI cars, replicated like player cars |
| Traffic | Server (seed + events) | The server sends a seed plus spawn/despawn events (lane, spline position, speed). Every client advances traffic deterministically along lanes. |
| Traffic after contact | Hitting client | The traffic car turns into a physics body owned by the hitter until it settles. The server arbitrates who owns it. |
| Weather, time | Server | Broadcast every few seconds |

### Vehicle state replication

- **Rate:** 30 Hz (60 Hz on LAN).
- **Contents:** timestamp, position (sector + float offset, see [ARCHITECTURE.md §8](ARCHITECTURE.md#8-floating-origin)), rotation (smallest-three quaternion), linear and angular velocity, per-wheel spin and steer, inputs, gear, RPM, lights, damage levels.
- **Size:** ~80 bytes per car. 16 cars at 30 Hz ≈ **40 KB/s down** per client.
- **Remote cars:** snapshot interpolation with an adaptive ~100 ms buffer. Up to 250 ms of extrapolation on packet loss. Locally they're **kinematic** bodies.
- **Car-to-car contact:** each client resolves contact against kinematic remotes for its own car. It also sends a bounded **contact impulse** (relayed by the server, rate-limited) so the other car's owner applies the reaction.
- **Ghosting:** servers can turn car-to-car collisions off.

## 7. Content transfer

*Requirements: MP-05, PLT-09, AV-06.*

- **Everything is addressed by content hash:** cars (with their engine sounds), tracks, platforms.
- **Cache:** content is stored in `user://cache/<sha256>/` after verification, and is never downloaded twice.
- **Chunks:** 64 KB on channel 2. Resumable by chunk index. The whole file is verified by SHA-256 when complete.
- **Rate limit:** ≤ 2 MB/s per transfer by default (server-configurable), so state traffic is never starved (NFR-05).
- **Order and placeholders:**
  1. **Track and platforms** must arrive before spawning, because they're required.
  2. **Cars** stream after spawning. First the manifest, `fit.json`, `paint.json`, `sound/profile.json` and the smallest LOD, so a low-detail version appears quickly. Then the rest.
  3. Until a car arrives, a **placeholder body** shows: a simple box car in the player's color.
- **Server caps** (MP-06): max package size, own sound recordings on/off (tuned built-in sounds always play), custom platforms on/off. A player whose car exceeds a cap uses the placeholder, with the message "Car too large for this server".
- **The host relays.** It uploads player cars to the others, so clients never connect to each other directly.

## 8. Cheating and fairness

nOSS is open source, so a determined cheater can modify their client. The goal is to make cheating hard and visible, not impossible.

- **Platform data comes from the server**, identified by hash. Clients simulate with the server's platform.
- **Plausibility checks** on every client's stream:
  - speed against the platform's top speed (plus margin for slipstream and boosts)
  - acceleration against platform limits
  - teleports
  - checkpoint order, and lap time against distance
- **Responses:** warn, kick or flag, configurable per server. Flagged laps never reach leaderboards.
- **Moderation and trust:** host moderation (§4), plus whitelisted servers for friends.

## 9. Dedicated server

- **Build:** Linux headless export, `noss_server --config server.json`.
- **Config:** name, port, password, max players (≤16), admin password, mode rotation, tracks (local `.nosstrack` files), allowed classes, tuning and assist rules, caps, collisions, police, traffic density, weather and time.
- **Operations:** console and admin chat commands (kick, ban, next event, change weather). Logs go to stdout and `logs/`.
- **No GPU needed:** physics only, no rendering.

## 10. Targets

| Metric | Target |
|---|---|
| Players | 16 per session, including splitscreen players |
| Latency | Playable at ≤150 ms RTT |
| Steady bandwidth | ≤64 KB/s per client |
| New player with an empty cache | Sees every real car within 60 s on a 50 Mbit link |

**Replays and ghosts** reuse the same vehicle-state format (AV-08).
