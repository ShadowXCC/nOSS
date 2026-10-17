#!/usr/bin/env python3
"""Checks data/schemas/*.schema.json.

Every schema must be a valid JSON Schema. For each fixtures/<name>/ folder,
valid_*.json must pass <name>.schema.json and invalid_*.json must fail it.
Every official platform in data/platforms/ must pass the platform schema, every mode in
data/modes/ the mode schema, every preset in data/input_presets/ the input preset schema, and
data/server.example.json the server schema, every tire sound in data/tire_sounds/ the tire
profile schema, every cup in data/cups/ the cup schema, every endless biome in data/endless/biomes/ the endless biome schema, and every built-in track in content/tracks/ the track and track package schemas.
"""

import json
import sys
from pathlib import Path

from jsonschema import Draft202012Validator

ROOT = Path(__file__).resolve().parents[2]
SCHEMAS = ROOT / "data" / "schemas"
FIXTURES = Path(__file__).resolve().parent / "fixtures"


def main() -> int:
    failures = []
    checked = 0

    for schema_path in sorted(SCHEMAS.glob("*.schema.json")):
        schema = json.loads(schema_path.read_text())
        Draft202012Validator.check_schema(schema)
        validator = Draft202012Validator(schema)
        name = schema_path.name.removesuffix(".schema.json")

        fixtures = sorted((FIXTURES / name).glob("*.json"))
        if not any(f.name.startswith("valid_") for f in fixtures):
            failures.append(f"{name}: no valid_* fixture")

        for fixture in fixtures:
            errors = list(validator.iter_errors(json.loads(fixture.read_text())))
            checked += 1
            if fixture.name.startswith("valid_") and errors:
                failures.append(f"{name}/{fixture.name}: rejected: {errors[0].message}")
            elif fixture.name.startswith("invalid_") and not errors:
                failures.append(f"{name}/{fixture.name}: accepted")

    platform_validator = Draft202012Validator(json.loads((SCHEMAS / "platform.schema.json").read_text()))
    for path in sorted((ROOT / "data" / "platforms").glob("*/*.platform.json")):
        errors = list(platform_validator.iter_errors(json.loads(path.read_text())))
        checked += 1
        if errors:
            failures.append(f"{path.relative_to(ROOT)}: rejected: {errors[0].message}")

    for schema_name, pattern in [("mode", "modes/*.mode.json"), ("input_preset", "input_presets/*.json"), ("server", "server.example.json"),
                                 ("tire_profile", "tire_sounds/*.json"), ("traffic_types", "traffic/types.json"),
                                 ("item_odds", "items/odds.json"), ("cup", "cups/*.cup.json"),
                                 ("endless_biome", "endless/biomes/*.json")]:
        validator = Draft202012Validator(json.loads((SCHEMAS / f"{schema_name}.schema.json").read_text()))
        for path in sorted((ROOT / "data").glob(pattern)):
            errors = list(validator.iter_errors(json.loads(path.read_text())))
            checked += 1
            if errors:
                failures.append(f"{path.relative_to(ROOT)}: rejected: {errors[0].message}")

    # Built-in tracks: their track.json and manifest.
    for schema_name, pattern in [("track", "*/track.json"), ("track_package", "*/manifest.json")]:
        validator = Draft202012Validator(json.loads((SCHEMAS / f"{schema_name}.schema.json").read_text()))
        for path in sorted((ROOT / "content" / "tracks").glob(pattern)):
            errors = list(validator.iter_errors(json.loads(path.read_text())))
            checked += 1
            if errors:
                failures.append(f"{path.relative_to(ROOT)}: rejected: {errors[0].message}")

    for failure in failures:
        print("FAIL", failure)
    print(f"schemas: {checked} files, {len(failures)} failures")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
