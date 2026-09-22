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
# With a trailing slash: assets/ may be a junction to another drive, which
# find and du treat as a link rather than a directory unless told to look
# through it, and the slash tells them.
ASSETS_DIR="$PROJECT_DIR/assets/"
OUTPUT_FILE="$PROJECT_DIR/inspect-output.txt"

source "$PROJECT_DIR/scripts/common.sh"

report_assets() {
	echo "=== assets directory ==="
	if [[ ! -d "$ASSETS_DIR" ]]; then
		echo "${ASSETS_DIR%/} does not exist."
		echo "The extraction has not run, or it wrote somewhere else."
		echo "Run: scripts/extract_assets.sh map"
		return 1
	fi

	echo "files: $(find "$ASSETS_DIR" -type f | wc -l | tr -d ' ')"
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
}

report_import() {
	echo "=== import inventory ==="
	local godot
	godot="$(find_godot)"
	if [[ -z "$godot" ]]; then
		echo "Skipped: no Godot binary found."
		echo "Either run it with GODOT=/path/to/godot, or just open"
		echo "maps/de_dust2/de_dust2.tscn in the editor and copy the Output panel."
		return 0
	fi

	import_assets "$godot" "$PROJECT_DIR" || return 1
	echo
	"$godot" --headless --path "$PROJECT_DIR" --script scripts/inspect_map.gd
}

main() {
	report_assets || return 1
	report_import
}

# A function piped through tee, rather than exec with a process substitution,
# which can exit before tee has flushed and leave the terminal blank.
main 2>&1 | tee "$OUTPUT_FILE"
exit "${PIPESTATUS[0]}"
