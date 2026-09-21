#!/usr/bin/env bash
#
# Extracts CS2 content into assets/ as glTF.
#
# This has to run on a machine with CS2 installed, because it reads the game's
# own VPK archives. Nothing it produces is committed: assets/ is gitignored,
# and it should stay that way. Valve's models, textures, sounds and map
# geometry cannot be redistributed.
#
# Usage:
#   scripts/extract_assets.sh list-map        # what is inside the dust2 VPK
#   scripts/extract_assets.sh list-weapons    # find the AK and M4A1-S models
#   scripts/extract_assets.sh map             # extract dust2 to glTF
#   scripts/extract_assets.sh weapons         # extract the two weapons
#   scripts/extract_assets.sh all             # map + weapons
#
# Requires Source2Viewer-CLI: https://github.com/ValveResourceFormat/ValveResourceFormat
# Point at it with S2V=/path/to/Source2Viewer-CLI if it is not on PATH.
# Point at the game with CS2_PATH=/path/to/Counter-Strike Global Offensive
# if it is not in one of the usual places.

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$PROJECT_DIR/assets"

# --- Locate Source2Viewer-CLI ---------------------------------------------

find_s2v() {
	if [[ -n "${S2V:-}" ]]; then
		echo "$S2V"
		return
	fi
	for candidate in Source2Viewer-CLI Source2Viewer-CLI.exe; do
		if command -v "$candidate" >/dev/null 2>&1; then
			command -v "$candidate"
			return
		fi
	done
	cat >&2 <<-MSG
	Could not find Source2Viewer-CLI.

	Download it from:
	  https://github.com/ValveResourceFormat/ValveResourceFormat/releases

	Then either put it on PATH, or run this script with:
	  S2V=/path/to/Source2Viewer-CLI scripts/extract_assets.sh $*
	MSG
	exit 1
}

# --- Locate the CS2 install -----------------------------------------------

find_cs2() {
	if [[ -n "${CS2_PATH:-}" ]]; then
		echo "$CS2_PATH"
		return
	fi
	local candidates=(
		"$HOME/.steam/steam/steamapps/common/Counter-Strike Global Offensive"
		"$HOME/.local/share/Steam/steamapps/common/Counter-Strike Global Offensive"
		"$HOME/Library/Application Support/Steam/steamapps/common/Counter-Strike Global Offensive"
		"/c/Program Files (x86)/Steam/steamapps/common/Counter-Strike Global Offensive"
		"/mnt/c/Program Files (x86)/Steam/steamapps/common/Counter-Strike Global Offensive"
	)
	for candidate in "${candidates[@]}"; do
		if [[ -d "$candidate/game/csgo" ]]; then
			echo "$candidate"
			return
		fi
	done
	cat >&2 <<-MSG
	Could not find the CS2 install.

	Looked in:
	$(printf '  %s\n' "${candidates[@]}")

	If it lives somewhere else (a second Steam library, for instance), run:
	  CS2_PATH="/path/to/Counter-Strike Global Offensive" scripts/extract_assets.sh $*
	MSG
	exit 1
}

COMMAND="${1:-}"
case "$COMMAND" in
	list-map|list-weapons|map|weapons|all) ;;
	*)
		sed -n '3,25p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
		exit 1
		;;
esac

S2V_BIN="$(find_s2v "$@")"
CS2_DIR="$(find_cs2 "$@")"
CSGO_DIR="$CS2_DIR/game/csgo"
MAP_VPK="$CSGO_DIR/maps/de_dust2.vpk"
PAK_VPK="$CSGO_DIR/pak01_dir.vpk"

echo "Source2Viewer-CLI: $S2V_BIN"
echo "CS2:               $CS2_DIR"
echo

require_file() {
	if [[ ! -f "$1" ]]; then
		echo "Expected to find $1 but it is not there." >&2
		echo "If CS2's layout has changed, 'list-map' and 'list-weapons' will show what is actually present." >&2
		exit 1
	fi
}

# --- Commands --------------------------------------------------------------

## Rather than hardcoding paths inside the VPKs, which drift between game
## updates, we list the archive and pick out what we need. If an update moves
## something, the list commands show where it went.

list_map() {
	require_file "$MAP_VPK"
	"$S2V_BIN" -i "$MAP_VPK" -l
}

list_weapons() {
	require_file "$PAK_VPK"
	"$S2V_BIN" -i "$PAK_VPK" -l \
		| grep -iE '\.vmdl_c$' \
		| grep -iE 'ak47|m4a1'
}

find_world_resource() {
	require_file "$MAP_VPK"
	local world
	world="$("$S2V_BIN" -i "$MAP_VPK" -l | grep -iE '\.vwrld_c$' | head -n 1 || true)"
	if [[ -z "$world" ]]; then
		echo "No .vwrld_c inside $MAP_VPK." >&2
		echo "Run 'scripts/extract_assets.sh list-map' to see what is in there." >&2
		exit 1
	fi
	echo "$world"
}

extract_map() {
	local world dest
	world="$(find_world_resource)"
	dest="$OUT_DIR/maps/de_dust2"
	mkdir -p "$dest"

	echo "Extracting $world"
	echo "        -> $dest"
	echo
	echo "This takes a while and produces a lot of PNGs. Expect the better part"
	echo "of a gigabyte."
	echo

	"$S2V_BIN" \
		-i "$MAP_VPK" \
		-f "$world" \
		-o "$dest" \
		-d \
		--gltf_export_format gltf \
		--gltf_export_materials \
		--gltf_textures_adapt

	echo
	echo "Done. Now open the project and run the map import:"
	echo "  the de_dust2 scene picks up whatever landed in $dest"
}

extract_weapons() {
	require_file "$PAK_VPK"
	local dest="$OUT_DIR/weapons"
	mkdir -p "$dest"

	local models
	models="$(list_weapons || true)"
	if [[ -z "$models" ]]; then
		echo "Found no AK-47 or M4A1-S models in $PAK_VPK." >&2
		echo "Run 'scripts/extract_assets.sh list-weapons' and check the filter." >&2
		exit 1
	fi

	echo "Extracting:"
	echo "$models" | sed 's/^/  /'
	echo

	# Comma-separated filter, which is what -f expects.
	local filter
	filter="$(echo "$models" | paste -sd, -)"

	"$S2V_BIN" \
		-i "$PAK_VPK" \
		-f "$filter" \
		-o "$dest" \
		-d \
		--gltf_export_format gltf \
		--gltf_export_materials \
		--gltf_export_animations \
		--gltf_textures_adapt
}

case "$COMMAND" in
	list-map) list_map ;;
	list-weapons) list_weapons ;;
	map) extract_map ;;
	weapons) extract_weapons ;;
	all) extract_map; extract_weapons ;;
esac
