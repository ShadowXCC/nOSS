#!/usr/bin/env bash
# Drag soak check (D168): a field of AI cars runs the ladder headless; fails on no winner, a pass
# nobody won, a stuck car, reactions a tree would not allow, bots that cannot hold their lane, a
# field that never shifts in the window, or a car that ends up in the sand. Options go to
# tests/drag/drag_check.gd, e.g. --cars=8 --class=pro --length=805.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
tools/godot.sh --headless --fixed-fps 120 res://tests/drag/drag_check.tscn -- "$@" 2>&1 \
	| grep -vE "^Godot Engine|^Gamepad|^Wheel support|^$| loaded .* in [0-9]+ ms"
exit "${PIPESTATUS[0]}"
