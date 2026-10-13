#!/usr/bin/env bash
# M6 acceptance check: a ~3 km track built headless with the track editor's commands, checked,
# saved and loaded back (tests/editor/track_check.gd); then 8 AI cars race a lap on it
# (race_check) and a bot with an empty cache gets it online and races (net_check --fresh).
#   tools/track_check.sh [--out=<file.nosstrack>]
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
failed=0
out="$(tools/godot.sh --headless res://tests/editor/track_check.tscn -- "$@" 2>&1 | grep -vE "^Godot Engine|^Gamepad|^Wheel support|^$")"
echo "$out" | grep -vE "^TRACK_CHECK "
track="$(echo "$out" | sed -n 's/^TRACK_CHECK //p')"
if [[ -z "$track" ]]; then
	echo "FAIL: the track wasn't built"
	exit 1
fi
echo "-- race_check: 8 cars, 1 lap"
tools/race_check.sh --track="$track" --cars=8 --laps=1 --seed=1 --builtin | grep -E "^(Race|Time|PASS|FAIL)"
[[ ${PIPESTATUS[0]} -eq 0 ]] || failed=1
echo "-- net_check: a fresh bot gets the track and races"
.venv/bin/python tools/net_check.py --track "$track" --fresh --clients 1 --ai 3 --laps 1 | grep -E "^(net_check|bot00 got|fresh|PASS|FAIL)"
[[ ${PIPESTATUS[0]} -eq 0 ]] || failed=1
if [[ $failed -ne 0 ]]; then
	echo "FAIL"
	exit 1
fi
echo "PASS"
