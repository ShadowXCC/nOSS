#!/usr/bin/env python3
"""Converts ripped Forza Motorsport 4 car folders into .noss packages (PKG-09).

Local use only: the packages are marked personal-use-only and must never be
shared or committed (Requirements.md §6). Format: docs/VEHICLE_PACKAGE.md.

    python3 tools/fm4_to_noss.py "<...>/Forza Motorsport 4/models/ACU_NSX_97"
    python3 tools/fm4_to_noss.py "<...>/Forza Motorsport 4/models"      # every car inside
    python3 tools/fm4_to_noss.py CAR --out DIR --rhd --sound v8_crossplane

Output goes to the game's garage (user://garage/) unless --out is given.
Re-running on an unchanged car leaves the package as is; a changed car gets version + 1.
"""

import argparse
import fnmatch
import hashlib
import io
import json
import math
import os
import re
import struct
import sys
import uuid
import zipfile
from pathlib import Path

TOOL_VERSION = "0.1"
GAME_MIN_VERSION = "0.1.0"
# Fixed namespace so the same FM4 car always gets the same package id.
ID_NAMESPACE = uuid.UUID("4f7c1e2a-9b3d-5e61-8a0f-6d2c3b4a5e70")

WHEEL_IDS = ("LF", "RF", "LR", "RR")
LOD_DISTANCES_M = [0, 12, 30, 70, 150, 300]
DEFAULT_SOUND = "v8_crossplane"
FINISHES = {"Normal": "solid", "Metallic": "metallic", "CarbonFiber": "matte"}
PAINT_SLOTS = {"Paint_Primary": "primary", "Paint_Secondary": "secondary", "Paint_Tertiary": "tertiary"}

# Eye point heuristic: seated eye height above the seat's lowest point, kept below the roof.
SEATED_EYE_HEIGHT_M = 0.75
EYE_BELOW_ROOF_M = 0.17
EYE_FORWARD_OF_SEAT_BACK_M = 0.30

ZIP_DATE = (1980, 1, 1, 0, 0, 0)
LIMIT_ZIP_BYTES = 50 * 1024 * 1024


class ConvertError(Exception):
    pass


# --- glTF helpers ------------------------------------------------------------


def read_glb_json(path):
    with open(path, "rb") as f:
        header = f.read(12)
        if len(header) < 12:
            raise ConvertError(f"{path.name}: not a GLB")
        magic, version, _ = struct.unpack("<III", header)
        if magic != 0x46546C67 or version != 2:
            raise ConvertError(f"{path.name}: not a glTF 2.0 binary")
        chunk_len, chunk_type = struct.unpack("<II", f.read(8))
        if chunk_type != 0x4E4F534A:
            raise ConvertError(f"{path.name}: first chunk isn't JSON")
        return json.loads(f.read(chunk_len))


def quat_to_matrix(q):
    x, y, z, w = q
    return [
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w), 0],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w), 0],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y), 0],
        [0, 0, 0, 1],
    ]


def mat_mul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(4)) for j in range(4)] for i in range(4)]


def node_matrix(node):
    if "matrix" in node:
        m = node["matrix"]  # column-major
        return [[m[c * 4 + r] for c in range(4)] for r in range(4)]
    t = node.get("translation", [0, 0, 0])
    s = node.get("scale", [1, 1, 1])
    m = quat_to_matrix(node.get("rotation", [0, 0, 0, 1]))
    for r in range(3):
        for c in range(3):
            m[r][c] *= s[c]
        m[r][3] = t[r]
    return m


def transform_point(m, p):
    return [m[r][0] * p[0] + m[r][1] * p[1] + m[r][2] * p[2] + m[r][3] for r in range(3)]


