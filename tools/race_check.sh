#!/usr/bin/env bash
# Race soak check (AI-01): a full AI grid races headless; fails on a pile-up, a stuck car or a car
# that doesn't finish. Options go to tests/race/race_check.gd, e.g. --laps=1 --seed=3 --bad=spin.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
tools/godot.sh --headless --fixed-fps 120 res://tests/race/race_check.tscn -- "$@" 2>&1 \
	| grep -vE "^Godot Engine|^Gamepad|^Wheel support|^$| loaded .* in [0-9]+ ms"
exit "${PIPESTATUS[0]}"
