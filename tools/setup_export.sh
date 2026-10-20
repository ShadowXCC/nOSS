#!/usr/bin/env bash
# Sets up exporting (Linux and Windows) and cross-building noss_core for Windows.
# Everything is pinned, checksum-verified and project-local. Remove the folders to undo:
#   .tools/llvm-mingw/                                        Windows cross compiler (LLVM MinGW)
#   .tools/godot/editor_data/export_templates/<version>/      Godot export templates (Linux, Windows)
#   native/bin/SDL3.dll                                       SDL3 for Windows builds (wheels, FFB)
#   native/bin/*discord_partner_sdk*                          Discord Social SDK (Rich Presence), if you have it
set -euo pipefail

GODOT_VERSION="4.7.2-stable"
TEMPLATES_SHA512="ca4d71c4d7b81dfc15d1a98baa07534aa95b03fdda78a0075b06672e1648d2e5f40980c9adc28d23e1b92e732ee7bf3461997aa804af74ec2fcd7a93ccb84079"
LLVM_MINGW_TAG="20261006"
LLVM_MINGW="llvm-mingw-$LLVM_MINGW_TAG-ucrt-ubuntu-22.04-x86_64"
LLVM_MINGW_SHA256="5f9c6ed95b2d4bdb2869a488c5fd5857fbdabcf288a0aa3eb1da43f6a08d8ab4"
SDL_VERSION="3.4.18"
SDL_SHA256="75c2c0fc74e7d1206aaedc22893a35887332f4f85f5c8b74fddc10d177985f2c"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS="$ROOT/.tools"
DL="$TOOLS/downloads"
mkdir -p "$DL"

fetch() { # url file
	if [[ ! -f "$DL/$2" ]]; then
		echo "Downloading $2"
		curl -fL --progress-bar -o "$DL/$2.part" "$1"
		mv "$DL/$2.part" "$DL/$2"
	fi
}

# LLVM MinGW: cross-compiles noss_core.dll.
if [[ ! -x "$TOOLS/llvm-mingw/bin/x86_64-w64-mingw32-clang++" ]]; then
	fetch "https://github.com/mstorsjo/llvm-mingw/releases/download/$LLVM_MINGW_TAG/$LLVM_MINGW.tar.xz" "$LLVM_MINGW.tar.xz"
	LLVM_MINGW_FILE="$LLVM_MINGW.tar.xz"
	echo "$LLVM_MINGW_SHA256  $DL/$LLVM_MINGW_FILE" | sha256sum -c -
	rm -rf "$TOOLS/llvm-mingw" "$TOOLS/$LLVM_MINGW"
	tar -xJf "$DL/$LLVM_MINGW_FILE" -C "$TOOLS"
	mv "$TOOLS/$LLVM_MINGW" "$TOOLS/llvm-mingw"
	rm "$DL/$LLVM_MINGW_FILE"
fi

# Export templates: only the Linux and Windows ones are kept.
TEMPLATE_DIR="$TOOLS/godot/editor_data/export_templates/${GODOT_VERSION/-/.}"
if [[ ! -f "$TEMPLATE_DIR/windows_release_x86_64.exe" ]]; then
	TPZ="Godot_v${GODOT_VERSION}_export_templates.tpz"
	fetch "https://github.com/godotengine/godot/releases/download/$GODOT_VERSION/$TPZ" "$TPZ"
	echo "$TEMPLATES_SHA512  $DL/$TPZ" | sha512sum -c -
	mkdir -p "$TEMPLATE_DIR"
	unzip -q -o -j "$DL/$TPZ" "templates/version.txt" "templates/linux_*x86_64" "templates/windows_*x86_64*" -d "$TEMPLATE_DIR"
	rm "$DL/$TPZ"
fi

# SDL3 for Windows (official build); exported next to the game by native/noss_core.gdextension.
if [[ ! -f "$ROOT/native/bin/SDL3.dll" ]]; then
	ZIP="SDL3-$SDL_VERSION-win32-x64.zip"
	fetch "https://github.com/libsdl-org/SDL/releases/download/release-$SDL_VERSION/$ZIP" "$ZIP"
	echo "$SDL_SHA256  $DL/$ZIP" | sha256sum -c -
	mkdir -p "$ROOT/native/bin"
	unzip -q -o -j "$DL/$ZIP" "SDL3.dll" -d "$ROOT/native/bin"
	rm "$DL/$ZIP"
fi

# Discord Social SDK for Rich Presence (docs/DECISIONS.md D186). Copied, not downloaded: it only
# comes from the authenticated Developer Portal, so there is no URL to pin a checksum against.
# Optional on purpose -- without it the game builds and runs with presence off.
DISCORD_SDK_DIR="${DISCORD_SDK_DIR:-$TOOLS/discord_social_sdk}"
if [[ -d "$DISCORD_SDK_DIR" ]]; then
	mkdir -p "$ROOT/native/bin"
	copied=()
	for pair in "lib/release/libdiscord_partner_sdk.so" "bin/release/discord_partner_sdk.dll" \
			"lib/release/libdiscord_partner_sdk.dylib"; do
		if [[ -f "$DISCORD_SDK_DIR/$pair" ]]; then
			cp -f "$DISCORD_SDK_DIR/$pair" "$ROOT/native/bin/"
			copied+=("$(basename "$pair")")
		fi
	done
	if [[ ${#copied[@]} -gt 0 ]]; then
		echo "Discord SDK: ${copied[*]}"
	else
		echo "Discord SDK: nothing to copy from $DISCORD_SDK_DIR (wrong layout?)" >&2
	fi
else
	cat >&2 <<-MSG
		Discord SDK not found, skipping (Rich Presence will be off).
		  To enable it: download the C++ Social SDK from your app's Downloads page at
		  https://discord.com/developers/applications -> Discord Social SDK -> Downloads,
		  unzip it so that $TOOLS/discord_social_sdk/{include,lib,bin} exists
		  (or point DISCORD_SDK_DIR at it), then run this script again.
	MSG
fi

rmdir "$DL" 2>/dev/null || true
echo "Done. Build Windows: tools/build_native.sh platform=windows target=template_release   Export: tools/export.sh"
