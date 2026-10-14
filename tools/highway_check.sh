#!/usr/bin/env bash
# Highway check (M7): a highway session headless, faster than real time. Options go to
# tests/highway/highway_check.gd, e.g. --scenario=loop --laps=3 or --players=4 --traffic=400.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
tools/godot.sh --headless --fixed-fps 120 res://tests/highway/highway_check.tscn -- "$@" 2>&1 \
	| grep -vE "^Godot Engine|^Gamepad|^Wheel support|^$| loaded .* in [0-9]+ ms"
exit "${PIPESTATUS[0]}"
