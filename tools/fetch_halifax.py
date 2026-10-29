#!/usr/bin/env python3
"""Fetches Halifax Speedway's real-world layout, lake and ground (D230) into tools/data/halifax.json.

Run once by a developer; the generators (tools/make_halifax_speedway.gd and
tools/make_halifax_road_course.gd) and their tests read the file offline. Standard library only;
the Overpass and OpenTopoData calls are fetch_piedmont.py's.

    python3 -I tools/fetch_halifax.py [--out=tools/data/halifax.json]

Layout: the Daytona International Speedway 2.5-mile tri-oval from OpenStreetMap (its five ways, in
driving order), its pit lane (two ways), every raceway way round it with its node ids (the infield
road course is routed through them) and Lake Lloyd's outline, from the Overpass API:
© OpenStreetMap contributors, ODbL 1.0. Ground: USGS 3DEP / NED 1/3 arc-second (about 10 m) from
the OpenTopoData API (dataset ned10m) on a 25 m grid over the venue plus MARGIN_M, at most 100
points a call and a call a second (their usage policy). USGS data is in the public domain.

Positions are metres from the oval's centre: x east, z south (north is -z).
"""

import argparse
import datetime
import importlib.util
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "tools" / "data" / "halifax.json"
_spec = importlib.util.spec_from_file_location("fetch_piedmont", Path(__file__).resolve().parent / "fetch_piedmont.py")
P = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(P)

# The oval's ways in driving order (counter-clockwise), and the pit lane's: (way, reversed).
OVAL_WAYS = [352070316, 11371365, 352067004, 352070311, 352070309]
PIT_WAYS = [(352067003, False), (198465568, False)]
LAKE_WAY = 119970289
CELL_M = 25.0
MARGIN_M = 250.0
# Raceway ways within this of the oval's centre are kept (the road course, its pit lane).
NEAR_M = 1300.0


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(OUT))
    args = ap.parse_args()

    ids = ",".join(str(w) for w in OVAL_WAYS + [w for w, _ in PIT_WAYS] + [LAKE_WAY])
    found = P.overpass("[out:json][timeout:90];way(id:%s);out body geom;" % ids)
    by_id = {e["id"]: e for e in found["elements"] if e["type"] == "way"}
    geom = lambda w: [(p["lat"], p["lon"]) for p in by_id[w]["geometry"]]
    oval = P.chain([geom(w) for w in OVAL_WAYS])
    if P.dist(oval[-1], oval[0]) > P.JOIN_M:
        raise SystemExit("the oval doesn't close")
    oval = oval[:-1]
    pit = P.chain([geom(w)[::-1] if rev else geom(w) for w, rev in PIT_WAYS])
    lake = geom(LAKE_WAY)[:-1]

    lats = [p[0] for p in oval]
    lons = [p[1] for p in oval]
    lat0 = (min(lats) + max(lats)) / 2.0
    lon0 = (min(lons) + max(lons)) / 2.0
    m_lat = math.radians(1.0) * P.EARTH_R
    m_lon = m_lat * math.cos(math.radians(lat0))

    def local(p: tuple) -> list:
        return [round((p[1] - lon0) * m_lon, 2), round(-(p[0] - lat0) * m_lat, 2)]

    centreline = [local(p) for p in oval]
    if P.signed_area(centreline) < 0.0:
        raise SystemExit("the oval runs clockwise")

    # Every raceway round it, with node ids, for the road course.
    around = P.overpass('[out:json][timeout:90];way["highway"="raceway"](around:%d,%.6f,%.6f);out body geom;' % (NEAR_M, lat0, lon0))
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
    length = sum(P.dist(a, b) for a, b in zip(oval, oval[1:] + oval[:1]))
    print("Oval: %d points, %.0f m; pit lane %d points; lake %d points; %d raceways; ground: %d by %d"
          % (len(oval), length, len(pit), len(lake), len(raceways), nx, nz))
    heights = P.elevations(grid)

    data = {
        "name": "Halifax Speedway",
        "fetched": datetime.date.today().isoformat(),
        "layout_source": "OpenStreetMap ways %s (the oval), %s (the pit lane), %d (Lake Lloyd) and the raceways round them, via the Overpass API"
            % (", ".join(str(w) for w in OVAL_WAYS), ", ".join(str(w) for w, _ in PIT_WAYS), LAKE_WAY),
        "layout_license": "© OpenStreetMap contributors, ODbL 1.0 (https://www.openstreetmap.org/copyright)",
        "ground_source": "USGS 3DEP / National Elevation Dataset 1/3 arc-second (about 10 m) via the OpenTopoData API",
        "ground_license": "Public domain (U.S. Geological Survey)",
        "origin_lat_lon": [round(lat0, 7), round(lon0, 7)],
        "axes": "metres from origin: x east, z south",
        "centreline": centreline,
        "pit_lane": [local(p) for p in pit],
        "lake": [local(p) for p in lake],
        "raceways": raceways,
        "dem": {"origin": [x0, z0], "cell_m": CELL_M, "size": [nx, nz], "heights": [round(h, 2) for h in heights]},
    }
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")) + "\n")
    print("Wrote %s" % out)


if __name__ == "__main__":
    main()
