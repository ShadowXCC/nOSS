#!/usr/bin/env bash
# Builds release noss_core for Linux and Windows and exports the game to export/<platform>/;
# "server" exports the dedicated server (Linux, headless) to export/server/noss_server.x86_64.
# Run tools/setup_export.sh once first. Only original content ships (Requirements.md §6):
# packages in the player's garage are never part of an export.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
targets=("${@:-linux windows}")
for t in ${targets[@]}; do
	case "$t" in
		linux) preset="Linux" ;;
		windows) preset="Windows" ;;
		server) preset="Linux Server" ;;
		*) echo "Unknown target: $t" >&2; exit 1 ;;
	esac
	echo "== $preset =="
	tools/build_native.sh -Q platform="$([[ $t == server ]] && echo linux || echo "$t")" target=template_release
	out="$(grep -A12 "name=\"$preset\"" export_presets.cfg | sed -n 's/^export_path="\(.*\)"/\1/p')"
	mkdir -p "$(dirname "$out")"
	tools/godot.sh --headless --export-release "$preset" "$out"
	ls -la "$(dirname "$out")"
done
