#!/usr/bin/env bash
# Platform conformance (docs/PLATFORMS.md §5): every official platform, every maneuver, across
# its geometry grid, within 2% of its reference geometry. Writes tests/conformance/out/
# (conformance.csv, summary.json, report.html), then checks the harness against Jolt.
# Options: --quick, --platform=<id>, --threads=<n>.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
tools/godot.sh --headless -s res://tests/conformance/run_conformance.gd -- "$@" 2>&1 | grep -vE "^Godot Engine|^$"
status=${PIPESTATUS[0]}
.venv/bin/python tools/conformance_report.py tests/conformance/out || status=1
# The harness against the game's own physics (Jolt).
tools/godot.sh --headless --fixed-fps 120 -s res://tests/conformance/engine_check.gd 2>&1 | grep -E "PASS|FAIL"
[[ ${PIPESTATUS[0]} -eq 0 ]] || status=1
exit "$status"
