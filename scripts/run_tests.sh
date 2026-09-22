#!/usr/bin/env bash
# Runs the headless test suite. Needs a Godot 4.7 binary: on PATH as `godot`,
# left on the desktop, or wherever GODOT points.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$PROJECT_DIR/scripts/common.sh"

GODOT="$(find_godot)"
if [[ -z "$GODOT" ]]; then
	echo "No Godot binary found. Run this with GODOT=/path/to/godot." >&2
	exit 1
fi

# The import pass registers the class_name globals. Without it the test script
# cannot see MovementSolver and friends, and fails to parse.
if [[ -d "$PROJECT_DIR/assets" ]]; then
	# Extracted content has to be imported with its texture settings in place,
	# here as anywhere else.
	import_assets "$GODOT" "$PROJECT_DIR"
else
	"$GODOT" --headless --path "$PROJECT_DIR" --import >/dev/null
fi
"$GODOT" --headless --path "$PROJECT_DIR" --script tests/run_tests.gd
"$GODOT" --headless --path "$PROJECT_DIR" --script tests/run_map_tests.gd
# Skips itself where dust2 has not been extracted.
"$GODOT" --headless --path "$PROJECT_DIR" --script tests/run_dust2_checks.gd
"$GODOT" --headless --path "$PROJECT_DIR" --script tests/run_model_checks.gd
"$GODOT" --headless --path "$PROJECT_DIR" --script tests/run_weapon_tests.gd
"$GODOT" --headless --path "$PROJECT_DIR" --script tests/run_range_checks.gd
