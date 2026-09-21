#!/usr/bin/env bash
#
# Reports on what the extraction actually produced. Run this and send the
# output when an import is not behaving: it covers both halves of the
# question, whether the files are there and what is inside them.
#
#   scripts/inspect_assets.sh
#
# The output is also written to inspect-output.txt in the project root, so it
# survives the terminal closing. On Windows, scripts/inspect_assets.bat runs
# this and waits for a keypress.
#
# The Godot half is skipped if no Godot binary is found. Point at one with
# GODOT=/path/to/godot if it is not on PATH or the desktop.

set -uo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSETS_DIR="$PROJECT_DIR/assets"
<<<<<<< HEAD

echo "=== assets directory ==="
if [[ ! -d "$ASSETS_DIR" ]]; then
	echo "$ASSETS_DIR does not exist."
	echo "The extraction has not run, or it wrote somewhere else."
	echo "Run: scripts/extract_assets.sh map"
	exit 1
fi

file_count="$(find "$ASSETS_DIR" -type f | wc -l | tr -d ' ')"
echo "files: $file_count"
echo "size:  $(du -sh "$ASSETS_DIR" 2>/dev/null | cut -f1)"
echo

echo "top-level layout:"
find "$ASSETS_DIR" -maxdepth 5 -type d | sed "s|$PROJECT_DIR/||" | head -30
echo

echo "glTF files found:"
find "$ASSETS_DIR" -type f \( -name '*.gltf' -o -name '*.glb' \) \
	| sed "s|$PROJECT_DIR/||" | head -20
echo

echo "largest files:"
find "$ASSETS_DIR" -type f -exec du -h {} + 2>/dev/null \
	| sort -rh | head -10 | sed "s|$PROJECT_DIR/||"
echo

# --- The import inventory --------------------------------------------------
=======
OUTPUT_FILE="$PROJECT_DIR/inspect-output.txt"
>>>>>>> 938b15b60f67e2da63e5be36467227b8a4e1c8c3

source "$PROJECT_DIR/scripts/common.sh"

<<<<<<< HEAD
echo "=== import inventory ==="
GODOT_BIN="$(find_godot)"
if [[ -z "$GODOT_BIN" ]]; then
	echo "Skipped: no Godot binary found."
	echo "Either run it with GODOT=/path/to/godot, or just open"
	echo "maps/de_dust2/de_dust2.tscn in the editor and copy the Output panel."
	exit 0
fi

import_assets "$GODOT_BIN" "$PROJECT_DIR" || exit 1
echo
"$GODOT_BIN" --headless --path "$PROJECT_DIR" --script scripts/inspect_map.gd
=======
report_assets() {
	echo "=== assets directory ==="
	if [[ ! -d "$ASSETS_DIR" ]]; then
		echo "$ASSETS_DIR does not exist."
		echo "The extraction has not run, or it wrote somewhere else."
		echo "Run: scripts/extract_assets.sh map"
		return 1
	fi

	echo "files: $(find "$ASSETS_DIR" -type f | wc -l | tr -d ' ')"
	echo "size:  $(du -sh "$ASSETS_DIR" 2>/dev/null | cut -f1)"
	echo
	echo "top-level layout:"
	find "$ASSETS_DIR" -maxdepth 3 -type d | sed "s|$PROJECT_DIR/||" | head -30
	echo
	echo "glTF files found:"
	find "$ASSETS_DIR" -type f \( -name '*.gltf' -o -name '*.glb' \) \
		| sed "s|$PROJECT_DIR/||" | head -20
	echo
	echo "largest files:"
	find "$ASSETS_DIR" -type f -exec du -h {} + 2>/dev/null \
		| sort -rh | head -10 | sed "s|$PROJECT_DIR/||"
	echo
	return 0
}

report_import() {
	echo "=== import inventory ==="
	local godot_bin
	godot_bin="$(find_godot)"
	if [[ -z "$godot_bin" ]]; then
		echo "Skipped: no Godot binary found."
		echo "Either run this as GODOT=/path/to/godot scripts/inspect_assets.sh,"
		echo "or open maps/de_dust2/de_dust2.tscn and press play, which writes"
		echo "the same inventory to map-report.txt."
		return 0
	fi
	"$godot_bin" --headless --path "$PROJECT_DIR" --import >/dev/null 2>&1
	"$godot_bin" --headless --path "$PROJECT_DIR" --script scripts/inspect_map.gd
}

# The whole report goes through tee so it lands in a file as well as on
# screen. A double-clicked terminal closes the instant the script ends, and the
# point of this script is to produce something readable afterwards.
main() {
	if report_assets; then
		report_import
	fi
	echo
	echo "Output saved to inspect-output.txt"
}

main 2>&1 | tee "$OUTPUT_FILE"
>>>>>>> 938b15b60f67e2da63e5be36467227b8a4e1c8c3
