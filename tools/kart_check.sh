#!/usr/bin/env bash
# Kart soak check (M8): a field of AI karts races with items headless; fails on a kart not
# classified, a stuck kart, a pile-up, too few items or drift boosts, loops not taken, too many
# tows or items left out. Options go to tests/kart/kart_check.gd, e.g. --karts=8 --laps=2 --seed=3.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
tools/godot.sh --headless --fixed-fps 120 res://tests/kart/kart_check.tscn -- "$@" 2>&1 \
	| grep -vE "^Godot Engine|^Gamepad|^Wheel support|^$| loaded .* in [0-9]+ ms"
exit "${PIPESTATUS[0]}"
