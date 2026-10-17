#!/usr/bin/env bash
# Endless road determinism across builds (D152, M9: "a seed reproduces the same road on two
# machines"): the exported Linux build and the exported Windows build (under Wine, in a throwaway
# prefix) each make 200 km of road for a few seeds (--endless-selftest) and print checksums of the
# road and of the ground along it; they must match.
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
a="$("$linux" --headless -- --endless-selftest 2>&1 | grep ENDLESS_SELFTEST | grep -v " ms$")"
b="$(WINEPREFIX="$prefix" WINEDLLOVERRIDES="winemenubuilder.exe=d" wine "$windows" --headless -- --endless-selftest 2>/dev/null | tr -d '\r' | grep ENDLESS_SELFTEST | grep -v " ms$")"
echo "linux:"
echo "$a"
echo "windows:"
echo "$b"
if [[ -n "$a" && "$a" == "$b" ]]; then
	echo "PASS"
	exit 0
fi
echo "FAIL"
exit 1
