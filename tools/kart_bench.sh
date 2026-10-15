#!/usr/bin/env bash
# Kart bench (M8, K0): the kart layer in Jolt. Options go to tests/kart/kart_bench.gd, e.g.
# --scenario=loop|wall|bounce --speeds=10,15,20 --radius=9.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
tools/godot.sh --headless --fixed-fps 120 res://tests/kart/kart_bench.tscn -- "$@" 2>&1 \
	| grep -vE "^Godot Engine|^Gamepad|^Wheel support|^$| loaded .* in [0-9]+ ms"
exit "${PIPESTATUS[0]}"
