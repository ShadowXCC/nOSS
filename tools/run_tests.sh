#!/usr/bin/env bash
# Runs every test suite: native (doctest), JSON schemas, tools (unittest), GDScript (gdUnit4, headless),
# platform conformance, a short AI race check (and one in the rain), a short kart check, two short
# sumo checks, two short drag checks, a 10-minute endless drive and a 5-minute one with traps and
# police, a short highway check, short online checks (a race, a highway with traffic, karts, an
# endless convoy, endless police, a sumo match, a drag ladder),
# the track editor's 3 km acceptance
# build (raced and sent online), boot smoke test.
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

step "Race check in the rain (6 cars, 1 lap)"
tools/race_check.sh --cars=6 --laps=1 --seed=3 --builtin --weather=rain | grep -E "^(Race|Time|PASS|FAIL)" ; [[ ${PIPESTATUS[0]} -eq 0 ]] || failed+=("rain race check")

step "Kart check (8 karts with items, 1 lap of the stunt fixture)"
tools/kart_check.sh --karts=8 --laps=1 --seed=1 | grep -E "^(kart_check|Race|Time|PASS|FAIL|  )" ; [[ ${PIPESTATUS[0]} -eq 0 ]] || failed+=("kart check")

step "Battle check (8 karts, last one standing, the arena fixture)"
tools/kart_check.sh --battle --karts=8 --seed=1 | grep -E "^(kart_check|Battle|Race|PASS|FAIL|  )" ; [[ ${PIPESTATUS[0]} -eq 0 ]] || failed+=("battle check")

step "Sumo check (6 cars, 2 platforms, the smooth shrink)"
tools/sumo_check.sh --cars=6 --tiers=2 --secs=45 --seed=1 | grep -E "^(sumo_check|Sumo|Check|Time|PASS|FAIL|  )" ; [[ ${PIPESTATUS[0]} -eq 0 ]] || failed+=("sumo check")

step "Sumo check (6 cars, 3 platforms, rings crumbling away)"
tools/sumo_check.sh --cars=6 --tiers=3 --shrink=crumble --secs=45 --seed=2 | grep -E "^(sumo_check|Sumo|Check|Time|PASS|FAIL|  )" ; [[ ${PIPESTATUS[0]} -eq 0 ]] || failed+=("sumo crumble check")

step "Drag: a ladder of AI passes"
tools/drag_check.sh --cars=6 --length=201 --skill=60-90 --seed=1 | grep -E "^(drag_check|Field|Drag|Ticks|PASS|FAIL|  )" ; [[ ${PIPESTATUS[0]} -eq 0 ]] || failed+=("drag check")

step "Drag: Top Fuel over half a mile"
tools/drag_check.sh --cars=4 --class=top_fuel --length=805 --skill=88-95 --seed=2 | grep -E "^(drag_check|Field|Drag|Ticks|PASS|FAIL|  )" ; [[ ${PIPESTATUS[0]} -eq 0 ]] || failed+=("drag top fuel check")

step "Endless check (10 minutes of driving, normal traffic)"
tools/endless_check.sh --minutes=10 --traffic=normal | grep -E "^(Endless|  |Time|PASS|FAIL)" ; [[ ${PIPESTATUS[0]} -eq 0 ]] || failed+=("endless check")

step "Endless check (5 minutes, four lanes on the left, heavy traffic, traps and police)"
tools/endless_check.sh --minutes=5 --traffic=heavy --lanes=4 --side=left --traps --police --speed-factor=1.4 | grep -E "^(Endless|  |Time|PASS|FAIL)" ; [[ ${PIPESTATUS[0]} -eq 0 ]] || failed+=("endless police check")

step "Highway check (2 players, 400 traffic, 60 s)"
tools/highway_check.sh --players=2 --traffic=400 --seconds=60 | grep -E "^(Highway|Time|PASS|FAIL)" ; [[ ${PIPESTATUS[0]} -eq 0 ]] || failed+=("highway check")

step "Online check (3 bots and an AI car race a lap, 150 ms)"
.venv/bin/python tools/net_check.py --clients 3 --event race --laps 1 --ai 1 --rtt 150 --jitter 10 --loss 1 | grep -E "^(net_check|PASS|FAIL)" ; [[ ${PIPESTATUS[0]} -eq 0 ]] || failed+=("net check")

step "Online highway check (3 bots, 60 traffic cars, 150 ms, one put out of step)"
.venv/bin/python tools/net_check.py --event highway --clients 3 --traffic 60 --duration 40 --rtt 150 --jitter 10 --loss 1 --desync | grep -E "^(net_check|PASS|FAIL)" ; [[ ${PIPESTATUS[0]} -eq 0 ]] || failed+=("highway net check")

step "Endless net check (3 bots, one joining late, 150 ms RTT)"
.venv/bin/python tools/net_check.py --event endless --clients 3 --late 40 --duration 150 --rtt 150 --jitter 10 --loss 1 | grep -E "^(net_check|server road|PASS|FAIL)" ; [[ ${PIPESTATUS[0]} -eq 0 ]] || failed+=("endless net check")

step "Endless police net check (2 bots, one speeding past the traps, 150 ms)"
.venv/bin/python tools/net_check.py --event endless --clients 2 --police --duration 150 --rtt 150 --jitter 10 --loss 1 | grep -E "^(net_check|police|PASS|FAIL)" ; [[ ${PIPESTATUS[0]} -eq 0 ]] || failed+=("endless police net check")

step "Kart net check (3 bots, 1 AI, 1 lap of Gearworks, 150 ms, 1% loss)"
.venv/bin/python tools/net_check.py --event kart --clients 3 --ai 1 --laps 1 --rtt 150 --jitter 10 --loss 1 | grep -E "^(net_check|server items|PASS|FAIL)" ; [[ ${PIPESTATUS[0]} -eq 0 ]] || failed+=("kart net check")

step "Battle net check (3 bots, 1 AI, the Crate Yard, 150 ms)"
.venv/bin/python tools/net_check.py --event battle --clients 3 --ai 1 --rtt 150 --jitter 10 --loss 1 | grep -E "^(net_check|server items|PASS|FAIL)" ; [[ ${PIPESTATUS[0]} -eq 0 ]] || failed+=("battle net check")

step "Sumo net check (3 bots, 2 AI, two platforms, 150 ms)"
.venv/bin/python tools/net_check.py --event sumo --clients 3 --ai 2 --tiers 2 --platform-secs 45 --duration 200 --rtt 150 --jitter 10 --loss 1 | grep -E "^(net_check|sumo results|server platforms|PASS|FAIL)" ; [[ ${PIPESTATUS[0]} -eq 0 ]] || failed+=("sumo net check")

step "Online: a drag ladder"
.venv/bin/python tools/net_check.py --event drag --clients 2 --ai 3 --length 201 --duration 200 --rtt 150 --jitter 10 --loss 1 | grep -E "^(net_check|drag results|  server|PASS|FAIL)" ; [[ ${PIPESTATUS[0]} -eq 0 ]] || failed+=("drag net check")

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
