#!/usr/bin/env python3
"""Tests for tools/fm4_to_noss.py with a synthetic FM4-style car (no ripped content)."""

import hashlib
import json
import struct
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

from jsonschema import Draft202012Validator

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import fm4_to_noss  # noqa: E402

HUBS = {
    "LF": ([0.80, 0.16, 1.33], 0.30, 0.215),
    "RF": ([-0.80, 0.16, 1.33], 0.30, 0.215),
    "LR": ([0.78, 0.17, -1.22], 0.31, 0.245),
    "RR": ([-0.78, 0.17, -1.22], 0.31, 0.245),
}


def make_glb(steering_x=0.37, with_hubs=True):
    """A GLB whose JSON chunk has the FM4 node layout; meshes are bounds-only accessors."""
    accessors, meshes, nodes = [], [], []

    def mesh(lo, hi):
        accessors.append({"componentType": 5126, "count": 3, "type": "VEC3", "min": lo, "max": hi})
        meshes.append({"primitives": [{"attributes": {"POSITION": len(accessors) - 1}}]})
        return len(meshes) - 1

    def node(name, children=(), **kw):
        nodes.append({"name": name, **kw, **({"children": list(children)} if children else {})})
        return len(nodes) - 1

    body = node("body_mesh", mesh=mesh([-0.9, -0.1, -2.1], [0.9, 1.05, 2.1]))
    seat_l = node("seatL", mesh=mesh([-0.3, -0.4, -0.5], [0.3, 0.4, 0.4]), translation=[0.4, 0.46, -0.1])
    seat_r = node("seatR", mesh=mesh([-0.3, -0.4, -0.5], [0.3, 0.4, 0.4]), translation=[-0.4, 0.46, -0.1])
    wheel = node("steering_wheel", mesh=mesh([-0.18, -0.18, -0.05], [0.18, 0.18, 0.05]), translation=[steering_x, 0.6, 0.45])
    roots = [node("body", [body]), node("interior", [seat_l, seat_r, wheel])]
    if with_hubs:
        for wid, (pos, r, w) in HUBS.items():
            spin = node(f"wheel_{wid}", mesh=mesh([-w / 2, -r, -r], [w / 2, r, r]))
            caliper = node(f"caliper_{wid}", mesh=mesh([-0.05, -0.1, -0.1], [0.05, 0.1, 0.1]))
            roots.append(node(f"hub_{wid}", [spin, caliper], translation=pos))
    root = node("CAR", roots)
    gltf = {"asset": {"version": "2.0"}, "scene": 0, "scenes": [{"nodes": [root]}], "nodes": nodes,
            "meshes": meshes, "accessors": accessors}
    js = json.dumps(gltf).encode()
    js += b" " * (-len(js) % 4)
    return struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js)) + struct.pack("<II", len(js), 0x4E4F534A) + js


def make_car(folder, media="TST_Car_99", **glb_kw):
    folder.mkdir(parents=True)
    car = {
        "media_name": media, "year": 1999, "make": "Testa", "make_code": "TST", "exported": "2026-10-09",
        "hubs": {wid: {"position": pos, "radius": r, "width": w} for wid, (pos, r, w) in HUBS.items()},
        "dimensions": {"wheelbase": 2.55, "front_ride_height": 0.14, "rear_ride_height": 0.14,
                       "curb_weight_kg": 13.6, "weight_distribution_front": 0.42},
    }
    paint = {"materials_in_glb": {"Paint_Primary": {"rgb": "#ffd400", "finish": "Normal"}},
             "factory_colors": [{"sequence": 2, "rgb": "#252295", "finish": "Metallic"},
                                {"sequence": 1, "rgb": "#FFD400", "finish": "Normal"}]}
    (folder / "car.json").write_text(json.dumps(car))
    (folder / "paint.json").write_text(json.dumps(paint))
    (folder / f"{media}.glb").write_bytes(make_glb(**glb_kw))
    (folder / f"{media}_lod1.glb").write_bytes(make_glb(**glb_kw))
    return folder


def validator(name):
    return Draft202012Validator(json.loads((ROOT / "data" / "schemas" / f"{name}.schema.json").read_text()))


class ConverterTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        self.out = self.dir / "garage"

    def tearDown(self):
        self.tmp.cleanup()

    def convert(self, folder, **kw):
        return fm4_to_noss.convert(folder, self.out, log=lambda *_: None, **kw)

    def test_package_is_valid(self):
        path = self.convert(make_car(self.dir / "car"))
        with zipfile.ZipFile(path) as zf:
            names = zf.namelist()
            manifest_bytes = zf.read("manifest.json")
            manifest = json.loads(manifest_bytes)
            fit = json.loads(zf.read("fit.json"))
            paint = json.loads(zf.read("paint.json"))
            for file, digest in manifest["files"].items():
                self.assertEqual(digest, "sha256:" + hashlib.sha256(zf.read(file)).hexdigest(), file)
        self.assertEqual(names[0], "manifest.json")
        self.assertEqual(sorted(names[1:]), sorted(manifest["files"]))
        self.assertIn("model/lod1.glb", names)
        for name, data in (("package", manifest), ("fit", fit), ("paint", paint)):
            errors = [e.message for e in validator(name).iter_errors(data)]
            self.assertEqual(errors, [], name)
        self.assertEqual(manifest["license"], "personal-use-only")
        self.assertEqual(manifest["name"], "1999 Testa Car")
        self.assertEqual(manifest_bytes, fm4_to_noss.canonical_json(manifest))

    def test_fit_from_hubs(self):
        path = self.convert(make_car(self.dir / "car"))
        fit = json.loads(zipfile.ZipFile(path).read("fit.json"))
        lf = next(w for w in fit["wheels"] if w["id"] == "LF")
        self.assertEqual(lf, {"id": "LF", "axle": 1, "side": "L", "node": "hub_LF", "spin_node": "wheel_LF",
                              "fixed_nodes": ["caliper_LF"], "center": [0.8, 0.16, 1.33], "radius": 0.3, "width": 0.215})
        self.assertAlmostEqual(fit["ground_y"], ((0.16 - 0.30) * 2 + (0.17 - 0.31) * 2) / 4, places=4)
        self.assertEqual(fit["envelope"]["max"][1], 1.05)
        self.assertEqual(fit["steering_wheel"]["node"], "steering_wheel")

    def test_platform_mass_is_ignored(self):
        path = self.convert(make_car(self.dir / "car"))
        with zipfile.ZipFile(path) as zf:
            text = b"".join(zf.read(n) for n in ("fit.json", "manifest.json", "paint.json"))
        self.assertNotIn(b"13.6", text)

    def test_driver_side_from_steering_wheel(self):
        lhd = json.loads(zipfile.ZipFile(self.convert(make_car(self.dir / "l", "TST_L_99"))).read("fit.json"))
        rhd = json.loads(zipfile.ZipFile(self.convert(make_car(self.dir / "r", "TST_R_99", steering_x=-0.37))).read("fit.json"))
        self.assertGreater(lhd["eye_point"][0], 0)
        self.assertLess(rhd["eye_point"][0], 0)
        self.assertLess(lhd["eye_point"][1], 1.05 - 0.1)  # below the roof

    def test_paint_slots_and_presets(self):
        paint = json.loads(zipfile.ZipFile(self.convert(make_car(self.dir / "car"))).read("paint.json"))
        self.assertEqual(paint["slots"], {"primary": {"materials": ["Paint_Primary"], "color": "#FFD400", "finish": "solid"}})
        self.assertEqual([p["name"] for p in paint["presets"]], ["Factory 1", "Factory 2"])
        self.assertEqual(paint["presets"][1]["finish"], "metallic")

    def test_rerun_is_stable_and_changes_bump_version(self):
        folder = make_car(self.dir / "car")
        path = self.convert(folder)
        first = path.read_bytes()
        self.convert(folder)
        self.assertEqual(path.read_bytes(), first)
        paint = json.loads((folder / "paint.json").read_text())
        paint["materials_in_glb"]["Paint_Primary"]["rgb"] = "#000000"
        (folder / "paint.json").write_text(json.dumps(paint))
        self.convert(folder)
        manifest = json.loads(zipfile.ZipFile(path).read("manifest.json"))
        self.assertEqual(manifest["version"], 2)

    def test_missing_hub_fails(self):
        with self.assertRaises(fm4_to_noss.ConvertError):
            self.convert(make_car(self.dir / "car", with_hubs=False))

    def test_finds_cars_in_parent_folder(self):
        make_car(self.dir / "models" / "a", "TST_A_99")
        make_car(self.dir / "models" / "b", "TST_B_99")
        self.assertEqual(len(fm4_to_noss.find_cars(self.dir / "models")), 2)
        self.assertEqual(fm4_to_noss.main([str(self.dir / "models"), "--out", str(self.out)]), 0)
        self.assertEqual(len(list(self.out.glob("*.noss"))), 2)


if __name__ == "__main__":
    unittest.main()
