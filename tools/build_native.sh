#!/usr/bin/env bash
# Builds noss_core. Extra args go to SCons, e.g. target=template_release or tests.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec "$ROOT/.venv/bin/scons" -C "$ROOT/native" -j"$(nproc)" "$@"
