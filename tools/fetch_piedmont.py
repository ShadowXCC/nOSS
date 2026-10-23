#!/usr/bin/env python3
"""Fetches Piedmont Speedway's real-world layout and ground (D206) into tools/data/piedmont.json.

Run once by a developer; the generators (tools/make_piedmont_speedway.gd and
tools/make_piedmont_road_course.gd) and their tests read the file offline. Standard library only.

    python3 -I tools/fetch_piedmont.py [--out=tools/data/piedmont.json]

Layout: the Charlotte Motor Speedway's 1.5-mile quad-oval from OpenStreetMap (its five ways, in
driving order), its pit lane (four ways, one turned round), and every raceway way round it with
its node ids (the infield road course is routed through them), from the Overpass API:
© OpenStreetMap contributors, ODbL 1.0. Ground: USGS 3DEP / NED 1/3 arc-second (about 10 m) from
the OpenTopoData API (dataset ned10m) on a 25 m grid over the venue plus MARGIN_M, at most 100
points a call and a call a second (their usage policy). USGS data is in the public domain.

Positions are metres from the oval's centre: x east, z south (north is -z).
"""

import argparse
import datetime
import json
import math
import time
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "tools" / "data" / "piedmont.json"
OVERPASS = "https://overpass-api.de/api/interpreter"
OPENTOPODATA = "https://api.opentopodata.org/v1/ned10m"
AGENT = "nOSS-track-tools/1.0 (+https://github.com/ShadowXCC/nOSS)"
# The oval's ways in driving order (counter-clockwise), and the pit lane's: (way, reversed).
OVAL_WAYS = [396483278, 116034341, 402168709, 1052107104, 402168711]
PIT_WAYS = [(116034339, False), (401660631, True), (1052107105, False), (401660628, False)]
EARTH_R = 6371000.0
CELL_M = 25.0
MARGIN_M = 250.0
# Joined ways must meet within this (m).
JOIN_M = 1.0
# Raceway ways within this of the oval's centre are kept (the road course, the pit roads).
NEAR_M = 900.0


def overpass(query: str) -> dict:
    data = urllib.parse.urlencode({"data": query}).encode()
    for attempt in range(6):
        req = urllib.request.Request(OVERPASS, data=data, headers={"User-Agent": AGENT})
        try:
            with urllib.request.urlopen(req, timeout=180) as r:
                return json.load(r)
        except Exception as e:  # busy (429, 502, 504): back off and try again
            wait = 10 * 2 ** attempt
            print("  overpass: %s, again in %d s" % (e, wait))
            time.sleep(wait)
    raise SystemExit("Overpass didn't answer")


def dist(a: tuple, b: tuple) -> float:
    lat = math.radians((a[0] + b[0]) / 2.0)
    return EARTH_R * math.hypot(math.radians(b[0] - a[0]), math.radians(b[1] - a[1]) * math.cos(lat))


def chain(ways: list) -> list:
    """Ways (each a list of (lat, lon)) joined end to start in the order given."""
    path = list(ways[0])
    for w in ways[1:]:
        gap = dist(path[-1], w[0])
        if gap > JOIN_M:
            raise SystemExit("ways don't join: %.1f m gap" % gap)
        path += w[1:]
    return path


def signed_area(path: list) -> float:
    """Shoelace area of (x, z) points: > 0 counter-clockwise seen from above (x east, z south)."""
    s = 0.0
    for (x0, z0), (x1, z1) in zip(path, path[1:] + path[:1]):
        s += x0 * z1 - x1 * z0
    return -s / 2.0  # z points south, so the sign turns round


