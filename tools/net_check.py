#!/usr/bin/env python3
"""Online load check (ROADMAP M5 acceptance): a dedicated server and headless bot clients.

Starts the dedicated server from the project, optionally a link simulator in front of it
(tools/net_sim.py: delay, jitter, loss, bandwidth), and bot clients (`--bot`), each with one or
four players on one connection. When the bots are done it reports, per bot and in total:
  - car-state traffic down and up per client (KB/s, steady part)  target: <= 64 KB/s down
  - how far off remote cars were shown (the true position against what was shown then)
  - contacts and pile-ups (3+ cars linked by contacts within 3 s and 30 m)
  - memory (RSS) of the server and of each bot
and exits 0 (PASS) or 1 (FAIL).

  tools/net_check.py --clients 12 --quad 1 --duration 60           # 16 players, free drive
  tools/net_check.py --clients 3 --rtt 150 --jitter 10 --loss 1     # through a bad link
  tools/net_check.py --fresh --ai 15 --rate 50mbit --rtt 20         # a fresh client fetches every car
  tools/net_check.py --track my.nosstrack --fresh --ai 3 --laps 1   # ...and the server's own track
  tools/net_check.py --event highway --clients 12 --quad 1 --traffic 150   # M7: highway traffic
  tools/net_check.py --event highway --clients 2 --dirs opposite --speed-factor 1.6 --duration 600   # M7 acceptance 3
  tools/net_check.py --event kart --clients 4 --ai 4 --track gearworks --laps 3 --rtt 150 --jitter 10 --loss 1   # M8
  tools/net_check.py --event battle --clients 4 --ai 4 --track crate_yard --rule hits   # M8
  tools/net_check.py --event endless --clients 3 --late 40 --duration 150   # M9: an endless convoy
  tools/net_check.py --event sumo --clients 3 --ai 4 --tiers 2 --rtt 150   # a sumo match
  tools/net_check.py --event drag --clients 3 --ai 4 --length 402 --rtt 150 # a drag ladder
  tools/net_check.py --event endless --clients 2 --exported --duration 120  # exported builds (tools/export.sh)

On a highway (--event highway, the Lumen Ring and the Street class unless given) every bot also
reports its traffic: checksums that disagreed with the server's (must be 0), full states taken
(1 on joining), late events rolled back, handovers, and the most physics cars it drove; the
server reports promotions and handovers (NETCHECK_SERVER). With --dirs opposite the server also
watches the first player each way round (NETCHECK_LOOP): they must pass every lap, and at least 60%
of the traffic the first meets on the other carriageway one lap must come round the next.

A kart race (--event kart: Gearworks and the Medium kart unless given) or battle (--event battle:
the Crate Yard; the bots drive Light, Medium and Heavy in turn unless --classes same) also checks the items (D141): every bot's Bolts and Slicks within 0.5 m of the server's (p95; Seekers home on each game's own
view, so theirs is shown, not checked),
under 5% of reported hits turned down, a classified race or a battle with a winner. With
KART_DEBUG=1 the bots log every item more than 1 m off (KARTDBG lines in their logs).

An endless road (--event endless: the Cruiser class, normal traffic) checks that every game makes
the same road (the bots' chunk checksums against the server's: none may differ), that remote cars
are shown where they are although each game's origin moves on its own (p95 under 1 m), that every
bot drove and moved its origin, and that the traffic was shared (a car one game drives shown on
another). With --late the last bot joins that many seconds after the rest: it must start just
behind the leader. Bots that start together must each start in their own spot.

With --exported the exported builds run instead of the project (tools/export.sh linux windows
server first): the dedicated server, then bots taking turns between the Linux export and the Windows
export under Wine (in a throwaway prefix), so the two builds play together.

With --fresh, the server's AI cars are this machine's garage cars (every one before any twice), and
one bot with an empty cache fetches them all whole; it reports when every car was there as a
preview and whole (target: whole within 60 s). A --track that isn't built in must reach it too
(the bot prints how long it took).
"""

import argparse
import json
import os
import re
import signal
import subprocess
import sys
import threading
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import net_sim  # noqa: E402

GODOT = str(ROOT / "tools" / "godot.sh")
PILEUP_S = 3.0
PILEUP_M = 30.0
PILEUP_CARS = 3
KART_PILEUP_CARS = 4
MAX_DOWN_KB = 64.0
MAX_TRAFFIC_ERR_M = 1.0
MAX_ENDLESS_ERR_M = 1.0
MAX_ITEM_ERR_M = 0.5
MAX_REJECTED = 0.05
KART_CLASSES = ["official.kart.light", "official.kart.medium", "official.kart.heavy"]  # --classes mixed: bot i drives the i-th
HIGHWAY_MISSES = 3  # HighwayNet.MISSES: checksums that disagree before a game asks again
LOOP_AGAIN_MIN = 0.6  # acceptance 3: the share of the traffic met one lap that comes round the next


