#!/usr/bin/env bash
# Runs the headless test suite. Needs a Godot 4.7 binary on PATH as `godot`,
# or set GODOT to point at one.
set -euo pipefail

GODOT="${GODOT:-godot}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# The import pass registers the class_name globals. Without it the test script
# cannot see MovementSolver and friends, and fails to parse.
"$GODOT" --headless --path "$PROJECT_DIR" --import >/dev/null
"$GODOT" --headless --path "$PROJECT_DIR" --script tests/run_tests.gd
"$GODOT" --headless --path "$PROJECT_DIR" --script tests/run_map_tests.gd
