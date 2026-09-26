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
#   scripts/extract_assets.sh list-map        # what is inside the map's VPK
#   scripts/extract_assets.sh list-weapons    # the gun models the weapons step takes
#   scripts/extract_assets.sh map             # every step for one map: world, hull, entities, nav, volumes, radar, surfaces, layers, sky, skybox, lightmaps, visibility, postprocessing
#   scripts/extract_assets.sh physics         # just the collision hull (seconds)
#   scripts/extract_assets.sh entities        # just the entity lump (seconds)
#   scripts/extract_assets.sh nav             # just the nav mesh the bots walk (seconds)
#   scripts/extract_assets.sh volumes         # just the buy zones, bomb sites and callouts' volumes, and the baked bomb damage
#   scripts/extract_assets.sh radar           # just the radar image and where it lies
#   scripts/extract_assets.sh surfaces        # just CS2's surfaces: parents, friction, penetration (seconds)
#   scripts/extract_assets.sh layers          # just the textures the glTF has no slot for: second layers, decals, glows
#   scripts/extract_assets.sh sky             # just the sky panorama
#   scripts/extract_assets.sh skybox          # just the 3D skybox: the far buildings and their baked light
#   scripts/extract_assets.sh lightmaps       # just the baked light: bounce light, the sun's shadow, light probes
#   scripts/extract_assets.sh visibility      # just which parts of the map can see which (seconds)
#   scripts/extract_assets.sh postprocessing  # just the map's colour grade: its curve, bloom and colour table (seconds)
#   scripts/extract_assets.sh weapons         # every gun: models, first- and third-person animations
#   scripts/extract_assets.sh weapon-animations  # just the guns' animations (a minute)
#   scripts/extract_assets.sh weapon-data     # just the game's weapon tuning (seconds)
#   scripts/extract_assets.sh weapon-physics  # just the items' physics blocks: bone, mass, damping (seconds)
#   scripts/extract_assets.sh equipment       # the bomb and kit, grenades, default knives, Zeus: models and animations
#   scripts/extract_assets.sh hud             # the scope overlay, the HUD's icons and font
#   scripts/extract_assets.sh effects         # the tracers' and muzzle flashes' textures
#   scripts/extract_assets.sh characters      # two player models and their locomotion
#   scripts/extract_assets.sh animgraphs      # the animation graphs that drive the clips (seconds)
#   scripts/extract_assets.sh character-masks # just the player models' cloth masks and eye textures (seconds; the characters step takes them too)
#   scripts/extract_assets.sh character-animations # just the player models' clips and skeletons (no models or materials)
#   scripts/extract_assets.sh sounds          # the guns' and the equipment's sounds, footsteps by surface, hits
#   scripts/extract_assets.sh all             # map + weapons + equipment + hud + effects + characters + animgraphs + sounds
#
# The steps for one map (list-map, map, physics, entities, nav, volumes,
# radar, layers, sky, skybox, lightmaps, visibility, postprocessing, and all) take the map's name after
# the step, de_dust2 when there is none:
#   scripts/extract_assets.sh map de_mirage   # all of de_mirage, into assets/maps/de_mirage
#   scripts/extract_assets.sh nav de_inferno  # just de_inferno's nav mesh
#   scripts/extract_assets.sh paths de_mirage # where they land; needs no CS2
# Each map lands in assets/maps/<name>, with its hull in <name>_physics and
# its 3D skybox in <name>_skybox; maps/play/play.tscn plays it (reference/extracting.md).
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

usage() {
	# The header comment, down to the first line that is not one.
	awk 'NR > 2 && /^#/ { sub(/^# ?/, ""); print; next } NR > 2 { exit }' "${BASH_SOURCE[0]}"
	exit 1
}

