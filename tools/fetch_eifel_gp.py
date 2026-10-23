#!/usr/bin/env python3
"""Fetches the Eifel GP's real-world layout and ground (D200) into tools/data/eifel_gp.json.

Run once by a developer; the generator (tools/make_eifel_gp.gd) and its test read the file
offline. Standard library only.

    python3 -I tools/fetch_eifel_gp.py [--out=tools/data/eifel_gp.json]

Layout: OpenStreetMap relation 38567 (the GP circuit, its ways one way in driving order) and
the main pit lane way, from the Overpass API: © OpenStreetMap contributors, ODbL 1.0.
Ground: EU-DEM v1.1 (25 m) from the OpenTopoData API on a 25 m grid over the circuit plus
MARGIN_M, at most 100 points a call and a call a second (their usage policy): produced using
Copernicus data and information funded by the European Union (EU-DEM layers).

Positions are metres from the circuit's centre: x east, z south (north is -z).
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
OUT = ROOT / "tools" / "data" / "eifel_gp.json"
OVERPASS = "https://overpass-api.de/api/interpreter"
OPENTOPODATA = "https://api.opentopodata.org/v1/eudem25m"
AGENT = "nOSS-track-tools/1.0 (+https://github.com/ShadowXCC/nOSS)"
RELATION = 38567
PIT_LANE_WAY = 30815119
EARTH_R = 6371000.0
CELL_M = 25.0
MARGIN_M = 250.0
# Joined ways must meet within this (m).
JOIN_M = 1.0


def overpass(query: str) -> dict:
    data = urllib.parse.urlencode({"data": query}).encode()
    req = urllib.request.Request(OVERPASS, data=data, headers={"User-Agent": AGENT})
    with urllib.request.urlopen(req, timeout=120) as r:
        return json.load(r)


def dist(a: tuple, b: tuple) -> float:
    lat = math.radians((a[0] + b[0]) / 2.0)
    return EARTH_R * math.hypot(math.radians(b[0] - a[0]), math.radians(b[1] - a[1]) * math.cos(lat))


def loop_of(relation: dict) -> list:
    """The relation's ways joined end to start into one closed loop of (lat, lon)."""
    ways = [[(p["lat"], p["lon"]) for p in m["geometry"]] for m in relation["members"]
            if m["type"] == "way" and m.get("geometry")]
    path = ways.pop(0)
    while ways:
        nearest = min(ways, key=lambda w: dist(path[-1], w[0]))
        gap = dist(path[-1], nearest[0])
        if gap > JOIN_M:
            raise SystemExit("ways don't join: %.1f m gap" % gap)
        ways.remove(nearest)
        path += nearest[1:]
    gap = dist(path[-1], path[0])
    if gap > JOIN_M:
        raise SystemExit("loop doesn't close: %.1f m gap" % gap)
    return path[:-1]


def elevations(points: list) -> list:
    """EU-DEM heights (m) at (lat, lon) points, 100 a call, a call a second."""
    out = []
    for i in range(0, len(points), 100):
        batch = points[i:i + 100]
        locs = "|".join("%.6f,%.6f" % p for p in batch)
        req = urllib.request.Request(OPENTOPODATA + "?" + urllib.parse.urlencode({"locations": locs}), headers={"User-Agent": AGENT})
        with urllib.request.urlopen(req, timeout=60) as r:
            reply = json.load(r)
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

    found = overpass("[out:json][timeout:60];(rel(%d);way(%d););out geom;" % (RELATION, PIT_LANE_WAY))
    relation = next(e for e in found["elements"] if e["type"] == "relation")
    pit_way = next(e for e in found["elements"] if e["type"] == "way" and e["id"] == PIT_LANE_WAY)
    loop = loop_of(relation)
    pit = [(p["lat"], p["lon"]) for p in pit_way["geometry"]]

    lats = [p[0] for p in loop]
    lons = [p[1] for p in loop]
    lat0 = (min(lats) + max(lats)) / 2.0
    lon0 = (min(lons) + max(lons)) / 2.0
    m_lat = math.radians(1.0) * EARTH_R
    m_lon = m_lat * math.cos(math.radians(lat0))

    def local(p: tuple) -> list:
        return [round((p[1] - lon0) * m_lon, 2), round(-(p[0] - lat0) * m_lat, 2)]

    centreline = [local(p) for p in loop]
    xs = [p[0] for p in centreline]
    zs = [p[1] for p in centreline]
    x0 = math.floor((min(xs) - MARGIN_M) / CELL_M) * CELL_M
    z0 = math.floor((min(zs) - MARGIN_M) / CELL_M) * CELL_M
    nx = int(math.ceil((max(xs) + MARGIN_M - x0) / CELL_M)) + 1
    nz = int(math.ceil((max(zs) + MARGIN_M - z0) / CELL_M)) + 1
    grid = [(lat0 - (z0 + j * CELL_M) / m_lat, lon0 + (x0 + i * CELL_M) / m_lon) for j in range(nz) for i in range(nx)]
    print("Layout: %d points, %.0f m; ground: %d by %d" % (len(loop), sum(dist(a, b) for a, b in zip(loop, loop[1:] + loop[:1])), nx, nz))
    heights = elevations(grid)

    data = {
        "name": "Eifel GP",
        "fetched": datetime.date.today().isoformat(),
        "layout_source": "OpenStreetMap relation %d (and way %d, the pit lane) via the Overpass API" % (RELATION, PIT_LANE_WAY),
        "layout_license": "© OpenStreetMap contributors, ODbL 1.0 (https://www.openstreetmap.org/copyright)",
        "ground_source": "EU-DEM v1.1 (25 m) via the OpenTopoData API",
        "ground_license": "Produced using Copernicus data and information funded by the European Union (EU-DEM layers)",
        "origin_lat_lon": [round(lat0, 7), round(lon0, 7)],
        "axes": "metres from origin: x east, z south",
        "centreline": centreline,
        "pit_lane": [local(p) for p in pit],
        "dem": {"origin": [x0, z0], "cell_m": CELL_M, "size": [nx, nz], "heights": [round(h, 1) for h in heights]},
    }
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")) + "\n")
    print("Wrote %s" % out)


if __name__ == "__main__":
    main()
