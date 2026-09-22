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
#   scripts/extract_assets.sh map             # dust2: world, collision hull, entities
#   scripts/extract_assets.sh physics         # just the collision hull (seconds)
#   scripts/extract_assets.sh entities        # just the entity lump (seconds)
#   scripts/extract_assets.sh layers          # just the blend materials' second layers
#   scripts/extract_assets.sh weapons         # extract the two weapons
#   scripts/extract_assets.sh all             # map + weapons
#
# Requires Source2Viewer-CLI: https://github.com/ValveResourceFormat/ValveResourceFormat
# Point at it with S2V=/path/to/Source2Viewer-CLI if it is not on PATH.
# Point at the game with CS2_PATH=/path/to/Counter-Strike Global Offensive
# if Steam's library list does not lead to it.
# With a Godot binary around (GODOT=/path/to/godot if it is not found), the
# extraction finishes by importing what it produced.

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$PROJECT_DIR/assets"

source "$PROJECT_DIR/scripts/common.sh"

# --- Locate Source2Viewer-CLI ---------------------------------------------

find_s2v() {
	if [[ -n "${S2V:-}" ]]; then
		# Checked here because a wrong path otherwise surfaces much later, as a
		# misleading complaint about the VPK's contents.
		if ! command -v "$S2V" >/dev/null 2>&1 && [[ ! -x "$S2V" ]]; then
			echo "S2V=$S2V is not an executable file." >&2
			exit 1
		fi
		echo "$S2V"
		return
	fi
	for candidate in Source2Viewer-CLI Source2Viewer-CLI.exe; do
		if command -v "$candidate" >/dev/null 2>&1; then
			command -v "$candidate"
			return
		fi
	done
	# Where the release zip lands if it is unpacked in place.
	for candidate in "$HOME"/Downloads/cli-*/Source2Viewer-CLI "$HOME"/Downloads/cli-*/Source2Viewer-CLI.exe; do
		if [[ -x "$candidate" ]]; then
			echo "$candidate"
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

STEAM_ROOTS=(
	"$HOME/.steam/steam"
	"$HOME/.local/share/Steam"
	"$HOME/Library/Application Support/Steam"
	"/c/Program Files (x86)/Steam"
	"/mnt/c/Program Files (x86)/Steam"
)

## Turns a Windows path out of a Steam config (D:\\SteamLibrary) into one this
## shell can open. Paths that are already POSIX pass through untouched.
to_posix() {
	local path="${1//\\\\//}"
	path="${path//\\//}"
	if [[ "$path" =~ ^([A-Za-z]):(.*)$ ]]; then
		local drive="${BASH_REMATCH[1],,}" rest="${BASH_REMATCH[2]}"
		if [[ -d "/mnt/$drive" ]]; then
			path="/mnt/$drive$rest"
		else
			path="/$drive$rest"
		fi
	fi
	echo "$path"
}

## Every Steam library on the machine. Steam records the extra ones (a second
## drive, for instance) in libraryfolders.vdf, so the game can be found there
## without being told.
steam_libraries() {
	local root vdf library
	for root in "${STEAM_ROOTS[@]}"; do
		vdf="$root/steamapps/libraryfolders.vdf"
		[[ -f "$vdf" ]] || continue
		echo "$root"
		tr -d '\r' < "$vdf" \
			| sed -nE 's/^[[:space:]]*"path"[[:space:]]+"(.*)"[[:space:]]*$/\1/p' \
			| while IFS= read -r library; do to_posix "$library"; done
	done
}

find_cs2() {
	if [[ -n "${CS2_PATH:-}" ]]; then
		to_posix "$CS2_PATH"
		return
	fi
	local candidates=() library
	while IFS= read -r library; do
		candidates+=("$library/steamapps/common/Counter-Strike Global Offensive")
	done < <(steam_libraries)
	for library in "${STEAM_ROOTS[@]}"; do
		candidates+=("$library/steamapps/common/Counter-Strike Global Offensive")
	done
	for candidate in "${candidates[@]}"; do
		# Check for the archive, not just the directory: moving the game to
		# another library leaves a cfg-only husk behind at the old location.
		if [[ -f "$candidate/game/csgo/pak01_dir.vpk" ]]; then
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
	list-map|list-weapons|map|physics|entities|layers|weapons|all) ;;
	*)
		# The header comment, down to the first line that is not one.
		awk 'NR > 2 && /^#/ { sub(/^# ?/, ""); print; next } NR > 2 { exit }' "${BASH_SOURCE[0]}"
		exit 1
		;;
