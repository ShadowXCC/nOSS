#!/usr/bin/env bash
# Traffic determinism across builds (D108, D109): the exported Linux build and the exported Windows
# build (under Wine, in a throwaway prefix) each step a built-in highway's traffic for 1000 s
# (--traffic-selftest) and print the lane graph's hash and the sim's checksum; they must match.
# Exports first unless --no-export. Needs tools/setup_export.sh and Wine.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
if [[ " $* " != *" --no-export "* ]]; then
	tools/export.sh linux windows >/dev/null || { echo "FAIL: export"; exit 1; }
fi
linux="$(ls export/linux/*.x86_64 | head -1)"
windows="$(ls export/windows/*.exe | head -1)"
prefix="$(mktemp -d)"
trap 'rm -rf "$prefix"' EXIT
a="$("$linux" --headless -- --traffic-selftest 2>&1 | grep TRAFFIC_SELFTEST)"
b="$(WINEPREFIX="$prefix" WINEDLLOVERRIDES="winemenubuilder.exe=d" wine "$windows" --headless -- --traffic-selftest 2>/dev/null | tr -d '\r' | grep TRAFFIC_SELFTEST)"
echo "linux:   $a"
echo "windows: $b"
strip() { echo "$1" | sed -E 's/ [0-9.]+ us\/tick//'; }
if [[ -n "$a" && "$(strip "$a")" == "$(strip "$b")" ]]; then
	echo "PASS"
	exit 0
fi
echo "FAIL"
exit 1