def elevations(points: list) -> list:
    """USGS NED heights (m) at (lat, lon) points, 100 a call, a call a second."""
    out = []
    for i in range(0, len(points), 100):
        batch = points[i:i + 100]
        locs = "|".join("%.6f,%.6f" % p for p in batch)
        url = OPENTOPODATA + "?" + urllib.parse.urlencode({"locations": locs})
        for attempt in range(5):
            try:
                with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": AGENT}), timeout=60) as r:
                    reply = json.load(r)
                break
            except Exception as e:
                print("  elevation: %s, again" % e)
                time.sleep(5 * 2 ** attempt)
        else:
            raise SystemExit("OpenTopoData didn't answer")
        if reply.get("status") != "OK":
            raise SystemExit("elevation: %s" % reply)
        out += [r["elevation"] for r in reply["results"]]
        print("  heights %d/%d" % (len(out), len(points)))
        time.sleep(1.1)
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(OUT))
    args = ap.parse_args()

    ids = ",".join(str(w) for w in OVAL_WAYS + [w for w, _ in PIT_WAYS])
    found = overpass("[out:json][timeout:90];way(id:%s);out body geom;" % ids)
    by_id = {e["id"]: e for e in found["elements"] if e["type"] == "way"}
    geom = lambda w: [(p["lat"], p["lon"]) for p in by_id[w]["geometry"]]
    oval = chain([geom(w) for w in OVAL_WAYS])
    if dist(oval[-1], oval[0]) > JOIN_M:
        raise SystemExit("the oval doesn't close")
    oval = oval[:-1]
    pit = chain([geom(w)[::-1] if rev else geom(w) for w, rev in PIT_WAYS])

    lats = [p[0] for p in oval]
    lons = [p[1] for p in oval]
    lat0 = (min(lats) + max(lats)) / 2.0
    lon0 = (min(lons) + max(lons)) / 2.0
    m_lat = math.radians(1.0) * EARTH_R
    m_lon = m_lat * math.cos(math.radians(lat0))

    def local(p: tuple) -> list:
        return [round((p[1] - lon0) * m_lon, 2), round(-(p[0] - lat0) * m_lat, 2)]

    centreline = [local(p) for p in oval]
    if signed_area(centreline) < 0.0:
        raise SystemExit("the oval runs clockwise")

    # Every raceway round it, with node ids, for the road course.
    around = overpass('[out:json][timeout:90];way["highway"="raceway"](around:%d,%.6f,%.6f);out body geom;' % (NEAR_M, lat0, lon0))
    raceways = []
    for e in sorted((e for e in around["elements"] if e["type"] == "way"), key=lambda e: e["id"]):
        raceways.append({
            "id": e["id"], "name": e.get("tags", {}).get("name", ""), "oneway": e.get("tags", {}).get("oneway", ""),
            "nodes": e["nodes"], "points": [local((p["lat"], p["lon"])) for p in e["geometry"]],
        })

    xs = [p[0] for p in centreline]
    zs = [p[1] for p in centreline]
    x0 = math.floor((min(xs) - MARGIN_M) / CELL_M) * CELL_M
    z0 = math.floor((min(zs) - MARGIN_M) / CELL_M) * CELL_M
    nx = int(math.ceil((max(xs) + MARGIN_M - x0) / CELL_M)) + 1
    nz = int(math.ceil((max(zs) + MARGIN_M - z0) / CELL_M)) + 1
    grid = [(lat0 - (z0 + j * CELL_M) / m_lat, lon0 + (x0 + i * CELL_M) / m_lon) for j in range(nz) for i in range(nx)]
    length = sum(dist(a, b) for a, b in zip(oval, oval[1:] + oval[:1]))
    print("Oval: %d points, %.0f m; pit lane %d points; %d raceways; ground: %d by %d" % (len(oval), length, len(pit), len(raceways), nx, nz))
    heights = elevations(grid)

    data = {
        "name": "Piedmont Speedway",
        "fetched": datetime.date.today().isoformat(),
        "layout_source": "OpenStreetMap ways %s (the oval), %s (the pit lane) and the raceways round them, via the Overpass API"
            % (", ".join(str(w) for w in OVAL_WAYS), ", ".join(str(w) for w, _ in PIT_WAYS)),
        "layout_license": "© OpenStreetMap contributors, ODbL 1.0 (https://www.openstreetmap.org/copyright)",
        "ground_source": "USGS 3DEP / National Elevation Dataset 1/3 arc-second (about 10 m) via the OpenTopoData API",
        "ground_license": "Public domain (U.S. Geological Survey)",
        "origin_lat_lon": [round(lat0, 7), round(lon0, 7)],
        "axes": "metres from origin: x east, z south",
        "centreline": centreline,
        "pit_lane": [local(p) for p in pit],
        "raceways": raceways,
        "dem": {"origin": [x0, z0], "cell_m": CELL_M, "size": [nx, nz], "heights": [round(h, 2) for h in heights]},
    }
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")) + "\n")
    print("Wrote %s" % out)


if __name__ == "__main__":
    main()
