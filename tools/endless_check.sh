#!/usr/bin/env bash
# Endless check (M9 acceptance 1: "a 2-hour drive with no precision artifacts and stable memory"):
# an autodriven endless drive headless at a fixed 120 Hz, faster than real time. Options go to
# tests/endless/endless_check.gd, e.g. --minutes=120 --traffic=normal, or --no-rebase (the
# negative control: without the floating origin the precision check must fail on a long drive).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
tools/godot.sh --headless --fixed-fps 120 res://tests/endless/endless_check.tscn -- "$@" 2>&1 \
	| grep -vE "^Godot Engine|^Gamepad|^Wheel support|^$| loaded .* in [0-9]+ ms"
exit "${PIPESTATUS[0]}"
