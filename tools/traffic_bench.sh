#!/usr/bin/env bash
# Traffic bench (M7, D120): physics cost per car per 120 Hz tick for full, lite and kinematic
# cars on flat ground. Options go to tests/highway/traffic_bench.gd, e.g. --cars=24.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
tools/godot.sh --headless --fixed-fps 120 res://tests/highway/traffic_bench.tscn -- "$@" 2>&1 \
	| grep -vE "^Godot Engine|^Gamepad|^Wheel support|^$| loaded .* in [0-9]+ ms"
exit "${PIPESTATUS[0]}"