esac

S2V_BIN="$(find_s2v "$@")"
CS2_DIR="$(find_cs2 "$@")"
CSGO_DIR="$CS2_DIR/game/csgo"
MAP_VPK="$CSGO_DIR/maps/de_dust2.vpk"
PAK_VPK="$CSGO_DIR/pak01_dir.vpk"

# On stderr, so that the list commands can be piped or redirected cleanly.
echo "Source2Viewer-CLI: $S2V_BIN" >&2
echo "CS2:               $CS2_DIR" >&2
echo >&2

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

## -l prints one resource per line as "path CRC:xxxx size:nnnn", with CRLF line
## endings on Windows. This reduces that to bare paths, which is what the greps
## below match on and what -f wants back.
list_paths() {
	"$S2V_BIN" -i "$1" -l \
		| tr -d '\r' \
		| sed -E 's/ CRC:[0-9a-fA-F]+ size:[0-9]+$//'
}

list_map() {
	require_file "$MAP_VPK"
	list_paths "$MAP_VPK"
}

list_weapons() {
	require_file "$PAK_VPK"
	# Anchored to weapons/models/ because the bare names also match keychain
	# charms (kc_wpn_m4a1s_*), which are not what anyone means by "the M4".
	list_paths "$PAK_VPK" \
		| grep -iE '\.vmdl_c$' \
		| grep -iE '^weapons/models/.*(ak47|m4a1)'
}

## Prints the one resource in the map VPK matching a pattern, or fails saying
## what was being looked for.
find_map_resource() {
	local pattern="$1" description="$2"
	require_file "$MAP_VPK"
	# Listed first and searched second, so that the tool failing is reported
	# as that and not as the VPK missing something.
	local listing found
	if ! listing="$(list_paths "$MAP_VPK")"; then
		echo "Source2Viewer-CLI failed while listing $MAP_VPK." >&2
		exit 1
	fi
	found="$(grep -iE "$pattern" <<<"$listing" | head -n 1 || true)"
	if [[ -z "$found" ]]; then
		echo "No $description inside $MAP_VPK." >&2
		echo "Run 'scripts/extract_assets.sh list-map' to see what is in there." >&2
		exit 1
	fi
	echo "$found"
}

MAP_DEST="$OUT_DIR/maps/de_dust2"
# A sibling, not a subdirectory: the map directory is scanned for the world
# glTF, and the hull export includes a file that would overwrite one of the
# world export's.
PHYSICS_DEST="$OUT_DIR/maps/de_dust2_physics"

extract_world() {
	local world
	world="$(find_map_resource '\.vwrld_c$' ".vwrld_c")" || exit 1
	mkdir -p "$MAP_DEST"

	echo "Extracting $world"
	echo "        -> $MAP_DEST"
	echo
	echo "This takes a minute or two and produces about 650 PNGs, a little over"
	echo "a gigabyte in all."
	echo

	"$S2V_BIN" \
		-i "$MAP_VPK" \
		-f "$world" \
		-o "$MAP_DEST" \
		-d \
		--gltf_export_format gltf \
		--gltf_export_materials \
		--gltf_textures_adapt
}

