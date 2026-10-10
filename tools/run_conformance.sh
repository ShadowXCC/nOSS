#!/usr/bin/env bash
# Platform conformance (docs/PLATFORMS.md §5): every official platform, every maneuver, across
# its geometry grid, within 2% of its reference geometry. Writes tests/conformance/out/
# (conformance.csv, summary.json, report.html). Options: --quick, --platform=<id>, --threads=<n>.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
tools/godot.sh --headless -s res://tests/conformance/run_conformance.gd -- "$@" 2>&1 | grep -vE "^Godot Engine|^$"
status=${PIPESTATUS[0]}
.venv/bin/python tools/conformance_report.py tests/conformance/out || status=1
exit "$status"