def lan_ip():
    """This PC's address on the LAN (no packet is sent)."""
    import socket
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            sock.connect(("192.0.2.1", 9))
            return sock.getsockname()[0]
    except OSError:
        return "this PC's address"


def rss_mb(pid):
    try:
        for line in Path(f"/proc/{pid}/status").read_text().splitlines():
            if line.startswith("VmRSS:"):
                return int(line.split()[1]) / 1024.0
    except OSError:
        pass
    return 0.0


def pileups(contacts, least=PILEUP_CARS):
    """Groups of `least`+ cars linked by contacts within PILEUP_S and PILEUP_M."""
    out = []
    used = set()
    for i, c in enumerate(contacts):
        if i in used:
            continue
        cars = {c["a"], c["b"]}
        group = {i}
        grew = True
        while grew:
            grew = False
            for j, d in enumerate(contacts):
                if j in group:
                    continue
                near = abs(d["t"] - c["t"]) <= PILEUP_S and dist(d["pos"], c["pos"]) <= PILEUP_M
                if near and (d["a"] in cars or d["b"] in cars):
                    cars |= {d["a"], d["b"]}
                    group.add(j)
                    grew = True
        used |= group
        if len(cars) >= least:
            out.append("%d cars at %.1f s (%s)" % (len(cars), c["t"], ", ".join(str(x) for x in sorted(cars))))
    return out


