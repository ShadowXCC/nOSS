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

On a highway (--event highway, the Lumen Ring and the Street class unless given) every bot also
reports its traffic: checksums that disagreed with the server's (must be 0), full states taken
(1 on joining), late events rolled back, handovers, and the most physics cars it drove; the
server reports promotions and handovers (NETCHECK_SERVER).

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
MAX_DOWN_KB = 64.0
MAX_TRAFFIC_ERR_M = 1.0


def rss_mb(pid):
    try:
        for line in Path(f"/proc/{pid}/status").read_text().splitlines():
            if line.startswith("VmRSS:"):
                return int(line.split()[1]) / 1024.0
    except OSError:
        pass
    return 0.0


def pileups(contacts):
    """Groups of PILEUP_CARS+ cars linked by contacts within PILEUP_S and PILEUP_M."""
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
        if len(cars) >= PILEUP_CARS:
            out.append("%d cars at %.1f s (%s)" % (len(cars), c["t"], ", ".join(str(x) for x in sorted(cars))))
    return out


def dist(a, b):
    return sum((x - y) ** 2 for x, y in zip(a, b)) ** 0.5


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--clients", type=int, default=3, help="bots with one player each")
    p.add_argument("--quad", type=int, default=0, help="bots with four players each (splitscreen guests)")
    p.add_argument("--duration", type=float, default=60.0, help="seconds of driving (free drive)")
    p.add_argument("--event", choices=["free", "race", "highway"], default="free")
    p.add_argument("--traffic", type=int, default=150, help="highway: traffic cars")
    p.add_argument("--laps", type=int, default=3)
    p.add_argument("--ai", type=int, default=0, help="AI cars the server adds (races)")
    p.add_argument("--class", dest="klass", default="")
    p.add_argument("--track", default="",
                   help="the server's track: an id, or a .nosstrack / track folder (sent to bots that lack it)")
    p.add_argument("--port", type=int, default=47850)
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
    p.add_argument("--verbose", action="store_true")
    args = p.parse_args(argv)
    highway = args.event == "highway"
    args.klass = args.klass or ("official.highway.street" if highway else "official.track.gt")
    args.track = args.track or ("lumen_ring" if highway else "proving_ground")

    logs = Path(args.logs) if args.logs else ROOT / "reports" / "net_check" / time.strftime("%Y%m%d_%H%M%S")
    logs.mkdir(parents=True, exist_ok=True)
    if args.fresh:
        args.clients, args.quad, args.event = 1, 0, "race"
    players = args.clients + 4 * args.quad
    track = args.track
    if Path(track).exists():  # a path here, not an id: the config lives in the logs' folder
        track = str(Path(track).resolve())
    builtin_track = (ROOT / "content" / "tracks" / args.track).is_dir()
    event = {"kind": args.event}
    if highway:
        event.update({"sub": "cruise", "traffic": args.traffic})
    if args.event == "race":
        event.update({"practice_min": 5 if args.fresh else 0, "qualifying_min": 0, "race_laps": args.laps,
                      "ai_count": args.ai, "grid": "random", "start": "standing",
                      "ai_cars": "garage" if args.fresh else "builtin"})
    config = {
        "schema": "noss.server/1", "name": "net_check", "port": args.port, "max_players": 16, "lan": False,
        "rotation": [{"track": track, "class": args.klass, "event": event}],
        "plausibility": args.plausibility,
    }
    config_path = logs / "server.json"
    config_path.write_text(json.dumps(config))
    procs = []

    def start(name, extra):
        out = open(logs / f"{name}.log", "w")
        proc = subprocess.Popen([GODOT, "--headless", "--"] + extra, stdout=out, stderr=subprocess.STDOUT,
                                cwd=ROOT, start_new_session=True)
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
    server = start("server", ["--server", f"--config={config_path}", f"--min-players={players}", "--net-stats"] + debug + personal)
    time.sleep(2.0)
    port = args.port
    sim = None
    if args.rtt or args.jitter or args.loss or args.rate != "0":
        sim = net_sim.NetSim(("127.0.0.1", 0), ("127.0.0.1", args.port), args.rtt / 2.0, args.jitter, args.loss,
                             net_sim.parse_rate(args.rate), seed=1)
        threading.Thread(target=sim.run, daemon=True).start()
        port = sim.port

    quit_flag = ["--quit-after-results"] if args.event == "race" else [f"--quit-at={args.duration + 15}"]
    if args.fresh:
        cache = logs / "fresh_cache"
        import shutil
        shutil.rmtree(cache, ignore_errors=True)
        quit_flag = [f"--quit-at={args.within + 40}", "--bot-full", f"--cache={cache}"] + debug
    bots = []
    for i in range(args.clients + args.quad):
        n = 4 if i >= args.clients else 1
        cheat = [f"--cheat={args.cheat}"] if args.cheat and i == 0 else []
        bots.append(start(f"bot{i:02d}", ["--bot", f"--connect=127.0.0.1:{port}", f"--players={n}",
                                          f"--bot-fps={args.bot_fps}"] + quit_flag + cheat))
        time.sleep(0.2)

    peak = {}
    deadline = time.monotonic() + (args.within + 80 if args.fresh else args.duration + 60 if args.event != "race" else 60 + args.laps * 150)
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

    # Gather the bots' reports.
    reports, contacts, fails, results, checks = {}, [], [], None, []
    server_stats = {}
    track_ms = {}
    for name, proc, _ in procs:
        text = (logs / f"{name}.log").read_text(errors="replace")
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
            elif line.startswith("NETCHECK_RESULTS "):
                results = json.loads(line[len("NETCHECK_RESULTS "):])
            elif line.startswith("NETCHECK_CONTACT "):
                t, a, b, x, y, z = line.split()[1:]
                contacts.append({"t": float(t), "a": int(a), "b": int(b), "pos": (float(x), float(y), float(z))})
            elif re.search(r"SCRIPT ERROR|^ERROR:", line) and "Remote Debugger" not in line:
                fails.append(f"{name}: {line.strip()}")
    if timed_out:
        fails.append("bots still running at the deadline")

    print("net_check: %d players (%d bots), %s, %s, %s%s" % (
        players, len(bots), args.event, args.klass, Path(args.track).name,
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
            if t["mismatches"] > 0:
                fails.append(f"{name}: {t['mismatches']} traffic checksums disagreed")
            if t["resyncs"] > 1:
                fails.append(f"{name}: took the server's traffic {t['resyncs']} times")
            if t["beats"] < 5:
                fails.append(f"{name}: only {t['beats']} traffic checksums compared")
            if 0 <= t["tick_rate_min"] < 18:
                fails.append(f"{name}: its lane sim fell behind ({t['tick_rate_min']:.0f} ticks/s)")
        if server_stats:
            print("server traffic: " + ", ".join(f"{k} {v}" for k, v in server_stats.items()))
        else:
            fails.append("the server reported no traffic")
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
    elif args.event == "race":
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
    piles = pileups(contacts)
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