COMMAND="${1:-}"
case "$COMMAND" in
	list-map|map|physics|entities|nav|volumes|radar|layers|sky|skybox|lightmaps|visibility|postprocessing|all|paths) ;;
	list-weapons|surfaces|weapons|weapon-animations|weapon-data|weapon-physics|equipment|hud|effects|characters|character-masks|character-animations|animgraphs|sounds)
		# Not a map's own step: a map name here would be ignored, which is
		# worse than being told.
		if [[ $# -gt 1 ]]; then
			echo "'$COMMAND' is not a step for one map, so it takes no map name." >&2
			exit 1
		fi
		;;
	*) usage ;;
esac

## The map the per-map steps work on, as CS2 names it (its VPK is
## maps/<name>.vpk). Everything the map's steps read and write is named from
## it; de_dust2's paths are the ones they always were.
MAP_NAME="${2:-de_dust2}"
if [[ ! "$MAP_NAME" =~ ^[a-z0-9_]+$ ]]; then
	echo "'$MAP_NAME' is not a map name: CS2's are lower case letters, digits and underscores (de_mirage)." >&2
	exit 1
fi
if [[ $# -gt 2 ]]; then
	usage
fi

MAP_DEST="$OUT_DIR/maps/$MAP_NAME"
# A sibling, not a subdirectory: the map directory is scanned for the world
# glTF, and the hull export includes a file that would overwrite one of the
# world export's.
PHYSICS_DEST="$OUT_DIR/maps/${MAP_NAME}_physics"
SKYBOX_DEST="$OUT_DIR/maps/${MAP_NAME}_skybox"
## Where the map's steps put the files the game reads by name, under
## MAP_DEST: they keep the path they have in the VPK.
MAP_NAV="maps/$MAP_NAME.nav"
MAP_ENTITY_MODELS="maps/$MAP_NAME/entities/"
MAP_RADAR="panorama/images/overheadmaps/${MAP_NAME}_radar_psd"
MAP_OVERVIEW="resource/overviews/$MAP_NAME.txt"

# Where a map's files land, without CS2 or Source2Viewer-CLI: MapPaths
# derives the same, and tests/run_map_mode_checks.gd holds the two together.
if [[ "$COMMAND" == paths ]]; then
	echo "map ${MAP_DEST#"$PROJECT_DIR"/}"
	echo "physics ${PHYSICS_DEST#"$PROJECT_DIR"/}"
	echo "skybox ${SKYBOX_DEST#"$PROJECT_DIR"/}"
	echo "nav ${MAP_DEST#"$PROJECT_DIR"/}/$MAP_NAV"
	echo "entity-models ${MAP_DEST#"$PROJECT_DIR"/}/$MAP_ENTITY_MODELS"
	echo "radar ${MAP_DEST#"$PROJECT_DIR"/}/$MAP_RADAR.png"
	echo "overview ${MAP_DEST#"$PROJECT_DIR"/}/$MAP_OVERVIEW"
	exit 0
fi

S2V_BIN="$(find_s2v "$@")"
CS2_DIR="$(find_cs2 "$@")"
CSGO_DIR="$CS2_DIR/game/csgo"
MAP_VPK="$CSGO_DIR/maps/$MAP_NAME.vpk"
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

## The equipment: the bomb (with the multimeter a defuse shows) and the
## defuse kit, the six grenades (with the pin and spoon they share, and the
## molotov's glass), the two default knives, and the Zeus. By their folders
## under weapons/models/; reference/weapons/equipment.md has the table.
EQUIPMENT_MODELS="c4/|defuser/|grenade/|knife/knife_default_(ct|t)/|taser/"
## Their first-person sets, their third-person ones (the knife's locomotion,
## the bomb's and the defuse's among them), and their skeletons. The Zeus's
## sets are pistol ones, which the guns' step takes too.
EQUIPMENT_FIRST_PERSON="equipment/c4|grenade/[a-z_]+|knife/(_default_knife|knife_default_t)|pistol/pistol_taser"
EQUIPMENT_THIRD_PERSON="equipment/c4|grenade/(_default_grenade|grenade_molotov)|knife/(_default_knife|default_ct|default_t)|shared/defuse|pistol/pistol_taser"
EQUIPMENT_SKELETONS="c4|decoy|flashbang|hegrenade|incendiary|molotov|smokegrenade|knife_default_ct|knife_default_t|taser"
## And their sound folders under sounds/weapons/, which the sounds step takes.
EQUIPMENT_SOUND_DIRS="c4|decoy|flashbang|hegrenade|incgrenade|molotov|smokegrenade|knife|taser"

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
		echo "Run 'scripts/extract_assets.sh list-map $MAP_NAME' to see what is in there." >&2
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

## The nav mesh the game's bots walk: maps/<name>.nav (dust2's is half a megabyte),
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

## The brush entities' own models, maps/<name>/entities/*.vmdl: the buy
## zones, the bomb sites and the callouts' places, which the entity lump
## names by model (the world export's world_physics.gltf holds them too, but
## named only by class). Each exports as a glTF, empty but for the two
## func_brush, and a _physics.gltf holding the volume, in inches about the
## entity's origin; BrushVolume reads them. With them, the game's baked bomb damage
## (maps/<name>/baked_bomb_damage.vdata), as KV3 text.
extract_volumes() {
	require_file "$MAP_VPK"
	mkdir -p "$MAP_DEST"
	echo "Extracting the brush entities' models and the baked bomb damage"
	echo "        -> $MAP_DEST"
	local count
	count="$("$S2V_BIN" -i "$MAP_VPK" -f "$MAP_ENTITY_MODELS" -e vmdl_c -o "$MAP_DEST" -d --gltf_export_format gltf \
		| { grep -c '^--- Dump written' || true; })"
	if [[ "$count" -eq 0 ]]; then
		echo "No brush entity models under $MAP_ENTITY_MODELS in $MAP_VPK." >&2
		exit 1
	fi
	echo "$count models"
	local damage
	damage="$(find_map_resource '/baked_bomb_damage\.vdata_c$' "baked bomb damage (baked_bomb_damage.vdata_c)")" || exit 1
	mkdir -p "$(dirname "$MAP_DEST/$damage")"
	"$S2V_BIN" -i "$MAP_VPK" -f "$damage" -o "$MAP_DEST/${damage%_c}" -d | grep -E '^--- Dump' || true
}

## CS2's surfaces: surfaceproperties.vsurf, every surface with its parent and
## physics (friction among them), and surfaceproperties_game.txt, the game's
## values (the two a round going through it uses among them), from the main
## archive. scripts/surface_tables.gd then writes reference/surfaces/ from
## them, which is what SurfaceProperties reads.
extract_surfaces() {
	require_file "$PAK_VPK"
	local dest="$OUT_DIR/surfaces"
	mkdir -p "$dest"
	echo "Extracting CS2's surfaces"
	echo "        -> $dest"
	"$S2V_BIN" -i "$PAK_VPK" -f "surfaceproperties/surfaceproperties.vsurf_c,scripts/surfaceproperties_game.txt" \
		-o "$dest" -d | grep -E '^--- Dump written' || true
	local godot
	godot="$(find_godot)"
	if [[ -z "$godot" ]]; then
		echo "No Godot binary found; the surface tables in reference/surfaces/ were not rewritten."
		return
	fi
	local version
	version="$(sed -n 's/^PatchVersion=//p' "$CS2_DIR/game/csgo/steam.inf" 2>/dev/null | tr -d '\r' || true)"
	CS2_VERSION="$version" "$godot" --headless --path "$PROJECT_DIR" --script scripts/surface_tables.gd 2>&1 \
		| grep -E '^(surface tables|  )' || true
}

## The map's radar: the overview image (a 1024 square) and the text that says
## where it lies over the map, in the main archive rather than the map's.
## MapOverview reads the text.
extract_radar() {
	require_file "$PAK_VPK"
	mkdir -p "$MAP_DEST"
	echo "Extracting $MAP_NAME's radar"
	echo "        -> $MAP_DEST"
	"$S2V_BIN" -i "$PAK_VPK" -f "$MAP_RADAR.vtex_c,$MAP_OVERVIEW" \
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
		echo "Run 'scripts/extract_assets.sh map $MAP_NAME' first." >&2
		exit 1
	fi

	# Every texture a material names that the glTF has no slot for: the two-
	# layer materials' second layer and blend mask (BlendMaterials), and the
	# props' decal and self-illumination mask (prop_features.gdshaderinc).
	local textures
	textures="$(grep -oE '"g_t(Layer2Color|Layer2NormalRoughness|BlendModulation|Decal|SelfIllumMask)" *: *"[^"]+"' "$world" \
		| sed -E 's/^"[^"]+" *: *"//; s/"$//; s/\.vtex$/.vtex_c/' | sort -u || true)"
	if [[ -z "$textures" ]]; then
		echo "No layered, decal or self-illuminated materials in $world; nothing to fetch."
	else
		echo "Extracting $(echo "$textures" | wc -l | tr -d ' ') second-layer, blend-mask, decal and self-illumination textures"
		echo "        -> $dest/materials"
		"$S2V_BIN" -i "$PAK_VPK" -f "$(echo "$textures" | paste -sd, -)" -o "$dest" -d \
			| grep -vE '^(Preloading|Added folder|--- \[)' || true
	fi
	restore_alpha "$world"
}

## Puts back the alpha an export dropped from the colour of an alpha-cut or
## translucent material (scripts/export_alpha.gd says which, and why): each
## such texture decompiled again on its own, which keeps its alpha, over the
## export's copy. Needs Godot to read the glTF; without it they are left as
## they are.
restore_alpha() {
	local world="$1"
	local godot
	godot="$(find_godot)"
	if [[ -z "$godot" ]]; then
		echo "No Godot binary found; colour textures exported without their alpha are left so."
		return
	fi
	local pairs
	# Godot is given the glTF under res://, which reads the same on every
	# system, and answers with the images there too.
	pairs="$("$godot" --headless --path "$PROJECT_DIR" --script scripts/export_alpha.gd -- "res://${world#"$PROJECT_DIR"/}" 2>/dev/null \
		| tr -d '\r' | sed -n 's/^ALPHA\t//p' || true)"
	if [[ -z "$pairs" ]]; then
		return
	fi
	local scratch
	scratch="$(mktemp -d)"
	echo "Restoring the alpha of $(wc -l <<<"$pairs" | tr -d ' ') colour textures the export wrote without it"
	"$S2V_BIN" -i "$PAK_VPK" -f "$(cut -f1 <<<"$pairs" | sed 's/\.vtex$/.vtex_c/' | sort -u | paste -sd, -)" -o "$scratch" -d \
		| grep -vE '^(Preloading|Added folder|--- \[|--- Dump)' || true
	local vtex image restored=0
	while IFS=$'\t' read -r vtex image; do
		if [[ -f "$scratch/${vtex%.vtex}.png" ]]; then
			cp "$scratch/${vtex%.vtex}.png" "$PROJECT_DIR/${image#res://}"
			restored=$((restored + 1))
		fi
	done <<<"$pairs"
	rm -rf "$scratch"
	echo "        $restored put back over the export's copies"
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
		echo "Run 'scripts/extract_assets.sh entities $MAP_NAME' first." >&2
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
	# Its own baked light, which its walls are drawn with as the map's are:
	# without it, the two-layer walls had nothing but the sun and were black
	# in shade. Its sun's shadow with it, where it has one. Not its light
	# probes, which light nothing that moves there.
	extract_baked_light "$vpk" "$SKYBOX_DEST" 'irradiance|directional_irradiance|direct_light_shadows' optional
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
		echo "Run 'scripts/extract_assets.sh entities $MAP_NAME' first." >&2
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

## A map's baked light from its VPK into dest, keeping the path each file
## has in the VPK: the lightmaps named in which (a pattern of their names,
## irradiance|directional_irradiance|direct_light_shadows, and the probes'
## atlases where wanted). With "optional" after them, a VPK that has none is
## passed over.
extract_baked_light() {
	local vpk="$1" dest="$2" which="$3" optional="${4:-}"
	local maps
	maps="$(list_paths "$vpk" | grep -E "/lightmaps/($which)\\.vtex_c\$" | paste -sd, - || true)"
	if [[ -z "$maps" && "$optional" == optional ]]; then
		echo "No lightmaps in $(basename "$vpk")."
		return
	fi
	require_filter "$maps" "the lightmaps in $(basename "$vpk")"
	mkdir -p "$dest"
	"$S2V_BIN" -i "$vpk" -f "$maps" -o "$dest" -d | grep -E '^--- Dump' | grep -vE '_atlas(_dlshd)?_z' || true
}

## The map's baked lighting. CS2 bakes the bounce light into an irradiance
## lightmap (8192 square, HDR, 78 MB compressed) with a companion that says
## which way the light mostly comes from. The sun's own light it computes
## live, but the static map's shadow from it is baked too, into
## direct_light_shadows: one channel per light the map bakes shadows for,
## which the light's bakedshadowindex names (the sun's is 0 on dust2), and
## that is what shadows the map (MapShadows). Source 2 Viewer writes the
## irradiance as an .exr of 300 MB, which Godot compresses back down on
## import.
## Also the light probes: one 3D atlas of ambient cubes for the whole map,
## which decompiles to one small HDR image per depth slice (720 on dust2),
## and the same lights' shadows at each probe in a second atlas (_dlshd,
## one slice for each six of those), for what the lightmaps do not cover.
## They go in a probes/ directory with a .gdignore, so Godot does not import
## eight hundred textures it will never draw; the game reads them itself.
extract_lightmaps() {
	echo "Extracting the baked lighting (a few hundred megabytes, uncompressed), the sun's shadow and the light probes"
	echo "        -> $MAP_DEST"
	extract_baked_light "$MAP_VPK" "$MAP_DEST" \
		'irradiance|directional_irradiance|direct_light_shadows|env_light_probe_volume_atlas|env_light_probe_volume_atlas_dlshd'
	# Not those already there from an extraction before: probes/ has them.
	find "$MAP_DEST" -not -path '*/probes/*' \( -name 'env_light_probe_volume_atlas_z*.exr' \
		-o -name 'env_light_probe_volume_atlas_dlshd_z*.png' -o -name 'env_light_probe_volume_atlas_dlshd_z*.exr' \) \
		| while IFS= read -r slice; do
			local probes="$(dirname "$slice")/probes"
			mkdir -p "$probes"
			touch "$probes/.gdignore"
			mv "$slice" "$probes/"
		done
	local count shadows
	count="$(find "$MAP_DEST" -path '*/probes/env_light_probe_volume_atlas_z*.exr' | wc -l | tr -d ' ')"
	shadows="$(find "$MAP_DEST" -path '*/probes/env_light_probe_volume_atlas_dlshd_z*' | wc -l | tr -d ' ')"
	echo "        light probes: $count atlas slices and $shadows shadow slices under lightmaps/probes/"
}

## The map's precomputed visibility: which of its parts can be seen from
## which, so what cannot be seen from where you stand is not drawn
## (WorldVisibility). Kept compiled, since its octree and rows are read
## straight out of the file (4 MB on dust2), and decompiled beside it for
## the counts and offsets its data block holds.
extract_visibility() {
	local visibility
	visibility="$(find_map_resource '/world_visibility\.vvis_c$' "world_visibility.vvis_c")" || exit 1
	mkdir -p "$MAP_DEST"

	echo "Extracting $visibility"
	echo "        -> $MAP_DEST"
	"$S2V_BIN" -i "$MAP_VPK" -f "$visibility" -o "$MAP_DEST" | grep -E '^--- Dump' || true
	"$S2V_BIN" -i "$MAP_VPK" -f "$visibility" -o "$MAP_DEST" -d | grep -E '^--- Dump' || true
}

## The map's colour grade: the post-processing file (.vpost) its
## post_processing_volume names (as resource_name:"lighting/...vpost" in
## a compiled lump, whose type prefix is dropped), which holds the filmic curve's numbers, the
## bloom's, and a 32-cube colour table every other layer is baked into.
## Decompiled, it is KV3 text with the table beside it as a .raw file (8-bit
## RGB); MapPostProcessing reads them, and ColourGrade draws with them. The
## entity lump says which file, so that runs first. The file is looked for
## in the map's VPK, then the game's main one. A vpost is data, not a
## shader, so CS2's newer shader format does not stop Source 2 Viewer.
extract_postprocessing() {
	local entities
	entities="$(find "$MAP_DEST" -name 'default_ents.vents' 2>/dev/null | head -n 1)"
	if [[ -z "$entities" ]]; then
		echo "No entity lump under $MAP_DEST to read the post-processing file from." >&2
		echo "Run 'scripts/extract_assets.sh entities $MAP_NAME' first." >&2
		exit 1
	fi
	local files
	files="$(tr -d '\r' < "$entities" | grep -E '^[[:space:]]*postprocessing ' \
		| sed -E 's/^[[:space:]]*postprocessing +//; s/^[a-z_]+://; s/"//g; s/[[:space:]]+$//; s/(\.vpost)(_c)?$/\1_c/' \
		| grep -E '\.vpost_c$' | sort -u || true)"
	if [[ -z "$files" ]]; then
		echo "No post_processing_volume in $entities names a file; the map is graded with the defaults."
		return
	fi
	mkdir -p "$MAP_DEST"
	local listing file vpk
	listing="$(list_paths "$MAP_VPK")"
	while IFS= read -r file; do
		vpk="$PAK_VPK"
		if grep -qixF "$file" <<<"$listing"; then
			vpk="$MAP_VPK"
		fi
		echo "Extracting $file from $(basename "$vpk")"
		echo "        -> $MAP_DEST"
		"$S2V_BIN" -i "$vpk" -f "$file" -o "$MAP_DEST" -d | grep -E '^--- Dump' || true
		if [[ ! -f "$MAP_DEST/${file%_c}" ]]; then
			echo "$file did not come out of $(basename "$vpk"); the map is graded with the defaults." >&2
		fi
	done <<<"$files"
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
	extract_surfaces
	echo
	extract_layers
	echo
	extract_sky
	echo
	extract_skybox
	echo
	extract_lightmaps
	echo
	extract_visibility
	echo
	extract_postprocessing
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
	extract_weapon_physics
	extract_weapon_animations
}

## The equipment's models, then its animations, first and third person, and
## skeletons, and the first-person clips' lengths and events (and the bomb's
## plant and the defuse's, third person), as the guns' are; the weapon tables
## are rewritten after, with reference/weapons/equipment.md. Its sounds come
## with the sounds step.
extract_equipment() {
	require_file "$PAK_VPK"
	local listing
	if ! listing="$(list_paths "$PAK_VPK")"; then
		echo "Source2Viewer-CLI failed while listing $PAK_VPK." >&2
		exit 1
	fi
	local models
	models="$(grep -iE "^weapons/models/($EQUIPMENT_MODELS)[^ ]*\.vmdl_c$" <<<"$listing" | paste -sd, - || true)"
	require_filter "$models" "the equipment models"
	local dest="$OUT_DIR/weapons"
	mkdir -p "$dest"
	echo "Extracting $(tr ',' '\n' <<<"$models" | wc -l | tr -d ' ') equipment models"
	echo "        -> $dest"
	s2v_batched "$models" -o "$dest" -d --gltf_export_format gltf --gltf_export_materials \
		--gltf_export_animations --gltf_textures_adapt \
		| grep -vE '^(Preloading|Added folder|--- )' || true

	local clips
	clips="$(grep -E "^animation/(anims/viewmodel/($EQUIPMENT_FIRST_PERSON)/|anims/world/($EQUIPMENT_THIRD_PERSON)/|skeletons/weapons/($EQUIPMENT_SKELETONS)\.vnmskel_c$)" <<<"$listing" \
		| paste -sd, - || true)"
	require_filter "$clips" "the equipment animations"
	echo
	echo "Extracting $(tr ',' '\n' <<<"$clips" | wc -l | tr -d ' ') equipment animations and skeletons, first and third person"
	echo "        -> $CHARACTERS_DEST/animation"
	mkdir -p "$CHARACTERS_DEST"
	s2v_batched "$clips" -o "$CHARACTERS_DEST" -d --gltf_export_format gltf \
		| grep -vE '^(Preloading|Added folder|--- )' || true

	local clip_data="$CHARACTERS_DEST/animation/anims/viewmodel/equipment_clip_data.txt"
	echo
	echo "Reading the equipment clips' lengths and events"
	echo "        -> $clip_data"
	"$S2V_BIN" -i "$PAK_VPK" \
		-f "animation/anims/viewmodel/equipment/,animation/anims/viewmodel/grenade/,animation/anims/viewmodel/knife/_default_knife/,animation/anims/viewmodel/knife/knife_default_t/,animation/anims/viewmodel/pistol/pistol_taser/,animation/anims/world/equipment/c4/,animation/anims/world/shared/defuse/" \
		-e vnmclip_c -b DATA > "$clip_data" 2>/dev/null || true

	extract_weapon_physics
	write_weapon_tables
}

## What the HUD draws that comes from the game: the sniper scope's overlay,
## which the game composes in code from three images (the black mask with its
## soft round opening, the lens's tint and dirt, and the soft line the cross
## is drawn with), and the equipment icons, one SVG per weapon by its class
## less "weapon_" (with the silencers-off variants), armour, the kit, the
## grenades, the knife and the bomb, for the ammo display, the kill feed and
## the buy menu. With them the rest of the HUD's images (panorama/images/hud
## and its teamcounter/: the armour and helmet, each gun's reserve magazine,
## the kill marks, the team counter's bot portrait and skull; not yet the
## radar's, the kill feed's or the death panel's), the few UI icons the HUD
## draws (HUD_UI_ICONS), the masks and the dot pattern its dark panels are
## cut and textured with, the agent's poses and CS2's word on each item for
## the buy menu, and CS2's font, Stratum2. The font is not in the
## VPK: it is loose in game/csgo/panorama/fonts as one stratum2.uifont, which
## Source2Viewer-CLI unpacks into the family's .otf files. It writes them
## beside its input whatever -o says, so it is given a copy here, never the
## game's own. src/ui/hud_style.gd reads it all from assets/hud/ and draws its
## own stand-ins where something is not there.
HUD_UI_ICONS="ct_logo_1c t_logo_1c buyzone elimination kill defuser_white alert"
HUD_MASKS="score-time-mask.vsvg_c playercount-mask.vsvg_c top-bottom-fade-4_png.vtex_c"
extract_hud() {
	require_file "$PAK_VPK"
	local uifont="$CSGO_DIR/panorama/fonts/stratum2.uifont"
	require_file "$uifont"
	local dest="$OUT_DIR/hud"
	mkdir -p "$dest"
	echo "Extracting the scope overlay, the HUD's images, icons and masks, and its font"
	echo "        -> $dest"
	local filter
	filter="$("$S2V_BIN" -i "$PAK_VPK" -f "panorama/images/hud/" -l \
		| tr -d '\r' | sed -E 's/ CRC:[0-9a-fA-F]+ size:[0-9]+$//' \
		| grep -E '^panorama/images/hud/([^/]+|scope/.+|teamcounter/.+)$' | paste -sd, -)"
	require_filter "$filter" "the HUD's images"
	filter+=",panorama/images/icons/equipment/,panorama/images/icons/person.vsvg_c"
	filter+=",panorama/images/backgrounds/bluedots_large_png.vtex_c"
	local name
	for name in $HUD_UI_ICONS; do
		filter+=",panorama/images/icons/ui/$name.vsvg_c"
	done
	for name in $HUD_MASKS; do
		filter+=",panorama/images/masks/$name"
	done
	s2v_batched "$filter" -o "$dest" -d | grep -vE '^(Preloading|Added folder|--- )' || true
	mkdir -p "$dest/fonts"
	cp "$uifont" "$dest/fonts/"
	(cd "$dest/fonts" && "$S2V_BIN" -i stratum2.uifont -o . -d > /dev/null)
	rm -f "$dest/fonts/stratum2.uifont"
	# The agent's poses beside the buy menu, one for each gun and side and
	# shared ones for the grenades, armour, kit, knife and bomb
	# (animation/anims/ui_anims/buy_menu), and the breath CS2 adds over them
	# (additive_anims/t/t_idle_layer01), exported as the other clips are,
	# into the characters' animations.
	local poses
	poses="$("$S2V_BIN" -i "$PAK_VPK" -f "animation/anims/ui_anims/" -l \
		| tr -d '\r' | sed -E 's/ CRC:[0-9a-fA-F]+ size:[0-9]+$//' \
		| grep -E '^animation/anims/ui_anims/(buy_menu/.*|additive_anims/t/t_idle_layer01)\.vnmclip_c$' \
		| grep -v 'vnmclip+' | paste -sd, -)"
	require_filter "$poses" "the buy menu's poses"
	s2v_batched "$poses" -o "$CHARACTERS_DEST" -d --gltf_export_format gltf \
		| grep -vE '^(Preloading|Added folder|--- )' || true
	# CS2's word on each item, for the buy menu's panel (its English strings'
	# csgo_item_usage_desc_*): Valve's text, so kept here with the rest.
	local strings="$dest/resource/.english"
	mkdir -p "$strings"
	"$S2V_BIN" -i "$PAK_VPK" -f "resource/csgo_english.txt" -o "$strings" > /dev/null
	grep -E '"csgo_item_usage_desc_[a-z0-9_]+"' "$strings/resource/csgo_english.txt" > "$dest/resource/item_usage.txt" || true
	rm -rf "$strings"
	echo "        $(find "$dest/" -name '*.svg' | wc -l | tr -d ' ') icons and masks, $(find "$dest/" -name '*.png' | wc -l | tr -d ' ') images, $(find "$dest/fonts" -name 'stratum2*' ! -name '*.import' | wc -l | tr -d ' ') font files, $(wc -l < "$dest/resource/item_usage.txt" | tr -d ' ') item notes, $(find "$CHARACTERS_DEST/animation/anims/ui_anims/buy_menu" -name '*.gltf' | wc -l | tr -d ' ') poses"
}

## The textures the guns' tracers and muzzle flashes draw with. CS2's particle
## systems (.vpcf) do not run in Godot; src/effects/ rebuilds them from their
## numbers (reference/weapons/effects.md), and draws them with these. The
## flames, steam and smoke are sprite sheets, which Source 2 Viewer writes as
## one trimmed image a frame; effect_textures.gd puts every frame back where
## it was on its sheet, from the rectangles the texture's data block gives
## (-b DATA), so each sheet is one texture again.
EFFECT_TEXTURES="materials/effects/spark.vtex_c,materials/particle/sparks/sparks.vtex_c,materials/particle/effects/bullet_tracer_seq.vtex_c,materials/particle/effects/bullet_tracer_tintable.vtex_c,materials/particle/fire_gas/fire_gas_batch_b_top.vtex_c,materials/particle/fire_small_sim/fire_small_sim_b.vtex_c,materials/particle/simulated/steam/wispy_steam_burst_b.vtex_c,materials/particle/simulated/steam/wispy_steam_set.vtex_c,materials/particle/smoke/smokeburst/smokeloop_i_0_sc_hardedge.vtex_c,materials/particle/smoke/smokeburst/smokeloop_i_0_sc.vtex_c,materials/particle/particle_glow_04.vtex_c"

extract_effects() {
	require_file "$PAK_VPK"
	local dest="$OUT_DIR/effects"
	local raw="$dest/raw"
	mkdir -p "$raw"
	# The frames as Source 2 Viewer writes them are only read to be put back
	# together, not imported.
	touch "$raw/.gdignore"
	echo "Extracting the tracers' and the muzzle flashes' textures"
	echo "        -> $dest"
	"$S2V_BIN" -i "$PAK_VPK" -f "$EFFECT_TEXTURES" -o "$raw" -d \
		| grep -vE '^(Preloading|Added folder|--- )' || true
	"$S2V_BIN" -i "$PAK_VPK" -f "$EFFECT_TEXTURES" -b DATA > "$raw/textures_data.txt" 2>/dev/null || true
	local godot
	godot="$(find_godot)"
	if [[ -z "$godot" ]]; then
		echo "No Godot binary found; the sprite sheets were not put back together."
		return
	fi
	"$godot" --headless --path "$PROJECT_DIR" --script scripts/effect_textures.gd 2>&1 \
		| grep -E '^(effect textures|  )' || true
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

## Every world model's physics block (PHYS), as text: the bone its hull is
## bound to and that bone's bind pose, the mass, the damping and the
## surface, for reference/weapons/physics.csv (ItemPhysics; the hull itself
## is the *_physics.gltf the weapons and equipment steps write beside each
## model). One pass over weapons/models/, a few seconds. Each block ends in
## the cloth data (m_pFeModel on, about 36 MB over every model), which
## nothing reads, so only what comes before it is kept.
extract_weapon_physics() {
	require_file "$PAK_VPK"
	local dest="$OUT_DIR/weapons/weapons/models"
	mkdir -p "$dest"
	echo "Reading the items' physics blocks"
	echo "        -> $dest/physics_data.txt"
	"$S2V_BIN" -i "$PAK_VPK" -f "weapons/models/" -e vmdl_c -b PHYS 2>/dev/null \
		| awk '/^\[[0-9]+\/[0-9]+\] /{keep=1} /^[[:space:]]*m_pFeModel/{keep=0} keep' \
		> "$dest/physics_data.txt" || true
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
	clips="$(grep -E "^animation/(anims/viewmodel/(rifle/(_default_rifle|rifle_[a-z0-9]+)|pistol/(_default_pistol|pistol_[a-z0-9]+))/|anims/world/(rifle/rifle_[a-z0-9_]+|pistol/pistol_[a-z0-9_]+)/|anims/world/pistol/_default_pistol/(idle|run|walk|crouch|inair|jump|shoot)_[a-z_]*\.vnmclip_c$|skeletons/weapons/($GUN_SKELETONS)\.vnmskel_c$)" <<<"$listing" \
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

## Writes the tables in reference/weapons/ (the guns' files, sounds, timings
## and tuning, and the equipment's) from what was extracted, so the code that
## picks a weapon's files can be written without them
## (scripts/weapon_tables.gd).
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
## switch), and the equipment's (the bomb's, the grenades', the knives' and
## the Zeus's); footsteps and landings by the surface types the map's hull
## names; and what the shooter hears on a hit, the files CS2's attacker
## feedback events name (game_sounds_player.vsndevts: kevlar_01 to _08, the
## helmet's headshot_armor_e1 and _flesh, headshot_noarmor, and the body's
## mud_impact_bullet; not the older kevlar1, headshot_armor_01 or
## bodyshot_kill_01, which no event plays), what the one hit and those near
## hear (player_damagebody_04 to _08), and the death groan (death1 to 6). CS2 keeps sounds as one file
## each (.vsnd_c), a few variants to a set, which the decompile writes out as
## the audio they hold. The sound event definitions that pair them with
## volumes and distances are not fetched; the numbers are set by ear.
SOUND_FILTER="^sounds/(weapons/($GUN_SOUND_DIRS|$EQUIPMENT_SOUND_DIRS)/[a-z0-9_-]+|weapons/[a-z0-9_]+|player/footsteps/(concrete_ct|dirt|sand|wood|metal_solid|metal_vent|metal_chainlink|metal_grate|tile|gravel|grass|carpet|glass|rubber|plastic_barrel|mud)_[0-9]+|player/footsteps/land_(concrete|dirt|sand|metal_solid|metal_vent|metal_grate|tile|gravel|grass|carpet|glass|rubber|mud|auto)(_[0-9]+)?|player/(kevlar_0[1-8]|headshot_armor_e1|headshot_armor_flesh|headshot_noarmor_0[1-5]|player_damagebody_0[4-8]|death[1-6])|physics/(concrete/concrete_impact_bullet[0-9]|surfaces/(sand|dirt|tile|default|carpet|grass|mud)_impact_bullet[0-9_]*|metal/metal_solid_impact_bullet[0-9]|wood/wood_solid_impact_bullet[0-9]))\.vsnd_c$"

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

	extract_character_animations "$listing"

	echo
	# A model whose materials came through without their descriptions is
	# still worth importing.
	extract_character_masks || true
}

## The characters' clips on their own: the rifle set, the shared deaths and
## jump additives, and the skeletons (extract_characters runs it after the
## models). Clips carry no materials and need none of CS2's shaders, so this
## step can run while the models cannot be re-exported whole (CS2's VCS 72
## shaders, 2026-09-23). listing is the archive's, if already read.
extract_character_animations() {
	require_file "$PAK_VPK"
	mkdir -p "$CHARACTERS_DEST"
	local listing="${1:-}"
	if [[ -z "$listing" ]] && ! listing="$(list_paths "$PAK_VPK")"; then
		echo "Source2Viewer-CLI failed while listing $PAK_VPK." >&2
		exit 1
	fi
	local clips
	# First person: the AK's clips and the shared rifle set, which is the
	# M4A1-S's. Third person: the shared set's locomotion (idle, walk, run,
	# crouch, in the eight directions, plus in-air, the jump's take-off in
	# each direction and shoot), each weapon's own draw, reload and shoot,
	# the shared deaths by where the last round landed, and the shared jump
	# additives, CS2's BodyAdditives layer. (The flinches beside them are additive layers, not
	# poses, and wait for an animation tree to add them.)
	clips="$(grep -E '^animation/(anims/viewmodel/rifle/(_default_rifle|rifle_ak)/|anims/world/rifle/(_default_rifle/(idle|run|walk|crouch|inair|jump|shoot)_[a-z_]*|rifle_ak/|rifle_m4a1_silencer/)|anims/world/shared/(death_(chest|gut|rknee|rshoulder)|jump_additive_)[a-z_]*\.vnmclip_c$|skeletons/characters/(viewmodel|worldmodel)\.vnmskel_c$|skeletons/weapons/(ak47|m4a1)[a-z_]*\.vnmskel_c$)' <<<"$listing" \
		| paste -sd, - || true)"
	require_filter "$clips" "the animations"
	echo
	echo "Extracting $(tr ',' '\n' <<<"$clips" | wc -l | tr -d ' ') rifle animations and skeletons, first and third person"
	echo "        -> $CHARACTERS_DEST/animation"
	"$S2V_BIN" -i "$PAK_VPK" -f "$clips" -o "$CHARACTERS_DEST" -d --gltf_export_format gltf \
		| grep -vE '^(Preloading|Added folder|--- )' || true
}

## The player models' cloth masks: the blue channel of each agent material's
## metalness texture (g_tMetalness), which says where CS2's character shader
## shades the material as cloth, with a sheen rather than a highlight
## (src/player/character.gdshader). The export reads only that texture's
## green, for the metalness, so the textures are read off the exported
## glTFs' material descriptions and decompiled on their own, as the map's
## layers are, landing under materials/ by the path the material names them
## by. No model is exported again, so this needs none of CS2's shaders; the
## prepare step drops the textures' alpha before the import
## (src/player/export_character_masks.gd).
extract_character_masks() {
	require_file "$PAK_VPK"
	local masks
	# The metalness textures carry the cloth mask; the eye textures are the
	# eyes' colour (its alpha the iris) and where on the model they are.
	masks="$(find "$CHARACTERS_DEST/agents" -name '*.gltf' \
		-exec grep -ohE '"(g_tMetalness|g_tEyeAlbedo1|g_tEyeMask1)" *: *"[^"]+"' {} + 2>/dev/null \
		| sed -E 's/^"[^"]+" *: *"//; s/"$//; s/\.vtex$/.vtex_c/' | sort -u || true)"
	if [[ -z "$masks" ]]; then
		echo "No player model under $CHARACTERS_DEST/agents names a metalness texture." >&2
		echo "Run 'scripts/extract_assets.sh characters' first." >&2
		return 1
	fi
	echo "Extracting $(wc -l <<<"$masks" | tr -d ' ') textures, for the player models' cloth masks and eyes"
	echo "        -> $CHARACTERS_DEST/materials"
	s2v_batched "$(paste -sd, - <<<"$masks")" -o "$CHARACTERS_DEST" -d \
		| grep -vE '^(Preloading|Added folder|--- \[)' || true
}

## The animation graphs: CS2's AnimGraph 2 (.vnmgraph_c, all of
## animation/graphs/), the logic that picks and blends the clips from what
## the game feeds it each frame (speed and direction, crouch, aim, the
## weapon's action, the flinches). They are data, which Source 2 Viewer's -b
## DATA prints as text: all 232, 15 MB of it, in seconds.
## scripts/animgraph_tables.gd writes reference/animgraph/ from it, and
## reference/animgraph2.md says what is in them.
extract_animgraphs() {
	require_file "$PAK_VPK"
	local dest="$CHARACTERS_DEST/animation/graphs"
	mkdir -p "$dest"
	echo "Reading the animation graphs"
	echo "        -> $dest/graph_data.txt"
	"$S2V_BIN" -i "$PAK_VPK" -f "animation/graphs/" -e vnmgraph_c -b DATA > "$dest/graph_data.txt" 2>/dev/null || true
	echo "        $(grep -c '^\[[0-9]*/[0-9]*\] ' "$dest/graph_data.txt" || true) graphs"
	write_animgraph_tables
}

write_animgraph_tables() {
	local godot
	godot="$(find_godot)"
	if [[ -z "$godot" ]]; then
		echo "No Godot binary found; the tables in reference/animgraph/ were not rewritten."
		return
	fi
	echo
	local version
	version="$(sed -n 's/^PatchVersion=//p' "$CS2_DIR/game/csgo/steam.inf" 2>/dev/null | tr -d '\r' || true)"
	CS2_VERSION="$version" "$godot" --headless --path "$PROJECT_DIR" --script scripts/animgraph_tables.gd 2>&1 \
		| grep -E '^(animation graph tables|  )' || true
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
	if [[ "$MAP_NAME" != de_dust2 ]]; then
		echo "To play $MAP_NAME: set Map Name on maps/play/play.tscn, or run"
		echo "  godot --path . maps/play/play.tscn -- --map $MAP_NAME"
	fi
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
	surfaces) extract_surfaces ;;
	layers) extract_layers; finish ;;
	sky) extract_sky; finish ;;
	skybox) extract_skybox; finish ;;
	lightmaps) extract_lightmaps; finish ;;
	visibility) extract_visibility ;;
	postprocessing) extract_postprocessing ;;
	characters) extract_characters; finish ;;
	character-masks) extract_character_masks; finish ;;
	character-animations) extract_character_animations; finish ;;
	animgraphs) extract_animgraphs ;;
	weapons) extract_weapons; finish ;;
	weapon-animations) extract_weapon_animations; finish ;;
	weapon-data) extract_weapon_data; write_weapon_tables ;;
	weapon-physics) extract_weapon_physics; write_weapon_tables ;;
	equipment) extract_equipment; finish ;;
	hud) extract_hud; finish ;;
	effects) extract_effects; finish ;;
	sounds) extract_sounds; finish ;;
	all) extract_map; echo; extract_weapons; echo; extract_equipment; echo; extract_hud; echo; extract_effects; echo; extract_characters; echo; extract_animgraphs; echo; extract_sounds; finish ;;
esac