class Model:
    """Node world transforms and mesh bounds of a GLB, from its JSON chunk alone."""

    def __init__(self, gltf):
        self.gltf = gltf
        self.world = {}  # node index -> 4x4
        self.by_name = {}
        scene = gltf.get("scenes", [{}])[gltf.get("scene", 0)]
        identity = [[1 if r == c else 0 for c in range(4)] for r in range(4)]
        for root in scene.get("nodes", []):
            self._walk(root, identity)

    def _walk(self, index, parent):
        node = self.gltf["nodes"][index]
        world = mat_mul(parent, node_matrix(node))
        self.world[index] = world
        if "name" in node:
            self.by_name.setdefault(node["name"], index)
        for child in node.get("children", []):
            self._walk(child, world)

    def position(self, name):
        index = self.by_name.get(name)
        return None if index is None else [self.world[index][r][3] for r in range(3)]

    def node_bounds(self, index):
        """World AABB of one node's own mesh, or None."""
        node = self.gltf["nodes"][index]
        if "mesh" not in node:
            return None
        lo, hi = [math.inf] * 3, [-math.inf] * 3
        for prim in self.gltf["meshes"][node["mesh"]]["primitives"]:
            acc = self.gltf["accessors"][prim["attributes"]["POSITION"]]
            if "min" not in acc or "max" not in acc:
                raise ConvertError("POSITION accessor without min/max")
            mn, mx = acc["min"], acc["max"]
            for corner in ((x, y, z) for x in (mn[0], mx[0]) for y in (mn[1], mx[1]) for z in (mn[2], mx[2])):
                p = transform_point(self.world[index], corner)
                lo = [min(lo[k], p[k]) for k in range(3)]
                hi = [max(hi[k], p[k]) for k in range(3)]
        return lo, hi

    def bounds(self, name=None):
        lo, hi = [math.inf] * 3, [-math.inf] * 3
        indices = self.world if name is None else [self.by_name[name]] if name in self.by_name else []
        for index in indices:
            b = self.node_bounds(index)
            if b:
                lo = [min(lo[k], b[0][k]) for k in range(3)]
                hi = [max(hi[k], b[1][k]) for k in range(3)]
        return None if lo[0] == math.inf else (lo, hi)

    def names_matching(self, pattern):
        return sorted(n for n in self.by_name if fnmatch.fnmatchcase(n.lower(), pattern.lower()))


# --- conversion --------------------------------------------------------------


def r4(v):
    return round(v, 4)


def vec(v):
    return [r4(x) for x in v]


def display_name(car):
    media = car["media_name"]
    parts = media.split("_")
    model = "_".join(parts[1:-1]) if len(parts) >= 3 else media
    model = re.sub(r"(?<=[a-z0-9])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])", " ", model).replace("_", " ")
    make = car.get("make") or car.get("make_code", "")
    return " ".join(str(x) for x in (car.get("year", ""), make, model) if x).strip()


def tags_for(car):
    tags = ["fm4"]
    if car.get("make"):
        tags.append(re.sub(r"[^a-z0-9_-]", "", car["make"].lower().replace(" ", "-")))
    if isinstance(car.get("year"), int):
        tags.append(f"{car['year'] // 10 * 10}s")
    return [t for t in tags if t]


def build_fit(car, model, warnings, driver_side):
    wheels = []
    for wid in WHEEL_IDS:
        hub = car["hubs"].get(wid)
        if hub is None:
            raise ConvertError(f"car.json has no hub {wid}")
        node_pos = model.position(f"hub_{wid}")
        if node_pos is None:
            raise ConvertError(f"model has no hub_{wid} node")
        if max(abs(a - b) for a, b in zip(node_pos, hub["position"])) > 0.01:
            warnings.append(f"hub_{wid} node is >1 cm from car.json position")
        wheel = {
            "id": wid,
            "axle": 1 if wid[1] == "F" else 2,
            "side": wid[0],
            "node": f"hub_{wid}",
            "center": vec(hub["position"]),
            "radius": r4(hub["radius"]),
            "width": r4(hub["width"]),
        }
        if f"wheel_{wid}" in model.by_name:
            wheel["spin_node"] = f"wheel_{wid}"
        if f"caliper_{wid}" in model.by_name:
            wheel["fixed_nodes"] = [f"caliper_{wid}"]
        wheels.append(wheel)

    by_id = {w["id"]: w for w in wheels}
    ground_y = sum(w["center"][1] - w["radius"] for w in wheels) / len(wheels)
    dims = car.get("dimensions", {})
    for axle, key in (("F", "front_ride_height"), ("R", "rear_ride_height")):
        if key in dims:
            axle_ground = sum(by_id[s + axle]["center"][1] - by_id[s + axle]["radius"] for s in "LR") / 2
            if abs(axle_ground + dims[key]) > 0.01:
                warnings.append(f"{key} differs from hubs by {abs(axle_ground + dims[key]) * 100:.1f} cm")

    wheelbase = sum(by_id[s + "F"]["center"][2] - by_id[s + "R"]["center"][2] for s in "LR") / 2
    if "wheelbase" in dims and abs(wheelbase - dims["wheelbase"]) > 0.01:
        warnings.append(f"wheelbase {wheelbase:.3f} m differs from car.json {dims['wheelbase']:.3f} m")
    for axle, key in (("F", "front_track_outer"), ("R", "rear_track_outer")):
        if key in dims:
            outer = by_id["L" + axle]["center"][0] - by_id["R" + axle]["center"][0] + by_id["L" + axle]["width"]
            if abs(outer - dims[key]) > 0.01:
                warnings.append(f"{key} {outer:.3f} m differs from car.json {dims[key]:.3f} m")

    bounds = model.bounds()
    if bounds is None:
        raise ConvertError("model has no meshes")
    lo, hi = bounds
    # FM4's collision box is a simplified shape (no mirrors, shorter overhangs), so only gross
    # mismatches matter: they mean wrong units or orientation.
    box = dims.get("collision_box_fm4_space")
    if box and (abs(hi[1] - box["MaxY"]) > 0.3 or abs(hi[2] - box["MaxZ"]) > 0.3 or abs(lo[2] - box["MinZ"]) > 0.3):
        warnings.append("model bounds differ from FM4 collision box by >30 cm")

    fit = {
        "schema": "noss.fit/1",
        "model_transform": {"scale": 1.0, "rotation_deg": [0, 0, 0], "offset_m": [0, 0, 0]},
        "ground_y": r4(ground_y),
        "wheel_mode": "model",
        "wheels": wheels,
        "steering_wheel": None,
        "eye_point": eye_point(model, hi[1], ground_y, driver_side, warnings),
        "cameras": {"hood": None, "bumper": None},
        "envelope": {"min": vec(lo), "max": vec(hi)},
        "lights": {
            "head": ["headlight*"] if model.names_matching("headlight*") else [],
            "brake": ["tail_light*"],
            "reverse": ["reverse_light*"],
            "indicator_L": [],
            "indicator_R": [],
        },
        "exhaust_points": [vec(model.position(n)) for n in model.names_matching("exhaust*")][:8],
        "hide_nodes": [],
        "lod_distances_m": LOD_DISTANCES_M,
    }
    if "steering_wheel" in model.by_name:
        fit["steering_wheel"] = {"node": "steering_wheel", "visual_lock_deg": 450}
    return fit


