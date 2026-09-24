class_name MapPaths
extends RefCounted

## Where a map's extracted files are, from nothing but its name.
##
## scripts/extract_assets.sh writes each map it takes (map <name>, de_dust2
## when none is given) into assets/maps/<name>, with its collision hull in
## <name>_physics and its 3D skybox in <name>_skybox beside it; the files the
## game reads by name keep the path they have in the map's VPK. This derives
## the same paths, so a map needs no code of its own to be loaded
## (MapLoader). `scripts/extract_assets.sh paths <name>` prints the script's
## side, and tests/run_map_mode_checks.gd holds the two together.

const ROOT := "res://assets/maps"

## The entity lump, relative to the directory the world glTF is in.
const ENTITIES_FILE := "entities/default_ents.vents"

## The map's name as CS2 has it: de_dust2, de_mirage.
var name: String = ""
## Where the world export is, with everything else of the map's own inside.
var map_dir: String = ""
## The collision hull's export, a sibling so the world glTF is found alone.
var collision_dir: String = ""
## The 3D skybox's export: a small map of its own.
var skybox_dir: String = ""
## The nav mesh the game's bots walk.
var nav_file: String = ""
## The directory the brush entities' models are in (BrushVolume finds each
## by the path the entity lump gives, under map_dir).
var entity_models_dir: String = ""
## The radar's image and the text that says where it lies over the map.
var radar_image: String = ""
var overview_file: String = ""
## The game's bomb damage baked over the map, as KV3 text.
var baked_bomb_damage: String = ""


static func of(map_name: String) -> MapPaths:
	var paths := MapPaths.new()
	paths.name = map_name
	paths.map_dir = ROOT.path_join(map_name)
	paths.collision_dir = ROOT.path_join(map_name + "_physics")
	paths.skybox_dir = ROOT.path_join(map_name + "_skybox")
	paths.nav_file = paths.map_dir.path_join("maps/%s.nav" % map_name)
	paths.entity_models_dir = paths.map_dir.path_join("maps/%s/entities/" % map_name)
	paths.radar_image = paths.map_dir.path_join("panorama/images/overheadmaps/%s_radar_psd.png" % map_name)
	paths.overview_file = paths.map_dir.path_join("resource/overviews/%s.txt" % map_name)
	paths.baked_bomb_damage = paths.map_dir.path_join("maps/%s/baked_bomb_damage.vdata" % map_name)
	return paths


## Whether a name can be a map's: CS2's are lower case letters, digits and
## underscores, and the extraction script takes nothing else.
static func is_valid_name(map_name: String) -> bool:
	return RegEx.create_from_string("^[a-z0-9_]+$").search(map_name) != null


## The extraction step that makes something of this map's, as it is typed:
## "scripts/extract_assets.sh nav de_mirage".
func extract_command(step: String) -> String:
	return "scripts/extract_assets.sh %s %s" % [step, name]
