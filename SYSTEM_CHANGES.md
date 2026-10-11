# System changes

Changes made outside this project directory, to be reversed later if wanted.

| Change | Created by | Reverse with |
|---|---|---|
| `~/.local/share/nOSS/` (logs, shader and Vulkan caches, ObjectDB snapshots, `settings.cfg`, `profiles/`) | Running the game or its tests. This is the game's normal `user://` folder (NFR-09). | `rm -rf ~/.local/share/nOSS` |
| `~/.local/share/nOSS/garage/*.noss`: the 8 converted FM4 cars (~125 MB, personal-use-only) | `tools/fm4_to_noss.py` (its default output) | `rm -rf ~/.local/share/nOSS/garage` |

| `~/.local/share/nOSS/fitting/` (Fitting Bay drafts), `cache/` (garage index, rendered thumbnails), `import/` (folder the bay lists) | Running the game (M2). Part of the game's `user://` folder. | Covered by `rm -rf ~/.local/share/nOSS`; or delete each folder |
| `~/.local/share/nOSS/garage/race.noss`, `sedan_sports.noss`, `toy_car.noss` | Fitting Bay tests during M2 (CC0 Kenney and Khronos models) | `rm ~/.local/share/nOSS/garage/{race,sedan_sports,toy_car}.noss` |
| `~/.local/share/nOSS/players.json` (which profile each controller belongs to), `profiles/player2.json` (made when a second controller joined in an M3 test run); `profiles/player1.json` rewritten in the v2 profile format | Running the game (M3). Part of the game's `user://` folder. | Covered by `rm -rf ~/.local/share/nOSS`; or `rm ~/.local/share/nOSS/players.json ~/.local/share/nOSS/profiles/player2.json` |
| `~/.local/share/nOSS/tests/` (test settings, profiles and packages) | gdUnit4 tests (M2, M3, M4) | `rm -rf ~/.local/share/nOSS/tests` |
| `~/.local/share/nOSS/ghosts/`, `leaderboards/` (time-trial ghosts and laps), `setups/` (car setups); `settings.cfg` gained the last race set up, sound volumes and the first-boot flag; `profiles/player1.json` rewritten as profile version 3 on its next load (assists Auto/On/Off) | Running the game and its checks (M4). Part of the game's `user://` folder. | Covered by `rm -rf ~/.local/share/nOSS`; or delete each folder |
| `~/.local/share/nOSS/identity/key.pem` (this install's online key pair, owner-only), `logs/server.log` (dedicated server log), `instances/<n>/` (settings, profiles and keys of `--instance=<n>` runs) | Running the game, its tests and the dedicated server (M5). Part of the game's `user://` folder. | Covered by `rm -rf ~/.local/share/nOSS`; or delete each. Deleting `identity/` gives the install a new fingerprint (bans and admin lists stop matching). |

Not system changes:
- git `user.name` and `user.email` are set in this repo's `.git/config`, not globally.
- Godot runs in self-contained mode, so it does not create `~/.config/godot`, `~/.local/share/godot` or `~/.cache/godot`.
- pip ran with `--no-cache-dir`, so there is no `~/.cache/pip` entry from this project.
- The Windows build was tested under Wine with a throwaway prefix in a temporary folder (not `~/.wine`), with menu-entry creation turned off (M1, M2 and M3).
- M3's multi-monitor runs opened fullscreen windows on both monitors only while the game ran; no display settings were changed.
- M4's screen-reader checks (`tools/a11y_check.py`) run the game in a private D-Bus session with the accessibility bus switched on in memory; the desktop's accessibility settings were not changed. They pass `--no-save`, so no settings or profiles are written.