def detect_driver_side(model):
    """'L' or 'R' from the steering wheel position (+X is the car's left)."""
    pos = model.position("steering_wheel")
    return "R" if pos is not None and pos[0] < 0 else "L"


def eye_point(model, roof_y, ground_y, side, warnings):
    seat = model.bounds(f"seat{side}") or model.bounds("seatL")
    wheel = model.position("steering_wheel")
    if seat is None:
        warnings.append("no seat node; eye point left for the Fitting Bay")
        return None
    lo, hi = seat
    y = min(lo[1] + SEATED_EYE_HEIGHT_M, roof_y - EYE_BELOW_ROOF_M)
    x = wheel[0] if wheel is not None else (lo[0] + hi[0]) / 2
    z = lo[2] + EYE_FORWARD_OF_SEAT_BACK_M
    if y - ground_y < 0.5:
        warnings.append("eye point is very low; check it in the Fitting Bay")
    return vec([x, y, z])


def build_paint(paint_src):
    slots = {}
    for material, info in paint_src.get("materials_in_glb", {}).items():
        slot = PAINT_SLOTS.get(material)
        if slot:
            slots[slot] = {
                "materials": [material],
                "color": info["rgb"].upper(),
                "finish": FINISHES.get(info.get("finish"), "solid"),
            }
    presets = []
    for color in sorted(paint_src.get("factory_colors", []), key=lambda c: c.get("sequence", 0))[:64]:
        presets.append(
            {
                "name": f"Factory {color.get('sequence', len(presets) + 1)}",
                "primary": color["rgb"].upper(),
                "finish": FINISHES.get(color.get("finish"), "solid"),
            }
        )
    paint = {"schema": "noss.paint/1", "slots": slots}
    if presets:
        paint["presets"] = presets
    return paint


def canonical_json(obj):
    return (json.dumps(obj, sort_keys=True, ensure_ascii=False, indent=2) + "\n").encode("utf-8")


def sha256(data):
    return "sha256:" + hashlib.sha256(data).hexdigest()


