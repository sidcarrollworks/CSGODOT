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
#   scripts/extract_assets.sh list-weapons    # the gun models the weapons step takes
#   scripts/extract_assets.sh map             # dust2: world, collision hull, entities
#   scripts/extract_assets.sh physics         # just the collision hull (seconds)
#   scripts/extract_assets.sh entities        # just the entity lump (seconds)
#   scripts/extract_assets.sh nav             # just the nav mesh the bots walk (seconds)
#   scripts/extract_assets.sh volumes         # just the buy zones, bomb sites and callouts' volumes, and the baked bomb damage
#   scripts/extract_assets.sh radar           # just the radar image and where it lies
#   scripts/extract_assets.sh layers          # just the blend materials' second layers
#   scripts/extract_assets.sh sky             # just the sky panorama
#   scripts/extract_assets.sh skybox          # just the 3D skybox: the far buildings
#   scripts/extract_assets.sh lightmaps       # just the baked bounce light
#   scripts/extract_assets.sh weapons         # every gun: models, first- and third-person animations
#   scripts/extract_assets.sh weapon-animations  # just the guns' animations (a minute)
#   scripts/extract_assets.sh weapon-data     # just the game's weapon tuning (seconds)
#   scripts/extract_assets.sh hud             # the scope overlay and the equipment icons
#   scripts/extract_assets.sh characters      # two player models and their locomotion
#   scripts/extract_assets.sh sounds          # every gun's sounds, footsteps by surface, hits
#   scripts/extract_assets.sh all             # map + weapons + hud + characters + sounds
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
	list-map|list-weapons|map|physics|entities|nav|volumes|radar|layers|sky|skybox|lightmaps|weapons|weapon-animations|weapon-data|hud|characters|sounds|all) ;;
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

## The guns: the 34 in the CS2 weapon sheet, by their folders under
## weapons/models/, which are not always the class names (weapon_m4a1, the
## M4A4, is in m4a4/; weapon_glock in glock18/). reference/weapons/models.md
## has the table, written from what the weapons step extracts.
GUN_DIRS="ak47|aug|awp|bizon|cz75a|deagle|elite|famas|fiveseven|g3sg1|galilar|glock18|hkp2000|m249|m4a1_silencer|m4a4|mac10|mag7|mp5sd|mp7|mp9|negev|nova|p250|p90|revolver|sawedoff|scar20|sg556|ssg08|tec9|ump45|usp_silencer|xm1014"
## Their animation skeletons are named the same, but for the Galil's.
GUN_SKELETONS="$GUN_DIRS|galil"
## And their sound folders under sounds/weapons/: the M4A4 and the M4A1-S
## share m4a1/, and the MP5-SD's is mp5/ and the USP-S's usp/.
GUN_SOUND_DIRS="ak47|aug|awp|bizon|cz75a|deagle|elite|famas|fiveseven|g3sg1|galilar|glock18|hkp2000|m249|m4a1|mac10|mag7|mp5|mp7|mp9|negev|nova|p250|p90|revolver|sawedoff|scar20|sg556|ssg08|tec9|ump45|usp|xm1014"

list_weapons() {
	require_file "$PAK_VPK"
	# Each gun's folder (the gun and its magazine as a model of its own), and
	# the shared shell casings. Anchored to weapons/models/ because the bare
	# names also match keychain charms (kc_wpn_m4a1s_*).
	list_paths "$PAK_VPK" \
		| grep -iE '\.vmdl_c$' \
		| grep -iE "^weapons/models/(($GUN_DIRS)/|shared/shells/)"
}

## Prints the one resource in a VPK matching a pattern, or fails saying what
## was being looked for. The VPK is the map's unless a third argument says.
find_map_resource() {
	local pattern="$1" description="$2" vpk="${3:-$MAP_VPK}"
	require_file "$vpk"
	# Listed first and searched second, so that the tool failing is reported
	# as that and not as the VPK missing something.
	local listing found
	if ! listing="$(list_paths "$vpk")"; then
		echo "Source2Viewer-CLI failed while listing $vpk." >&2
		exit 1
	fi
	found="$(grep -iE "$pattern" <<<"$listing" | head -n 1 || true)"
	if [[ -z "$found" ]]; then
		echo "No $description inside $vpk." >&2
		echo "Run 'scripts/extract_assets.sh list-map' to see what is in there." >&2
		exit 1
	fi
	echo "$found"
}

