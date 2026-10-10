#!/usr/bin/env bash
# Sets up a project-local dev environment. Nothing is installed system-wide.
#   .tools/godot/  pinned Godot editor (self-contained: editor data stays here)
#   .venv/         Python venv with SCons and jsonschema
# Remove both folders to undo.
set -euo pipefail

GODOT_VERSION="4.7.2-stable"
GODOT_ZIP="Godot_v${GODOT_VERSION}_linux.x86_64.zip"
GODOT_SHA512="9aa00f7a605200940bce3027a567b782f49bd8e940dd06ae9e987bd65aee1b1467edd56ed84fcdcbdd44354bf613bdbb4e5d2913e925850368e150c59ed54c65"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT_DIR="$ROOT/.tools/godot"
GODOT_BIN="$GODOT_DIR/Godot_v${GODOT_VERSION}_linux.x86_64"

if [[ ! -x "$GODOT_BIN" ]]; then
	echo "Downloading Godot $GODOT_VERSION"
	mkdir -p "$GODOT_DIR"
	curl -fL --progress-bar -o "$GODOT_DIR/$GODOT_ZIP" \
		"https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/${GODOT_ZIP}"
	echo "$GODOT_SHA512  $GODOT_DIR/$GODOT_ZIP" | sha512sum -c -
	unzip -q -o "$GODOT_DIR/$GODOT_ZIP" -d "$GODOT_DIR"
	rm "$GODOT_DIR/$GODOT_ZIP"
	# Self-contained mode: editor settings and cache live next to the binary, not in ~/.config.
	touch "$GODOT_DIR/._sc_"
fi

if [[ ! -x "$ROOT/.venv/bin/scons" ]]; then
	echo "Creating .venv"
	python3 -m venv "$ROOT/.venv"
	"$ROOT/.venv/bin/pip" install --no-cache-dir --quiet -r "$ROOT/tools/requirements-dev.txt"
fi

git -C "$ROOT" submodule update --init --recursive

echo "Done. Godot: tools/godot.sh   Build: tools/build_native.sh   Tests: tools/run_tests.sh"
