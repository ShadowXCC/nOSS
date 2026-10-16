#!/usr/bin/env bash
# Runs every test suite: native (doctest), JSON schemas, tools (unittest), GDScript (gdUnit4, headless),
# platform conformance, a short AI race check, a short kart check, a short highway check, short online checks (a race,
# a highway with traffic), the track editor's 3 km acceptance build (raced and sent online), boot
# smoke test.
# Exits non-zero if any fails. Run tools/setup_dev.sh once first.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
GODOT="tools/godot.sh"
failed=()

step() { printf '\n== %s ==\n' "$1"; }

step "Native: build noss_core"
tools/build_native.sh -Q || failed+=("native build")

step "Native: doctest"
tools/build_native.sh -Q tests || failed+=("doctest")

step "Schemas"
.venv/bin/python tests/schemas/check_schemas.py || failed+=("schemas")

step "Tools"
.venv/bin/python -m unittest discover -s tests/tools -p 'test_*.py' -q || failed+=("tools")

step "Godot: import"
$GODOT --headless --import >/dev/null 2>&1 || failed+=("godot import")

step "Godot: scripts compile"
$GODOT --headless -s res://tools/check_scripts.gd 2>&1 | tail -1 | grep -q " 0 failed" || failed+=("scripts")

step "Godot: gdUnit4"
# --remote-debug to a closed port stops Godot's interactive debugger from looping on script errors.
$GODOT --headless -s -d --remote-debug tcp://127.0.0.1:0 res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
	-a res://tests/game --ignoreHeadlessMode -rd res://reports || failed+=("gdUnit4")

step "Conformance"
tools/run_conformance.sh || failed+=("conformance")

step "Race check (12 cars, 1 lap)"
tools/race_check.sh --cars=12 --laps=1 --seed=1 --builtin --bad=stall | grep -E "^(Race|Time|PASS|FAIL)" ; [[ ${PIPESTATUS[0]} -eq 0 ]] || failed+=("race check")

step "Kart check (8 karts with items, 1 lap of the stunt fixture)"
tools/kart_check.sh --karts=8 --laps=1 --seed=1 | grep -E "^(kart_check|Race|Time|PASS|FAIL|  )" ; [[ ${PIPESTATUS[0]} -eq 0 ]] || failed+=("kart check")

step "Battle check (8 karts, last one standing, the arena fixture)"
tools/kart_check.sh --battle --karts=8 --seed=1 | grep -E "^(kart_check|Battle|Race|PASS|FAIL|  )" ; [[ ${PIPESTATUS[0]} -eq 0 ]] || failed+=("battle check")

step "Highway check (2 players, 400 traffic, 60 s)"
tools/highway_check.sh --players=2 --traffic=400 --seconds=60 | grep -E "^(Highway|Time|PASS|FAIL)" ; [[ ${PIPESTATUS[0]} -eq 0 ]] || failed+=("highway check")

step "Online check (3 bots and an AI car race a lap, 150 ms)"
.venv/bin/python tools/net_check.py --clients 3 --event race --laps 1 --ai 1 --rtt 150 --jitter 10 --loss 1 | grep -E "^(net_check|PASS|FAIL)" ; [[ ${PIPESTATUS[0]} -eq 0 ]] || failed+=("net check")

step "Online highway check (3 bots, 60 traffic cars, 150 ms, one put out of step)"
.venv/bin/python tools/net_check.py --event highway --clients 3 --traffic 60 --duration 40 --rtt 150 --jitter 10 --loss 1 --desync | grep -E "^(net_check|PASS|FAIL)" ; [[ ${PIPESTATUS[0]} -eq 0 ]] || failed+=("highway net check")

step "Kart net check (3 bots, 1 AI, 1 lap of Gearworks, 150 ms, 1% loss)"
.venv/bin/python tools/net_check.py --event kart --clients 3 --ai 1 --laps 1 --rtt 150 --jitter 10 --loss 1 | grep -E "^(net_check|server items|PASS|FAIL)" ; [[ ${PIPESTATUS[0]} -eq 0 ]] || failed+=("kart net check")

step "Battle net check (3 bots, 1 AI, the Crate Yard, 150 ms)"
.venv/bin/python tools/net_check.py --event battle --clients 3 --ai 1 --rtt 150 --jitter 10 --loss 1 | grep -E "^(net_check|server items|PASS|FAIL)" ; [[ ${PIPESTATUS[0]} -eq 0 ]] || failed+=("battle net check")

step "Track check (3 km track: built in the editor, raced, sent online)"
tools/track_check.sh | grep -E "^(track_check|Race|Time|net_check|bot00 got|fresh|PASS|FAIL)" ; [[ ${PIPESTATUS[0]} -eq 0 ]] || failed+=("track check")

step "Godot: boot"
boot_log="$($GODOT --headless --quit-after 30 2>&1)"
echo "$boot_log" | grep -E "^nOSS .* \(core " || true
if ! echo "$boot_log" | grep -qE "^nOSS [0-9.]+ \(core [0-9.]+\)$" || echo "$boot_log" | grep -qE "ERROR|SCRIPT ERROR"; then
	echo "$boot_log"
	failed+=("boot")
fi

echo
if ((${#failed[@]})); then
	echo "FAILED: ${failed[*]}"
	exit 1
fi
echo "All tests passed."