## Runs Source2Viewer-CLI on the main game archive over a comma-separated
## list of paths, a batch at a time, with the rest of the arguments as given:
## Windows caps a command line at 32,767 characters, and a few hundred paths
## overrun it ("Argument list too long", and nothing extracted).
s2v_batched() {
	local files="$1"
	shift
	local batch="" path
	while IFS= read -r path; do
		if [[ -n "$batch" ]] && (( ${#batch} + ${#path} > 20000 )); then
			"$S2V_BIN" -i "$PAK_VPK" -f "$batch" "$@"
			batch=""
		fi
		batch="${batch:+$batch,}$path"
	done < <(tr ',' '\n' <<<"$files")
	if [[ -n "$batch" ]]; then
		"$S2V_BIN" -i "$PAK_VPK" -f "$batch" "$@"
	fi
}

## Refuses to hand Source2Viewer-CLI an empty filter, which it reads as
## "everything": the whole game, gigabytes of it, wherever -o points.
require_filter() {
	if [[ -z "$1" ]]; then
		echo "Nothing to extract for $2: the filter came out empty." >&2
		exit 1
	fi
}

MAP_DEST="$OUT_DIR/maps/de_dust2"
# A sibling, not a subdirectory: the map directory is scanned for the world
# glTF, and the hull export includes a file that would overwrite one of the
# world export's.
PHYSICS_DEST="$OUT_DIR/maps/de_dust2_physics"
SKYBOX_DEST="$OUT_DIR/maps/de_dust2_skybox"
CHARACTERS_DEST="$OUT_DIR/characters"

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

## The nav mesh the game's bots walk: maps/de_dust2.nav, half a megabyte,
## stored in the map's VPK as it is (not a compiled resource), so it comes
## out byte for byte. SourceNavMesh reads it.
extract_nav() {
	local nav
	nav="$(find_map_resource '^maps/[^/]+\.nav$' "nav mesh (.nav)")" || exit 1
	mkdir -p "$MAP_DEST"

	echo "Extracting $nav"
	echo "        -> $MAP_DEST"
	"$S2V_BIN" -i "$MAP_VPK" -f "$nav" -o "$MAP_DEST"
}

## The brush entities' own models, maps/de_dust2/entities/*.vmdl: the buy
## zones, the bomb sites and the callouts' places, which the entity lump
## names by model and which exist nowhere else. Each exports as an empty glTF
## and a _physics.gltf holding the volume, in inches about the entity's
## origin; BrushVolume reads them. With them, the game's baked bomb damage
## (maps/de_dust2/baked_bomb_damage.vdata), as KV3 text.
extract_volumes() {
	require_file "$MAP_VPK"
	mkdir -p "$MAP_DEST"
	echo "Extracting the brush entities' models and the baked bomb damage"
	echo "        -> $MAP_DEST"
	"$S2V_BIN" -i "$MAP_VPK" -f "maps/de_dust2/entities/" -e vmdl_c -o "$MAP_DEST" -d --gltf_export_format gltf \
		| grep -c '^--- Dump' | sed 's/$/ models/'
	local damage
	damage="$(find_map_resource '/baked_bomb_damage\.vdata_c$' "baked bomb damage (baked_bomb_damage.vdata_c)")" || exit 1
	mkdir -p "$(dirname "$MAP_DEST/$damage")"
	"$S2V_BIN" -i "$MAP_VPK" -f "$damage" -o "$MAP_DEST/${damage%_c}" -d | grep -E '^--- Dump' || true
}

## dust2's radar: the overview image (a 1024 square) and the text that says
## where it lies over the map, in the main archive rather than the map's.
## MapOverview reads the text.
extract_radar() {
	require_file "$PAK_VPK"
	mkdir -p "$MAP_DEST"
	echo "Extracting dust2's radar"
	echo "        -> $MAP_DEST"
	"$S2V_BIN" -i "$PAK_VPK" -f "panorama/images/overheadmaps/de_dust2_radar_psd.vtex_c,resource/overviews/de_dust2.txt" \
		-o "$MAP_DEST" -d | grep -E '^--- Dump' || true
}

## Most of dust2's walls and ground are two texture layers painted together,
## and a glTF material has room for one. The export keeps each material's full
## description in its extras, second layer and blend mask included, so the
## textures it left behind can be read off the glTF and fetched by name. They
## land under materials/, by the same path the material refers to them by.
extract_layers() {
	extract_layers_under "$MAP_DEST"
}

extract_layers_under() {
	local dest="$1"
	require_file "$PAK_VPK"
	local world
	world="$(find "$dest" -name 'world.gltf' 2>/dev/null | head -n 1)"
	if [[ -z "$world" ]]; then
		echo "No world.gltf under $dest to read the materials from." >&2
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
	echo "        -> $dest/materials"
	"$S2V_BIN" -i "$PAK_VPK" -f "$(echo "$textures" | paste -sd, -)" -o "$dest" -d \
		| grep -vE '^(Preloading|Added folder|--- \[)' || true
}

## The 3D skybox: the buildings and horizon beyond the playable map, which
## are a small map of their own, built at a sixteenth of the scale around a
## sky_camera. Which map is in the entity lump (skybox_reference), so that
## runs first. It comes with its own entity lump, for the camera's position.
extract_skybox() {
	local entities
	entities="$(find "$MAP_DEST" -name 'default_ents.vents' 2>/dev/null | head -n 1)"
	if [[ -z "$entities" ]]; then
		echo "No entity lump under $MAP_DEST to read the skybox map from." >&2
		echo "Run 'scripts/extract_assets.sh entities' first." >&2
		exit 1
	fi
	local target
	target="$(tr -d '\r' < "$entities" | grep -oE 'targetmapname +"[^"]+"' | head -n 1 \
		| sed -E 's/.*"([^"]+)"/\1/; s/\.vmap$//' || true)"
	if [[ -z "$target" ]]; then
		echo "No skybox_reference in $entities; the map has no 3D skybox."
		return
	fi
	local vpk="$CSGO_DIR/$target.vpk"
	require_file "$vpk"
	mkdir -p "$SKYBOX_DEST"

	local world
	world="$(find_map_resource '\.vwrld_c$' ".vwrld_c" "$vpk")" || exit 1
	echo "Extracting $world"
	echo "        -> $SKYBOX_DEST"
	"$S2V_BIN" -i "$vpk" -f "$world" -o "$SKYBOX_DEST" -d \
		--gltf_export_format gltf --gltf_export_materials --gltf_textures_adapt \
		| grep -vE '^(Preloading|Added folder|--- \[|--- Creating|--- Loading)' || true

	local lump
	lump="$(find_map_resource '/entities/default_ents\.vents_c$' "default_ents.vents_c" "$vpk")" || exit 1
	"$S2V_BIN" -i "$vpk" -f "$lump" -o "$SKYBOX_DEST" -d | grep -E '^--- Dump' || true
	echo
	extract_layers_under "$SKYBOX_DEST"
}

## The sky, as the HDR panorama the map's sky material is made of. Which
## material that is comes from the entity lump (env_sky), so that runs first.
extract_sky() {
	require_file "$PAK_VPK"
	local entities
	entities="$(find "$MAP_DEST" -name 'default_ents.vents' 2>/dev/null | head -n 1)"
	if [[ -z "$entities" ]]; then
		echo "No entity lump under $MAP_DEST to read the sky material from." >&2
		echo "Run 'scripts/extract_assets.sh entities' first." >&2
		exit 1
	fi
	local sky
	sky="$(tr -d '\r' < "$entities" | grep -oE 'skyname +resource_name:"[^"]+"' | head -n 1 \
		| sed -E 's/.*"([^"]+)"/\1/; s/\.vmat$/.vmat_c/' || true)"
	if [[ -z "$sky" ]]; then
		echo "No env_sky in $entities; the map has no sky material to fetch."
		return
	fi
	echo "Extracting $sky"
	echo "        -> $MAP_DEST"
	"$S2V_BIN" -i "$PAK_VPK" -f "$sky" -o "$MAP_DEST" -d \
		| grep -vE '^(Preloading|Added folder|--- \[)' || true
}

## The map's baked lighting. CS2 bakes the bounce light into an irradiance
## lightmap (8192 square, HDR, 78 MB compressed) with a companion that says
## which way the light mostly comes from; the sun's own light it computes
## live, so its shadow masks are not fetched. Source 2 Viewer writes the
## irradiance as an .exr of 300 MB, which Godot compresses back down on
## import.
## Also the light probes: one 3D atlas of ambient cubes for the whole map,
## which decompiles to one small HDR image per depth slice (720 on dust2).
## They go in a probes/ directory with a .gdignore, so Godot does not import
## seven hundred textures it will never draw; the game reads them itself.
extract_lightmaps() {
	local maps
	maps="$(list_paths "$MAP_VPK" | grep -E '/lightmaps/(irradiance|directional_irradiance|env_light_probe_volume_atlas)\.vtex_c$' | paste -sd, - || true)"
	require_filter "$maps" "the lightmaps"
	mkdir -p "$MAP_DEST"
	echo "Extracting the baked lighting (a few hundred megabytes, uncompressed) and the light probes"
	echo "        -> $MAP_DEST"
	"$S2V_BIN" -i "$MAP_VPK" -f "$maps" -o "$MAP_DEST" -d | grep -E '^--- Dump' | grep -v '_atlas_z' || true
	find "$MAP_DEST" -name 'env_light_probe_volume_atlas_z*.exr' | while IFS= read -r slice; do
		local probes="$(dirname "$slice")/probes"
		mkdir -p "$probes"
		touch "$probes/.gdignore"
		mv "$slice" "$probes/"
	done
	local count
	count="$(find "$MAP_DEST" -path '*/probes/env_light_probe_volume_atlas_z*.exr' | wc -l | tr -d ' ')"
	echo "        light probes: $count atlas slices under lightmaps/probes/"
}

extract_map() {
	extract_world
	echo
	extract_physics
	echo
	extract_entities
	echo
	extract_nav
	echo
	extract_volumes
	echo
	extract_radar
	echo
	extract_layers
	echo
	extract_sky
	echo
	extract_skybox
	echo
	extract_lightmaps
}

extract_weapons() {
	require_file "$PAK_VPK"
	local dest="$OUT_DIR/weapons"
	mkdir -p "$dest"

	local models listing
	if ! listing="$(list_paths "$PAK_VPK")"; then
		echo "Source2Viewer-CLI failed while listing $PAK_VPK." >&2
		exit 1
	fi
	models="$(list_weapons || true)"
	if [[ -z "$models" ]]; then
		echo "Found no gun models in $PAK_VPK." >&2
		echo "Run 'scripts/extract_assets.sh list-weapons' and check the filter." >&2
		exit 1
	fi

	echo "Extracting $(wc -l <<<"$models" | tr -d ' ') gun models:"
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

	extract_weapon_data
	extract_weapon_animations
}

## What the HUD draws that comes from the game: the sniper scope's overlay,
## which the game composes in code from three images (the black mask with its
## soft round opening, the lens's tint and dirt, and the soft line the cross
## is drawn with), and the equipment icons, one SVG per weapon by its class
## less "weapon_" (with the silencers-off variants), armour, the kit, the
## grenades, the knife and the bomb, for the ammo display, the kill feed and
## the buy menu.
extract_hud() {
	require_file "$PAK_VPK"
	local dest="$OUT_DIR/hud"
	mkdir -p "$dest"
	echo "Extracting the scope overlay and the equipment icons"
	echo "        -> $dest"
	"$S2V_BIN" -i "$PAK_VPK" -f "panorama/images/hud/scope/,panorama/images/icons/equipment/" -o "$dest" -d \
		| grep -vE '^(Preloading|Added folder|--- )' || true
	echo "        $(find "$dest" -name '*.svg' | wc -l | tr -d ' ') icons, $(find "$dest" -path '*scope*' -name '*.png' | wc -l | tr -d ' ') scope images"
}

## The game's own weapon tuning, scripts/weapons.vdata_c, decoded to KV3 text
## (this Source 2 Viewer reads it; older ones did not). Every gun's damage,
## fire rate, spread and inaccuracy, recovery, recoil, zoom levels, deploy
## time and muzzle position, each gun's entry inheriting through _base from
## its prefab and class. weapon_tables.gd writes reference/weapons/vdata.md
## from it, with a check against the weapon sheet.
extract_weapon_data() {
	require_file "$PAK_VPK"
	local dest="$OUT_DIR/scripts"
	mkdir -p "$dest"
	echo "Reading the game's weapon tuning"
	echo "        -> $dest/weapons.vdata.txt"
	"$S2V_BIN" -i "$PAK_VPK" -f "scripts/weapons.vdata_c" -b DATA > "$dest/weapons.vdata.txt" 2>/dev/null || true
}

## The guns' animations, beside the characters' where the view model and the
## player model look for them: each gun's first-person set (draw, idle,
## inspect, reload, fire; the shared _default_ sets are the M4A1-S's and the
## USP-S's), its third-person set (draw, idle, reload and fire, standing and
## crouched), the pistols' shared locomotion, and each gun's skeleton. SMGs,
## shotguns, snipers and machine guns are all rifle sets.
extract_weapon_animations() {
	require_file "$PAK_VPK"
	local listing
	if ! listing="$(list_paths "$PAK_VPK")"; then
		echo "Source2Viewer-CLI failed while listing $PAK_VPK." >&2
		exit 1
	fi
	local clips
	clips="$(grep -E "^animation/(anims/viewmodel/(rifle/(_default_rifle|rifle_[a-z0-9]+)|pistol/(_default_pistol|pistol_[a-z0-9]+))/|anims/world/(rifle/rifle_[a-z0-9_]+|pistol/pistol_[a-z0-9_]+)/|anims/world/pistol/_default_pistol/(idle|run|walk|crouch|inair|jump_stand|shoot)_[a-z_]*\.vnmclip_c$|skeletons/weapons/($GUN_SKELETONS)\.vnmskel_c$)" <<<"$listing" \
		| paste -sd, - || true)"
	require_filter "$clips" "the gun animations"
	echo
	echo "Extracting $(tr ',' '\n' <<<"$clips" | wc -l | tr -d ' ') gun animations and skeletons, first and third person"
	echo "        -> $CHARACTERS_DEST/animation"
	mkdir -p "$CHARACTERS_DEST"
	s2v_batched "$clips" -o "$CHARACTERS_DEST" -d --gltf_export_format gltf \
		| grep -vE '^(Preloading|Added folder|--- )' || true

	# And the first-person clips' own data, which the glTF leaves out: each
	# clip's length and its events, among them when a reload puts the rounds
	# in, a shotgun's shell-by-shell loop, when a silencer goes on, and the
	# sounds' timing. weapon_tables.gd reads it for reference/weapons/timings.md.
	local clip_data="$CHARACTERS_DEST/animation/anims/viewmodel/clip_data.txt"
	echo
	echo "Reading the first-person clips' lengths and events"
	echo "        -> $clip_data"
	"$S2V_BIN" -i "$PAK_VPK" -f "animation/anims/viewmodel/rifle/,animation/anims/viewmodel/pistol/" \
		-e vnmclip_c -b DATA > "$clip_data" 2>/dev/null || true

	write_weapon_tables
}

## Writes reference/weapons/models.md and sounds.md from what was
## extracted, so the code that picks a gun's files can be written without
## them (scripts/weapon_tables.gd).
write_weapon_tables() {
	local godot
	godot="$(find_godot)"
	if [[ -z "$godot" ]]; then
		echo "No Godot binary found; the weapon tables in reference/weapons/ were not rewritten."
		return
	fi
	echo
	local version
	version="$(sed -n 's/^PatchVersion=//p' "$CS2_DIR/game/csgo/steam.inf" 2>/dev/null | tr -d '\r' || true)"
	CS2_VERSION="$version" "$godot" --headless --path "$PROJECT_DIR" --script scripts/weapon_tables.gd 2>&1 \
		| grep -E '^(weapon tables|  )' || true
}

## The sounds: every gun's whole folder (firing near and far, the reload's
## parts, the draw, the inspect, and the modes: silencer, zoom, burst), with
## the weapon sounds they share (empty clicks, the zoom, the fire-mode
## switch); footsteps
## and landings by the surface types the map's hull names; and what the
## shooter hears on a hit. CS2 keeps sounds as one file each (.vsnd_c), a
## few variants to a set, which the decompile writes out as the audio they
## hold. The sound event definitions that pair them with volumes and
## distances are not fetched; the numbers are set by ear.
SOUND_FILTER="^sounds/(weapons/($GUN_SOUND_DIRS)/[a-z0-9_-]+|weapons/[a-z0-9_]+|player/footsteps/(concrete_ct|dirt|sand|wood|metal_solid|metal_vent|metal_chainlink|metal_grate|tile|gravel|grass|carpet|glass|rubber|plastic_barrel|mud)_[0-9]+|player/footsteps/land_(concrete|dirt|sand|metal_solid|metal_vent|metal_grate|tile|gravel|grass|carpet|glass|rubber|mud|auto)(_[0-9]+)?|player/(kevlar[0-9]|headshot_armor_01|headshot_noarmor_0[1-5]|bodyshot_kill_01)|physics/(concrete/concrete_impact_bullet[0-9]|surfaces/(sand|dirt|tile|default|carpet|grass)_impact_bullet[0-9_]*|metal/metal_solid_impact_bullet[0-9]|wood/wood_solid_impact_bullet[0-9]))\.vsnd_c$"

## The bullet holes: the game's bullet-hole materials for concrete, plaster,
## metal and wood, which are what dust2 is made of, and the colour, occlusion
## and normal textures they name. The materials decompile to .vmat text, which
## says which texture is which and how big the hole is; the textures to png.
## Beside the sounds, under decals/.
DECAL_FILTER='^materials/decals/((concrete/concrete[1-5]|plaster/plaster[1-4]|metal/metal[1-3]|wood/wood[1-4])\.vmat_c|(concrete/bullethole_concrete_[1-5]|plaster/(plaster[12]_bullet|plaster_2_bullet|plaster0[12])|metal/bullethole_metal_[1-3]|wood/wood_[1-4]_decal)_(color|ao|normal)_[a-z0-9_]*\.vtex_c)$'

extract_sounds() {
	require_file "$PAK_VPK"
	local dest="$OUT_DIR/sounds"
	mkdir -p "$dest"
	local listing sounds
	if ! listing="$(list_paths "$PAK_VPK")"; then
		echo "Source2Viewer-CLI failed while listing $PAK_VPK." >&2
		exit 1
	fi
	sounds="$(grep -E "$SOUND_FILTER" <<<"$listing" | paste -sd, - || true)"
	require_filter "$sounds" "the sounds"
	echo "Extracting $(tr ',' '\n' <<<"$sounds" | wc -l | tr -d ' ') sounds: the weapons, footsteps by surface, hits, impacts"
	echo "        -> $dest"
	s2v_batched "$sounds" -o "$dest" -d \
		| grep -vE '^(Preloading|Added folder|--- )' || true

	local decals
	decals="$(grep -E "$DECAL_FILTER" <<<"$listing" | paste -sd, - || true)"
	require_filter "$decals" "the bullet holes"
	mkdir -p "$OUT_DIR/decals"
	echo "Extracting $(tr ',' '\n' <<<"$decals" | wc -l | tr -d ' ') bullet-hole materials and textures"
	echo "        -> $OUT_DIR/decals"
	"$S2V_BIN" -i "$PAK_VPK" -f "$decals" -o "$OUT_DIR/decals" -d \
		| grep -vE '^(Preloading|Added folder|--- )' || true

	write_weapon_tables
}

## The player models, and the animations the first-person view is made of.
##
## The models under characters/ are stubs; the meshes are the "agents" under
## agents/models, one variant of which is exported per side, without the two
## thousand animations each one embeds. Animations in CS2 are files of their
## own: the first-person rifle clips are fetched here, with the skeleton they
## are for, and the rest can follow the same way when they are wanted.
AGENTS="agents/models/tm_phoenix/tm_phoenix_varianta.vmdl_c,agents/models/ctm_sas/ctm_sas.vmdl_c"

extract_characters() {
	require_file "$PAK_VPK"
	mkdir -p "$CHARACTERS_DEST"
	local listing
	if ! listing="$(list_paths "$PAK_VPK")"; then
		echo "Source2Viewer-CLI failed while listing $PAK_VPK." >&2
		exit 1
	fi

	local agents
	agents="$(tr ',' '\n' <<<"$AGENTS" | while IFS= read -r agent; do
		grep -xF "$agent" <<<"$listing" || echo "Not in the game archive: $agent" >&2
	done | paste -sd, -)"
	require_filter "$agents" "the player models"
	echo "Extracting the player models:"
	tr ',' '\n' <<<"$agents" | sed 's/^/  /'
	"$S2V_BIN" -i "$PAK_VPK" -f "$agents" -o "$CHARACTERS_DEST" -d \
		--gltf_export_format gltf --gltf_export_materials --gltf_textures_adapt \
		--gltf_export_animations --gltf_animation_list "idle_default_stand" \
		| grep -vE '^(Preloading|Added folder|--- \[|--- Creating|--- Loading)' || true

	# The hitboxes: each model's cstrike hitbox set, in the decompiled model
	# description. The decompile writes the meshes and a few animations out
	# beside it as well, so it goes through a scratch directory and only the
	# description is kept, next to the model's glTF.
	local scratch
	scratch="$(mktemp -d)"
	echo
	echo "Extracting the hitbox sets"
	"$S2V_BIN" -i "$PAK_VPK" -f "$agents" -o "$scratch" -d \
		| grep -vE '^(Preloading|Added folder|--- )' || true
	find "$scratch" -name '*.vmdl' | while IFS= read -r description; do
		local relative="${description#"$scratch"/}"
		mkdir -p "$CHARACTERS_DEST/$(dirname "$relative")"
		cp "$description" "$CHARACTERS_DEST/$relative"
		echo "        -> $CHARACTERS_DEST/$relative"
	done
	rm -rf "$scratch"

	local clips
	# First person: the AK's clips and the shared rifle set, which is the
	# M4A1-S's. Third person: the shared set's locomotion (idle, walk, run,
	# crouch, in the eight directions, plus in-air, jump and shoot), each
	# weapon's own draw, reload and shoot, and the shared deaths by where the
	# last round landed. (The flinches beside them are additive layers, not
	# poses, and wait for an animation tree to add them.)
	clips="$(grep -E '^animation/(anims/viewmodel/rifle/(_default_rifle|rifle_ak)/|anims/world/rifle/(_default_rifle/(idle|run|walk|crouch|inair|jump_stand|shoot)_[a-z_]*|rifle_ak/|rifle_m4a1_silencer/)|anims/world/shared/death_(chest|gut|rknee|rshoulder)[a-z_]*\.vnmclip_c$|skeletons/characters/(viewmodel|worldmodel)\.vnmskel_c$|skeletons/weapons/(ak47|m4a1)[a-z_]*\.vnmskel_c$)' <<<"$listing" \
		| paste -sd, - || true)"
	require_filter "$clips" "the animations"
	echo
	echo "Extracting $(tr ',' '\n' <<<"$clips" | wc -l | tr -d ' ') rifle animations and skeletons, first and third person"
	echo "        -> $CHARACTERS_DEST/animation"
	"$S2V_BIN" -i "$PAK_VPK" -f "$clips" -o "$CHARACTERS_DEST" -d --gltf_export_format gltf \
		| grep -vE '^(Preloading|Added folder|--- )' || true
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
	nav) extract_nav ;;
	volumes) extract_volumes ;;
	radar) extract_radar ;;
	layers) extract_layers; finish ;;
	sky) extract_sky; finish ;;
	skybox) extract_skybox; finish ;;
	lightmaps) extract_lightmaps; finish ;;
	characters) extract_characters; finish ;;
	weapons) extract_weapons; finish ;;
	weapon-animations) extract_weapon_animations; finish ;;
	weapon-data) extract_weapon_data; write_weapon_tables ;;
	hud) extract_hud; finish ;;
	sounds) extract_sounds; finish ;;
	all) extract_map; echo; extract_weapons; echo; extract_hud; echo; extract_characters; echo; extract_sounds; finish ;;
esac
