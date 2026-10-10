#!/usr/bin/env bash
# Builds noss_core. Extra args go to SCons, e.g. target=template_release or tests.
# platform=windows cross-compiles with the LLVM MinGW from tools/setup_export.sh.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
extra=()
if [[ " $* " == *" platform=windows "* ]]; then
	extra=(use_mingw=yes use_llvm=yes "mingw_prefix=$ROOT/.tools/llvm-mingw")
fi
exec "$ROOT/.venv/bin/scons" -C "$ROOT/native" -j"$(nproc)" "${extra[@]}" "$@"