def convert(src, out_dir, side_override=None, sound=DEFAULT_SOUND, log=print):
    """Converts one FM4 car folder. Returns the package path."""
    src = Path(src)
    car = json.loads((src / "car.json").read_text())
    media = car["media_name"]
    body_path = src / f"{media}.glb"
    if not body_path.exists():
        raise ConvertError(f"missing {body_path.name}")
    model = Model(read_glb_json(body_path))
    warnings = []
    side = side_override or detect_driver_side(model)

    files = {
        "fit.json": canonical_json(build_fit(car, model, warnings, side)),
        "paint.json": canonical_json(build_paint(json.loads((src / "paint.json").read_text()))),
        "model/body.glb": body_path.read_bytes(),
        "sound/profile.json": canonical_json({"schema": "noss.sound/1", "name": "Default", "base": sound}),
    }
    for lod in range(1, 6):
        lod_path = src / f"{media}_lod{lod}.glb"
        if lod_path.exists():
            read_glb_json(lod_path)  # header check
            files[f"model/lod{lod}.glb"] = lod_path.read_bytes()
    thumb = src / "previews" / f"{media}_front34.png"
    if thumb.exists() and thumb.stat().st_size < 4 * 1024 * 1024:
        files["thumb.png"] = thumb.read_bytes()

    package_id = str(uuid.uuid5(ID_NAMESPACE, "fm4:" + media))
    manifest = {
        "schema": "noss.package/1",
        "id": package_id,
        "version": 1,
        "name": display_name(car)[:96],
        "author": "fm4_to_noss",
        "license": "personal-use-only",
        "family": "car",
        "tags": tags_for(car),
        "source": f"fm4_to_noss {TOOL_VERSION} from {media}",
        "created": car.get("exported", "1970-01-01"),
        "game_min_version": GAME_MIN_VERSION,
        "files": {path: sha256(data) for path, data in sorted(files.items())},
    }

    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / f"{media.lower()}.noss"
    previous = read_manifest(out_path)
    if previous and previous.get("id") == package_id:
        if {**previous, "version": 1} == manifest:
            log(f"{media}: unchanged ({out_path})")
            return out_path
        manifest["version"] = int(previous.get("version", 0)) + 1

    manifest_bytes = canonical_json(manifest)
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w") as zf:
        write_entry(zf, "manifest.json", manifest_bytes)
        for path, data in sorted(files.items()):
            write_entry(zf, path, data)
    if buffer.tell() > LIMIT_ZIP_BYTES:
        raise ConvertError(f"package is {buffer.tell() / 1e6:.1f} MB, over the 50 MB limit")
    tmp = out_path.with_suffix(".noss.tmp")
    tmp.write_bytes(buffer.getvalue())
    os.replace(tmp, out_path)

    for w in warnings:
        log(f"{media}: warning: {w}")
    log(f"{media}: {manifest['name']} v{manifest['version']} -> {out_path} ({buffer.tell() / 1e6:.1f} MB, {sha256(manifest_bytes)[:19]})")
    return out_path


def write_entry(zf, path, data):
    info = zipfile.ZipInfo(path, date_time=ZIP_DATE)
    info.compress_type = zipfile.ZIP_DEFLATED
    info.external_attr = 0o644 << 16
    zf.writestr(info, data, compresslevel=6)


def read_manifest(path):
    try:
        with zipfile.ZipFile(path) as zf:
            return json.loads(zf.read("manifest.json"))
    except (OSError, KeyError, zipfile.BadZipFile, ValueError):
        return None


def default_garage():
    if sys.platform.startswith("win"):
        base = Path(os.environ.get("APPDATA", Path.home() / "AppData" / "Roaming"))
    elif sys.platform == "darwin":
        base = Path.home() / "Library" / "Application Support"
    else:
        base = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local" / "share"))
    return base / "nOSS" / "garage"


def find_cars(path):
    path = Path(path)
    if (path / "car.json").exists():
        return [path]
    return sorted(p.parent for p in path.glob("*/car.json"))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("cars", nargs="+", help="FM4 car folder(s), or a folder of car folders")
    parser.add_argument("--out", default=None, help=f"output folder (default: {default_garage()})")
    side = parser.add_mutually_exclusive_group()
    side.add_argument("--rhd", action="store_true", help="driver sits on the right (default: from the steering wheel)")
    side.add_argument("--lhd", action="store_true", help="driver sits on the left")
    parser.add_argument("--sound", default=DEFAULT_SOUND, help=f"built-in engine sound id (default: {DEFAULT_SOUND})")
    args = parser.parse_args(argv)

    out = Path(args.out).expanduser() if args.out else default_garage()
    side_override = "R" if args.rhd else "L" if args.lhd else None
    folders = [car for path in args.cars for car in find_cars(path)]
    if not folders:
        print("No FM4 car folders (with car.json) found.", file=sys.stderr)
        return 1
    failed = 0
    for folder in folders:
        try:
            convert(folder, out, side_override, args.sound)
        except (ConvertError, OSError, KeyError, ValueError) as e:
            failed += 1
            print(f"{folder.name}: failed: {e}", file=sys.stderr)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
