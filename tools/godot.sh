#!/usr/bin/env bash
# Runs the pinned Godot from .tools/ (see setup_dev.sh), or $GODOT if set.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-$ROOT/.tools/godot/Godot_v4.7.2-stable_linux.x86_64}"
if [[ ! -x "$GODOT" ]]; then
	echo "Godot not found. Run tools/setup_dev.sh first." >&2
	exit 1
fi
# A fresh checkout must be imported once, or the game starts without noss_core registered.
if [[ ! -f "$ROOT/.godot/extension_list.cfg" ]]; then
	"$GODOT" --path "$ROOT" --headless --import >/dev/null 2>&1
fi
exec "$GODOT" --path "$ROOT" "$@"