## The collision hull: what the game itself collides with, player-clip brushes
## included. A tenth of the triangles of the visible world, and the corners
## are the ones movement was tuned against.
extract_physics() {
	local physics
	physics="$(find_map_resource '/world_physics\.vmdl_c$' "world_physics.vmdl_c")" || exit 1
	mkdir -p "$PHYSICS_DEST"

	echo "Extracting $physics"
	echo "        -> $PHYSICS_DEST"
	"$S2V_BIN" -i "$MAP_VPK" -f "$physics" -o "$PHYSICS_DEST" -d --gltf_export_format gltf

	# The model has no render meshes, so its own glTF comes out as an empty
	# scene; the hull is in the *_physics.gltf written next to it.
	local stub
	stub="$PHYSICS_DEST/${physics%.vmdl_c}.gltf"
	if [[ -f "$stub" && -f "${stub%.gltf}_physics.gltf" ]]; then
		rm -f "$stub" "$stub.import"
	fi
}

## The entity lump, as text: spawn points, bomb sites, the sun.
extract_entities() {
	local entities
	entities="$(find_map_resource '/entities/default_ents\.vents_c$' "default_ents.vents_c")" || exit 1
	mkdir -p "$MAP_DEST"

	echo "Extracting $entities"
	echo "        -> $MAP_DEST"
	"$S2V_BIN" -i "$MAP_VPK" -f "$entities" -o "$MAP_DEST" -d
}

## Most of dust2's walls and ground are two texture layers painted together,
## and a glTF material has room for one. The export keeps each material's full
## description in its extras, second layer and blend mask included, so the
## textures it left behind can be read off the glTF and fetched by name. They
## land under materials/, by the same path the material refers to them by.
extract_layers() {
	require_file "$PAK_VPK"
	local world
	world="$(find "$MAP_DEST" -name 'world.gltf' 2>/dev/null | head -n 1)"
	if [[ -z "$world" ]]; then
		echo "No world.gltf under $MAP_DEST to read the materials from." >&2
		echo "Run 'scripts/extract_assets.sh map' first." >&2
		exit 1
	fi

	local textures
	textures="$(grep -oE '"g_t(Layer2Color|Layer2NormalRoughness|BlendModulation)" *: *"[^"]+"' "$world" \
		| sed -E 's/^"[^"]+" *: *"//; s/"$//; s/\.vtex$/.vtex_c/' | sort -u || true)"
	if [[ -z "$textures" ]]; then
		echo "No layered materials in $world; nothing to fetch."
		return
	fi

	echo "Extracting $(echo "$textures" | wc -l | tr -d ' ') second-layer and blend-mask textures"
	echo "        -> $MAP_DEST/materials"
	"$S2V_BIN" -i "$PAK_VPK" -f "$(echo "$textures" | paste -sd, -)" -o "$MAP_DEST" -d \
		| grep -vE '^(Preloading|Added folder|--- \[)' || true
}

extract_map() {
	extract_world
	echo
	extract_physics
	echo
	extract_entities
	echo
	extract_layers
}

extract_weapons() {
	require_file "$PAK_VPK"
	local dest="$OUT_DIR/weapons"
	mkdir -p "$dest"

	local models
	if ! list_paths "$PAK_VPK" >/dev/null; then
		echo "Source2Viewer-CLI failed while listing $PAK_VPK." >&2
		exit 1
	fi
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

## Godot only picks up new files on an import pass, and the textures need
## their import settings written first (see write_import_settings.gd).
finish() {
	echo
	local godot
	godot="$(find_godot)"
	if [[ -z "$godot" ]]; then
		echo "Extracted, but not imported: no Godot binary found."
		echo "Run scripts/inspect_assets.sh with GODOT=/path/to/godot to finish the job."
		return
	fi
	import_assets "$godot" "$PROJECT_DIR"
	echo
	echo "Done. Open maps/de_dust2/de_dust2.tscn and press play, or run"
	echo "scripts/inspect_assets.sh for a report on what came through."
}

case "$COMMAND" in
	list-map) list_map ;;
	list-weapons) list_weapons ;;
	map) extract_map; finish ;;
	physics) extract_physics; finish ;;
	entities) extract_entities ;;
	layers) extract_layers; finish ;;
	weapons) extract_weapons; finish ;;
	all) extract_map; echo; extract_weapons; finish ;;
esac
