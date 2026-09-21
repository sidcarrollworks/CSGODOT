#!/usr/bin/env bash
#
# Reports on what the extraction actually produced. Run this and send the
# output when an import is not behaving: it covers both halves of the
# question, whether the files are there and what is inside them.
#
#   scripts/inspect_assets.sh
#
# The Godot half is skipped if no Godot binary is found. Point at one with
# GODOT=/path/to/godot if it is not on PATH.

set -uo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSETS_DIR="$PROJECT_DIR/assets"

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

# --- The import inventory --------------------------------------------------

find_godot() {
	if [[ -n "${GODOT:-}" ]]; then
		echo "$GODOT"
		return
	fi
	for candidate in godot godot4 Godot; do
		if command -v "$candidate" >/dev/null 2>&1; then
			command -v "$candidate"
			return
		fi
	done
	echo ""
}

GODOT_BIN="$(find_godot)"
if [[ -z "$GODOT_BIN" ]]; then
	echo "=== import inventory ==="
	echo "Skipped: no Godot binary found."
	echo "Either run it with GODOT=/path/to/godot, or just open"
	echo "maps/de_dust2/de_dust2.tscn in the editor and copy the Output panel."
	exit 0
fi

echo "=== import inventory ==="
"$GODOT_BIN" --headless --path "$PROJECT_DIR" --import >/dev/null 2>&1
"$GODOT_BIN" --headless --path "$PROJECT_DIR" --script scripts/inspect_map.gd
