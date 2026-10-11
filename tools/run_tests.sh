#!/usr/bin/env bash
# Runs every test suite: native (doctest), JSON schemas, tools (unittest), GDScript (gdUnit4, headless),
# platform conformance, a short AI race check, boot smoke test.
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