def dist(a, b):
    return sum((x - y) ** 2 for x, y in zip(a, b)) ** 0.5


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--clients", type=int, default=3, help="bots with one player each")
    p.add_argument("--quad", type=int, default=0, help="bots with four players each (splitscreen guests)")
    p.add_argument("--duration", type=float, default=60.0, help="seconds of driving (free drive)")
    p.add_argument("--event", choices=["free", "race", "highway", "kart", "battle", "endless", "sumo", "drag"], default="free")
    p.add_argument("--rule", choices=["standing", "hits"], default="standing", help="battle: last one standing or most hits")
    p.add_argument("--tiers", type=int, default=2, help="sumo: how many platforms are stacked (1-3)")
    p.add_argument("--length", type=int, default=402, help="drag: the strip in metres (201, 402 or 805)")
    p.add_argument("--boost", type=int, default=1, help="drag: bottles each driver gets (0-3)")
    p.add_argument("--drag-class", choices=["street", "pro", "top_fuel"], default="street", help="drag: the class the field drives")
    p.add_argument("--hazard", choices=["lava", "acid"], default="lava", help="sumo: what is under the platforms")
    p.add_argument("--shrink", choices=["smooth", "crumble", "stepped"], default="smooth", help="sumo: how a platform shrinks")
    p.add_argument("--platform-secs", type=int, default=60, help="sumo: how long one platform takes to go")
    p.add_argument("--minutes", type=int, default=5, help="battle: its length at most")
    p.add_argument("--traffic", type=int, default=150, help="highway: traffic cars")
    p.add_argument("--dirs", choices=["same", "opposite"], default="same", help="highway: players start one way, or turn about")
    p.add_argument("--sub", choices=["cruise", "score", "loop"], default="cruise", help="highway: the sub-mode")
    p.add_argument("--police", action="store_true", help="highway: police on (the bots speed, so they get chased)")
    p.add_argument("--speed-factor", type=float, default=0.0, help="highway: the bots drive at this times the limit (default 1.4 with --police, else 1)")
    p.add_argument("--open", action="store_true",
                   help="a place kept for a player from outside (another PC joining with --perf-log); the server goes on the "
                        "LAN list, on the standard port 47800 unless --port is given")
    p.add_argument("--desync", action="store_true", help="highway: the first bot's traffic goes out of step once (it must resync)")
    p.add_argument("--laps", type=int, default=3)
    p.add_argument("--seed", type=int, default=7, help="endless: the road's seed")
    p.add_argument("--late", type=float, default=0.0, help="endless: the last bot joins this many seconds after the others")
    p.add_argument("--ai", type=int, default=0, help="AI cars the server adds (races)")
    p.add_argument("--class", dest="klass", default="")
    p.add_argument("--classes", choices=["mixed", "same"], default="mixed",
                   help="kart: the bots drive Light, Medium and Heavy in turn, or all the server's class")
    p.add_argument("--track", default="",
                   help="the server's track: an id, or a .nosstrack / track folder (sent to bots that lack it)")
    p.add_argument("--port", type=int, default=0, help="the server's port (default 47850; 47800 with --open)")
    p.add_argument("--rtt", type=float, default=0.0, help="simulated round trip, ms")
    p.add_argument("--jitter", type=float, default=0.0)
    p.add_argument("--loss", type=float, default=0.0, help="percent, each way")
    p.add_argument("--rate", default="0", help="bandwidth per client each way, e.g. 50mbit")
    p.add_argument("--bot-fps", type=int, default=60)
    p.add_argument("--cheat", default="", help="the first bot cheats (speed, teleport, time): it must be caught")
    p.add_argument("--plausibility", default="flag", choices=["off", "warn", "flag", "kick"])
    p.add_argument("--fresh", action="store_true", help="one bot with an empty cache fetches every car")
    p.add_argument("--within", type=float, default=60.0, help="--fresh: seconds allowed for every car")
    p.add_argument("--logs", default="", help="the logs' folder (default reports/net_check/<time>/)")
    p.add_argument("--exported", action="store_true", help="run the exported server, Linux and Windows (Wine) builds")
    p.add_argument("--verbose", action="store_true")
    args = p.parse_args(argv)
    # The game's LAN list only asks the standard ports (47800-47815), so an open server uses one.
    args.port = args.port or (47800 if args.open else 47850)
    highway = args.event == "highway"
    karts = args.event in ["kart", "battle"]
    endless = args.event == "endless"
    sumo = args.event == "sumo"
    drag = args.event == "drag"
    args.klass = args.klass or ("official.highway.street" if highway else "official.kart.medium" if karts
                                else "official.endless.cruiser" if endless else "official.sumo.standard" if sumo
                                else ("official.drag." + args.drag_class) if drag else "official.track.gt")
    args.track = args.track or ("lumen_ring" if highway else "gearworks" if args.event == "kart" else "crate_yard" if args.event == "battle"
                                else "endless" if endless else "proving_ground")

    logs = Path(args.logs) if args.logs else ROOT / "reports" / "net_check" / time.strftime("%Y%m%d_%H%M%S")
    logs.mkdir(parents=True, exist_ok=True)
    if args.fresh:
        args.clients, args.quad, args.event = 1, 0, "race"
    players = args.clients + 4 * args.quad
    if args.open and players >= 16:
        sys.exit("--open: at most 15 bot players, so one place is left")
    track = args.track
    if Path(track).exists():  # a path here, not an id: the config lives in the logs' folder
        track = str(Path(track).resolve())
    builtin_track = (ROOT / "content" / "tracks" / args.track).is_dir() or endless or sumo or drag
    event = {"kind": "race" if args.event == "kart" else args.event}
    if highway:
        event.update({"sub": args.sub, "traffic": args.traffic, "direction": 0 if args.dirs == "opposite" else 1, "police": args.police})
    if endless:
        event.update({"road_seed": args.seed, "biome": 1, "endless_traffic": "normal", "oncoming": True})
    if sumo:
        # The arena is generated from these, so there is no track to agree on (D162).
        event.update({"sumo_tiers": args.tiers, "sumo_hazard": args.hazard, "sumo_shrink": args.shrink,
                      "sumo_secs": args.platform_secs, "ai_count": args.ai, "ai_cars": "builtin"})
    if drag:
        # The strip is generated from these, so there is no track to agree on (D168).
        event.update({"drag_length_m": args.length, "drag_boost": args.boost,
                      "ai_count": args.ai, "ai_cars": "builtin"})
    if args.event == "battle":
        event.update({"battle_rule": args.rule, "battle_min": args.minutes, "ai_count": args.ai, "ai_cars": "builtin"})
    if args.event in ["race", "kart"]:
        event.update({"practice_min": 5 if args.fresh else 0, "qualifying_min": 0, "race_laps": args.laps,
                      "ai_count": args.ai, "grid": "random", "start": "standing",
                      "ai_cars": "garage" if args.fresh else "builtin"})
    config = {
        "schema": "noss.server/1", "name": "net_check", "port": args.port, "max_players": 16, "lan": bool(args.open),
        "rotation": [{"track": track, "class": args.klass, "event": event}],
        "plausibility": args.plausibility,
    }
    config_path = logs / "server.json"
    config_path.write_text(json.dumps(config))
    procs = []

    wine_prefix = None
    if args.exported:
        import tempfile
        wine_prefix = tempfile.mkdtemp(prefix="noss_wine_")

    def command(name):
        """The program for `name`: the project, or (--exported) the server export and the Linux and
        Windows exports in turn for bots."""
        if not args.exported:
            return [GODOT], {}
        if name == "server":
            return [str(ROOT / "export" / "server" / "noss_server.x86_64")], {}
        if int(name[3:]) % 2 == 0:
            return [str(next((ROOT / "export" / "linux").glob("*.x86_64")))], {}
        env = dict(os.environ, WINEPREFIX=wine_prefix, WINEDLLOVERRIDES="winemenubuilder.exe=d", WINEDEBUG="-all")
        return ["wine", str(next((ROOT / "export" / "windows").glob("*.exe")))], env

    def start(name, extra):
        out = open(logs / f"{name}.log", "w")
        program, env = command(name)
        proc = subprocess.Popen(program + ["--headless", "--"] + extra, stdout=out, stderr=subprocess.STDOUT,
                                cwd=ROOT, start_new_session=True, env=env or None)
        procs.append((name, proc, out))
        return proc

    def stop_all():
        for _, proc, out in procs:
            if proc.poll() is None:
                os.killpg(proc.pid, signal.SIGTERM)
        for _, proc, out in procs:
            try:
                proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(proc.pid, signal.SIGKILL)
            out.close()

    debug = ["--net-debug"] if args.verbose else []
    # --fresh: the garage's personal-use cars (FM4) go to this PC's own bot only (Requirements §6).
    personal = ["--share-personal"] if args.fresh else []
    # Its own folder (instances/90): its boards and keys never mix with this PC's player's.
    late_bots = 1 if endless and args.late > 0 else 0
    server = start("server", ["--server", f"--config={config_path}", f"--min-players={players - late_bots * (4 if args.quad and not args.clients else 1)}",
                              "--net-stats", "--instance=90"] + debug + personal)
    time.sleep(2.0)
    if server.poll() is not None:  # it couldn't start (most often: the port is taken by another server)
        reason = [l for l in (logs / "server.log").read_text(errors="replace").splitlines() if "Can't" in l or "ERROR" in l]
        stop_all()
        sys.exit("FAIL the server stopped at once: " + (reason[-1].strip() if reason else "see " + str(logs / "server.log")))
    if args.open:
        print(f'open: join "net_check" from the LAN list, or {lan_ip()}:{args.port} (UDP {args.port} and {args.port + 1} must be let in)', flush=True)
    port = args.port
    sim = None
    if args.rtt or args.jitter or args.loss or args.rate != "0":
        sim = net_sim.NetSim(("127.0.0.1", 0), ("127.0.0.1", args.port), args.rtt / 2.0, args.jitter, args.loss,
                             net_sim.parse_rate(args.rate), seed=1)
        threading.Thread(target=sim.run, daemon=True).start()
        port = sim.port

    quit_flag = ["--quit-after-results"] if args.event in ["race", "kart", "battle", "sumo", "drag"] else [f"--quit-at={args.duration + 15}"]
    if args.fresh:
        cache = logs / "fresh_cache"
        import shutil
        shutil.rmtree(cache, ignore_errors=True)
        quit_flag = [f"--quit-at={args.within + 40}", "--bot-full", f"--cache={cache}"] + debug
    bots = []
    for i in range(args.clients + args.quad):
        if late_bots and i == args.clients + args.quad - 1:
            time.sleep(args.late)
        late = ["--quit-at=%g" % (args.duration + 15 - args.late)] if late_bots and i == args.clients + args.quad - 1 else []
        n = 4 if i >= args.clients else 1
        cheat = [f"--cheat={args.cheat}"] if args.cheat and i == 0 else []
        cheat += ["--traffic-desync"] if args.desync and i == 0 else []
        factor = args.speed_factor or (1.4 if args.police else 0.0)
        cheat += [f"--speed-factor={factor:g}"] if factor else []
        cheat += ["--kart-debug"] if os.environ.get("KART_DEBUG") else []
        if karts and args.classes == "mixed":
            cheat += ["--p1-profile=" + json.dumps({"kart_class": KART_CLASSES[i % len(KART_CLASSES)]})]
        bots.append(start(f"bot{i:02d}", ["--bot", f"--connect=127.0.0.1:{port}", f"--players={n}",
                                          f"--bot-fps={args.bot_fps}"] + (late or quit_flag) + cheat))
        time.sleep(0.2)

    peak = {}
    deadline = time.monotonic() + (args.within + 80 if args.fresh else 120 + args.minutes * 60 if args.event == "battle"
                                   else 60 + args.laps * 150 if args.event in ["race", "kart"] else args.duration + 60)
    try:
        while time.monotonic() < deadline and any(b.poll() is None for b in bots):
            for name, proc, _ in procs:
                peak[name] = max(peak.get(name, 0.0), rss_mb(proc.pid))
            time.sleep(1.0)
    finally:
        timed_out = any(b.poll() is None for b in bots)
        stop_all()
        if sim:
            sim.running = False
        if wine_prefix:
            import shutil
            server_bin = shutil.which("wineserver") or "/usr/lib/x86_64-linux-gnu/wine/wineserver"
            if Path(server_bin).exists():  # the prefix's server would linger
                subprocess.run([server_bin, "-k"], env=dict(os.environ, WINEPREFIX=wine_prefix), stderr=subprocess.DEVNULL)
            shutil.rmtree(wine_prefix, ignore_errors=True)

    # Gather the bots' reports.
    reports, contacts, fails, results, checks = {}, [], [], None, []
    server_stats = {}
    endless_server = None
    kart_server = None
    drag_server = None
    loop = None
    track_ms = {}
    for name, proc, _ in procs:
        text = (logs / f"{name}.log").read_text(errors="replace").replace("\r", "")
        if args.verbose:
            print(f"--- {name}\n{text}")
        for line in text.splitlines():
            if line.startswith("NETCHECK "):
                reports[name] = json.loads(line[len("NETCHECK "):])
            elif "Checks failed:" in line:
                checks.append(line.split("Checks failed:", 1)[1].strip())
            elif line.startswith("NETCHECK_TRACK "):
                track_ms[name] = int(line.split()[1])
            elif line.startswith("NETCHECK_SERVER "):
                server_stats = json.loads(line[len("NETCHECK_SERVER "):])
            elif line.startswith("NETCHECK_LOOP "):
                loop = json.loads(line[len("NETCHECK_LOOP "):])
            elif line.startswith("NETCHECK_RESULTS "):
                results = json.loads(line[len("NETCHECK_RESULTS "):])
            elif line.startswith("NETCHECK_ENDLESS_SERVER "):
                endless_server = json.loads(line[len("NETCHECK_ENDLESS_SERVER "):])
            elif line.startswith("NETCHECK_KART_SERVER "):
                kart_server = json.loads(line[len("NETCHECK_KART_SERVER "):])
            elif line.startswith("NETCHECK_DRAG_SERVER "):
                drag_server = json.loads(line[len("NETCHECK_DRAG_SERVER "):])
            elif line.startswith("NETCHECK_CONTACT "):
                t, a, b, x, y, z = line.split()[1:]
                contacts.append({"t": float(t), "a": int(a), "b": int(b), "pos": (float(x), float(y), float(z))})
            elif re.search(r"SCRIPT ERROR|^ERROR:", line) and "Remote Debugger" not in line:
                fails.append(f"{name}: {line.strip()}")
    if timed_out:
        fails.append("bots still running at the deadline")

    print("net_check: %d players (%d bots), %s, %s, %s%s%s" % (
        players, len(bots), args.event, args.klass, Path(args.track).name, ", exported builds (odd bots on Windows under Wine)" if args.exported else "",
        f", link {args.rtt:g} ms RTT, jitter {args.jitter:g} ms, loss {args.loss:g}%, rate {args.rate}" if sim else ""))
    print("%-7s %4s %8s %8s %8s %9s %9s %9s %8s %7s %5s" % ("bot", "pl", "down", "max", "up", "err med", "err p95", "err max", "contacts", "RSS", "thr"))
    worst_down = 0.0
    for name in sorted(n for n in reports if n.startswith("bot")):
        r = reports[name]
        worst_down = max(worst_down, r["down_avg"])
        print("%-7s %4d %7.1fK %7.1fK %7.1fK %8.2fm %8.2fm %8.2fm %8d %6.0fM %5d" % (
            name, r["players"], r["down_avg"], r["down_max"], r["up_avg"], r["err_median"], r["err_p95"],
            r["err_max"], r["contacts"], peak.get(name, 0.0), r.get("throttle_min", 32)))
        if r.get("throttle_min", 32) < 32:  # ENet would drop most of its car states (D79)
            fails.append(f"{name}: ENet's throttle fell to {r['throttle_min']}/32")
        kicked = args.cheat and args.plausibility == "kick"
        if kicked and name == "bot00":
            continue  # kicked (and back, as bots rejoin)
        if r["sessions"] < 1:
            fails.append(f"{name} never got into the session")
        elif r["remote_cars"] < players - r["players"] - (1 if kicked else 0):
            fails.append(f"{name} saw {r['remote_cars']} remote cars, not {players - r['players']}")
    for name in (f"bot{i:02d}" for i in range(len(bots))):
        if name not in reports:
            fails.append(f"{name} reported nothing")
    print("server RSS %.0f MB, bots max %.0f MB" % (peak.get("server", 0.0), max([v for k, v in peak.items() if k.startswith("bot")] or [0])))
    if highway:
        print("%-7s %10s %7s %6s %9s %9s %8s %9s" % ("traffic", "mismatches", "resyncs", "late", "handovers", "owned max", "ticks/s", "err p95"))
        for name in sorted(n for n in reports if n.startswith("bot")):
            t = reports[name].get("traffic", {})
            if not t:
                fails.append(f"{name}: no traffic")
                continue
            print("%-7s %10d %7d %6d %9d %9d %8.0f %8.2fm" % (name, t["mismatches"], t["resyncs"], t["late"], t["handovers"], t["owned_max"],
                  t["tick_rate_min"], t.get("err_p95", 0.0)))
            if t.get("err_p95", 0.0) > MAX_TRAFFIC_ERR_M:
                fails.append(f"{name}: traffic shown {t['err_p95']:.2f} m off (p95)")
            desynced = args.desync and name == "bot00"
            if desynced:  # it must notice and come back: out of step, then the server's again
                if t["mismatches"] < HIGHWAY_MISSES or t["resyncs"] < 2:
                    fails.append(f"{name}: put out of step, it didn't resync ({t['mismatches']} mismatches, {t['resyncs']} full states)")
            elif t["mismatches"] > 0:
                fails.append(f"{name}: {t['mismatches']} traffic checksums disagreed")
            if t["resyncs"] > 1 and not desynced:
                fails.append(f"{name}: took the server's traffic {t['resyncs']} times")
            if t["beats"] < 5:
                fails.append(f"{name}: only {t['beats']} traffic checksums compared")
            if 0 <= t["tick_rate_min"] < 18:
                fails.append(f"{name}: its lane sim fell behind ({t['tick_rate_min']:.0f} ticks/s)")
        if server_stats:
            print("server traffic: " + ", ".join(f"{k} {v}" for k, v in server_stats.items()))
            if args.police and server_stats.get("pursuits", 0) < 1:
                fails.append("police on, but no chase began")
        else:
            fails.append("the server reported no traffic")
        if args.dirs == "opposite":  # acceptance 3 online: they meet every lap, the traffic comes round
            if not loop or not loop["rows"]:
                fails.append("no whole lap of the loop (%s)" % (
                    "on lap %d, +1 player at %s m and %s km/h" % (loop["lap"], *loop.get("a_at", ["?", "?"])) if loop else "nobody each way round"))
            else:
                print("loop: %s (+1) on lap %d and %s (-1) on lap %d" % (loop["a"], loop["lap"], loop["b"], loop["b_lap"]))
                if loop["b_lap"] < loop["lap"] - 1:  # the server counts laps the other way round too
                    fails.append(f"loop: {loop['b']}'s laps didn't count (lap {loop['b_lap']})")
                for r in loop["rows"]:
                    print("  lap %d: met %d times, %d traffic cars met, %s met again next lap" % (
                        r["lap"], r["met"], r["traffic"], "%.0f%%" % (r["again"] * 100) if r["again"] >= 0 else "-"))
                    if r["met"] < 1:
                        fails.append(f"loop lap {r['lap']}: they never passed")
                    if 0 <= r["again"] < LOOP_AGAIN_MIN:
                        fails.append(f"loop lap {r['lap']}: only {r['again'] * 100:.0f}% of the traffic came round again")
    if endless:
        print("%-7s %7s %7s %8s %6s %9s %8s %9s %6s %7s" % ("endless", "km", "shifts", "start", "lead", "traffic", "proxies", "handovers", "gone", "near s"))
        last = f"bot{len(bots) - 1:02d}"
        for name in sorted(n for n in reports if n.startswith("bot")):
            r = reports[name]
            e = r.get("endless", {})
            if not e:
                fails.append(f"{name}: no endless report")
                continue
            print("%-7s %7.2f %7d %7.0fm %5.0fm %9d %8d %9d %6d %7d" % (name, e["km"], e["shifts"], e["start_m"], e["lead_m"], e["owned_max"],
                  e["proxies_max"], e["handovers"], e["gone"], e["near_s"]))
            if r["err_p95"] > MAX_ENDLESS_ERR_M:
                fails.append(f"{name}: remote cars shown {r['err_p95']:.2f} m off (p95)")
            if e["km"] < 0.5:
                fails.append(f"{name}: drove only {e['km'] * 1000:.0f} m")
            if args.duration >= 120 and e["shifts"] < 1 and not (late_bots and name == last):
                fails.append(f"{name}: its origin never moved")
            if late_bots and name == last:
                gap = e["lead_m"] - e["start_m"]
                if e["lead_m"] < 0 or not 0 <= gap <= 400:
                    fails.append(f"{name} joined {gap:.0f} m behind the leader")
        # Bots that started together each have their own spot (a LAN test had two cars land on each other).
        spawns = sorted((reports[n]["endless"]["spawn_m"], n) for n in reports
                        if n.startswith("bot") and reports[n].get("endless", {}).get("spawn_m") is not None
                        and not (late_bots and n == last))
        for (a, na), (b, nb) in zip(spawns, spawns[1:]):
            if b - a < 10.0:
                fails.append(f"{na} and {nb} started {b - a:.1f} m apart")
        if not any(reports[n].get("endless", {}).get("proxies_max", 0) > 0 for n in reports if n.startswith("bot")) and len(bots) > 1:
            fails.append("no traffic car was shown from another game")
        if endless_server is None:
            fails.append("the server reported nothing on the road")
        else:
            print("server road: %d chunks checked, %d differed; %d traffic owners, %d handovers, %d slots used up" % (
                endless_server["checked"], endless_server["mismatches"], endless_server["owners"], endless_server["handovers"], endless_server["gone"]))
            if endless_server["checked"] < len(bots) * 5:
                fails.append(f"only {endless_server['checked']} road chunks checked")
            if endless_server["mismatches"]:
                fails.append(f"{endless_server['mismatches']} road chunks differed from the server's")
    for name, ms in sorted(track_ms.items()):
        print("%s got the track in %d ms" % (name, ms))
    if args.fresh and not builtin_track and "bot00" not in track_ms:
        fails.append("the fresh bot never got the track")
    if args.fresh:
        r = reports.get("bot00", {})
        print("fresh client: %d cars, all as previews in %.1f s, whole in %.1f s (target %g s)" % (
            r.get("cars", 0), r.get("preview_s", -1), r.get("full_s", -1), args.within))
        if r.get("full_s", -1) < 0 or r["full_s"] > args.within:
            fails.append("not every car whole within %g s" % args.within)
    elif args.event == "battle":
        if results is None:
            fails.append("no battle results")
        else:
            rows = results["rows"]
            print("battle results (%s):" % args.rule)
            for r in rows:
                print("  P%-2d %-16s lives %s, hits %d%s" % (r["position"], r["name"], r["lives"] if r["lives"] >= 0 else "-", r["hits"],
                      "  (AI)" if r["ai"] else ""))
            if len(rows) != players + args.ai:
                fails.append("%d karts in the results, not %d" % (len(rows), players + args.ai))
    elif args.event == "drag":
        if results is None:
            fails.append("no drag results")
        else:
            rows = results["rows"]
            print("drag results (%d m, %s):" % (args.length, args.drag_class))
            for r in rows:
                print("  P%-2d %-16s round %s, %s, %s%s" % (r["position"], r["name"], r.get("round", "-"),
                      "RT %.3f" % r["reaction"] if r.get("reaction", -1.0) >= 0.0 else "RT -",
                      "ET %.3f" % r["et"] if r.get("et", -1.0) >= 0.0 else "ET -", "  (AI)" if r["ai"] else ""))
            if len(rows) != players + args.ai:
                fails.append("%d cars in the results, not %d" % (len(rows), players + args.ai))
            # One winner, and everyone else out of the ladder behind it.
            if rows and int(rows[0].get("round", 0)) <= 0:
                fails.append("the leader never reached a round")
            # The ladder eliminates one car a pass, so a field of n takes n-1 passes.
            server = drag_server or {}
            if server:
                print("  server: %d events, %d grades taken from clients, %d passes" % (
                    server.get("events", 0), server.get("grades", 0), server.get("passes", 0)))
                want = max(len(rows) - 1, 1)
                if int(server.get("passes", 0)) != want:
                    fails.append("%d passes run, %d expected for %d cars" % (server["passes"], want, len(rows)))
                if not server.get("winner"):
                    fails.append("the server's ladder has no winner")
                if int(server.get("grades", 0)) == 0 and players > 0:
                    fails.append("the server took no shift grades from any client")
    elif args.event == "sumo":
        if results is None:
            fails.append("no sumo results")
        else:
            rows = results["rows"]
            print("sumo results (%d tier(s), %s, %s):" % (args.tiers, args.hazard, args.shrink))
            for r in rows:
                print("  P%-2d %-16s tier %s, %s%s" % (r["position"], r["name"], r.get("tier", "-"),
                      "lasted %.1f s" % r["lasted"] if r.get("out") else "won", "  (AI)" if r["ai"] else ""))
            if len(rows) != players + args.ai:
                fails.append("%d cars in the results, not %d" % (len(rows), players + args.ai))
            still_in = [r for r in rows if not r.get("out")]
            if len(still_in) != 1:
                fails.append("%d cars ended still in, not 1" % len(still_in))
    elif args.event in ["race", "kart"]:
        if results is None:
            fails.append("no race results")
        else:
            rows = results["rows"]
            print("race results:")
            for r in rows:
                print("  P%-2d %-16s %d laps  %s%s" % (r["position"], r["name"], r["laps"],
                      "DNF" if r["dnf"] else "%.3f s" % r["time"], "  (AI)" if r["ai"] else ""))
            if len(rows) != players + args.ai:
                fails.append("%d cars classified, not %d" % (len(rows), players + args.ai))
            for r in rows:
                if r["dnf"] or r["laps"] < args.laps:
                    fails.append("%s not classified (%d laps%s)" % (r["name"], r["laps"], ", DNF" if r["dnf"] else ""))
    if karts:
        print("%-7s %6s %6s %11s %9s %11s  %s" % ("items", "uses", "hits", "corrections", "err p95", "seekers p95", "class"))
        for name in sorted(n for n in reports if n.startswith("bot")):
            k = reports[name].get("kart", {})
            if not k:
                fails.append(f"{name}: no kart items")
                continue
            print("%-7s %6d %6d %11d %8.2fm %10.2fm  %s" % (name, k["uses"], k["hits"], k["corrections"], k["err_p95"], k.get("chaser_p95", 0.0),
                                                       k.get("class", "").rsplit(".", 1)[-1]))
            if k["err_p95"] > MAX_ITEM_ERR_M:
                fails.append(f"{name}: items {k['err_p95']:.2f} m off the server's (p95)")
        if kart_server is None:
            fails.append("the server reported no items")
        else:
            print("server items: %d hits validated, %d turned down, %d contested, %d forced; picks turned down %d, uses %d" % (
                kart_server["validated"], kart_server["rejected"], kart_server.get("contested", 0), kart_server["forced"],
                kart_server.get("rejected_picks", 0), kart_server.get("rejected_uses", 0)))
            reported = kart_server["validated"] + kart_server["rejected"]
            # A hit turned down now and then is the system working; most of them is sync going wrong.
            if kart_server["rejected"] > max(1, reported * MAX_REJECTED):
                fails.append("%d of %d hit reports turned down" % (kart_server["rejected"], reported))
            if kart_server.get("rejected_uses", 0) > 0:
                fails.append("%d item uses turned down" % kart_server["rejected_uses"])
    for c in checks:
        print("check: " + c)
    if args.cheat:
        if not checks:
            fails.append(f"the {args.cheat} cheat wasn't caught")
        elif len({c.split(" (")[0] for c in checks}) > 1:
            fails.append("honest cars failed checks too")
    elif checks:
        fails.append("honest cars failed checks (%d)" % len(checks))
    if worst_down > MAX_DOWN_KB and not args.fresh:  # a fresh client's download isn't steady traffic
        fails.append("%.1f KB/s down, over %g" % (worst_down, MAX_DOWN_KB))
    if highway:  # knocks with traffic happen offline too; a pile-up of players' cars says sync is off
        contacts = [c for c in contacts if c["a"] < 1000 and c["b"] < 1000]
    # Karts bump far more than cars (kart_check's rule: 4); in an arena they meet head on: what a
    # battle is, and on a shrinking platform shoving each other is the whole of a sumo match.
    piles = [] if args.event in ("battle", "sumo") else pileups(contacts, KART_PILEUP_CARS if karts else PILEUP_CARS)
    for pile in piles:
        fails.append("pile-up: " + pile)
    print("contacts %d, pile-ups %d" % (len(contacts), len(piles)))
    print("logs: %s" % logs)
    if fails:
        for f in fails[:20]:
            print("FAIL " + f)
        return 1
    print("PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
