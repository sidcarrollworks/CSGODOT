#!/usr/bin/env bash
# Build the pinned addon plus the opt-in projectile trace on Linux/macOS.
# Requires Git, Python 3 and a C/C++ compiler. Incremental outputs are cached.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec python3 "$PROJECT_DIR/scripts/build_box3d_projectiles.py" --project "$PROJECT_DIR" "$@"
