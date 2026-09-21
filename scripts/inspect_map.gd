extends SceneTree

## Prints what the map import found, without opening the editor or pressing
## play.
##
##   godot --headless --path . --script scripts/inspect_map.gd
##
## (scripts/inspect_assets.sh runs this for you.)
##
## The output is the thing to send over when asking for help with an import:
## it says how many meshes came through, how big the map is, and every material
## name, which is what decides how collision gets configured.

const MAP_DIR := "res://assets/maps/de_dust2"
const COLLISION_DIR := "res://assets/maps/de_dust2_physics"
const ENTITIES_FILE := "entities/default_ents.vents"

var _done: bool = false


func _process(_delta: float) -> bool:
	# One frame of grace so the tree is ready to parent into.
	if not _done:
		_done = true
		return false

	var map_file := MapImporter.find_map_file(MAP_DIR)
	if map_file.is_empty():
		print("No glTF found under %s" % MAP_DIR)
		print("")
		print("Either the extraction has not been run, or it wrote somewhere else.")
		print("Run 'scripts/extract_assets.sh map' on a machine with CS2 installed,")
		print("then check that assets/maps/de_dust2 has files in it.")
		quit(1)
		return true

	print("Found: %s" % map_file)
	print("")

	# Set up the way maps/de_dust2/de_dust2.gd sets it up, so that what is
	# reported here is what the game gets.
	var importer := MapImporter.new()
	importer.source_path = map_file
	importer.collision_path = MapImporter.find_collision_file(COLLISION_DIR)
	importer.scale_factor = MapImporter.SOURCE2_VIEWER_SCALE
	importer.report = true
	root.add_child(importer)

	var entities_path := ProjectSettings.globalize_path(
		map_file.get_base_dir().path_join(ENTITIES_FILE)
	)
	var spawns := SourceEntities.player_spawns(SourceEntities.parse(entities_path))
	print("")
	print("--- spawn points: %d T, %d CT" % [spawns["T"].size(), spawns["CT"].size()])
	if spawns["T"].is_empty() and spawns["CT"].is_empty():
		print("    none, so the player is dropped in from above the middle of the map.")
		print("    Run 'scripts/extract_assets.sh entities' to get them.")
	if importer.collision_path.is_empty():
		print("")
		print("No collision hull under %s, so collision is the visible world:" % COLLISION_DIR)
		print("ten times the triangles and no player clips.")
		print("Run 'scripts/extract_assets.sh physics' to get it.")

	var failed: bool = importer.stats.has("error")
	importer.free()
	quit(1 if failed else 0)
	return true
