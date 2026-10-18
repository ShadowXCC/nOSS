#!/usr/bin/env bash
# Sumo soak check (D162): a field of AI cars fights on the shrinking platforms headless; fails on
# no winner, a platform shrinking with nobody on it, a stuck car, a missed fall between tiers or
# two cars out on one tick. Options go to tests/sumo/sumo_check.gd, e.g. --cars=8 --tiers=3.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
tools/godot.sh --headless --fixed-fps 120 res://tests/sumo/sumo_check.tscn -- "$@" 2>&1 \
	| grep -vE "^Godot Engine|^Gamepad|^Wheel support|^$| loaded .* in [0-9]+ ms"
exit "${PIPESTATUS[0]}"
